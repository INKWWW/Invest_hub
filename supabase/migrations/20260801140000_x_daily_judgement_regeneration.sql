-- Explicit administrator regeneration is a new independent judgement run. It
-- never changes the frozen collection batch, its source coverage, or a prior
-- immutable judgement version.

alter table public.x_daily_judgement_runs
  add column run_kind text not null default 'initial'
    check (run_kind in ('initial', 'regeneration')),
  add column requested_by uuid;

update public.x_daily_judgement_runs
set run_kind = 'initial', requested_by = null;

create function public.regenerate_x_daily_judgement(p_batch_id uuid, p_requested_by uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_batch public.x_collection_batches%rowtype;
  v_run public.x_daily_judgement_runs%rowtype;
begin
  if p_requested_by is null or not exists (
    select 1 from public.profiles where id = p_requested_by
  ) then
    raise exception 'invalid_x_daily_judgement_regeneration_actor' using errcode = '22023';
  end if;

  select * into v_batch
  from public.x_collection_batches
  where id = p_batch_id
  for update;

  if not found or v_batch.status <> 'succeeded' then
    raise exception 'x_daily_judgement_regeneration_not_available' using errcode = '22023';
  end if;

  if not exists (
    select 1 from public.x_daily_judgement_versions where batch_id = v_batch.id
  ) then
    raise exception 'x_daily_judgement_regeneration_requires_successful_version' using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.x_daily_judgement_runs
    where batch_id = v_batch.id
      and status in ('queued', 'leased', 'running', 'retryable_failed')
  ) then
    raise exception 'x_daily_judgement_regeneration_active' using errcode = 'PT409';
  end if;

  insert into public.x_daily_judgement_runs (batch_id, status, attempt, run_kind, requested_by)
  values (v_batch.id, 'queued', 0, 'regeneration', p_requested_by)
  returning * into v_run;

  return jsonb_build_object('run_id', v_run.id::text, 'status', v_run.status, 'attempt', v_run.attempt);
end;
$$;

revoke all on function public.regenerate_x_daily_judgement(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.regenerate_x_daily_judgement(uuid, uuid)
  to service_role;
