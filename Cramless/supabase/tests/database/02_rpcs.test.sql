-- The service-role RPCs: plans, quotas and Squad, run as the functions run them. (tests/store_contract.test.ts
-- covers the same rules through PostgresStore; this file pins the SQL on its own.)
begin;
create extension if not exists pgtap with schema extensions;
select plan(16);

insert into auth.users (id, email, aud, role)
values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'owner@capling.test', 'authenticated', 'authenticated'),
       ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'friend@capling.test', 'authenticated', 'authenticated');
update public.profiles set display_name = 'Maya', timezone = 'America/Los_Angeles'
where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

set local role service_role;

select is(public.cramless_context('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '2026-10-22T09:00:00Z') ->> 'plan', 'free', 'a new account is free');
select is(public.cramless_context('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '2026-10-22T09:00:00Z') ->> 'timezone', 'America/Los_Angeles', 'with its time zone');
select is(public.cramless_context('cccccccc-cccc-4ccc-8ccc-cccccccccccc', '2026-10-22T09:00:00Z') ->> 'exists', 'false', 'a deleted account doesn''t exist');

select is(public.cramless_consume('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'grades', '2026-10-22', 1, 1) ->> 'allowed', 'true', 'the first grade');
select is(public.cramless_consume('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'grades', '2026-10-22', 1, 1) ->> 'allowed', 'false', 'the limit holds');
select is(public.cramless_usage('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '[{"meter": "grades", "period": "2026-10-22"}, {"meter": "tutor", "period": "2026-10-22"}]'),
          '{"grades": 1, "tutor": 0}'::jsonb, 'usage per meter');

select is(public.cramless_consume_scan('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'transcribe', 1, '2026-10-19', 3, '2026-10-22T09:00:00Z') ->> 'counted', 'true', 'a transcription opens a scan');
select is(public.cramless_consume_scan('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'generate', 1, '2026-10-19', 3, '2026-10-22T09:05:00Z') ->> 'counted', 'false', 'its generate closes it');
select is(public.cramless_consume_scan('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'generate', 1, '2026-10-19', 3, '2026-10-22T09:06:00Z') ->> 'counted', 'true', 'the next generate is a new scan');

select lives_ok($$ select public.cramless_save_entitlements('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  '[{"plan": "squad", "product_id": "com.loopware.Capling.squad.yearly", "original_transaction_id": "sq1", "transaction_id": "t1",
     "purchase_date": "2026-10-01T00:00:00Z", "expires_at": "2027-10-01T00:00:00Z", "revoked_at": null, "environment": "Sandbox"}]'::jsonb,
  '2026-10-22T09:00:00Z') $$, 'a Squad subscription is saved');
select is(public.cramless_context('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '2026-10-22T09:00:00Z') ->> 'plan', 'squad', 'the purchaser has Squad');
select is(public.cramless_squad_invite('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'CAP-7Q4K', '2026-11-05T00:00:00Z', '2026-10-22T00:00:00Z') ->> 'ok', 'true', 'the purchaser invites');
select is(public.cramless_squad_redeem('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'cap-7q4k', '2026-10-22T01:00:00Z'),
          '{"ok": true, "owner_name": "Maya"}'::jsonb, 'a friend redeems');
select is(public.cramless_context('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', '2026-10-22T09:00:00Z') ->> 'plan', 'squad', 'the friend has Squad');
select is(jsonb_array_length(public.cramless_squad_members('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb') -> 'members'), 2, 'two of four seats');
select throws_ok($$ insert into public.squad_invites (code, squad_id, expires_at) values ('bad code', gen_random_uuid(), now()) $$,
                 '23514', null, 'invite codes have one shape');

select * from finish();
rollback;
