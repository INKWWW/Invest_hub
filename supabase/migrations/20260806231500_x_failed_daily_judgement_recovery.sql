-- Queue a fresh audited judgement run against the exact frozen input of a
-- terminally failed initial batch. This is deliberately separate from normal
-- regeneration, which requires an existing successful immutable version.
create function public.recover_failed_x_daily_judgement(
  p_batch_id uuid,
  p_requested_by uuid
)
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
    raise exception 'invalid_x_failed_judgement_recovery_actor' using errcode = '22023';
  end if;

  if not exists (
    select 1 from public.profiles where id = p_requested_by and role = 'admin'
  ) then
    raise exception 'actor_not_authorized' using errcode = '42501';
  end if;

  select * into v_batch
  from public.x_collection_batches
  where id = p_batch_id
  for update;

  if not found or v_batch.status <> 'judgement_failed' then
    raise exception 'x_failed_judgement_recovery_not_available' using errcode = '22023';
  end if;

  if exists (
    select 1 from public.x_daily_judgement_versions where batch_id = v_batch.id
  ) then
    raise exception 'x_failed_judgement_recovery_requires_zero_versions' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.x_daily_judgement_runs
    where batch_id = v_batch.id and status = 'failed'
  ) then
    raise exception 'x_failed_judgement_recovery_requires_failed_run' using errcode = '22023';
  end if;

  if not public.x_daily_judgement_batch_has_provider_input(v_batch.id) then
    raise exception 'x_daily_judgement_no_provider_input' using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.x_daily_judgement_runs
    where batch_id = v_batch.id
      and status in ('queued', 'leased', 'running', 'retryable_failed')
  ) then
    raise exception 'x_failed_judgement_recovery_active' using errcode = 'PT409';
  end if;

  insert into public.x_daily_judgement_runs (
    batch_id, status, attempt, run_kind, requested_by
  ) values (
    v_batch.id, 'queued', 0, 'regeneration', p_requested_by
  ) returning * into v_run;

  return jsonb_build_object(
    'run_id', v_run.id::text,
    'status', v_run.status,
    'attempt', v_run.attempt
  );
end;
$$;

revoke all on function public.recover_failed_x_daily_judgement(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.recover_failed_x_daily_judgement(uuid, uuid)
  to service_role;

