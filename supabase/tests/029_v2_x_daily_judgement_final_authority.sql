begin;

select plan(65);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at)
values ('00000000-0000-0000-0000-000000029010', 'authenticated', 'authenticated', 'final-authority-admin@example.invalid', 'not-a-secret', now());
insert into public.profiles (id, role, display_name)
values ('00000000-0000-0000-0000-000000029010', 'admin', 'Final authority admin');

insert into public.workers (id, name, device_secret_hash, status, last_heartbeat_at, capabilities)
values
  ('00000000-0000-0000-0000-000000029001', 'final-authority-fresh', 'final-authority-fresh-hash', 'online', '2026-07-31T16:00:00Z', array['x_sync']),
  ('00000000-0000-0000-0000-000000029002', 'final-authority-enrolled', 'final-authority-enrolled-hash', 'enrolled', '2026-07-31T16:00:00Z', array['x_sync']),
  ('00000000-0000-0000-0000-000000029003', 'final-authority-stale', 'final-authority-stale-hash', 'online', '2026-07-31T15:58:00Z', array['x_sync']),
  ('00000000-0000-0000-0000-000000029004', 'final-authority-unauthorized', 'final-authority-unauthorized-hash', 'online', '2026-07-31T16:00:00Z', array['x_sync']);

insert into public.sources (id, source_key, source_type, display_name, parameter_version, authorized_worker_id)
values
  ('d0000000-0000-4000-8000-000000029101', 'final-authority-source-a', 'x', 'Final source A', 'v2-final-authority', '00000000-0000-0000-0000-000000029001'),
  ('00000000-0000-0000-0000-000000029102', 'final-authority-source-enrolled', 'x', 'Final source enrolled', 'v2-final-authority', '00000000-0000-0000-0000-000000029002'),
  ('00000000-0000-0000-0000-000000029103', 'final-authority-source-stale', 'x', 'Final source stale', 'v2-final-authority', '00000000-0000-0000-0000-000000029003'),
  ('00000000-0000-0000-0000-000000029104', 'final-authority-source-b', 'x', 'Final source B', 'v2-final-authority', '00000000-0000-0000-0000-000000029001');
insert into public.x_source_profiles (source_id, requested_handle, account_id, display_name, resolution_status)
values
  ('d0000000-0000-4000-8000-000000029101', 'final_authority_a', 'final_authority_a', 'Final source A', 'resolved'),
  ('00000000-0000-0000-0000-000000029102', 'final_authority_enrolled', 'final_authority_enrolled', 'Final source enrolled', 'resolved'),
  ('00000000-0000-0000-0000-000000029103', 'final_authority_stale', 'final_authority_stale', 'Final source stale', 'resolved'),
  ('00000000-0000-0000-0000-000000029104', 'final_authority_b', 'final_authority_b', 'Final source B', 'resolved');
insert into public.source_collection_coverage (source_id, coverage_start_at, coverage_through_at)
values
  ('d0000000-0000-4000-8000-000000029101', '2026-07-31T00:00:00+08:00', '2026-07-31T20:00:00+08:00'),
  ('00000000-0000-0000-0000-000000029102', '2026-07-31T00:00:00+08:00', '2026-07-31T20:00:00+08:00'),
  ('00000000-0000-0000-0000-000000029103', '2026-07-31T00:00:00+08:00', '2026-07-31T20:00:00+08:00'),
  ('00000000-0000-0000-0000-000000029104', '2026-07-31T00:00:00+08:00', '2026-07-31T20:00:00+08:00');

select throws_ok(
  $$select public.ensure_due_x_collection_batches('00000000-0000-0000-0000-000000029002', '2026-08-01T00:01:00+08:00')$$,
  '42501', 'worker_not_authorized', 'an enrolled Worker cannot ensure judgement batches'
);
select throws_ok(
  $$select public.ensure_due_x_collection_batches('00000000-0000-0000-0000-000000029003', '2026-08-01T00:01:00+08:00')$$,
  '42501', 'worker_not_authorized', 'an online Worker with a stale heartbeat cannot ensure judgement batches'
);
select lives_ok(
  $$select public.ensure_due_x_collection_batches('00000000-0000-0000-0000-000000029001', '2026-08-01T00:01:00+08:00')$$,
  'an online X Worker with a heartbeat inside two minutes can ensure judgement batches'
);
update public.workers
set last_heartbeat_at = '2099-01-01T00:00:00Z'
where id = '00000000-0000-0000-0000-000000029001';
select throws_ok(
  $$select public.ensure_due_x_collection_batches('00000000-0000-0000-0000-000000029001', '2026-08-01T00:01:00+08:00')$$,
  '42501', 'worker_not_authorized', 'a far-future heartbeat cannot keep a disconnected Worker eligible'
);
update public.workers
set last_heartbeat_at = '2026-07-31T16:00:00Z'
where id = '00000000-0000-0000-0000-000000029001';

update public.workers
set last_heartbeat_at = case
  when id = '00000000-0000-0000-0000-000000029003' then now() - interval '3 minutes'
  else now()
end
where id in (
  '00000000-0000-0000-0000-000000029001',
  '00000000-0000-0000-0000-000000029002',
  '00000000-0000-0000-0000-000000029003'
);

insert into public.x_collection_batches (id, scheduled_window_key, natural_date, cutoff_at, settlement_deadline_at, status)
values
  ('00000000-0000-0000-0000-000000029201', '2026-08-02T08:00+08:00', '2026-08-02', '2026-08-02T00:00:00Z', '2026-08-02T02:00:00Z', 'judgement_pending'),
  ('00000000-0000-0000-0000-000000029202', '2026-08-02T12:00+08:00', '2026-08-02', '2026-08-02T04:00:00Z', '2026-08-02T06:00:00Z', 'judgement_pending'),
  ('00000000-0000-0000-0000-000000029203', '2026-08-02T16:00+08:00', '2026-08-02', '2026-08-02T08:00:00Z', '2026-08-02T10:00:00Z', 'judgement_pending');
insert into public.x_collection_batch_sources (batch_id, source_id, source_display_name, settlement_status, settled_at)
values
  ('00000000-0000-0000-0000-000000029201', '00000000-0000-0000-0000-000000029102', 'Final source enrolled', 'included', now()),
  ('00000000-0000-0000-0000-000000029202', '00000000-0000-0000-0000-000000029103', 'Final source stale', 'included', now()),
  ('00000000-0000-0000-0000-000000029203', 'd0000000-0000-4000-8000-000000029101', 'Final source A', 'included', now());
insert into public.x_daily_judgement_runs (id, batch_id, status, attempt, available_at)
values
  ('00000000-0000-0000-0000-000000029301', '00000000-0000-0000-0000-000000029201', 'queued', 0, '2026-07-31T16:00:00Z'),
  ('00000000-0000-0000-0000-000000029302', '00000000-0000-0000-0000-000000029202', 'queued', 0, '2026-07-31T16:00:00Z'),
  ('00000000-0000-0000-0000-000000029303', '00000000-0000-0000-0000-000000029203', 'queued', 0, '2026-07-31T16:00:00Z');

select throws_ok(
  $$select public.claim_next_x_daily_judgement('00000000-0000-0000-0000-000000029002', now())$$,
  '42501', 'worker_not_authorized', 'an enrolled Worker cannot claim judgement work'
);
select is((select status from public.x_daily_judgement_runs where id = '00000000-0000-0000-0000-000000029301'), 'queued', 'enrolled Worker rejection leaves its run queued');
select throws_ok(
  $$select public.claim_next_x_daily_judgement('00000000-0000-0000-0000-000000029003', now())$$,
  '42501', 'worker_not_authorized', 'a stale online Worker cannot claim judgement work'
);
select is((select status from public.x_daily_judgement_runs where id = '00000000-0000-0000-0000-000000029302'), 'queued', 'stale Worker rejection leaves its run queued');
update public.workers
set last_heartbeat_at = '2099-01-01T00:00:00Z'
where id = '00000000-0000-0000-0000-000000029001';
create function pg_temp.expect_future_claim_rejected()
returns void language plpgsql as $$
begin
  perform public.claim_next_x_daily_judgement('00000000-0000-0000-0000-000000029001', now());
  raise exception 'unexpected_future_claim' using errcode = 'P0001';
end;
$$;
select throws_ok(
  $$select pg_temp.expect_future_claim_rejected()$$,
  '42501', 'worker_not_authorized', 'a far-future heartbeat cannot claim judgement work'
);
select is((select status from public.x_daily_judgement_runs where id = '00000000-0000-0000-0000-000000029303'), 'queued', 'future-heartbeat rejection leaves its run queued');
update public.workers
set last_heartbeat_at = now()
where id = '00000000-0000-0000-0000-000000029001';
create temporary table fresh_claim as
select public.claim_next_x_daily_judgement('00000000-0000-0000-0000-000000029001', now()) as payload;
select is((select payload->>'run_id' from fresh_claim), '00000000-0000-0000-0000-000000029303', 'a fresh online Worker claims its authorized judgement run');
select is(
  (select public.get_x_daily_judgement_context(
    '00000000-0000-0000-0000-000000029303', 1, '00000000-0000-0000-0000-000000029001'
  )->>'batch_id'),
  '00000000-0000-0000-0000-000000029203',
  'the frozen Worker context exposes its batch identity for opaque-token validation'
);

insert into public.x_collection_batches (id, scheduled_window_key, natural_date, cutoff_at, settlement_deadline_at, status)
values ('00000000-0000-0000-0000-000000029204', '2026-08-03T08:00+08:00', '2026-08-03', '2026-08-03T00:00:00Z', '2026-08-03T02:00:00Z', 'succeeded');
insert into public.x_collection_batch_sources (batch_id, source_id, source_display_name, settlement_status, settled_at)
values ('00000000-0000-0000-0000-000000029204', 'd0000000-0000-4000-8000-000000029101', 'Final source A', 'no_new_information', now());
insert into public.x_daily_judgement_versions
  (batch_id, revision, coverage_status, input_snapshot, output, provider, prompt_version, schema_version)
values (
  '00000000-0000-0000-0000-000000029204', 1, 'no_new_information',
  '{"sources":[{"source_id":"d0000000-0000-4000-8000-000000029101","display_name":"Final source A","settlement_status":"no_new_information","segments":[]}]}'::jsonb,
  '{"stock_viewpoints":[],"market_industry_viewpoints":[],"uncertainties":[]}'::jsonb,
  'codex_cli', 'v2-x-cross-blogger-1', 'v2-x-cross-blogger'
);
select throws_ok(
  $$select public.regenerate_x_daily_judgement('00000000-0000-0000-0000-000000029204', '00000000-0000-0000-0000-000000029010')$$,
  '22023', 'x_daily_judgement_regeneration_no_new_information', 'a no-new batch cannot queue regeneration'
);
select is((select count(*)::text from public.x_daily_judgement_runs where batch_id = '00000000-0000-0000-0000-000000029204'), '0', 'no-new regeneration rejection creates no Provider run');
select is((select status from public.x_collection_batches where id = '00000000-0000-0000-0000-000000029204'), 'succeeded', 'no-new regeneration rejection preserves the succeeded batch');
select is((select coverage_status from public.x_daily_judgement_versions where batch_id = '00000000-0000-0000-0000-000000029204'), 'no_new_information', 'no-new regeneration rejection preserves version coverage');
select is((select coverage_through_at::text from public.source_collection_coverage where source_id = 'd0000000-0000-4000-8000-000000029101'), '2026-07-31 12:00:00+00', 'no-new regeneration rejection preserves source coverage');
select is((select count(*)::text from public.x_daily_judgement_versions where batch_id = '00000000-0000-0000-0000-000000029204'), '1', 'no-new regeneration rejection preserves the one immutable version');

insert into public.x_daily_judgement_runs
  (id, batch_id, status, attempt, run_kind, requested_by, available_at)
values (
  '00000000-0000-0000-0000-000000029304', '00000000-0000-0000-0000-000000029204',
  'queued', 0, 'regeneration', '00000000-0000-0000-0000-000000029010', now()
);
create temporary table legacy_no_new_claim as
select public.claim_next_x_daily_judgement('00000000-0000-0000-0000-000000029001', now()) as payload;
select is((select payload from legacy_no_new_claim), null::jsonb, 'claim never returns a legacy queued no-new regeneration');
select is(
  (select status || '|' || coalesce(failure_class, '') || '|' || attempt::text
   from public.x_daily_judgement_runs where id = '00000000-0000-0000-0000-000000029304'),
  'failed|schema_error|0',
  'claim terminalizes a legacy queued no-new regeneration without incrementing its attempt'
);
select is(
  (select count(*)::text from public.x_daily_judgement_versions where batch_id = '00000000-0000-0000-0000-000000029204'),
  '1',
  'legacy queued-run cleanup preserves the immutable no-new version'
);

insert into public.x_collection_batches (id, scheduled_window_key, natural_date, cutoff_at, settlement_deadline_at, status)
values ('00000000-0000-0000-0000-000000029206', '2026-08-03T12:00+08:00', '2026-08-03', '2026-08-03T04:00:00Z', '2026-08-03T06:00:00Z', 'succeeded');
insert into public.x_collection_batch_sources (batch_id, source_id, source_display_name, settlement_status, settled_at)
values ('00000000-0000-0000-0000-000000029206', 'd0000000-0000-4000-8000-000000029101', 'Final source A', 'no_new_information', now());
insert into public.x_daily_judgement_versions
  (batch_id, revision, coverage_status, input_snapshot, output, provider, prompt_version, schema_version)
values (
  '00000000-0000-0000-0000-000000029206', 1, 'no_new_information',
  '{"sources":[{"source_id":"d0000000-0000-4000-8000-000000029101","display_name":"Final source A","settlement_status":"no_new_information","segments":[]}]}'::jsonb,
  '{"stock_viewpoints":[],"market_industry_viewpoints":[],"uncertainties":[]}'::jsonb,
  'codex_cli', 'v2-x-cross-blogger-1', 'v2-x-cross-blogger'
);
insert into public.x_daily_judgement_runs
  (id, batch_id, status, attempt, run_kind, requested_by, lease_owner, lease_expires_at, available_at)
values (
  '00000000-0000-0000-0000-000000029306', '00000000-0000-0000-0000-000000029206',
  'leased', 1, 'regeneration', '00000000-0000-0000-0000-000000029010',
  '00000000-0000-0000-0000-000000029001', now() + interval '1 hour', now()
);
select throws_ok(
  $$select public.complete_x_daily_judgement(
    '00000000-0000-0000-0000-000000029306', 1, '00000000-0000-0000-0000-000000029001',
    '{"schema_version":"v2-x-cross-blogger","provider":"codex_cli","model_reported":null,"prompt_version":"v2-x-cross-blogger-1","stock_viewpoints":[],"market_industry_viewpoints":[],"uncertainties":[]}'::jsonb
  )$$,
  '22023', 'x_daily_judgement_no_provider_input', 'DB completion rejects a legacy leased no-new regeneration before writing'
);
select is((select status from public.x_daily_judgement_runs where id = '00000000-0000-0000-0000-000000029306'), 'leased', 'rejected direct completion does not mutate the legacy lease');
select is(
  (select count(*)::text from public.x_daily_judgement_versions where batch_id = '00000000-0000-0000-0000-000000029206'),
  '1',
  'rejected direct completion cannot append a complete version to a no-new batch'
);
create temporary table legacy_leased_cleanup as
select public.claim_next_x_daily_judgement('00000000-0000-0000-0000-000000029001', now()) as payload;
select is((select payload from legacy_leased_cleanup), null::jsonb, 'claim cleanup does not return a legacy leased no-new regeneration');
select is(
  (select status || '|' || coalesce(failure_class, '') || '|' || attempt::text || '|' || coalesce(lease_owner::text, '')
   from public.x_daily_judgement_runs where id = '00000000-0000-0000-0000-000000029306'),
  'failed|schema_error|1|',
  'claim cleanup terminalizes a legacy lease without changing its attempt or retaining its owner'
);

insert into public.x_collection_batches (id, scheduled_window_key, natural_date, cutoff_at, settlement_deadline_at, status)
values ('00000000-0000-0000-0000-000000029207', '2026-08-03T16:00+08:00', '2026-08-03', '2026-08-03T08:00:00Z', '2026-08-03T10:00:00Z', 'succeeded');
insert into public.x_collection_batch_sources (batch_id, source_id, source_display_name, settlement_status, settled_at)
values ('00000000-0000-0000-0000-000000029207', '00000000-0000-0000-0000-000000029104', 'Final source B frozen', 'included', now());
insert into public.x_daily_judgement_versions
  (batch_id, revision, coverage_status, input_snapshot, output, provider, prompt_version, schema_version)
values (
  '00000000-0000-0000-0000-000000029207', 1, 'complete',
  public.build_x_daily_judgement_input_snapshot('00000000-0000-0000-0000-000000029207'),
  '{"stock_viewpoints":[],"market_industry_viewpoints":[],"uncertainties":[]}'::jsonb,
  'codex_cli', 'v2-x-cross-blogger-1', 'v2-x-cross-blogger'
);
insert into public.x_daily_judgement_runs
  (id, batch_id, status, attempt, run_kind, requested_by, available_at)
values (
  '00000000-0000-0000-0000-000000029307', '00000000-0000-0000-0000-000000029207',
  'queued', 0, 'regeneration', '00000000-0000-0000-0000-000000029010', now()
);
create temporary table archived_claim_before as
select
  (select to_jsonb(batch_source) from public.x_collection_batch_sources batch_source where batch_id = '00000000-0000-0000-0000-000000029207') as frozen_snapshot,
  (select input_snapshot from public.x_daily_judgement_versions where batch_id = '00000000-0000-0000-0000-000000029207') as judgement_input,
  (select coverage_through_at from public.source_collection_coverage where source_id = '00000000-0000-0000-0000-000000029104') as coverage_through_at;
update public.sources set enabled = false where id in (
  'd0000000-0000-4000-8000-000000029101',
  '00000000-0000-0000-0000-000000029104'
);
update public.x_source_profiles set enabled = false where source_id in (
  'd0000000-0000-4000-8000-000000029101',
  '00000000-0000-0000-0000-000000029104'
);
update public.workers set last_heartbeat_at = now() where id in (
  '00000000-0000-0000-0000-000000029001',
  '00000000-0000-0000-0000-000000029004'
);
select throws_ok(
  $$select public.ensure_due_x_collection_batches('00000000-0000-0000-0000-000000029001', now())$$,
  '42501', 'worker_not_authorized', 'new batch ensure still requires a current enabled and resolved source'
);
select throws_ok(
  $$select public.claim_next_x_daily_judgement('00000000-0000-0000-0000-000000029004', now())$$,
  '42501', 'worker_not_authorized', 'an online fresh Worker without X authorization remains rejected'
);
select is((select status from public.x_daily_judgement_runs where id = '00000000-0000-0000-0000-000000029307'), 'queued', 'unauthorized rejection leaves the archived-source run queued');
select lives_ok(
  $$select public.claim_next_x_daily_judgement('00000000-0000-0000-0000-000000029001', now())$$,
  'an online fresh Worker can claim its frozen batch after source and profile archive'
);
select is(
  (select status || '|' || lease_owner::text || '|' || attempt::text from public.x_daily_judgement_runs where id = '00000000-0000-0000-0000-000000029307'),
  'leased|00000000-0000-0000-0000-000000029001|1',
  'the archived-source queued run is leased only to its authorized Worker'
);
select is(
  (select to_jsonb(batch_source) from public.x_collection_batch_sources batch_source where batch_id = '00000000-0000-0000-0000-000000029207'),
  (select frozen_snapshot from archived_claim_before),
  'claim after archive preserves the frozen batch-source snapshot'
);
select is(
  (select input_snapshot from public.x_daily_judgement_versions where batch_id = '00000000-0000-0000-0000-000000029207'),
  (select judgement_input from archived_claim_before),
  'claim after archive preserves the immutable judgement input'
);
select is(
  (select coverage_through_at from public.source_collection_coverage where source_id = '00000000-0000-0000-0000-000000029104'),
  (select coverage_through_at from archived_claim_before),
  'claim after archive preserves source collection coverage'
);
update public.sources set enabled = true where id in (
  'd0000000-0000-4000-8000-000000029101',
  '00000000-0000-0000-0000-000000029104'
);
update public.x_source_profiles set enabled = true where source_id in (
  'd0000000-0000-4000-8000-000000029101',
  '00000000-0000-0000-0000-000000029104'
);

insert into public.x_collection_batches (id, scheduled_window_key, natural_date, cutoff_at, settlement_deadline_at, status)
values ('a0000000-0000-4000-8000-000000029205', '2026-08-04T16:00+08:00', '2026-08-04', '2026-08-04T08:00:00Z', '2026-08-04T10:00:00Z', 'judgement_pending');
insert into public.sync_tasks (
  id, task_type, source_id, status, parameter_version, collection_scope, capture_range,
  author_profile_snapshot, x_source_snapshot, collection_batch_id
) values
  ('00000000-0000-0000-0000-000000029401', 'x_sync', 'd0000000-0000-4000-8000-000000029101', 'succeeded', 'v2-final-authority',
    '{"mode":"window"}'::jsonb,
    '{"mode":"window","trigger":"scheduled","timezone":"Asia/Shanghai","start_at":"2026-08-04T00:00:00Z","end_at":"2026-08-04T08:00:00Z","scheduled_window_key":"2026-08-04T16:00+08:00","overlap_start_at":"2026-08-04T00:00:00Z"}'::jsonb,
    '[]'::jsonb, '{"source_type":"x","account_id":"final_authority_a","display_name":"Final source A","parameter_version":"v2-final-authority"}'::jsonb,
    'a0000000-0000-4000-8000-000000029205'),
  ('00000000-0000-0000-0000-000000029402', 'x_sync', '00000000-0000-0000-0000-000000029104', 'succeeded', 'v2-final-authority',
    '{"mode":"window"}'::jsonb,
    '{"mode":"window","trigger":"scheduled","timezone":"Asia/Shanghai","start_at":"2026-08-04T00:00:00Z","end_at":"2026-08-04T08:00:00Z","scheduled_window_key":"2026-08-04T16:00+08:00","overlap_start_at":"2026-08-04T00:00:00Z"}'::jsonb,
    '[]'::jsonb, '{"source_type":"x","account_id":"final_authority_b","display_name":"Final source B","parameter_version":"v2-final-authority"}'::jsonb,
    'a0000000-0000-4000-8000-000000029205');
insert into public.x_collection_batch_sources
  (batch_id, source_id, source_display_name, x_sync_task_id, settlement_status, settled_at)
values
  ('a0000000-0000-4000-8000-000000029205', 'd0000000-0000-4000-8000-000000029101', 'Final source A', '00000000-0000-0000-0000-000000029401', 'included', now()),
  ('a0000000-0000-4000-8000-000000029205', '00000000-0000-0000-0000-000000029104', 'Final source B', '00000000-0000-0000-0000-000000029402', 'included', now());
insert into public.canonical_messages (id, source_id, external_message_id, occurred_at, author_display, content)
values
  ('00000000-0000-0000-0000-000000029501', 'd0000000-0000-4000-8000-000000029101', 'post-alpha', '2026-08-04T07:00:00Z', 'A', 'Synthetic A'),
  ('00000000-0000-0000-0000-000000029502', '00000000-0000-0000-0000-000000029104', 'post-beta', '2026-08-04T07:00:00Z', 'B', 'Synthetic B');
insert into public.x_post_contexts (canonical_message_id, post_type, post_url, context_status)
values
  ('00000000-0000-0000-0000-000000029501', 'original', 'https://x.com/a/status/2901', 'complete'),
  ('00000000-0000-0000-0000-000000029502', 'original', 'https://x.com/b/status/2902', 'complete');
insert into public.x_post_analyses
  (canonical_message_id, analysis_version, blogger_viewpoint, arguments, quoted_post_viewpoint, uncertainties, evidence_refs)
values
  ('00000000-0000-0000-0000-000000029501', 1, 'A view', '[]'::jsonb, null, '[]'::jsonb, '["post-alpha","quote-alpha"]'::jsonb),
  ('00000000-0000-0000-0000-000000029502', 1, 'B view', '[]'::jsonb, null, '[]'::jsonb, '["post-beta"]'::jsonb);
insert into public.x_daily_viewpoint_segments
  (id, source_id, natural_date, range_task_id, segment_version, occurred_from_at, occurred_through_at, window_viewpoints, post_analysis_refs, evidence_refs)
values
  ('c0000000-0000-4000-8000-000000029601', 'd0000000-0000-4000-8000-000000029101', '2026-08-04', '00000000-0000-0000-0000-000000029401', 1,
    '2026-08-04T00:00:00Z', '2026-08-04T08:00:00Z', '["A view"]'::jsonb, '[{"post_id":"post-alpha","analysis_version":1}]'::jsonb, '["post-alpha","quote-alpha"]'::jsonb),
  ('00000000-0000-0000-0000-000000029602', '00000000-0000-0000-0000-000000029104', '2026-08-04', '00000000-0000-0000-0000-000000029402', 1,
    '2026-08-04T00:00:00Z', '2026-08-04T08:00:00Z', '["B view"]'::jsonb, '[{"post_id":"post-beta","analysis_version":1}]'::jsonb, '["post-beta"]'::jsonb);
insert into public.x_daily_judgement_runs
  (id, batch_id, status, attempt, lease_owner, lease_expires_at, available_at, run_kind)
values ('b0000000-0000-4000-8000-000000029305', 'a0000000-0000-4000-8000-000000029205', 'leased', 1,
  '00000000-0000-0000-0000-000000029001', now() + interval '1 hour', now(), 'initial');

create function pg_temp.expect_final_authority_rejected(p_payload jsonb)
returns void language plpgsql as $$
begin
  perform public.complete_x_daily_judgement(
    'b0000000-0000-4000-8000-000000029305', 1, '00000000-0000-0000-0000-000000029001', p_payload
  );
  raise exception 'unexpected_completion_accept' using errcode = 'P0001';
end;
$$;

select throws_ok(
  format(
    $$select pg_temp.expect_final_authority_rejected(%L::jsonb)$$,
    jsonb_build_object(
      'schema_version', 'v2-x-cross-blogger', 'provider', 'codex_cli', 'model_reported', null,
      'prompt_version', 'v2-x-cross-blogger-1',
      'stock_viewpoints', jsonb_build_array(jsonb_build_object(
        'statement', case when field_name = 'statement' then rendered_opaque_id || ' supports this statement' else 'Synthetic statement' end,
        'supporting_source_ids', jsonb_build_array('d0000000-0000-4000-8000-000000029101'),
        'dissenting_source_ids', '[]'::jsonb,
        'analysis_ids', jsonb_build_array('post-alpha@1'),
        'evidence_post_ids', jsonb_build_array('post-alpha', 'quote-alpha'),
        'uncertainties', case when field_name = 'item_uncertainty' then jsonb_build_array(rendered_opaque_id || ' needs context') else '[]'::jsonb end
      )),
      'market_industry_viewpoints', '[]'::jsonb,
      'uncertainties', case when field_name = 'top_uncertainty' then jsonb_build_array(rendered_opaque_id || ' needs context') else '[]'::jsonb end
    )
  ),
  '22023', 'invalid_x_daily_judgement_evidence',
  format('DB completion rejects opaque %s ID in %s (uppercase=%s)', opaque_kind, field_name, use_upper)
)
from (values
  ('batch', 'a0000000-0000-4000-8000-000000029205'),
  ('run', 'b0000000-0000-4000-8000-000000029305'),
  ('segment', 'c0000000-0000-4000-8000-000000029601')
) opaque(opaque_kind, opaque_id)
cross join (values (false), (true)) variants(use_upper)
cross join lateral (
  select case when use_upper then upper(opaque_id) else opaque_id end as rendered_opaque_id
) rendered
cross join (values ('statement'), ('item_uncertainty'), ('top_uncertainty')) fields(field_name);

select throws_ok(
  format(
    $$select pg_temp.expect_final_authority_rejected(%L::jsonb)$$,
    jsonb_build_object(
      'schema_version', 'v2-x-cross-blogger', 'provider', 'codex_cli', 'model_reported', null,
      'prompt_version', 'v2-x-cross-blogger-1',
      'stock_viewpoints', jsonb_build_array(jsonb_build_object(
        'statement', case when field_name = 'statement' then opaque_id || ' supports this statement' else 'Synthetic statement' end,
        'supporting_source_ids', jsonb_build_array('d0000000-0000-4000-8000-000000029101'),
        'dissenting_source_ids', '[]'::jsonb,
        'analysis_ids', jsonb_build_array('post-alpha@1'),
        'evidence_post_ids', jsonb_build_array('post-alpha', 'quote-alpha'),
        'uncertainties', case when field_name = 'item_uncertainty' then jsonb_build_array(opaque_id || ' needs context') else '[]'::jsonb end
      )),
      'market_industry_viewpoints', '[]'::jsonb,
      'uncertainties', case when field_name = 'top_uncertainty' then jsonb_build_array(opaque_id || ' needs context') else '[]'::jsonb end
    )
  ),
  '22023', 'invalid_x_daily_judgement_evidence',
  format('DB completion rejects uppercase opaque %s ID in %s', opaque_kind, field_name)
)
from (values
  ('source', upper('d0000000-0000-4000-8000-000000029101')),
  ('analysis', upper('post-alpha@1')),
  ('evidence', upper('quote-alpha'))
) opaque(opaque_kind, opaque_id)
cross join (values ('statement'), ('item_uncertainty'), ('top_uncertainty')) fields(field_name);

select throws_ok(
  $$select pg_temp.expect_final_authority_rejected('{"schema_version":"v2-x-cross-blogger","provider":"codex_cli","model_reported":null,"prompt_version":"v2-x-cross-blogger-1","stock_viewpoints":[{"statement":"市场已确认估值见底。","supporting_source_ids":["d0000000-0000-4000-8000-000000029101"],"dissenting_source_ids":[],"analysis_ids":["post-alpha@1"],"evidence_post_ids":["post-alpha","quote-alpha"],"uncertainties":[]}],"market_industry_viewpoints":[],"uncertainties":[]}'::jsonb)$$,
  '22023', 'invalid_x_daily_judgement_evidence', 'DB completion rejects single-source strong consensus wording'
);
select throws_ok(
  $$select pg_temp.expect_final_authority_rejected('{"schema_version":"v2-x-cross-blogger","provider":"codex_cli","model_reported":null,"prompt_version":"v2-x-cross-blogger-1","stock_viewpoints":[{"statement":"多位博主一致认为估值见底。","supporting_source_ids":["d0000000-0000-4000-8000-000000029101"],"dissenting_source_ids":["00000000-0000-0000-0000-000000029104"],"analysis_ids":["post-alpha@1","post-beta@1"],"evidence_post_ids":["post-alpha","quote-alpha","post-beta"],"uncertainties":[]}],"market_industry_viewpoints":[],"uncertainties":[]}'::jsonb)$$,
  '22023', 'invalid_x_daily_judgement_evidence', 'DB completion rejects dissenting strong consensus wording'
);
select is(
  (select public.complete_x_daily_judgement(
    'b0000000-0000-4000-8000-000000029305', 1, '00000000-0000-0000-0000-000000029001',
    '{"schema_version":"v2-x-cross-blogger","provider":"codex_cli","model_reported":null,"prompt_version":"v2-x-cross-blogger-1","stock_viewpoints":[{"statement":"两位博主形成共识，认为估值仍需观察。","supporting_source_ids":["d0000000-0000-4000-8000-000000029101","00000000-0000-0000-0000-000000029104"],"dissenting_source_ids":[],"analysis_ids":["post-alpha@1","post-beta@1"],"evidence_post_ids":["post-alpha","quote-alpha","post-beta"],"uncertainties":[]}],"market_industry_viewpoints":[],"uncertainties":[]}'::jsonb
  )->>'status'),
  'succeeded',
  'DB completion accepts strong consensus wording from two independent unopposed sources'
);
select is((select count(*)::text from public.x_daily_judgement_versions where batch_id = 'a0000000-0000-4000-8000-000000029205'), '1', 'valid consensus completion appends exactly one immutable version');

select * from finish();
rollback;
