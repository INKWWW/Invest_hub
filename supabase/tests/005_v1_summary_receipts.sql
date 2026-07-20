begin;

select plan(5);

select has_column('public', 'worker_execution_receipts', 'summary_batch_ids', 'persistence receipts retain batch summary IDs');
select has_column('public', 'worker_execution_receipts', 'daily_summary_ids', 'persistence receipts retain daily summary IDs');

insert into public.workers (id, name, device_secret_hash, status)
values ('00000000-0000-0000-0000-000000005001', 'summary-receipt-worker', 'summary-receipt-hash', 'online');
insert into public.sources (id, source_key, source_type, display_name, parameter_version)
values ('00000000-0000-0000-0000-000000005011', 'summary-receipt-source', 'discord', 'Summary receipt source', 'v1-test-1');
insert into public.sync_tasks (id, task_type, source_id, status, parameter_version, lease_owner, lease_expires_at)
values ('00000000-0000-0000-0000-000000005021', 'discord_sync', '00000000-0000-0000-0000-000000005011', 'leased', 'v1-test-1', '00000000-0000-0000-0000-000000005001', '2099-01-01 00:10:00+00');
insert into public.task_attempts (task_id, attempt, worker_id, status, lease_expires_at)
values ('00000000-0000-0000-0000-000000005021', 1, '00000000-0000-0000-0000-000000005001', 'leased', '2099-01-01 00:10:00+00');

create temporary table persisted_summary_receipt as
select public.persist_worker_execution(
  '00000000-0000-0000-0000-000000005021', 1, '00000000-0000-0000-0000-000000005001',
  '{"contract_version":"v0","task_id":"00000000-0000-0000-0000-000000005021","attempt":1,"source_id":"summary-receipt-source","raw_messages":[{"external_message_id":"summary-message","occurred_at":"2099-01-01T00:00:00Z","local_raw_ref":"local://summary/message.json","payload_hash":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff","retention_expires_at":"2100-01-01T00:00:00Z"}],"canonical_messages":[{"external_message_id":"summary-message","occurred_at":"2099-01-01T00:00:00Z","author_display":"fixture","content":"fixture","has_unparsed_media":false,"metadata":{}}],"structured_runs":[{"chunk_key":"summary-chunk","provider":"mock","parameter_version":"v1-test-1","input_message_ids":["summary-message"],"media_source_message_ids":[],"output":{"topics":[]}}],"batch_summaries":[{"natural_date":"2099-01-01","input_message_ids":["summary-message"],"structured_run_keys":["summary-chunk"],"output":{"topics":[],"warnings":[]},"coverage":{"unparsed_media":false}}]}'::jsonb
) as payload;

select is((select jsonb_array_length(payload -> 'summary_batch_ids')::text from persisted_summary_receipt), '1', 'persistence returns a batch summary receipt');

select throws_ok(
  $$select public.accept_task_result(
    '00000000-0000-0000-0000-000000005021', 1,
    '{"status":"succeeded","summary_batch_ids":[],"daily_summary_ids":[]}'::jsonb,
    '{"worker_id":"00000000-0000-0000-0000-000000005001","persisted":true}'::jsonb
  );$$,
  '55000', null,
  'a result cannot advance checkpoint with missing summary receipt IDs'
);

select is(
  public.accept_task_result(
    '00000000-0000-0000-0000-000000005021', 1,
    jsonb_build_object(
      'status', 'succeeded', 'safe_checkpoint', 'summary-message', 'raw_count', 1, 'canonical_count', 1,
      'structured_run_ids', (select payload -> 'structured_run_ids' from persisted_summary_receipt),
      'summary_batch_ids', (select payload -> 'summary_batch_ids' from persisted_summary_receipt),
      'daily_summary_ids', (select payload -> 'daily_summary_ids' from persisted_summary_receipt)
    ),
    '{"worker_id":"00000000-0000-0000-0000-000000005001","persisted":true}'::jsonb
  ) ->> 'status',
  'succeeded',
  'matching summary receipts permit a checkpoint advance'
);

select * from finish();
rollback;
