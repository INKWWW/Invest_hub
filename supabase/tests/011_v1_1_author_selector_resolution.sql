begin;

select plan(12);

select has_column('public', 'source_author_profiles', 'requested_author', 'V1.1 stores an administrator-entered author selector');
select has_column('public', 'source_author_profiles', 'resolution_status', 'V1.1 records whether a selector has a stable identity');
select has_function(
  'public',
  'resolve_windowed_author_profiles',
  array['uuid', 'integer', 'uuid'],
  'a leased Worker can resolve a window task author selector after persistence'
);

insert into public.workers (id, name, device_secret_hash, status)
values ('00000000-0000-0000-0000-000000011001', 'v11-selector-worker', 'v11-selector-worker-hash', 'online');

insert into public.sources (id, source_key, source_type, display_name, parameter_version, authorized_worker_id)
values (
  '00000000-0000-0000-0000-000000011011',
  'discord-v11-selector',
  'discord',
  'V1.1 selector source',
  'v1.1-test',
  '00000000-0000-0000-0000-000000011001'
);

insert into public.source_author_profiles (
  id, source_id, requested_author, resolution_status, author_id, author_display, author_handle, enabled
) values (
  '00000000-0000-0000-0000-000000011021',
  '00000000-0000-0000-0000-000000011011',
  'Priority author',
  'pending',
  null,
  'Priority author',
  null,
  true
), (
  '00000000-0000-0000-0000-000000011022',
  '00000000-0000-0000-0000-000000011011',
  'Not yet observed',
  'pending',
  null,
  'Not yet observed',
  null,
  true
);

select is(
  (select resolution_status from public.source_author_profiles where id = '00000000-0000-0000-0000-000000011021'),
  'pending',
  'an administrator can save an unobserved selector as pending'
);

insert into public.sync_tasks (
  id, task_type, source_id, status, parameter_version, collection_scope, capture_range,
  author_profile_snapshot, lease_owner, lease_expires_at
) values (
  '00000000-0000-0000-0000-000000011031',
  'discord_sync',
  '00000000-0000-0000-0000-000000011011',
  'leased',
  'v1.1-test',
  '{"mode":"window"}'::jsonb,
  '{"mode":"window","trigger":"manual","timezone":"Asia/Shanghai","start_at":"2099-01-01T00:00:00Z","end_at":"2099-01-01T08:00:00Z","scheduled_window_key":null}'::jsonb,
  '[
    {"profile_id":"00000000-0000-0000-0000-000000011021","requested_author":"Priority author","resolution_status":"pending","author_id":null,"author_display":"Priority author","author_handle":null,"enabled":true},
    {"profile_id":"00000000-0000-0000-0000-000000011022","requested_author":"Not yet observed","resolution_status":"pending","author_id":null,"author_display":"Not yet observed","author_handle":null,"enabled":true}
  ]'::jsonb,
  '00000000-0000-0000-0000-000000011001',
  '2100-01-01T00:00:00Z'
);

insert into public.task_attempts (task_id, attempt, worker_id, status, lease_expires_at)
values (
  '00000000-0000-0000-0000-000000011031',
  1,
  '00000000-0000-0000-0000-000000011001',
  'leased',
  '2100-01-01T00:00:00Z'
);

insert into public.canonical_messages (
  source_id, external_message_id, occurred_at, author_display, content, metadata
) values (
  '00000000-0000-0000-0000-000000011011',
  'selector-message-1',
  '2099-01-01T01:00:00Z',
  'Priority author',
  'private message text must not leave the control plane',
  '{"author_id":"stable-author-priority"}'::jsonb
);

create temporary table resolved_selectors as
select public.resolve_windowed_author_profiles(
  '00000000-0000-0000-0000-000000011031',
  1,
  '00000000-0000-0000-0000-000000011001'
) as payload;

select is(
  (select jsonb_array_length(payload->'author_profiles')::text from resolved_selectors),
  '1',
  'only uniquely resolved selectors are returned to the Worker'
);
select is(
  (select payload->'author_profiles'->0->>'author_id' from resolved_selectors),
  'stable-author-priority',
  'the Worker receives the stable author identity after the captured message persists'
);
select ok(
  not (select payload::text like '%private message text%' from resolved_selectors),
  'the resolution response contains no canonical message text'
);
select is(
  (select resolution_status from public.source_author_profiles where id = '00000000-0000-0000-0000-000000011021'),
  'resolved',
  'a uniquely matched selector becomes resolved'
);
select is(
  (select resolution_status from public.source_author_profiles where id = '00000000-0000-0000-0000-000000011022'),
  'pending',
  'a selector with no candidate remains pending rather than being guessed'
);
select throws_ok(
  $$select public.resolve_windowed_author_profiles(
    '00000000-0000-0000-0000-000000011031',
    1,
    '00000000-0000-0000-0000-000000011099'
  );$$,
  '40001',
  null,
  'author resolution rejects a Worker outside the current lease'
);

insert into public.source_author_profiles (
  id, source_id, requested_author, resolution_status, author_id, author_display, author_handle, enabled
) values (
  '00000000-0000-0000-0000-000000011023',
  '00000000-0000-0000-0000-000000011011',
  'Duplicate display',
  'pending',
  null,
  'Duplicate display',
  null,
  true
);

insert into public.sync_tasks (
  id, task_type, source_id, status, parameter_version, collection_scope, capture_range,
  author_profile_snapshot, lease_owner, lease_expires_at
) values (
  '00000000-0000-0000-0000-000000011032',
  'discord_sync',
  '00000000-0000-0000-0000-000000011011',
  'leased',
  'v1.1-test',
  '{"mode":"window"}'::jsonb,
  '{"mode":"window","trigger":"manual","timezone":"Asia/Shanghai","start_at":"2099-01-01T08:00:00Z","end_at":"2099-01-01T16:00:00Z","scheduled_window_key":null}'::jsonb,
  '[{"profile_id":"00000000-0000-0000-0000-000000011023","requested_author":"Duplicate display","resolution_status":"pending","author_id":null,"author_display":"Duplicate display","author_handle":null,"enabled":true}]'::jsonb,
  '00000000-0000-0000-0000-000000011001',
  '2100-01-01T00:00:00Z'
);

insert into public.task_attempts (task_id, attempt, worker_id, status, lease_expires_at)
values (
  '00000000-0000-0000-0000-000000011032',
  1,
  '00000000-0000-0000-0000-000000011001',
  'leased',
  '2100-01-01T00:00:00Z'
);

insert into public.canonical_messages (
  source_id, external_message_id, occurred_at, author_display, content, metadata
) values (
  '00000000-0000-0000-0000-000000011011',
  'selector-message-2',
  '2099-01-01T09:00:00Z',
  'Duplicate display',
  'private candidate one',
  '{"author_id":"stable-author-one"}'::jsonb
), (
  '00000000-0000-0000-0000-000000011011',
  'selector-message-3',
  '2099-01-01T10:00:00Z',
  'Duplicate display',
  'private candidate two',
  '{"author_id":"stable-author-two"}'::jsonb
);

create temporary table ambiguous_selector as
select public.resolve_windowed_author_profiles(
  '00000000-0000-0000-0000-000000011032',
  1,
  '00000000-0000-0000-0000-000000011001'
) as payload;

select is(
  (select jsonb_array_length(payload->'author_profiles')::text from ambiguous_selector),
  '0',
  'a selector with multiple stable candidates is not returned to the Worker'
);
select is(
  (select resolution_status from public.source_author_profiles where id = '00000000-0000-0000-0000-000000011023'),
  'ambiguous',
  'a selector with multiple stable candidates is marked ambiguous rather than guessed'
);

select * from finish();
rollback;
