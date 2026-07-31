begin;

select plan(20);

select has_function(
  'public',
  'x_collection_batch_logical_date',
  array['timestamp with time zone'],
  'batch logical dates are derived by one database authority'
);

insert into public.workers (id, name, device_secret_hash, status, capabilities)
values
  ('00000000-0000-0000-0000-000000027001', 'batch-worker-a', 'batch-worker-a-hash', 'online', array['x_sync']),
  ('00000000-0000-0000-0000-000000027002', 'batch-worker-b', 'batch-worker-b-hash', 'enrolled', array['x_sync']),
  ('00000000-0000-0000-0000-000000027003', 'discord-only-worker', 'discord-only-worker-hash', 'online', array['discord_sync']),
  ('00000000-0000-0000-0000-000000027004', 'unassigned-x-worker', 'unassigned-x-worker-hash', 'online', array['x_sync']);

insert into public.sources (id, source_key, source_type, display_name, parameter_version, authorized_worker_id)
values
  ('00000000-0000-0000-0000-000000027011', 'batch-source-a', 'x', 'Current source A', 'v2-batch-identity', '00000000-0000-0000-0000-000000027001'),
  ('00000000-0000-0000-0000-000000027012', 'batch-source-b', 'x', 'Lagging source B', 'v2-batch-identity', '00000000-0000-0000-0000-000000027002'),
  ('00000000-0000-0000-0000-000000027013', 'batch-source-no-coverage', 'x', 'No coverage source', 'v2-batch-identity', '00000000-0000-0000-0000-000000027001');

insert into public.x_source_profiles (source_id, requested_handle, account_id, display_name, resolution_status, enabled)
values
  ('00000000-0000-0000-0000-000000027011', 'batch_source_a', 'batch_source_a', 'Current source A', 'resolved', true),
  ('00000000-0000-0000-0000-000000027012', 'batch_source_b', 'batch_source_b', 'Lagging source B', 'resolved', true),
  ('00000000-0000-0000-0000-000000027013', 'batch_source_no_coverage', 'batch_source_no_coverage', 'No coverage source', 'resolved', true);

insert into public.source_collection_coverage (source_id, coverage_start_at, coverage_through_at)
values
  ('00000000-0000-0000-0000-000000027011', '2026-07-31T00:00:00+08:00', '2026-07-31T20:00:00+08:00'),
  ('00000000-0000-0000-0000-000000027012', '2026-07-31T00:00:00+08:00', '2026-07-31T16:00:00+08:00');

select throws_ok(
  $$select public.ensure_due_x_collection_batches('00000000-0000-0000-0000-000000027003', '2026-08-01T00:01:00+08:00')$$,
  '42501', 'worker_not_authorized',
  'a Discord-only Worker cannot ensure X judgement batches'
);
select throws_ok(
  $$select public.ensure_due_x_collection_batches('00000000-0000-0000-0000-000000027004', '2026-08-01T00:01:00+08:00')$$,
  '42501', 'worker_not_authorized',
  'an unassigned X-capable Worker cannot ensure X judgement batches'
);
select lives_ok(
  $$select public.ensure_due_x_collection_batches('00000000-0000-0000-0000-000000027001', '2026-08-01T00:01:00+08:00')$$,
  'an authorized X-capable Worker can ensure due batches across source owners'
);

select is(
  (select natural_date::text from public.x_collection_batches where scheduled_window_key = '2026-08-01T00:00+08:00'),
  '2026-07-31',
  'the next-day Shanghai midnight cutoff belongs to the prior natural date'
);
select is(
  (select count(*)::text from public.x_collection_batch_sources batch_source
   join public.x_collection_batches batch on batch.id = batch_source.batch_id
   where batch.scheduled_window_key = '2026-08-01T00:00+08:00'),
  '3',
  'the cutoff freezes every enabled resolved X source, including lagging and uninitialized sources'
);
select is(
  (select source_display_name from public.x_collection_batch_sources batch_source
   join public.x_collection_batches batch on batch.id = batch_source.batch_id
   where batch.scheduled_window_key = '2026-08-01T00:00+08:00'
     and batch_source.source_id = '00000000-0000-0000-0000-000000027012'),
  'Lagging source B',
  'a source owned by another Worker remains visible in the immutable snapshot'
);
select is(
  (select settlement_status from public.x_collection_batch_sources batch_source
   join public.x_collection_batches batch on batch.id = batch_source.batch_id
   where batch.scheduled_window_key = '2026-08-01T00:00+08:00'
     and batch_source.source_id = '00000000-0000-0000-0000-000000027012'),
  'excluded',
  'a source behind the cutoff is safely excluded instead of hidden'
);
select is(
  (select x_sync_task_id::text from public.x_collection_batch_sources batch_source
   join public.x_collection_batches batch on batch.id = batch_source.batch_id
   where batch.scheduled_window_key = '2026-08-01T00:00+08:00'
     and batch_source.source_id = '00000000-0000-0000-0000-000000027012'),
  null,
  'a lagging source is not bound to a nonmatching collection range'
);
select is(
  (select settlement_status from public.x_collection_batch_sources batch_source
   join public.x_collection_batches batch on batch.id = batch_source.batch_id
   where batch.scheduled_window_key = '2026-08-01T00:00+08:00'
     and batch_source.source_id = '00000000-0000-0000-0000-000000027013'),
  'excluded',
  'a source without initialized coverage is safely excluded instead of omitted'
);
select is(
  (select exclusion_code from public.x_collection_batch_sources batch_source
   join public.x_collection_batches batch on batch.id = batch_source.batch_id
   where batch.scheduled_window_key = '2026-08-01T00:00+08:00'
     and batch_source.source_id = '00000000-0000-0000-0000-000000027013'),
  'coverage_not_initialized',
  'the frozen snapshot records why an uninitialized source was excluded'
);
select is(
  (select task.capture_range->>'end_at' from public.x_collection_batch_sources batch_source
   join public.x_collection_batches batch on batch.id = batch_source.batch_id
   join public.sync_tasks task on task.id = batch_source.x_sync_task_id
   where batch.scheduled_window_key = '2026-08-01T00:00+08:00'
     and batch_source.source_id = '00000000-0000-0000-0000-000000027011'),
  '2026-07-31T16:00:00+00:00',
  'only the source with the exact due range is bound to the cutoff batch'
);

update public.sync_tasks
set status = 'succeeded'
where id = (
  select batch_source.x_sync_task_id
  from public.x_collection_batch_sources batch_source
  join public.x_collection_batches batch on batch.id = batch_source.batch_id
  where batch.scheduled_window_key = '2026-08-01T00:00+08:00'
    and batch_source.source_id = '00000000-0000-0000-0000-000000027011'
);
insert into public.x_daily_viewpoint_segments (
  source_id, natural_date, range_task_id, segment_version,
  occurred_from_at, occurred_through_at, window_viewpoints, post_analysis_refs, evidence_refs
) values (
  '00000000-0000-0000-0000-000000027011', '2026-07-31',
  (select batch_source.x_sync_task_id
   from public.x_collection_batch_sources batch_source
   join public.x_collection_batches batch on batch.id = batch_source.batch_id
   where batch.scheduled_window_key = '2026-08-01T00:00+08:00'
     and batch_source.source_id = '00000000-0000-0000-0000-000000027011'),
  1, '2026-07-31T12:00:00Z', '2026-07-31T15:59:00Z',
  '["fixture viewpoint"]'::jsonb, '[]'::jsonb, '[]'::jsonb
);
create temporary table midnight_settlement as
select public.settle_x_collection_batch(
  (select id from public.x_collection_batches where scheduled_window_key = '2026-08-01T00:00+08:00'),
  '2026-08-01T00:02:00+08:00'
) as payload;

select is((select payload->>'coverage_status' from midnight_settlement), 'partial', 'visible excluded sources force partial judgement coverage');
select is(
  (select settlement_status from public.x_collection_batch_sources batch_source
   join public.x_collection_batches batch on batch.id = batch_source.batch_id
   where batch.scheduled_window_key = '2026-08-01T00:00+08:00'
     and batch_source.source_id = '00000000-0000-0000-0000-000000027011'),
  'included',
  'a matching prior-date segment is included in the midnight batch'
);
select is(
  (select run.status from public.x_daily_judgement_runs run
   join public.x_collection_batches batch on batch.id = run.batch_id
   where batch.scheduled_window_key = '2026-08-01T00:00+08:00'),
  'queued',
  'a partially covered batch with included evidence queues judgement work'
);

select throws_ok(
  $$select public.claim_next_x_daily_judgement('00000000-0000-0000-0000-000000027003', '2026-08-01T00:03:00+08:00')$$,
  '42501', 'worker_not_authorized',
  'a Discord-only Worker cannot receive X judgement work'
);
update public.x_daily_judgement_runs
set status = 'queued', attempt = 0, lease_owner = null, lease_expires_at = null
where batch_id = (select id from public.x_collection_batches where scheduled_window_key = '2026-08-01T00:00+08:00');
create temporary table worker_b_claim as
select public.claim_next_x_daily_judgement('00000000-0000-0000-0000-000000027002', '2026-08-01T00:03:00+08:00') as payload;
select isnt((select payload->>'run_id' from worker_b_claim), null, 'an authorized X-capable Worker for another frozen source may claim the shared judgement');
select is((select payload->'batch'->>'coverage_status' from worker_b_claim), 'partial', 'the Worker receives partial rather than false complete coverage');

insert into public.x_collection_batches (
  id, scheduled_window_key, natural_date, cutoff_at, settlement_deadline_at, status
) values (
  '00000000-0000-0000-0000-000000027021', '2026-08-01T08:00+08:00', '2026-08-01',
  '2026-08-01T00:00:00Z', '2026-08-01T02:00:00Z', 'collecting'
);
insert into public.sync_tasks (
  id, task_type, source_id, status, parameter_version, collection_scope, capture_range,
  author_profile_snapshot, x_source_snapshot, collection_batch_id
) values (
  '00000000-0000-0000-0000-000000027022', 'x_sync', '00000000-0000-0000-0000-000000027011',
  'succeeded', 'v2-batch-identity', '{"mode":"window"}'::jsonb,
  '{"mode":"window","trigger":"scheduled","timezone":"Asia/Shanghai","start_at":"2026-07-31T16:00:00Z","end_at":"2026-08-01T00:00:00Z","scheduled_window_key":"2026-08-01T08:00+08:00","overlap_start_at":"2026-07-31T15:30:00Z"}'::jsonb,
  '[]'::jsonb,
  '{"source_type":"x","account_id":"batch_source_a","display_name":"Current source A","parameter_version":"v2-batch-identity"}'::jsonb,
  '00000000-0000-0000-0000-000000027021'
);
insert into public.x_collection_batch_sources (batch_id, source_id, source_display_name, x_sync_task_id)
values (
  '00000000-0000-0000-0000-000000027021', '00000000-0000-0000-0000-000000027011',
  'Current source A', '00000000-0000-0000-0000-000000027022'
);
insert into public.x_daily_viewpoint_segments (
  source_id, natural_date, range_task_id, segment_version,
  occurred_from_at, occurred_through_at, window_viewpoints, post_analysis_refs, evidence_refs
) values (
  '00000000-0000-0000-0000-000000027011', '2026-07-31', '00000000-0000-0000-0000-000000027022',
  2, '2026-08-01T00:00:00Z', '2026-08-01T00:01:00Z', '["wrong date"]'::jsonb, '[]'::jsonb, '[]'::jsonb
);
create temporary table wrong_date_settlement as
select public.settle_x_collection_batch('00000000-0000-0000-0000-000000027021', '2026-08-01T02:01:00Z') as payload;
select is(
  (select settlement_status from public.x_collection_batch_sources where batch_id = '00000000-0000-0000-0000-000000027021'),
  'excluded',
  'a segment from another natural date cannot satisfy this batch'
);
select is((select payload->>'coverage_status' from wrong_date_settlement), 'partial', 'a wrong-date-only source cannot yield complete coverage');

select * from finish();
rollback;
