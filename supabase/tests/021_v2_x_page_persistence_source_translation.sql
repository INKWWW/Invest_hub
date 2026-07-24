begin;

select plan(5);

insert into public.workers (id, name, device_secret_hash, status)
values ('00000000-0000-0000-0000-000000021001', 'x-persistence-worker', 'x-persistence-worker-hash', 'online');

insert into public.sources (id, source_key, source_type, display_name, parameter_version, authorized_worker_id)
values ('00000000-0000-0000-0000-000000021011', 'x-persistence-source', 'x', 'X persistence source', 'v2-persistence', '00000000-0000-0000-0000-000000021001');

insert into public.sync_tasks (
  id, task_type, source_id, status, parameter_version, lease_owner, lease_expires_at,
  collection_scope, capture_range, x_source_snapshot
) values (
  '00000000-0000-0000-0000-000000021021',
  'x_sync',
  '00000000-0000-0000-0000-000000021011',
  'running',
  'v2-persistence',
  '00000000-0000-0000-0000-000000021001',
  '2100-01-01T00:00:00Z',
  '{"mode":"window"}'::jsonb,
  '{"mode":"window","trigger":"manual","timezone":"Asia/Shanghai","start_at":"2099-01-01T00:00:00Z","end_at":"2099-01-01T08:00:00Z","scheduled_window_key":null,"overlap_start_at":"2099-01-01T00:00:00Z"}'::jsonb,
  '{"source_type":"x","account_id":"fixture_account","display_name":"X persistence source","parameter_version":"v2-persistence"}'::jsonb
);

insert into public.task_attempts (task_id, attempt, worker_id, status, lease_expires_at)
values ('00000000-0000-0000-0000-000000021021', 1, '00000000-0000-0000-0000-000000021001', 'running', '2100-01-01T00:00:00Z');

insert into public.source_collection_coverage (source_id, coverage_start_at, coverage_through_at)
values ('00000000-0000-0000-0000-000000021011', '2099-01-01T00:00:00Z', '2099-01-01T00:00:00Z');

insert into public.sync_task_capture_progress (task_id, source_id, capture_range)
values (
  '00000000-0000-0000-0000-000000021021',
  '00000000-0000-0000-0000-000000021011',
  '{"mode":"window","trigger":"manual","timezone":"Asia/Shanghai","start_at":"2099-01-01T00:00:00Z","end_at":"2099-01-01T08:00:00Z","scheduled_window_key":null,"overlap_start_at":"2099-01-01T00:00:00Z"}'::jsonb
);

create temporary table x_page_input as
select '{
  "contract_version":"v0",
  "task_id":"00000000-0000-0000-0000-000000021021",
  "attempt":1,
  "source_id":"00000000-0000-0000-0000-000000021011",
  "raw_messages":[{
    "external_message_id":"x-page-post-1",
    "occurred_at":"2099-01-01T01:00:00Z",
    "local_raw_ref":"local://x/page-1",
    "payload_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "retention_expires_at":"2100-01-01T01:00:00Z"
  }],
  "canonical_messages":[{
    "external_message_id":"x-page-post-1",
    "occurred_at":"2099-01-01T01:00:00Z",
    "author_display":"Fixture account",
    "content":"fixture X page content",
    "has_unparsed_media":false,
    "metadata":{"author_id":"fixture_account","post_url":"https://x.com/fixture_account/status/1","post_type":"original","unresolved":false}
  }],
  "structured_runs":[],
  "capture_segment":{
    "idempotency_key":"x-page:1",
    "request_cursor":null,
    "next_cursor":null,
    "oldest_occurred_at":"2099-01-01T01:00:00Z",
    "newest_occurred_at":"2099-01-01T01:00:00Z",
    "response_matched":true,
    "response_fresh":true
  },
  "x_post_contexts":[{
    "external_message_id":"x-page-post-1",
    "post_type":"original",
    "post_url":"https://x.com/fixture_account/status/1",
    "quoted_post_id":null,
    "reply_to_post_id":null,
    "reposted_post_id":null,
    "context_status":"complete",
    "attachments":[]
  }]
}'::jsonb as payload;

create temporary table x_persisted_page as
select public.persist_windowed_capture_page(
  '00000000-0000-0000-0000-000000021021',
  1,
  '00000000-0000-0000-0000-000000021001',
  (select payload from x_page_input)
) as payload;

select is((select payload->>'persisted' from x_persisted_page), 'true', 'an X page persists when the Worker sends its configured source UUID');
select is((select count(*)::text from public.raw_messages where source_id = '00000000-0000-0000-0000-000000021011'), '1', 'the X raw evidence is persisted');
select is((select count(*)::text from public.canonical_messages where source_id = '00000000-0000-0000-0000-000000021011'), '1', 'the X canonical fact is persisted');
select is((select count(*)::text from public.x_post_contexts), '1', 'the X context is persisted with its canonical fact');
select is((select page_count::text from public.sync_task_capture_progress where task_id = '00000000-0000-0000-0000-000000021021'), '1', 'the X page receipt advances durable page progress');

select * from finish();
rollback;
