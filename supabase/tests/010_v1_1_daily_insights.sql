begin;

select plan(10);

select has_function(
  'public',
  'get_window_daily_fact_context',
  array['uuid', 'integer', 'uuid'],
  'a leased window task can request a read-only daily fact context'
);

insert into public.workers (id, name, device_secret_hash, status)
values ('00000000-0000-0000-0000-000000010001', 'v11-daily-worker', 'v11-daily-worker-hash', 'online');

insert into public.sources (id, source_key, source_type, display_name, parameter_version, authorized_worker_id)
values (
  '00000000-0000-0000-0000-000000010011',
  'discord-v11-daily',
  'discord',
  'V1.1 daily source',
  'v1.1-test',
  '00000000-0000-0000-0000-000000010001'
);

insert into public.sync_tasks (
  id, task_type, source_id, status, parameter_version, collection_scope, capture_range
) values (
  '00000000-0000-0000-0000-000000010021',
  'discord_sync',
  '00000000-0000-0000-0000-000000010011',
  'succeeded',
  'v1.1-test',
  '{"mode":"window"}'::jsonb,
  '{"mode":"window","trigger":"manual","timezone":"Asia/Shanghai","start_at":"2098-12-31T16:00:00Z","end_at":"2099-01-01T00:00:00Z","scheduled_window_key":null}'::jsonb
), (
  '00000000-0000-0000-0000-000000010022',
  'discord_sync',
  '00000000-0000-0000-0000-000000010011',
  'leased',
  'v1.1-test',
  '{"mode":"window"}'::jsonb,
  '{"mode":"window","trigger":"manual","timezone":"Asia/Shanghai","start_at":"2099-01-01T00:00:00Z","end_at":"2099-01-01T08:00:00Z","scheduled_window_key":null}'::jsonb
);

update public.sync_tasks
set lease_owner = '00000000-0000-0000-0000-000000010001',
    lease_expires_at = '2100-01-01T00:00:00Z'
where id = '00000000-0000-0000-0000-000000010022';

insert into public.task_attempts (task_id, attempt, worker_id, status, lease_expires_at)
values (
  '00000000-0000-0000-0000-000000010022',
  1,
  '00000000-0000-0000-0000-000000010001',
  'leased',
  '2100-01-01T00:00:00Z'
);

insert into public.source_collection_coverage (
  source_id, coverage_start_at, coverage_through_at, last_completed_task_id
) values (
  '00000000-0000-0000-0000-000000010011',
  '2098-12-31T16:00:00Z',
  '2099-01-01T00:00:00Z',
  '00000000-0000-0000-0000-000000010021'
);

insert into public.sync_task_capture_progress (task_id, source_id, capture_range)
values (
  '00000000-0000-0000-0000-000000010022',
  '00000000-0000-0000-0000-000000010011',
  '{"mode":"window","trigger":"manual","timezone":"Asia/Shanghai","start_at":"2099-01-01T00:00:00Z","end_at":"2099-01-01T08:00:00Z","scheduled_window_key":null}'::jsonb
);

insert into public.canonical_messages (
  source_id, external_message_id, occurred_at, author_display, content, metadata
) values (
  '00000000-0000-0000-0000-000000010011',
  'prior-1',
  '2099-01-01T01:00:00Z',
  'Prior author',
  'this private raw text must never enter the daily context',
  '{"author_id":"author-prior"}'::jsonb
);

insert into public.summary_batches (
  task_id, source_id, natural_date, input_message_ids, structured_run_ids, output, coverage
) values (
  '00000000-0000-0000-0000-000000010021',
  '00000000-0000-0000-0000-000000010011',
  '2099-01-01',
  '["prior-1"]'::jsonb,
  '["prior-run"]'::jsonb,
  '{"schema_version":"v1.1-batch","facts":[{"author_id":"author-prior","topic":"市场","viewpoint":"早盘判断","reasoning":null,"operation_tendency":null,"methodology":[],"uncertainty":[],"source_message_ids":["prior-1"]}],"warnings":[],"daily_summary":{"schema_version":"v1.1","natural_date":"2099-01-01","as_of":"2099-01-01T00:00:00Z","author_cards":[],"topic_discussions":[],"warnings":[]}}'::jsonb,
  '{"unparsed_media":false,"unparsed_media_message_ids":[]}'::jsonb
);

insert into public.daily_summaries (
  source_id, natural_date, version, is_current, batch_ids, output, coverage
) values (
  '00000000-0000-0000-0000-000000010011',
  '2099-01-01',
  1,
  true,
  '["00000000-0000-0000-0000-000000010031"]'::jsonb,
  '{"legacy":"prior-current"}'::jsonb,
  '{"as_of":"2099-01-01T00:00:00Z","unparsed_media":false}'::jsonb
);

create temporary table daily_context as
select public.get_window_daily_fact_context(
  '00000000-0000-0000-0000-000000010022',
  1,
  '00000000-0000-0000-0000-000000010001'
) as payload;

select is(
  (select payload->'message_catalog'->0->>'external_message_id' from daily_context),
  'prior-1',
  'daily context returns canonical message identity only'
);
select ok(
  not (select payload->'message_catalog'->0 ? 'content' from daily_context),
  'daily context does not return canonical raw text'
);
select is(
  (select payload->'prior_batches'->0->'facts'->0->>'viewpoint' from daily_context),
  '早盘判断',
  'daily context returns only prior structured fact units'
);
select throws_ok(
  $$select public.get_window_daily_fact_context(
    '00000000-0000-0000-0000-000000010022',
    1,
    '00000000-0000-0000-0000-000000010099'
  );$$,
  '40001',
  null,
  'daily context rejects a worker outside the task lease'
);

create temporary table persisted_daily as
select public.persist_worker_execution(
  '00000000-0000-0000-0000-000000010022',
  1,
  '00000000-0000-0000-0000-000000010001',
  '{"contract_version":"v0","task_id":"00000000-0000-0000-0000-000000010022","attempt":1,"source_id":"discord-v11-daily","raw_messages":[{"external_message_id":"current-1","occurred_at":"2099-01-01T02:00:00Z","local_raw_ref":"local://daily/current-1","payload_hash":"1111111111111111111111111111111111111111111111111111111111111111","retention_expires_at":"2100-01-01T00:00:00Z"}],"canonical_messages":[{"external_message_id":"current-1","occurred_at":"2099-01-01T02:00:00Z","author_display":"Current author","content":"private current text","has_unparsed_media":false,"metadata":{"author_id":"author-current"}}],"structured_runs":[{"chunk_key":"v11-day-1","provider":"mock","parameter_version":"v1.1-test","input_message_ids":["current-1"],"media_source_message_ids":[],"output":{"schema_version":"v1.1-chunk","facts":[],"media_source_message_ids":[],"warnings":[]}}],"batch_summaries":[{"natural_date":"2099-01-01","input_message_ids":["current-1"],"structured_run_keys":["v11-day-1"],"output":{"schema_version":"v1.1-batch","facts":[],"warnings":[],"daily_summary":{"schema_version":"v1.1","natural_date":"2099-01-01","as_of":"2099-01-01T08:00:00Z","author_cards":[],"topic_discussions":[],"warnings":[]}},"coverage":{"unparsed_media":false,"unparsed_media_message_ids":[]}}]}'::jsonb
) as payload;

select is(
  (select jsonb_array_length(payload->'daily_summary_ids')::text from persisted_daily),
  '1',
  'V1.1 persistence returns the direct daily insight receipt'
);
select is(
  (select output->>'legacy' from public.daily_summaries
   where source_id = '00000000-0000-0000-0000-000000010011' and is_current),
  'prior-current',
  'the prior current daily summary remains visible before range completion'
);
select is(
  (select is_current::text from public.daily_summaries
   where id::text = (select payload->'daily_summary_ids'->>0 from persisted_daily)),
  'false',
  'the new V1.1 daily insight remains hidden before range completion'
);

select is(
  public.complete_windowed_capture_range(
    '00000000-0000-0000-0000-000000010022',
    1,
    '00000000-0000-0000-0000-000000010001',
    jsonb_build_object(
      'range_complete', true,
      'capture_range', '{"mode":"window","trigger":"manual","timezone":"Asia/Shanghai","start_at":"2099-01-01T00:00:00Z","end_at":"2099-01-01T08:00:00Z","scheduled_window_key":null}'::jsonb,
      'boundary', jsonb_build_object('kind', 'oldest_at_or_before_start', 'observed_at', '2099-01-01T00:00:00Z'),
      'summary_batch_ids', (select payload->'summary_batch_ids' from persisted_daily),
      'daily_summary_ids', (select payload->'daily_summary_ids' from persisted_daily),
      'no_new_data', false
    )
  )->>'status',
  'succeeded',
  'range completion accepts the exact V1.1 persistence receipt'
);
select is(
  (select output->>'schema_version' from public.daily_summaries
   where source_id = '00000000-0000-0000-0000-000000010011' and is_current),
  'v1.1',
  'range completion promotes only the completed V1.1 daily insight'
);

select * from finish();
rollback;
