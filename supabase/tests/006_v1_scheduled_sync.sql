begin;

select plan(11);

select has_table('public', 'scheduled_sync_windows', 'scheduled windows are persisted for cross-process idempotency');
select has_function('public', 'enqueue_scheduled_discord_tasks', array['uuid', 'text'], 'scheduled task enqueue function exists');

insert into public.workers (id, name, device_secret_hash, status)
values
  ('00000000-0000-0000-0000-000000006001', 'schedule-worker-a', 'schedule-worker-a-hash', 'online'),
  ('00000000-0000-0000-0000-000000006002', 'schedule-worker-b', 'schedule-worker-b-hash', 'online');

insert into public.sources (id, source_key, source_type, display_name, parameter_version, authorized_worker_id)
values
  ('00000000-0000-0000-0000-000000006011', 'schedule-source-a', 'discord', 'Schedule source A', 'v1-schedule-a', '00000000-0000-0000-0000-000000006001'),
  ('00000000-0000-0000-0000-000000006012', 'schedule-source-b', 'discord', 'Schedule source B', 'v1-schedule-b', '00000000-0000-0000-0000-000000006002'),
  ('00000000-0000-0000-0000-000000006013', 'schedule-source-disabled', 'discord', 'Disabled schedule source', 'v1-schedule-disabled', '00000000-0000-0000-0000-000000006001');

update public.sources set enabled = false where id = '00000000-0000-0000-0000-000000006013';

create temporary table first_tick as
select public.enqueue_scheduled_discord_tasks(
  '00000000-0000-0000-0000-000000006001', '2099-01-01T08:00+08:00'
) as payload;

select is((select jsonb_array_length(payload -> 'tasks')::text from first_tick), '1', 'a Worker only creates tasks for its enabled bound source');
select is(
  (select payload -> 'tasks' -> 0 ->> 'source_id' from first_tick),
  '00000000-0000-0000-0000-000000006011',
  'the created task belongs to the bound source'
);
select is(
  (select payload -> 'tasks' -> 0 ->> 'idempotent' from first_tick),
  'false',
  'the first tick reports a newly created task'
);

create temporary table duplicate_tick as
select public.enqueue_scheduled_discord_tasks(
  '00000000-0000-0000-0000-000000006001', '2099-01-01T08:00+08:00'
) as payload;

select is(
  (select payload -> 'tasks' -> 0 ->> 'id' from duplicate_tick),
  (select payload -> 'tasks' -> 0 ->> 'id' from first_tick),
  'a duplicate window returns the original task'
);
select is((select payload -> 'tasks' -> 0 ->> 'idempotent' from duplicate_tick), 'true', 'a duplicate window is marked idempotent');
select is((select count(*)::text from public.sync_tasks), '1', 'duplicate ticks do not create another sync task');
select is((select count(*)::text from public.scheduled_sync_windows), '1', 'duplicate ticks do not create another window row');

select throws_ok(
  $$select public.enqueue_scheduled_discord_tasks(
    '00000000-0000-0000-0000-000000006001', 'not-a-window'
  );$$,
  '22023', null,
  'invalid window keys are rejected before task creation'
);

select throws_ok(
  $$select public.enqueue_scheduled_discord_tasks(
    '00000000-0000-0000-0000-000000006099', '2099-01-01T08:00+08:00'
  );$$,
  '42501', null,
  'unknown Workers cannot create scheduled tasks'
);

select * from finish();
rollback;
