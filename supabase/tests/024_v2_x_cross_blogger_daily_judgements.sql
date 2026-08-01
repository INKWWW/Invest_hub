begin;

select plan(32);

select has_table('public', 'x_collection_batches', 'scheduled X collection batches are persisted');
select has_table('public', 'x_collection_batch_sources', 'batch source snapshots are persisted');
select has_table('public', 'x_daily_judgement_runs', 'daily judgement work is persisted independently');
select has_table('public', 'x_daily_judgement_versions', 'daily judgement versions are persisted append-only');

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at)
values
  ('00000000-0000-0000-0000-000000024010', 'authenticated', 'authenticated', 'daily-judgement-admin@example.invalid', 'not-a-secret', now()),
  ('00000000-0000-0000-0000-000000024015', 'authenticated', 'authenticated', 'daily-judgement-user@example.invalid', 'not-a-secret', now());
insert into public.profiles (id, role, display_name)
values
  ('00000000-0000-0000-0000-000000024010', 'admin', 'Daily judgement admin'),
  ('00000000-0000-0000-0000-000000024015', 'user', 'Daily judgement user');
insert into public.workers (id, name, device_secret_hash, status, capabilities, last_heartbeat_at)
values (
  '00000000-0000-0000-0000-000000024001', 'daily-judgement-worker',
  'daily-judgement-worker-hash', 'online', array['x_sync'], '2026-07-24T00:00:00Z'
);

insert into public.sources (id, source_key, source_type, display_name, parameter_version, authorized_worker_id)
values
  ('00000000-0000-0000-0000-000000024011', 'daily-judgement-source-a', 'x', 'Frozen source A', 'v2-daily-judgement', '00000000-0000-0000-0000-000000024001'),
  ('00000000-0000-0000-0000-000000024012', 'daily-judgement-source-b', 'x', 'Frozen source B', 'v2-daily-judgement', '00000000-0000-0000-0000-000000024001'),
  ('00000000-0000-0000-0000-000000024013', 'daily-judgement-source-c', 'x', 'Later enabled source', 'v2-daily-judgement', '00000000-0000-0000-0000-000000024001');
insert into public.x_source_profiles (source_id, requested_handle, account_id, display_name, resolution_status, enabled)
values
  ('00000000-0000-0000-0000-000000024011', 'daily_source_a', 'daily_source_a', 'Frozen source A', 'resolved', true),
  ('00000000-0000-0000-0000-000000024012', 'daily_source_b', 'daily_source_b', 'Frozen source B', 'resolved', true),
  ('00000000-0000-0000-0000-000000024013', 'daily_source_c', 'daily_source_c', 'Later enabled source', 'resolved', false);
insert into public.source_collection_coverage (source_id, coverage_start_at, coverage_through_at)
values
  ('00000000-0000-0000-0000-000000024011', '2026-07-24T00:00:00+08:00', '2026-07-24T00:00:00+08:00'),
  ('00000000-0000-0000-0000-000000024012', '2026-07-24T00:00:00+08:00', '2026-07-24T00:00:00+08:00'),
  ('00000000-0000-0000-0000-000000024013', '2026-07-24T00:00:00+08:00', '2026-07-24T00:00:00+08:00');

create temporary table first_due_batch as
select public.ensure_due_x_collection_batches('00000000-0000-0000-0000-000000024001', '2026-07-24T00:01:00Z') as payload;

select is((select count(*)::text from public.x_collection_batches), '1', 'one scheduled cutoff creates one logical X collection batch');
select is((select count(*)::text from public.x_collection_batch_sources), '2', 'the batch freezes each enabled resolved source once');
select is((select count(*)::text from public.sync_tasks where collection_batch_id is not null), '2', 'each frozen source task links to the shared collection batch');

update public.sources set enabled = true where id = '00000000-0000-0000-0000-000000024013';
update public.x_source_profiles set enabled = true where source_id = '00000000-0000-0000-0000-000000024013';
create temporary table repeated_due_batch as
select public.ensure_due_x_collection_batches('00000000-0000-0000-0000-000000024001', '2026-07-24T00:01:00Z') as payload;

select is((select count(*)::text from public.x_collection_batches), '1', 'a repeated scheduler invocation reuses the scheduled batch');
select is((select count(*)::text from public.x_collection_batch_sources), '2', 'a later enabled source does not join an old frozen snapshot');

select throws_ok(
  $$insert into public.sync_tasks (
      task_type, source_id, parameter_version, requested_by, collection_scope, capture_range, author_profile_snapshot, x_source_snapshot, collection_batch_id
    ) values (
      'x_sync', '00000000-0000-0000-0000-000000024011', 'v2-daily-judgement', '00000000-0000-0000-0000-000000024010',
      '{"mode":"window"}'::jsonb,
      '{"mode":"window","trigger":"manual","timezone":"Asia/Shanghai","start_at":"2026-07-24T00:00:00Z","end_at":"2026-07-24T04:00:00Z","scheduled_window_key":null,"overlap_start_at":"2026-07-24T00:00:00Z"}'::jsonb,
      '[]'::jsonb,
      '{"source_type":"x","account_id":"daily_source_a","display_name":"Frozen source A","parameter_version":"v2-daily-judgement"}'::jsonb,
      (select id from public.x_collection_batches limit 1)
    )$$,
  '23514', 'invalid_x_collection_batch_task', 'manual X tasks cannot join a scheduled collection batch'
);

select throws_ok(
  $$insert into public.sync_tasks (
      task_type, source_id, parameter_version, collection_scope, capture_range, author_profile_snapshot, x_source_snapshot, collection_batch_id
    ) values (
      'x_sync', '00000000-0000-0000-0000-000000024011', 'v2-daily-judgement',
      '{"mode":"history"}'::jsonb, null, '[]'::jsonb,
      '{"source_type":"x","account_id":"daily_source_a","display_name":"Frozen source A","parameter_version":"v2-daily-judgement"}'::jsonb,
      (select id from public.x_collection_batches limit 1)
    )$$,
  '23514', 'invalid_x_collection_batch_task', 'history X tasks cannot join a scheduled collection batch'
);

update public.sync_tasks set status = 'succeeded'
where id = (select x_sync_task_id from public.x_collection_batch_sources where source_id = '00000000-0000-0000-0000-000000024011');
insert into public.x_daily_viewpoint_segments (
  source_id, natural_date, range_task_id, segment_version, occurred_from_at, occurred_through_at, window_viewpoints, post_analysis_refs, evidence_refs
) values (
  '00000000-0000-0000-0000-000000024011', '2026-07-24',
  (select x_sync_task_id from public.x_collection_batch_sources where source_id = '00000000-0000-0000-0000-000000024011'),
  1, '2026-07-24T00:00:00Z', '2026-07-24T00:00:00Z', '["fixture viewpoint"]'::jsonb,
  '[{"post_id":"fixture-post","analysis_version":1}]'::jsonb, '["fixture-post"]'::jsonb
);
update public.sync_tasks set status = 'succeeded'
where id = (select x_sync_task_id from public.x_collection_batch_sources where source_id = '00000000-0000-0000-0000-000000024012');
insert into public.task_attempts (task_id, attempt, worker_id, status, lease_expires_at, result, completed_at)
values (
  (select x_sync_task_id from public.x_collection_batch_sources where source_id = '00000000-0000-0000-0000-000000024012'),
  1, '00000000-0000-0000-0000-000000024001', 'succeeded', '2026-07-24T00:11:00Z', '{"no_new_data":true}'::jsonb, '2026-07-24T00:01:00Z'
);
create temporary table initial_settlement as
select public.settle_x_collection_batch((select id from public.x_collection_batches limit 1), '2026-07-24T00:02:00Z') as payload;

select is((select settlement_status from public.x_collection_batch_sources where source_id = '00000000-0000-0000-0000-000000024011'), 'included', 'a successful source with a persisted segment is included');
select is((select settlement_status from public.x_collection_batch_sources where source_id = '00000000-0000-0000-0000-000000024012'), 'no_new_information', 'a successful source with no_new_data is settled without invention');
select is((select status from public.x_daily_judgement_runs limit 1), 'queued', 'a batch with included input queues independent judgement work');

insert into public.x_collection_batches (id, scheduled_window_key, natural_date, cutoff_at, settlement_deadline_at, status)
values ('00000000-0000-0000-0000-000000024002', '2026-07-25T08:00+08:00', '2026-07-25', '2026-07-25T00:00:00Z', '2026-07-25T02:00:00Z', 'collecting');
insert into public.sync_tasks (
  id, task_type, source_id, status, parameter_version, collection_scope, capture_range, author_profile_snapshot, x_source_snapshot, collection_batch_id
) values
  ('00000000-0000-0000-0000-000000024101', 'x_sync', '00000000-0000-0000-0000-000000024011', 'succeeded', 'v2-daily-judgement',
    '{"mode":"window"}'::jsonb,
    '{"mode":"window","trigger":"scheduled","timezone":"Asia/Shanghai","start_at":"2026-07-24T16:00:00Z","end_at":"2026-07-25T00:00:00Z","scheduled_window_key":"2026-07-25T08:00+08:00","overlap_start_at":"2026-07-24T16:00:00Z"}'::jsonb,
    '[]'::jsonb, '{"source_type":"x","account_id":"daily_source_a","display_name":"Frozen source A","parameter_version":"v2-daily-judgement"}'::jsonb,
    '00000000-0000-0000-0000-000000024002'),
  ('00000000-0000-0000-0000-000000024102', 'x_sync', '00000000-0000-0000-0000-000000024013', 'failed', 'v2-daily-judgement',
    '{"mode":"window"}'::jsonb,
    '{"mode":"window","trigger":"scheduled","timezone":"Asia/Shanghai","start_at":"2026-07-24T16:00:00Z","end_at":"2026-07-25T00:00:00Z","scheduled_window_key":"2026-07-25T08:00+08:00","overlap_start_at":"2026-07-24T16:00:00Z"}'::jsonb,
    '[]'::jsonb, '{"source_type":"x","account_id":"daily_source_c","display_name":"Later enabled source","parameter_version":"v2-daily-judgement"}'::jsonb,
    '00000000-0000-0000-0000-000000024002');
insert into public.x_collection_batch_sources (batch_id, source_id, source_display_name, x_sync_task_id)
values
  ('00000000-0000-0000-0000-000000024002', '00000000-0000-0000-0000-000000024011', 'Frozen source A', '00000000-0000-0000-0000-000000024101'),
  ('00000000-0000-0000-0000-000000024002', '00000000-0000-0000-0000-000000024013', 'Later enabled source', '00000000-0000-0000-0000-000000024102');
insert into public.x_daily_viewpoint_segments (
  source_id, natural_date, range_task_id, segment_version, occurred_from_at, occurred_through_at, window_viewpoints, post_analysis_refs, evidence_refs
) values (
  '00000000-0000-0000-0000-000000024011', '2026-07-25', '00000000-0000-0000-0000-000000024101',
  1, '2026-07-24T16:00:00Z', '2026-07-24T16:00:00Z', '["fixture viewpoint"]'::jsonb,
  '[{"post_id":"fixture-post-2","analysis_version":1}]'::jsonb, '["fixture-post-2"]'::jsonb
);
create temporary table partial_settlement as
select public.settle_x_collection_batch('00000000-0000-0000-0000-000000024002', '2026-07-25T00:01:00Z') as payload;
select is((select settlement_status from public.x_collection_batch_sources where batch_id = '00000000-0000-0000-0000-000000024002' and source_id = '00000000-0000-0000-0000-000000024013'), 'excluded', 'a terminal source failure is excluded from the frozen batch');
select is((select payload->>'coverage_status' from partial_settlement), 'partial', 'an excluded source yields partial coverage');

insert into public.x_collection_batches (id, scheduled_window_key, natural_date, cutoff_at, settlement_deadline_at, status)
values ('00000000-0000-0000-0000-000000024003', '2026-07-25T12:00+08:00', '2026-07-25', '2026-07-25T04:00:00Z', '2026-07-25T06:00:00Z', 'collecting');
insert into public.sync_tasks (
  id, task_type, source_id, status, parameter_version, collection_scope, capture_range, author_profile_snapshot, x_source_snapshot, collection_batch_id
) values (
  '00000000-0000-0000-0000-000000024103', 'x_sync', '00000000-0000-0000-0000-000000024012', 'succeeded', 'v2-daily-judgement',
  '{"mode":"window"}'::jsonb,
  '{"mode":"window","trigger":"scheduled","timezone":"Asia/Shanghai","start_at":"2026-07-25T00:00:00Z","end_at":"2026-07-25T04:00:00Z","scheduled_window_key":"2026-07-25T12:00+08:00","overlap_start_at":"2026-07-25T00:00:00Z"}'::jsonb,
  '[]'::jsonb, '{"source_type":"x","account_id":"daily_source_b","display_name":"Frozen source B","parameter_version":"v2-daily-judgement"}'::jsonb,
  '00000000-0000-0000-0000-000000024003'
);
insert into public.x_collection_batch_sources (batch_id, source_id, source_display_name, x_sync_task_id)
values ('00000000-0000-0000-0000-000000024003', '00000000-0000-0000-0000-000000024012', 'Frozen source B', '00000000-0000-0000-0000-000000024103');
insert into public.task_attempts (task_id, attempt, worker_id, status, lease_expires_at, result, completed_at)
values ('00000000-0000-0000-0000-000000024103', 1, '00000000-0000-0000-0000-000000024001', 'succeeded', '2026-07-25T04:11:00Z', '{"no_new_data":true}'::jsonb, '2026-07-25T04:01:00Z');
create temporary table no_new_settlement as
select public.settle_x_collection_batch('00000000-0000-0000-0000-000000024003', '2026-07-25T04:01:00Z') as payload;
select is((select payload->>'coverage_status' from no_new_settlement), 'no_new_information', 'a fully checked no-new batch records no_new_information');
select is((select count(*)::text from public.x_daily_judgement_runs where batch_id = '00000000-0000-0000-0000-000000024003'), '0', 'a fully no-new batch does not queue model work');
select is((select coverage_status from public.x_daily_judgement_versions where batch_id = '00000000-0000-0000-0000-000000024003'), 'no_new_information', 'a fully no-new batch stores its no-new judgement version directly');

insert into public.x_collection_batches (id, scheduled_window_key, natural_date, cutoff_at, settlement_deadline_at, status)
values ('00000000-0000-0000-0000-000000024001', '2026-07-24T12:00+08:00', '2026-07-24', '2026-07-24T04:00:00Z', '2026-07-24T06:00:00Z', 'collecting');
select throws_ok(
  $$insert into public.x_collection_batch_sources (batch_id, source_id, source_display_name, x_sync_task_id)
    values ('00000000-0000-0000-0000-000000024001', '00000000-0000-0000-0000-000000024012', 'Wrong source',
      (select x_sync_task_id from public.x_collection_batch_sources
       where batch_id = (select id from public.x_collection_batches where scheduled_window_key = '2026-07-24T08:00+08:00')
         and source_id = '00000000-0000-0000-0000-000000024011'))$$,
  '23514', 'x_collection_batch_task_source_mismatch', 'a frozen source cannot point at another source task'
);
select throws_ok(
  $$insert into public.x_collection_batch_sources (batch_id, source_id, source_display_name)
    values ((select id from public.x_collection_batches where scheduled_window_key = '2026-07-24T08:00+08:00'), '00000000-0000-0000-0000-000000024011', 'Duplicate')$$,
  '23505', null, 'a source appears only once in a batch snapshot'
);
select throws_ok(
  $$update public.x_collection_batch_sources set source_display_name = 'Mutated' where source_id = '00000000-0000-0000-0000-000000024011'$$,
  '55000', 'x_collection_snapshot_immutable', 'frozen source display names are immutable'
);

insert into public.sources (id, source_key, source_type, display_name, parameter_version)
values ('00000000-0000-0000-0000-000000024014', 'daily-judgement-discord', 'discord', 'Discord fixture', 'v1');
select throws_ok(
  $$insert into public.sync_tasks (task_type, source_id, parameter_version, collection_scope, author_profile_snapshot, collection_batch_id)
    values ('discord_sync', '00000000-0000-0000-0000-000000024014', 'v1', '{"mode":"incremental"}'::jsonb, '[]'::jsonb,
      (select id from public.x_collection_batches limit 1))$$,
  '23514', 'invalid_x_collection_batch_task', 'non-X tasks cannot join X collection batches'
);
select throws_ok(
  $$insert into public.x_daily_judgement_runs (batch_id, status, available_at)
    values ((select id from public.x_collection_batches where scheduled_window_key = '2026-07-24T08:00+08:00'), 'queued', '2026-07-24T00:02:00Z')$$,
  '23505', null, 'a batch cannot have a second active judgement run'
);

select throws_ok(
  $$insert into public.x_daily_judgement_versions
      (batch_id, revision, coverage_status, input_snapshot, output, provider, prompt_version, schema_version)
    values ('00000000-0000-0000-0000-000000024001', 1, 'complete',
      '{"sources":[]}'::jsonb, '{"stock_viewpoints":[]}'::jsonb,
      'codex_cli', 'v2-x-cross-blogger-1', 'v2-x-cross-blogger')$$,
  '22023', 'invalid_x_daily_judgement_evidence', 'a judgement may not cite evidence outside its frozen input snapshot'
);

insert into public.x_daily_judgement_versions
  (batch_id, revision, coverage_status, input_snapshot, output, provider, prompt_version, schema_version)
values ('00000000-0000-0000-0000-000000024001', 1, 'no_new_information',
  '{"sources":[]}'::jsonb, '{"stock_viewpoints":[],"market_industry_viewpoints":[],"uncertainties":[]}'::jsonb,
  'codex_cli', 'v2-x-cross-blogger-1', 'v2-x-cross-blogger');
select throws_ok(
  $$insert into public.x_daily_judgement_versions
      (batch_id, revision, coverage_status, input_snapshot, output, provider, prompt_version, schema_version)
    values ('00000000-0000-0000-0000-000000024001', 3, 'no_new_information',
      '{"sources":[]}'::jsonb, '{"stock_viewpoints":[],"market_industry_viewpoints":[],"uncertainties":[]}'::jsonb,
      'codex_cli', 'v2-x-cross-blogger-1', 'v2-x-cross-blogger')$$,
  '23514', 'invalid_x_daily_judgement_revision', 'judgement revisions must be sequential per batch'
);
select throws_ok(
  $$update public.x_daily_judgement_versions set provider = 'mock' where batch_id = '00000000-0000-0000-0000-000000024001'$$,
  '55000', 'x_daily_judgement_version_immutable', 'judgement versions are append-only'
);
select throws_ok(
  $$delete from public.x_daily_judgement_versions where batch_id = '00000000-0000-0000-0000-000000024001'$$,
  '55000', 'x_daily_judgement_version_immutable', 'judgement versions cannot be deleted'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000024015', true);
select is((select count(*)::text from public.x_collection_batches), '0', 'authenticated non-admins cannot read collection batches');
select is((select count(*)::text from public.x_collection_batch_sources), '0', 'authenticated non-admins cannot read batch source snapshots');
select is((select count(*)::text from public.x_daily_judgement_runs), '0', 'authenticated non-admins cannot read judgement runs');
select is((select count(*)::text from public.x_daily_judgement_versions), '0', 'authenticated non-admins cannot read judgement versions');
reset role;

select * from finish();
rollback;
