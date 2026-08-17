begin;

select * from no_plan();

select has_table('public', 'x_collection_rebaseline_events', 'rebaseline events table exists');
select has_function(
  'public',
  'rebaseline_x_collection',
  array['uuid', 'integer', 'timestamptz'],
  'admin rebaseline function exists'
);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at)
values ('00000000-0000-0000-0000-000000057001', 'authenticated', 'authenticated', 'rebaseline-admin@example.invalid', 'not-a-secret', now())
on conflict (id) do nothing;
insert into public.profiles (id, role, display_name)
values ('00000000-0000-0000-0000-000000057001', 'admin', 'Rebaseline Admin')
on conflict (id) do update set role = excluded.role;
insert into public.workers (id, name, device_secret_hash, status, last_heartbeat_at, capabilities)
values ('00000000-0000-0000-0000-000000057099', 'rebaseline-worker', 'rebaseline-worker-secret-hash', 'online', now(), array['x_sync'])
on conflict (id) do update set status = excluded.status, capabilities = excluded.capabilities;

insert into public.sources (id, source_key, source_type, display_name, parameter_version, enabled, authorized_worker_id)
select source_id, 'rebaseline-source-' || right(source_id::text, 3), 'x', 'Rebaseline Source ' || right(source_id::text, 3), 'x-rebaseline-v1', true, '00000000-0000-0000-0000-000000057099'
from unnest(array[
  '00000000-0000-0000-0000-000000057011'::uuid,
  '00000000-0000-0000-0000-000000057012'::uuid,
  '00000000-0000-0000-0000-000000057013'::uuid,
  '00000000-0000-0000-0000-000000057014'::uuid,
  '00000000-0000-0000-0000-000000057015'::uuid,
  '00000000-0000-0000-0000-000000057016'::uuid,
  '00000000-0000-0000-0000-000000057017'::uuid,
  '00000000-0000-0000-0000-000000057018'::uuid
]) as source_id
on conflict (id) do nothing;
insert into public.x_source_profiles (source_id, requested_handle, account_id, display_name, resolution_status, enabled)
select id, 'rebaseline-' || right(id::text, 3), 'rebaseline-account-' || right(id::text, 3), display_name, 'resolved', true
from public.sources
where source_key like 'rebaseline-source-%'
on conflict (source_id) do update set resolution_status = excluded.resolution_status, enabled = excluded.enabled;
insert into public.source_collection_coverage (source_id, coverage_start_at, coverage_through_at)
select id, '2026-08-15T00:00:00+08:00', '2026-08-16T20:00:00+08:00'
from public.sources
where source_key like 'rebaseline-source-%'
on conflict (source_id) do update set coverage_start_at = excluded.coverage_start_at, coverage_through_at = excluded.coverage_through_at, last_completed_task_id = null;

insert into public.sync_tasks (
  id, task_type, source_id, status, parameter_version, rule_snapshot, collection_scope,
  capture_range, author_profile_snapshot, x_source_snapshot
)
values (
  '00000000-0000-0000-0000-000000057101', 'x_sync', '00000000-0000-0000-0000-000000057011', 'queued', 'x-rebaseline-v1',
  '{"version":0,"target_author_ids":[]}'::jsonb, '{"mode":"window"}'::jsonb,
  '{"mode":"window","trigger":"scheduled","timezone":"Asia/Shanghai","start_at":"2026-08-16T12:00:00+08:00","end_at":"2026-08-16T20:00:00+08:00","scheduled_window_key":"2026-08-16T20:00+08:00","overlap_start_at":"2026-08-16T12:00:00+08:00"}'::jsonb,
  '[]'::jsonb,
  '{"source_type":"x","account_id":"rebaseline-account-011","display_name":"Rebaseline Source 011","parameter_version":"x-rebaseline-v1"}'::jsonb
);
insert into public.sync_tasks (
  id, task_type, source_id, status, parameter_version, rule_snapshot, collection_scope,
  capture_range, author_profile_snapshot, x_source_snapshot
)
values (
  '00000000-0000-0000-0000-000000057102', 'x_sync', '00000000-0000-0000-0000-000000057012', 'succeeded', 'x-rebaseline-v1',
  '{"version":0,"target_author_ids":[]}'::jsonb, '{"mode":"window"}'::jsonb,
  '{"mode":"window","trigger":"scheduled","timezone":"Asia/Shanghai","start_at":"2026-08-16T12:00:00+08:00","end_at":"2026-08-16T20:00:00+08:00","scheduled_window_key":"2026-08-16T20:00+08:00","overlap_start_at":"2026-08-16T12:00:00+08:00"}'::jsonb,
  '[]'::jsonb,
  '{"source_type":"x","account_id":"rebaseline-account-012","display_name":"Rebaseline Source 012","parameter_version":"x-rebaseline-v1"}'::jsonb
);
insert into public.raw_messages (id, source_id, external_message_id, occurred_at, local_raw_ref, payload_hash, retention_expires_at)
values ('00000000-0000-0000-0000-000000057201', '00000000-0000-0000-0000-000000057011', 'rebaseline-raw-1', '2026-08-16T12:00:00+00:00', 'fixture/raw/rebaseline-1', 'fixture-raw-hash-1', '2027-08-16T12:00:00+00:00');
insert into public.canonical_messages (id, source_id, external_message_id, occurred_at, author_display, content, metadata)
values ('00000000-0000-0000-0000-000000057202', '00000000-0000-0000-0000-000000057011', 'rebaseline-canonical-1', '2026-08-16T12:00:00+00:00', 'Fixture Author', 'Synthetic canonical fact', '{"fixture":true}'::jsonb);
insert into public.x_post_contexts (canonical_message_id, post_type, post_url, context_status)
values ('00000000-0000-0000-0000-000000057202', 'original', 'https://x.com/rebaseline/status/57202', 'complete');
insert into public.x_post_analyses (canonical_message_id, analysis_version, blogger_viewpoint, arguments, uncertainties, evidence_refs)
values ('00000000-0000-0000-0000-000000057202', 1, 'Synthetic viewpoint', '["fixture argument"]'::jsonb, '[]'::jsonb, '["rebaseline-canonical-1"]'::jsonb);
insert into public.canonical_messages (id, source_id, external_message_id, occurred_at, author_display, content, metadata)
values ('00000000-0000-0000-0000-000000057204', '00000000-0000-0000-0000-000000057012', 'rebaseline-canonical-1', '2026-08-16T12:00:00+00:00', 'Fixture Author', 'Synthetic canonical fact for batch', '{"fixture":true}'::jsonb);
insert into public.x_post_contexts (canonical_message_id, post_type, post_url, context_status)
values ('00000000-0000-0000-0000-000000057204', 'original', 'https://x.com/rebaseline/status/57204', 'complete');
insert into public.x_post_analyses (canonical_message_id, analysis_version, blogger_viewpoint, arguments, uncertainties, evidence_refs)
values ('00000000-0000-0000-0000-000000057204', 1, 'Synthetic viewpoint', '["fixture argument"]'::jsonb, '[]'::jsonb, '["rebaseline-canonical-1"]'::jsonb);
insert into public.structured_runs (id, task_id, provider, parameter_version, output)
values ('00000000-0000-0000-0000-000000057203', '00000000-0000-0000-0000-000000057102', 'mock', 'x-rebaseline-v1', '{"fixture":true}'::jsonb);
insert into public.x_collection_batches (id, scheduled_window_key, natural_date, cutoff_at, settlement_deadline_at, status)
values ('00000000-0000-0000-0000-000000057301', '2026-08-16T20:00+08:00', '2026-08-16', '2026-08-16T12:00:00+00:00', '2026-08-16T14:00:00+00:00', 'succeeded');
update public.sync_tasks set collection_batch_id = '00000000-0000-0000-0000-000000057301'
where id = '00000000-0000-0000-0000-000000057102';
insert into public.x_collection_batch_sources (batch_id, source_id, source_display_name, x_sync_task_id, settlement_status, settled_at)
values ('00000000-0000-0000-0000-000000057301', '00000000-0000-0000-0000-000000057012', 'Rebaseline Source 012', '00000000-0000-0000-0000-000000057102', 'included', '2026-08-16T14:00:00+00:00');
insert into public.x_daily_viewpoint_segments (id, source_id, natural_date, range_task_id, segment_version, occurred_from_at, occurred_through_at, window_viewpoints, post_analysis_refs, evidence_refs)
values ('00000000-0000-0000-0000-000000057401', '00000000-0000-0000-0000-000000057012', '2026-08-16', '00000000-0000-0000-0000-000000057102', 1, '2026-08-16T12:00:00+00:00', '2026-08-16T12:00:00+00:00', '[{"fixture":true}]'::jsonb, '[{"post_id":"rebaseline-canonical-1","analysis_version":1}]'::jsonb, '["rebaseline-canonical-1"]'::jsonb);
insert into public.x_daily_judgement_runs (id, batch_id, status, attempt, available_at, failure_class, run_kind)
values ('00000000-0000-0000-0000-000000057501', '00000000-0000-0000-0000-000000057301', 'failed', 1, '2026-08-16T14:00:00+00:00', 'fixture_failure', 'initial');
insert into public.x_daily_judgement_versions (id, batch_id, revision, coverage_status, input_snapshot, output, provider, model_reported, prompt_version, schema_version)
values ('00000000-0000-0000-0000-000000057502', '00000000-0000-0000-0000-000000057301', 1, 'no_new_information', public.build_x_daily_judgement_input_snapshot('00000000-0000-0000-0000-000000057301'), '{"stock_viewpoints":[],"market_industry_viewpoints":[],"uncertainties":[]}'::jsonb, 'codex_cli', null, 'v2-x-cross-blogger-1', 'v2-x-cross-blogger');

select throws_ok(
  $$select public.rebaseline_x_collection('00000000-0000-0000-0000-000000057001', 7, '2026-08-17T00:00:00+08:00'::timestamptz);$$,
  'P0001', 'x_collection_rebaseline_source_count', 'source-count drift fails closed'
);
select throws_ok(
  $$select public.rebaseline_x_collection('00000000-0000-0000-0000-000000057001', 8, '2026-08-17T08:00:00+08:00'::timestamptz);$$,
  'P0001', 'x_collection_rebaseline_target', 'only the fixed Shanghai baseline is accepted'
);

update public.sync_tasks
set status = 'leased', lease_owner = '00000000-0000-0000-0000-000000057099', lease_expires_at = '2099-01-01T00:00:00Z'
where id = '00000000-0000-0000-0000-000000057101';
select throws_ok(
  $$select public.rebaseline_x_collection('00000000-0000-0000-0000-000000057001', 8, '2026-08-17T00:00:00+08:00'::timestamptz);$$,
  'P0001', 'x_collection_rebaseline_active_lease', 'active leases reject the whole transaction'
);
select is((select count(*)::integer from public.x_collection_rebaseline_events), 0, 'active-lease rejection writes no event');
select is((select coverage_through_at::text from public.source_collection_coverage where source_id = '00000000-0000-0000-0000-000000057011'), '2026-08-16 12:00:00+00', 'active-lease rejection leaves old coverage unchanged');
update public.sync_tasks
set status = 'queued', lease_owner = null, lease_expires_at = null
where id = '00000000-0000-0000-0000-000000057101';

insert into public.task_attempts (task_id, attempt, worker_id, status, lease_expires_at, started_at)
values ('00000000-0000-0000-0000-000000057101', 1, '00000000-0000-0000-0000-000000057099', 'leased', '2099-01-01T00:00:00+00:00', '2026-08-16T12:00:00+00:00');
select throws_ok(
  $$select public.rebaseline_x_collection('00000000-0000-0000-0000-000000057001', 8, '2026-08-17T00:00:00+08:00'::timestamptz);$$,
  'P0001', 'x_collection_rebaseline_active_lease', 'active task-attempt leases reject the whole transaction even without a task lease'
);
select is((select count(*)::integer from public.x_collection_rebaseline_events), 0, 'active attempt rejection writes no event');
select is((select coverage_through_at::text from public.source_collection_coverage where source_id = '00000000-0000-0000-0000-000000057011'), '2026-08-16 12:00:00+00', 'active attempt rejection leaves old coverage unchanged');
update public.task_attempts
set status = 'retryable_failed', completed_at = '2026-08-16T13:00:00+00:00', lease_expires_at = '2026-08-16T12:30:00+00:00'
where task_id = '00000000-0000-0000-0000-000000057101' and attempt = 1;

create function pg_temp.rebaseline_fact_snapshot()
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'sync_tasks', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'status', status, 'capture_range', capture_range, 'collection_batch_id', collection_batch_id) order by id) from public.sync_tasks where source_id in ('00000000-0000-0000-0000-000000057011'::uuid, '00000000-0000-0000-0000-000000057012'::uuid)), '[]'::jsonb),
    'task_attempts', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'task_id', task_id, 'attempt', attempt, 'status', status, 'lease_expires_at', lease_expires_at, 'completed_at', completed_at) order by id) from public.task_attempts where task_id in ('00000000-0000-0000-0000-000000057101'::uuid, '00000000-0000-0000-0000-000000057102'::uuid)), '[]'::jsonb),
    'raw_messages', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'source_id', source_id, 'external_message_id', external_message_id, 'payload_hash', payload_hash) order by id) from public.raw_messages where source_id = '00000000-0000-0000-0000-000000057011'::uuid), '[]'::jsonb),
    'canonical_messages', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'source_id', source_id, 'external_message_id', external_message_id, 'content', content, 'metadata', metadata) order by id) from public.canonical_messages where source_id = '00000000-0000-0000-0000-000000057011'::uuid), '[]'::jsonb),
    'post_contexts', coalesce((select jsonb_agg(jsonb_build_object('canonical_message_id', canonical_message_id, 'post_type', post_type, 'post_url', post_url, 'context_status', context_status) order by canonical_message_id) from public.x_post_contexts where canonical_message_id in ('00000000-0000-0000-0000-000000057202'::uuid, '00000000-0000-0000-0000-000000057204'::uuid)), '[]'::jsonb),
    'post_analyses', coalesce((select jsonb_agg(jsonb_build_object('canonical_message_id', canonical_message_id, 'analysis_version', analysis_version, 'blogger_viewpoint', blogger_viewpoint, 'arguments', arguments, 'evidence_refs', evidence_refs) order by canonical_message_id, analysis_version) from public.x_post_analyses where canonical_message_id in ('00000000-0000-0000-0000-000000057202'::uuid, '00000000-0000-0000-0000-000000057204'::uuid)), '[]'::jsonb),
    'batches', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'scheduled_window_key', scheduled_window_key, 'status', status) order by id) from public.x_collection_batches where id = '00000000-0000-0000-0000-000000057301'::uuid), '[]'::jsonb),
    'segments', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'source_id', source_id, 'range_task_id', range_task_id, 'segment_version', segment_version, 'window_viewpoints', window_viewpoints, 'post_analysis_refs', post_analysis_refs, 'evidence_refs', evidence_refs) order by id) from public.x_daily_viewpoint_segments where id = '00000000-0000-0000-0000-000000057401'::uuid), '[]'::jsonb),
    'judgement_runs', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'batch_id', batch_id, 'status', status, 'attempt', attempt, 'failure_class', failure_class, 'run_kind', run_kind) order by id) from public.x_daily_judgement_runs where id = '00000000-0000-0000-0000-000000057501'::uuid), '[]'::jsonb),
    'judgement_versions', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'batch_id', batch_id, 'revision', revision, 'coverage_status', coverage_status, 'input_snapshot', input_snapshot, 'output', output, 'provider', provider, 'prompt_version', prompt_version, 'schema_version', schema_version) order by id) from public.x_daily_judgement_versions where id = '00000000-0000-0000-0000-000000057502'::uuid), '[]'::jsonb)
  );
$$;
create temporary table rebaseline_fact_snapshot_before as
select pg_temp.rebaseline_fact_snapshot() as snapshot;

select ok((public.rebaseline_x_collection(
  '00000000-0000-0000-0000-000000057001', 8, '2026-08-17T00:00:00+08:00'::timestamptz
)->>'idempotent')::boolean = false, 'first rebaseline creates a new epoch');
select is((select count(*)::integer from public.x_collection_rebaseline_events), 8, 'one immutable event is recorded per active source');
select is((select count(*)::integer from public.x_collection_rebaseline_events where reason_code = 'x_collection_demo_rebaseline_2026_08_17'), 8, 'reason code is fixed');
select is((select count(*)::integer from public.source_collection_coverage where coverage_start_at = '2026-08-17T00:00:00+08:00' and coverage_through_at = '2026-08-17T00:00:00+08:00' and last_completed_task_id is null), 8, 'all coverage rows move atomically to the new baseline');
select is((select old_coverage_through_at::text from public.x_collection_rebaseline_events where source_id = '00000000-0000-0000-0000-000000057011'), '2026-08-16 12:00:00+00', 'event retains the old through waterline');
select is((select old_last_completed_task_id from public.x_collection_rebaseline_events where source_id = '00000000-0000-0000-0000-000000057011'), null, 'event retains the old completion pointer');
select is((select status from public.sync_tasks where id = '00000000-0000-0000-0000-000000057101'), 'queued', 'old task is retained unchanged');
select is(pg_temp.rebaseline_fact_snapshot(), (select snapshot from rebaseline_fact_snapshot_before), 'rebaseline preserves task, attempt, raw, canonical, analysis, batch, segment, judgement run, and judgement version facts');

select ok((public.rebaseline_x_collection(
  '00000000-0000-0000-0000-000000057001', 8, '2026-08-17T00:00:00+08:00'::timestamptz
)->>'idempotent')::boolean = true, 'repeating the same baseline is idempotent');
select is((select count(*)::integer from public.x_collection_rebaseline_events), 8, 'idempotence does not duplicate events');
select throws_ok(
  $$update public.x_collection_rebaseline_events set reason_code = 'changed' where source_id = '00000000-0000-0000-0000-000000057011';$$,
  '55000', 'x_collection_rebaseline_immutable', 'rebaseline events reject updates'
);
select throws_ok(
  $$delete from public.x_collection_rebaseline_events where source_id = '00000000-0000-0000-0000-000000057011';$$,
  '55000', 'x_collection_rebaseline_immutable', 'rebaseline events reject deletes'
);
select throws_ok(
  $$select public.rebaseline_x_collection('00000000-0000-0000-0000-000000057001', 8, '2026-08-18T00:00:00+08:00'::timestamptz);$$,
  'P0001', 'x_collection_rebaseline_target', 'a different target cannot create a second epoch'
);

select is(public.claim_next_task('00000000-0000-0000-0000-000000057099', '2026-08-17T00:01:00+08:00'::timestamptz), null, 'a covered old queued task cannot be claimed');
select is((public.create_windowed_x_sync_task(
  '00000000-0000-0000-0000-000000057012', 'x-rebaseline-v1', null, 'scheduled',
  '2026-08-17T08:00:00+08:00'::timestamptz, '2026-08-17T08:00+08:00'
)->'capture_range'->>'start_at'), '2026-08-16T16:00:00+00:00', 'the first new task starts at the rebaseline boundary');
select is((public.create_windowed_x_sync_task(
  '00000000-0000-0000-0000-000000057011', 'x-rebaseline-v1', null, 'scheduled',
  '2026-08-17T08:00:00+08:00'::timestamptz, '2026-08-17T08:00+08:00'
)->'capture_range'->>'start_at'), '2026-08-16T16:00:00+00:00', 'an old queued task does not block a new epoch task');
select is((select count(*)::integer from public.sync_tasks where id = '00000000-0000-0000-0000-000000057101'), 1, 'old task row remains present');

select * from finish();
rollback;
