begin;

select plan(24);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at)
values
  ('00000000-0000-0000-0000-000000043001', 'authenticated', 'authenticated', 'x-gap-admin@example.invalid', 'fixture-only', now()),
  ('00000000-0000-0000-0000-000000043002', 'authenticated', 'authenticated', 'x-gap-user@example.invalid', 'fixture-only', now());
insert into public.profiles (id, role, display_name)
values
  ('00000000-0000-0000-0000-000000043001', 'admin', 'X Gap Admin'),
  ('00000000-0000-0000-0000-000000043002', 'user', 'X Gap User');
insert into public.workers (id, name, device_secret_hash, status, capabilities, last_heartbeat_at)
values ('00000000-0000-0000-0000-000000043010', 'x-gap-worker', 'x-gap-worker-hash', 'online', array['x_sync'], '2099-01-02T12:00:00Z');

insert into public.sources (id, source_key, source_type, display_name, parameter_version, authorized_worker_id)
values
  ('00000000-0000-0000-0000-000000043011', 'x-gap-source-a', 'x', 'X gap source A', 'v4-gap-test', '00000000-0000-0000-0000-000000043010'),
  ('00000000-0000-0000-0000-000000043012', 'x-gap-source-b', 'x', 'X gap source B', 'v4-gap-test', '00000000-0000-0000-0000-000000043010'),
  ('00000000-0000-0000-0000-000000043013', 'x-gap-source-c', 'x', 'X gap source C', 'v4-gap-test', '00000000-0000-0000-0000-000000043010');
insert into public.x_source_profiles (source_id, requested_handle, account_id, display_name, resolution_status)
values
  ('00000000-0000-0000-0000-000000043011', 'x_gap_a', 'x_gap_a', 'X gap source A', 'resolved'),
  ('00000000-0000-0000-0000-000000043012', 'x_gap_b', 'x_gap_b', 'X gap source B', 'resolved'),
  ('00000000-0000-0000-0000-000000043013', 'x_gap_c', 'x_gap_c', 'X gap source C', 'resolved');
insert into public.source_collection_coverage (source_id, coverage_start_at, coverage_through_at)
values
  ('00000000-0000-0000-0000-000000043011', '2099-01-02T00:00:00Z', '2099-01-02T04:00:00Z'),
  ('00000000-0000-0000-0000-000000043012', '2099-01-02T00:00:00Z', '2099-01-02T04:00:00Z'),
  ('00000000-0000-0000-0000-000000043013', '2099-01-02T00:00:00Z', '2099-01-02T04:00:00Z');

insert into public.sync_tasks (
  id, task_type, source_id, status, parameter_version, collection_scope, capture_range,
  author_profile_snapshot, x_source_snapshot
) values (
  '00000000-0000-0000-0000-000000043021', 'x_sync', '00000000-0000-0000-0000-000000043011', 'succeeded',
  'v4-gap-test', '{"mode":"window"}'::jsonb,
  '{"mode":"window","trigger":"scheduled","timezone":"Asia/Shanghai","start_at":"2099-01-02T00:00:00Z","end_at":"2099-01-02T04:00:00Z","scheduled_window_key":"2099-01-02T12:00+08:00","overlap_start_at":"2099-01-02T00:00:00Z"}'::jsonb,
  '[]'::jsonb, '{"source_type":"x","account_id":"x_gap_a","display_name":"X gap source A","parameter_version":"v4-gap-test"}'::jsonb
);
update public.source_collection_coverage
set last_completed_task_id = '00000000-0000-0000-0000-000000043021'
where source_id = '00000000-0000-0000-0000-000000043011';

select has_table('public', 'x_collection_gaps', 'the immutable X gap ledger exists');
select has_function('public', 'skip_terminal_x_window', array['uuid', 'uuid', 'timestamptz'], 'the explicit historical skip exists');

create temporary table task_a as
select public.create_windowed_x_sync_task(
  '00000000-0000-0000-0000-000000043011', 'v4-gap-test', null, 'scheduled',
  '2099-01-02T08:00:00Z', '2099-01-02T16:00+08:00'
) as payload;
create temporary table claim_a_one as
select public.claim_next_task('00000000-0000-0000-0000-000000043010', '2099-01-02T12:01:00Z') as payload;
select public.record_task_failure(
  (select (payload->>'task_id')::uuid from claim_a_one), 1,
  '{"status":"retryable_failed","failure_class":"timeout","failure_stage":"collection_fetch","retryable":true}'::jsonb,
  '{"worker_id":"00000000-0000-0000-0000-000000043010"}'::jsonb
);
select is((select status from public.sync_tasks where id = (select (payload->>'id')::uuid from task_a)), 'retryable_failed', 'attempt one remains retryable');
select is((select count(*)::text from public.x_collection_gaps where failed_task_id = (select (payload->>'id')::uuid from task_a)), '0', 'attempt one does not create a gap');
select is((select coverage_through_at::text from public.source_collection_coverage where source_id = '00000000-0000-0000-0000-000000043011'), '2099-01-02 04:00:00+00', 'attempt one does not advance coverage');

create temporary table claim_a_two as
select public.claim_next_task('00000000-0000-0000-0000-000000043010', '2099-01-02T12:06:00Z') as payload;
select public.record_task_failure(
  (select (payload->>'task_id')::uuid from claim_a_two), 2,
  '{"status":"retryable_failed","failure_class":"timeout","failure_stage":"collection_fetch","retryable":false}'::jsonb,
  '{"worker_id":"00000000-0000-0000-0000-000000043010"}'::jsonb
);
select is((select status from public.sync_tasks where id = (select (payload->>'id')::uuid from task_a)), 'failed', 'attempt two is terminal');
select is((select count(*)::text from public.x_collection_gaps where failed_task_id = (select (payload->>'id')::uuid from task_a)), '1', 'attempt two creates one immutable gap');
select is((select source_id::text from public.x_collection_gaps where failed_task_id = (select (payload->>'id')::uuid from task_a)), '00000000-0000-0000-0000-000000043011', 'gap is bound to its source');
select is((select natural_date::text from public.x_collection_gaps where failed_task_id = (select (payload->>'id')::uuid from task_a)), '2099-01-02', 'gap uses the batch logical date');
select is((select window_start_at::text || '/' || window_end_at::text from public.x_collection_gaps where failed_task_id = (select (payload->>'id')::uuid from task_a)), '2099-01-02 04:00:00+00/2099-01-02 08:00:00+00', 'gap stores the exact missing range');
select is((select failure_class from public.x_collection_gaps where failed_task_id = (select (payload->>'id')::uuid from task_a)), 'timeout', 'gap stores only the safe failure class');
select is((select last_completed_task_id::text from public.source_collection_coverage where source_id = '00000000-0000-0000-0000-000000043011'), '00000000-0000-0000-0000-000000043021', 'gap skip preserves the last real success pointer');
select is((select count(*)::text from public.sync_task_capture_segments where task_id = (select (payload->>'id')::uuid from task_a)), '0', 'a failed task has no captured segment');

create temporary table duplicate_failure as
select public.record_task_failure(
  (select (payload->>'task_id')::uuid from claim_a_two), 2,
  '{"status":"retryable_failed","failure_class":"timeout","failure_stage":"collection_fetch","retryable":false}'::jsonb,
  '{"worker_id":"00000000-0000-0000-0000-000000043010"}'::jsonb
) as payload;
select is((select payload->>'idempotent' from duplicate_failure), 'true', 'duplicate terminal failure is idempotent');

select public.enqueue_due_x_tasks('00000000-0000-0000-0000-000000043010', '2099-01-02T12:10:00Z');
select is((select capture_range->>'start_at' from public.sync_tasks where source_id = '00000000-0000-0000-0000-000000043011' and status = 'queued'), '2099-01-02T08:00:00+00:00', 'the next A window starts at the skipped end');
select is((select count(*)::text from public.sync_tasks where source_id = '00000000-0000-0000-0000-000000043012' and status = 'queued'), '1', 'source B remains independently schedulable');

create temporary table task_c as
select public.create_windowed_x_sync_task(
  '00000000-0000-0000-0000-000000043013', 'v4-gap-test', null, 'scheduled',
  '2099-01-02T08:00:00Z', '2099-01-02T16:00+08:00'
) as payload;
update public.sync_tasks set status = 'failed' where id = (select (payload->>'id')::uuid from task_c);
update public.source_collection_coverage
set coverage_through_at = '2099-01-02T00:00:00Z'
where source_id = '00000000-0000-0000-0000-000000043013';
select throws_ok(
  $$select public.skip_terminal_x_window((select (payload->>'id')::uuid from task_c), '00000000-0000-0000-0000-000000043001', '2099-01-02T12:11:00Z')$$,
  '22023', null, 'historical skip rejects a stale source waterline'
);
select is((select count(*)::text from public.x_collection_gaps where failed_task_id = (select (payload->>'id')::uuid from task_c)), '0', 'waterline mismatch leaves no gap');
update public.source_collection_coverage
set coverage_through_at = '2099-01-02T04:00:00Z'
where source_id = '00000000-0000-0000-0000-000000043013';
select throws_ok(
  $$select public.skip_terminal_x_window((select (payload->>'id')::uuid from task_c), '00000000-0000-0000-0000-000000043002', '2099-01-02T12:11:00Z')$$,
  '42501', null, 'historical skip requires an administrator'
);
select public.skip_terminal_x_window((select (payload->>'id')::uuid from task_c), '00000000-0000-0000-0000-000000043001', '2099-01-02T12:12:00Z');
select is((select count(*)::text from public.x_collection_gaps where failed_task_id = (select (payload->>'id')::uuid from task_c)), '1', 'admin historical skip creates one gap');
select is((select coverage_through_at::text from public.source_collection_coverage where source_id = '00000000-0000-0000-0000-000000043013'), '2099-01-02 08:00:00+00', 'admin historical skip advances only the exact frontier');

create temporary table task_c_two as
select public.create_windowed_x_sync_task(
  '00000000-0000-0000-0000-000000043013', 'v4-gap-test', null, 'scheduled',
  '2099-01-02T12:00:00Z', '2099-01-02T20:00+08:00'
) as payload;
update public.sync_tasks
set status = 'failed'
where source_id in ('00000000-0000-0000-0000-000000043011', '00000000-0000-0000-0000-000000043012')
  and status = 'queued';
create temporary table claim_c_two as
select public.claim_next_task('00000000-0000-0000-0000-000000043010', '2099-01-02T12:13:00Z') as payload;
create function public.test_043_reject_gap_insert()
returns trigger
language plpgsql
as $$
begin
  raise exception 'injected_gap_insert_failure' using errcode = 'P0001';
end;
$$;
create trigger test_043_reject_gap_insert
before insert on public.x_collection_gaps
for each row execute function public.test_043_reject_gap_insert();
select throws_ok(
  $$select public.record_task_failure(
    (select (payload->>'task_id')::uuid from claim_c_two), 1,
    '{"status":"retryable_failed","failure_class":"timeout","failure_stage":"collection_fetch","retryable":false}'::jsonb,
    '{"worker_id":"00000000-0000-0000-0000-000000043010"}'::jsonb
  )$$,
  'P0001', null, 'gap insert failure rolls back the terminal transition'
);
select is(
  format('%s/%s/%s',
    (select status from public.sync_tasks where id = (select (payload->>'id')::uuid from task_c_two)),
    (select coverage_through_at::text from public.source_collection_coverage where source_id = '00000000-0000-0000-0000-000000043013'),
    (select count(*)::text from public.x_collection_gaps where failed_task_id = (select (payload->>'id')::uuid from task_c_two))
  ),
  'leased/2099-01-02 08:00:00+00/0',
  'gap insert failure rolls back task status, coverage, and gap ledger'
);
drop trigger test_043_reject_gap_insert on public.x_collection_gaps;
drop function public.test_043_reject_gap_insert();
select throws_ok(
  $$update public.x_collection_gaps set failure_class = 'changed' where failed_task_id = (select (payload->>'id')::uuid from task_a)$$,
  '55000', null, 'gap ledger rejects mutation after insertion'
);

select * from finish();
rollback;
