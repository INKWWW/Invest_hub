begin;

select plan(30);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at)
values
  ('00000000-0000-0000-0000-000000026010', 'authenticated', 'authenticated', 'regeneration-admin@example.invalid', 'not-a-secret', now()),
  ('00000000-0000-0000-0000-000000026011', 'authenticated', 'authenticated', 'regeneration-user@example.invalid', 'not-a-secret', now());
insert into public.profiles (id, role, display_name)
values
  ('00000000-0000-0000-0000-000000026010', 'admin', 'Regeneration admin'),
  ('00000000-0000-0000-0000-000000026011', 'user', 'Regeneration user');
insert into public.workers (id, name, device_secret_hash, status, capabilities)
values ('00000000-0000-0000-0000-000000026001', 'regeneration-worker', 'regeneration-worker-hash', 'online', array['x_sync']);
insert into public.sources (id, source_key, source_type, display_name, parameter_version, authorized_worker_id)
values ('00000000-0000-0000-0000-000000026030', 'regeneration-excluded-source', 'x', 'Excluded regeneration source', 'v2-regeneration', '00000000-0000-0000-0000-000000026001');
insert into public.x_source_profiles (source_id, requested_handle, account_id, display_name, resolution_status)
values ('00000000-0000-0000-0000-000000026030', 'regeneration_excluded', 'regeneration_excluded', 'Excluded regeneration source', 'resolved');

insert into public.x_collection_batches (id, scheduled_window_key, natural_date, cutoff_at, settlement_deadline_at, status)
values
  ('00000000-0000-0000-0000-000000026020', '2026-08-01T08:00+08:00', '2026-08-01', '2026-08-01T00:00:00Z', '2026-08-01T02:00:00Z', 'succeeded'),
  ('00000000-0000-0000-0000-000000026021', '2026-08-01T12:00+08:00', '2026-08-01', '2026-08-01T04:00:00Z', '2026-08-01T06:00:00Z', 'succeeded'),
  ('00000000-0000-0000-0000-000000026022', '2026-08-01T16:00+08:00', '2026-08-01', '2026-08-01T08:00:00Z', '2026-08-01T10:00:00Z', 'collecting'),
  ('00000000-0000-0000-0000-000000026023', '2026-08-01T20:00+08:00', '2026-08-01', '2026-08-01T12:00:00Z', '2026-08-01T14:00:00Z', 'judgement_pending'),
  ('00000000-0000-0000-0000-000000026024', '2026-08-02T08:00+08:00', '2026-08-02', '2026-08-02T00:00:00Z', '2026-08-02T02:00:00Z', 'judgement_failed'),
  ('00000000-0000-0000-0000-000000026025', '2026-08-02T12:00+08:00', '2026-08-02', '2026-08-02T04:00:00Z', '2026-08-02T06:00:00Z', 'succeeded'),
  ('00000000-0000-0000-0000-000000026026', '2026-08-02T16:00+08:00', '2026-08-02', '2026-08-02T08:00:00Z', '2026-08-02T10:00:00Z', 'judgement_pending');

insert into public.x_daily_judgement_versions
  (batch_id, revision, coverage_status, input_snapshot, output, provider, model_reported, prompt_version, schema_version)
values
  ('00000000-0000-0000-0000-000000026020', 1, 'no_new_information',
    '{"sources":[]}'::jsonb, '{"stock_viewpoints":[],"market_industry_viewpoints":[],"uncertainties":["revision one"]}'::jsonb,
    'codex_cli', 'fixture-model', 'v2-x-cross-blogger-1', 'v2-x-cross-blogger'),
  ('00000000-0000-0000-0000-000000026025', 1, 'no_new_information',
    '{"sources":[]}'::jsonb, '{"stock_viewpoints":[],"market_industry_viewpoints":[],"uncertainties":[]}'::jsonb,
    'codex_cli', null, 'v2-x-cross-blogger-1', 'v2-x-cross-blogger');
insert into public.x_collection_batch_sources (batch_id, source_id, source_display_name, settlement_status, settled_at)
values
  ('00000000-0000-0000-0000-000000026020', '00000000-0000-0000-0000-000000026030', 'Excluded regeneration source', 'included', timezone('utc', now())),
  ('00000000-0000-0000-0000-000000026026', '00000000-0000-0000-0000-000000026030', 'Excluded regeneration source', 'included', timezone('utc', now()));
select has_column('public', 'x_daily_judgement_runs', 'run_kind', 'judgement runs distinguish initial and explicit regeneration work');
select has_column('public', 'x_daily_judgement_runs', 'requested_by', 'regeneration runs preserve the requesting actor');
set local role service_role;
select is(
  (select public.regenerate_x_daily_judgement('00000000-0000-0000-0000-000000026020', '00000000-0000-0000-0000-000000026010')->>'status'),
  'queued',
  'service-role regeneration queues independent work'
);
reset role;
select is((select count(*)::text from public.x_daily_judgement_runs where batch_id = '00000000-0000-0000-0000-000000026020'), '1', 'regeneration inserts exactly one run');
select is(
  (select run_kind || '|' || requested_by::text || '|' || status || '|' || attempt::text
   from public.x_daily_judgement_runs where batch_id = '00000000-0000-0000-0000-000000026020'),
  'regeneration|00000000-0000-0000-0000-000000026010|queued|0',
  'regeneration records its kind, actor, and fresh attempt'
);
select is((select status from public.x_collection_batches where id = '00000000-0000-0000-0000-000000026020'), 'succeeded', 'queueing regeneration does not alter the succeeded batch');
select is((select count(*)::text from public.x_collection_batch_sources where batch_id = '00000000-0000-0000-0000-000000026020'), '1', 'queueing regeneration does not create or alter frozen source rows');
select is(
  (select input_snapshot::text || '|' || output::text || '|' || provider || '|' || coalesce(model_reported, '')
   from public.x_daily_judgement_versions where batch_id = '00000000-0000-0000-0000-000000026020' and revision = 1),
  '{"sources": []}|{"uncertainties": ["revision one"], "stock_viewpoints": [], "market_industry_viewpoints": []}|codex_cli|fixture-model',
  'queueing regeneration leaves revision one byte-for-byte unchanged'
);

create temporary table regeneration_claim as
select public.claim_next_x_daily_judgement('00000000-0000-0000-0000-000000026001', timezone('utc', now())) as payload;
select is((select payload->>'attempt' from regeneration_claim), '1', 'normal Worker claim leases the queued regeneration');
select is(
  (select public.complete_x_daily_judgement(
    (select (payload->>'run_id')::uuid from regeneration_claim), 1, '00000000-0000-0000-0000-000000026001',
    '{"schema_version":"v2-x-cross-blogger","provider":"codex_cli","model_reported":null,"prompt_version":"v2-x-cross-blogger-1","stock_viewpoints":[],"market_industry_viewpoints":[],"uncertainties":[]}'::jsonb
  )->>'status'),
  'succeeded',
  'normal completion succeeds regeneration work'
);
select is((select count(*)::text from public.x_daily_judgement_versions where batch_id = '00000000-0000-0000-0000-000000026020'), '2', 'completion appends revision two');
select is((select max(revision)::text from public.x_daily_judgement_versions where batch_id = '00000000-0000-0000-0000-000000026020'), '2', 'the appended version is revision two');
select is(
  (select input_snapshot::text || '|' || output::text || '|' || provider || '|' || coalesce(model_reported, '')
   from public.x_daily_judgement_versions where batch_id = '00000000-0000-0000-0000-000000026020' and revision = 1),
  '{"sources": []}|{"uncertainties": ["revision one"], "stock_viewpoints": [], "market_industry_viewpoints": []}|codex_cli|fixture-model',
  'completion leaves revision one byte-for-byte unchanged'
);

insert into public.x_daily_judgement_runs (id, batch_id, status, attempt, run_kind, available_at)
values ('00000000-0000-0000-0000-000000026040', '00000000-0000-0000-0000-000000026026', 'queued', 0, 'initial', timezone('utc', now()));
select is((select count(*)::text from public.x_daily_judgement_versions where batch_id = '00000000-0000-0000-0000-000000026026'), '0', 'a queued initial run starts without a version');
create temporary table initial_claim as
select public.claim_next_x_daily_judgement('00000000-0000-0000-0000-000000026001', timezone('utc', now())) as payload;
select is((select payload->>'attempt' from initial_claim), '1', 'normal Worker claims the queued initial run as attempt one');
select is(
  (select public.fail_x_daily_judgement(
    (select (payload->>'run_id')::uuid from initial_claim), 1, '00000000-0000-0000-0000-000000026001', 'provider_failure'
  )->>'status'),
  'retryable_failed',
  'provider failure makes the initial attempt retryable'
);
create temporary table initial_retry_claim as
select public.claim_next_x_daily_judgement('00000000-0000-0000-0000-000000026001', timezone('utc', now())) as payload;
select is((select payload->>'attempt' from initial_retry_claim), '2', 'normal Worker claims the retryable initial run as attempt two');
select is(
  (select public.complete_x_daily_judgement(
    (select (payload->>'run_id')::uuid from initial_retry_claim), 2, '00000000-0000-0000-0000-000000026001',
    '{"schema_version":"v2-x-cross-blogger","provider":"codex_cli","model_reported":null,"prompt_version":"v2-x-cross-blogger-1","stock_viewpoints":[],"market_industry_viewpoints":[],"uncertainties":[]}'::jsonb
  )->>'status'),
  'succeeded',
  'normal completion succeeds the initial retryable run'
);
select is((select count(*)::text from public.x_daily_judgement_versions where batch_id = '00000000-0000-0000-0000-000000026026'), '1', 'the initial retry writes exactly one version');
select is((select max(revision)::text from public.x_daily_judgement_versions where batch_id = '00000000-0000-0000-0000-000000026026'), '1', 'the initial retry writes revision one, not revision two');

select throws_ok($$select public.regenerate_x_daily_judgement('00000000-0000-0000-0000-000000026021', '00000000-0000-0000-0000-000000026010')$$,
  '22023', 'x_daily_judgement_regeneration_requires_successful_version', 'a succeeded batch without a version cannot regenerate');
select throws_ok($$select public.regenerate_x_daily_judgement('00000000-0000-0000-0000-000000026022', '00000000-0000-0000-0000-000000026010')$$,
  '22023', 'x_daily_judgement_regeneration_not_available', 'a collecting batch cannot regenerate');
select throws_ok($$select public.regenerate_x_daily_judgement('00000000-0000-0000-0000-000000026023', '00000000-0000-0000-0000-000000026010')$$,
  '22023', 'x_daily_judgement_regeneration_not_available', 'a pending batch cannot regenerate');
select throws_ok($$select public.regenerate_x_daily_judgement('00000000-0000-0000-0000-000000026024', '00000000-0000-0000-0000-000000026010')$$,
  '22023', 'x_daily_judgement_regeneration_not_available', 'a failed batch cannot regenerate');
select throws_ok($$select public.regenerate_x_daily_judgement('00000000-0000-0000-0000-000000026025', null)$$,
  '22023', 'invalid_x_daily_judgement_regeneration_actor', 'a null actor cannot regenerate');
select throws_ok($$select public.regenerate_x_daily_judgement('00000000-0000-0000-0000-000000026025', '00000000-0000-0000-0000-000000026099')$$,
  '22023', 'invalid_x_daily_judgement_regeneration_actor', 'an unknown actor cannot regenerate');
set local role service_role;
select throws_ok($$select public.regenerate_x_daily_judgement('00000000-0000-0000-0000-000000026021', '00000000-0000-0000-0000-000000026011')$$,
  '42501', 'actor_not_authorized', 'service role cannot create regeneration work for an ordinary user actor');
reset role;
select is(
  (select public.regenerate_x_daily_judgement('00000000-0000-0000-0000-000000026025', '00000000-0000-0000-0000-000000026010')->>'status'),
  'queued',
  'a versioned succeeded batch can queue regeneration'
);
select throws_ok($$select public.regenerate_x_daily_judgement('00000000-0000-0000-0000-000000026025', '00000000-0000-0000-0000-000000026010')$$,
  'PT409', 'x_daily_judgement_regeneration_active', 'a second concurrent regeneration is rejected by the active run guard');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000026011', true);
select throws_ok($$select public.regenerate_x_daily_judgement('00000000-0000-0000-0000-000000026020', '00000000-0000-0000-0000-000000026011')$$,
  '42501', null, 'authenticated users cannot execute regeneration directly');
reset role;

select * from finish();
rollback;
