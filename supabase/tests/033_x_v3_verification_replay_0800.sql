begin;

select plan(20);

select has_table('public', 'x_v3_verification_replays', 'verification replay lifecycle is persisted separately from scheduled batches');
select has_table('public', 'x_v3_verification_replay_sources', 'verification replay freezes its eligible sources');
select has_table('public', 'x_v3_verification_segments', 'verification replay stores its own immutable v3 windows');
select has_table('public', 'x_v3_verification_versions', 'verification replay stores its own immutable v3 daily output');
select has_function('public', 'create_x_v3_verification_replay', array['uuid', 'uuid'], 'admins create an explicit replay without creating scheduled work');
select has_function('public', 'complete_x_v3_verification_replay', array['uuid', 'integer', 'uuid', 'jsonb'], 'one completion boundary validates and persists the replay');

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at)
values
  ('00000000-0000-0000-0000-000000033010', 'authenticated', 'authenticated', 'replay-admin@example.invalid', 'not-a-secret', now()),
  ('00000000-0000-0000-0000-000000033011', 'authenticated', 'authenticated', 'replay-user@example.invalid', 'not-a-secret', now());
insert into public.profiles (id, role, display_name)
values
  ('00000000-0000-0000-0000-000000033010', 'admin', 'Replay Admin'),
  ('00000000-0000-0000-0000-000000033011', 'user', 'Replay User');
insert into public.workers (id, name, device_secret_hash, status, capabilities, last_heartbeat_at)
values ('00000000-0000-0000-0000-000000033001', 'replay-worker', 'replay-worker-hash', 'online', array['x_sync'], now());
insert into public.sources (id, source_key, source_type, display_name, parameter_version, authorized_worker_id)
values
  ('00000000-0000-0000-0000-000000033101', 'replay-source-a', 'x', 'Replay source A', 'v2-replay', '00000000-0000-0000-0000-000000033001'),
  ('00000000-0000-0000-0000-000000033102', 'replay-source-b', 'x', 'Replay source B', 'v2-replay', '00000000-0000-0000-0000-000000033001'),
  ('00000000-0000-0000-0000-000000033103', 'replay-source-c', 'x', 'Replay source C', 'v2-replay', '00000000-0000-0000-0000-000000033001'),
  ('00000000-0000-0000-0000-000000033104', 'replay-source-excluded', 'x', 'Replay excluded source', 'v2-replay', '00000000-0000-0000-0000-000000033001');
insert into public.x_source_profiles (source_id, requested_handle, account_id, display_name, resolution_status)
select id, source_key, source_key, display_name, 'resolved' from public.sources where source_key like 'replay-source-%';
insert into public.x_collection_batches (id, scheduled_window_key, natural_date, cutoff_at, settlement_deadline_at, status)
values
  ('00000000-0000-0000-0000-000000033201', '2026-08-04T08:00+08:00', '2026-08-04', '2026-08-04T00:00:00Z', '2026-08-04T02:00:00Z', 'judgement_failed'),
  ('00000000-0000-0000-0000-000000033202', '2026-08-04T12:00+08:00', '2026-08-04', '2026-08-04T04:00:00Z', '2026-08-04T06:00:00Z', 'judgement_failed');
insert into public.sync_tasks (id, task_type, source_id, status, parameter_version, collection_scope, capture_range, author_profile_snapshot, x_source_snapshot, collection_batch_id)
values
  ('00000000-0000-0000-0000-000000033301', 'x_sync', '00000000-0000-0000-0000-000000033101', 'succeeded', 'v2-replay', '{"mode":"window"}', '{"mode":"window","trigger":"scheduled","timezone":"Asia/Shanghai","start_at":"2026-08-03T16:00:00Z","end_at":"2026-08-04T00:00:00Z","scheduled_window_key":"2026-08-04T08:00+08:00","overlap_start_at":"2026-08-03T16:00:00Z"}', '[]', '{"source_type":"x","account_id":"replay-source-a","display_name":"Replay source A","parameter_version":"v2-replay"}', '00000000-0000-0000-0000-000000033201'),
  ('00000000-0000-0000-0000-000000033302', 'x_sync', '00000000-0000-0000-0000-000000033102', 'succeeded', 'v2-replay', '{"mode":"window"}', '{"mode":"window","trigger":"scheduled","timezone":"Asia/Shanghai","start_at":"2026-08-03T16:00:00Z","end_at":"2026-08-04T00:00:00Z","scheduled_window_key":"2026-08-04T08:00+08:00","overlap_start_at":"2026-08-03T16:00:00Z"}', '[]', '{"source_type":"x","account_id":"replay-source-b","display_name":"Replay source B","parameter_version":"v2-replay"}', '00000000-0000-0000-0000-000000033201'),
  ('00000000-0000-0000-0000-000000033303', 'x_sync', '00000000-0000-0000-0000-000000033103', 'succeeded', 'v2-replay', '{"mode":"window"}', '{"mode":"window","trigger":"scheduled","timezone":"Asia/Shanghai","start_at":"2026-08-03T16:00:00Z","end_at":"2026-08-04T00:00:00Z","scheduled_window_key":"2026-08-04T08:00+08:00","overlap_start_at":"2026-08-03T16:00:00Z"}', '[]', '{"source_type":"x","account_id":"replay-source-c","display_name":"Replay source C","parameter_version":"v2-replay"}', '00000000-0000-0000-0000-000000033201');
insert into public.x_collection_batch_sources (batch_id, source_id, source_display_name, x_sync_task_id, settlement_status, exclusion_code, settled_at)
values
  ('00000000-0000-0000-0000-000000033201', '00000000-0000-0000-0000-000000033101', 'Replay source A', '00000000-0000-0000-0000-000000033301', 'included', null, now()),
  ('00000000-0000-0000-0000-000000033201', '00000000-0000-0000-0000-000000033102', 'Replay source B', '00000000-0000-0000-0000-000000033302', 'included', null, now()),
  ('00000000-0000-0000-0000-000000033201', '00000000-0000-0000-0000-000000033103', 'Replay source C', '00000000-0000-0000-0000-000000033303', 'included', null, now()),
  ('00000000-0000-0000-0000-000000033201', '00000000-0000-0000-0000-000000033104', 'Replay excluded source', null, 'excluded', 'source_behind_cutoff', now());
insert into public.canonical_messages (id, source_id, external_message_id, occurred_at, author_display, content)
values
  ('00000000-0000-0000-0000-000000033501', '00000000-0000-0000-0000-000000033101', 'post-a', '2026-08-04T00:00:00Z', 'A', 'Synthetic replay A'),
  ('00000000-0000-0000-0000-000000033502', '00000000-0000-0000-0000-000000033102', 'post-b', '2026-08-04T00:00:00Z', 'B', 'Synthetic replay B'),
  ('00000000-0000-0000-0000-000000033503', '00000000-0000-0000-0000-000000033103', 'post-c', '2026-08-04T00:00:00Z', 'C', 'Synthetic replay C');
insert into public.x_post_contexts (canonical_message_id, post_type, post_url, context_status)
values
  ('00000000-0000-0000-0000-000000033501', 'original', 'https://x.com/a/status/3301', 'complete'),
  ('00000000-0000-0000-0000-000000033502', 'original', 'https://x.com/b/status/3302', 'complete'),
  ('00000000-0000-0000-0000-000000033503', 'original', 'https://x.com/c/status/3303', 'complete');
insert into public.x_post_analyses (canonical_message_id, analysis_version, blogger_viewpoint, arguments, quoted_post_viewpoint, uncertainties, evidence_refs)
select id, 1, 'Legacy v2 viewpoint', '[]', null, '[]', jsonb_build_array(external_message_id) from public.canonical_messages where id between '00000000-0000-0000-0000-000000033501' and '00000000-0000-0000-0000-000000033503';
insert into public.x_daily_viewpoint_segments (id, source_id, natural_date, range_task_id, segment_version, occurred_from_at, occurred_through_at, window_viewpoints, post_analysis_refs, evidence_refs)
values
  ('00000000-0000-0000-0000-000000033601', '00000000-0000-0000-0000-000000033101', '2026-08-04', '00000000-0000-0000-0000-000000033301', 1, '2026-08-04T00:00:00Z', '2026-08-04T00:00:00Z', '[]', '[{"post_id":"post-a","analysis_version":1}]', '["post-a"]'),
  ('00000000-0000-0000-0000-000000033602', '00000000-0000-0000-0000-000000033102', '2026-08-04', '00000000-0000-0000-0000-000000033302', 1, '2026-08-04T00:00:00Z', '2026-08-04T00:00:00Z', '[]', '[{"post_id":"post-b","analysis_version":1}]', '["post-b"]'),
  ('00000000-0000-0000-0000-000000033603', '00000000-0000-0000-0000-000000033103', '2026-08-04', '00000000-0000-0000-0000-000000033303', 1, '2026-08-04T00:00:00Z', '2026-08-04T00:00:00Z', '[]', '[{"post_id":"post-c","analysis_version":1}]', '["post-c"]');
insert into public.x_daily_judgement_runs (id, batch_id, status, attempt, available_at, failure_class, run_kind)
values ('00000000-0000-0000-0000-000000033401', '00000000-0000-0000-0000-000000033201', 'failed', 3, now(), 'schema_error', 'initial');

select throws_ok($$select public.create_x_v3_verification_replay('00000000-0000-0000-0000-000000033201', '00000000-0000-0000-0000-000000033011')$$, '42501', 'actor_not_authorized', 'ordinary users cannot create a replay');
select throws_ok($$select public.create_x_v3_verification_replay('00000000-0000-0000-0000-000000033202', '00000000-0000-0000-0000-000000033010')$$, '22023', 'x_v3_verification_source_batch_not_available', 'only the exact failed 08:00 batch is eligible');
create temporary table replay_seed as select public.create_x_v3_verification_replay('00000000-0000-0000-0000-000000033201', '00000000-0000-0000-0000-000000033010') as payload;
select is((select count(*)::text from public.x_v3_verification_replay_sources where replay_id = (select (payload->>'replay_id')::uuid from replay_seed)), '3', 'replay freezes exactly the included sources');
select is((select count(*)::text from public.sync_tasks), '3', 'replay creation does not create collection tasks');
select is((select count(*)::text from public.x_daily_judgement_runs), '1', 'replay creation does not create daily runs');
select is((select status from public.x_collection_batches where id = '00000000-0000-0000-0000-000000033201'), 'judgement_failed', 'replay creation preserves the scheduled batch failure');
select throws_ok($$select public.create_x_v3_verification_replay('00000000-0000-0000-0000-000000033201', '00000000-0000-0000-0000-000000033010')$$, '23505', null, 'one scheduled batch has at most one replay');
create temporary table replay_claim as select public.claim_x_v3_verification_replay((select (payload->>'replay_id')::uuid from replay_seed), '00000000-0000-0000-0000-000000033001') as payload;
select is((select payload->>'attempt' from replay_claim), '1', 'the explicit worker claims the replay exactly once');
select is((select jsonb_array_length(public.get_x_v3_verification_replay_context((select (payload->>'replay_id')::uuid from replay_seed), 1, '00000000-0000-0000-0000-000000033001')->'sources')::text), '3', 'claimed context exposes exactly the frozen sources');
create function pg_temp.valid_completion() returns jsonb language sql as $$
  select jsonb_build_object(
    'provider', 'codex_cli', 'model_reported', null,
    'sources', jsonb_agg(jsonb_build_object(
      'source_id', source_id, 'analyses', jsonb_build_array(jsonb_build_object(
        'post_id', post_id, 'analysis_id', post_id || '@2', 'analysis_version', 2,
        'schema_version', 'v3-x-post-analysis', 'prompt_version', 'v3-x-post-analysis-1',
        'analysis_output', jsonb_build_object('schema_version', 'v3-x-post-analysis', 'post_id', post_id),
        'blogger_viewpoint', 'Synthetic v3 viewpoint', 'arguments', '[]'::jsonb, 'quoted_post_viewpoint', null,
        'uncertainties', '[]'::jsonb, 'evidence_post_ids', jsonb_build_array(post_id), 'post_link', post_link
      )),
      'segment', jsonb_build_object(
        'occurred_from_at', '2026-08-04T00:00:00Z', 'occurred_through_at', '2026-08-04T00:00:00Z',
        'schema_version', 'v3-x-window', 'prompt_version', 'v3-x-window-1',
        'segment_output', jsonb_build_object('schema_version', 'v3-x-window', 'analysis_ids', jsonb_build_array(post_id || '@2'), 'evidence_post_ids', jsonb_build_array(post_id)),
        'analysis_ids', jsonb_build_array(post_id || '@2'), 'evidence_post_ids', jsonb_build_array(post_id), 'uncertainties', '[]'::jsonb
      )
    )),
    'daily', jsonb_build_object(
      'schema_version', 'v3-x-cross-blogger', 'prompt_version', 'v3-x-cross-blogger-1',
      'security_industry_viewpoints', jsonb_build_array(jsonb_build_object(
        'statement', 'Synthetic replay relation', 'action_intent', 'watch', 'action_scope', 'Synthetic scope', 'conditions', '[]'::jsonb,
        'supporting_source_ids', jsonb_build_array('00000000-0000-0000-0000-000000033101', '00000000-0000-0000-0000-000000033102', '00000000-0000-0000-0000-000000033103'),
        'dissenting_source_ids', '[]'::jsonb, 'analysis_ids', jsonb_build_array('post-a@2', 'post-b@2', 'post-c@2'),
        'evidence_post_ids', jsonb_build_array('post-a', 'post-b', 'post-c'), 'uncertainties', '[]'::jsonb
      )), 'market_structure_viewpoints', '[]'::jsonb, 'strategy_mindset_viewpoints', '[]'::jsonb, 'uncertainties', '[]'::jsonb
    )
  )
  from (values
    ('00000000-0000-0000-0000-000000033101'::text, 'post-a', 'https://x.com/a/status/3301'),
    ('00000000-0000-0000-0000-000000033102'::text, 'post-b', 'https://x.com/b/status/3302'),
    ('00000000-0000-0000-0000-000000033103'::text, 'post-c', 'https://x.com/c/status/3303')
  ) rows(source_id, post_id, post_link)
$$;
select is((select public.complete_x_v3_verification_replay((select (payload->>'replay_id')::uuid from replay_seed), 1, '00000000-0000-0000-0000-000000033001', pg_temp.valid_completion())->>'status'), 'succeeded', 'a complete v3 replay atomically persists its independent result');
select is((select count(*)::text from public.x_v3_verification_versions where replay_id = (select (payload->>'replay_id')::uuid from replay_seed)), '1', 'successful replay writes one immutable daily version');
select is((select output ? 'schema_version' or output ? 'prompt_version' from public.x_v3_verification_versions where replay_id = (select (payload->>'replay_id')::uuid from replay_seed)), false, 'stored replay output excludes wire-only schema and prompt metadata');
select is((select schema_version from public.x_v3_verification_versions where replay_id = (select (payload->>'replay_id')::uuid from replay_seed)), 'v3-x-cross-blogger', 'stored replay version retains its schema column');
select is((select prompt_version from public.x_v3_verification_versions where replay_id = (select (payload->>'replay_id')::uuid from replay_seed)), 'v3-x-cross-blogger-1', 'stored replay version retains its prompt column');

select * from finish();
rollback;
