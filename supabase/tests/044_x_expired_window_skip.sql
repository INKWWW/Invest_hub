begin;

select plan(12);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at)
values ('00000000-0000-0000-0000-000000044001', 'authenticated', 'authenticated', 'x-expired-user@example.invalid', 'fixture-only', now());
insert into public.profiles (id, role, display_name)
values ('00000000-0000-0000-0000-000000044001', 'user', 'X Expired User');
insert into public.workers (id, name, device_secret_hash, status, capabilities, last_heartbeat_at)
values ('00000000-0000-0000-0000-000000044010', 'x-expired-worker', 'x-expired-worker-hash', 'online', array['x_sync'], '2099-01-02T12:00:00Z');

insert into public.sources (id, source_key, source_type, display_name, parameter_version, authorized_worker_id)
values
  ('00000000-0000-0000-0000-000000044011', 'x-expired-source-a', 'x', 'X expired source A', 'v4-expired-test', '00000000-0000-0000-0000-000000044010'),
  ('00000000-0000-0000-0000-000000044012', 'x-expired-source-b', 'x', 'X expired source B', 'v4-expired-test', '00000000-0000-0000-0000-000000044010');
insert into public.x_source_profiles (source_id, requested_handle, account_id, display_name, resolution_status)
values
  ('00000000-0000-0000-0000-000000044011', 'x_expired_a', 'x_expired_a', 'X expired source A', 'resolved'),
  ('00000000-0000-0000-0000-000000044012', 'x_expired_b', 'x_expired_b', 'X expired source B', 'resolved');
insert into public.source_collection_coverage (source_id, coverage_start_at, coverage_through_at)
values
  ('00000000-0000-0000-0000-000000044011', '2099-01-02T00:00:00Z', '2099-01-02T04:00:00Z'),
  ('00000000-0000-0000-0000-000000044012', '2099-01-02T00:00:00Z', '2099-01-02T04:00:00Z');

create temporary table task_a as
select public.create_windowed_x_sync_task(
  '00000000-0000-0000-0000-000000044011', 'v4-expired-test', null, 'scheduled',
  '2099-01-02T16:00:00+08:00', '2099-01-02T16:00+08:00'
) as payload;

create temporary table claim_a_one as
select public.claim_next_task('00000000-0000-0000-0000-000000044010', '2099-01-02T12:01:00Z') as payload;
select is((select payload->>'attempt' from claim_a_one), '1', 'first claim gets attempt one');

create temporary table task_b as
select public.create_windowed_x_sync_task(
  '00000000-0000-0000-0000-000000044012', 'v4-expired-test', null, 'scheduled',
  '2099-01-02T16:00:00+08:00', '2099-01-02T16:00+08:00'
) as payload;
update public.sync_tasks
set queued_at = queued_at + interval '1 second'
where id = (select (payload->>'id')::uuid from task_b);

create temporary table claim_a_two as
select public.claim_next_task('00000000-0000-0000-0000-000000044010', '2099-01-02T12:12:00Z') as payload;
select is((select payload->>'attempt' from claim_a_two), '2', 'first expired lease gets one retry');

create temporary table claim_b_after_a as
select public.claim_next_task('00000000-0000-0000-0000-000000044010', '2099-01-02T12:23:00Z') as payload;
select is((select payload->>'task_id' from claim_b_after_a), (select payload->>'id' from task_b), 'second expired lease releases the worker to another source');
select is((select payload->>'attempt' from claim_b_after_a), '1', 'next source starts at attempt one');

select is((select status from public.sync_tasks where id = (select (payload->>'id')::uuid from task_a)), 'failed', 'expired X window becomes terminal');
select is((select count(*)::text from public.task_attempts where task_id = (select (payload->>'id')::uuid from task_a)), '2', 'expired X window never creates a third attempt');
select is((select status from public.task_attempts where task_id = (select (payload->>'id')::uuid from task_a) and attempt = 1), 'retryable_failed', 'first expired attempt remains retryable history');
select is((select status from public.task_attempts where task_id = (select (payload->>'id')::uuid from task_a) and attempt = 2), 'failed', 'second expired attempt is terminal history');
select is((select failure->>'failure_class' from public.task_attempts where task_id = (select (payload->>'id')::uuid from task_a) and attempt = 2), 'lease_expired', 'terminal attempt records a safe lease failure class');
select is((select count(*)::text from public.x_collection_gaps where failed_task_id = (select (payload->>'id')::uuid from task_a)), '1', 'terminal lease expiry creates one gap');
select is((select coverage_through_at::text from public.source_collection_coverage where source_id = '00000000-0000-0000-0000-000000044011'), '2099-01-02 08:00:00+00', 'gap transition advances only the failed source waterline');
select is((select coverage_through_at::text from public.source_collection_coverage where source_id = '00000000-0000-0000-0000-000000044012'), '2099-01-02 04:00:00+00', 'other source waterline remains independent');

select * from finish();
rollback;
