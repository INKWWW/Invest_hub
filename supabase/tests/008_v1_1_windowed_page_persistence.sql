begin;

select plan(6);

select has_function(
  'public',
  'persist_windowed_capture_page',
  array['uuid', 'integer', 'uuid', 'jsonb'],
  'a V1.1 page persistence function atomically stores facts and its segment'
);

insert into public.workers (id, name, device_secret_hash, status)
values ('00000000-0000-0000-0000-000000008001', 'v11-page-worker', 'v11-page-worker-hash', 'online');

insert into public.sources (id, source_key, source_type, display_name, parameter_version)
values ('00000000-0000-0000-0000-000000008011', 'discord-v11-page', 'discord', 'V1.1 page source', 'v1.1-test');

insert into public.sync_tasks (
  id, task_type, source_id, status, parameter_version, lease_owner, lease_expires_at, collection_scope, capture_range
) values (
  '00000000-0000-0000-0000-000000008021',
  'discord_sync',
  '00000000-0000-0000-0000-000000008011',
  'running',
  'v1.1-test',
  '00000000-0000-0000-0000-000000008001',
  '2100-01-01T00:00:00Z',
  '{"mode":"window"}'::jsonb,
  '{"mode":"window","trigger":"manual","timezone":"Asia/Shanghai","start_at":"2099-01-01T00:00:00Z","end_at":"2099-01-01T08:00:00Z","scheduled_window_key":null}'::jsonb
);

insert into public.task_attempts (task_id, attempt, worker_id, status, lease_expires_at)
values (
  '00000000-0000-0000-0000-000000008021', 1,
  '00000000-0000-0000-0000-000000008001', 'running', '2100-01-01T00:00:00Z'
);

insert into public.sync_task_capture_progress (task_id, source_id, capture_range)
values (
  '00000000-0000-0000-0000-000000008021',
  '00000000-0000-0000-0000-000000008011',
  '{"mode":"window","trigger":"manual","timezone":"Asia/Shanghai","start_at":"2099-01-01T00:00:00Z","end_at":"2099-01-01T08:00:00Z","scheduled_window_key":null}'::jsonb
);

create temporary table page_input as
select '{
    "contract_version":"v0",
    "task_id":"00000000-0000-0000-0000-000000008021",
    "attempt":1,
    "source_id":"discord-v11-page",
    "raw_messages":[{
      "external_message_id":"page-message-1",
      "occurred_at":"2099-01-01T01:00:00Z",
      "local_raw_ref":"local://discord/page-1",
      "payload_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "retention_expires_at":"2100-01-01T00:00:00Z"
    }],
    "canonical_messages":[{
      "external_message_id":"page-message-1",
      "occurred_at":"2099-01-01T01:00:00Z",
      "author_display":"Fixture author",
      "content":"fixture page content",
      "has_unparsed_media":false,
      "metadata":{"author_id":"fixture-author"}
    }],
    "structured_runs":[],
    "capture_segment":{
      "idempotency_key":"page:1",
      "request_cursor":null,
      "next_cursor":"cursor-1",
      "oldest_occurred_at":"2099-01-01T01:00:00Z",
      "newest_occurred_at":"2099-01-01T01:00:00Z",
      "response_matched":true,
      "response_fresh":true
    }
  }'::jsonb as payload;

create temporary table persisted_page as
select public.persist_windowed_capture_page(
  '00000000-0000-0000-0000-000000008021',
  1,
  '00000000-0000-0000-0000-000000008001',
  (select payload from page_input)
) as payload;

select is((select payload ->> 'persisted' from persisted_page), 'true', 'the page facts and segment receive one durable acknowledgement');
select is(
  (select resume_cursor from public.sync_task_capture_progress where task_id = '00000000-0000-0000-0000-000000008021'),
  'cursor-1',
  'only the confirmed page segment advances the recovery cursor'
);
select is(
  (select content from public.canonical_messages where source_id = '00000000-0000-0000-0000-000000008011' and external_message_id = 'page-message-1'),
  'fixture page content',
  'the same transaction persists the page canonical fact'
);
select is(
  (select count(*)::text from public.worker_execution_receipts where task_id = '00000000-0000-0000-0000-000000008021'),
  '0',
  'a partial page cannot create the final range completion receipt'
);
select is(
  public.persist_windowed_capture_page(
    '00000000-0000-0000-0000-000000008021',
    1,
    '00000000-0000-0000-0000-000000008001',
    (select payload from page_input)
  ) ->> 'idempotent',
  'true',
  'replaying a persisted page after an acknowledgement is idempotent'
);

select * from finish();
rollback;
