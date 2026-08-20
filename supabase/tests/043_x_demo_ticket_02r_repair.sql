begin;

select plan(28);

select has_column('public', 'x_demo_fixed_window_runs', 'owner_worker_id', 'each demo run has one immutable Worker owner');
select has_function('public', 'terminalize_x_demo_fixed_window_judgement', array['uuid', 'uuid', 'uuid'], 'Ticket 02R exposes only a demo-scoped judgement terminalization seam');

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at)
values ('00000000-0000-0000-0000-000000043001', 'authenticated', 'authenticated', 'ticket-02r-repair@example.invalid', 'not-a-secret', now());
insert into public.profiles (id, role, display_name)
values ('00000000-0000-0000-0000-000000043001', 'admin', 'Ticket 02R repair admin');
insert into public.workers (id, name, device_secret_hash, status, last_heartbeat_at, capabilities)
values
  ('00000000-0000-0000-0000-000000043002', 'Ticket 02R repair owner', 'ticket-02r-repair-hash-1', 'online', now(), array['x_sync']),
  ('00000000-0000-0000-0000-000000043003', 'Ticket 02R repair intruder', 'ticket-02r-repair-hash-2', 'online', now(), array['x_sync']),
  ('00000000-0000-0000-0000-000000043004', 'Ticket 02R repair non X', 'ticket-02r-repair-hash-3', 'online', now(), array['discord_sync']);

select public.create_x_source('x:ticket-02r-repair', 'Ticket 02R repair source', 'fixture_repair', 'x-standard-v2', '00000000-0000-0000-0000-000000043001');
select public.claim_next_x_activation('00000000-0000-0000-0000-000000043002', now());
select public.resolve_x_source_identity(
  (select id from public.sources where source_key = 'x:ticket-02r-repair'),
  '00000000-0000-0000-0000-000000043002', 'x-standard-v2', 'fixture_repair'
);
update public.sources set authorized_worker_id = '00000000-0000-0000-0000-000000043002' where source_key = 'x:ticket-02r-repair';

create temporary table repair_run as
select public.start_x_demo_fixed_window_run('2026-08-18T16:00:00+08:00', '00000000-0000-0000-0000-000000043002') as payload;
create temporary table repair_task as
select public.create_x_demo_fixed_window_task_for_worker(
  (select id from public.sources where source_key = 'x:ticket-02r-repair'),
  '2026-08-18T16:00:00+08:00', '00000000-0000-0000-0000-000000043002', 'fixture_repair'
) as payload;
select public.bind_x_demo_fixed_window_task(
  (select (payload->>'run_id')::uuid from repair_run),
  (select id from public.sources where source_key = 'x:ticket-02r-repair'),
  (select (payload->>'id')::uuid from repair_task),
  '00000000-0000-0000-0000-000000043002'
);
select is(
  (select public.claim_x_demo_fixed_window_task(
    (select (payload->>'id')::uuid from repair_task),
    '00000000-0000-0000-0000-000000043002', now()
  )->>'task_id'),
  (select payload->>'id' from repair_task),
  'the exact Ticket 02R task is claimed once'
);
select public.record_task_failure(
  (select (payload->>'id')::uuid from repair_task), 1,
  '{"status":"retryable_failed","failure_class":"provider_failure","safe_checkpoint":null,"retryable":false}'::jsonb,
  '{"worker_id":"00000000-0000-0000-0000-000000043002"}'::jsonb
);
select is((select status from public.sync_tasks where id = (select (payload->>'id')::uuid from repair_task)), 'failed', 'a non-retryable sync failure is terminal');
select is((select count(*) from public.x_collection_gaps where failed_task_id = (select (payload->>'id')::uuid from repair_task)), 0::bigint, 'a failed Demo task does not create a collection gap');
select is((select count(*) from public.source_collection_coverage where source_id = (select source_id from public.sync_tasks where id = (select (payload->>'id')::uuid from repair_task))), 0::bigint, 'a failed Demo task does not create or advance source coverage');
select is((select public.claim_x_demo_fixed_window_task((select (payload->>'id')::uuid from repair_task), '00000000-0000-0000-0000-000000043002', now()) is null), true, 'a terminal exact task cannot be claimed again');
update public.x_demo_fixed_window_runs set status = 'partial';
update public.x_collection_batches set status = 'judgement_pending';

insert into public.x_daily_judgement_runs (id, batch_id, status, attempt, available_at)
select '00000000-0000-0000-0000-000000043020', batch_id, 'retryable_failed', 2, now() from public.x_demo_fixed_window_runs;
select is((select public.terminalize_x_demo_fixed_window_judgement((select (payload->>'run_id')::uuid from repair_run), '00000000-0000-0000-0000-000000043020', '00000000-0000-0000-0000-000000043002')->>'status'), 'failed', 'exact attempt-2 retryable judgement is terminalized');
select is((select status from public.x_daily_judgement_runs where id = '00000000-0000-0000-0000-000000043020'), 'failed', 'the exact judgement becomes failed');
select is((select status from public.x_collection_batches), 'judgement_failed', 'the exact batch becomes judgement_failed');
select is((select status from public.x_demo_fixed_window_runs), 'failed', 'the exact Demo run becomes failed');
select is((select public.terminalize_x_demo_fixed_window_judgement((select (payload->>'run_id')::uuid from repair_run), '00000000-0000-0000-0000-000000043020', '00000000-0000-0000-0000-000000043002')->>'idempotent'), 'true', 'the same exact failed identity is idempotent');

insert into public.x_daily_judgement_runs (id, batch_id, status, attempt, available_at)
select '00000000-0000-0000-0000-000000043021', batch_id, 'retryable_failed', 1, now() from public.x_demo_fixed_window_runs;
select throws_ok($$select public.terminalize_x_demo_fixed_window_judgement((select (payload->>'run_id')::uuid from repair_run), '00000000-0000-0000-0000-000000043021', '00000000-0000-0000-0000-000000043002')$$, '22023', 'invalid_x_demo_fixed_window_judgement', 'attempt one is rejected');
select throws_ok($$select public.terminalize_x_demo_fixed_window_judgement((select (payload->>'run_id')::uuid from repair_run), '00000000-0000-0000-0000-000000043021', '00000000-0000-0000-0000-000000043003')$$, '42501', 'worker_not_authorized', 'a non-owner Worker is rejected');
select throws_ok($$select public.terminalize_x_demo_fixed_window_judgement((select (payload->>'run_id')::uuid from repair_run), '00000000-0000-0000-0000-000000043021', '00000000-0000-0000-0000-000000043004')$$, '42501', 'worker_not_authorized', 'a Worker without x_sync is rejected');

insert into public.x_collection_batches (id, scheduled_window_key, natural_date, cutoff_at, settlement_deadline_at, status, snapshot_completeness)
values ('00000000-0000-0000-0000-000000043030', '2026-08-18T20:00+08:00', '2026-08-18', '2026-08-18T12:00:00Z', '2026-08-18T14:00:00Z', 'judgement_pending', 'complete');
insert into public.x_daily_judgement_runs (id, batch_id, status, attempt, available_at)
values ('00000000-0000-0000-0000-000000043031', '00000000-0000-0000-0000-000000043030', 'retryable_failed', 2, now());
select throws_ok($$select public.terminalize_x_demo_fixed_window_judgement((select (payload->>'run_id')::uuid from repair_run), '00000000-0000-0000-0000-000000043031', '00000000-0000-0000-0000-000000043002')$$, '22023', 'invalid_x_demo_fixed_window_judgement', 'a judgement from another batch is rejected');
select is((select status from public.x_daily_judgement_runs where id = '00000000-0000-0000-0000-000000043031'), 'retryable_failed', 'a non-Ticket-02R judgement is unchanged');
select throws_ok($$do $block$ begin perform set_config('invest_hub.ticket_02r_demo_run_id', '', true); perform set_config('invest_hub.ticket_02r_judgement_run_id', '', true); update public.x_daily_judgement_runs set status = 'failed' where id = '00000000-0000-0000-0000-000000043031'; end; $block$;$$, '55000', 'invalid_x_daily_judgement_run_transition', 'a non-Ticket-02R attempt-two judgement cannot use the direct transition');
select is((select status from public.x_daily_judgement_runs where id = '00000000-0000-0000-0000-000000043031'), 'retryable_failed', 'the rejected non-Ticket-02R transition leaves state unchanged');

insert into public.x_collection_batches (id, scheduled_window_key, natural_date, cutoff_at, settlement_deadline_at, status, snapshot_completeness)
values ('00000000-0000-0000-0000-000000043040', '2026-08-19T00:00+08:00', '2026-08-18', '2026-08-18T16:00:00Z', '2026-08-18T18:00:00Z', 'judgement_pending', 'complete');
insert into public.x_demo_fixed_window_runs (id, cutoff_at, batch_id, owner_worker_id, status, source_snapshot)
values ('00000000-0000-0000-0000-000000043041', '2026-08-18T16:00:00Z', '00000000-0000-0000-0000-000000043040', '00000000-0000-0000-0000-000000043002', 'partial', '[]');
insert into public.x_daily_judgement_runs (id, batch_id, status, attempt, lease_owner, lease_expires_at, available_at)
values ('00000000-0000-0000-0000-000000043032', '00000000-0000-0000-0000-000000043040', 'leased', 2, '00000000-0000-0000-0000-000000043002', now() + interval '10 minutes', now());
select throws_ok($$select public.terminalize_x_demo_fixed_window_judgement('00000000-0000-0000-0000-000000043041', '00000000-0000-0000-0000-000000043032', '00000000-0000-0000-0000-000000043002')$$, '22023', 'invalid_x_demo_fixed_window_judgement', 'a leased judgement is rejected');

insert into public.x_collection_batches (id, scheduled_window_key, natural_date, cutoff_at, settlement_deadline_at, status, snapshot_completeness)
values ('00000000-0000-0000-0000-000000043060', '2026-08-19T12:00+08:00', '2026-08-19', '2026-08-19T04:00:00Z', '2026-08-19T06:00:00Z', 'judgement_pending', 'complete');
insert into public.x_demo_fixed_window_runs (id, cutoff_at, batch_id, owner_worker_id, status, source_snapshot)
values ('00000000-0000-0000-0000-000000043061', '2026-08-19T04:00:00Z', '00000000-0000-0000-0000-000000043060', '00000000-0000-0000-0000-000000043002', 'partial', '[]');
insert into public.x_daily_judgement_runs (id, batch_id, status, attempt, available_at)
values ('00000000-0000-0000-0000-000000043034', '00000000-0000-0000-0000-000000043060', 'retryable_failed', 2, now());
select throws_ok($$do $block$ begin perform set_config('invest_hub.ticket_02r_demo_run_id', '', true); perform set_config('invest_hub.ticket_02r_judgement_run_id', '', true); update public.x_daily_judgement_runs set status = 'failed' where id = '00000000-0000-0000-0000-000000043034'; end; $block$;$$, '55000', 'invalid_x_daily_judgement_run_transition', 'a direct attempt-two update remains forbidden without a marker');

select throws_ok($$do $block$ begin perform set_config('invest_hub.ticket_02r_demo_run_id', (select (payload->>'run_id') from repair_run), true); perform set_config('invest_hub.ticket_02r_judgement_run_id', '', true); update public.x_daily_judgement_runs set status = 'failed' where id = '00000000-0000-0000-0000-000000043034'; end; $block$;$$, '55000', 'invalid_x_daily_judgement_run_transition', 'a demo-only marker is insufficient');
select throws_ok($$do $block$ begin perform set_config('invest_hub.ticket_02r_demo_run_id', '00000000-0000-0000-0000-000000043099', true); perform set_config('invest_hub.ticket_02r_judgement_run_id', '00000000-0000-0000-0000-000000043034', true); update public.x_daily_judgement_runs set status = 'failed' where id = '00000000-0000-0000-0000-000000043034'; end; $block$;$$, '55000', 'invalid_x_daily_judgement_run_transition', 'a judgement-only marker is insufficient');
select throws_ok($$do $block$ begin perform set_config('invest_hub.ticket_02r_demo_run_id', '00000000-0000-0000-0000-000000043099', true); perform set_config('invest_hub.ticket_02r_judgement_run_id', '00000000-0000-0000-0000-000000043034', true); update public.x_daily_judgement_runs set status = 'failed' where id = '00000000-0000-0000-0000-000000043034'; end; $block$;$$, '55000', 'invalid_x_daily_judgement_run_transition', 'an unknown demo marker is rejected');
select throws_ok($$do $block$ begin perform set_config('invest_hub.ticket_02r_demo_run_id', (select (payload->>'run_id') from repair_run), true); perform set_config('invest_hub.ticket_02r_judgement_run_id', '00000000-0000-0000-0000-000000043099', true); update public.x_daily_judgement_runs set status = 'failed' where id = '00000000-0000-0000-0000-000000043034'; end; $block$;$$, '55000', 'invalid_x_daily_judgement_run_transition', 'an unknown judgement marker is rejected');
select throws_ok($$do $block$ begin perform set_config('invest_hub.ticket_02r_demo_run_id', '00000000-0000-0000-0000-000000043061', true); perform set_config('invest_hub.ticket_02r_judgement_run_id', '00000000-0000-0000-0000-000000043034', true); update public.x_daily_judgement_runs set status = 'failed', failure_class = 'provider_error' where id = '00000000-0000-0000-0000-000000043034'; end; $block$;$$, '55000', 'invalid_x_daily_judgement_run_transition', 'the scoped exception cannot change failure class');
select throws_ok($$do $block$ begin perform set_config('invest_hub.ticket_02r_demo_run_id', '00000000-0000-0000-0000-000000043061', true); perform set_config('invest_hub.ticket_02r_judgement_run_id', '00000000-0000-0000-0000-000000043034', true); update public.x_daily_judgement_runs set status = 'failed', available_at = now() + interval '1 hour' where id = '00000000-0000-0000-0000-000000043034'; end; $block$;$$, '55000', 'invalid_x_daily_judgement_run_transition', 'the scoped exception cannot change availability');

insert into public.x_collection_batches (id, scheduled_window_key, natural_date, cutoff_at, settlement_deadline_at, status, snapshot_completeness)
values ('00000000-0000-0000-0000-000000043050', '2026-08-19T08:00+08:00', '2026-08-19', '2026-08-19T00:00:00Z', '2026-08-19T02:00:00Z', 'succeeded', 'complete');
insert into public.x_daily_judgement_versions (batch_id, revision, coverage_status, input_snapshot, output, provider, prompt_version, schema_version)
values ('00000000-0000-0000-0000-000000043050', 1, 'no_new_information', '{"sources":[]}', '{"security_industry_viewpoints":[],"market_structure_viewpoints":[],"strategy_mindset_viewpoints":[],"uncertainties":[]}', 'mock', 'ticket-02r-repair', 'v4-x-cross-blogger');
insert into public.x_daily_judgement_runs (id, batch_id, status, attempt, run_kind, available_at)
values ('00000000-0000-0000-0000-000000043039', '00000000-0000-0000-0000-000000043050', 'retryable_failed', 0, 'regeneration', now());
select lives_ok($$update public.x_daily_judgement_runs set status = 'failed', failure_class = 'schema_error' where id = '00000000-0000-0000-0000-000000043039'$$, 'the pre-existing regeneration no-new exception remains valid');

select * from finish();
rollback;
