begin;

select plan(11);

select has_function(
  'public',
  'enqueue_due_discord_tasks',
  array['uuid', 'timestamp with time zone'],
  'the control plane can enqueue every due V1.1 window from trusted time'
);

insert into public.workers (id, name, device_secret_hash, status)
values ('00000000-0000-0000-0000-000000009001', 'v11-schedule-worker', 'v11-schedule-worker-hash', 'online');

insert into public.sources (id, source_key, source_type, display_name, parameter_version, authorized_worker_id)
values (
  '00000000-0000-0000-0000-000000009011',
  'discord-v11-schedule',
  'discord',
  'V1.1 schedule source',
  'v1.1-schedule-test',
  '00000000-0000-0000-0000-000000009001'
);

insert into public.source_collection_coverage (source_id, coverage_start_at, coverage_through_at)
values (
  '00000000-0000-0000-0000-000000009011',
  '2098-12-31T16:00:00Z',
  '2098-12-31T16:00:00Z'
);

create temporary table first_due_tick as
select public.enqueue_due_discord_tasks(
  '00000000-0000-0000-0000-000000009001',
  '2099-01-05T16:00:00Z'
) as payload;

select is(
  (select jsonb_array_length(payload -> 'tasks')::text from first_due_tick),
  '20',
  'twenty overdue Shanghai windows are all enqueued without a count cap'
);
select is(
  (select payload -> 'tasks' -> 0 ->> 'idempotent' from first_due_tick),
  'false',
  'the first due tick creates the first source window'
);
select is(
  (select capture_range ->> 'start_at' from public.sync_tasks where id = (select (payload -> 'tasks' -> 0 ->> 'id')::uuid from first_due_tick)),
  '2098-12-31T16:00:00+00:00',
  'the first window starts from the current source coverage waterline'
);
select is(
  (select capture_range ->> 'end_at' from public.sync_tasks where id = (select (payload -> 'tasks' -> 19 ->> 'id')::uuid from first_due_tick)),
  '2099-01-05T16:00:00+00:00',
  'the last due task ends at the trusted control-plane time boundary'
);

create temporary table duplicate_due_tick as
select public.enqueue_due_discord_tasks(
  '00000000-0000-0000-0000-000000009001',
  '2099-01-05T16:00:00Z'
) as payload;

select is(
  (select payload -> 'tasks' -> 0 ->> 'idempotent' from duplicate_due_tick),
  'true',
  'repeating a control-plane tick returns existing windows idempotently'
);
select is(
  (select count(*)::text from public.scheduled_sync_windows where source_id = '00000000-0000-0000-0000-000000009011'),
  '20',
  'a duplicate tick does not create additional scheduled tasks'
);

create temporary table first_claim as
select public.claim_next_task(
  '00000000-0000-0000-0000-000000009001',
  '2099-01-05T16:01:00Z'
) as payload;

select is(
  (select payload -> 'capture_range' ->> 'end_at' from first_claim),
  '2099-01-01T00:00:00+00:00',
  'only the earliest missing range is claimable while later windows await its coverage'
);

update public.sync_tasks
set status = 'retryable_failed', lease_owner = null, lease_expires_at = null
where id = (select (payload ->> 'task_id')::uuid from first_claim);

insert into public.sources (id, source_key, source_type, display_name, parameter_version, authorized_worker_id)
values (
  '00000000-0000-0000-0000-000000009012',
  'discord-v11-manual-follow-up',
  'discord',
  'V1.1 manual follow-up source',
  'v1.1-schedule-test',
  '00000000-0000-0000-0000-000000009001'
);

-- This is the persisted source waterline after a completed 10:30 manual
-- refresh.  Task 1 covers that only a verified completion can set it.
insert into public.source_collection_coverage (source_id, coverage_start_at, coverage_through_at)
values (
  '00000000-0000-0000-0000-000000009012',
  '2099-01-05T02:30:00Z',
  '2099-01-05T02:30:00Z'
);

create temporary table manual_follow_up_tick as
select public.enqueue_due_discord_tasks(
  '00000000-0000-0000-0000-000000009001',
  '2099-01-05T08:00:00Z'
) as payload;

select is(
  (select count(*)::text from public.sync_tasks where source_id = '00000000-0000-0000-0000-000000009012'),
  '1',
  'a retryable failure on one source does not block another source from scheduling'
);
select is(
  (select capture_range ->> 'start_at' from public.sync_tasks where source_id = '00000000-0000-0000-0000-000000009012'),
  '2099-01-05T02:30:00+00:00',
  'the 16:00 scheduled range starts at the completed 10:30 manual waterline'
);
select is(
  (select capture_range ->> 'end_at' from public.sync_tasks where source_id = '00000000-0000-0000-0000-000000009012'),
  '2099-01-05T08:00:00+00:00',
  'the 16:00 scheduled range uses its Shanghai boundary as the fixed end time'
);

select * from finish();
rollback;
