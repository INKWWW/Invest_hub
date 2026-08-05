begin;
select plan(13);

select has_table('public', 'x_manual_recovery_runs', 'manual X recovery runs are persisted');
select has_table('public', 'x_manual_recovery_run_sources', 'manual X recovery freezes its source set');
select has_function('public', 'create_x_manual_recovery_run', array['uuid', 'timestamp with time zone'], 'admin can create a manual X recovery run');
select has_function('public', 'advance_x_manual_recovery_runs', array['uuid', 'timestamp with time zone'], 'eligible Worker advances manual X recovery runs');
select ok(
  exists(
    select 1
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname = 'advance_x_manual_recovery_runs'
      and position('terminal_recovery_failed' in lower(pg_get_functiondef(procedure.oid))) > 0
  ),
  'manual X recovery stops visibly after its bounded recovery fails'
);
select ok(
  exists(
    select 1
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname = 'enqueue_due_x_tasks'
      and position('recovered_from_task_id is null' in lower(pg_get_functiondef(procedure.oid))) > 0
  ),
  'automatic X recovery is bounded to a terminal root task'
);

select lives_ok(
  $$insert into public.x_collection_batches (
      id, scheduled_window_key, natural_date, cutoff_at, settlement_deadline_at, status
    ) values (
      '00000000-0000-0000-0000-000000035201',
      'manual:00000000-0000-0000-0000-000000035202',
      '2026-08-05', '2026-08-05T04:00:00Z', '2026-08-05T07:00:00Z', 'collecting'
    )$$,
  'a manual recovery batch key is valid alongside the normal scheduled key contract'
);
select is(
  (select scheduled_window_key from public.x_collection_batches where id = '00000000-0000-0000-0000-000000035201'),
  'manual:00000000-0000-0000-0000-000000035202',
  'manual recovery keeps its own immutable batch identity'
);
select throws_ok(
  $$insert into public.x_collection_batches (
      id, scheduled_window_key, natural_date, cutoff_at, settlement_deadline_at, status
    ) values (
      '00000000-0000-0000-0000-000000035203',
      'manual:not-a-run-id',
      '2026-08-05', '2026-08-05T04:00:00Z', '2026-08-05T07:00:00Z', 'collecting'
    )$$,
  '23514', null,
  'only a run-scoped manual batch key can bypass the normal timestamp key contract'
);

insert into public.workers (id, name, device_secret_hash, status, capabilities, last_heartbeat_at)
values ('00000000-0000-0000-0000-000000035101', 'manual-recovery-contract-worker', 'manual-recovery-contract-hash', 'online', array['x_sync'], now());
insert into public.sources (id, source_key, source_type, display_name, parameter_version, authorized_worker_id)
values ('00000000-0000-0000-0000-000000035111', 'manual-recovery-contract-source', 'x', 'Manual recovery contract source', 'v3-manual-recovery', '00000000-0000-0000-0000-000000035101');
insert into public.x_source_profiles (source_id, requested_handle, account_id, display_name, resolution_status)
values ('00000000-0000-0000-0000-000000035111', 'manual_recovery_contract', 'manual_recovery_contract', 'Manual recovery contract source', 'resolved');
insert into public.x_collection_batches (
  id, scheduled_window_key, natural_date, cutoff_at, settlement_deadline_at, status
) values (
  '00000000-0000-0000-0000-000000035204',
  '2026-08-05T12:00+08:00',
  '2026-08-05', '2026-08-05T04:00:00Z', '2026-08-05T07:00:00Z', 'collecting'
);
insert into public.sync_tasks (
  id, task_type, source_id, status, parameter_version, collection_scope, capture_range, author_profile_snapshot, x_source_snapshot, collection_batch_id
) values (
  '00000000-0000-0000-0000-000000035121', 'x_sync', '00000000-0000-0000-0000-000000035111', 'succeeded', 'v3-manual-recovery',
  '{"mode":"window"}'::jsonb,
  '{"mode":"window","trigger":"scheduled","timezone":"Asia/Shanghai","start_at":"2026-08-05T00:00:00Z","end_at":"2026-08-05T04:00:00Z","scheduled_window_key":"2026-08-05T12:00+08:00","overlap_start_at":"2026-08-05T00:00:00Z"}'::jsonb,
  '[]'::jsonb,
  '{"source_type":"x","account_id":"manual_recovery_contract","display_name":"Manual recovery contract source","parameter_version":"v3-manual-recovery"}'::jsonb,
  '00000000-0000-0000-0000-000000035204'
);
insert into public.x_collection_batch_sources (batch_id, source_id, source_display_name, x_sync_task_id)
values (
  '00000000-0000-0000-0000-000000035204',
  '00000000-0000-0000-0000-000000035111',
  'Manual recovery contract source',
  '00000000-0000-0000-0000-000000035121'
);
select lives_ok(
  $$insert into public.x_collection_batch_sources (batch_id, source_id, source_display_name, x_sync_task_id)
    values (
      '00000000-0000-0000-0000-000000035201',
      '00000000-0000-0000-0000-000000035111',
      'Manual recovery contract source',
      '00000000-0000-0000-0000-000000035121'
    )$$,
  'a manual recovery batch can reference a same-source successful historical window task'
);
select is(
  (select x_sync_task_id::text from public.x_collection_batch_sources where batch_id = '00000000-0000-0000-0000-000000035201'),
  '00000000-0000-0000-0000-000000035121',
  'manual recovery retains the exact historical task used as its frozen input'
);

insert into public.sources (id, source_key, source_type, display_name, parameter_version, authorized_worker_id)
values ('00000000-0000-0000-0000-000000035112', 'manual-recovery-batchless-source', 'x', 'Manual recovery batchless source', 'v3-manual-recovery', '00000000-0000-0000-0000-000000035101');
insert into public.x_source_profiles (source_id, requested_handle, account_id, display_name, resolution_status)
values ('00000000-0000-0000-0000-000000035112', 'manual_recovery_batchless', 'manual_recovery_batchless', 'Manual recovery batchless source', 'resolved');
insert into public.sync_tasks (
  id, task_type, source_id, status, parameter_version, collection_scope, capture_range, author_profile_snapshot, x_source_snapshot
) values (
  '00000000-0000-0000-0000-000000035122', 'x_sync', '00000000-0000-0000-0000-000000035112', 'succeeded', 'v3-manual-recovery',
  '{"mode":"window"}'::jsonb,
  '{"mode":"window","trigger":"scheduled","timezone":"Asia/Shanghai","start_at":"2026-08-05T00:00:00Z","end_at":"2026-08-05T04:00:00Z","scheduled_window_key":"2026-08-05T12:00+08:00","overlap_start_at":"2026-08-05T00:00:00Z"}'::jsonb,
  '[]'::jsonb,
  '{"source_type":"x","account_id":"manual_recovery_batchless","display_name":"Manual recovery batchless source","parameter_version":"v3-manual-recovery"}'::jsonb
);
select lives_ok(
  $$insert into public.x_collection_batch_sources (batch_id, source_id, source_display_name, x_sync_task_id)
    values (
      '00000000-0000-0000-0000-000000035201',
      '00000000-0000-0000-0000-000000035112',
      'Manual recovery batchless source',
      '00000000-0000-0000-0000-000000035122'
    )$$,
  'a manual recovery batch can also freeze an eligible batchless historical window task'
);
select is(
  (select x_sync_task_id::text from public.x_collection_batch_sources where batch_id = '00000000-0000-0000-0000-000000035201' and source_id = '00000000-0000-0000-0000-000000035112'),
  '00000000-0000-0000-0000-000000035122',
  'batchless historical input remains traceable in the manual recovery snapshot'
);

select * from finish();
rollback;
