begin;

select plan(22);

-- This is the one durable, public synthetic case that joins the existing
-- Ticket 01 completion seam to the Ticket 02R settlement/judgement seam.
select has_function(
  'public', 'complete_windowed_capture_range', array['uuid', 'integer', 'uuid', 'jsonb'],
  'the representative case uses the existing exact-window completion seam'
);
select has_function(
  'public', 'complete_x_daily_judgement', array['uuid', 'integer', 'uuid', 'jsonb'],
  'the representative case uses the existing judgement completion seam'
);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at)
values ('00000000-0000-0000-0000-000000044001', 'authenticated', 'authenticated', 'ticket-05r@example.invalid', 'not-a-secret', now());
insert into public.profiles (id, role, display_name)
values ('00000000-0000-0000-0000-000000044001', 'admin', 'Ticket 05R admin');
insert into public.workers (id, name, device_secret_hash, status, last_heartbeat_at, capabilities)
values ('00000000-0000-0000-0000-000000044002', 'Ticket 05R Worker', 'ticket-05r-hash', 'online', now(), array['x_sync']);

create temporary table demo_source as
select public.create_x_source(
  'x:ticket-05r-success', 'Ticket 05R synthetic blogger', 'ticket05r', 'x-standard-v2',
  '00000000-0000-0000-0000-000000044001'
) as payload;
update public.sources
set authorized_worker_id = '00000000-0000-0000-0000-000000044002'
where id = (select (payload->>'id')::uuid from demo_source);
select public.resolve_x_source_identity(
  (select (payload->>'id')::uuid from demo_source),
  '00000000-0000-0000-0000-000000044002', 'x-standard-v2', 'ticket05r'
);
select public.initialize_x_collection_coverage(
  (select (payload->>'id')::uuid from demo_source),
  '00000000-0000-0000-0000-000000044001', '2026-08-17T16:00:00+08:00'
);

create temporary table demo_run as
select public.start_x_demo_fixed_window_run(
  '2026-08-18T16:00:00+08:00', '00000000-0000-0000-0000-000000044002'
) as payload;
select is((select payload->>'idempotent' from demo_run), 'false', 'the representative cutoff creates one Demo run');
select is((select jsonb_array_length(payload->'sources') from demo_run), 1, 'the run freezes the enabled ready source');

create temporary table demo_task as
select public.create_x_demo_fixed_window_task_for_run(
  (select (payload->>'run_id')::uuid from demo_run),
  (select (payload->>'id')::uuid from demo_source),
  '2026-08-18T16:00:00+08:00', '00000000-0000-0000-0000-000000044002', 'ticket05r'
) as payload;
select public.bind_x_demo_fixed_window_task(
  (select (payload->>'run_id')::uuid from demo_run),
  (select (payload->>'id')::uuid from demo_source),
  (select (payload->>'id')::uuid from demo_task),
  '00000000-0000-0000-0000-000000044002'
);
create temporary table demo_claim as
select public.claim_x_demo_fixed_window_task(
  (select (payload->>'id')::uuid from demo_task),
  '00000000-0000-0000-0000-000000044002', '2026-08-18T17:00:00+08:00'
) as payload;
select is(
  (select payload->>'task_id' from demo_claim),
  (select payload->>'id' from demo_task),
  'the Worker claims only the exact task returned for this cutoff'
);
select is(
  (select payload->'capture_range'->>'start_at' from demo_claim),
  '2026-08-18T04:00:00+00:00',
  'the exact task preserves its fixed-window lower bound'
);

insert into public.canonical_messages (id, source_id, external_message_id, occurred_at, author_display, content)
values (
  '00000000-0000-0000-0000-000000044004',
  (select (payload->>'id')::uuid from demo_source),
  'ticket-05r-post', '2026-08-18T05:00:00Z', 'Ticket 05R synthetic blogger', '公开 synthetic 事实'
);
insert into public.x_post_contexts (canonical_message_id, post_type, post_url, context_status, attachments)
values (
  '00000000-0000-0000-0000-000000044004', 'original',
  'https://x.com/ticket_05r_fixture/status/1', 'complete', '[]'::jsonb
);
update public.sync_task_capture_progress
set page_count = 1
where task_id = (select (payload->>'task_id')::uuid from demo_claim);

create temporary table demo_completion as
select public.complete_windowed_capture_range(
  (select (payload->>'task_id')::uuid from demo_claim), 1,
  '00000000-0000-0000-0000-000000044002',
  jsonb_build_object(
    'contract_version', 'v0',
    'task_id', (select payload->>'task_id' from demo_claim),
    'attempt', 1,
    'range_complete', true,
    'capture_range', (select payload->'capture_range' from demo_claim),
    'boundary', jsonb_build_object('kind', 'history_exhausted', 'observed_at', '2026-08-18T05:00:00Z'),
    'summary_batch_ids', '[]'::jsonb,
    'daily_summary_ids', '[]'::jsonb,
    'x_post_analyses', jsonb_build_array(jsonb_build_object(
      'post_id', 'ticket-05r-post', 'analysis_id', 'ticket-05r-post@2', 'analysis_version', 2,
      'schema_version', 'v4-x-post-analysis', 'prompt_version', 'v4-x-post-analysis-1',
      'analysis_output', jsonb_build_object(
        'schema_version', 'v4-x-post-analysis', 'post_id', 'ticket-05r-post',
        'investment_relevance', 'investment_related', 'investment_categories', jsonb_build_array('security_industry'),
        'blogger_viewpoint', '公开 synthetic 单博主观点', 'action_intent', 'watch',
        'action_scope_status', 'specified', 'action_scope', '公开 synthetic 标的',
        'conditions', '[]'::jsonb, 'arguments', jsonb_build_array('公开 synthetic 论据'),
        'quoted_post_viewpoint', null, 'uncertainties', '[]'::jsonb,
        'evidence_post_ids', jsonb_build_array('ticket-05r-post'),
        'post_link', 'https://x.com/ticket_05r_fixture/status/1'
      ),
      'blogger_viewpoint', '公开 synthetic 单博主观点',
      'arguments', jsonb_build_array('公开 synthetic 论据'), 'quoted_post_viewpoint', null,
      'uncertainties', '[]'::jsonb, 'evidence_post_ids', jsonb_build_array('ticket-05r-post'),
      'post_link', 'https://x.com/ticket_05r_fixture/status/1'
    )),
    'x_daily_segments', jsonb_build_array(jsonb_build_object(
      'natural_date', '2026-08-18', 'occurred_from_at', '2026-08-18T05:00:00Z',
      'occurred_through_at', '2026-08-18T05:00:00Z', 'schema_version', 'v4-x-window',
      'prompt_version', 'v4-x-window-1',
      'segment_output', jsonb_build_object(
        'schema_version', 'v4-x-window',
        'range_task_id', (select payload->>'task_id' from demo_claim),
        'natural_date', '2026-08-18', 'occurred_from_at', '2026-08-18T05:00:00Z',
        'occurred_through_at', '2026-08-18T05:00:00Z',
        'security_industry_viewpoints', jsonb_build_array(jsonb_build_object(
          'statement', '公开 synthetic 窗口观点', 'action_intent', 'watch',
          'action_scope_status', 'specified', 'action_scope', '公开 synthetic 标的',
          'conditions', '[]'::jsonb, 'analysis_ids', jsonb_build_array('ticket-05r-post@2'),
          'evidence_post_ids', jsonb_build_array('ticket-05r-post'), 'uncertainties', '[]'::jsonb
        )),
        'market_structure_viewpoints', '[]'::jsonb, 'strategy_mindset_viewpoints', '[]'::jsonb,
        'analysis_ids', jsonb_build_array('ticket-05r-post@2'),
        'evidence_post_ids', jsonb_build_array('ticket-05r-post'), 'uncertainties', '[]'::jsonb
      ),
      'window_viewpoints', '[]'::jsonb,
      'analysis_ids', jsonb_build_array('ticket-05r-post@2'),
      'evidence_post_ids', jsonb_build_array('ticket-05r-post'), 'uncertainties', '[]'::jsonb
    )),
    'no_new_data', false
  )
) as payload;
select is((select payload->>'status' from demo_completion), 'succeeded', 'collection and analysis persist through the existing completion RPC');
select is((select status from public.sync_tasks where id = (select (payload->>'id')::uuid from demo_task)), 'succeeded', 'the exact collection task reaches succeeded');
select is((select count(*)::int from public.x_post_analyses where canonical_message_id = '00000000-0000-0000-0000-000000044004'), 1, 'one post analysis is durably persisted');
select is((select count(*)::int from public.x_daily_viewpoint_segments where range_task_id = (select (payload->>'id')::uuid from demo_task)), 1, 'one single-blogger window segment is durably persisted');

create temporary table settled as
select public.settle_x_demo_fixed_window_run(
  (select (payload->>'run_id')::uuid from demo_run),
  '00000000-0000-0000-0000-000000044002'
) as payload;
select is((select payload->>'status' from settled), 'judgement_pending', 'settlement admits the persisted source into judgement');
select is((select payload->>'coverage_status' from settled), 'complete', 'one successful source produces complete coverage');

create temporary table judgement_claim as
select public.claim_x_demo_fixed_window_judgement(
  (select (payload->>'run_id')::uuid from demo_run),
  '00000000-0000-0000-0000-000000044002', clock_timestamp()
) as payload;
select is((select payload->>'attempt' from judgement_claim), '1', 'the exact settled run produces one judgement attempt');
create temporary table judgement_context as
select public.get_x_daily_judgement_context(
  (select (payload->>'run_id')::uuid from judgement_claim),
  (select (payload->>'attempt')::integer from judgement_claim),
  '00000000-0000-0000-0000-000000044002'
) as payload;
select is((select payload->>'batch_id' from judgement_context), (select payload->'batch'->>'id' from judgement_claim), 'judgement context remains bound to the exact batch');
select is((select jsonb_array_length(payload->'sources') from judgement_context), 1, 'judgement context contains the included source');
select is((select jsonb_array_length(payload->'sources'->0->'window_segments') from judgement_context), 1, 'judgement context contains the persisted single-blogger segment');

create temporary table judgement_completion as
select public.complete_x_daily_judgement(
  (select (payload->>'run_id')::uuid from judgement_claim),
  (select (payload->>'attempt')::integer from judgement_claim),
  '00000000-0000-0000-0000-000000044002',
  jsonb_build_object(
    'schema_version', 'v4-x-cross-blogger', 'provider', 'mock', 'model_reported', null,
    'prompt_version', 'v4-x-cross-blogger-1',
    'security_industry_viewpoints', jsonb_build_array(jsonb_build_object(
      'statement', '公开 synthetic 跨博主判断', 'action_intent', 'watch',
      'action_scope_status', 'specified', 'action_scope', '公开 synthetic 标的',
      'conditions', '[]'::jsonb, 'supporting_source_ids', jsonb_build_array((select (payload->>'id') from demo_source)),
      'dissenting_source_ids', '[]'::jsonb, 'analysis_ids', jsonb_build_array('ticket-05r-post@2'),
      'evidence_post_ids', jsonb_build_array('ticket-05r-post'), 'uncertainties', '[]'::jsonb
    )),
    'market_structure_viewpoints', '[]'::jsonb, 'strategy_mindset_viewpoints', '[]'::jsonb,
    'uncertainties', '[]'::jsonb
  )
) as payload;
select is((select payload->>'status' from judgement_completion), 'succeeded', 'the synthetic judgement persists through the production completion contract');
select is((select status from public.x_daily_judgement_runs where id = (select (payload->>'run_id')::uuid from judgement_claim)), 'succeeded', 'the exact judgement run reaches succeeded');
select is((select status from public.x_collection_batches where id = (select (payload->'batch'->>'id')::uuid from judgement_claim)), 'succeeded', 'the exact collection batch reaches succeeded');
select is((select status from public.x_demo_fixed_window_runs where id = (select (payload->>'run_id')::uuid from demo_run)), 'complete', 'the exact Demo run reaches complete');
select is((select coverage_status from public.x_daily_judgement_versions where batch_id = (select (payload->'batch'->>'id')::uuid from judgement_claim)), 'complete', 'the persisted judgement version records complete coverage');
select is((select output->'security_industry_viewpoints'->0->>'statement' from public.x_daily_judgement_versions where batch_id = (select (payload->'batch'->>'id')::uuid from judgement_claim)), '公开 synthetic 跨博主判断', 'the persisted judgement retains the safe synthetic viewpoint');

select * from finish();
rollback;
