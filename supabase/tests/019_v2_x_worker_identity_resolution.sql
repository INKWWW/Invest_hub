begin;

select plan(18);

insert into public.workers (id, name, device_secret_hash, status)
values
  ('00000000-0000-0000-0000-000000019001', 'x-identity-worker', 'x-identity-worker-hash', 'online'),
  ('00000000-0000-0000-0000-000000019002', 'other-x-identity-worker', 'other-x-identity-worker-hash', 'online');

insert into public.sources (id, source_key, source_type, display_name, parameter_version, authorized_worker_id)
values
  ('00000000-0000-0000-0000-000000019011', 'x-identity-primary', 'x', 'X Identity Primary', 'v2-identity', '00000000-0000-0000-0000-000000019001'),
  ('00000000-0000-0000-0000-000000019012', 'x-identity-coverage', 'x', 'X Identity Coverage', 'v2-identity', '00000000-0000-0000-0000-000000019001'),
  ('00000000-0000-0000-0000-000000019013', 'x-identity-queued', 'x', 'X Identity Queued', 'v2-identity', '00000000-0000-0000-0000-000000019001'),
  ('00000000-0000-0000-0000-000000019014', 'x-identity-leased', 'x', 'X Identity Leased', 'v2-identity', '00000000-0000-0000-0000-000000019001'),
  ('00000000-0000-0000-0000-000000019015', 'x-identity-retryable', 'x', 'X Identity Retryable', 'v2-identity', '00000000-0000-0000-0000-000000019001'),
  ('00000000-0000-0000-0000-000000019016', 'x-identity-running', 'x', 'X Identity Running', 'v2-identity', '00000000-0000-0000-0000-000000019001'),
  ('00000000-0000-0000-0000-000000019017', 'x-identity-unbound', 'x', 'X Identity Unbound', 'v2-identity', null),
  ('00000000-0000-0000-0000-000000019018', 'x-identity-mismatch', 'x', 'X Identity Mismatch', 'v2-identity', '00000000-0000-0000-0000-000000019001');

insert into public.x_source_profiles (source_id, requested_handle, display_name, resolution_status)
values
  ('00000000-0000-0000-0000-000000019011', 'fixture_handle', 'X Identity Primary', 'pending'),
  ('00000000-0000-0000-0000-000000019012', 'coverage_handle', 'X Identity Coverage', 'pending'),
  ('00000000-0000-0000-0000-000000019013', 'queued_handle', 'X Identity Queued', 'pending'),
  ('00000000-0000-0000-0000-000000019014', 'leased_handle', 'X Identity Leased', 'pending'),
  ('00000000-0000-0000-0000-000000019015', 'retry_handle', 'X Identity Retryable', 'pending'),
  ('00000000-0000-0000-0000-000000019016', 'fixture_running', 'X Identity Running', 'pending'),
  ('00000000-0000-0000-0000-000000019017', 'fixture_unbound', 'X Identity Unbound', 'pending'),
  ('00000000-0000-0000-0000-000000019018', 'fixture_requested', 'X Identity Mismatch', 'pending');

insert into public.source_collection_coverage (source_id, coverage_start_at, coverage_through_at)
values ('00000000-0000-0000-0000-000000019012', '2026-07-23T00:00:00+08:00', '2026-07-23T00:00:00+08:00');

insert into public.sync_tasks (task_type, source_id, status, parameter_version, x_source_snapshot)
values
  (
    'x_sync', '00000000-0000-0000-0000-000000019013', 'queued', 'v2-identity',
    jsonb_build_object('source_type', 'x', 'account_id', 'queued_handle', 'display_name', 'X Identity Queued', 'parameter_version', 'v2-identity')
  ),
  (
    'x_sync', '00000000-0000-0000-0000-000000019014', 'leased', 'v2-identity',
    jsonb_build_object('source_type', 'x', 'account_id', 'leased_handle', 'display_name', 'X Identity Leased', 'parameter_version', 'v2-identity')
  ),
  (
    'x_sync', '00000000-0000-0000-0000-000000019015', 'retryable_failed', 'v2-identity',
    jsonb_build_object('source_type', 'x', 'account_id', 'retry_handle', 'display_name', 'X Identity Retryable', 'parameter_version', 'v2-identity')
  ),
  (
    'x_sync', '00000000-0000-0000-0000-000000019016', 'running', 'v2-identity',
    jsonb_build_object('source_type', 'x', 'account_id', 'running_handle', 'display_name', 'X Identity Running', 'parameter_version', 'v2-identity')
  );

select throws_ok(
  $$select public.resolve_x_source_identity('00000000-0000-0000-0000-000000019099', '00000000-0000-0000-0000-000000019001', 'v2-identity', 'fixture_handle')$$,
  '22023', 'source_not_found', 'missing source is rejected'
);
select throws_ok(
  $$select public.resolve_x_source_identity('00000000-0000-0000-0000-000000019011', '00000000-0000-0000-0000-000000019001', 'other-version', 'fixture_handle')$$,
  '22023', 'source_parameter_version_mismatch', 'parameter version must match before activation'
);
select throws_ok(
  $$select public.resolve_x_source_identity('00000000-0000-0000-0000-000000019011', '00000000-0000-0000-0000-000000019001', 'v2-identity', '')$$,
  '22023', 'invalid_x_identity', 'empty identity is rejected'
);
select throws_ok(
  $$select public.resolve_x_source_identity('00000000-0000-0000-0000-000000019011', '00000000-0000-0000-0000-000000019001', 'v2-identity', '@fixture_handle')$$,
  '22023', 'invalid_x_identity', 'database rejects an identity with an at-sign'
);
select throws_ok(
  $$select public.resolve_x_source_identity('00000000-0000-0000-0000-000000019011', '00000000-0000-0000-0000-000000019001', 'v2-identity', 'Fixture_Handle')$$,
  '22023', 'invalid_x_identity', 'database rejects an identity that was not normalized to lowercase'
);
select throws_ok(
  $$select public.resolve_x_source_identity('00000000-0000-0000-0000-000000019011', '00000000-0000-0000-0000-000000019002', 'v2-identity', 'fixture_handle')$$,
  '42501', 'worker_not_authorized', 'a worker not explicitly bound to the source cannot resolve it'
);
select throws_ok(
  $$select public.resolve_x_source_identity('00000000-0000-0000-0000-000000019017', '00000000-0000-0000-0000-000000019001', 'v2-identity', 'fixture_unbound')$$,
  '42501', 'worker_not_authorized', 'an unbound source rejects a real worker ID'
);
select throws_ok(
  $$select public.resolve_x_source_identity('00000000-0000-0000-0000-000000019017', null, 'v2-identity', 'fixture_unbound')$$,
  '42501', 'worker_not_authorized', 'an unbound source rejects a null worker ID'
);
select throws_ok(
  $$select public.resolve_x_source_identity('00000000-0000-0000-0000-000000019018', '00000000-0000-0000-0000-000000019001', 'v2-identity', 'fixture_other')$$,
  '22023', 'invalid_x_identity', 'a valid account different from the requested handle is rejected'
);
select throws_ok(
  $$select public.resolve_x_source_identity('00000000-0000-0000-0000-000000019012', '00000000-0000-0000-0000-000000019001', 'v2-identity', 'coverage_handle')$$,
  '23505', 'x_identity_activation_blocked', 'existing coverage blocks first identity activation'
);
select throws_ok(
  $$select public.resolve_x_source_identity('00000000-0000-0000-0000-000000019013', '00000000-0000-0000-0000-000000019001', 'v2-identity', 'queued_handle')$$,
  '23505', 'x_identity_activation_blocked', 'a queued X task blocks first identity activation'
);
select throws_ok(
  $$select public.resolve_x_source_identity('00000000-0000-0000-0000-000000019014', '00000000-0000-0000-0000-000000019001', 'v2-identity', 'leased_handle')$$,
  '23505', 'x_identity_activation_blocked', 'a leased X task blocks first identity activation'
);
select throws_ok(
  $$select public.resolve_x_source_identity('00000000-0000-0000-0000-000000019015', '00000000-0000-0000-0000-000000019001', 'v2-identity', 'retry_handle')$$,
  '23505', 'x_identity_activation_blocked', 'a retryable failed X task blocks first identity activation'
);
select throws_ok(
  $$select public.resolve_x_source_identity('00000000-0000-0000-0000-000000019016', '00000000-0000-0000-0000-000000019001', 'v2-identity', 'fixture_running')$$,
  '23505', 'x_identity_activation_blocked', 'a running X task blocks first identity activation'
);

create temporary table x_identity_success as
select public.resolve_x_source_identity(
  '00000000-0000-0000-0000-000000019011', '00000000-0000-0000-0000-000000019001', 'v2-identity', 'fixture_handle'
) as payload;
select is(
  (select payload from x_identity_success),
  jsonb_build_object(
    'source_id', '00000000-0000-0000-0000-000000019011',
    'account_id', 'fixture_handle',
    'resolution_status', 'resolved',
    'parameter_version', 'v2-identity',
    'idempotent', false
  ),
  'matching bound worker resolves a pending X source with the exact receipt'
);
select throws_ok(
  $$select public.resolve_x_source_identity('00000000-0000-0000-0000-000000019011', '00000000-0000-0000-0000-000000019001', 'v2-identity', 'other_handle')$$,
  '22023', 'x_identity_conflict', 'a resolved source identity can never be overwritten'
);
select throws_ok(
  $$select public.resolve_x_source_identity('00000000-0000-0000-0000-000000019011', '00000000-0000-0000-0000-000000019001', 'other-version', 'fixture_handle')$$,
  '22023', 'source_parameter_version_mismatch', 'a resolved source still requires the exact parameter version'
);
select is(
  public.resolve_x_source_identity('00000000-0000-0000-0000-000000019011', '00000000-0000-0000-0000-000000019001', 'v2-identity', 'fixture_handle'),
  jsonb_build_object(
    'source_id', '00000000-0000-0000-0000-000000019011',
    'account_id', 'fixture_handle',
    'resolution_status', 'resolved',
    'parameter_version', 'v2-identity',
    'idempotent', true
  ),
  'the already resolved matching identity returns the exact idempotent receipt'
);

select * from finish();
rollback;
