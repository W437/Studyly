-- Row-level security and grants, as the app's roles see them. Run with `supabase test db` against the local stack.
begin;
create extension if not exists pgtap with schema extensions;
select plan(40);

-- Two people (the profile trigger gives each a profile) and one anonymous session.
insert into auth.users (id, email, aud, role, is_anonymous)
values ('11111111-1111-4111-8111-111111111111', 'a@capling.test', 'authenticated', 'authenticated', false),
       ('22222222-2222-4222-8222-222222222222', 'b@capling.test', 'authenticated', 'authenticated', false),
       ('33333333-3333-4333-8333-333333333333', null, 'authenticated', 'authenticated', true);

select is((select count(*)::int from public.profiles
           where id in ('11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222',
                        '33333333-3333-4333-8333-333333333333')), 3, 'every auth user gets a profile');

-- As A.
set local role authenticated;
set local request.jwt.claims = '{"sub": "11111111-1111-4111-8111-111111111111", "role": "authenticated"}';

select lives_ok($$ insert into public.courses (id, name, updated_at) values ('c0000000-0000-4000-8000-00000000000a', 'Bio 101', '2026-10-22T09:00:00Z') $$,
                'A inserts a course; user_id defaults to A');
select is((select user_id from public.courses where id = 'c0000000-0000-4000-8000-00000000000a'),
          '11111111-1111-4111-8111-111111111111'::uuid, 'the row is A''s');
select isnt((select synced_at from public.courses where id = 'c0000000-0000-4000-8000-00000000000a'), null, 'synced_at is stamped');
select throws_ok($$ insert into public.courses (id, user_id, name) values ('c0000000-0000-4000-8000-00000000000b', '22222222-2222-4222-8222-222222222222', 'Not mine') $$,
                 '42501', null, 'A cannot write a row for B');
select lives_ok($$ insert into public.courses (id, name, updated_at) values ('c0000000-0000-4000-8000-00000000000a', 'Bio 101 (new)', '2026-10-22T10:00:00Z')
                   on conflict (id) do update set name = excluded.name, updated_at = excluded.updated_at $$,
                'A upserts her own course');
select is((select name from public.courses where id = 'c0000000-0000-4000-8000-00000000000a'), 'Bio 101 (new)', 'a newer write wins');
select lives_ok($$ update public.courses set name = 'Stale', updated_at = '2026-10-21T00:00:00Z' where id = 'c0000000-0000-4000-8000-00000000000a' $$,
                'an older write is accepted…');
select is((select name from public.courses where id = 'c0000000-0000-4000-8000-00000000000a'), 'Bio 101 (new)', '…and changes nothing (last writer wins)');
select throws_ok($$ update public.courses set user_id = '22222222-2222-4222-8222-222222222222' where id = 'c0000000-0000-4000-8000-00000000000a' $$,
                 '42501', null, 'a row cannot change owner');
select throws_ok($$ delete from public.courses where id = 'c0000000-0000-4000-8000-00000000000a' $$,
                 '42501', null, 'clients never delete rows (tombstones only)');
select lives_ok($$ update public.courses set deleted_at = now(), updated_at = '2026-10-22T11:00:00Z' where id = 'c0000000-0000-4000-8000-00000000000a' $$,
                'a tombstone is an update');

select lives_ok($$ insert into public.review_logs (id, item_id, reviewed_at, rating, graded_by) values ('a0000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000001', now(), 3, 'person') $$,
                'A appends a review');
select lives_ok($$ insert into public.review_logs (id, item_id, reviewed_at, rating, graded_by) values ('a0000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000001', now(), 1, 'person') on conflict do nothing $$,
                'a retried push is ignored');
select is((select rating from public.review_logs where id = 'a0000000-0000-4000-8000-000000000001'), 3, 'the first review stands');
select throws_ok($$ update public.review_logs set rating = 4 $$, '42501', null, 'reviews are insert-only');
select throws_ok($$ delete from public.review_logs $$, '42501', null, 'reviews cannot be deleted by clients');

select lives_ok($$ insert into public.day_records (day_key, day, sessions) values ('2026-10-22', '2026-10-22', 1) $$, 'A records a day');
select is((select quest_mask::int from public.day_records where day_key = '2026-10-22'), 0, 'a day starts with no quests finished');
select lives_ok($$ insert into public.day_records (day_key, day, sessions, quest_mask) values ('2026-10-22', '2026-10-22', 1, 7)
                   on conflict (user_id, day_key) do update set quest_mask = excluded.quest_mask $$,
                'A pushes the quests she finished');
select throws_ok($$ update public.day_records set quest_mask = 2048 where day_key = '2026-10-22' $$,
                 '23514', null, 'a quest mask stays within the bits that exist');
select lives_ok($$ insert into public.profiles (id, display_name, timezone) values ('11111111-1111-4111-8111-111111111111', 'Maya', 'America/Los_Angeles')
                   on conflict (id) do update set display_name = excluded.display_name, timezone = excluded.timezone $$,
                'A sets her own name and time zone');

select throws_ok($$ insert into public.entitlements (user_id, plan, product_id, original_transaction_id, transaction_id, purchase_date, environment)
                    values ('11111111-1111-4111-8111-111111111111', 'pro', 'p', 'o', 't', now(), 'Sandbox') $$,
                 '42501', null, 'nobody grants themselves a plan');
select throws_ok($$ insert into public.usage_counters (user_id, meter, period_start, used) values ('11111111-1111-4111-8111-111111111111', 'grades', '2026-10-22', 0) $$,
                 '42501', null, 'nobody resets their own quota');
select throws_ok($$ select count(*) from public.ai_requests $$, '42501', null, 'the AI log is service-only');
select throws_ok($$ select count(*) from public.scan_windows $$, '42501', null, 'scan windows are service-only');
select throws_ok($$ insert into public.squads (owner_id) values ('11111111-1111-4111-8111-111111111111') $$,
                 '42501', null, 'Squads are made by the account function only');
select throws_ok($$ select public.cramless_consume('11111111-1111-4111-8111-111111111111', 'grades', '2026-10-22', -100, null) $$,
                 '42501', null, 'clients cannot call the quota RPCs');
select throws_ok($$ select public.cramless_save_entitlements('11111111-1111-4111-8111-111111111111', '[]'::jsonb, now()) $$,
                 '42501', null, 'clients cannot call the entitlement RPCs');

-- Storage: A's own folder only.
select lives_ok($$ insert into storage.objects (bucket_id, name, owner) values ('sources', '11111111-1111-4111-8111-111111111111/s1/p1.jpg', '11111111-1111-4111-8111-111111111111') $$,
                'A uploads into her folder');
select throws_ok($$ insert into storage.objects (bucket_id, name, owner) values ('sources', '22222222-2222-4222-8222-222222222222/s1/p1.jpg', '11111111-1111-4111-8111-111111111111') $$,
                 '42501', null, 'A cannot upload into B''s folder');

-- As B: none of A's rows exist.
set local request.jwt.claims = '{"sub": "22222222-2222-4222-8222-222222222222", "role": "authenticated"}';
select is((select count(*)::int from public.courses), 0, 'B sees none of A''s courses');
select is((select count(*)::int from public.review_logs), 0, 'B sees none of A''s reviews');
select is((select count(*)::int from public.profiles), 1, 'B sees only her own profile');
select is((select count(*)::int from storage.objects where bucket_id = 'sources'), 0, 'B sees none of A''s files');
update public.courses set name = 'Hijacked' where id = 'c0000000-0000-4000-8000-00000000000a';
reset role;
select is((select name from public.courses where id = 'c0000000-0000-4000-8000-00000000000a'), 'Bio 101 (new)', 'B''s update touched nothing');

-- The anonymous session can't back up files.
set local role authenticated;
set local request.jwt.claims = '{"sub": "33333333-3333-4333-8333-333333333333", "role": "authenticated", "is_anonymous": true}';
select throws_ok($$ insert into storage.objects (bucket_id, name, owner) values ('sources', '33333333-3333-4333-8333-333333333333/s1/p1.jpg', '33333333-3333-4333-8333-333333333333') $$,
                 '42501', null, 'anonymous sessions cannot upload');

-- No JWT at all.
set local role anon;
select throws_ok($$ select count(*) from public.courses $$, '42501', null, 'anon reads nothing');
select throws_ok($$ select count(*) from public.items $$, '42501', null, 'anon reads no items');
reset role;

-- Deleting the auth user removes everything.
delete from auth.users where id = '11111111-1111-4111-8111-111111111111';
select is((select count(*)::int from public.courses where user_id = '11111111-1111-4111-8111-111111111111'), 0, 'courses cascade with the account');

select * from finish();
rollback;
