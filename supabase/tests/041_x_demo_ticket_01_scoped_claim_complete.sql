begin;

select plan(16);

select has_function(
  'public', 'claim_next_x_demo_fixed_window_task', array['uuid', 'timestamp with time zone'],
  'Ticket 01 exposes a scoped claim path for its explicit fixed-window task'
);
select ok(
  has_function_privilege('service_role', 'public.claim_next_x_demo_fixed_window_task(uuid, timestamp with time zone)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.claim_next_x_demo_fixed_window_task(uuid, timestamp with time zone)', 'EXECUTE'),
  'only service_role can execute the scoped fixed-window claim'
);
select ok(
  has_function_privilege('service_role', 'public.complete_windowed_capture_range(uuid, integer, uuid, jsonb)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.complete_windowed_capture_range(uuid, integer, uuid, jsonb)', 'EXECUTE'),
  'only service_role can execute the fixed-window completion path'
);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at)
values ('00000000-0000-0000-0000-000000041001', 'authenticated', 'authenticated', 'ticket-01-scoped@example.invalid', 'not-a-secret', now());
insert into public.profiles (id, role, display_name)
values ('00000000-0000-0000-0000-000000041001', 'admin', 'Ticket 01 scoped admin');
insert into public.workers (id, name, device_secret_hash, status, last_heartbeat_at, capabilities)
values ('00000000-0000-0000-0000-000000041002', 'Ticket 01 scoped Worker', 'ticket-01-scoped-hash', 'online', now(), array['x_sync']);

create temporary table scoped_source as
select public.create_x_source('x:ticket-01-scoped', 'Ticket 01 scoped blogger', 'scoped_fixture', 'x-standard-v2', '00000000-0000-0000-0000-000000041001') as payload;
select public.claim_next_x_activation('00000000-0000-0000-0000-000000041002', now());
select public.resolve_x_source_identity(
  (select (payload->>'id')::uuid from scoped_source),
  '00000000-0000-0000-0000-000000041002', 'x-standard-v2', 'scoped_fixture'
);
select public.initialize_x_collection_coverage(
  (select (payload->>'id')::uuid from scoped_source),
  '00000000-0000-0000-0000-000000041001', '2026-08-16T16:00:00+08:00'
);

insert into public.sync_tasks (
  id, task_type, source_id, status, parameter_version, collection_scope, capture_range,
  author_profile_snapshot, x_source_snapshot, queued_at
) values (
  '00000000-0000-0000-0000-000000041003', 'x_sync',
  (select (payload->>'id')::uuid from scoped_source), 'retryable_failed', 'x-standard-v2',
  '{"mode":"window"}'::jsonb,
  '{"mode":"window","trigger":"scheduled","timezone":"Asia/Shanghai","start_at":"2026-08-16T08:00:00Z","end_at":"2026-08-16T12:00:00Z","scheduled_window_key":"2026-08-16T20:00+08:00","overlap_start_at":"2026-08-16T08:00:00Z"}'::jsonb,
  '[]'::jsonb,
  '{"source_type":"x","account_id":"scoped_fixture","display_name":"Ticket 01 scoped blogger","parameter_version":"x-standard-v2"}'::jsonb,
  '2026-08-16T12:01:00Z'
);

create temporary table scoped_task as
select public.create_x_demo_fixed_window_task(
  (select (payload->>'id')::uuid from scoped_source),
  '2026-08-17T16:00:00+08:00',
  '00000000-0000-0000-0000-000000041001'
) as payload;
create temporary table scoped_task_again as
select public.create_x_demo_fixed_window_task(
  (select (payload->>'id')::uuid from scoped_source),
  '2026-08-17T16:00:00+08:00',
  '00000000-0000-0000-0000-000000041001'
) as payload;

select is((select payload->>'idempotent' from scoped_task), 'false', 'the first explicit fixed-window request creates one task');
select is((select payload->>'idempotent' from scoped_task_again), 'true', 'the same source and cutoff are idempotent');
select is((select payload->>'id' from scoped_task_again), (select payload->>'id' from scoped_task), 'idempotent creation reuses the existing task');
select throws_ok(
  $$select public.create_x_demo_fixed_window_task(
    (select (payload->>'id')::uuid from scoped_source),
    '2099-01-01T00:00:00+08:00',
    '00000000-0000-0000-0000-000000041001'
  )$$,
  '22023', 'future_x_demo_cutoff', 'the server rejects a fixed-window target that has not ended'
);
select throws_ok(
  $$select public.x_demo_fixed_window_bounds('2026-08-17T16:00:01+08:00')$$,
  '22023', 'invalid_x_demo_cutoff', 'non-zero cutoff seconds are rejected'
);

create temporary table scoped_claim as
select public.claim_next_task('00000000-0000-0000-0000-000000041002', '2026-08-18T00:00:00Z') as payload;
select is(
  (select payload->>'task_id' from scoped_claim),
  (select payload->>'id' from scoped_task),
  'generic Worker claim selects the explicit fixed window before an older retryable gap'
);
select is((select payload->'capture_range'->>'start_at' from scoped_claim), '2026-08-17T04:00:00+00:00', 'scoped claim keeps the exact target start');
select is((select payload->'capture_range'->>'end_at' from scoped_claim), '2026-08-17T08:00:00+00:00', 'scoped claim keeps the exact target end');

-- Keep the completion assertions executable during Red: the baseline may have
-- leased the old gap, while the candidate must already have leased the target.
update public.sync_tasks set status = 'succeeded', lease_owner = null, lease_expires_at = null
where id = '00000000-0000-0000-0000-000000041003';
create temporary table scoped_execution_claim as
select case
  when (select payload->>'task_id' from scoped_claim) = (select payload->>'id' from scoped_task)
    then (select payload from scoped_claim)
  else public.claim_next_task('00000000-0000-0000-0000-000000041002', '2026-08-18T00:00:00Z')
end as payload;

insert into public.canonical_messages (id, source_id, external_message_id, occurred_at, author_display, content)
values ('00000000-0000-0000-0000-000000041004', (select (payload->>'id')::uuid from scoped_source), 'scoped-post', '2026-08-17T05:00:00Z', 'Ticket 01 scoped blogger', '公开 synthetic fixture');
insert into public.x_post_contexts (canonical_message_id, post_type, post_url, context_status, attachments)
values ('00000000-0000-0000-0000-000000041004', 'original', 'https://x.com/scoped_fixture/status/1', 'complete', '[]'::jsonb);
update public.sync_task_capture_progress set page_count = 1
where task_id = (select (payload->>'task_id')::uuid from scoped_execution_claim);

create temporary table scoped_completion (payload jsonb);
do $$
begin
  insert into scoped_completion
  select public.complete_windowed_capture_range(
  (select (payload->>'task_id')::uuid from scoped_execution_claim), 1,
  '00000000-0000-0000-0000-000000041002',
  jsonb_build_object(
    'contract_version', 'v0', 'task_id', (select payload->>'task_id' from scoped_claim), 'attempt', 1,
    'range_complete', true, 'capture_range', (select payload->'capture_range' from scoped_execution_claim),
    'boundary', jsonb_build_object('kind', 'history_exhausted', 'observed_at', '2026-08-17T05:00:00Z'),
    'summary_batch_ids', '[]'::jsonb, 'daily_summary_ids', '[]'::jsonb,
    'x_post_analyses', jsonb_build_array(jsonb_build_object(
      'post_id', 'scoped-post', 'analysis_id', 'scoped-post@2', 'analysis_version', 2,
      'schema_version', 'v4-x-post-analysis', 'prompt_version', 'v4-x-post-analysis-1',
      'analysis_output', jsonb_build_object('schema_version', 'v4-x-post-analysis', 'post_id', 'scoped-post', 'investment_relevance', 'investment_related', 'investment_categories', jsonb_build_array('security_industry'), 'blogger_viewpoint', '公开 synthetic 观点', 'action_intent', 'watch', 'action_scope_status', 'specified', 'action_scope', '公开 synthetic 标的', 'conditions', '[]'::jsonb, 'arguments', jsonb_build_array('公开 synthetic 论据'), 'quoted_post_viewpoint', null, 'uncertainties', '[]'::jsonb, 'evidence_post_ids', jsonb_build_array('scoped-post'), 'post_link', 'https://x.com/scoped_fixture/status/1'),
      'blogger_viewpoint', '公开 synthetic 观点', 'arguments', jsonb_build_array('公开 synthetic 论据'), 'quoted_post_viewpoint', null, 'uncertainties', '[]'::jsonb,
      'evidence_post_ids', jsonb_build_array('scoped-post'), 'post_link', 'https://x.com/scoped_fixture/status/1'
    )),
    'x_daily_segments', jsonb_build_array(jsonb_build_object(
      'natural_date', '2026-08-17', 'occurred_from_at', '2026-08-17T05:00:00Z', 'occurred_through_at', '2026-08-17T05:00:00Z',
      'schema_version', 'v4-x-window', 'prompt_version', 'v4-x-window-1', 'segment_output', jsonb_build_object(
        'schema_version', 'v4-x-window', 'range_task_id', (select payload->>'task_id' from scoped_execution_claim), 'natural_date', '2026-08-17',
        'occurred_from_at', '2026-08-17T05:00:00Z', 'occurred_through_at', '2026-08-17T05:00:00Z',
        'security_industry_viewpoints', jsonb_build_array(jsonb_build_object('statement', '公开 synthetic 窗口观点', 'action_intent', 'watch', 'action_scope_status', 'specified', 'action_scope', '公开 synthetic 标的', 'conditions', '[]'::jsonb, 'analysis_ids', jsonb_build_array('scoped-post@2'), 'evidence_post_ids', jsonb_build_array('scoped-post'), 'uncertainties', '[]'::jsonb)),
        'market_structure_viewpoints', '[]'::jsonb, 'strategy_mindset_viewpoints', '[]'::jsonb, 'analysis_ids', jsonb_build_array('scoped-post@2'), 'evidence_post_ids', jsonb_build_array('scoped-post'), 'uncertainties', '[]'::jsonb
      ),
      'window_viewpoints', '[]'::jsonb, 'analysis_ids', jsonb_build_array('scoped-post@2'), 'evidence_post_ids', jsonb_build_array('scoped-post'), 'uncertainties', '[]'::jsonb
    )), 'no_new_data', false
  ));
exception when others then
  insert into scoped_completion values (jsonb_build_object('error', sqlstate));
end;
$$;

update public.sync_tasks set status = 'retryable_failed'
where id = '00000000-0000-0000-0000-000000041003';
select is((select payload->>'status' from scoped_completion), 'succeeded', 'the scoped fixed window completes through the existing range completion contract');
select is((select status from public.sync_tasks where id = (select (payload->>'task_id')::uuid from scoped_execution_claim)), 'succeeded', 'the scoped task is marked succeeded');
select is((select count(*)::int from public.x_post_analyses where canonical_message_id = '00000000-0000-0000-0000-000000041004'), 1, 'one v4 per-post analysis is persisted');
select is((select count(*)::int from public.x_daily_viewpoint_segments where range_task_id = (select (payload->>'task_id')::uuid from scoped_execution_claim)), 1, 'one single-blogger window aggregate is persisted');
select is((select status from public.sync_tasks where id = '00000000-0000-0000-0000-000000041003'), 'retryable_failed', 'the older gap remains audit history and does not block scoped completion');

select * from finish();
rollback;
