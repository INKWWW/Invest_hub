begin;

select plan(5);

insert into public.workers (id, name, device_secret_hash, status)
values ('00000000-0000-0000-0000-000000022001', 'covered-failure-worker', 'covered-failure-worker-hash', 'online');

insert into public.sources (id, source_key, source_type, display_name, parameter_version, authorized_worker_id)
values
  ('00000000-0000-0000-0000-000000022011', 'covered-failure-source', 'x', 'Covered failure source', 'v2-covered-failure', '00000000-0000-0000-0000-000000022001'),
  ('00000000-0000-0000-0000-000000022012', 'uncovered-failure-source', 'x', 'Uncovered failure source', 'v2-covered-failure', '00000000-0000-0000-0000-000000022001');

insert into public.x_source_profiles (source_id, requested_handle, account_id, display_name, resolution_status)
values
  ('00000000-0000-0000-0000-000000022011', 'covered_failure', 'covered_failure', 'Covered failure source', 'resolved'),
  ('00000000-0000-0000-0000-000000022012', 'uncovered_failure', 'uncovered_failure', 'Uncovered failure source', 'resolved');

insert into public.source_collection_coverage (source_id, coverage_start_at, coverage_through_at)
values
  ('00000000-0000-0000-0000-000000022011', '2026-07-24T08:00:00Z', '2026-07-24T08:00:00Z'),
  ('00000000-0000-0000-0000-000000022012', '2026-07-24T08:00:00Z', '2026-07-24T08:00:00Z');

create temporary table covered_failed_task as
select public.create_windowed_x_sync_task(
  '00000000-0000-0000-0000-000000022011', 'v2-covered-failure', null, 'scheduled',
  '2026-07-24T12:00:00Z', '2026-07-24T20:00+08:00'
) as payload;

update public.sync_tasks
set status = 'failed'
where id = (select (payload->>'id')::uuid from covered_failed_task);

update public.source_collection_coverage
set coverage_through_at = '2026-07-24T12:00:00Z'
where source_id = '00000000-0000-0000-0000-000000022011';

create temporary table covered_successor_task as
select public.create_windowed_x_sync_task(
  '00000000-0000-0000-0000-000000022011', 'v2-covered-failure', null, 'scheduled',
  '2026-07-24T16:00:00Z', '2026-07-25T00:00+08:00'
) as payload;

create temporary table covered_claim as
select public.claim_next_task('00000000-0000-0000-0000-000000022001', '2026-07-24T16:01:00Z') as payload;

select is(
  (select payload->>'task_id' from covered_claim),
  (select payload->>'id' from covered_successor_task),
  'a terminal failed X task whose range is already covered does not block the next range'
);

insert into public.sync_tasks (
  id, task_type, source_id, status, parameter_version, collection_scope,
  capture_range, author_profile_snapshot, x_source_snapshot, queued_at
) values
  (
    '00000000-0000-0000-0000-000000022101', 'x_sync', '00000000-0000-0000-0000-000000022012', 'failed', 'v2-covered-failure', '{"mode":"window"}'::jsonb,
    '{"mode":"window","trigger":"scheduled","timezone":"Asia/Shanghai","start_at":"2026-07-24T08:00:00Z","end_at":"2026-07-24T12:00:00Z","scheduled_window_key":"2026-07-24T20:00+08:00","overlap_start_at":"2026-07-24T08:00:00Z"}'::jsonb,
    '[]'::jsonb, '{"source_type":"x","account_id":"uncovered_failure","display_name":"Uncovered failure source","parameter_version":"v2-covered-failure"}'::jsonb, '2026-07-24T12:00:00Z'
  ),
  (
    '00000000-0000-0000-0000-000000022102', 'x_sync', '00000000-0000-0000-0000-000000022012', 'queued', 'v2-covered-failure', '{"mode":"window"}'::jsonb,
    '{"mode":"window","trigger":"scheduled","timezone":"Asia/Shanghai","start_at":"2026-07-24T12:00:00Z","end_at":"2026-07-24T16:00:00Z","scheduled_window_key":"2026-07-25T00:00+08:00","overlap_start_at":"2026-07-24T11:30:00Z"}'::jsonb,
    '[]'::jsonb, '{"source_type":"x","account_id":"uncovered_failure","display_name":"Uncovered failure source","parameter_version":"v2-covered-failure"}'::jsonb, '2026-07-24T16:00:00Z'
  );

create temporary table uncovered_claim as
select public.claim_next_task('00000000-0000-0000-0000-000000022001', '2026-07-24T16:02:00Z') as payload;

select is(
  (select payload from uncovered_claim),
  null,
  'a terminal failed X task beyond the coverage waterline still blocks an unproven later range'
);

insert into public.sources (id, source_key, source_type, display_name, parameter_version, authorized_worker_id)
values (
  '00000000-0000-0000-0000-000000022013',
  'covered-retryable-source',
  'x',
  'Covered retryable source',
  'v2-covered-failure',
  '00000000-0000-0000-0000-000000022001'
);

insert into public.x_source_profiles (source_id, requested_handle, account_id, display_name, resolution_status)
values (
  '00000000-0000-0000-0000-000000022013',
  'covered_retryable',
  'covered_retryable',
  'Covered retryable source',
  'resolved'
);

insert into public.source_collection_coverage (source_id, coverage_start_at, coverage_through_at)
values (
  '00000000-0000-0000-0000-000000022013',
  '2026-07-24T08:00:00Z',
  '2026-07-24T08:00:00Z'
);

create temporary table covered_retryable_task as
select public.create_windowed_x_sync_task(
  '00000000-0000-0000-0000-000000022013', 'v2-covered-failure', null, 'scheduled',
  '2026-07-24T12:00:00Z', '2026-07-24T20:00+08:00'
) as payload;

update public.sync_tasks
set status = 'retryable_failed',
    queued_at = '2026-07-24T12:00:00Z'
where id = (select (payload->>'id')::uuid from covered_retryable_task);

update public.source_collection_coverage
set coverage_through_at = '2026-07-24T12:00:00Z'
where source_id = '00000000-0000-0000-0000-000000022013';

create temporary table current_retryable_successor_task as
select public.create_windowed_x_sync_task(
  '00000000-0000-0000-0000-000000022013', 'v2-covered-failure', null, 'scheduled',
  '2026-07-24T16:00:00Z', '2026-07-25T00:00+08:00'
) as payload;

select is(
  (select payload->'capture_range'->>'start_at' from current_retryable_successor_task),
  '2026-07-24T12:00:00+00:00',
  'the scheduler creates a fresh X window from the current coverage waterline when an older retryable window is already covered'
);

select is(
  (select payload->'capture_range'->>'end_at' from current_retryable_successor_task),
  '2026-07-24T16:00:00+00:00',
  'the fresh X window retains the requested fixed end boundary'
);

create temporary table covered_retryable_claim as
select public.claim_next_task('00000000-0000-0000-0000-000000022001', '2026-07-24T16:03:00Z') as payload;

select is(
  (select payload->>'task_id' from covered_retryable_claim),
  (
    select id::text
    from public.sync_tasks
    where source_id = '00000000-0000-0000-0000-000000022013'
      and (capture_range->>'start_at')::timestamptz = '2026-07-24T12:00:00Z'::timestamptz
  ),
  'a covered retryable X window cannot preempt the window at the current coverage waterline'
);

select * from finish();
rollback;
