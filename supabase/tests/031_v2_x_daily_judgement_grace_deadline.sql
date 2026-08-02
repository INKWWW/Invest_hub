begin;

select plan(13);

insert into public.workers (id, name, device_secret_hash, status, capabilities, last_heartbeat_at)
values ('00000000-0000-0000-0000-000000031001', 'grace-deadline-worker', 'grace-deadline-worker-hash', 'online', array['x_sync'], '2026-08-01T12:00:00Z');

insert into public.sources (id, source_key, source_type, display_name, parameter_version, authorized_worker_id)
values ('00000000-0000-0000-0000-000000031101', 'grace-deadline-source', 'x', 'Grace deadline source', 'v2-grace-deadline', '00000000-0000-0000-0000-000000031001');

insert into public.x_source_profiles (source_id, requested_handle, account_id, display_name, resolution_status)
values ('00000000-0000-0000-0000-000000031101', 'grace_deadline_source', 'grace_deadline_source', 'Grace deadline source', 'resolved');

insert into public.source_collection_coverage (source_id, coverage_start_at, coverage_through_at)
values ('00000000-0000-0000-0000-000000031101', '2026-08-01T00:00:00+08:00', '2026-08-01T16:00:00+08:00');

select has_function(
  'public',
  'x_collection_batch_settlement_deadline',
  array['date'],
  'the settlement deadline has one natural-date authority'
);

select is(
  (select (public.x_collection_batch_settlement_deadline(date '2026-08-01') at time zone 'Asia/Shanghai')::text),
  '2026-08-02 01:00:00',
  'the natural day settles at Shanghai next-day 01:00'
);

select lives_ok(
  $$select public.ensure_due_x_collection_batches('00000000-0000-0000-0000-000000031001', '2026-08-01T20:01:00+08:00')$$,
  'an authorized Worker can create the 20:00 batch'
);

select is(
  (select (settlement_deadline_at at time zone 'Asia/Shanghai')::text
   from public.x_collection_batches where scheduled_window_key = '2026-08-01T20:00+08:00'),
  '2026-08-02 01:00:00',
  'the 20:00 batch persists the natural-day grace deadline'
);

update public.sync_tasks
set status = 'succeeded'
where id = (
  select x_sync_task_id from public.x_collection_batch_sources batch_source
  join public.x_collection_batches batch on batch.id = batch_source.batch_id
  where batch.scheduled_window_key = '2026-08-01T20:00+08:00'
    and batch_source.source_id = '00000000-0000-0000-0000-000000031101'
);
update public.source_collection_coverage
set coverage_through_at = '2026-08-01T20:00:00+08:00'
where source_id = '00000000-0000-0000-0000-000000031101';
update public.workers
set last_heartbeat_at = '2026-08-01T16:01:00Z'
where id = '00000000-0000-0000-0000-000000031001';

select lives_ok(
  $$select public.ensure_due_x_collection_batches('00000000-0000-0000-0000-000000031001', '2026-08-02T00:01:00+08:00')$$,
  'an authorized Worker can create the prior-day midnight batch'
);

select is(
  (select natural_date::text from public.x_collection_batches where scheduled_window_key = '2026-08-02T00:00+08:00'),
  '2026-08-01',
  'the midnight batch remains attached to the prior natural day'
);

select is(
  (select (settlement_deadline_at at time zone 'Asia/Shanghai')::text
   from public.x_collection_batches where scheduled_window_key = '2026-08-02T00:00+08:00'),
  '2026-08-02 01:00:00',
  'the midnight batch shares the prior natural-day grace deadline'
);

update public.sync_tasks
set status = 'succeeded'
where id = (
  select x_sync_task_id from public.x_collection_batch_sources batch_source
  join public.x_collection_batches batch on batch.id = batch_source.batch_id
  where batch.scheduled_window_key = '2026-08-02T00:00+08:00'
    and batch_source.source_id = '00000000-0000-0000-0000-000000031101'
);
insert into public.x_daily_viewpoint_segments (
  id, source_id, natural_date, range_task_id, segment_version,
  occurred_from_at, occurred_through_at, window_viewpoints, post_analysis_refs, evidence_refs
) values (
  '00000000-0000-0000-0000-000000031201',
  '00000000-0000-0000-0000-000000031101',
  '2026-08-01',
  (select x_sync_task_id from public.x_collection_batch_sources batch_source
   join public.x_collection_batches batch on batch.id = batch_source.batch_id
   where batch.scheduled_window_key = '2026-08-02T00:00+08:00'
     and batch_source.source_id = '00000000-0000-0000-0000-000000031101'),
  1,
  '2026-08-01T12:00:00Z',
  '2026-08-01T16:00:00Z',
  '["fixture grace viewpoint"]'::jsonb,
  '[]'::jsonb,
  '[]'::jsonb
);

select is(
  (select public.settle_x_collection_batch(
    (select id from public.x_collection_batches where scheduled_window_key = '2026-08-02T00:00+08:00'),
    '2026-08-02T00:59:59+08:00'
  )->>'coverage_status'),
  'complete',
  'a fully persisted source before 01:00 is included for judgement'
);

select is(
  (select status from public.x_collection_batch_sources batch_source
   join public.x_collection_batches batch on batch.id = batch_source.batch_id
   where batch.scheduled_window_key = '2026-08-02T00:00+08:00'
     and batch_source.source_id = '00000000-0000-0000-0000-000000031101'),
  'judgement_pending',
  'pre-deadline settlement advances the included source to judgement processing'
);

select is(
  (select count(*)::text from public.x_daily_judgement_runs run
   join public.x_collection_batches batch on batch.id = run.batch_id
   where batch.scheduled_window_key = '2026-08-02T00:00+08:00'),
  '1',
  'an included source queues exactly one Provider judgement run'
);

insert into public.x_collection_batches (id, scheduled_window_key, natural_date, cutoff_at, settlement_deadline_at)
values (
  '00000000-0000-0000-0000-000000031301',
  '2026-08-02T20:00+08:00',
  '2026-08-02',
  '2026-08-02T12:00:00Z',
  '2026-08-02T17:00:00Z'
);
insert into public.sync_tasks (
  id, task_type, source_id, status, parameter_version, collection_scope, capture_range,
  author_profile_snapshot, x_source_snapshot, collection_batch_id
) values (
  '00000000-0000-0000-0000-000000031302',
  'x_sync',
  '00000000-0000-0000-0000-000000031101',
  'queued',
  'v2-grace-deadline',
  '{"mode":"window"}'::jsonb,
  '{"mode":"window","trigger":"scheduled","timezone":"Asia/Shanghai","start_at":"2026-08-02T08:00:00Z","end_at":"2026-08-02T12:00:00Z","scheduled_window_key":"2026-08-02T20:00+08:00","overlap_start_at":"2026-08-02T08:00:00Z"}'::jsonb,
  '[]'::jsonb,
  '{"source_type":"x","account_id":"grace_deadline_source","display_name":"Grace deadline source","parameter_version":"v2-grace-deadline"}'::jsonb,
  '00000000-0000-0000-0000-000000031301'
);
insert into public.x_collection_batch_sources (batch_id, source_id, source_display_name, x_sync_task_id)
values (
  '00000000-0000-0000-0000-000000031301',
  '00000000-0000-0000-0000-000000031101',
  'Grace deadline source',
  '00000000-0000-0000-0000-000000031302'
);

select is(
  (select public.settle_x_collection_batch('00000000-0000-0000-0000-000000031301', '2026-08-03T01:00:00+08:00')->>'coverage_status'),
  'partial',
  'an unfinished source at 01:00 settles as partial'
);

select is(
  (select exclusion_code from public.x_collection_batch_sources
   where batch_id = '00000000-0000-0000-0000-000000031301'),
  'settlement_deadline_exceeded',
  'an unfinished source at 01:00 is explicitly excluded for deadline expiry'
);

select is(
  (select count(*)::text from public.x_daily_judgement_runs
   where batch_id = '00000000-0000-0000-0000-000000031301'),
  '0',
  'a timeout-only batch does not queue Provider judgement work'
);

select * from finish();
rollback;
