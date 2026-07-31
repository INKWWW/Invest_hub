begin;

select plan(30);

select is(
  (position('settle_x_collection_batch' in pg_get_functiondef('public.complete_windowed_capture_range(uuid, integer, uuid, jsonb)'::regprocedure)) = 0)::text,
  'true',
  'dual-source range completions cannot enter judgement settlement while holding independent source locks'
);
select is(
  (position('dispatch_due_x_collection_batch_settlements' in pg_get_functiondef('public.ensure_due_x_collection_batches(uuid, timestamptz)'::regprocedure)) > 0)::text,
  'true',
  'the independent post-commit scheduler dispatches already-committed batch settlement'
);
select ok(
  not has_function_privilege('service_role', 'public.ensure_due_x_collection_batches_core(uuid, timestamp with time zone)', 'EXECUTE'),
  'service_role cannot execute the scheduler implementation directly'
);
select ok(
  has_function_privilege('service_role', 'public.ensure_due_x_collection_batches(uuid, timestamp with time zone)', 'EXECUTE'),
  'service_role can execute the scheduler wrapper'
);
select ok(public.x_daily_judgement_safe_text('A/B', 100), 'normal slash-separated labels remain valid');
select ok(public.x_daily_judgement_safe_text('risk/reward', 100), 'normal risk/reward text remains valid');
select ok(not public.x_daily_judgement_safe_text('/private/evidence.json', 100), 'absolute Unix paths are rejected');
select ok(not public.x_daily_judgement_safe_text('C:\\evidence\\raw.json', 100), 'Windows drive paths are rejected');
select ok(not public.x_daily_judgement_safe_text('file:///private/evidence.json', 100), 'file URI paths are rejected');
select ok(not public.x_daily_judgement_safe_text('local_evidence_path: evidence.json', 100), 'local evidence prefixes are rejected');

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at)
values ('00000000-0000-0000-0000-000000025001', 'authenticated', 'authenticated', 'task1-regression-admin@example.invalid', 'not-a-secret', now());
insert into public.profiles (id, role, display_name)
values ('00000000-0000-0000-0000-000000025001', 'admin', 'Task 1 regression admin');
insert into public.workers (id, name, device_secret_hash, status, capabilities)
values ('00000000-0000-0000-0000-000000025002', 'task1-regression-worker', 'task1-regression-worker-hash', 'online', array['x_sync']);

set local role service_role;
select throws_ok(
  $$select public.ensure_due_x_collection_batches_core('00000000-0000-0000-0000-000000025002', '2026-07-26T00:01:00Z')$$,
  '42501', 'permission denied for function ensure_due_x_collection_batches_core',
  'service_role cannot call the scheduler implementation directly'
);
select throws_ok(
  $$select public.ensure_due_x_collection_batches('00000000-0000-0000-0000-000000025002', '2026-07-26T00:01:00Z')$$,
  '42501', 'worker_not_authorized',
  'service_role reaches the scheduler wrapper, which still enforces X source authorization'
);
reset role;

insert into public.x_collection_batches (id, scheduled_window_key, natural_date, cutoff_at, settlement_deadline_at, status)
values
  ('00000000-0000-0000-0000-000000025011', '2026-07-27T08:00+08:00', '2026-07-27', '2026-07-27T00:00:00Z', '2026-07-27T02:00:00Z', 'collecting'),
  ('00000000-0000-0000-0000-000000025012', '2026-07-27T12:00+08:00', '2026-07-27', '2026-07-27T04:00:00Z', '2026-07-27T06:00:00Z', 'collecting'),
  ('00000000-0000-0000-0000-000000025014', '2026-07-27T16:00+08:00', '2026-07-27', '2026-07-27T08:00:00Z', '2026-07-27T10:00:00Z', 'collecting'),
  ('00000000-0000-0000-0000-000000025015', '2026-07-27T20:00+08:00', '2026-07-27', '2026-07-27T12:00:00Z', '2026-07-27T14:00:00Z', 'collecting');

select throws_ok(
  $$insert into public.x_daily_judgement_versions (batch_id, revision, coverage_status, input_snapshot, output, provider, prompt_version, schema_version)
    values ('00000000-0000-0000-0000-000000025014', 1, 'no_new_information',
      '{"sources":[{"source_id":"00000000-0000-0000-0000-000000025021","display_name":"Safe","settlement_status":"included"}]}'::jsonb,
      '{"stock_viewpoints":[],"market_industry_viewpoints":[],"uncertainties":[]}'::jsonb, 'codex_cli','v2-x-cross-blogger-1','v2-x-cross-blogger')$$,
  '22023', 'invalid_x_daily_judgement_snapshot', 'missing snapshot segment fields are rejected'
);
select throws_ok(
  $$insert into public.x_daily_judgement_versions (batch_id, revision, coverage_status, input_snapshot, output, provider, prompt_version, schema_version)
    values ('00000000-0000-0000-0000-000000025015', 1, 'no_new_information',
      '{"sources":[{"source_id":"/tmp/path-disguised-as-identity","display_name":"Safe","settlement_status":"included","segments":[]}]}'::jsonb,
      '{"stock_viewpoints":[],"market_industry_viewpoints":[],"uncertainties":[]}'::jsonb, 'codex_cli','v2-x-cross-blogger-1','v2-x-cross-blogger')$$,
  '22023', 'invalid_x_daily_judgement_snapshot', 'path-disguised-as-source identity is rejected'
);

select throws_ok(
  $$insert into public.x_daily_judgement_versions
      (batch_id, revision, coverage_status, input_snapshot, output, provider, prompt_version, schema_version)
    values ('00000000-0000-0000-0000-000000025011', 1, 'no_new_information',
      '{"sources":[]}'::jsonb,
      '{"stock_viewpoints":[],"market_industry_viewpoints":[],"uncertainties":[],"raw_x_content":"must-not-persist"}'::jsonb,
      'codex_cli', 'v2-x-cross-blogger-1', 'v2-x-cross-blogger')$$,
  '22023', 'invalid_x_daily_judgement_output', 'versions reject unknown raw-content output fields'
);
select throws_ok(
  $$insert into public.x_daily_judgement_versions
      (batch_id, revision, coverage_status, input_snapshot, output, provider, prompt_version, schema_version)
    values ('00000000-0000-0000-0000-000000025012', 1, 'no_new_information',
      '{"sources":[{"source_id":"safe-source","display_name":"Safe","settlement_status":"no_new_information","segments":[],"local_evidence_path":"/private/secret"}]}'::jsonb,
      '{"stock_viewpoints":[],"market_industry_viewpoints":[],"uncertainties":[]}'::jsonb,
      'codex_cli', 'v2-x-cross-blogger-1', 'v2-x-cross-blogger')$$,
  '22023', 'invalid_x_daily_judgement_snapshot', 'versions reject nested local evidence paths in input snapshots'
);

insert into public.sources (id, source_key, source_type, display_name, parameter_version, authorized_worker_id)
values
  ('00000000-0000-0000-0000-000000025021', 'task1-regression-source', 'x', 'Regression source', 'v2-task1-regression', '00000000-0000-0000-0000-000000025002'),
  ('00000000-0000-0000-0000-000000025022', 'task1-active-manual', 'x', 'Active manual source', 'v2-task1-regression', '00000000-0000-0000-0000-000000025002'),
  ('00000000-0000-0000-0000-000000025023', 'task1-terminal-manual', 'x', 'Terminal manual source', 'v2-task1-regression', '00000000-0000-0000-0000-000000025002');
insert into public.x_source_profiles (source_id, requested_handle, account_id, display_name, resolution_status)
values
  ('00000000-0000-0000-0000-000000025021', 'regression_source', 'regression_source', 'Regression source', 'resolved'),
  ('00000000-0000-0000-0000-000000025022', 'active_manual', 'active_manual', 'Active manual source', 'resolved'),
  ('00000000-0000-0000-0000-000000025023', 'terminal_manual', 'terminal_manual', 'Terminal manual source', 'resolved');
insert into public.source_collection_coverage (source_id, coverage_start_at, coverage_through_at)
values
  ('00000000-0000-0000-0000-000000025021', '2026-07-26T00:00:00+08:00', '2026-07-26T00:00:00+08:00'),
  ('00000000-0000-0000-0000-000000025022', '2026-07-26T00:00:00+08:00', '2026-07-26T00:00:00+08:00'),
  ('00000000-0000-0000-0000-000000025023', '2026-07-26T00:00:00+08:00', '2026-07-26T00:00:00+08:00');

insert into public.sync_tasks (id, task_type, source_id, status, parameter_version, requested_by, collection_scope, capture_range, author_profile_snapshot, x_source_snapshot)
values (
  '00000000-0000-0000-0000-000000025031', 'x_sync', '00000000-0000-0000-0000-000000025022', 'queued', 'v2-task1-regression', '00000000-0000-0000-0000-000000025001',
  '{"mode":"window"}'::jsonb,
  '{"mode":"window","trigger":"manual","timezone":"Asia/Shanghai","start_at":"2026-07-25T16:00:00Z","end_at":"2026-07-26T00:00:00Z","scheduled_window_key":null,"overlap_start_at":"2026-07-25T16:00:00Z"}'::jsonb,
  '[]'::jsonb, '{"source_type":"x","account_id":"active_manual","display_name":"Active manual source","parameter_version":"v2-task1-regression"}'::jsonb
), (
  '00000000-0000-0000-0000-000000025032', 'x_sync', '00000000-0000-0000-0000-000000025023', 'failed', 'v2-task1-regression', '00000000-0000-0000-0000-000000025001',
  '{"mode":"window"}'::jsonb,
  '{"mode":"window","trigger":"manual","timezone":"Asia/Shanghai","start_at":"2026-07-25T16:00:00Z","end_at":"2026-07-26T00:00:00Z","scheduled_window_key":null,"overlap_start_at":"2026-07-25T16:00:00Z"}'::jsonb,
  '[]'::jsonb, '{"source_type":"x","account_id":"terminal_manual","display_name":"Terminal manual source","parameter_version":"v2-task1-regression"}'::jsonb
);

select lives_ok(
  $$select public.ensure_due_x_collection_batches('00000000-0000-0000-0000-000000025002', '2026-07-26T00:01:00Z')$$,
  'an active manual window does not make scheduled batch creation fail'
);
select is(
  (select collection_batch_id::text from public.sync_tasks where id = '00000000-0000-0000-0000-000000025031'),
  null,
  'an active manual task remains unbound from a scheduled batch'
);
select is(
  (select settlement_status from public.x_collection_batch_sources where source_id = '00000000-0000-0000-0000-000000025022'),
  'excluded',
  'an active manual conflict is safely excluded from its frozen batch'
);
select is(
  (select collection_batch_id::text from public.sync_tasks where id = '00000000-0000-0000-0000-000000025032'),
  null,
  'a terminal manual task remains unbound from a scheduled batch'
);
select is(
  (select count(*)::text from public.sync_tasks where source_id = '00000000-0000-0000-0000-000000025023' and capture_range->>'trigger' = 'scheduled'),
  '1',
  'a terminal manual task does not prevent creation of its scheduled task'
);

insert into public.x_collection_batches (id, scheduled_window_key, natural_date, cutoff_at, settlement_deadline_at, status)
values ('00000000-0000-0000-0000-000000025013', '2026-07-26T16:00+08:00', '2026-07-26', '2026-07-26T08:00:00Z', '2026-07-26T10:00:00Z', 'collecting');
insert into public.sync_tasks (id, task_type, source_id, status, parameter_version, collection_scope, capture_range, author_profile_snapshot, x_source_snapshot, collection_batch_id)
values ('00000000-0000-0000-0000-000000025033', 'x_sync', '00000000-0000-0000-0000-000000025021', 'succeeded', 'v2-task1-regression',
  '{"mode":"window"}'::jsonb,
  '{"mode":"window","trigger":"scheduled","timezone":"Asia/Shanghai","start_at":"2026-07-26T04:00:00Z","end_at":"2026-07-26T08:00:00Z","scheduled_window_key":"2026-07-26T16:00+08:00","overlap_start_at":"2026-07-26T04:00:00Z"}'::jsonb,
  '[]'::jsonb, '{"source_type":"x","account_id":"regression_source","display_name":"Regression source","parameter_version":"v2-task1-regression"}'::jsonb,
  '00000000-0000-0000-0000-000000025013');
insert into public.x_collection_batch_sources (batch_id, source_id, source_display_name, x_sync_task_id, settlement_status, settled_at)
values ('00000000-0000-0000-0000-000000025013', '00000000-0000-0000-0000-000000025021', 'Regression source', '00000000-0000-0000-0000-000000025033', 'included', '2026-07-26T08:01:00Z');
insert into public.x_daily_viewpoint_segments (id, source_id, natural_date, range_task_id, segment_version, occurred_from_at, occurred_through_at, window_viewpoints, post_analysis_refs, evidence_refs)
values ('00000000-0000-0000-0000-000000025041', '00000000-0000-0000-0000-000000025021', '2026-07-26', '00000000-0000-0000-0000-000000025033', 1, '2026-07-26T04:00:00Z', '2026-07-26T04:00:00Z', '[]'::jsonb, '[{"post_id":"safe-post","analysis_version":1}]'::jsonb, '["safe-post"]'::jsonb);

select throws_ok(
  $$insert into public.x_daily_judgement_versions (batch_id, revision, coverage_status, input_snapshot, output, provider, prompt_version, schema_version)
    values ('00000000-0000-0000-0000-000000025013', 1, 'complete',
      '{"sources":[{"source_id":"00000000-0000-0000-0000-000000025024","display_name":"Regression source","settlement_status":"included","segments":[{"segment_id":"00000000-0000-0000-0000-000000025041","analysis_ids":[{"post_id":"safe-post","analysis_version":1}],"evidence_post_ids":["safe-post"]}]}]}'::jsonb,
      '{"stock_viewpoints":[],"market_industry_viewpoints":[],"uncertainties":[]}'::jsonb, 'codex_cli','v2-x-cross-blogger-1','v2-x-cross-blogger')$$,
  '22023', 'invalid_x_daily_judgement_snapshot', 'a UUID-shaped source from outside the frozen batch is rejected'
);
select throws_ok(
  $$insert into public.x_daily_judgement_versions (batch_id, revision, coverage_status, input_snapshot, output, provider, prompt_version, schema_version)
    values ('00000000-0000-0000-0000-000000025013', 1, 'complete',
      '{"sources":[{"source_id":"00000000-0000-0000-0000-000000025021","display_name":"Regression source","settlement_status":"included","segments":[{"segment_id":"00000000-0000-0000-0000-000000025042","analysis_ids":[{"post_id":"safe-post","analysis_version":1}],"evidence_post_ids":["safe-post"]}]}]}'::jsonb,
      '{"stock_viewpoints":[],"market_industry_viewpoints":[],"uncertainties":[]}'::jsonb, 'codex_cli','v2-x-cross-blogger-1','v2-x-cross-blogger')$$,
  '22023', 'invalid_x_daily_judgement_snapshot', 'a UUID-shaped segment outside the frozen range task is rejected'
);
select throws_ok(
  $$insert into public.x_daily_judgement_versions (batch_id, revision, coverage_status, input_snapshot, output, provider, prompt_version, schema_version)
    values ('00000000-0000-0000-0000-000000025013', 1, 'complete',
      '{"sources":[{"source_id":"00000000-0000-0000-0000-000000025021","display_name":"Regression source","settlement_status":"included","segments":[{"segment_id":"00000000-0000-0000-0000-000000025041","analysis_ids":[{"post_id":"forged-post","analysis_version":1}],"evidence_post_ids":["forged-post"]}]}]}'::jsonb,
      '{"stock_viewpoints":[],"market_industry_viewpoints":[],"uncertainties":[]}'::jsonb, 'codex_cli','v2-x-cross-blogger-1','v2-x-cross-blogger')$$,
  '22023', 'invalid_x_daily_judgement_snapshot', 'forged analysis and post identities are rejected even when their JSON shape is valid'
);

select lives_ok(
  $$select public.dispatch_due_x_collection_batch_settlements('2026-07-26T08:01:00Z')$$,
  'a later independent dispatcher settles a committed successful source'
);
select is(
  (select count(*)::text from public.x_daily_judgement_runs where batch_id = '00000000-0000-0000-0000-000000025013' and status = 'queued'),
  '1',
  'post-commit settlement reaches a queued judgement run'
);
update public.x_daily_judgement_runs
set id = '00000000-0000-0000-0000-000000025051', status = 'leased', attempt = 1,
    lease_owner = '00000000-0000-0000-0000-000000025002', lease_expires_at = timezone('utc', now()) + interval '10 minutes'
where batch_id = '00000000-0000-0000-0000-000000025013' and status = 'queued';
select throws_ok(
  $$select public.complete_x_daily_judgement('00000000-0000-0000-0000-000000025051', 1, '00000000-0000-0000-0000-000000025002',
    '{"schema_version":"v2-x-cross-blogger","provider":"codex_cli","model_reported":null,"prompt_version":"v2-x-cross-blogger-1","stock_viewpoints":[{"statement":"safe","supporting_source_ids":["00000000-0000-0000-0000-000000025021"],"dissenting_source_ids":[],"analysis_ids":["safe-post@1"],"evidence_post_ids":["safe-post"],"uncertainties":[],"raw_x_content":"must-not-persist"}],"market_industry_viewpoints":[],"uncertainties":[]}'::jsonb)$$,
  '22023', 'invalid_x_daily_judgement_output', 'completion rejects nested raw content instead of persisting it'
);

insert into public.sources (id, source_key, source_type, display_name, parameter_version, authorized_worker_id)
values ('00000000-0000-0000-0000-000000025024', 'task1-dispatch-isolation', 'x', 'Dispatch isolation source', 'v2-task1-regression', '00000000-0000-0000-0000-000000025002');
insert into public.x_source_profiles (source_id, requested_handle, account_id, display_name, resolution_status)
values ('00000000-0000-0000-0000-000000025024', 'dispatch_isolation', 'dispatch_isolation', 'Dispatch isolation source', 'resolved');
insert into public.source_collection_coverage (source_id, coverage_start_at, coverage_through_at)
values ('00000000-0000-0000-0000-000000025024', '2026-07-26T00:00:00Z', '2026-07-26T00:00:00Z');
insert into public.x_collection_batches (id, scheduled_window_key, natural_date, cutoff_at, settlement_deadline_at, status)
values ('00000000-0000-0000-0000-000000025016', '2026-07-28T08:00+08:00', '2026-07-28', '2026-07-28T00:00:00Z', '2026-07-28T02:00:00Z', 'collecting');
create function public.task1_inject_dispatch_failure()
returns trigger language plpgsql as $$
begin
  if new.id = '00000000-0000-0000-0000-000000025016' then
    raise exception 'injected dispatcher failure' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
create trigger task1_inject_dispatch_failure
before update on public.x_collection_batches
for each row execute function public.task1_inject_dispatch_failure();
create temporary table scheduler_dispatch_isolation as
select public.ensure_due_x_collection_batches('00000000-0000-0000-0000-000000025002', '2026-07-26T08:01:00Z') as payload;
select is(
  (select count(*)::text from public.sync_tasks where source_id = '00000000-0000-0000-0000-000000025024' and collection_batch_id is not null),
  '1',
  'a dispatcher exception does not roll back new scheduler task creation'
);
select is(
  (select payload->>'settlement_dispatch_failed' from scheduler_dispatch_isolation),
  'true',
  'the scheduler reports an isolated dispatcher failure without raising it'
);
select is(
  (select status from public.x_collection_batches where id = '00000000-0000-0000-0000-000000025016'),
  'collecting',
  'a failed dispatcher leaves its batch for a later independent retry'
);

select * from finish();
rollback;
