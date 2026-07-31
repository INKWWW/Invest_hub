begin;

select plan(3);

insert into public.workers (id, name, device_secret_hash, status)
values ('00000000-0000-0000-0000-000000026001', 'completion-lease-worker', 'completion-lease-worker-hash', 'online');
insert into public.x_collection_batches (id, scheduled_window_key, natural_date, cutoff_at, settlement_deadline_at, status)
values ('00000000-0000-0000-0000-000000026002', '2026-07-29T08:00+08:00', '2026-07-29', '2026-07-29T00:00:00Z', '2026-07-29T02:00:00Z', 'judgement_pending');
insert into public.x_daily_judgement_runs (id, batch_id, status, attempt, lease_owner, lease_expires_at, available_at)
values ('00000000-0000-0000-0000-000000026003', '00000000-0000-0000-0000-000000026002', 'leased', 1,
  '00000000-0000-0000-0000-000000026001', timezone('utc', now()) + interval '10 minutes', timezone('utc', now()));

select throws_ok(
  $$select public.complete_x_daily_judgement('00000000-0000-0000-0000-000000026003', 1, '00000000-0000-0000-0000-000000026001',
    '{"schema_version":"v2-x-cross-blogger","provider":"codex_cli","model_reported":"file:///private/worker/output.json","prompt_version":"v2-x-cross-blogger-1","stock_viewpoints":[],"market_industry_viewpoints":[],"uncertainties":[]}'::jsonb)$$,
  '22023', 'invalid_x_daily_judgement_completion', 'direct completion RPC rejects file URI model metadata'
);

update public.x_daily_judgement_runs
set lease_expires_at = timezone('utc', now()) - interval '1 second'
where id = '00000000-0000-0000-0000-000000026003';
select throws_ok(
  $$select public.complete_x_daily_judgement('00000000-0000-0000-0000-000000026003', 1, '00000000-0000-0000-0000-000000026001',
    '{"schema_version":"v2-x-cross-blogger","provider":"codex_cli","model_reported":null,"prompt_version":"v2-x-cross-blogger-1","stock_viewpoints":[],"market_industry_viewpoints":[],"uncertainties":[]}'::jsonb)$$,
  'PT409', 'lease_mismatch', 'matching owner and attempt cannot complete after the lease expires'
);
select is(
  (select count(*)::text from public.x_daily_judgement_versions where batch_id = '00000000-0000-0000-0000-000000026002'),
  '0',
  'expired lease completion does not persist a judgement version'
);

select * from finish();
rollback;
