begin;

select plan(5);

insert into public.workers (id, name, device_secret_hash, status)
values ('00000000-0000-0000-0000-000000023001', 'terminal-failure-scheduler-worker', 'terminal-failure-scheduler-hash', 'online');

insert into public.sources (id, source_key, source_type, display_name, parameter_version, authorized_worker_id)
values
  ('00000000-0000-0000-0000-000000023011', 'terminal-failure-source', 'x', 'Terminal failure source', 'v2-terminal-failure', '00000000-0000-0000-0000-000000023001'),
  ('00000000-0000-0000-0000-000000023012', 'healthy-source', 'x', 'Healthy source', 'v2-terminal-failure', '00000000-0000-0000-0000-000000023001');

insert into public.x_source_profiles (source_id, requested_handle, account_id, display_name, resolution_status)
values
  ('00000000-0000-0000-0000-000000023011', 'terminal_failure', 'terminal_failure', 'Terminal failure source', 'resolved'),
  ('00000000-0000-0000-0000-000000023012', 'healthy_source', 'healthy_source', 'Healthy source', 'resolved');

insert into public.source_collection_coverage (source_id, coverage_start_at, coverage_through_at)
values
  ('00000000-0000-0000-0000-000000023011', '2026-07-24T00:00:00Z', '2026-07-24T00:00:00Z'),
  ('00000000-0000-0000-0000-000000023012', '2026-07-24T00:00:00Z', '2026-07-24T00:00:00Z');

create temporary table terminal_failure_task as
select public.create_windowed_x_sync_task(
  '00000000-0000-0000-0000-000000023011', 'v2-terminal-failure', null, 'scheduled',
  '2026-07-24T12:00+08:00', '2026-07-24T12:00+08:00'
) as payload;

update public.sync_tasks
set status = 'failed'
where id = (select (payload->>'id')::uuid from terminal_failure_task);

create temporary table due_tick as
select public.enqueue_due_x_tasks('00000000-0000-0000-0000-000000023001', '2026-07-24T04:01:00Z') as payload;

select is(
  (select jsonb_array_length(payload->'tasks')::text from due_tick),
  '1',
  'a terminal failed X source is deferred while a healthy source is scheduled'
);
select is(
  (select payload->'tasks'->0->>'source_id' from due_tick),
  '00000000-0000-0000-0000-000000023012',
  'the healthy source remains independently schedulable'
);
select is(
  (select jsonb_array_length(payload->'deferred_source_ids')::text from due_tick),
  '1',
  'the terminal failed source is explicitly reported as deferred'
);
select is(
  (select count(*)::text from public.sync_tasks where source_id = '00000000-0000-0000-0000-000000023011'),
  '1',
  'the scheduler does not recreate the same terminal failed window'
);
select is(
  (select status from public.sync_tasks where source_id = '00000000-0000-0000-0000-000000023011'),
  'failed',
  'the terminal failure remains available as audit evidence'
);

select * from finish();
rollback;
