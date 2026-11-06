-- The Squad's studied-today dot. Off for everyone until they switch it on (`profiles.share_squad_activity`). A row in `squad_activity` says one thing: this person finished a session on this
-- day of theirs. It holds no course, topic, answer or number, it is kept for two weeks, and it goes the moment they switch sharing off, leave the Squad or delete their account.
--
-- The table has no client grants: the `account` function reads and writes it through the functions below, and it answers only for people who opted in.

alter table public.profiles
  add column share_squad_activity boolean not null default false;

create table public.squad_activity (
  user_id uuid not null references auth.users (id) on delete cascade,
  day_key text not null check (day_key ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'),
  created_at timestamptz not null default now(),
  primary key (user_id, day_key)
);

alter table public.squad_activity enable row level security;

revoke all on public.squad_activity from anon, authenticated;
grant all on public.squad_activity to service_role;

-- Switches sharing. Off also deletes what was shared. Returns {ok} or {ok: false, reason: 'no_squad'}.
create or replace function public.cramless_squad_share(p_user uuid, p_on boolean)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
begin
  if not exists (select 1 from public.squads where owner_id = p_user)
     and not exists (select 1 from public.squad_members where user_id = p_user) then
    return jsonb_build_object('ok', false, 'reason', 'no_squad');
  end if;
  update public.profiles set share_squad_activity = p_on, updated_at = now() where id = p_user;
  if not p_on then
    delete from public.squad_activity where user_id = p_user;
  end if;
  return jsonb_build_object('ok', true);
end
$$;

-- This person finished a session on `p_day`. Nothing is kept for anyone who hasn't opted in or isn't in a Squad. Returns {recorded}.
create or replace function public.cramless_squad_studied(p_user uuid, p_day text)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
begin
  if not exists (select 1 from public.profiles where id = p_user and share_squad_activity) then
    return jsonb_build_object('recorded', false);
  end if;
  if not exists (select 1 from public.squads where owner_id = p_user)
     and not exists (select 1 from public.squad_members where user_id = p_user) then
    return jsonb_build_object('recorded', false);
  end if;
  insert into public.squad_activity (user_id, day_key) values (p_user, p_day) on conflict do nothing;
  -- Two weeks, for everyone: someone who stopped studying doesn't keep a row just because they never come back to prune it.
  delete from public.squad_activity where day_key < to_char(p_day::date - 14, 'YYYY-MM-DD');
  return jsonb_build_object('recorded', true);
end
$$;

-- The members, now with what the dot needs: each one's time zone, whether they share, and the last day they studied (only if they share).
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
               'id', x.user_id, 'name', x.name, 'joined_at', x.joined_at, 'is_owner', x.is_owner,
               'time_zone', x.time_zone, 'shares', x.shares,
               'last_day', case when x.shares then
                 (select max(a.day_key) from public.squad_activity a where a.user_id = x.user_id) end)
             order by x.is_owner desc, x.joined_at, x.user_id), '[]'::jsonb)
      from (
        select v_squad.owner_id as user_id, coalesce(p.display_name, '') as name, v_squad.created_at as joined_at,
               true as is_owner, coalesce(p.timezone, 'UTC') as time_zone, coalesce(p.share_squad_activity, false) as shares
        from (select 1) one left join public.profiles p on p.id = v_squad.owner_id
        union all
        select m.user_id, coalesce(p.display_name, ''), m.joined_at, false,
               coalesce(p.timezone, 'UTC'), coalesce(p.share_squad_activity, false)
        from public.squad_members m left join public.profiles p on p.id = m.user_id
        where m.squad_id = v_squad.id
      ) x
    )
  );
end
$$;

-- Leaving a Squad ends sharing: joining another one later never shows anything the person hasn't switched on for it.
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
  update public.profiles set share_squad_activity = false where id = p_member;
  delete from public.squad_activity where user_id = p_member;
  return jsonb_build_object('ok', true);
end
$$;

-- Deleting an account: its own activity goes, and so does the sharing of everyone on a Squad it owned, which ends with it.
create or replace function public.cramless_delete_account_data(p_user uuid)
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  update public.profiles set share_squad_activity = false
  where id in (select m.user_id from public.squad_members m join public.squads s on s.id = m.squad_id where s.owner_id = p_user);
  delete from public.squad_activity
  where user_id = p_user
     or user_id in (select m.user_id from public.squad_members m join public.squads s on s.id = m.squad_id where s.owner_id = p_user);
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

-- Service role only (replacing a function keeps its grants; the two new ones need theirs).
do $$
declare
  f text;
begin
  foreach f in array array[
    'cramless_squad_share(uuid, boolean)',
    'cramless_squad_studied(uuid, text)'
  ]
  loop
    execute format('revoke all on function public.%s from public, anon, authenticated', f);
    execute format('grant execute on function public.%s to service_role', f);
  end loop;
end
$$;
