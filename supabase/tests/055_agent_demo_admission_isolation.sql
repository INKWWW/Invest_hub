begin;

select plan(8);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at)
values
  ('00000000-0000-0000-0000-000000055001', 'authenticated', 'authenticated', 'demo-a@example.invalid', 'not-a-secret', now()),
  ('00000000-0000-0000-0000-000000055002', 'authenticated', 'authenticated', 'demo-b@example.invalid', 'not-a-secret', now())
on conflict (id) do nothing;
insert into public.profiles (id, role, display_name)
values
  ('00000000-0000-0000-0000-000000055001', 'user', 'Demo A'),
  ('00000000-0000-0000-0000-000000055002', 'user', 'Demo B')
on conflict (id) do nothing;
insert into public.research_threads (id, owner_id, title)
values
  ('00000000-0000-0000-0000-000000055011', '00000000-0000-0000-0000-000000055001', 'A 会话'),
  ('00000000-0000-0000-0000-000000055012', '00000000-0000-0000-0000-000000055002', 'B 会话');
insert into public.workers (id, name, device_secret_hash, status, last_heartbeat_at, capabilities)
values ('00000000-0000-0000-0000-000000055099', 'demo-worker-055', 'demo-worker-055-secret', 'online', timezone('utc', now()), array['agent_demo']);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000055001', true);
select is((public.admit_agent_demo_run('00000000-0000-0000-0000-000000055001', '00000000-0000-0000-0000-000000055011', 'request-055-a', 'A 的问题')->>'status'), 'queued', 'first user can create the active Demo run');
select throws_ok(
  $$select public.admit_agent_demo_run('00000000-0000-0000-0000-000000055002', '00000000-0000-0000-0000-000000055012', 'request-055-b', 'B 的问题');$$,
  'P0001', 'demo_runner_busy', 'second user is rejected while the global slot is active'
);
select is((select count(*)::integer from public.agent_demo_runs where owner_id = '00000000-0000-0000-0000-000000055002'), 0, 'busy rejection leaves no foreign run');
select is((select count(*)::integer from public.research_messages where owner_id = '00000000-0000-0000-0000-000000055002'), 0, 'busy rejection leaves no user message');

reset role;
update public.agent_demo_runs set status = 'failed' where request_id = 'request-055-a';
update public.workers set status = 'offline' where id = '00000000-0000-0000-0000-000000055099';
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000055002', true);
select throws_ok(
  $$select public.admit_agent_demo_run('00000000-0000-0000-0000-000000055002', '00000000-0000-0000-0000-000000055012', 'request-055-c', '离线问题');$$,
  'P0001', 'demo_runner_unavailable', 'offline Worker is rejected before message creation'
);
select is((select count(*)::integer from public.research_messages where owner_id = '00000000-0000-0000-0000-000000055002'), 0, 'offline rejection leaves no user message');
select is((select count(*)::integer from public.agent_demo_runs), 0, 'foreign user cannot list another users Demo run');
select is((select count(*)::integer from public.agent_demo_runs where owner_id <> auth.uid()), 0, 'owner RLS filters guessed Demo run rows');

select * from finish();
rollback;
