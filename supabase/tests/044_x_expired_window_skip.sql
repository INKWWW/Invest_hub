begin;

select plan(25);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at)
values ('00000000-0000-0000-0000-000000044001', 'authenticated', 'authenticated', 'x-expired-user@example.invalid', 'fixture-only', now());
insert into public.profiles (id, role, display_name)
values ('00000000-0000-0000-0000-000000044001', 'user', 'X Expired User');
insert into public.workers (id, name, device_secret_hash, status, capabilities, last_heartbeat_at)
values
  ('00000000-0000-0000-0000-000000044010', 'x-expired-worker-a', 'x-expired-worker-a-hash', 'online', array['x_sync'], '2099-01-02T12:00:00Z'),
  ('00000000-0000-0000-0000-000000044020', 'x-expired-worker-b', 'x-expired-worker-b-hash', 'online', array['x_sync'], '2099-01-02T12:00:00Z');

insert into public.sources (id, source_key, source_type, display_name, parameter_version, authorized_worker_id)
values
  ('00000000-0000-0000-0000-000000044011', 'x-expired-source-a', 'x', 'X expired source A', 'v4-expired-test', '00000000-0000-0000-0000-000000044010'),
  ('00000000-0000-0000-0000-000000044012', 'x-expired-source-b', 'x', 'X expired source B', 'v4-expired-test', '00000000-0000-0000-0000-000000044010'),
  ('00000000-0000-0000-0000-000000044013', 'x-expired-source-c', 'x', 'X expired source C', 'v4-expired-test', '00000000-0000-0000-0000-000000044020');
insert into public.x_source_profiles (source_id, requested_handle, account_id, display_name, resolution_status)
values
  ('00000000-0000-0000-0000-000000044011', 'x_expired_a', 'x_expired_a', 'X expired source A', 'resolved'),
  ('00000000-0000-0000-0000-000000044012', 'x_expired_b', 'x_expired_b', 'X expired source B', 'resolved'),
  ('00000000-0000-0000-0000-000000044013', 'x_expired_c', 'x_expired_c', 'X expired source C', 'resolved');
insert into public.source_collection_coverage (source_id, coverage_start_at, coverage_through_at)
values
  ('00000000-0000-0000-0000-000000044011', '2099-01-02T00:00:00Z', '2099-01-02T04:00:00Z'),
  ('00000000-0000-0000-0000-000000044012', '2099-01-02T00:00:00Z', '2099-01-02T04:00:00Z'),
  ('00000000-0000-0000-0000-000000044013', '2099-01-02T00:00:00Z', '2099-01-02T04:00:00Z');

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

create temporary table task_c as
select public.create_windowed_x_sync_task(
  '00000000-0000-0000-0000-000000044013', 'v4-expired-test', null, 'scheduled',
  '2099-01-02T16:00:00+08:00', '2099-01-02T16:00+08:00'
) as payload;

create temporary table claim_c_one as
select public.claim_next_task('00000000-0000-0000-0000-000000044020', '2099-01-02T12:01:00Z') as payload;

create temporary table claim_a_two as
select public.claim_next_task('00000000-0000-0000-0000-000000044010', '2099-01-02T12:12:00Z') as payload;
select is((select payload->>'attempt' from claim_a_two), '2', 'first expired lease gets one retry');
select is((select status from public.sync_tasks where id = (select (payload->>'id')::uuid from task_a)), 'leased', 'worker A keeps the retried task leased before any cross-worker claim');

select is(
  public.reap_expired_x_window_tasks(
    '00000000-0000-0000-0000-000000044020'::uuid,
    '2099-01-02T12:23:00Z'::timestamptz
  )::text,
  '0',
  'worker B helper does not reap worker A expired task'
);
select is((select status from public.sync_tasks where id = (select (payload->>'id')::uuid from task_a)), 'leased', 'worker B helper leaves worker A task leased');

update public.sync_tasks
set lease_owner = '00000000-0000-0000-0000-000000044020'
where id = (select (payload->>'id')::uuid from task_a);
select is(
  public.reap_expired_x_window_tasks(
    '00000000-0000-0000-0000-000000044010'::uuid,
    '2099-01-02T12:23:00Z'::timestamptz
  )::text,
  '0',
  'worker A does not reap an expired task leased to another worker'
);
select is((select status from public.sync_tasks where id = (select (payload->>'id')::uuid from task_a)), 'leased', 'lease owner guard leaves the task leased');
update public.sync_tasks
set lease_owner = '00000000-0000-0000-0000-000000044010'
where id = (select (payload->>'id')::uuid from task_a);

update public.task_attempts
set worker_id = '00000000-0000-0000-0000-000000044020'
where task_id = (select (payload->>'id')::uuid from task_a) and attempt = 2;
select is(
  public.reap_expired_x_window_tasks(
    '00000000-0000-0000-0000-000000044010'::uuid,
    '2099-01-02T12:23:00Z'::timestamptz
  )::text,
  '0',
  'worker A does not reap an expired attempt owned by another worker'
);
select is((select status from public.sync_tasks where id = (select (payload->>'id')::uuid from task_a)), 'leased', 'attempt owner guard leaves the task leased');
update public.task_attempts
set worker_id = '00000000-0000-0000-0000-000000044010'
where task_id = (select (payload->>'id')::uuid from task_a) and attempt = 2;

create temporary table claim_c_two as
select public.claim_next_task('00000000-0000-0000-0000-000000044020', '2099-01-02T12:12:00Z') as payload;
update public.workers
set status = 'offline'
where id = '00000000-0000-0000-0000-000000044020';

select throws_ok(
  $$select public.reap_expired_x_window_tasks('00000000-0000-0000-0000-000000044020', '2099-01-02T12:23:00Z')$$,
  '42501', 'worker_not_authorized', 'reaper rejects an invalid worker before scanning sources'
);
select throws_ok(
  $$select public.claim_next_task('00000000-0000-0000-0000-000000044020', '2099-01-02T12:23:00Z')$$,
  '42501', 'worker_not_authorized', 'invalid worker is rejected before expiry reaping'
);
select is((select status from public.sync_tasks where id = (select (payload->>'id')::uuid from task_c)), 'leased', 'rejected worker cannot mutate its expired task');
select is((select count(*)::text from public.x_collection_gaps where failed_task_id = (select (payload->>'id')::uuid from task_c)), '0', 'rejected worker cannot create a gap');
update public.workers
set status = 'online'
where id = '00000000-0000-0000-0000-000000044020';

create temporary table claim_b_after_a as
select public.claim_next_task('00000000-0000-0000-0000-000000044010', '2099-01-02T12:24:00Z') as payload;
select is((select payload->>'task_id' from claim_b_after_a), (select payload->>'id' from task_b), 'worker A reaps its own expired lease and moves to the next source');
select is((select payload->>'attempt' from claim_b_after_a), '1', 'next source starts at attempt one');

select is((select status from public.sync_tasks where id = (select (payload->>'id')::uuid from task_a)), 'failed', 'expired X window becomes terminal');
select is((select count(*)::text from public.task_attempts where task_id = (select (payload->>'id')::uuid from task_a)), '2', 'expired X window never creates a third attempt');
select is((select status from public.task_attempts where task_id = (select (payload->>'id')::uuid from task_a) and attempt = 1), 'retryable_failed', 'first expired attempt remains retryable history');
select is((select status from public.task_attempts where task_id = (select (payload->>'id')::uuid from task_a) and attempt = 2), 'failed', 'second expired attempt is terminal history');
select is((select failure->>'failure_class' from public.task_attempts where task_id = (select (payload->>'id')::uuid from task_a) and attempt = 2), 'lease_expired', 'terminal attempt records a safe lease failure class');
select is((select failure ? 'failure_stage' from public.task_attempts where task_id = (select (payload->>'id')::uuid from task_a) and attempt = 2), false, 'terminal lease expiry does not write an unknown failure stage');
select is((select count(*)::text from public.x_collection_gaps where failed_task_id = (select (payload->>'id')::uuid from task_a)), '1', 'terminal lease expiry creates one gap');
select is((select coverage_through_at::text from public.source_collection_coverage where source_id = '00000000-0000-0000-0000-000000044011'), '2099-01-02 08:00:00+00', 'gap transition advances only the failed source waterline');
select is((select coverage_through_at::text from public.source_collection_coverage where source_id = '00000000-0000-0000-0000-000000044012'), '2099-01-02 04:00:00+00', 'other source waterline remains independent');
select is((select coverage_through_at::text from public.source_collection_coverage where source_id = '00000000-0000-0000-0000-000000044013'), '2099-01-02 04:00:00+00', 'worker B source waterline remains independent');

select * from finish();
rollback;
