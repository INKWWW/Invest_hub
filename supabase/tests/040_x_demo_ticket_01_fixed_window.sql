begin;

select plan(13);

select has_function(
  'public', 'x_demo_fixed_window_bounds', array['timestamp with time zone'],
  'Ticket 01 exposes one deterministic fixed-window boundary contract'
);
select has_function(
  'public', 'create_x_demo_fixed_window_task', array['uuid', 'timestamp with time zone', 'uuid'],
  'Ticket 01 can create a task for one explicit source and cutoff'
);
select has_table('public', 'x_demo_fixed_window_tasks', 'Ticket 01 records fixed-window task identity separately from legacy waterlines');

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at)
values ('00000000-0000-0000-0000-000000040001', 'authenticated', 'authenticated', 'ticket-01-admin@example.invalid', 'not-a-secret', now());
insert into public.profiles (id, role, display_name)
values ('00000000-0000-0000-0000-000000040001', 'admin', 'Ticket 01 admin');

select lives_ok(
  $$select public.create_x_source('x:ticket-01-offline', 'Ticket 01 blogger', 'fixture_handle', 'x-standard-v2', '00000000-0000-0000-0000-000000040001')$$,
  'an X source can be saved while no Worker is online'
);
select is(
  (select resolution_status from public.x_source_profiles profile join public.sources source on source.id = profile.source_id where source.source_key = 'x:ticket-01-offline'),
  'pending',
  'an offline-created X source waits for bounded identity activation'
);
select is(
  (select authorized_worker_id from public.sources where source_key = 'x:ticket-01-offline'),
  null::uuid,
  'an offline-created X source is not bound to a missing Worker'
);

insert into public.workers (id, name, device_secret_hash, status, last_heartbeat_at, capabilities)
values ('00000000-0000-0000-0000-000000040002', 'Ticket 01 Worker', 'ticket-01-worker-hash', 'online', now(), array['x_sync']);

select public.claim_next_x_activation(
  '00000000-0000-0000-0000-000000040002', now()
);
select public.resolve_x_source_identity(
  (select id from public.sources where source_key = 'x:ticket-01-offline'),
  '00000000-0000-0000-0000-000000040002', 'x-standard-v2', 'fixture_handle'
);

select is(
  public.x_demo_fixed_window_bounds('2026-08-18T00:00:00+08:00'),
  jsonb_build_object(
    'start_at', '2026-08-17T12:00:00+00:00',
    'end_at', '2026-08-17T16:00:00+00:00',
    'scheduled_window_key', '2026-08-18T00:00+08:00',
    'natural_date', '2026-08-17'
  ),
  'midnight uses the preceding Shanghai 20:00 to 24:00 range and date'
);

insert into public.sync_tasks (id, task_type, source_id, status, parameter_version, capture_range, collection_scope, x_source_snapshot)
values (
  '00000000-0000-0000-0000-000000040003', 'x_sync',
  (select id from public.sources where source_key = 'x:ticket-01-offline'), 'failed', 'x-standard-v2',
  '{"mode":"window","trigger":"scheduled","timezone":"Asia/Shanghai","start_at":"2026-08-17T00:00:00Z","end_at":"2026-08-17T04:00:00Z","scheduled_window_key":"2026-08-17T12:00+08:00","overlap_start_at":"2026-08-17T00:00:00Z"}'::jsonb,
  '{"mode":"window"}'::jsonb,
  '{"source_type":"x","account_id":"fixture_handle","display_name":"Ticket 01 blogger","parameter_version":"x-standard-v2"}'::jsonb
);

select lives_ok(
  $$select public.create_x_demo_fixed_window_task(
    (select id from public.sources where source_key = 'x:ticket-01-offline'),
    '2026-08-18T00:00:00+08:00',
    '00000000-0000-0000-0000-000000040001'
  )$$,
  'a later fixed window is created without repairing an earlier failed task'
);
select is(
  (select capture_range->>'start_at' from public.sync_tasks task join public.x_demo_fixed_window_tasks demo on demo.task_id = task.id where demo.cutoff_at = '2026-08-18T00:00:00+08:00'),
  '2026-08-17T12:00:00+00:00',
  'the later fixed window starts at the unique preceding cutoff'
);
select is(
  (select capture_range->>'end_at' from public.sync_tasks task join public.x_demo_fixed_window_tasks demo on demo.task_id = task.id where demo.cutoff_at = '2026-08-18T00:00:00+08:00'),
  '2026-08-17T16:00:00+00:00',
  'the later fixed window ends at its explicit cutoff'
);
select is(
  (select natural_date::text from public.x_demo_fixed_window_tasks where cutoff_at = '2026-08-18T00:00:00+08:00'),
  '2026-08-17',
  'the fixed window keeps its Shanghai natural date'
);
select is(
  (select count(*)::int from public.sync_tasks where source_id = (select id from public.sources where source_key = 'x:ticket-01-offline') and status <> 'succeeded'),
  2,
  'the old failed task remains audit history and is not replaced'
);

select throws_ok(
  $$select public.x_demo_fixed_window_bounds('2026-08-18T10:00:00+08:00')$$,
  '22023', 'invalid_x_demo_cutoff',
  'an arbitrary time cannot become a fixed X window'
);

select * from finish();
rollback;
