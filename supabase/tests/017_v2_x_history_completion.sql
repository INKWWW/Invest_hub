begin;

select plan(6);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at)
values ('00000000-0000-0000-0000-000000017001', 'authenticated', 'authenticated', 'v2-x-history-complete-admin@example.invalid', 'not-a-secret', now());
insert into public.profiles (id, role, display_name)
values ('00000000-0000-0000-0000-000000017001', 'admin', 'X History Completion Admin');
insert into public.sources (id, source_key, source_type, display_name, parameter_version)
values ('00000000-0000-0000-0000-000000017011', 'x-history-completion-source', 'x', 'X History Completion Source', 'v2-history-completion');
insert into public.x_source_profiles (source_id, requested_handle, account_id, display_name, resolution_status)
values ('00000000-0000-0000-0000-000000017011', 'history_complete', 'history_complete', 'X History Completion Source', 'resolved');
insert into public.source_collection_coverage (source_id, coverage_start_at, coverage_through_at)
values ('00000000-0000-0000-0000-000000017011', '2026-07-22T00:00:00+08:00', '2026-07-23T00:00:00+08:00');
insert into public.workers (id, name, device_secret_hash, status)
values ('00000000-0000-0000-0000-000000017101', 'x-history-completion-worker', 'x-history-completion-worker-hash', 'online');
update public.sources
set authorized_worker_id = '00000000-0000-0000-0000-000000017101'
where id = '00000000-0000-0000-0000-000000017011';

create temporary table x_history_completion_task as
select public.create_bounded_x_history_task(
  '00000000-0000-0000-0000-000000017011', 'v2-history-completion', '00000000-0000-0000-0000-000000017001',
  '2026-07-20T00:00:00+08:00', '2026-07-20T08:00:00+08:00'
) as payload;
create temporary table x_history_completion_claim as
select public.claim_next_task('00000000-0000-0000-0000-000000017101', '2026-07-23T00:01:00Z') as payload;
select ok((select payload ? 'capture_range' from x_history_completion_claim), 'history claim returns an immutable capture range');

create temporary table x_history_page_receipt as
select public.record_windowed_capture_segment(
  (select (payload->>'task_id')::uuid from x_history_completion_claim), 1,
  '00000000-0000-0000-0000-000000017101',
  jsonb_build_object(
    'idempotency_key', 'history-page-001', 'request_cursor', null, 'next_cursor', null,
    'oldest_occurred_at', '2026-07-19T16:00:00Z', 'newest_occurred_at', '2026-07-19T16:10:00Z',
    'response_matched', true, 'response_fresh', true
  )
) as payload;
select is((select payload->>'resume_cursor' from x_history_page_receipt), null, 'history page receives a durable null-cursor receipt');

insert into public.canonical_messages (id, source_id, external_message_id, occurred_at, author_display, content)
values ('00000000-0000-0000-0000-000000017201', '00000000-0000-0000-0000-000000017011', 'post-history-completion', '2026-07-19T16:10:00Z', 'X History Completion Source', 'fixture');
insert into public.x_post_contexts (canonical_message_id, post_type, post_url, context_status, attachments)
values ('00000000-0000-0000-0000-000000017201', 'original', 'https://x.com/history_complete/status/1', 'complete', '[]'::jsonb);
update public.sync_task_capture_progress set page_count = 1
where task_id = (select (payload->>'task_id')::uuid from x_history_completion_claim);

create temporary table x_history_completion_result as
select public.complete_bounded_x_history_range(
  (select (payload->>'task_id')::uuid from x_history_completion_claim), 1,
  '00000000-0000-0000-0000-000000017101',
  jsonb_build_object(
    'contract_version', 'v0', 'task_id', (select payload->>'task_id' from x_history_completion_claim), 'attempt', 1,
    'range_complete', true, 'capture_range', (select payload->'capture_range' from x_history_completion_claim),
    'boundary', jsonb_build_object('kind', 'history_exhausted', 'observed_at', '2026-07-19T16:10:00Z'),
    'summary_batch_ids', '[]'::jsonb, 'daily_summary_ids', '[]'::jsonb,
    'x_post_analyses', jsonb_build_array(jsonb_build_object(
      'post_id', 'post-history-completion', 'analysis_id', 'post-history-completion@1', 'analysis_version', 1,
      'blogger_viewpoint', 'fixture viewpoint', 'arguments', jsonb_build_array('fixture argument'),
      'quoted_post_viewpoint', null, 'uncertainties', '[]'::jsonb,
      'evidence_post_ids', jsonb_build_array('post-history-completion'), 'post_link', 'https://x.com/history_complete/status/1'
    )),
    'x_daily_segments', jsonb_build_array(jsonb_build_object(
      'natural_date', '2026-07-20', 'occurred_from_at', '2026-07-19T16:10:00Z', 'occurred_through_at', '2026-07-19T16:10:00Z',
      'window_viewpoints', jsonb_build_array('fixture history viewpoint'), 'analysis_ids', jsonb_build_array('post-history-completion@1'),
      'evidence_post_ids', jsonb_build_array('post-history-completion'), 'uncertainties', '[]'::jsonb
    )), 'no_new_data', false
  )
) as payload;

select is((select payload->>'status' from x_history_completion_result), 'succeeded', 'bounded history completion validates and succeeds');
select is((select payload->>'history_contiguous' from x_history_completion_result), 'false', 'non-contiguous history result is explicitly marked');
select is((select coverage_through_at::text from public.source_collection_coverage where source_id = '00000000-0000-0000-0000-000000017011'), '2026-07-22 16:00:00+00', 'non-contiguous history never moves the continuous waterline');
select is((select capture_range->>'mode' from public.sync_tasks where id = (select (payload->>'task_id')::uuid from x_history_completion_claim)), 'history', 'completed task retains its immutable history range');

select * from finish();
rollback;
