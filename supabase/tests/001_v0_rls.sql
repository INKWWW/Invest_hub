begin;

select plan(44);

select has_table('public', 'profiles', 'profiles table exists');
select has_table('public', 'invites', 'invites table exists');
select has_table('public', 'workers', 'workers table exists');
select has_table('public', 'sources', 'sources table exists');
select has_table('public', 'sync_tasks', 'sync_tasks table exists');
select has_table('public', 'task_attempts', 'task_attempts table exists');
select has_table('public', 'checkpoints', 'checkpoints table exists');
select has_table('public', 'canonical_messages', 'canonical_messages table exists');
select has_table('public', 'structured_runs', 'structured_runs table exists');
select has_table('public', 'task_events', 'task_events table exists');

select has_function(
  'public',
  'claim_next_task',
  array['uuid', 'timestamptz'],
  'claim_next_task function exists'
);
select has_function(
  'public',
  'accept_task_result',
  array['uuid', 'integer', 'jsonb', 'jsonb'],
  'accept_task_result function exists'
);
select has_function(
  'public',
  'consume_invite',
  array['text', 'uuid', 'timestamptz'],
  'consume_invite function exists'
);

select ok(
  exists (
    select 1 from pg_indexes
    where schemaname = 'public'
      and tablename = 'canonical_messages'
      and indexdef like 'CREATE UNIQUE%'
      and indexdef like '%source_id%'
      and indexdef like '%external_message_id%'
  ),
  'canonical message id is unique'
);
select ok(
  exists (
    select 1 from pg_indexes
    where schemaname = 'public'
      and tablename = 'task_attempts'
      and indexdef like 'CREATE UNIQUE%'
      and indexdef like '%task_id%'
      and indexdef like '%attempt%'
  ),
  'task attempt is unique'
);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at)
values
  ('00000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'v0-admin@example.invalid', 'not-a-secret', now()),
  ('00000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'v0-user@example.invalid', 'not-a-secret', now())
on conflict (id) do nothing;

insert into public.profiles (id, role, display_name)
values
  ('00000000-0000-0000-0000-000000000001', 'admin', 'V0 Admin'),
  ('00000000-0000-0000-0000-000000000002', 'user', 'V0 User')
on conflict (id) do update set role = excluded.role;

insert into public.workers (id, name, device_secret_hash)
values
  ('00000000-0000-0000-0000-000000000011', 'worker-one', 'hash-worker-one'),
  ('00000000-0000-0000-0000-000000000012', 'worker-two', 'hash-worker-two');

insert into public.sources (id, source_key, source_type, display_name, parameter_version)
values ('00000000-0000-0000-0000-000000000021', 'discord-v0-test', 'discord', 'V0 test source', 'v0-test-1');

insert into public.sync_tasks (id, task_type, source_id, parameter_version, requested_by)
values (
  '00000000-0000-0000-0000-000000000031',
  'discord_sync',
  '00000000-0000-0000-0000-000000000021',
  'v0-test-1',
  '00000000-0000-0000-0000-000000000001'
);

insert into public.invites (id, code_hash, role, created_by, expires_at)
values (
  '00000000-0000-0000-0000-000000000041',
  'hash-invite-one',
  'user',
  '00000000-0000-0000-0000-000000000001',
  '2099-01-02 00:00:00+00'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);
select is((select count(*)::text from public.profiles), '1', 'ordinary user can read only own profile');
select is((select count(*)::text from public.sync_tasks), '0', 'ordinary user cannot read tasks');
select is((select count(*)::text from public.workers), '0', 'ordinary user cannot read workers');
select is((select count(*)::text from public.sources), '0', 'ordinary user cannot read sources');
select is((select count(*)::text from public.raw_messages), '0', 'ordinary user cannot read raw messages');
select is((select count(*)::text from public.canonical_messages), '0', 'ordinary user cannot read canonical messages');
select is((select count(*)::text from public.structured_runs), '0', 'ordinary user cannot read structured runs');
select is((select count(*)::text from public.task_events), '0', 'ordinary user cannot read task events');
select throws_ok(
  $$insert into public.invites (id, code_hash, role, expires_at)
    values ('00000000-0000-0000-0000-000000000042', 'hash-invite-two', 'user', '2099-01-02 00:00:00+00');$$,
  '42501',
  null,
  'ordinary user cannot write invites'
);
select throws_ok(
  $$insert into public.workers (id, name, device_secret_hash)
    values ('00000000-0000-0000-0000-000000000013', 'worker-three', 'hash-worker-three');$$,
  '42501',
  null,
  'ordinary user cannot write workers'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
insert into public.invites (id, code_hash, role, created_by, expires_at)
values (
  '00000000-0000-0000-0000-000000000043',
  'hash-invite-admin-created',
  'user',
  '00000000-0000-0000-0000-000000000001',
  '2099-01-02 00:00:00+00'
);
select ok(
  exists (select 1 from public.invites where id = '00000000-0000-0000-0000-000000000043'),
  'admin can create an invite'
);
select is((select count(*)::text from public.sync_tasks), '1', 'admin can read task state');

reset role;
select ok(
  public.consume_invite('hash-invite-one', '00000000-0000-0000-0000-000000000002', '2099-01-01 00:00:00+00') is not null,
  'invite can be consumed once'
);
select ok(
  public.consume_invite('hash-invite-one', '00000000-0000-0000-0000-000000000002', '2099-01-01 00:00:01+00') is null,
  'consumed invite cannot be consumed again'
);

insert into public.canonical_messages (
  id, source_id, external_message_id, occurred_at, author_display, content
)
values (
  '00000000-0000-0000-0000-000000000051',
  '00000000-0000-0000-0000-000000000021',
  'external-1',
  '2099-01-01 00:00:00+00',
  'fixture-author',
  'fixture-content'
);
select throws_ok(
  $$insert into public.canonical_messages (source_id, external_message_id, content)
    values ('00000000-0000-0000-0000-000000000021', 'external-1', 'duplicate-content');$$,
  '23505',
  null,
  'duplicate canonical message is rejected'
);

select is(
  public.claim_next_task('00000000-0000-0000-0000-000000000011', '2099-01-01 00:00:00+00') ->> 'attempt',
  '1',
  'first worker claims queued task'
);
select ok(
  public.claim_next_task('00000000-0000-0000-0000-000000000012', '2099-01-01 00:00:01+00') is null,
  'second worker cannot claim an active lease'
);
select is(
  public.claim_next_task('00000000-0000-0000-0000-000000000012', '2099-01-01 00:11:00+00') ->> 'attempt',
  '2',
  'second worker can take over an expired lease'
);
select is(
  (select status from public.sync_tasks where id = '00000000-0000-0000-0000-000000000031'),
  'leased',
  'takeover leaves task leased to the new worker'
);

select throws_ok(
  $$select public.accept_task_result(
    '00000000-0000-0000-0000-000000000031',
    2,
    '{"status":"succeeded","safe_checkpoint":"message-2"}'::jsonb,
    '{"worker_id":"00000000-0000-0000-0000-000000000012","persisted":false}'::jsonb
  );$$,
  '55000',
  null,
  'result cannot advance checkpoint before persistence confirmation'
);
select is(
  public.accept_task_result(
    '00000000-0000-0000-0000-000000000031',
    2,
    '{"status":"succeeded","safe_checkpoint":"message-2"}'::jsonb,
    '{"worker_id":"00000000-0000-0000-0000-000000000012","persisted":true}'::jsonb
  ) ->> 'status',
  'succeeded',
  'matching worker can accept a persisted result'
);
select is(
  (select status from public.sync_tasks where id = '00000000-0000-0000-0000-000000000031'),
  'succeeded',
  'accepted result closes the task'
);
select is(
  (select safe_checkpoint from public.checkpoints where source_id = '00000000-0000-0000-0000-000000000021'),
  'message-2',
  'accepted result advances checkpoint after persistence'
);
select is(
  public.accept_task_result(
    '00000000-0000-0000-0000-000000000031',
    2,
    '{"status":"succeeded","safe_checkpoint":"message-2"}'::jsonb,
    '{"worker_id":"00000000-0000-0000-0000-000000000012","persisted":true}'::jsonb
  ) ->> 'idempotent',
  'true',
  'repeating the same result is idempotent'
);
select throws_ok(
  $$select public.accept_task_result(
    '00000000-0000-0000-0000-000000000031',
    2,
    '{"status":"succeeded","safe_checkpoint":"message-conflict"}'::jsonb,
    '{"worker_id":"00000000-0000-0000-0000-000000000012","persisted":true}'::jsonb
  );$$,
  '23505',
  null,
  'conflicting duplicate result is rejected'
);
select throws_ok(
  $$select public.accept_task_result(
    '00000000-0000-0000-0000-000000000031',
    1,
    '{"status":"succeeded","safe_checkpoint":"stale"}'::jsonb,
    '{"worker_id":"00000000-0000-0000-0000-000000000011","persisted":true}'::jsonb
  );$$,
  '40001',
  null,
  'stale lease owner cannot submit a result'
);

insert into public.sync_tasks (
  id, task_type, source_id, parameter_version, requested_by
)
values (
  '00000000-0000-0000-0000-000000000032',
  'discord_sync',
  '00000000-0000-0000-0000-000000000021',
  'v0-test-1',
  '00000000-0000-0000-0000-000000000001'
);
select is(
  public.claim_next_task('00000000-0000-0000-0000-000000000011', '2099-01-01 00:30:00+00') ->> 'attempt',
  '1',
  'worker can claim a new task after a completed task'
);
select is(
  public.record_task_failure(
    '00000000-0000-0000-0000-000000000032',
    1,
    '{"status":"retryable_failed","failure_class":"timeout","safe_checkpoint":"should-not-advance","retryable":true}'::jsonb,
    '{"worker_id":"00000000-0000-0000-0000-000000000011"}'::jsonb
  ) ->> 'status',
  'retryable_failed',
  'retryable failure is recorded'
);
select is(
  (select safe_checkpoint from public.checkpoints where source_id = '00000000-0000-0000-0000-000000000021'),
  'message-2',
  'failure does not advance checkpoint'
);

select * from finish();
rollback;
