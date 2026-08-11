begin;

select plan(38);

select has_table('public', 'research_quotas', 'research quota table exists');
select has_table('public', 'research_quota_reservations', 'quota reservations table exists');
select has_table('public', 'research_quota_ledger', 'quota ledger table exists');
select ok((select relrowsecurity from pg_class where oid = 'public.research_quotas'::regclass), 'quota rows use RLS');
select ok((select relrowsecurity from pg_class where oid = 'public.research_quota_reservations'::regclass), 'reservations use RLS');
select ok((select relrowsecurity from pg_class where oid = 'public.research_quota_ledger'::regclass), 'ledger uses RLS');
select ok(
  exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'research_quota_reservations_request_idx'),
  'request identity is indexed and unique per owner'
);
select ok(
  exists (select 1 from pg_proc where proname = 'reserve_research_quota'),
  'reservation RPC exists'
);
select ok(
  exists (select 1 from pg_proc where proname = 'commit_research_quota'),
  'commit RPC exists'
);
select ok(
  exists (select 1 from pg_proc where proname = 'release_research_quota'),
  'release RPC exists'
);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at)
values
  ('00000000-0000-0000-0000-000000039001', 'authenticated', 'authenticated', 'quota-one@example.invalid', 'not-a-secret', now()),
  ('00000000-0000-0000-0000-000000039002', 'authenticated', 'authenticated', 'quota-two@example.invalid', 'not-a-secret', now()),
  ('00000000-0000-0000-0000-000000039099', 'authenticated', 'authenticated', 'quota-admin@example.invalid', 'not-a-secret', now())
on conflict (id) do nothing;

insert into public.profiles (id, role, display_name)
values
  ('00000000-0000-0000-0000-000000039001', 'user', 'Quota One'),
  ('00000000-0000-0000-0000-000000039002', 'user', 'Quota Two'),
  ('00000000-0000-0000-0000-000000039099', 'admin', 'Quota Admin')
on conflict (id) do update set role = excluded.role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000039099', true);
select is(
  (public.admin_adjust_research_quota('00000000-0000-0000-0000-000000039001', 2, 'initial test allocation')->>'available_units')::integer,
  2,
  'admin can assign lifetime quota'
);
select is(
  (select count(*)::integer from public.research_quota_ledger where owner_id = '00000000-0000-0000-0000-000000039001'),
  1,
  'admin assignment creates one audit ledger event'
);
select is(
  (select actor_id from public.research_quota_ledger where owner_id = '00000000-0000-0000-0000-000000039001'),
  '00000000-0000-0000-0000-000000039099'::uuid,
  'ledger records the real administrator actor'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000039001', true);
select is((select count(*)::integer from public.research_quotas), 1, 'owner can read own quota');
select is((select lifetime_units from public.research_quotas), 2, 'owner sees assigned lifetime units');
select set_config('test.reservation_first_idempotent', (public.reserve_research_quota('run-039-a')->>'idempotent'), true);
select is(current_setting('test.reservation_first_idempotent'), 'false', 'first reservation is not idempotent');
select is((public.reserve_research_quota('run-039-a')->>'status'), 'reserved', 'first request reserves one unit');
select is((public.reserve_research_quota('run-039-a')->>'idempotent')::boolean, true, 'repeated request is idempotent');
select is((public.reserve_research_quota('run-039-a')->>'available_units')::integer, 1, 'reservation reduces available units');
select is((select count(*)::integer from public.research_quota_reservations where request_id = 'run-039-a'), 1, 'repeated request keeps one reservation row');
select is((select reserved_units from public.research_quotas), 1, 'repeated request does not double reserve');
select is((public.commit_research_quota((select id from public.research_quota_reservations where request_id = 'run-039-a')) ->> 'status'), 'committed', 'commit settles a reservation');
select is((select reserved_units from public.research_quotas), 0, 'commit releases reserved counter');
select is((select settled_units from public.research_quotas), 1, 'commit increments settled counter');
select is((public.commit_research_quota((select id from public.research_quota_reservations where request_id = 'run-039-a')) ->> 'idempotent')::boolean, true, 'repeated commit is idempotent');
select is((select count(*)::integer from public.research_quota_ledger where owner_id = '00000000-0000-0000-0000-000000039001' and event_type = 'commit'), 1, 'repeated commit writes one ledger event');

select is((public.reserve_research_quota('run-039-b')->>'status'), 'reserved', 'second request can reserve remaining unit');
select throws_ok(
  $$select public.reserve_research_quota('run-039-c');$$,
  'P0001', 'research_quota_insufficient', 'insufficient available quota rejects reservation'
);
select is((public.release_research_quota((select id from public.research_quota_reservations where request_id = 'run-039-b')) ->> 'status'), 'released', 'release returns reservation to available balance');
select is((select reserved_units from public.research_quotas), 0, 'release decrements reserved counter');
select is((select (lifetime_units - reserved_units - settled_units) from public.research_quotas), 1, 'available balance remains derived from authority counters');
select is((public.release_research_quota((select id from public.research_quota_reservations where request_id = 'run-039-b')) ->> 'idempotent')::boolean, true, 'repeated release is idempotent');

select throws_ok(
  $$select public.admin_adjust_research_quota('00000000-0000-0000-0000-000000039001', 0, 'too low');$$,
  '42501', null, 'admin cannot reduce lifetime quota below settled usage'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000039002', true);
select is((select count(*)::integer from public.research_quotas), 0, 'second user cannot read another user quota');
select throws_ok(
  $$select public.reserve_research_quota('foreign-run');$$,
  'P0001', 'research_quota_insufficient', 'unassigned user has no available quota'
);
select is((select count(*)::integer from public.research_quota_ledger), 0, 'second user cannot read another user ledger');

select throws_ok(
  $$insert into public.research_quotas (owner_id, lifetime_units) values ('00000000-0000-0000-0000-000000039002', 99);$$,
  '42501', null, 'ordinary user cannot forge quota rows'
);
select throws_ok(
  $$insert into public.research_quota_ledger (owner_id, event_type, reason) values ('00000000-0000-0000-0000-000000039002', 'admin_adjustment', 'forged');$$,
  '42501', null, 'ordinary user cannot forge audit events'
);

select * from finish();
rollback;
