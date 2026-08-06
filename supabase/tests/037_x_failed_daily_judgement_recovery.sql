begin;

select plan(15);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at)
values
  ('00000000-0000-0000-0000-000000037010', 'authenticated', 'authenticated', 'failed-recovery-admin@example.invalid', 'not-a-secret', now()),
  ('00000000-0000-0000-0000-000000037011', 'authenticated', 'authenticated', 'failed-recovery-user@example.invalid', 'not-a-secret', now());
insert into public.profiles (id, role, display_name)
values
  ('00000000-0000-0000-0000-000000037010', 'admin', 'Failed recovery admin'),
  ('00000000-0000-0000-0000-000000037011', 'user', 'Failed recovery user');

insert into public.workers (id, name, device_secret_hash, status, capabilities, last_heartbeat_at)
values ('00000000-0000-0000-0000-000000037001', 'failed-recovery-worker', 'failed-recovery-worker-hash', 'online', array['x_sync'], now());
insert into public.sources (id, source_key, source_type, display_name, parameter_version, authorized_worker_id)
values ('00000000-0000-0000-0000-000000037100', 'failed-recovery-source', 'x', 'Failed recovery source', 'v4-failed-recovery', '00000000-0000-0000-0000-000000037001');
insert into public.x_source_profiles (source_id, requested_handle, account_id, display_name, resolution_status)
values ('00000000-0000-0000-0000-000000037100', 'failed_recovery', 'failed_recovery', 'Failed recovery source', 'resolved');

insert into public.x_collection_batches (id, scheduled_window_key, natural_date, cutoff_at, settlement_deadline_at, status)
values
  ('00000000-0000-0000-0000-000000037200', '2026-08-06T08:00+08:00', '2026-08-06', '2026-08-06T00:00:00Z', '2026-08-06T02:00:00Z', 'judgement_failed'),
  ('00000000-0000-0000-0000-000000037201', '2026-08-06T12:00+08:00', '2026-08-06', '2026-08-06T04:00:00Z', '2026-08-06T06:00:00Z', 'succeeded'),
  ('00000000-0000-0000-0000-000000037202', '2026-08-06T16:00+08:00', '2026-08-06', '2026-08-06T08:00:00Z', '2026-08-06T10:00:00Z', 'judgement_failed'),
  ('00000000-0000-0000-0000-000000037203', '2026-08-06T20:00+08:00', '2026-08-06', '2026-08-06T12:00:00Z', '2026-08-06T14:00:00Z', 'judgement_failed'),
  ('00000000-0000-0000-0000-000000037204', '2026-08-07T00:00+08:00', '2026-08-06', '2026-08-06T16:00:00Z', '2026-08-06T18:00:00Z', 'judgement_failed');
insert into public.x_collection_batch_sources (batch_id, source_id, source_display_name, settlement_status, settled_at)
values
  ('00000000-0000-0000-0000-000000037200', '00000000-0000-0000-0000-000000037100', 'Failed recovery source', 'included', now()),
  ('00000000-0000-0000-0000-000000037201', '00000000-0000-0000-0000-000000037100', 'Failed recovery source', 'included', now()),
  ('00000000-0000-0000-0000-000000037203', '00000000-0000-0000-0000-000000037100', 'Failed recovery source', 'included', now()),
  ('00000000-0000-0000-0000-000000037204', '00000000-0000-0000-0000-000000037100', 'Failed recovery source', 'included', now());
insert into public.x_daily_judgement_runs (id, batch_id, status, attempt, failure_class, run_kind, available_at)
values
  ('00000000-0000-0000-0000-000000037300', '00000000-0000-0000-0000-000000037200', 'failed', 3, 'schema_error', 'initial', now()),
  ('00000000-0000-0000-0000-000000037302', '00000000-0000-0000-0000-000000037202', 'failed', 3, 'schema_error', 'initial', now()),
  ('00000000-0000-0000-0000-000000037303', '00000000-0000-0000-0000-000000037203', 'failed', 3, 'schema_error', 'initial', now()),
  ('00000000-0000-0000-0000-000000037304', '00000000-0000-0000-0000-000000037204', 'failed', 3, 'schema_error', 'initial', now());
insert into public.x_daily_judgement_versions
  (batch_id, revision, coverage_status, input_snapshot, output, provider, prompt_version, schema_version)
select
  '00000000-0000-0000-0000-000000037204', 1, 'complete',
  public.build_x_daily_judgement_input_snapshot('00000000-0000-0000-0000-000000037204'),
  '{"security_industry_viewpoints":[],"market_structure_viewpoints":[],"strategy_mindset_viewpoints":[],"uncertainties":[]}'::jsonb,
  'codex_cli', 'v4-x-cross-blogger-1', 'v4-x-cross-blogger';

create temporary table failed_recovery_batch_before as
select to_jsonb(batch) as snapshot
from public.x_collection_batches batch
where id = '00000000-0000-0000-0000-000000037200';
create temporary table failed_recovery_sources_before as
select jsonb_agg(to_jsonb(batch_source) order by batch_source.source_id) as snapshot
from public.x_collection_batch_sources batch_source
where batch_id = '00000000-0000-0000-0000-000000037200';

select has_function(
  'public', 'recover_failed_x_daily_judgement', array['uuid', 'uuid'],
  'service role can queue a new audited run for a frozen failed judgement batch'
);

set local role service_role;
select is(
  (select public.recover_failed_x_daily_judgement(
    '00000000-0000-0000-0000-000000037200', '00000000-0000-0000-0000-000000037010'
  )->>'status'),
  'queued',
  'service-role recovery queues independent work'
);
reset role;

select is(
  (select count(*)::text from public.x_daily_judgement_runs where batch_id='00000000-0000-0000-0000-000000037200'),
  '2',
  'recovery appends exactly one run without replacing the failed run'
);
select is(
  (select status || '|' || attempt::text || '|' || failure_class
     from public.x_daily_judgement_runs where id='00000000-0000-0000-0000-000000037300'),
  'failed|3|schema_error',
  'the original terminal run remains immutable'
);
select is(
  (select run_kind || '|' || requested_by::text || '|' || status || '|' || attempt::text
     from public.x_daily_judgement_runs
    where batch_id='00000000-0000-0000-0000-000000037200' and id<>'00000000-0000-0000-0000-000000037300'),
  'regeneration|00000000-0000-0000-0000-000000037010|queued|0',
  'the recovery run records actor, kind, and a fresh attempt counter'
);
select is(
  (select to_jsonb(batch) from public.x_collection_batches batch where id='00000000-0000-0000-0000-000000037200'),
  (select snapshot from failed_recovery_batch_before),
  'queueing recovery does not alter the failed frozen batch'
);
select is(
  (select jsonb_agg(to_jsonb(batch_source) order by batch_source.source_id)
     from public.x_collection_batch_sources batch_source
    where batch_id='00000000-0000-0000-0000-000000037200'),
  (select snapshot from failed_recovery_sources_before),
  'queueing recovery does not alter frozen source rows'
);
select throws_ok(
  $$select public.recover_failed_x_daily_judgement('00000000-0000-0000-0000-000000037200', '00000000-0000-0000-0000-000000037010')$$,
  'PT409', 'x_failed_judgement_recovery_active',
  'a concurrent recovery for the same frozen batch is rejected'
);
select throws_ok(
  $$select public.recover_failed_x_daily_judgement('00000000-0000-0000-0000-000000037201', '00000000-0000-0000-0000-000000037010')$$,
  '22023', 'x_failed_judgement_recovery_not_available',
  'a succeeded batch cannot enter failed-batch recovery'
);
select throws_ok(
  $$select public.recover_failed_x_daily_judgement('00000000-0000-0000-0000-000000037202', '00000000-0000-0000-0000-000000037010')$$,
  '22023', 'x_daily_judgement_no_provider_input',
  'a failed batch without included Provider input cannot recover'
);
select throws_ok(
  $$select public.recover_failed_x_daily_judgement('00000000-0000-0000-0000-000000037204', '00000000-0000-0000-0000-000000037010')$$,
  '22023', 'x_failed_judgement_recovery_requires_zero_versions',
  'a versioned failed batch cannot use the zero-version repair path'
);
select throws_ok(
  $$select public.recover_failed_x_daily_judgement('00000000-0000-0000-0000-000000037203', null)$$,
  '22023', 'invalid_x_failed_judgement_recovery_actor',
  'a null actor cannot request failed-batch recovery'
);
set local role service_role;
select throws_ok(
  $$select public.recover_failed_x_daily_judgement('00000000-0000-0000-0000-000000037203', '00000000-0000-0000-0000-000000037011')$$,
  '42501', 'actor_not_authorized',
  'service role cannot recover for an ordinary user actor'
);
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000037010', true);
select throws_ok(
  $$select public.recover_failed_x_daily_judgement('00000000-0000-0000-0000-000000037203', '00000000-0000-0000-0000-000000037010')$$,
  '42501', null,
  'authenticated admins cannot execute the service-only repair RPC directly'
);
reset role;
select is(
  (select count(*)::text from public.x_daily_judgement_runs where batch_id='00000000-0000-0000-0000-000000037203'),
  '1',
  'rejected recovery attempts leave the target failed run unchanged'
);

select * from finish();
rollback;
