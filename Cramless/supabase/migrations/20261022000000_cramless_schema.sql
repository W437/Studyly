-- Cramless backend schema: profiles, the synced study tables, entitlements, quotas, Squad and the AI request log.
--
-- Rules
-- - Row-level security is on for every table. Study data belongs to `auth.uid()`; the Edge Functions use the
--   service role, which bypasses RLS, and are the only writers of entitlements, usage, Squad and the AI log.
-- - Synced rows carry the client's `updated_at` (last writer wins: an older write never replaces a newer row) and
--   a server-stamped `synced_at`, the pull cursor. Deletes are tombstones (`deleted_at`), never row deletes.
-- - No foreign keys between synced tables: rows arrive in any order from several devices. Every row references
--   auth.users with ON DELETE CASCADE, so deleting the auth user removes everything.
-- - review_logs is insert-only for clients: no UPDATE or DELETE grant, no policy for either.
-- - ai_requests never holds content: route, model, tokens, cost, status and latency only.

-- ---------------------------------------------------------------------------------------------------------------
-- Helpers

-- BEFORE INSERT OR UPDATE on synced tables: stamps synced_at with the server's clock and keeps the newer row when
-- two devices write the same id (an update whose updated_at is older than the stored one changes nothing).
create or replace function public.cramless_sync_stamp()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    if new.user_id is distinct from old.user_id then
      raise exception 'user_id cannot change' using errcode = '42501';
    end if;
    if new.updated_at is not null and old.updated_at is not null and new.updated_at < old.updated_at then
      return old;
    end if;
  end if;
  new.synced_at := clock_timestamp();
  return new;
end
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Profiles: one per auth user, created by a trigger. The display name is what Squad members see; the time zone
-- decides when daily and weekly quotas reset.

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default '' check (char_length(display_name) <= 80),
  timezone text not null default 'UTC' check (char_length(timezone) between 1 and 64),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "profiles: owner reads" on public.profiles
  for select to authenticated using (id = (select auth.uid()));
create policy "profiles: owner inserts" on public.profiles
  for insert to authenticated with check (id = (select auth.uid()));
create policy "profiles: owner updates" on public.profiles
  for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));

create or replace function public.cramless_handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id) values (new.id) on conflict (id) do nothing;
  return new;
end
$$;

create trigger cramless_on_auth_user_created
  after insert on auth.users
  for each row execute function public.cramless_handle_new_user();

-- ---------------------------------------------------------------------------------------------------------------
-- Synced study tables. Column names are the Swift model fields in snake_case; `…Data` blobs are jsonb.

create table public.courses (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null,
  color text not null default 'sky',
  symbol text not null default 'book.closed',
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  synced_at timestamptz not null default clock_timestamp()
);

create table public.topics (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  course_id uuid,
  name text not null,
  summary text not null default '',
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  synced_at timestamptz not null default clock_timestamp()
);

create table public.sources (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  course_id uuid,
  kind text not null,
  status text not null,
  title text not null default '',
  -- The original file's name on the device; the uploaded copy, when there is one, is storage_path in the
  -- private `sources` bucket (`<user id>/<source id>/<file>`).
  file_name text,
  storage_path text,
  duration double precision not null default 0,
  segments jsonb,
  flags jsonb,
  notes jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  synced_at timestamptz not null default clock_timestamp()
);

create table public.source_pages (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  source_id uuid not null,
  page_index integer not null,
  label text not null default '',
  text text not null default '',
  lines jsonb,
  -- How the text was read and how far to trust it (SourcePage.readData, a PageRead).
  read jsonb,
  -- The page image in the `sources` bucket, when it was uploaded.
  image_path text,
  width double precision not null default 0,
  height double precision not null default 0,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  synced_at timestamptz not null default clock_timestamp()
);

create table public.items (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  course_id uuid,
  topic_id uuid,
  kind text not null,
  status text not null,
  origin text not null,
  prompt text not null,
  answer text not null,
  explanation text not null default '',
  key_ideas jsonb,
  choices jsonb,
  cloze jsonb,
  diagram jsonb,
  source_ref jsonb,
  checked_at timestamptz,
  difficulty_hint double precision not null default 0.5,
  reported boolean not null default false,
  -- Memory (FSRS), flattened as on the device.
  state integer not null default 0,
  stability double precision not null default 0,
  difficulty double precision not null default 0,
  due timestamptz,
  last_review timestamptz,
  reps integer not null default 0,
  lapses integer not null default 0,
  step integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  synced_at timestamptz not null default clock_timestamp()
);

create table public.review_logs (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  item_id uuid not null,
  course_id uuid,
  session_id uuid,
  reviewed_at timestamptz not null,
  rating integer not null,
  score double precision not null default -1,
  answer text,
  graded_by text not null,
  duration_ms integer not null default 0,
  state_before integer not null default 0,
  stability_before double precision not null default 0,
  difficulty_before double precision not null default 0,
  elapsed_days double precision not null default 0,
  scheduled_days double precision not null default 0,
  stability_after double precision not null default 0,
  difficulty_after double precision not null default 0,
  synced_at timestamptz not null default clock_timestamp()
);

create table public.exams (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  course_id uuid,
  title text not null,
  date timestamptz not null,
  scope jsonb,
  format jsonb,
  target_readiness double precision not null default 0.9,
  result_score double precision,
  result_logged_at timestamptz,
  readiness_at_exam double precision,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  synced_at timestamptz not null default clock_timestamp()
);

create table public.study_sessions (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  kind text not null,
  started_at timestamptz not null,
  ended_at timestamptz,
  planned_seconds double precision not null default 0,
  active_seconds double precision not null default 0,
  item_count integer not null default 0,
  correct_count integer not null default 0,
  course_id uuid,
  exam_id uuid,
  confusion_id uuid,
  readiness_before double precision,
  readiness_after double precision,
  -- The device has no updatedAt for a session: it sends ended_at, or started_at while the session runs.
  updated_at timestamptz not null default now(),
  synced_at timestamptz not null default clock_timestamp()
);

create table public.day_records (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  day_key text not null check (day_key ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'),
  day timestamptz not null,
  study_seconds double precision not null default 0,
  items_reviewed integer not null default 0,
  sessions integer not null default 0,
  frozen boolean not null default false,
  repaired boolean not null default false,
  updated_at timestamptz not null default now(),
  synced_at timestamptz not null default clock_timestamp(),
  primary key (user_id, day_key)
);

create table public.confusions (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  course_id uuid,
  name text not null,
  explanation text not null default '',
  item_ids jsonb,
  fix jsonb,
  status text not null default 'open',
  miss_count integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  deleted_at timestamptz,
  synced_at timestamptz not null default clock_timestamp()
);

-- Owner-only access, the pull index and the sync stamp, for every synced table.
do $$
declare
  t text;
begin
  foreach t in array array['courses', 'topics', 'sources', 'source_pages', 'items', 'review_logs', 'exams',
                           'study_sessions', 'day_records', 'confusions']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create index %I on public.%I (user_id, synced_at)', t || '_pull', t);
    execute format('create policy %I on public.%I for select to authenticated using (user_id = (select auth.uid()))',
                   t || ': owner reads', t);
    execute format('create policy %I on public.%I for insert to authenticated with check (user_id = (select auth.uid()))',
                   t || ': owner inserts', t);
    execute format('create trigger %I before insert or update on public.%I for each row execute function public.cramless_sync_stamp()',
                   t || '_stamp', t);
    if t <> 'review_logs' then
      execute format('create policy %I on public.%I for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()))',
                     t || ': owner updates', t);
    end if;
    -- Tombstones only: clients never delete rows (account deletion runs as the service role).
    execute format('revoke all on public.%I from anon, authenticated', t);
    if t = 'review_logs' then
      -- Insert-only: no client update of a review.
      execute format('grant select, insert on public.%I to authenticated', t);
    else
      execute format('grant select, insert, update on public.%I to authenticated', t);
    end if;
    execute format('grant all on public.%I to service_role', t);
  end loop;
end
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Entitlements: verified App Store transactions, one row per original transaction and environment. The account
-- function writes them; the person can read their own. A transaction synced from another account moves to it
-- (restoring purchases on a new install), so one purchase powers one account at a time.

create table public.entitlements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  plan text not null check (plan in ('pro', 'squad', 'pass')),
  product_id text not null,
  original_transaction_id text not null,
  transaction_id text not null,
  purchase_date timestamptz not null,
  -- Null only for a purchase that never expires (none today); an Exam Pass gets purchase date + 30 days.
  expires_at timestamptz,
  revoked_at timestamptz,
  environment text not null check (environment in ('Production', 'Sandbox', 'Xcode')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (environment, original_transaction_id)
);

create index entitlements_user on public.entitlements (user_id);

alter table public.entitlements enable row level security;
create policy "entitlements: owner reads" on public.entitlements
  for select to authenticated using (user_id = (select auth.uid()));
revoke insert, update, delete, truncate on public.entitlements from anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------
-- Quotas: one counter per person, meter and period (the local day, or the local week starting Monday).

create table public.usage_counters (
  user_id uuid not null references auth.users (id) on delete cascade,
  -- 'extras' meters check, confusions and cards-from-chat; 'redeems' caps Squad code attempts (guessing).
  meter text not null check (meter in ('scans', 'grades', 'tutor', 'lectures', 'extras', 'redeems')),
  period_start date not null,
  used integer not null default 0 check (used >= 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, meter, period_start)
);

alter table public.usage_counters enable row level security;
create policy "usage: owner reads" on public.usage_counters
  for select to authenticated using (user_id = (select auth.uid()));
revoke insert, update, delete, truncate on public.usage_counters from anon, authenticated;

-- An AI scan is a capture session: its page transcriptions and the generate call that follows, within 30 minutes
-- and 10 pages. This row remembers the person's open scan.
create table public.scan_windows (
  user_id uuid primary key references auth.users (id) on delete cascade,
  opened_at timestamptz not null default '-infinity',
  period_start date,
  pages integer not null default 0,
  generated boolean not null default true
);

alter table public.scan_windows enable row level security;
revoke all on public.scan_windows from anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------
-- Squad: the purchaser owns it; up to three friends join with single-use invite codes (four seats in all).
-- Clients read their own Squad through security-definer helpers; every write goes through the account function.

create table public.squads (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null unique references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

create table public.squad_members (
  squad_id uuid not null references public.squads (id) on delete cascade,
  user_id uuid not null unique references auth.users (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (squad_id, user_id)
);

create table public.squad_invites (
  code text primary key check (code ~ '^CAP-[A-Z0-9]{4}$'),
  squad_id uuid not null references public.squads (id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  redeemed_by uuid references auth.users (id) on delete set null,
  redeemed_at timestamptz
);

create index squad_invites_squad on public.squad_invites (squad_id);

-- The Squads the caller belongs to (as owner or member). Security definer, so the policies below don't recurse
-- through squad_members' own policy.
create or replace function public.cramless_my_squad_ids()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select s.id from public.squads s where s.owner_id = (select auth.uid())
  union
  select m.squad_id from public.squad_members m where m.user_id = (select auth.uid())
$$;

revoke all on function public.cramless_my_squad_ids() from public, anon;
grant execute on function public.cramless_my_squad_ids() to authenticated;

-- The Squads the caller owns.
create or replace function public.cramless_my_owned_squad_ids()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select s.id from public.squads s where s.owner_id = (select auth.uid())
$$;

revoke all on function public.cramless_my_owned_squad_ids() from public, anon;
grant execute on function public.cramless_my_owned_squad_ids() to authenticated;

alter table public.squads enable row level security;
alter table public.squad_members enable row level security;
alter table public.squad_invites enable row level security;

create policy "squads: members read" on public.squads
  for select to authenticated using (id in (select public.cramless_my_squad_ids()));
create policy "squad_members: members read" on public.squad_members
  for select to authenticated using (squad_id in (select public.cramless_my_squad_ids()));
create policy "squad_invites: owner reads" on public.squad_invites
  for select to authenticated using (squad_id in (select public.cramless_my_owned_squad_ids()));

revoke insert, update, delete, truncate on public.squads, public.squad_members, public.squad_invites
  from anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------
-- The AI request log: what each relay call cost. Never content.

create table public.ai_requests (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  route text not null,
  model text not null,
  plan text not null,
  status integer not null,
  mock boolean not null default false,
  input_tokens integer not null default 0,
  output_tokens integer not null default 0,
  cache_read_tokens integer not null default 0,
  cache_write_tokens integer not null default 0,
  cost_usd numeric(14, 9) not null default 0,
  latency_ms integer not null default 0,
  created_at timestamptz not null default now()
);

create index ai_requests_user on public.ai_requests (user_id, created_at);

alter table public.ai_requests enable row level security;
revoke all on public.ai_requests from anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------
-- Storage: a private bucket with one folder per person (`<user id>/…`). Anonymous sessions can read their folder
-- but not upload: backups of page photos need a real account.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('sources', 'sources', false, 15728640,
        array['image/jpeg', 'image/png', 'image/heic', 'application/pdf', 'audio/mp4', 'audio/x-m4a'])
on conflict (id) do nothing;

create policy "sources bucket: owner reads" on storage.objects
  for select to authenticated
  using (bucket_id = 'sources' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "sources bucket: owner uploads" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'sources'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false
  );

create policy "sources bucket: owner updates" on storage.objects
  for update to authenticated
  using (bucket_id = 'sources' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'sources' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "sources bucket: owner deletes" on storage.objects
  for delete to authenticated
  using (bucket_id = 'sources' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- ---------------------------------------------------------------------------------------------------------------
-- Grants. New tables get no privileges by default, so every one is granted here, least first: clients read and
-- write their own study data (RLS above), read their own profile, plan, usage and Squad; everything else is the
-- service role's (the Edge Functions).

revoke all on public.profiles, public.entitlements, public.usage_counters, public.scan_windows, public.squads,
  public.squad_members, public.squad_invites, public.ai_requests from anon, authenticated;
grant select, insert, update on public.profiles to authenticated;
grant select on public.entitlements, public.usage_counters, public.squads, public.squad_members, public.squad_invites
  to authenticated;
grant all on public.profiles, public.entitlements, public.usage_counters, public.scan_windows, public.squads,
  public.squad_members, public.squad_invites, public.ai_requests to service_role;
grant usage, select on all sequences in schema public to service_role;
