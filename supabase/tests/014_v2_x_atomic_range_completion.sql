begin;

select plan(9);

select is(
  (
    select coalesce(array_to_string(proconfig, ','), '') like '%lock_timeout=5s%'
    from pg_proc
    where oid = 'public.complete_windowed_capture_range(uuid, integer, uuid, jsonb)'::regprocedure
  ),
  true,
  'X range completion bounds lock waits so a stale request cannot hold the Worker past its deadline'
);

select throws_ok(
  $$select public.complete_windowed_capture_range(
    '00000000-0000-0000-0000-000000014999'::uuid,
    1,
    '00000000-0000-0000-0000-000000014998'::uuid,
    '{}'::jsonb
  )$$,
  'PT409',
  'lease_mismatch',
  'X range completion reports a business lease conflict without using a serialization failure code'
);

insert into public.sources (id, source_key, source_type, display_name, parameter_version)
values ('00000000-0000-0000-0000-000000014001', 'x-completion-source', 'x', 'X completion source', 'v2-completion');
insert into public.x_source_profiles (source_id, requested_handle, account_id, display_name, resolution_status)
values ('00000000-0000-0000-0000-000000014001', 'completion_author', 'account-completion', 'Completion Author', 'resolved');
insert into public.source_collection_coverage (source_id, coverage_start_at, coverage_through_at)
values ('00000000-0000-0000-0000-000000014001', '2026-07-23T00:00:00+08:00', '2026-07-23T00:00:00+08:00');
insert into public.workers (id, name, device_secret_hash, status)
values ('00000000-0000-0000-0000-000000014101', 'x-completion-worker', 'x-completion-worker-hash', 'online');
update public.sources
set authorized_worker_id = '00000000-0000-0000-0000-000000014101'
where id = '00000000-0000-0000-0000-000000014001';

create temporary table x_completion_task as
select public.create_windowed_x_sync_task(
  '00000000-0000-0000-0000-000000014001', 'v2-completion', null, 'scheduled',
  '2026-07-23T12:00:00+08:00', '2026-07-23T12:00+08:00'
) as payload;
create temporary table x_completion_claim as
select public.claim_next_task('00000000-0000-0000-0000-000000014101', '2026-07-23T00:01:00Z') as payload;

insert into public.canonical_messages (id, source_id, external_message_id, occurred_at, author_display, content)
values ('00000000-0000-0000-0000-000000014201', '00000000-0000-0000-0000-000000014001', 'post-completion', '2026-07-23T00:10:00Z', 'Completion Author', 'fixture');
insert into public.x_post_contexts (canonical_message_id, post_type, post_url, context_status, attachments)
values ('00000000-0000-0000-0000-000000014201', 'original', 'https://x.com/completion_author/status/1', 'complete', '[]'::jsonb);
update public.sync_task_capture_progress set page_count = 1
where task_id = (select (payload->>'task_id')::uuid from x_completion_claim);

create temporary table x_completion_result as
select public.complete_windowed_capture_range(
  (select (payload->>'task_id')::uuid from x_completion_claim), 1,
  '00000000-0000-0000-0000-000000014101',
  jsonb_build_object(
    'contract_version', 'v0', 'task_id', (select payload->>'task_id' from x_completion_claim), 'attempt', 1,
    'range_complete', true, 'capture_range', (select payload->'capture_range' from x_completion_claim),
    'boundary', jsonb_build_object('kind', 'history_exhausted', 'observed_at', '2026-07-23T00:10:00Z'),
    'summary_batch_ids', '[]'::jsonb, 'daily_summary_ids', '[]'::jsonb,
    'x_post_analyses', jsonb_build_array(jsonb_build_object(
      'post_id', 'post-completion', 'analysis_id', 'post-completion@1', 'analysis_version', 1,
      'blogger_viewpoint', 'fixture viewpoint', 'arguments', jsonb_build_array('fixture argument'),
      'quoted_post_viewpoint', null, 'uncertainties', '[]'::jsonb,
      'evidence_post_ids', jsonb_build_array('post-completion'), 'post_link', 'https://x.com/completion_author/status/1'
    )),
    'x_daily_segments', jsonb_build_array(jsonb_build_object(
      'natural_date', '2026-07-23', 'occurred_from_at', '2026-07-23T00:10:00Z', 'occurred_through_at', '2026-07-23T00:10:00Z',
      'window_viewpoints', jsonb_build_array('fixture window viewpoint'), 'analysis_ids', jsonb_build_array('post-completion@1'),
      'evidence_post_ids', jsonb_build_array('post-completion'), 'uncertainties', '[]'::jsonb
    )), 'no_new_data', false
  )
) as payload;

select is((select payload->>'status' from x_completion_result), 'succeeded', 'X completion atomically succeeds after page evidence exists');
select is((select status from public.sync_tasks where id = (select (payload->>'task_id')::uuid from x_completion_claim)), 'succeeded', 'X task is completed only with its immutable analysis');
select is((select coverage_through_at::text from public.source_collection_coverage where source_id = '00000000-0000-0000-0000-000000014001'), '2026-07-23 04:00:00+00', 'completion advances exactly to the fixed X range end');
select is((select count(*)::text from public.x_post_analyses where canonical_message_id = '00000000-0000-0000-0000-000000014201'), '1', 'one immutable analysis is stored for the in-range post');
select is((select count(*)::text from public.x_daily_viewpoint_segments where range_task_id = (select (payload->>'task_id')::uuid from x_completion_claim)), '1', 'one append-only daily viewpoint segment is stored');
select is((select (post_analysis_refs->0->>'post_id') from public.x_daily_viewpoint_segments where range_task_id = (select (payload->>'task_id')::uuid from x_completion_claim)), 'post-completion', 'daily segment points to the exact persisted post analysis');
select is((select payload->'x_daily_segment_ids'->0 is not null from x_completion_result), true, 'completion receipt returns the created immutable segment identity');

select * from finish();
rollback;
