begin;

select plan(5);

insert into public.workers (id, name, device_secret_hash, status)
values
  ('00000000-0000-0000-0000-000000020001', 'bound-x-worker', 'bound-x-worker-hash', 'online'),
  ('00000000-0000-0000-0000-000000020002', 'other-worker', 'other-worker-hash', 'online');

insert into public.sources (id, source_key, source_type, display_name, parameter_version, authorized_worker_id)
values
  ('00000000-0000-0000-0000-000000020011', 'x-unbound-source', 'x', 'Unbound X source', 'v2-claim', null),
  ('00000000-0000-0000-0000-000000020012', 'x-bound-source', 'x', 'Bound X source', 'v2-claim', '00000000-0000-0000-0000-000000020001'),
  ('00000000-0000-0000-0000-000000020013', 'discord-unbound-source', 'discord', 'Unbound Discord source', 'v1-claim', null);

insert into public.x_source_profiles (source_id, requested_handle, account_id, display_name, resolution_status)
values
  ('00000000-0000-0000-0000-000000020011', 'unbound_claim', 'unbound_claim', 'Unbound X source', 'resolved'),
  ('00000000-0000-0000-0000-000000020012', 'bound_claim', 'bound_claim', 'Bound X source', 'resolved');

insert into public.source_collection_coverage (source_id, coverage_start_at, coverage_through_at)
values
  ('00000000-0000-0000-0000-000000020011', '2026-07-23T00:00:00+08:00', '2026-07-23T00:00:00+08:00'),
  ('00000000-0000-0000-0000-000000020012', '2026-07-23T00:00:00+08:00', '2026-07-23T00:00:00+08:00');

create temporary table unbound_x_task as
select public.create_windowed_x_sync_task(
  '00000000-0000-0000-0000-000000020011', 'v2-claim', null, 'scheduled',
  '2026-07-23T08:00:00+08:00', '2026-07-23T08:00+08:00'
) as payload;
create temporary table bound_x_task as
select public.create_windowed_x_sync_task(
  '00000000-0000-0000-0000-000000020012', 'v2-claim', null, 'scheduled',
  '2026-07-23T08:00:00+08:00', '2026-07-23T08:00+08:00'
) as payload;

insert into public.sync_tasks (id, task_type, source_id, status, parameter_version, collection_scope, queued_at)
values (
  '00000000-0000-0000-0000-000000020101', 'discord_sync', '00000000-0000-0000-0000-000000020013',
  'queued', 'v1-claim', '{"mode":"incremental","max_pages":1}'::jsonb, '2099-01-01T00:00:00Z'
);

create temporary table bound_x_claim as
select public.claim_next_task('00000000-0000-0000-0000-000000020001', '2026-07-23T00:01:00Z') as payload;

select is(
  (select payload->>'task_id' from bound_x_claim),
  (select payload->>'id' from bound_x_task),
  'a dedicated X Worker skips an older unbound X task and claims only its explicitly bound source'
);
select is(
  (select payload->>'source_id' from bound_x_claim),
  '00000000-0000-0000-0000-000000020012',
  'an X claim returns the source UUID used by the local V2 Worker configuration'
);
select is(
  (select status from public.sync_tasks where id = (select (payload->>'id')::uuid from unbound_x_task)),
  'queued',
  'an unbound X task remains unleased'
);

create temporary table other_claim as
select public.claim_next_task('00000000-0000-0000-0000-000000020002', '2026-07-23T00:02:00Z') as payload;

select is(
  (select payload->>'task_id' from other_claim),
  '00000000-0000-0000-0000-000000020101',
  'an unbound X task is not claimable by another Worker, while unbound Discord work remains claimable'
);
select is(
  (select payload->>'source_id' from other_claim),
  'discord-unbound-source',
  'the Discord claim envelope preserves its existing source-key contract'
);

select * from finish();
rollback;
