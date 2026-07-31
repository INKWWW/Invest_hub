begin;

select plan(37);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at)
values ('00000000-0000-0000-0000-000000028010', 'authenticated', 'authenticated', 'state-security-admin@example.invalid', 'not-a-secret', now());
insert into public.profiles (id, role, display_name)
values ('00000000-0000-0000-0000-000000028010', 'admin', 'State security admin');
insert into public.workers (id, name, device_secret_hash, status, capabilities)
values ('00000000-0000-0000-0000-000000028001', 'state-security-worker', 'state-security-worker-hash', 'online', array['x_sync']);
insert into public.sources (id, source_key, source_type, display_name, parameter_version, authorized_worker_id)
values
  ('00000000-0000-0000-0000-000000028101', 'state-security-source-a', 'x', 'State source A', 'v2-state-security', '00000000-0000-0000-0000-000000028001'),
  ('00000000-0000-0000-0000-000000028102', 'state-security-source-b', 'x', 'State source B', 'v2-state-security', '00000000-0000-0000-0000-000000028001');
insert into public.x_source_profiles (source_id, requested_handle, account_id, display_name, resolution_status)
values
  ('00000000-0000-0000-0000-000000028101', 'state_source_a', 'state_source_a', 'State source A', 'resolved'),
  ('00000000-0000-0000-0000-000000028102', 'state_source_b', 'state_source_b', 'State source B', 'resolved');

insert into public.x_collection_batches (id, scheduled_window_key, natural_date, cutoff_at, settlement_deadline_at, status)
values
  ('00000000-0000-0000-0000-000000028201', '2026-08-03T08:00+08:00', '2026-08-03', '2026-08-03T00:00:00Z', '2026-08-03T02:00:00Z', 'succeeded'),
  ('00000000-0000-0000-0000-000000028202', '2026-08-03T12:00+08:00', '2026-08-03', '2026-08-03T04:00:00Z', '2026-08-03T06:00:00Z', 'succeeded'),
  ('00000000-0000-0000-0000-000000028203', '2026-08-03T16:00+08:00', '2026-08-03', '2026-08-03T08:00:00Z', '2026-08-03T10:00:00Z', 'judgement_pending'),
  ('00000000-0000-0000-0000-000000028204', '2026-08-03T20:00+08:00', '2026-08-03', '2026-08-03T12:00:00Z', '2026-08-03T14:00:00Z', 'judgement_pending'),
  ('00000000-0000-0000-0000-000000028205', '2026-08-04T08:00+08:00', '2026-08-04', '2026-08-04T00:00:00Z', '2026-08-04T02:00:00Z', 'succeeded'),
  ('00000000-0000-0000-0000-000000028206', '2026-08-04T12:00+08:00', '2026-08-04', '2026-08-04T04:00:00Z', '2026-08-04T06:00:00Z', 'collecting'),
  ('00000000-0000-0000-0000-000000028207', '2026-08-04T16:00+08:00', '2026-08-04', '2026-08-04T08:00:00Z', '2026-08-04T10:00:00Z', 'judgement_pending'),
  ('00000000-0000-0000-0000-000000028208', '2026-08-04T20:00+08:00', '2026-08-04', '2026-08-04T12:00:00Z', '2026-08-04T14:00:00Z', 'succeeded'),
  ('00000000-0000-0000-0000-000000028209', '2026-08-05T08:00+08:00', '2026-08-05', '2026-08-05T00:00:00Z', '2026-08-05T02:00:00Z', 'succeeded'),
  ('00000000-0000-0000-0000-000000028211', '2026-08-05T16:00+08:00', '2026-08-05', '2026-08-05T08:00:00Z', '2026-08-05T10:00:00Z', 'judgement_pending');

insert into public.x_collection_batch_sources
  (batch_id, source_id, source_display_name, settlement_status, exclusion_code, settled_at)
values
  ('00000000-0000-0000-0000-000000028201', '00000000-0000-0000-0000-000000028101', 'State source A', 'included', null, now()),
  ('00000000-0000-0000-0000-000000028202', '00000000-0000-0000-0000-000000028101', 'State source A', 'no_new_information', null, now()),
  ('00000000-0000-0000-0000-000000028203', '00000000-0000-0000-0000-000000028101', 'State source A', 'included', null, now()),
  ('00000000-0000-0000-0000-000000028204', '00000000-0000-0000-0000-000000028101', 'State source A', 'included', null, now()),
  ('00000000-0000-0000-0000-000000028205', '00000000-0000-0000-0000-000000028101', 'State source A', 'included', null, now()),
  ('00000000-0000-0000-0000-000000028206', '00000000-0000-0000-0000-000000028101', 'State source A', 'pending', null, null),
  ('00000000-0000-0000-0000-000000028208', '00000000-0000-0000-0000-000000028101', 'State source A', 'included', null, now()),
  ('00000000-0000-0000-0000-000000028209', '00000000-0000-0000-0000-000000028101', 'State source A', 'included', null, now()),
  ('00000000-0000-0000-0000-000000028211', '00000000-0000-0000-0000-000000028101', 'State source A', 'included', null, now());

insert into public.x_daily_judgement_versions
  (batch_id, revision, coverage_status, input_snapshot, output, provider, prompt_version, schema_version)
values
  ('00000000-0000-0000-0000-000000028201', 1, 'complete',
    '{"sources":[{"source_id":"00000000-0000-0000-0000-000000028101","display_name":"State source A","settlement_status":"included","segments":[]}]}'::jsonb,
    '{"stock_viewpoints":[],"market_industry_viewpoints":[],"uncertainties":[]}'::jsonb, 'codex_cli', 'v2-x-cross-blogger-1', 'v2-x-cross-blogger'),
  ('00000000-0000-0000-0000-000000028202', 1, 'no_new_information',
    '{"sources":[{"source_id":"00000000-0000-0000-0000-000000028101","display_name":"State source A","settlement_status":"no_new_information","segments":[]}]}'::jsonb,
    '{"stock_viewpoints":[],"market_industry_viewpoints":[],"uncertainties":[]}'::jsonb, 'codex_cli', 'v2-x-cross-blogger-1', 'v2-x-cross-blogger'),
  ('00000000-0000-0000-0000-000000028205', 1, 'complete',
    '{"sources":[{"source_id":"00000000-0000-0000-0000-000000028101","display_name":"State source A","settlement_status":"included","segments":[]}]}'::jsonb,
    '{"stock_viewpoints":[],"market_industry_viewpoints":[],"uncertainties":[]}'::jsonb, 'codex_cli', 'v2-x-cross-blogger-1', 'v2-x-cross-blogger');

insert into public.x_daily_judgement_runs
  (id, batch_id, status, attempt, lease_owner, lease_expires_at, available_at, run_kind)
values
  ('00000000-0000-0000-0000-000000028401', '00000000-0000-0000-0000-000000028201', 'succeeded', 1, null, null, now(), 'initial'),
  ('00000000-0000-0000-0000-000000028403', '00000000-0000-0000-0000-000000028203', 'leased', 3, '00000000-0000-0000-0000-000000028001', now() - interval '1 minute', now(), 'initial'),
  ('00000000-0000-0000-0000-000000028404', '00000000-0000-0000-0000-000000028204', 'leased', 3, '00000000-0000-0000-0000-000000028001', now() + interval '1 hour', now(), 'initial'),
  ('00000000-0000-0000-0000-000000028405', '00000000-0000-0000-0000-000000028205', 'leased', 3, '00000000-0000-0000-0000-000000028001', now() + interval '1 hour', now(), 'regeneration'),
  ('00000000-0000-0000-0000-000000028408', '00000000-0000-0000-0000-000000028208', 'succeeded', 1, null, null, now(), 'initial'),
  ('00000000-0000-0000-0000-000000028411', '00000000-0000-0000-0000-000000028211', 'retryable_failed', 3, null, null, now(), 'initial');

create temporary table expired_claim as
select public.claim_next_x_daily_judgement('00000000-0000-0000-0000-000000028001', now()) as payload;
select is((select payload from expired_claim), null::jsonb, 'an expired third lease is not claimable as attempt four');
select is((select status from public.x_daily_judgement_runs where id = '00000000-0000-0000-0000-000000028403'), 'failed', 'an expired third lease becomes terminal failed');
select is((select attempt::text from public.x_daily_judgement_runs where id = '00000000-0000-0000-0000-000000028403'), '3', 'lease expiry never increments past the third attempt');
select is((select status from public.x_collection_batches where id = '00000000-0000-0000-0000-000000028203'), 'judgement_failed', 'terminal expiry of an initial run fails its batch');
select is((select status from public.x_daily_judgement_runs where id = '00000000-0000-0000-0000-000000028411'), 'failed', 'a legacy retryable third attempt is terminalized instead of stranded');
select is((select status from public.x_collection_batches where id = '00000000-0000-0000-0000-000000028211'), 'judgement_failed', 'terminalizing a legacy initial third attempt fails its batch');

select is(
  (select public.fail_x_daily_judgement('00000000-0000-0000-0000-000000028404', 3, '00000000-0000-0000-0000-000000028001', 'provider_failure')->>'status'),
  'failed',
  'a reported third failure is terminal'
);
select is((select status from public.x_collection_batches where id = '00000000-0000-0000-0000-000000028204'), 'judgement_failed', 'terminal failure of an initial run fails its batch');
select is(
  (select public.fail_x_daily_judgement('00000000-0000-0000-0000-000000028405', 3, '00000000-0000-0000-0000-000000028001', 'provider_failure')->>'status'),
  'failed',
  'a regeneration third failure is terminal for its run'
);
select is((select status from public.x_collection_batches where id = '00000000-0000-0000-0000-000000028205'), 'succeeded', 'terminal regeneration failure preserves the succeeded batch');
select is((select count(*)::text from public.x_daily_judgement_versions where batch_id = '00000000-0000-0000-0000-000000028205'), '1', 'terminal regeneration failure preserves the previous immutable version');

select is((select count(*)::text from public.x_daily_judgement_runs where batch_id = '00000000-0000-0000-0000-000000028201'), '1', 'successful fixture starts with one terminal run');
select is((select count(*)::text from public.x_daily_judgement_versions where batch_id = '00000000-0000-0000-0000-000000028201'), '1', 'successful fixture starts with one immutable version');
select public.settle_x_collection_batch('00000000-0000-0000-0000-000000028201', now());
select is((select count(*)::text from public.x_daily_judgement_runs where batch_id = '00000000-0000-0000-0000-000000028201'), '1', 'settling a succeeded included batch cannot create another initial run');
select is((select count(*)::text from public.x_daily_judgement_versions where batch_id = '00000000-0000-0000-0000-000000028201'), '1', 'settling a succeeded included batch cannot append another version');
select is((select status from public.x_collection_batches where id = '00000000-0000-0000-0000-000000028201'), 'succeeded', 'settling a succeeded included batch keeps it terminal');
select public.settle_x_collection_batch('00000000-0000-0000-0000-000000028202', now());
select is((select count(*)::text from public.x_daily_judgement_versions where batch_id = '00000000-0000-0000-0000-000000028202'), '1', 'settling a succeeded no-new batch cannot append a second no-new version');
select is((select status from public.x_collection_batches where id = '00000000-0000-0000-0000-000000028202'), 'succeeded', 'settling a succeeded no-new batch keeps it terminal');

select ok(not has_table_privilege('authenticated', 'public.x_collection_batches', 'INSERT,UPDATE,DELETE'), 'authenticated has no batch DML privilege');
select ok(not has_table_privilege('authenticated', 'public.x_collection_batch_sources', 'INSERT,UPDATE,DELETE'), 'authenticated has no snapshot DML privilege');
select ok(not has_table_privilege('authenticated', 'public.x_daily_judgement_runs', 'INSERT,UPDATE,DELETE'), 'authenticated has no run DML privilege');
select ok(not has_table_privilege('authenticated', 'public.x_daily_judgement_versions', 'INSERT,UPDATE,DELETE'), 'authenticated has no version DML privilege');
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000028010', true);
select throws_ok(
  $$update public.x_collection_batches set status = 'judgement_failed' where id = '00000000-0000-0000-0000-000000028206'$$,
  '42501', null, 'an authenticated admin cannot directly mutate batch state'
);
reset role;

select throws_ok(
  $$update public.x_collection_batch_sources
    set settlement_status = 'excluded', exclusion_code = 'tampered', settled_at = now()
    where batch_id = '00000000-0000-0000-0000-000000028209'$$,
  '55000', 'x_collection_snapshot_terminal', 'a settled frozen source row cannot be rewritten even by database authority'
);
select throws_ok(
  $$update public.x_daily_judgement_runs set failure_class = 'tampered'
    where id = '00000000-0000-0000-0000-000000028408'$$,
  '55000', 'x_daily_judgement_run_terminal', 'a terminal run cannot be rewritten even by database authority'
);

insert into public.sync_tasks (
  id, task_type, source_id, status, parameter_version, collection_scope, capture_range,
  author_profile_snapshot, x_source_snapshot, collection_batch_id
) values
  ('00000000-0000-0000-0000-000000028301', 'x_sync', '00000000-0000-0000-0000-000000028101', 'succeeded', 'v2-state-security',
    '{"mode":"window"}'::jsonb,
    '{"mode":"window","trigger":"scheduled","timezone":"Asia/Shanghai","start_at":"2026-08-04T00:00:00Z","end_at":"2026-08-04T08:00:00Z","scheduled_window_key":"2026-08-04T16:00+08:00","overlap_start_at":"2026-08-04T00:00:00Z"}'::jsonb,
    '[]'::jsonb, '{"source_type":"x","account_id":"state_source_a","display_name":"State source A","parameter_version":"v2-state-security"}'::jsonb,
    '00000000-0000-0000-0000-000000028207'),
  ('00000000-0000-0000-0000-000000028302', 'x_sync', '00000000-0000-0000-0000-000000028102', 'succeeded', 'v2-state-security',
    '{"mode":"window"}'::jsonb,
    '{"mode":"window","trigger":"scheduled","timezone":"Asia/Shanghai","start_at":"2026-08-04T00:00:00Z","end_at":"2026-08-04T08:00:00Z","scheduled_window_key":"2026-08-04T16:00+08:00","overlap_start_at":"2026-08-04T00:00:00Z"}'::jsonb,
    '[]'::jsonb, '{"source_type":"x","account_id":"state_source_b","display_name":"State source B","parameter_version":"v2-state-security"}'::jsonb,
    '00000000-0000-0000-0000-000000028207');
insert into public.x_collection_batch_sources
  (batch_id, source_id, source_display_name, x_sync_task_id, settlement_status, settled_at)
values
  ('00000000-0000-0000-0000-000000028207', '00000000-0000-0000-0000-000000028101', 'State source A', '00000000-0000-0000-0000-000000028301', 'included', now()),
  ('00000000-0000-0000-0000-000000028207', '00000000-0000-0000-0000-000000028102', 'State source B', '00000000-0000-0000-0000-000000028302', 'included', now());
insert into public.canonical_messages (id, source_id, external_message_id, occurred_at, author_display, content)
values
  ('00000000-0000-0000-0000-000000028501', '00000000-0000-0000-0000-000000028101', 'post-a', '2026-08-04T07:00:00Z', 'A', 'Synthetic A'),
  ('00000000-0000-0000-0000-000000028502', '00000000-0000-0000-0000-000000028102', 'post-b', '2026-08-04T07:00:00Z', 'B', 'Synthetic B');
insert into public.x_post_contexts (canonical_message_id, post_type, post_url, context_status)
values
  ('00000000-0000-0000-0000-000000028501', 'original', 'https://x.com/a/status/2801', 'complete'),
  ('00000000-0000-0000-0000-000000028502', 'original', 'https://x.com/b/status/2802', 'complete');
insert into public.x_post_analyses
  (canonical_message_id, analysis_version, blogger_viewpoint, arguments, quoted_post_viewpoint, uncertainties, evidence_refs)
values
  ('00000000-0000-0000-0000-000000028501', 1, 'A view', '[]'::jsonb, null, '[]'::jsonb, '["post-a","quote-a"]'::jsonb),
  ('00000000-0000-0000-0000-000000028502', 1, 'B view', '[]'::jsonb, null, '[]'::jsonb, '["post-b"]'::jsonb);
insert into public.x_daily_viewpoint_segments
  (id, source_id, natural_date, range_task_id, segment_version, occurred_from_at, occurred_through_at, window_viewpoints, post_analysis_refs, evidence_refs)
values
  ('00000000-0000-0000-0000-000000028601', '00000000-0000-0000-0000-000000028101', '2026-08-04', '00000000-0000-0000-0000-000000028301', 1,
    '2026-08-04T00:00:00Z', '2026-08-04T08:00:00Z', '["A view"]'::jsonb, '[{"post_id":"post-a","analysis_version":1}]'::jsonb, '["post-a","quote-a"]'::jsonb),
  ('00000000-0000-0000-0000-000000028602', '00000000-0000-0000-0000-000000028102', '2026-08-04', '00000000-0000-0000-0000-000000028302', 1,
    '2026-08-04T00:00:00Z', '2026-08-04T08:00:00Z', '["B view"]'::jsonb, '[{"post_id":"post-b","analysis_version":1}]'::jsonb, '["post-b"]'::jsonb);
insert into public.x_daily_judgement_runs
  (id, batch_id, status, attempt, lease_owner, lease_expires_at, available_at, run_kind)
values ('00000000-0000-0000-0000-000000028407', '00000000-0000-0000-0000-000000028207', 'leased', 1,
  '00000000-0000-0000-0000-000000028001', now() + interval '1 hour', now(), 'initial');

create function pg_temp.expect_completion_rejected(p_payload jsonb)
returns void language plpgsql as $$
begin
  perform public.complete_x_daily_judgement(
    '00000000-0000-0000-0000-000000028407', 1, '00000000-0000-0000-0000-000000028001', p_payload
  );
  raise exception 'unexpected_completion_accept' using errcode = 'P0001';
end;
$$;

select throws_ok(
  $$select pg_temp.expect_completion_rejected('{"schema_version":"v2-x-cross-blogger","provider":"codex_cli","model_reported":null,"prompt_version":"v2-x-cross-blogger-1","stock_viewpoints":[{"statement":"Synthetic","supporting_source_ids":["00000000-0000-0000-0000-000000028101"],"dissenting_source_ids":[],"analysis_ids":["post-b@1"],"evidence_post_ids":["post-b"],"uncertainties":[]}],"market_industry_viewpoints":[],"uncertainties":[]}'::jsonb)$$,
  '22023', 'invalid_x_daily_judgement_evidence', 'DB completion rejects cross-source analysis splicing'
);
select throws_ok(
  $$select pg_temp.expect_completion_rejected('{"schema_version":"v2-x-cross-blogger","provider":"codex_cli","model_reported":null,"prompt_version":"v2-x-cross-blogger-1","stock_viewpoints":[{"statement":"Synthetic","supporting_source_ids":["00000000-0000-0000-0000-000000028101","00000000-0000-0000-0000-000000028101"],"dissenting_source_ids":[],"analysis_ids":["post-a@1"],"evidence_post_ids":["post-a","quote-a"],"uncertainties":[]}],"market_industry_viewpoints":[],"uncertainties":[]}'::jsonb)$$,
  '22023', 'invalid_x_daily_judgement_evidence', 'DB completion rejects duplicate source IDs'
);
select throws_ok(
  $$select pg_temp.expect_completion_rejected('{"schema_version":"v2-x-cross-blogger","provider":"codex_cli","model_reported":null,"prompt_version":"v2-x-cross-blogger-1","stock_viewpoints":[{"statement":"Synthetic","supporting_source_ids":["00000000-0000-0000-0000-000000028101"],"dissenting_source_ids":[],"analysis_ids":["post-a@1","post-a@1"],"evidence_post_ids":["post-a","quote-a"],"uncertainties":[]}],"market_industry_viewpoints":[],"uncertainties":[]}'::jsonb)$$,
  '22023', 'invalid_x_daily_judgement_evidence', 'DB completion rejects duplicate analysis IDs'
);
select throws_ok(
  $$select pg_temp.expect_completion_rejected('{"schema_version":"v2-x-cross-blogger","provider":"codex_cli","model_reported":null,"prompt_version":"v2-x-cross-blogger-1","stock_viewpoints":[{"statement":"Synthetic","supporting_source_ids":["00000000-0000-0000-0000-000000028101"],"dissenting_source_ids":[],"analysis_ids":["post-a@1"],"evidence_post_ids":["post-a","quote-a","post-a"],"uncertainties":[]}],"market_industry_viewpoints":[],"uncertainties":[]}'::jsonb)$$,
  '22023', 'invalid_x_daily_judgement_evidence', 'DB completion rejects duplicate evidence IDs'
);
select throws_ok(
  $$select pg_temp.expect_completion_rejected('{"schema_version":"v2-x-cross-blogger","provider":"codex_cli","model_reported":null,"prompt_version":"v2-x-cross-blogger-1","stock_viewpoints":[{"statement":"Synthetic","supporting_source_ids":["00000000-0000-0000-0000-000000028101"],"dissenting_source_ids":["00000000-0000-0000-0000-000000028101"],"analysis_ids":["post-a@1"],"evidence_post_ids":["post-a","quote-a"],"uncertainties":[]}],"market_industry_viewpoints":[],"uncertainties":[]}'::jsonb)$$,
  '22023', 'invalid_x_daily_judgement_evidence', 'DB completion rejects support and dissent overlap'
);
select throws_ok(
  $$select pg_temp.expect_completion_rejected('{"schema_version":"v2-x-cross-blogger","provider":"codex_cli","model_reported":null,"prompt_version":"v2-x-cross-blogger-1","stock_viewpoints":[{"statement":"Synthetic","supporting_source_ids":["00000000-0000-0000-0000-000000028101"],"dissenting_source_ids":[],"analysis_ids":["post-a@1"],"evidence_post_ids":[],"uncertainties":[]}],"market_industry_viewpoints":[],"uncertainties":[]}'::jsonb)$$,
  '22023', 'invalid_x_daily_judgement_evidence', 'DB completion rejects empty item evidence'
);
select throws_ok(
  $$select pg_temp.expect_completion_rejected('{"schema_version":"v2-x-cross-blogger","provider":"codex_cli","model_reported":null,"prompt_version":"v2-x-cross-blogger-1","stock_viewpoints":[{"statement":"Synthetic","supporting_source_ids":["00000000-0000-0000-0000-000000028101"],"dissenting_source_ids":[],"analysis_ids":["post-a@1"],"evidence_post_ids":["post-a"],"uncertainties":[]}],"market_industry_viewpoints":[],"uncertainties":[]}'::jsonb)$$,
  '22023', 'invalid_x_daily_judgement_evidence', 'DB completion requires the exact analysis evidence union'
);
select throws_ok(
  $$select pg_temp.expect_completion_rejected('{"schema_version":"v2-x-cross-blogger","provider":"codex_cli","model_reported":null,"prompt_version":"v2-x-cross-blogger-1","stock_viewpoints":[{"statement":"00000000-0000-0000-0000-000000028101 supports this","supporting_source_ids":["00000000-0000-0000-0000-000000028101"],"dissenting_source_ids":[],"analysis_ids":["post-a@1"],"evidence_post_ids":["post-a","quote-a"],"uncertainties":[]}],"market_industry_viewpoints":[],"uncertainties":[]}'::jsonb)$$,
  '22023', 'invalid_x_daily_judgement_evidence', 'DB completion rejects opaque source IDs embedded in statements'
);
select throws_ok(
  $$select pg_temp.expect_completion_rejected('{"schema_version":"v2-x-cross-blogger","provider":"codex_cli","model_reported":null,"prompt_version":"v2-x-cross-blogger-1","stock_viewpoints":[{"statement":"Synthetic","supporting_source_ids":["00000000-0000-0000-0000-000000028101"],"dissenting_source_ids":[],"analysis_ids":["post-a@1"],"evidence_post_ids":["post-a","quote-a"],"uncertainties":["quote-a needs context"]}],"market_industry_viewpoints":[],"uncertainties":[]}'::jsonb)$$,
  '22023', 'invalid_x_daily_judgement_evidence', 'DB completion rejects opaque evidence IDs embedded in uncertainties'
);

select is(
  (select public.complete_x_daily_judgement(
    '00000000-0000-0000-0000-000000028407', 1, '00000000-0000-0000-0000-000000028001',
    '{"schema_version":"v2-x-cross-blogger","provider":"codex_cli","model_reported":null,"prompt_version":"v2-x-cross-blogger-1","stock_viewpoints":[{"statement":"Synthetic exact relation","supporting_source_ids":["00000000-0000-0000-0000-000000028101"],"dissenting_source_ids":["00000000-0000-0000-0000-000000028102"],"analysis_ids":["post-a@1","post-b@1"],"evidence_post_ids":["post-a","quote-a","post-b"],"uncertainties":[]}],"market_industry_viewpoints":[],"uncertainties":[]}'::jsonb
  )->>'status'),
  'succeeded',
  'DB completion accepts an exact source-analysis-evidence relation'
);
select is((select count(*)::text from public.x_daily_judgement_versions where batch_id = '00000000-0000-0000-0000-000000028207'), '1', 'valid completion appends exactly one immutable version');

insert into public.x_collection_batches (id, scheduled_window_key, natural_date, cutoff_at, settlement_deadline_at, status)
values ('00000000-0000-0000-0000-000000028210', '2026-08-05T12:00+08:00', '2026-08-05', '2026-08-05T04:00:00Z', '2026-08-05T06:00:00Z', 'judgement_pending');
insert into public.sync_tasks (
  id, task_type, source_id, status, parameter_version, collection_scope, capture_range,
  author_profile_snapshot, x_source_snapshot, collection_batch_id
) values (
  '00000000-0000-0000-0000-000000028303', 'x_sync', '00000000-0000-0000-0000-000000028101', 'succeeded', 'v2-state-security',
  '{"mode":"window"}'::jsonb,
  '{"mode":"window","trigger":"scheduled","timezone":"Asia/Shanghai","start_at":"2026-08-05T00:00:00Z","end_at":"2026-08-05T04:00:00Z","scheduled_window_key":"2026-08-05T12:00+08:00","overlap_start_at":"2026-08-05T00:00:00Z"}'::jsonb,
  '[]'::jsonb, '{"source_type":"x","account_id":"state_source_a","display_name":"State source A","parameter_version":"v2-state-security"}'::jsonb,
  '00000000-0000-0000-0000-000000028210'
);
insert into public.x_collection_batch_sources
  (batch_id, source_id, source_display_name, x_sync_task_id, settlement_status, settled_at)
values ('00000000-0000-0000-0000-000000028210', '00000000-0000-0000-0000-000000028101', 'State source A',
  '00000000-0000-0000-0000-000000028303', 'included', now());
insert into public.canonical_messages (id, source_id, external_message_id, occurred_at, author_display, content)
values ('00000000-0000-0000-0000-000000028503', '00000000-0000-0000-0000-000000028101', 'post-c', '2026-08-05T03:00:00Z', 'A', 'Synthetic C');
insert into public.x_post_contexts (canonical_message_id, post_type, post_url, context_status)
values ('00000000-0000-0000-0000-000000028503', 'original', 'https://x.com/a/status/2803', 'complete');
insert into public.x_post_analyses
  (canonical_message_id, analysis_version, blogger_viewpoint, arguments, quoted_post_viewpoint, uncertainties, evidence_refs)
values ('00000000-0000-0000-0000-000000028503', 1, 'C view', '[]'::jsonb, null, '[]'::jsonb, '["post-c","analysis-only"]'::jsonb);
insert into public.x_daily_viewpoint_segments
  (id, source_id, natural_date, range_task_id, segment_version, occurred_from_at, occurred_through_at, window_viewpoints, post_analysis_refs, evidence_refs)
values ('00000000-0000-0000-0000-000000028603', '00000000-0000-0000-0000-000000028101', '2026-08-05',
  '00000000-0000-0000-0000-000000028303', 1, '2026-08-05T00:00:00Z', '2026-08-05T04:00:00Z', '["C view"]'::jsonb,
  '[{"post_id":"post-c","analysis_version":1}]'::jsonb, '["post-c"]'::jsonb);
insert into public.x_daily_judgement_runs
  (id, batch_id, status, attempt, lease_owner, lease_expires_at, available_at, run_kind)
values ('00000000-0000-0000-0000-000000028410', '00000000-0000-0000-0000-000000028210', 'leased', 1,
  '00000000-0000-0000-0000-000000028001', now() + interval '1 hour', now(), 'initial');
create function pg_temp.expect_unfrozen_analysis_evidence_rejected()
returns void language plpgsql as $$
begin
  perform public.complete_x_daily_judgement(
    '00000000-0000-0000-0000-000000028410', 1, '00000000-0000-0000-0000-000000028001',
    '{"schema_version":"v2-x-cross-blogger","provider":"codex_cli","model_reported":null,"prompt_version":"v2-x-cross-blogger-1","stock_viewpoints":[{"statement":"Synthetic inconsistent evidence","supporting_source_ids":["00000000-0000-0000-0000-000000028101"],"dissenting_source_ids":[],"analysis_ids":["post-c@1"],"evidence_post_ids":["post-c","analysis-only"],"uncertainties":[]}],"market_industry_viewpoints":[],"uncertainties":[]}'::jsonb
  );
  raise exception 'unexpected_completion_accept' using errcode = 'P0001';
end;
$$;
select throws_ok(
  $$select pg_temp.expect_unfrozen_analysis_evidence_rejected()$$,
  '22023', 'invalid_x_daily_judgement_evidence', 'DB completion rejects analysis evidence absent from the frozen segment evidence set'
);

select * from finish();
rollback;
