begin;

select plan(26);

select has_table('public', 'x_demo_fixed_window_runs', 'Ticket 02R stores one explicit runner identity per cutoff');
select has_function('public', 'start_x_demo_fixed_window_run', array['timestamp with time zone', 'uuid'], 'Ticket 02R freezes the enabled source snapshot');
select has_function('public', 'bind_x_demo_fixed_window_task', array['uuid', 'uuid', 'uuid', 'uuid'], 'Ticket 02R binds only its exact Ticket 01 task');
select has_function('public', 'claim_x_demo_fixed_window_judgement', array['uuid', 'uuid', 'timestamp with time zone'], 'Ticket 02R exposes an exact judgement claim');

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at)
values ('00000000-0000-0000-0000-000000042001', 'authenticated', 'authenticated', 'ticket-02r@example.invalid', 'not-a-secret', now());
insert into public.profiles (id, role, display_name)
values ('00000000-0000-0000-0000-000000042001', 'admin', 'Ticket 02R admin');
insert into public.workers (id, name, device_secret_hash, status, last_heartbeat_at, capabilities)
values ('00000000-0000-0000-0000-000000042002', 'Ticket 02R Worker', 'ticket-02r-hash', 'online', now(), array['x_sync']);

select public.create_x_source('x:ticket-02r-a', 'Ticket 02R A', 'fixture_a', 'x-standard-v2', '00000000-0000-0000-0000-000000042001');
update public.sources
set authorized_worker_id = '00000000-0000-0000-0000-000000042002'
where source_key = 'x:ticket-02r-a';
select public.resolve_x_source_identity(
  (select id from public.sources where source_key = 'x:ticket-02r-a'),
  '00000000-0000-0000-0000-000000042002', 'x-standard-v2', 'fixture_a'
);
update public.sources
set authorized_worker_id = '00000000-0000-0000-0000-000000042002'
where source_key = 'x:ticket-02r-a';
select public.create_x_source('x:ticket-02r-b', 'Ticket 02R B', 'fixture_b', 'x-standard-v2', '00000000-0000-0000-0000-000000042001');

update public.sources
set authorized_worker_id = '00000000-0000-0000-0000-000000042002'
where source_key = 'x:ticket-02r-b';
select public.resolve_x_source_identity(
  (select id from public.sources where source_key = 'x:ticket-02r-b'),
  '00000000-0000-0000-0000-000000042002', 'x-standard-v2', 'fixture_b'
);
update public.x_source_profiles
set resolution_status = 'pending', account_id = null
where source_id = (select id from public.sources where source_key = 'x:ticket-02r-b');
create temporary table before_not_ready as
select
  (select count(*) from public.x_demo_fixed_window_runs) as runs,
  (select count(*) from public.x_collection_batches) as batches,
  (select count(*) from public.x_collection_batch_sources) as batch_sources,
  (select count(*) from public.sync_tasks) as tasks,
  (select count(*) from public.x_daily_judgement_runs) as judgements;
select throws_ok(
  $$select public.start_x_demo_fixed_window_run('2026-08-18T16:00:00+08:00', '00000000-0000-0000-0000-000000042002')$$,
  'PT409', 'x_demo_sources_not_ready', 'an enabled source without a ready identity is rejected before run creation'
);
select is((select count(*) from public.x_demo_fixed_window_runs), (select runs from before_not_ready), 'not-ready start creates no run');
select is((select count(*) from public.x_collection_batches), (select batches from before_not_ready), 'not-ready start creates no batch');
select is((select count(*) from public.x_collection_batch_sources), (select batch_sources from before_not_ready), 'not-ready start creates no batch sources');
select is((select count(*) from public.sync_tasks), (select tasks from before_not_ready), 'not-ready start creates no task');
select is((select count(*) from public.x_daily_judgement_runs), (select judgements from before_not_ready), 'not-ready start creates no judgement');

select public.resolve_x_source_identity(
  (select id from public.sources where source_key = 'x:ticket-02r-b'),
  '00000000-0000-0000-0000-000000042002', 'x-standard-v2', 'fixture_b'
);
update public.x_source_profiles set enabled = true
where source_id = (select id from public.sources where source_key = 'x:ticket-02r-b');

create temporary table demo_run as
select public.start_x_demo_fixed_window_run(
  '2026-08-18T16:00:00+08:00', '00000000-0000-0000-0000-000000042002'
) as payload;

select is((select payload->>'idempotent' from demo_run), 'false', 'the first cutoff creates one runner identity');
select is((select jsonb_array_length(payload->'sources') from demo_run), 2, 'the frozen snapshot contains all enabled X sources');
select is(
  (select array_agg(item->>'source_id' order by item->>'source_id') from demo_run, jsonb_array_elements(payload->'sources') item),
  (select array_agg(id::text order by id::text) from public.sources where source_key in ('x:ticket-02r-a', 'x:ticket-02r-b')),
  'the snapshot is stable and source-id ordered'
);

create temporary table demo_run_again as
select public.start_x_demo_fixed_window_run(
  '2026-08-18T16:00:00+08:00', '00000000-0000-0000-0000-000000042002'
) as payload;
select is((select payload->>'idempotent' from demo_run_again), 'true', 'the same cutoff returns the existing run identity');
select is((select payload->>'run_id' from demo_run_again), (select payload->>'run_id' from demo_run), 'duplicate start does not create a second run');
select is((select count(*)::int from public.x_demo_fixed_window_runs), 1, 'the cutoff uniqueness is durable');

create temporary table exact_task as
select public.create_x_demo_fixed_window_task_for_worker(
  (select id from public.sources where source_key = 'x:ticket-02r-a'),
  '2026-08-18T16:00:00+08:00', '00000000-0000-0000-0000-000000042002', 'fixture_a'
) as payload;
select lives_ok(
  $$select public.bind_x_demo_fixed_window_task(
    (select (payload->>'run_id')::uuid from demo_run),
    (select id from public.sources where source_key = 'x:ticket-02r-a'),
    (select (payload->>'id')::uuid from exact_task),
    '00000000-0000-0000-0000-000000042002'
  )$$,
  'the runner binds the exact task returned by Ticket 01 creation'
);
select is(
  (select collection_batch_id from public.sync_tasks where id = (select (payload->>'id')::uuid from exact_task)),
  (select batch_id from public.x_demo_fixed_window_runs where id = (select (payload->>'run_id')::uuid from demo_run)),
  'the exact task is attached to the frozen batch'
);
select is(
  (select x_sync_task_id from public.x_collection_batch_sources where source_id = (select id from public.sources where source_key = 'x:ticket-02r-a')),
  (select (payload->>'id')::uuid from exact_task),
  'the batch source row records the exact task and no other task'
);
update public.sources
set enabled = false, display_name = 'Ticket 02R A renamed after start', parameter_version = 'mutated-after-start'
where source_key = 'x:ticket-02r-a';
update public.x_source_profiles
set enabled = false, display_name = 'Ticket 02R A profile renamed after start'
where source_id = (select id from public.sources where source_key = 'x:ticket-02r-a');
select is(
  (select item->>'display_name' from demo_run, jsonb_array_elements(payload->'sources') item where item->>'source_id' = (select id::text from public.sources where source_key = 'x:ticket-02r-a')),
  'Ticket 02R A',
  'mutable source changes do not rewrite the current run snapshot'
);
select lives_ok($$select public.create_x_demo_fixed_window_task_for_run(
  (select (payload->>'run_id')::uuid from demo_run),
  (select id from public.sources where source_key = 'x:ticket-02r-a'),
  '2026-08-18T16:00:00+08:00', '00000000-0000-0000-0000-000000042002', 'fixture_a'
)$$, 'the current run still creates its exact task from the frozen snapshot after mutation');

update public.sources set enabled = false where source_key = 'x:ticket-02r-b';
update public.x_source_profiles set enabled = false
where source_id = (select id from public.sources where source_key = 'x:ticket-02r-b');
create temporary table demo_run_after_mutation as
select public.start_x_demo_fixed_window_run(
  '2026-08-18T16:00:00+08:00', '00000000-0000-0000-0000-000000042002'
) as payload;
select is((select payload->>'idempotent' from demo_run_after_mutation), 'true', 'an existing cutoff is idempotent before rechecking readiness');
select is((select payload->>'run_id' from demo_run_after_mutation), (select payload->>'run_id' from demo_run), 'a later unready source does not create a second run');

update public.sources set enabled = true where source_key = 'x:ticket-02r-b';
update public.x_source_profiles set enabled = true
where source_id = (select id from public.sources where source_key = 'x:ticket-02r-b');

create temporary table next_demo_run as
select public.start_x_demo_fixed_window_run(
  '2026-08-18T20:00:00+08:00', '00000000-0000-0000-0000-000000042002'
) as payload;
select is((select jsonb_array_length(payload->'sources') from next_demo_run), 1, 'the next run refreezes the changed enabled source set');
select is((select payload->'sources'->0->>'source_id' from next_demo_run), (select id::text from public.sources where source_key = 'x:ticket-02r-b'), 'the next run excludes the source disabled after the first start');
select is((select count(*)::int from pg_proc where pronamespace = 'public'::regnamespace and proname = 'claim_x_demo_fixed_window_activation'), 0, 'Ticket 02R has no runtime activation RPC');

select * from finish();
rollback;
