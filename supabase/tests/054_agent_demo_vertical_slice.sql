begin;

select plan(19);

select has_table('public', 'agent_demo_runs', 'demo run table exists');
select has_column('public', 'agent_demo_runs', 'invocation_mode', 'run stores invocation mode');
select has_column('public', 'agent_demo_runs', 'skill_id', 'run stores optional Skill ID');
select ok((select relrowsecurity from pg_class where oid = 'public.agent_demo_runs'::regclass), 'demo runs use RLS');
select ok(exists (select 1 from pg_indexes where indexname = 'agent_demo_runs_owner_request_idx'), 'request identity is indexed');
select ok(exists (select 1 from pg_indexes where indexname = 'agent_demo_runs_one_active_idx'), 'one active demo run is enforced');
select has_function('public', 'admit_agent_demo_run', array['uuid', 'uuid', 'text', 'text', 'text', 'text'], 'demo admission function exists');
select has_function('public', 'claim_agent_demo_run', array['uuid', 'uuid'], 'demo claim function exists');
select has_function('public', 'complete_agent_demo_run', array['uuid', 'uuid', 'text', 'text'], 'demo completion function exists');

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at)
values ('00000000-0000-0000-0000-000000054001', 'authenticated', 'authenticated', 'demo-one@example.invalid', 'not-a-secret', now())
on conflict (id) do nothing;
insert into public.profiles (id, role, display_name)
values ('00000000-0000-0000-0000-000000054001', 'user', 'Demo One')
on conflict (id) do nothing;
insert into public.research_threads (id, owner_id, title)
values ('00000000-0000-0000-0000-000000054011', '00000000-0000-0000-0000-000000054001', '新研究会话');
insert into public.workers (id, name, device_secret_hash, status, last_heartbeat_at, capabilities)
values
  ('00000000-0000-0000-0000-000000054099', 'demo-worker', 'demo-worker-secret-hash', 'online', timezone('utc', now()), array['agent_demo']),
  ('00000000-0000-0000-0000-000000054098', 'x-only-worker', 'x-only-worker-secret-hash', 'online', timezone('utc', now()), array['x_sync']);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000054001', true);
select is((public.admit_agent_demo_run(
  '00000000-0000-0000-0000-000000054001',
  '00000000-0000-0000-0000-000000054011',
  'request-054-a',
  '研究宁德时代'
)->>'status'), 'queued', 'admission creates queued run');
select is((select count(*)::integer from public.research_messages where thread_id = '00000000-0000-0000-0000-000000054011'), 1, 'admission creates one user message');
select is((public.admit_agent_demo_run(
  '00000000-0000-0000-0000-000000054001',
  '00000000-0000-0000-0000-000000054011',
  'request-054-a',
  '研究宁德时代'
)->>'idempotent')::boolean, true, 'same request is idempotent');
select is((select count(*)::integer from public.research_messages where thread_id = '00000000-0000-0000-0000-000000054011'), 1, 'idempotent admission does not duplicate user message');
reset role;
select is((public.claim_agent_demo_run((select id from public.agent_demo_runs where request_id = 'request-054-a'), '00000000-0000-0000-0000-000000054099') ->> 'status'), 'running', 'worker claims queued run');
select is((public.complete_agent_demo_run((select id from public.agent_demo_runs where request_id = 'request-054-a'), '00000000-0000-0000-0000-000000054099', '# 完成\n\n脚本 Provider 结果。', 'scripted') ->> 'status'), 'succeeded', 'completion stores success');
select is((select count(*)::integer from public.research_messages where thread_id = '00000000-0000-0000-0000-000000054011' and role = 'assistant'), 1, 'completion creates one assistant message');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000054001', true);
select is((public.admit_agent_demo_run(
  '00000000-0000-0000-0000-000000054001',
  '00000000-0000-0000-0000-000000054011',
  'request-054-b',
  '第二个研究问题'
)->>'status'), 'queued', 'a second Demo run can be queued after completion');
reset role;
select is(public.claim_agent_demo_run((select id from public.agent_demo_runs where request_id = 'request-054-b'), '00000000-0000-0000-0000-000000054098'), null, 'X-only Worker cannot claim an Agent Demo run');

reset role;
update public.agent_demo_runs
set status = 'failed'
where request_id = 'request-054-b';
update public.workers
set status = 'offline'
where id = '00000000-0000-0000-0000-000000054099';
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000054001', true);
select throws_ok(
  $$select public.admit_agent_demo_run('00000000-0000-0000-0000-000000054001', '00000000-0000-0000-0000-000000054011', 'request-054-c', '没有 Agent Worker 的问题');$$,
  'P0001', 'demo_runner_unavailable', 'admission rejects when only non-Agent Workers are online'
);

select * from finish();
rollback;
