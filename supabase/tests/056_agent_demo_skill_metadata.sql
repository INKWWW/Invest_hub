begin;

select plan(8);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at)
values ('00000000-0000-0000-0000-000000056001', 'authenticated', 'authenticated', 'demo-skill@example.invalid', 'not-a-secret', now())
on conflict (id) do nothing;
insert into public.profiles (id, role, display_name)
values ('00000000-0000-0000-0000-000000056001', 'user', 'Demo Skill')
on conflict (id) do nothing;
insert into public.research_threads (id, owner_id, title)
values ('00000000-0000-0000-0000-000000056011', '00000000-0000-0000-0000-000000056001', 'Skill 会话');
insert into public.workers (id, name, device_secret_hash, status, last_heartbeat_at)
values ('00000000-0000-0000-0000-000000056099', 'demo-worker-056', 'demo-worker-056-secret', 'online', timezone('utc', now()));

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000056001', true);
select is((public.admit_agent_demo_run(
  '00000000-0000-0000-0000-000000056001',
  '00000000-0000-0000-0000-000000056011',
  'request-056-a',
  '/investment-research 研究公开公司',
  'explicit',
  'investment-research'
)->>'status'), 'queued', 'explicit Skill admission is queued');
select is((public.admit_agent_demo_run(
  '00000000-0000-0000-0000-000000056001',
  '00000000-0000-0000-0000-000000056011',
  'request-056-a',
  '/investment-research 研究公开公司',
  'explicit',
  'investment-research'
)->>'invocation_mode'), 'explicit', 'explicit invocation mode is persisted');
select is((public.admit_agent_demo_run(
  '00000000-0000-0000-0000-000000056001',
  '00000000-0000-0000-0000-000000056011',
  'request-056-a',
  '/investment-research 研究公开公司',
  'explicit',
  'investment-research'
)->>'skill_id'), 'investment-research', 'one fixed Skill ID is persisted');
select is((select invocation_mode from public.agent_demo_runs where request_id = 'request-056-a'), 'explicit'::text, 'stored run metadata is explicit');
select is((select skill_id from public.agent_demo_runs where request_id = 'request-056-a'), 'investment-research'::text, 'stored run Skill matches the command');

reset role;
select is((public.claim_agent_demo_run((select id from public.agent_demo_runs where request_id = 'request-056-a'), '00000000-0000-0000-0000-000000056099')->>'skill_id'), 'investment-research', 'Worker claim carries one Skill ID');
select throws_ok($$select public.admit_agent_demo_run('00000000-0000-0000-0000-000000056001', '00000000-0000-0000-0000-000000056011', 'request-056-b', 'bad', 'explicit', 'not-allowlisted');$$, '22023', 'invalid_demo_message', 'unallowlisted Skill is rejected');
select throws_ok($$select public.admit_agent_demo_run('00000000-0000-0000-0000-000000056001', '00000000-0000-0000-0000-000000056011', 'request-056-c', 'bad', 'explicit', null);$$, '22023', 'invalid_demo_message', 'explicit mode requires a Skill ID');

select * from finish();
rollback;
