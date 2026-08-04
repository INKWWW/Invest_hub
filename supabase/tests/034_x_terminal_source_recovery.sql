begin;

select plan(10);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at)
values
  ('00000000-0000-0000-0000-000000034001', 'authenticated', 'authenticated', 'x-recovery-admin@example.invalid', 'not-a-secret', now()),
  ('00000000-0000-0000-0000-000000034002', 'authenticated', 'authenticated', 'x-recovery-user@example.invalid', 'not-a-secret', now());
insert into public.profiles (id, role, display_name)
values
  ('00000000-0000-0000-0000-000000034001', 'admin', 'X Recovery Admin'),
  ('00000000-0000-0000-0000-000000034002', 'user', 'X Recovery User');
insert into public.sources (id, source_key, source_type, display_name, parameter_version)
values ('00000000-0000-0000-0000-000000034011', 'x-terminal-recovery-source', 'x', 'X Terminal Recovery Source', 'v2-terminal-recovery');
insert into public.x_source_profiles (source_id, requested_handle, account_id, display_name, resolution_status)
values ('00000000-0000-0000-0000-000000034011', 'terminal_recovery', 'terminal_recovery', 'X Terminal Recovery Source', 'resolved');
insert into public.source_collection_coverage (source_id, coverage_start_at, coverage_through_at)
values ('00000000-0000-0000-0000-000000034011', '2026-07-24T00:00:00Z', '2026-07-24T00:00:00Z');
insert into public.workers (id, name, device_secret_hash, status)
values ('00000000-0000-0000-0000-000000034101', 'x-terminal-recovery-worker', 'x-terminal-recovery-worker-hash', 'online');
update public.sources set authorized_worker_id = '00000000-0000-0000-0000-000000034101'
where id = '00000000-0000-0000-0000-000000034011';

create temporary table x_terminal_failed_task as
select public.create_windowed_x_sync_task(
  '00000000-0000-0000-0000-000000034011', 'v2-terminal-recovery', null, 'scheduled',
  '2026-07-24T12:00:00+08:00', '2026-07-24T12:00+08:00'
) as payload;
update public.sync_tasks set status = 'failed'
where id = (select (payload->>'id')::uuid from x_terminal_failed_task);

select throws_ok(
  $$select public.create_x_terminal_recovery_task((select (payload->>'id')::uuid from x_terminal_failed_task), '00000000-0000-0000-0000-000000034002')$$,
  '42501', null, 'only an administrator can create a terminal source recovery'
);

create temporary table x_terminal_recovery_task as
select public.create_x_terminal_recovery_task(
  (select (payload->>'id')::uuid from x_terminal_failed_task),
  '00000000-0000-0000-0000-000000034001'
) as payload;

select is((select payload->>'task_type' from x_terminal_recovery_task), 'x_sync', 'replacement is an X sync task');
select is((select payload->'capture_range'->>'trigger' from x_terminal_recovery_task), 'recovery', 'replacement has an explicit recovery trigger');
select is((select payload->'capture_range'->>'start_at' from x_terminal_recovery_task),
  (select payload->'capture_range'->>'start_at' from x_terminal_failed_task), 'replacement preserves failed range start');
select is((select payload->'capture_range'->>'end_at' from x_terminal_recovery_task),
  (select payload->'capture_range'->>'end_at' from x_terminal_failed_task), 'replacement preserves failed range end');
select is((select recovered_from_task_id::text from public.sync_tasks where id = (select (payload->>'id')::uuid from x_terminal_recovery_task)),
  (select payload->>'id' from x_terminal_failed_task), 'replacement links back to immutable failed task');
select is((select status from public.sync_tasks where id = (select (payload->>'id')::uuid from x_terminal_failed_task)), 'failed', 'original terminal task remains failed');
create temporary table x_terminal_recovery_claim as
select public.claim_next_task('00000000-0000-0000-0000-000000034101', '2026-07-24T04:01:00Z') as payload;
select public.record_task_failure(
  (select (payload->>'task_id')::uuid from x_terminal_recovery_claim), 1,
  '{"status":"retryable_failed","failure_class":"persistence_failure","failure_stage":"remote_page_persist","safe_checkpoint":null,"retryable":true}'::jsonb,
  '{"worker_id":"00000000-0000-0000-0000-000000034101"}'::jsonb
);
select is((select failure->>'failure_stage' from public.task_attempts where task_id = (select (payload->>'task_id')::uuid from x_terminal_recovery_claim) and attempt = 1),
  'remote_page_persist', 'attempt failure preserves the safe failure stage');
select is((select details->>'failure_stage' from public.task_events where task_id = (select (payload->>'task_id')::uuid from x_terminal_recovery_claim) and event_type = 'retry'),
  'remote_page_persist', 'task event records the safe failure stage');
select throws_ok(
  $$select public.create_x_terminal_recovery_task((select (payload->>'id')::uuid from x_terminal_failed_task), '00000000-0000-0000-0000-000000034001')$$,
  '23505', null, 'one failed task cannot have multiple replacements'
);

select * from finish();
rollback;
