-- The database calls the Edge Functions make (service role only): the caller's plan, quota metering, entitlement
-- writes, Squad and deletion. Each one is a single transaction, so concurrent requests can't overspend a quota or
-- overfill a Squad. Every function here is revoked from public, anon and authenticated at the end of the file.

-- ---------------------------------------------------------------------------------------------------------------
-- Plans

create or replace function public.cramless_plan_rank(p_plan text)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case p_plan when 'squad' then 3 when 'pro' then 2 when 'pass' then 1 else 0 end
$$;

-- An entitlement row that is active at p_now.
create or replace function public.cramless_is_active(p_expires timestamptz, p_revoked timestamptz, p_now timestamptz)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_revoked is null and (p_expires is null or p_expires > p_now)
$$;

-- The plan a person has right now: their best active entitlement, or 'squad' through a Squad whose owner's Squad
-- subscription is active. No row means free.
create or replace function public.cramless_plan_of(p_user uuid, p_now timestamptz)
returns table (plan text, expires_at timestamptz, via_squad boolean)
language sql
stable
set search_path = ''
as $$
  with candidates as (
    select e.plan, e.expires_at, false as via_squad
    from public.entitlements e
    where e.user_id = p_user and public.cramless_is_active(e.expires_at, e.revoked_at, p_now)
    union all
    select 'squad', e.expires_at, true
    from public.squad_members m
    join public.squads s on s.id = m.squad_id
    join public.entitlements e on e.user_id = s.owner_id and e.plan = 'squad'
    where m.user_id = p_user and public.cramless_is_active(e.expires_at, e.revoked_at, p_now)
  )
  select c.plan, c.expires_at, c.via_squad
  from candidates c
  order by public.cramless_plan_rank(c.plan) desc, c.expires_at desc nulls first
  limit 1
$$;

-- Everything a relay request needs to know about its caller, in one round trip.
create or replace function public.cramless_context(p_user uuid, p_now timestamptz)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_profile public.profiles;
  v_plan text;
  v_expires timestamptz;
begin
  select * into v_profile from public.profiles where id = p_user;
  if not found then
    return jsonb_build_object('exists', false);
  end if;
  select p.plan, p.expires_at into v_plan, v_expires from public.cramless_plan_of(p_user, p_now) p;
  return jsonb_build_object(
    'exists', true,
    'plan', coalesce(v_plan, 'free'),
    'expires_at', v_expires,
    'timezone', v_profile.timezone,
    'display_name', v_profile.display_name
  );
end
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Quotas

-- Adds p_amount to a meter unless that would pass p_limit (null: no limit). Returns {allowed, used}.
create or replace function public.cramless_consume(p_user uuid, p_meter text, p_period date, p_amount integer,
                                                   p_limit integer)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_used integer;
begin
  insert into public.usage_counters (user_id, meter, period_start, used)
  values (p_user, p_meter, p_period, 0)
  on conflict (user_id, meter, period_start) do nothing;

  select used into v_used
  from public.usage_counters
  where user_id = p_user and meter = p_meter and period_start = p_period
  for update;

  if p_limit is not null and v_used + p_amount > p_limit then
    return jsonb_build_object('allowed', false, 'used', v_used);
  end if;

  update public.usage_counters
  set used = used + p_amount, updated_at = now()
  where user_id = p_user and meter = p_meter and period_start = p_period;
  return jsonb_build_object('allowed', true, 'used', v_used + p_amount);
end
$$;

-- Gives back what a failed request consumed.
create or replace function public.cramless_refund(p_user uuid, p_meter text, p_period date, p_amount integer)
returns void
language sql
volatile
set search_path = ''
as $$
  update public.usage_counters
  set used = greatest(used - p_amount, 0), updated_at = now()
  where user_id = p_user and meter = p_meter and period_start = p_period
$$;

-- One AI scan is a capture session: the page transcriptions (kind 'transcribe', one page each) and the generate
-- call that closes it, within p_window_minutes and p_max_pages pages. A request that fits the open scan doesn't
-- count again; anything else opens a new scan, which costs one from the 'scans' meter.
-- Returns {allowed, used, counted}: counted is true when this request opened a new scan.
create or replace function public.cramless_consume_scan(p_user uuid, p_kind text, p_pages integer, p_period date,
                                                        p_limit integer, p_now timestamptz,
                                                        p_window_minutes integer default 30,
                                                        p_max_pages integer default 10)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_window public.scan_windows;
  v_result jsonb;
  v_used integer;
begin
  if p_kind not in ('transcribe', 'generate') then
    raise exception 'unknown scan kind %', p_kind;
  end if;

  insert into public.scan_windows (user_id) values (p_user) on conflict (user_id) do nothing;
  select * into v_window from public.scan_windows where user_id = p_user for update;

  if v_window.opened_at > p_now - make_interval(mins => p_window_minutes)
     and not v_window.generated
     and v_window.period_start = p_period
     and (p_kind = 'generate' or v_window.pages + p_pages <= p_max_pages) then
    update public.scan_windows
    set pages = pages + case when p_kind = 'transcribe' then p_pages else 0 end,
        generated = (p_kind = 'generate')
    where user_id = p_user;
    select coalesce(max(used), 0) into v_used
    from public.usage_counters
    where user_id = p_user and meter = 'scans' and period_start = p_period;
    return jsonb_build_object('allowed', true, 'used', v_used, 'counted', false);
  end if;

  v_result := public.cramless_consume(p_user, 'scans', p_period, 1, p_limit);
  if (v_result ->> 'allowed')::boolean then
    update public.scan_windows
    set opened_at = p_now, period_start = p_period, pages = p_pages, generated = (p_kind = 'generate')
    where user_id = p_user;
  end if;
  return v_result || jsonb_build_object('counted', (v_result ->> 'allowed')::boolean);
end
$$;

-- Undoes cramless_consume_scan after the request failed: a counted scan is refunded and its window closed; a
-- generate that rode on an open scan reopens it, so the retry rides on it again.
create or replace function public.cramless_refund_scan(p_user uuid, p_kind text, p_pages integer, p_period date,
                                                       p_counted boolean)
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  if p_counted then
    perform public.cramless_refund(p_user, 'scans', p_period, 1);
    update public.scan_windows set opened_at = '-infinity', pages = 0, generated = true where user_id = p_user;
  elsif p_kind = 'generate' then
    update public.scan_windows set generated = false where user_id = p_user;
  else
    update public.scan_windows set pages = greatest(pages - p_pages, 0) where user_id = p_user;
  end if;
end
$$;

-- The meters' values for the given periods: p_keys is [{"meter": "scans", "period": "2026-10-19"}, …].
create or replace function public.cramless_usage(p_user uuid, p_keys jsonb)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(k.meter, coalesce(u.used, 0)), '{}'::jsonb)
  from jsonb_to_recordset(p_keys) as k (meter text, period date)
  left join public.usage_counters u
    on u.user_id = p_user and u.meter = k.meter and u.period_start = k.period
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Entitlements

-- Writes verified transactions for p_user. A row keeps the newest transaction of its original transaction (by
-- purchase date); a row another account synced before moves to p_user.
create or replace function public.cramless_save_entitlements(p_user uuid, p_rows jsonb, p_now timestamptz)
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  insert into public.entitlements as e (
    user_id, plan, product_id, original_transaction_id, transaction_id, purchase_date, expires_at, revoked_at,
    environment, updated_at
  )
  select p_user, r.plan, r.product_id, r.original_transaction_id, r.transaction_id, r.purchase_date, r.expires_at,
         r.revoked_at, r.environment, p_now
  from jsonb_to_recordset(p_rows) as r (
    plan text, product_id text, original_transaction_id text, transaction_id text, purchase_date timestamptz,
    expires_at timestamptz, revoked_at timestamptz, environment text
  )
  on conflict (environment, original_transaction_id) do update set
    user_id = excluded.user_id,
    plan = case when excluded.purchase_date >= e.purchase_date then excluded.plan else e.plan end,
    product_id = case when excluded.purchase_date >= e.purchase_date then excluded.product_id else e.product_id end,
    transaction_id = case when excluded.purchase_date >= e.purchase_date then excluded.transaction_id
                          else e.transaction_id end,
    purchase_date = greatest(e.purchase_date, excluded.purchase_date),
    expires_at = case when excluded.purchase_date >= e.purchase_date then excluded.expires_at else e.expires_at end,
    revoked_at = case when excluded.purchase_date >= e.purchase_date then excluded.revoked_at else e.revoked_at end,
    updated_at = excluded.updated_at;
end
$$;

-- An App Store Server Notification for a transaction we know: updates its row when the notification's
-- transaction is the same or newer. Unknown transactions are ignored (the app syncs them when it next runs).
-- Returns 'applied', 'stale' or 'unknown'.
create or replace function public.cramless_apply_notification(p_environment text, p_original text,
                                                              p_transaction text, p_product text, p_plan text,
                                                              p_purchase timestamptz, p_expires timestamptz,
                                                              p_revoked timestamptz, p_now timestamptz)
returns text
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_row public.entitlements;
begin
  select * into v_row from public.entitlements
  where environment = p_environment and original_transaction_id = p_original
  for update;
  if not found then
    return 'unknown';
  end if;
  if p_purchase < v_row.purchase_date then
    return 'stale';
  end if;
  update public.entitlements
  set plan = coalesce(p_plan, plan), product_id = coalesce(p_product, product_id),
      transaction_id = coalesce(p_transaction, transaction_id), purchase_date = p_purchase,
      expires_at = p_expires, revoked_at = p_revoked, updated_at = p_now
  where id = v_row.id;
  return 'applied';
end
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Squad (four seats: the owner and three members)

create or replace function public.cramless_squad_owner_active(p_owner uuid, p_now timestamptz)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (
    select 1 from public.entitlements e
    where e.user_id = p_owner and e.plan = 'squad' and public.cramless_is_active(e.expires_at, e.revoked_at, p_now)
  )
$$;

-- Creates a single-use invite code. Only someone with an active Squad subscription owns a Squad (created on the
-- first invite). Returns {ok, squad_id} or {ok: false, reason: 'not_owner' | 'full'}.
create or replace function public.cramless_squad_invite(p_owner uuid, p_code text, p_expires timestamptz,
                                                        p_now timestamptz, p_seats integer default 4)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_squad uuid;
  v_members integer;
begin
  if not public.cramless_squad_owner_active(p_owner, p_now) then
    return jsonb_build_object('ok', false, 'reason', 'not_owner');
  end if;
  insert into public.squads (owner_id) values (p_owner) on conflict (owner_id) do nothing;
  select id into v_squad from public.squads where owner_id = p_owner for update;
  select count(*) into v_members from public.squad_members where squad_id = v_squad;
  if v_members + 1 >= p_seats then
    return jsonb_build_object('ok', false, 'reason', 'full');
  end if;
  insert into public.squad_invites (code, squad_id, created_at, expires_at)
  values (p_code, v_squad, p_now, p_expires);
  return jsonb_build_object('ok', true, 'squad_id', v_squad);
end
$$;

-- Joins the Squad behind a code. Returns {ok, owner_name} or {ok: false, reason: 'not_found' | 'used' | 'expired' |
-- 'own_squad' | 'other_squad' | 'owner_lapsed' | 'full'}. Joining a Squad you're already in succeeds and leaves
-- the code unused.
create or replace function public.cramless_squad_redeem(p_user uuid, p_code text, p_now timestamptz,
                                                        p_seats integer default 4)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_invite public.squad_invites;
  v_squad public.squads;
  v_current uuid;
  v_members integer;
  v_owner_name text;
begin
  select * into v_invite from public.squad_invites where code = upper(trim(p_code)) for update;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;
  select * into v_squad from public.squads where id = v_invite.squad_id for update;
  select display_name into v_owner_name from public.profiles where id = v_squad.owner_id;
  v_owner_name := coalesce(nullif(trim(v_owner_name), ''), 'Your friend');

  select squad_id into v_current from public.squad_members where user_id = p_user;
  if v_current = v_squad.id then
    return jsonb_build_object('ok', true, 'owner_name', v_owner_name);
  end if;
  if v_invite.redeemed_at is not null then
    return jsonb_build_object('ok', false, 'reason', 'used');
  end if;
  if v_invite.expires_at <= p_now then
    return jsonb_build_object('ok', false, 'reason', 'expired');
  end if;
  if v_squad.owner_id = p_user then
    return jsonb_build_object('ok', false, 'reason', 'own_squad');
  end if;
  if v_current is not null then
    return jsonb_build_object('ok', false, 'reason', 'other_squad');
  end if;
  if not public.cramless_squad_owner_active(v_squad.owner_id, p_now) then
    return jsonb_build_object('ok', false, 'reason', 'owner_lapsed');
  end if;
  select count(*) into v_members from public.squad_members where squad_id = v_squad.id;
  if v_members + 1 >= p_seats then
    return jsonb_build_object('ok', false, 'reason', 'full');
  end if;

  insert into public.squad_members (squad_id, user_id, joined_at) values (v_squad.id, p_user, p_now);
  update public.squad_invites set redeemed_by = p_user, redeemed_at = p_now where code = v_invite.code;
  return jsonb_build_object('ok', true, 'owner_name', v_owner_name);
end
$$;

-- The caller's Squad (owned first, else joined): {ok, squad_id, owner_id, members: [{id, name, joined_at,
-- is_owner}]} with the owner first, or {ok: false, reason: 'no_squad'}.
create or replace function public.cramless_squad_members(p_user uuid)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_squad public.squads;
begin
  select * into v_squad from public.squads where owner_id = p_user;
  if not found then
    select s.* into v_squad
    from public.squad_members m join public.squads s on s.id = m.squad_id
    where m.user_id = p_user;
  end if;
  if v_squad.id is null then
    return jsonb_build_object('ok', false, 'reason', 'no_squad');
  end if;
  return jsonb_build_object(
    'ok', true,
    'squad_id', v_squad.id,
    'owner_id', v_squad.owner_id,
    'members', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', x.user_id, 'name', x.name, 'joined_at', x.joined_at, 'is_owner', x.is_owner)
             order by x.is_owner desc, x.joined_at, x.user_id), '[]'::jsonb)
      from (
        select v_squad.owner_id as user_id, coalesce(p.display_name, '') as name, v_squad.created_at as joined_at,
               true as is_owner
        from (select 1) one left join public.profiles p on p.id = v_squad.owner_id
        union all
        select m.user_id, coalesce(p.display_name, ''), m.joined_at, false
        from public.squad_members m left join public.profiles p on p.id = m.user_id
        where m.squad_id = v_squad.id
      ) x
    )
  );
end
$$;

-- The owner removes a member, or a member leaves. Returns {ok} or {ok: false, reason: 'not_allowed' | 'not_found'}.
create or replace function public.cramless_squad_remove(p_actor uuid, p_member uuid)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_squad uuid;
  v_owner uuid;
begin
  select m.squad_id, s.owner_id into v_squad, v_owner
  from public.squad_members m join public.squads s on s.id = m.squad_id
  where m.user_id = p_member;
  if v_squad is null then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;
  if p_actor <> v_owner and p_actor <> p_member then
    return jsonb_build_object('ok', false, 'reason', 'not_allowed');
  end if;
  delete from public.squad_members where squad_id = v_squad and user_id = p_member;
  return jsonb_build_object('ok', true);
end
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Deletion

-- "Delete my AI data": the request log and the open scan. Usage counters stay (they hold counts only, and keep
-- the free quotas honest).
create or replace function public.cramless_delete_ai_data(p_user uuid)
returns void
language sql
volatile
set search_path = ''
as $$
  delete from public.ai_requests where user_id = p_user;
  delete from public.scan_windows where user_id = p_user;
$$;

-- Every row the person owns, before the auth user itself is deleted (which would cascade anyway). Squads they
-- own go with their members' seats; their own seat in someone else's Squad is freed.
create or replace function public.cramless_delete_account_data(p_user uuid)
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  delete from public.squads where owner_id = p_user;
  delete from public.squad_members where user_id = p_user;
  delete from public.courses where user_id = p_user;
  delete from public.topics where user_id = p_user;
  delete from public.sources where user_id = p_user;
  delete from public.source_pages where user_id = p_user;
  delete from public.items where user_id = p_user;
  delete from public.review_logs where user_id = p_user;
  delete from public.exams where user_id = p_user;
  delete from public.study_sessions where user_id = p_user;
  delete from public.day_records where user_id = p_user;
  delete from public.confusions where user_id = p_user;
  delete from public.entitlements where user_id = p_user;
  delete from public.usage_counters where user_id = p_user;
  delete from public.scan_windows where user_id = p_user;
  delete from public.ai_requests where user_id = p_user;
  delete from public.profiles where id = p_user;
end
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Service role only.

do $$
declare
  f text;
begin
  foreach f in array array[
    'cramless_plan_rank(text)',
    'cramless_is_active(timestamptz, timestamptz, timestamptz)',
    'cramless_plan_of(uuid, timestamptz)',
    'cramless_context(uuid, timestamptz)',
    'cramless_consume(uuid, text, date, integer, integer)',
    'cramless_refund(uuid, text, date, integer)',
    'cramless_consume_scan(uuid, text, integer, date, integer, timestamptz, integer, integer)',
    'cramless_refund_scan(uuid, text, integer, date, boolean)',
    'cramless_usage(uuid, jsonb)',
    'cramless_save_entitlements(uuid, jsonb, timestamptz)',
    'cramless_apply_notification(text, text, text, text, text, timestamptz, timestamptz, timestamptz, timestamptz)',
    'cramless_squad_owner_active(uuid, timestamptz)',
    'cramless_squad_invite(uuid, text, timestamptz, timestamptz, integer)',
    'cramless_squad_redeem(uuid, text, timestamptz, integer)',
    'cramless_squad_members(uuid)',
    'cramless_squad_remove(uuid, uuid)',
    'cramless_delete_ai_data(uuid)',
    'cramless_delete_account_data(uuid)'
  ]
  loop
    execute format('revoke all on function public.%s from public, anon, authenticated', f);
    execute format('grant execute on function public.%s to service_role', f);
  end loop;
end
$$;
