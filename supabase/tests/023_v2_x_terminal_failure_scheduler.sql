begin;

select plan(6);

insert into public.workers (id, name, device_secret_hash, status, capabilities, last_heartbeat_at)
values (
  '00000000-0000-0000-0000-000000023001', 'terminal-failure-scheduler-worker',
  'terminal-failure-scheduler-hash', 'online', array['x_sync'], '2026-07-24T04:00:00Z'
);

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
select public.ensure_due_x_collection_batches('00000000-0000-0000-0000-000000023001', '2026-07-24T04:01:00Z') as payload;

select is(
  (select jsonb_array_length(payload->'batches')::text from due_tick),
  '1',
  'a terminal failed X source and a healthy source still form one scheduled batch'
);
select is(
  (select count(*)::text from public.x_collection_batch_sources),
  '2',
  'the batch freezes both the terminal source and the healthy source for partial settlement'
);
select is(
  (select x_sync_task_id::text from public.x_collection_batch_sources where source_id = '00000000-0000-0000-0000-000000023011'),
  (select id::text from public.sync_tasks where source_id = '00000000-0000-0000-0000-000000023011'),
  'the terminal task is retained as the frozen source audit task'
);
select is(
  (select collection_batch_id is not null from public.sync_tasks where source_id = '00000000-0000-0000-0000-000000023012')::text,
  'true',
  'the healthy source remains independently scheduled and linked to its batch'
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
