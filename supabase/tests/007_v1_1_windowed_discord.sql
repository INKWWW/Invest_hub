begin;

select plan(32);

select has_table('public', 'source_collection_coverage', 'V1.1 stores a per-source collection coverage waterline');
select has_table('public', 'sync_task_capture_progress', 'V1.1 stores resumable progress per window task');
select has_table('public', 'sync_task_capture_segments', 'V1.1 persists idempotent verified page segments');
select has_table('public', 'source_author_profiles', 'V1.1 stores stable channel-scoped author profiles');
select has_column('public', 'sync_tasks', 'capture_range', 'V1.1 tasks retain an immutable capture range');
select has_column('public', 'sync_tasks', 'author_profile_snapshot', 'V1.1 tasks retain an immutable author-profile snapshot');
select has_function('public', 'initialize_discord_collection_coverage', array['uuid', 'uuid', 'timestamp with time zone'], 'coverage initialization function exists');
select has_function('public', 'create_windowed_discord_sync_task', array['uuid', 'text', 'uuid', 'text', 'timestamp with time zone', 'text'], 'window task creation function exists');
select has_function('public', 'record_windowed_capture_segment', array['uuid', 'integer', 'uuid', 'jsonb'], 'capture segment receipt function exists');
select has_function('public', 'complete_windowed_capture_range', array['uuid', 'integer', 'uuid', 'jsonb'], 'range completion function exists');

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at)
values
  ('00000000-0000-0000-0000-000000007001', 'authenticated', 'authenticated', 'v11-admin@example.invalid', 'not-a-secret', now()),
  ('00000000-0000-0000-0000-000000007002', 'authenticated', 'authenticated', 'v11-user@example.invalid', 'not-a-secret', now());

insert into public.profiles (id, role, display_name)
values
  ('00000000-0000-0000-0000-000000007001', 'admin', 'V1.1 Admin'),
  ('00000000-0000-0000-0000-000000007002', 'user', 'V1.1 Reader');

insert into public.workers (id, name, device_secret_hash, status)
values ('00000000-0000-0000-0000-000000007011', 'v11-worker', 'v11-worker-hash', 'online');

insert into public.sources (id, source_key, source_type, display_name, parameter_version, authorized_worker_id)
values ('00000000-0000-0000-0000-000000007021', 'discord-v11-windowed', 'discord', 'V1.1 Windowed source', 'v1.1-test', '00000000-0000-0000-0000-000000007011');

select throws_ok(
  $$select public.initialize_discord_collection_coverage(
    '00000000-0000-0000-0000-000000007021',
    '00000000-0000-0000-0000-000000007002',
    '2099-01-01T00:00:00Z'
  );$$,
  '42501',
  null,
  'ordinary users cannot initialize a collection boundary'
);

insert into public.checkpoints (source_id, safe_checkpoint, version)
values ('00000000-0000-0000-0000-000000007021', 'legacy-v1-cursor', 7);

select throws_ok(
  $$select public.create_windowed_discord_sync_task(
    '00000000-0000-0000-0000-000000007021',
    'v1.1-test',
    '00000000-0000-0000-0000-000000007001',
    'manual',
    '2099-01-01T08:00:00Z',
    null
  );$$,
  '22023',
  null,
  'a legacy safe checkpoint cannot be inferred as complete window coverage'
);

create temporary table initialized_coverage as
select public.initialize_discord_collection_coverage(
  '00000000-0000-0000-0000-000000007021',
  '00000000-0000-0000-0000-000000007001',
  '2099-01-01T00:00:00Z'
) as payload;

select is(
  (select payload ->> 'coverage_start_at' from initialized_coverage),
  '2099-01-01T00:00:00+00:00',
  'the explicit Shanghai boundary is retained as the initial coverage start'
);
select is(
  (select payload ->> 'coverage_through_at' from initialized_coverage),
  '2099-01-01T00:00:00+00:00',
  'the initial waterline starts at the explicitly selected boundary'
);
select throws_ok(
  $$select public.initialize_discord_collection_coverage(
    '00000000-0000-0000-0000-000000007021',
    '00000000-0000-0000-0000-000000007001',
    '2099-01-01T01:00:00Z'
  );$$,
  '22023',
  null,
  'initialization rejects a non-schedule boundary'
);

insert into public.source_author_profiles (source_id, author_id, author_display, author_handle, enabled, created_by)
values (
  '00000000-0000-0000-0000-000000007021',
  'discord-stable-author-1',
  'Observed author',
  'observed-author',
  true,
  '00000000-0000-0000-0000-000000007001'
);

select throws_ok(
  $$insert into public.source_author_profiles (source_id, author_id, author_display, enabled)
    values (
      '00000000-0000-0000-0000-000000007021',
      'discord-stable-author-1',
      'Changed display name',
      true
    );$$,
  '23505',
  null,
  'one channel has only one stable author profile per Discord account'
);

create temporary table first_window_task as
select public.create_windowed_discord_sync_task(
  '00000000-0000-0000-0000-000000007021',
  'v1.1-test',
  '00000000-0000-0000-0000-000000007001',
  'manual',
  '2099-01-01T08:00:00Z',
  null
) as payload;

select is(
  (select payload -> 'collection_scope' from first_window_task),
  '{"mode":"window"}'::jsonb,
  'new V1.1 tasks use the window collection mode without a page cap'
);
select is(
  (select payload -> 'capture_range' ->> 'start_at' from first_window_task),
  '2099-01-01T00:00:00+00:00',
  'a window task starts at the last completed coverage waterline'
);
select is(
  (select payload -> 'capture_range' ->> 'end_at' from first_window_task),
  '2099-01-01T08:00:00+00:00',
  'a window task stores its immutable trusted end instant'
);
select is(
  (select jsonb_array_length(payload -> 'author_profile_snapshot')::text from first_window_task),
  '1',
  'a task freezes the configured author profile snapshot'
);

select throws_ok(
  $$insert into public.sync_tasks (
      task_type, source_id, parameter_version, collection_scope, capture_range
    ) values (
      'discord_sync',
      '00000000-0000-0000-0000-000000007021',
      'v1.1-test',
      '{"mode":"window","max_pages":5}'::jsonb,
      '{"mode":"window","trigger":"manual","timezone":"Asia/Shanghai","start_at":"2099-01-01T00:00:00Z","end_at":"2099-01-01T08:00:00Z","scheduled_window_key":null}'::jsonb
    );$$,
  '23514',
  null,
  'V1.1 window tasks reject max_pages as a success boundary'
);

create temporary table claimed_window_task as
select public.claim_next_task(
  '00000000-0000-0000-0000-000000007011',
  '2099-01-01T00:01:00Z'
) as payload;

select is(
  (select payload -> 'capture_range' ->> 'end_at' from claimed_window_task),
  '2099-01-01T08:00:00+00:00',
  'the worker claim includes the immutable capture range'
);
select ok(
  (select payload -> 'coverage_snapshot' ? 'last_completed_task_id' from claimed_window_task),
  'a first window claim preserves the nullable last-completed task field required by its contract'
);

insert into public.worker_execution_receipts (
  task_id, attempt, worker_id, payload_digest, raw_count, canonical_count, structured_run_ids, summary_batch_ids, daily_summary_ids
) values (
  (select (payload ->> 'id')::uuid from first_window_task),
  (select (payload ->> 'attempt')::integer from claimed_window_task),
  '00000000-0000-0000-0000-000000007011',
  'v11-empty-window-receipt',
  0,
  0,
  '[]'::jsonb,
  '[]'::jsonb,
  '[]'::jsonb
);

create temporary table first_segment as
select public.record_windowed_capture_segment(
  (select (payload ->> 'id')::uuid from first_window_task),
  (select (payload ->> 'attempt')::integer from claimed_window_task),
  '00000000-0000-0000-0000-000000007011',
  '{"idempotency_key":"page-001","request_cursor":null,"next_cursor":"cursor-001","oldest_occurred_at":"2099-01-01T00:00:00Z","newest_occurred_at":"2099-01-01T08:00:00Z","response_matched":true,"response_fresh":true}'::jsonb
) as payload;

select is((select payload ->> 'idempotent' from first_segment), 'false', 'the first verified page segment is recorded');
select is(
  public.record_windowed_capture_segment(
    (select (payload ->> 'id')::uuid from first_window_task),
    (select (payload ->> 'attempt')::integer from claimed_window_task),
    '00000000-0000-0000-0000-000000007011',
    '{"idempotency_key":"page-001","request_cursor":null,"next_cursor":"cursor-001","oldest_occurred_at":"2099-01-01T00:00:00Z","newest_occurred_at":"2099-01-01T08:00:00Z","response_matched":true,"response_fresh":true}'::jsonb
  ) ->> 'idempotent',
  'true',
  'a repeated page receipt is idempotent'
);
select throws_ok(
  $$select public.record_windowed_capture_segment(
    (select (payload ->> 'id')::uuid from first_window_task),
    1,
    '00000000-0000-0000-0000-000000007011',
    '{"idempotency_key":"page-002","request_cursor":"wrong-cursor","next_cursor":"cursor-002","oldest_occurred_at":"2098-12-31T23:59:00Z","newest_occurred_at":"2099-01-01T00:00:00Z","response_matched":true,"response_fresh":true}'::jsonb
  );$$,
  '40001',
  null,
  'a page receipt cannot move a task from an unexpected resume cursor'
);

select throws_ok(
  $$select public.complete_windowed_capture_range(
    (select (payload ->> 'id')::uuid from first_window_task),
    1,
    '00000000-0000-0000-0000-000000007011',
    '{"range_complete":true,"capture_range":{"mode":"window","trigger":"manual","timezone":"Asia/Shanghai","start_at":"2099-01-01T00:00:00Z","end_at":"2099-01-01T08:00:00Z","scheduled_window_key":null},"summary_batch_ids":[],"daily_summary_ids":[],"no_new_data":true}'::jsonb
  );$$,
  '22023',
  null,
  'a task cannot complete without verified range-boundary evidence'
);
select is(
  (select coverage_through_at::text from public.source_collection_coverage where source_id = '00000000-0000-0000-0000-000000007021'),
  '2099-01-01 00:00:00+00',
  'a failed range completion cannot advance the coverage waterline'
);

select is(
  public.complete_windowed_capture_range(
    (select (payload ->> 'id')::uuid from first_window_task),
    1,
    '00000000-0000-0000-0000-000000007011',
    '{"range_complete":true,"capture_range":{"mode":"window","trigger":"manual","timezone":"Asia/Shanghai","start_at":"2099-01-01T00:00:00Z","end_at":"2099-01-01T08:00:00Z","scheduled_window_key":null},"boundary":{"kind":"oldest_at_or_before_start","observed_at":"2099-01-01T00:00:00Z"},"summary_batch_ids":[],"daily_summary_ids":[],"no_new_data":true}'::jsonb
  ) ->> 'status',
  'succeeded',
  'only a verified boundary and matching persistence receipt complete the range'
);
select is(
  (select coverage_through_at::text from public.source_collection_coverage where source_id = '00000000-0000-0000-0000-000000007021'),
  '2099-01-01 08:00:00+00',
  'a successful range completion atomically advances coverage to its end instant'
);

create temporary table second_window_task as
select public.create_windowed_discord_sync_task(
  '00000000-0000-0000-0000-000000007021',
  'v1.1-test',
  '00000000-0000-0000-0000-000000007001',
  'manual',
  '2099-01-01T16:00:00Z',
  null
) as payload;

select is(
  (select payload -> 'capture_range' ->> 'start_at' from second_window_task),
  '2099-01-01T08:00:00+00:00',
  'the following task starts from the completed coverage waterline'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000007002', true);
select is(
  (select count(*)::text from public.source_author_profiles),
  '0',
  'ordinary users cannot read channel author-profile configuration'
);
reset role;

select * from finish();
rollback;
