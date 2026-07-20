begin;

select plan(12);

select has_function(
  'public',
  'persist_worker_execution',
  array['uuid', 'integer', 'uuid', 'jsonb'],
  'worker persistence function exists'
);

insert into public.workers (id, name, device_secret_hash, status)
values ('00000000-0000-0000-0000-000000000111', 'persistence-worker', 'hash-persistence-worker', 'online');

insert into public.sources (id, source_key, source_type, display_name, parameter_version)
values ('00000000-0000-0000-0000-000000000121', 'discord-persistence-test', 'discord', 'Persistence test source', 'v0-test-1');

insert into public.sync_tasks (id, task_type, source_id, status, parameter_version, lease_owner, lease_expires_at)
values (
  '00000000-0000-0000-0000-000000000131',
  'discord_sync',
  '00000000-0000-0000-0000-000000000121',
  'leased',
  'v0-test-1',
  '00000000-0000-0000-0000-000000000111',
  '2099-01-01 00:10:00+00'
);

insert into public.task_attempts (task_id, attempt, worker_id, status, lease_expires_at)
values (
  '00000000-0000-0000-0000-000000000131',
  1,
  '00000000-0000-0000-0000-000000000111',
  'leased',
  '2099-01-01 00:10:00+00'
);

insert into public.sync_tasks (id, task_type, source_id, status, parameter_version, lease_owner, lease_expires_at)
values (
  '00000000-0000-0000-0000-000000000132',
  'discord_sync',
  '00000000-0000-0000-0000-000000000121',
  'leased',
  'v0-test-1',
  '00000000-0000-0000-0000-000000000111',
  '2099-01-01 00:10:00+00'
);

insert into public.task_attempts (task_id, attempt, worker_id, status, lease_expires_at)
values (
  '00000000-0000-0000-0000-000000000132',
  1,
  '00000000-0000-0000-0000-000000000111',
  'leased',
  '2099-01-01 00:10:00+00'
);

select throws_ok(
  $$select public.accept_task_result(
    '00000000-0000-0000-0000-000000000132',
    1,
    '{"status":"succeeded","safe_checkpoint":"forged","raw_count":0,"canonical_count":0,"structured_run_ids":[]}'::jsonb,
    '{"worker_id":"00000000-0000-0000-0000-000000000111","persisted":true}'::jsonb
  );$$,
  '55000',
  null,
  'a claimed task cannot advance a checkpoint from a forged persistence flag'
);

select is(
  public.persist_worker_execution(
    '00000000-0000-0000-0000-000000000131',
    1,
    '00000000-0000-0000-0000-000000000111',
    '{
      "contract_version":"v0",
      "task_id":"00000000-0000-0000-0000-000000000131",
      "attempt":1,
      "source_id":"discord-persistence-test",
      "raw_messages":[{"external_message_id":"message-1","occurred_at":"2099-01-01T00:00:00Z","local_raw_ref":"local://v0/raw/message-1.json","payload_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retention_expires_at":"2100-01-01T00:00:00Z"}],
      "canonical_messages":[{"external_message_id":"message-1","occurred_at":"2099-01-01T00:00:00Z","author_display":"fixture-author","content":"fixture content","has_unparsed_media":false,"metadata":{}}],
      "structured_runs":[{"chunk_key":"chunk-1","provider":"mock","parameter_version":"v0-test-1","input_message_ids":["message-1"],"media_source_message_ids":[],"output":{"topics":[]}}]
    }'::jsonb
  ) ->> 'persisted',
  'true',
  'leased worker persists a complete execution payload'
);

select is((select count(*)::text from public.raw_messages where source_id = '00000000-0000-0000-0000-000000000121'), '1', 'raw retention reference is stored');
select is((select count(*)::text from public.canonical_messages where source_id = '00000000-0000-0000-0000-000000000121'), '1', 'canonical content is stored');
select is((select count(*)::text from public.structured_runs where task_id = '00000000-0000-0000-0000-000000000131'), '1', 'structured output is stored');
select is((select count(*)::text from public.evidence_refs), '2', 'message and local raw evidence are linked');

select is(
  public.persist_worker_execution(
    '00000000-0000-0000-0000-000000000131',
    1,
    '00000000-0000-0000-0000-000000000111',
    '{
      "contract_version":"v0",
      "task_id":"00000000-0000-0000-0000-000000000131",
      "attempt":1,
      "source_id":"discord-persistence-test",
      "raw_messages":[{"external_message_id":"message-1","occurred_at":"2099-01-01T00:00:00Z","local_raw_ref":"local://v0/raw/message-1.json","payload_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retention_expires_at":"2100-01-01T00:00:00Z"}],
      "canonical_messages":[{"external_message_id":"message-1","occurred_at":"2099-01-01T00:00:00Z","author_display":"fixture-author","content":"fixture content","has_unparsed_media":false,"metadata":{}}],
      "structured_runs":[{"chunk_key":"chunk-1","provider":"mock","parameter_version":"v0-test-1","input_message_ids":["message-1"],"media_source_message_ids":[],"output":{"topics":[]}}]
    }'::jsonb
  ) ->> 'idempotent',
  'true',
  'repeating identical persistence is idempotent'
);
select is((select count(*)::text from public.structured_runs where task_id = '00000000-0000-0000-0000-000000000131'), '1', 'idempotent persistence does not duplicate runs');

select throws_ok(
  $$select public.persist_worker_execution(
    '00000000-0000-0000-0000-000000000131',
    1,
    '00000000-0000-0000-0000-000000000111',
    '{"contract_version":"v0","task_id":"00000000-0000-0000-0000-000000000131","attempt":1,"source_id":"wrong-source","raw_messages":[],"canonical_messages":[],"structured_runs":[]}'::jsonb
  );$$,
  '22023',
  null,
  'worker cannot persist a payload for a different source'
);

select is(
  public.persist_worker_execution(
    '00000000-0000-0000-0000-000000000132',
    1,
    '00000000-0000-0000-0000-000000000111',
    '{
      "contract_version":"v0",
      "task_id":"00000000-0000-0000-0000-000000000132",
      "attempt":1,
      "source_id":"discord-persistence-test",
      "raw_messages":[{"external_message_id":"message-1","occurred_at":"2099-01-01T00:00:00Z","local_raw_ref":"local://v0/raw/recapture-message-1.json","payload_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retention_expires_at":"2100-01-01T00:00:00Z"}],
      "canonical_messages":[{"external_message_id":"message-1","occurred_at":"2099-01-01T00:00:00Z","author_display":"fixture-author","content":"fixture content","has_unparsed_media":false,"metadata":{}}],
      "structured_runs":[{"chunk_key":"recapture-chunk-1","provider":"mock","parameter_version":"v0-test-1","input_message_ids":["message-1"],"media_source_message_ids":[],"output":{"topics":[]}}]
    }'::jsonb
  ) ->> 'persisted',
  'true',
  'a same-payload recapture may use a new local evidence reference'
);

select is(
  public.accept_task_result(
    '00000000-0000-0000-0000-000000000131',
    1,
    jsonb_build_object(
      'status', 'succeeded',
      'safe_checkpoint', 'message-1',
      'raw_count', 1,
      'canonical_count', 1,
      'structured_run_ids', (
        select structured_run_ids
        from public.worker_execution_receipts
        where task_id = '00000000-0000-0000-0000-000000000131'
      )
    ),
    '{"worker_id":"00000000-0000-0000-0000-000000000111","persisted":true}'::jsonb
  ) ->> 'status',
  'succeeded',
  'checkpoint advances only after the persisted execution is accepted'
);

select * from finish();
rollback;
