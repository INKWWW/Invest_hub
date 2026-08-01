begin;

select plan(41);

select has_function(
  'public',
  'x_collection_batch_logical_date',
  array['timestamp with time zone'],
  'batch logical dates are derived by one database authority'
);

select has_function(
  'public',
  'lock_and_assert_x_collection_batch_identity_migration_safe',
  array[]::text[],
  'migration identity preflight is guarded by one lock-order authority'
);
select ok(
  coalesce((
    select
      position('lock table public.x_collection_batches in access exclusive mode' in definition) > 0
      and position('lock table public.x_collection_batches in access exclusive mode' in definition)
        < position('lock table public.x_collection_batch_sources in access exclusive mode' in definition)
      and position('lock table public.x_collection_batch_sources in access exclusive mode' in definition)
        < position('lock table public.x_daily_judgement_runs in access exclusive mode' in definition)
      and position('lock table public.x_daily_judgement_runs in access exclusive mode' in definition)
        < position('lock table public.x_daily_judgement_versions in access exclusive mode' in definition)
      and position('lock table public.x_daily_judgement_versions in access exclusive mode' in definition)
        < position('perform public.assert_x_collection_batch_identity_migration_safe()' in definition)
    from (
      select lower(pg_get_functiondef(
        to_regprocedure('public.lock_and_assert_x_collection_batch_identity_migration_safe()')
      )) as definition
    ) migration_lock_source
  ), false),
  'all four ACCESS EXCLUSIVE locks are acquired in fixed order before legacy preflight'
);
select lives_ok(
  $$select public.lock_and_assert_x_collection_batch_identity_migration_safe()$$,
  'the migration lock authority can acquire all four table locks before preflight'
);
select is(
  (select count(distinct relation)::text
   from pg_locks
   where pid = pg_backend_pid()
     and locktype = 'relation'
     and mode = 'AccessExclusiveLock'
     and granted
     and relation in (
       'public.x_collection_batches'::regclass,
       'public.x_collection_batch_sources'::regclass,
       'public.x_daily_judgement_runs'::regclass,
       'public.x_daily_judgement_versions'::regclass
     )),
  '4',
  'the lock authority holds all protected legacy identity tables for the transaction'
);

insert into public.workers (id, name, device_secret_hash, status, capabilities, last_heartbeat_at)
values
  ('00000000-0000-0000-0000-000000027001', 'batch-worker-a', 'batch-worker-a-hash', 'online', array['x_sync'], '2026-07-31T16:00:00Z'),
  ('00000000-0000-0000-0000-000000027002', 'batch-worker-b', 'batch-worker-b-hash', 'enrolled', array['x_sync'], null),
  ('00000000-0000-0000-0000-000000027003', 'discord-only-worker', 'discord-only-worker-hash', 'online', array['discord_sync'], '2026-07-31T16:00:00Z'),
  ('00000000-0000-0000-0000-000000027004', 'unassigned-x-worker', 'unassigned-x-worker-hash', 'online', array['x_sync'], '2026-07-31T16:00:00Z');

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
  id, source_id, natural_date, range_task_id, segment_version,
  occurred_from_at, occurred_through_at, window_viewpoints, post_analysis_refs, evidence_refs
) values (
  '00000000-0000-0000-0000-000000027031',
  '00000000-0000-0000-0000-000000027011', '2026-07-31',
  (select batch_source.x_sync_task_id
   from public.x_collection_batch_sources batch_source
   join public.x_collection_batches batch on batch.id = batch_source.batch_id
   where batch.scheduled_window_key = '2026-08-01T00:00+08:00'
     and batch_source.source_id = '00000000-0000-0000-0000-000000027011'),
  1, '2026-07-31T12:00:00Z', '2026-07-31T15:59:00Z',
  '["fixture viewpoint"]'::jsonb, '[]'::jsonb, '[]'::jsonb
);
insert into public.x_daily_viewpoint_segments (
  id, source_id, natural_date, range_task_id, segment_version,
  occurred_from_at, occurred_through_at, window_viewpoints, post_analysis_refs, evidence_refs
) values (
  '00000000-0000-0000-0000-000000027032',
  '00000000-0000-0000-0000-000000027011', '2026-08-01',
  (select batch_source.x_sync_task_id
   from public.x_collection_batch_sources batch_source
   join public.x_collection_batches batch on batch.id = batch_source.batch_id
   where batch.scheduled_window_key = '2026-08-01T00:00+08:00'
     and batch_source.source_id = '00000000-0000-0000-0000-000000027011'),
  1, '2026-07-31T15:59:30Z', '2026-07-31T16:00:00Z',
  '["wrong-day fixture viewpoint"]'::jsonb, '[]'::jsonb, '[]'::jsonb
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

update public.workers
set last_heartbeat_at = '2026-07-31T16:02:00Z'
where id = '00000000-0000-0000-0000-000000027003';
select throws_ok(
  $$select public.claim_next_x_daily_judgement('00000000-0000-0000-0000-000000027003', '2026-08-01T00:03:00+08:00')$$,
  '42501', 'worker_not_authorized',
  'a Discord-only Worker cannot receive X judgement work'
);
update public.x_daily_judgement_runs
set status = 'queued', attempt = 0, lease_owner = null, lease_expires_at = null
where batch_id = (select id from public.x_collection_batches where scheduled_window_key = '2026-08-01T00:00+08:00');
update public.workers
set status = 'online', last_heartbeat_at = timezone('utc', now())
where id = '00000000-0000-0000-0000-000000027002';
create temporary table worker_b_claim as
select public.claim_next_x_daily_judgement('00000000-0000-0000-0000-000000027002', timezone('utc', now())) as payload;
select isnt((select payload->>'run_id' from worker_b_claim), null, 'an authorized X-capable Worker for another frozen source may claim the shared judgement');
select is((select payload->'batch'->>'coverage_status' from worker_b_claim), 'partial', 'the Worker receives partial rather than false complete coverage');

create temporary table mixed_day_context as
select public.get_x_daily_judgement_context(
  (select (payload->>'run_id')::uuid from worker_b_claim),
  (select (payload->>'attempt')::integer from worker_b_claim),
  '00000000-0000-0000-0000-000000027002'
) as payload;
select is(
  (select jsonb_array_length(payload->'sources'->0->'window_segments')::text from mixed_day_context),
  '1',
  'Worker context excludes a wrong-natural-date segment from the same range task'
);
select is(
  (select payload->'sources'->0->'window_segments'->0->>'id' from mixed_day_context),
  '00000000-0000-0000-0000-000000027031',
  'Worker context retains only the batch-natural-date segment'
);
select throws_ok(
  $$insert into public.x_daily_judgement_versions (
      batch_id, revision, coverage_status, input_snapshot, output, provider, model_reported, prompt_version, schema_version
    ) values (
      (select id from public.x_collection_batches where scheduled_window_key = '2026-08-01T00:00+08:00'),
      1, 'partial',
      '{"sources":[{"source_id":"00000000-0000-0000-0000-000000027011","display_name":"Current source A","settlement_status":"included","segments":[{"segment_id":"00000000-0000-0000-0000-000000027031","analysis_ids":[],"evidence_post_ids":[]},{"segment_id":"00000000-0000-0000-0000-000000027032","analysis_ids":[],"evidence_post_ids":[]}]}]}'::jsonb,
      '{"stock_viewpoints":[],"market_industry_viewpoints":[],"uncertainties":[]}'::jsonb,
      'mock', null, 'v2-x-cross-blogger-1', 'v2-x-cross-blogger'
    )$$,
  '22023', 'invalid_x_daily_judgement_snapshot',
  'immutable version authority rejects a wrong-natural-date segment even when the range task matches'
);
select is(
  (select public.complete_x_daily_judgement(
    (select (payload->>'run_id')::uuid from worker_b_claim),
    (select (payload->>'attempt')::integer from worker_b_claim),
    '00000000-0000-0000-0000-000000027002',
    '{"schema_version":"v2-x-cross-blogger","provider":"mock","model_reported":null,"prompt_version":"v2-x-cross-blogger-1","stock_viewpoints":[],"market_industry_viewpoints":[],"uncertainties":[]}'::jsonb
  )->>'status'),
  'succeeded',
  'completion persists the filtered immutable snapshot'
);
select is(
  (select jsonb_array_length(input_snapshot->'sources'->0->'segments')::text
   from public.x_daily_judgement_versions
   where batch_id = (select id from public.x_collection_batches where scheduled_window_key = '2026-08-01T00:00+08:00')
   order by revision desc limit 1),
  '1',
  'completion snapshot excludes the same-task wrong-day segment'
);
select is(
  (select input_snapshot->'sources'->0->'segments'->0->>'segment_id'
   from public.x_daily_judgement_versions
   where batch_id = (select id from public.x_collection_batches where scheduled_window_key = '2026-08-01T00:00+08:00')
   order by revision desc limit 1),
  '00000000-0000-0000-0000-000000027031',
  'completion snapshot retains only the correct natural-date segment'
);

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

select has_column(
  'public', 'x_collection_batches', 'snapshot_completeness',
  'batches record whether their frozen source universe is verified complete'
);
select lives_ok(
  $$insert into public.x_collection_batches (
      id, scheduled_window_key, natural_date, cutoff_at, settlement_deadline_at, status, snapshot_completeness
    ) values (
      '00000000-0000-0000-0000-000000027041', '2026-08-02T08:00+08:00', '2026-08-02',
      '2026-08-02T00:00:00Z', '2026-08-02T02:00:00Z', 'succeeded', 'legacy_unverified'
    )$$,
  'a pre-remediation incomplete source snapshot can be represented explicitly'
);
insert into public.x_collection_batch_sources (batch_id, source_id, source_display_name)
values (
  '00000000-0000-0000-0000-000000027041',
  '00000000-0000-0000-0000-000000027011',
  'Current source A'
);
insert into public.x_daily_judgement_runs (id, batch_id, status, available_at)
values (
  '00000000-0000-0000-0000-000000027042',
  '00000000-0000-0000-0000-000000027041',
  'queued', timezone('utc', now())
);
select is(
  (select snapshot_completeness from public.x_collection_batches
   where id = '00000000-0000-0000-0000-000000027041'),
  'legacy_unverified',
  'the incomplete historical batch carries an explicit legacy marker'
);
select is(
  (select public.settle_x_collection_batch(
    '00000000-0000-0000-0000-000000027041', timezone('utc', now())
  )->>'settled'),
  'false',
  'direct settlement also fails closed for a legacy-unverified source snapshot'
);
update public.source_collection_coverage
set coverage_through_at = '2026-08-02T00:00:00+08:00'
where source_id in (
  '00000000-0000-0000-0000-000000027011',
  '00000000-0000-0000-0000-000000027012'
);
update public.workers
set last_heartbeat_at = '2026-08-02T00:00:00Z'
where id = '00000000-0000-0000-0000-000000027001';
create temporary table legacy_batch_reuse as
select public.ensure_due_x_collection_batches(
  '00000000-0000-0000-0000-000000027001',
  '2026-08-02T08:01:00+08:00'
) as payload;
select is(
  (select jsonb_array_length(payload->'batches')::text from legacy_batch_reuse),
  '0',
  'an existing legacy-incomplete batch is not returned as a normal scheduled batch'
);
select is(
  (select jsonb_array_length(payload->'unavailable_batches')::text from legacy_batch_reuse),
  '1',
  'the scheduler explicitly reports the legacy batch as unavailable without filling current sources'
);
select is(
  (select status from public.x_collection_batches where id = '00000000-0000-0000-0000-000000027041'),
  'judgement_failed',
  'a legacy-incomplete batch cannot remain succeeded or complete'
);
update public.workers
set last_heartbeat_at = timezone('utc', now())
where id = '00000000-0000-0000-0000-000000027001';
select is(
  (select public.claim_next_x_daily_judgement(
    '00000000-0000-0000-0000-000000027001', timezone('utc', now())
  )::text),
  null,
  'legacy-incomplete judgement work is unavailable to Workers'
);

select has_function(
  'public',
  'assert_x_collection_batch_identity_migration_safe',
  array[]::text[],
  'migration exposes a reusable fail-closed legacy identity preflight'
);
alter table public.x_collection_batches drop constraint x_collection_batches_logical_date_check;
insert into public.x_collection_batches (
  id, scheduled_window_key, natural_date, cutoff_at, settlement_deadline_at, status
) values (
  '00000000-0000-0000-0000-000000027051', '2026-08-03T00:00+08:00', '2026-08-03',
  '2026-08-02T16:00:00Z', '2026-08-02T18:00:00Z', 'succeeded'
);
insert into public.x_daily_judgement_versions (
  batch_id, revision, coverage_status, input_snapshot, output, provider, model_reported, prompt_version, schema_version
) values (
  '00000000-0000-0000-0000-000000027051', 1, 'no_new_information',
  '{"sources":[]}'::jsonb,
  '{"stock_viewpoints":[],"market_industry_viewpoints":[],"uncertainties":[]}'::jsonb,
  'mock', null, 'v2-x-cross-blogger-1', 'v2-x-cross-blogger'
);
select throws_ok(
  $$select public.assert_x_collection_batch_identity_migration_safe()$$,
  '55000', 'unsafe_legacy_x_collection_batch_identity',
  'migration fails closed instead of re-dating a midnight batch with immutable version evidence'
);
select is(
  (select natural_date::text from public.x_collection_batches where id = '00000000-0000-0000-0000-000000027051'),
  '2026-08-03',
  'failed legacy preflight leaves historical version identity unchanged'
);

select * from finish();
rollback;
