begin;

select plan(12);

insert into public.sources (id, source_key, source_type, display_name, parameter_version)
values ('00000000-0000-0000-0000-000000013001', 'x-window-source', 'x', 'X window source', 'v2-window');
insert into public.x_source_profiles (source_id, requested_handle, account_id, display_name, resolution_status)
values ('00000000-0000-0000-0000-000000013001', 'window_author', 'account-window', 'Window Author', 'resolved');
insert into public.source_collection_coverage (source_id, coverage_start_at, coverage_through_at)
values ('00000000-0000-0000-0000-000000013001', '2026-07-23T00:00:00+08:00', '2026-07-23T00:00:00+08:00');

create temporary table x_task as
select public.create_windowed_x_sync_task(
  '00000000-0000-0000-0000-000000013001', 'v2-window', null, 'scheduled',
  '2026-07-23T08:00:00+08:00', '2026-07-23T08:00+08:00'
) as payload;

select is((select payload->>'task_type' from x_task), 'x_sync', 'X schedule creates an X task');
select is((select payload->'capture_range'->>'start_at' from x_task), '2026-07-22T16:00:00+00:00', 'continuous range starts at the last successful waterline');
select is((select payload->'capture_range'->>'overlap_start_at' from x_task), '2026-07-22T16:00:00+00:00', 'first-day overlap does not read before Shanghai day start');
select is((select payload->'capture_range'->>'end_at' from x_task), '2026-07-23T00:00:00+00:00', 'scheduled end is immutable');
select is((select payload->'x_source_snapshot'->>'account_id' from x_task), 'account-window', 'task snapshots only the resolved X identity');

select is(
  (select (public.create_windowed_x_sync_task(
    '00000000-0000-0000-0000-000000013001', 'v2-window', null, 'scheduled',
    '2026-07-23T12:00:00+08:00', '2026-07-23T12:00+08:00'
  )->>'id')),
  (select payload->>'id' from x_task),
  'a failed or active predecessor is reused before a later cutoff can skip it'
);
select throws_ok(
  $$select public.create_windowed_x_sync_task('00000000-0000-0000-0000-000000013001', 'v2-window', null, 'scheduled', '2026-07-23T20:50:00+08:00', '2026-07-23T20:50+08:00')$$,
  '22023', null, 'X does not accept the legacy Discord 20:50 cutoff'
);
select throws_ok(
  $$select public.create_windowed_x_sync_task('00000000-0000-0000-0000-000000013001', 'bad', null, 'scheduled', '2026-07-23T12:00:00+08:00', '2026-07-23T12:00+08:00')$$,
  '22023', null, 'parameter drift cannot create an X range'
);

insert into public.workers (id, name, device_secret_hash, status)
values ('00000000-0000-0000-0000-000000013101', 'x-window-worker', 'x-window-worker-hash', 'online');
create temporary table x_claim as
select public.claim_next_task('00000000-0000-0000-0000-000000013101', '2026-07-23T00:01:00Z') as payload;
select is((select payload->>'task_type' from x_claim), 'x_sync', 'the regular worker claim path returns the X task');
select is((select payload->'source_snapshot'->>'account_id' from x_claim), 'account-window', 'an X claim includes its safe resolved-account snapshot');

create temporary table x_due as
select public.enqueue_due_x_tasks('00000000-0000-0000-0000-000000013101', '2026-07-23T04:00:00Z') as payload;
select is((select jsonb_array_length(payload->'tasks')::text from x_due), '1', 'a due X tick emits one source-isolated active task');
select is((select payload->'tasks'->0->>'id' from x_due), (select payload->>'id' from x_task), 'a due later tick reuses the oldest unfinished X range');

select * from finish();
rollback;
