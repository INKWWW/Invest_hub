-- A failed recovery run is immutable audit history.  This scoped entry point
-- creates a new run for one already-elapsed schedule cutoff instead of
-- resetting attempts or editing the failed run/batch.
create function public.create_x_manual_recovery_run_at(
  p_requested_by uuid,
  p_target_cutoff_at timestamptz,
  p_now timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_local_cutoff timestamp;
  v_run public.x_manual_recovery_runs%rowtype;
begin
  if p_requested_by is null or p_target_cutoff_at is null or p_now is null
     or not exists (select 1 from public.profiles where id = p_requested_by and role = 'admin') then
    raise exception 'actor_not_authorized' using errcode = '42501';
  end if;

  v_local_cutoff := p_target_cutoff_at at time zone 'Asia/Shanghai';
  if p_target_cutoff_at > p_now
     or date_trunc('minute', v_local_cutoff) <> v_local_cutoff
     or extract(hour from v_local_cutoff) not in (0, 8, 12, 16, 20) then
    raise exception 'invalid_manual_x_recovery_cutoff' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_target_cutoff_at::text, 24002));
  select * into v_run
  from public.x_manual_recovery_runs
  where target_cutoff_at = p_target_cutoff_at
    and status in ('queued', 'collecting', 'summarizing')
  for update;
  if found then
    return jsonb_build_object(
      'id', v_run.id::text,
      'status', v_run.status,
      'target_cutoff_at', v_run.target_cutoff_at,
      'idempotent', true
    );
  end if;

  insert into public.x_manual_recovery_runs (requested_by, target_cutoff_at)
  values (p_requested_by, p_target_cutoff_at)
  returning * into v_run;

  insert into public.x_manual_recovery_run_sources (run_id, source_id, source_display_name)
  select v_run.id, source.id, profile.display_name
  from public.sources source
  join public.x_source_profiles profile
    on profile.source_id = source.id
   and profile.enabled
   and profile.resolution_status = 'resolved'
  where source.source_type = 'x'
    and source.enabled;

  if not exists (select 1 from public.x_manual_recovery_run_sources where run_id = v_run.id) then
    raise exception 'manual_x_recovery_no_sources' using errcode = '22023';
  end if;

  return jsonb_build_object(
    'id', v_run.id::text,
    'status', v_run.status,
    'target_cutoff_at', v_run.target_cutoff_at,
    'idempotent', false
  );
end;
$$;

revoke all on function public.create_x_manual_recovery_run_at(uuid, timestamptz, timestamptz)
  from public, anon, authenticated;
grant execute on function public.create_x_manual_recovery_run_at(uuid, timestamptz, timestamptz)
  to service_role;
