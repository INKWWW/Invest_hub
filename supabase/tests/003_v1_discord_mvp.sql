begin;

select plan(28);

select has_column('public', 'sources', 'authorized_worker_id', 'sources bind a logical source to an authorized worker');
select has_column('public', 'sync_tasks', 'rule_snapshot', 'tasks retain an immutable target-author snapshot');
select has_column('public', 'sync_tasks', 'collection_scope', 'tasks retain a finite collection scope');
select has_table('public', 'source_author_rules', 'source author rule table exists');
select has_table('public', 'summary_batches', 'batch summary table exists');
select has_table('public', 'daily_summaries', 'daily summary version table exists');
select has_column('public', 'summary_batches', 'structured_run_ids', 'batch summaries retain structured-run evidence');
select has_column('public', 'daily_summaries', 'is_current', 'daily summaries retain a current-version pointer');

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at)
values
  ('00000000-0000-0000-0000-000000003001', 'authenticated', 'authenticated', 'v1-admin@example.invalid', 'not-a-secret', now()),
  ('00000000-0000-0000-0000-000000003002', 'authenticated', 'authenticated', 'v1-reader@example.invalid', 'not-a-secret', now());

insert into public.profiles (id, role, display_name)
values
  ('00000000-0000-0000-0000-000000003001', 'admin', 'V1 Admin'),
  ('00000000-0000-0000-0000-000000003002', 'user', 'V1 Reader');

insert into public.workers (id, name, device_secret_hash, status)
values
  ('00000000-0000-0000-0000-000000003011', 'v1-authorized-worker', 'hash-v1-authorized', 'online'),
  ('00000000-0000-0000-0000-000000003012', 'v1-other-worker', 'hash-v1-other', 'online');

insert into public.sources (id, source_key, source_type, display_name, parameter_version, authorized_worker_id)
values ('00000000-0000-0000-0000-000000003021', 'discord-v1-bound', 'discord', 'V1 bound source', 'v1-test-1', '00000000-0000-0000-0000-000000003011');

insert into public.sources (id, source_key, source_type, display_name, parameter_version)
values ('00000000-0000-0000-0000-000000003022', 'discord-v1-foreign', 'discord', 'V1 foreign source', 'v1-test-1');

insert into public.canonical_messages (source_id, external_message_id, occurred_at, content)
values ('00000000-0000-0000-0000-000000003022', 'foreign-message', '2099-01-01 00:00:00+00', 'foreign fixture content');

select throws_ok(
  $$insert into public.sync_tasks (task_type, source_id, parameter_version, rule_snapshot, collection_scope)
    values (
      'discord_sync',
      '00000000-0000-0000-0000-000000003021',
      'v1-test-1',
      '{"version":1.5,"target_author_ids":[]}'::jsonb,
      '{"mode":"incremental","max_pages":1}'::jsonb
    );$$,
  '23514',
  null,
  'task rule snapshot version must be an integer'
);

insert into public.source_author_rules (id, author_id, scope, source_id, policy, enabled, version, created_by)
values
  ('00000000-0000-0000-0000-000000003041', 'author-global', 'global', null, 'target', true, 1, '00000000-0000-0000-0000-000000003001'),
  ('00000000-0000-0000-0000-000000003042', 'author-source', 'source', '00000000-0000-0000-0000-000000003021', 'target', true, 1, '00000000-0000-0000-0000-000000003001'),
  ('00000000-0000-0000-0000-000000003043', 'author-global', 'source', '00000000-0000-0000-0000-000000003021', 'exclude', true, 1, '00000000-0000-0000-0000-000000003001');

insert into public.sync_tasks (
  id, task_type, source_id, parameter_version, requested_by, rule_snapshot, collection_scope
)
values (
  '00000000-0000-0000-0000-000000003031',
  'discord_sync',
  '00000000-0000-0000-0000-000000003021',
  'v1-test-1',
  '00000000-0000-0000-0000-000000003001',
  '{"version":1,"target_author_ids":["author-source"]}'::jsonb,
  '{"mode":"incremental","max_pages":5}'::jsonb
);

select is(
  public.claim_next_task('00000000-0000-0000-0000-000000003012', '2099-01-01 00:00:00+00'),
  null,
  'a non-authorized worker cannot claim a bound source'
);

create temporary table captured_v1_claim as
select public.claim_next_task('00000000-0000-0000-0000-000000003011', '2099-01-01 00:00:01+00') as payload;

select is(
  (select payload -> 'rule_snapshot' ->> 'version' from captured_v1_claim),
  '1',
  'the claim contains the frozen rule snapshot'
);

select is(
  (select payload -> 'collection_scope' ->> 'max_pages' from captured_v1_claim),
  '5',
  'the claim contains the finite collection scope'
);

update public.source_author_rules
set enabled = false, version = 2
where id = '00000000-0000-0000-0000-000000003042';

select is(
  (select rule_snapshot -> 'target_author_ids' ->> 0 from public.sync_tasks where id = '00000000-0000-0000-0000-000000003031'),
  'author-source',
  'rule changes after queueing do not rewrite a task snapshot'
);

insert into public.sync_tasks (
  id, task_type, source_id, status, parameter_version, requested_by, lease_owner, lease_expires_at, rule_snapshot, collection_scope
)
values (
  '00000000-0000-0000-0000-000000003032',
  'discord_sync',
  '00000000-0000-0000-0000-000000003021',
  'leased',
  'v1-test-1',
  '00000000-0000-0000-0000-000000003001',
  '00000000-0000-0000-0000-000000003011',
  '2099-01-01 00:10:00+00',
  '{"version":1,"target_author_ids":["author-source"]}'::jsonb,
  '{"mode":"history","max_pages":2}'::jsonb
);

insert into public.task_attempts (task_id, attempt, worker_id, status, lease_expires_at)
values (
  '00000000-0000-0000-0000-000000003032', 1, '00000000-0000-0000-0000-000000003011', 'leased', '2099-01-01 00:10:00+00'
);

insert into public.sync_tasks (
  id, task_type, source_id, status, parameter_version, lease_owner, lease_expires_at, rule_snapshot, collection_scope
)
values
  ('00000000-0000-0000-0000-000000003033', 'discord_sync', '00000000-0000-0000-0000-000000003021', 'leased', 'v1-test-1', '00000000-0000-0000-0000-000000003011', '2099-01-01 00:10:00+00', '{"version":1,"target_author_ids":["author-source"]}'::jsonb, '{"mode":"incremental","max_pages":1}'::jsonb),
  ('00000000-0000-0000-0000-000000003034', 'discord_sync', '00000000-0000-0000-0000-000000003021', 'leased', 'v1-test-1', '00000000-0000-0000-0000-000000003011', '2099-01-01 00:10:00+00', '{"version":1,"target_author_ids":["author-source"]}'::jsonb, '{"mode":"incremental","max_pages":1}'::jsonb),
  ('00000000-0000-0000-0000-000000003035', 'discord_sync', '00000000-0000-0000-0000-000000003021', 'leased', 'v1-test-1', '00000000-0000-0000-0000-000000003011', '2099-01-01 00:10:00+00', '{"version":1,"target_author_ids":["author-source"]}'::jsonb, '{"mode":"incremental","max_pages":1}'::jsonb);

insert into public.task_attempts (task_id, attempt, worker_id, status, lease_expires_at)
values
  ('00000000-0000-0000-0000-000000003033', 1, '00000000-0000-0000-0000-000000003011', 'leased', '2099-01-01 00:10:00+00'),
  ('00000000-0000-0000-0000-000000003034', 1, '00000000-0000-0000-0000-000000003011', 'leased', '2099-01-01 00:10:00+00'),
  ('00000000-0000-0000-0000-000000003035', 1, '00000000-0000-0000-0000-000000003011', 'leased', '2099-01-01 00:10:00+00');

select is(
  public.persist_worker_execution(
    '00000000-0000-0000-0000-000000003032',
    1,
    '00000000-0000-0000-0000-000000003011',
    '{
      "contract_version":"v0",
      "task_id":"00000000-0000-0000-0000-000000003032",
      "attempt":1,
      "source_id":"discord-v1-bound",
      "raw_messages":[{"external_message_id":"v1-message-1","occurred_at":"2099-01-01T00:00:00Z","local_raw_ref":"local://v1/raw/v1-message-1.json","payload_hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","retention_expires_at":"2100-01-01T00:00:00Z"}],
      "canonical_messages":[{"external_message_id":"v1-message-1","occurred_at":"2099-01-01T00:00:00Z","author_display":"fixture-author","content":"fixture content","has_unparsed_media":false,"metadata":{"author_id":"author-source"}}],
      "structured_runs":[{"chunk_key":"chunk-v1-1","provider":"mock","parameter_version":"v1-test-1","input_message_ids":["v1-message-1"],"media_source_message_ids":[],"output":{"topics":[]}}],
      "batch_summaries":[{"natural_date":"2099-01-01","input_message_ids":["v1-message-1"],"structured_run_keys":["chunk-v1-1"],"output":{"topics":[],"warnings":[]},"coverage":{"unparsed_media":false}}]
    }'::jsonb
  ) ->> 'persisted',
  'true',
  'complete persistence includes an evidence-backed batch summary'
);

select is((select count(*)::text from public.summary_batches where task_id = '00000000-0000-0000-0000-000000003032'), '1', 'one batch summary is written');
select is((select count(*)::text from public.daily_summaries where source_id = '00000000-0000-0000-0000-000000003021' and is_current), '1', 'one current daily summary is written');

select is(
  public.persist_worker_execution(
    '00000000-0000-0000-0000-000000003032',
    1,
    '00000000-0000-0000-0000-000000003011',
    '{
      "contract_version":"v0",
      "task_id":"00000000-0000-0000-0000-000000003032",
      "attempt":1,
      "source_id":"discord-v1-bound",
      "raw_messages":[{"external_message_id":"v1-message-1","occurred_at":"2099-01-01T00:00:00Z","local_raw_ref":"local://v1/raw/v1-message-1.json","payload_hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","retention_expires_at":"2100-01-01T00:00:00Z"}],
      "canonical_messages":[{"external_message_id":"v1-message-1","occurred_at":"2099-01-01T00:00:00Z","author_display":"fixture-author","content":"fixture content","has_unparsed_media":false,"metadata":{"author_id":"author-source"}}],
      "structured_runs":[{"chunk_key":"chunk-v1-1","provider":"mock","parameter_version":"v1-test-1","input_message_ids":["v1-message-1"],"media_source_message_ids":[],"output":{"topics":[]}}],
      "batch_summaries":[{"natural_date":"2099-01-01","input_message_ids":["v1-message-1"],"structured_run_keys":["chunk-v1-1"],"output":{"topics":[],"warnings":[]},"coverage":{"unparsed_media":false}}]
    }'::jsonb
  ) ->> 'idempotent',
  'true',
  'repeating the same summary persistence is idempotent'
);

select is((select count(*)::text from public.daily_summaries where source_id = '00000000-0000-0000-0000-000000003021'), '1', 'idempotent persistence does not add a daily version');

select throws_ok(
  $$select public.persist_worker_execution(
    '00000000-0000-0000-0000-000000003033', 1, '00000000-0000-0000-0000-000000003011',
    '{"contract_version":"v0","task_id":"00000000-0000-0000-0000-000000003033","attempt":1,"source_id":"discord-v1-bound","raw_messages":[{"external_message_id":"unknown-run-message","occurred_at":"2099-01-01T00:00:00Z","local_raw_ref":"local://v1/raw/unknown-run-message.json","payload_hash":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","retention_expires_at":"2100-01-01T00:00:00Z"}],"canonical_messages":[{"external_message_id":"unknown-run-message","occurred_at":"2099-01-01T00:00:00Z","author_display":"fixture-author","content":"fixture content","has_unparsed_media":false,"metadata":{}}],"structured_runs":[{"chunk_key":"known-run","provider":"mock","parameter_version":"v1-test-1","input_message_ids":["unknown-run-message"],"media_source_message_ids":[],"output":{"topics":[]}}],"batch_summaries":[{"natural_date":"2099-01-01","input_message_ids":["unknown-run-message"],"structured_run_keys":["missing-run"],"output":{"topics":[]},"coverage":{"unparsed_media":false}}]}'::jsonb
  );$$,
  '22023',
  null,
  'batch summary cannot reference an unknown structured run'
);

select throws_ok(
  $$select public.persist_worker_execution(
    '00000000-0000-0000-0000-000000003034', 1, '00000000-0000-0000-0000-000000003011',
    '{"contract_version":"v0","task_id":"00000000-0000-0000-0000-000000003034","attempt":1,"source_id":"discord-v1-bound","raw_messages":[{"external_message_id":"cross-source-local","occurred_at":"2099-01-01T00:00:00Z","local_raw_ref":"local://v1/raw/cross-source-local.json","payload_hash":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","retention_expires_at":"2100-01-01T00:00:00Z"}],"canonical_messages":[{"external_message_id":"cross-source-local","occurred_at":"2099-01-01T00:00:00Z","author_display":"fixture-author","content":"fixture content","has_unparsed_media":false,"metadata":{}}],"structured_runs":[{"chunk_key":"local-run","provider":"mock","parameter_version":"v1-test-1","input_message_ids":["cross-source-local"],"media_source_message_ids":[],"output":{"topics":[]}}],"batch_summaries":[{"natural_date":"2099-01-01","input_message_ids":["foreign-message"],"structured_run_keys":["local-run"],"output":{"topics":[]},"coverage":{"unparsed_media":false}}]}'::jsonb
  );$$,
  '22023',
  null,
  'batch summary cannot reference a canonical message from another source'
);

select throws_ok(
  $$select public.persist_worker_execution(
    '00000000-0000-0000-0000-000000003035', 1, '00000000-0000-0000-0000-000000003011',
    '{"contract_version":"v0","task_id":"00000000-0000-0000-0000-000000003035","attempt":1,"source_id":"discord-v1-bound","raw_messages":[{"external_message_id":"wrong-date-message","occurred_at":"2099-01-01T00:00:00Z","local_raw_ref":"local://v1/raw/wrong-date-message.json","payload_hash":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","retention_expires_at":"2100-01-01T00:00:00Z"}],"canonical_messages":[{"external_message_id":"wrong-date-message","occurred_at":"2099-01-01T00:00:00Z","author_display":"fixture-author","content":"fixture content","has_unparsed_media":false,"metadata":{}}],"structured_runs":[{"chunk_key":"dated-run","provider":"mock","parameter_version":"v1-test-1","input_message_ids":["wrong-date-message"],"media_source_message_ids":[],"output":{"topics":[]}}],"batch_summaries":[{"natural_date":"2099-01-02","input_message_ids":["wrong-date-message"],"structured_run_keys":["dated-run"],"output":{"topics":[]},"coverage":{"unparsed_media":false}}]}'::jsonb
  );$$,
  '22023',
  null,
  'batch summary natural date must match its canonical message evidence'
);

select is(
  (
    (select count(*) from public.raw_messages where external_message_id in ('unknown-run-message', 'cross-source-local', 'wrong-date-message'))
    + (select count(*) from public.canonical_messages where external_message_id in ('unknown-run-message', 'cross-source-local', 'wrong-date-message'))
    + (select count(*) from public.structured_runs where task_id in ('00000000-0000-0000-0000-000000003033', '00000000-0000-0000-0000-000000003034', '00000000-0000-0000-0000-000000003035'))
    + (select count(*) from public.worker_execution_receipts where task_id in ('00000000-0000-0000-0000-000000003033', '00000000-0000-0000-0000-000000003034', '00000000-0000-0000-0000-000000003035'))
    + (select count(*) from public.summary_batches where task_id in ('00000000-0000-0000-0000-000000003033', '00000000-0000-0000-0000-000000003034', '00000000-0000-0000-0000-000000003035'))
  )::text,
  '0',
  'a rejected batch summary rolls back all execution writes'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000003002', true);
select is((select count(*)::text from public.source_author_rules), '0', 'ordinary users cannot read source rules');
select is((select count(*)::text from public.sync_tasks), '0', 'ordinary users cannot read task diagnostics');
select is((select count(*)::text from public.workers), '0', 'ordinary users cannot read worker diagnostics');
select is((select count(*)::text from public.raw_messages), '0', 'ordinary users cannot read raw local references');
select is((select count(*)::text from public.summary_batches), '1', 'ordinary users can read generated batch summaries');
select is((select count(*)::text from public.daily_summaries), '1', 'ordinary users can read generated daily summaries');
reset role;

select * from finish();
rollback;
