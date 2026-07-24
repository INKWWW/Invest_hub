-- A source identity may only be activated by the one Worker explicitly bound
-- to it.  This does not collect X content or initialize collection coverage.

create function public.resolve_x_source_identity(
  p_source_id uuid,
  p_worker_id uuid,
  p_parameter_version text,
  p_account_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_source public.sources%rowtype;
  v_profile public.x_source_profiles%rowtype;
  v_normalized_account text := p_account_id;
begin
  select * into v_source
  from public.sources
  where id = p_source_id and source_type = 'x'
  for update;
  if not found then
    raise exception 'source_not_found' using errcode = '22023';
  end if;

  select * into v_profile
  from public.x_source_profiles
  where source_id = p_source_id
  for update;
  if not found then
    raise exception 'source_not_found' using errcode = '22023';
  end if;

  if v_source.authorized_worker_id is distinct from p_worker_id then
    raise exception 'worker_not_authorized' using errcode = '42501';
  end if;
  if p_parameter_version is null or p_parameter_version <> v_source.parameter_version then
    raise exception 'source_parameter_version_mismatch' using errcode = '22023';
  end if;
  if v_normalized_account is null or v_normalized_account !~ '^[a-z0-9_]{1,15}$' then
    raise exception 'invalid_x_identity' using errcode = '22023';
  end if;

  if v_profile.resolution_status = 'resolved' then
    if v_profile.account_id = v_normalized_account then
      return jsonb_build_object(
        'source_id', p_source_id::text,
        'account_id', v_profile.account_id,
        'resolution_status', 'resolved',
        'parameter_version', v_source.parameter_version,
        'idempotent', true
      );
    end if;
    raise exception 'x_identity_conflict' using errcode = '22023';
  end if;

  if v_profile.resolution_status <> 'pending'
     or exists (
       select 1
       from public.source_collection_coverage
       where source_id = p_source_id
       for update
     )
     or exists (
       select 1
       from public.sync_tasks task
       where task.source_id = p_source_id
         and task.task_type = 'x_sync'
         and task.status in ('queued', 'leased', 'running', 'retryable_failed')
       for update
     ) then
    raise exception 'x_identity_activation_blocked' using errcode = '23505';
  end if;

  update public.x_source_profiles
  set account_id = v_normalized_account,
      resolution_status = 'resolved'
  where source_id = p_source_id
    and resolution_status = 'pending';

  return jsonb_build_object(
    'source_id', p_source_id::text,
    'account_id', v_normalized_account,
    'resolution_status', 'resolved',
    'parameter_version', v_source.parameter_version,
    'idempotent', false
  );
end;
$$;

revoke all on function public.resolve_x_source_identity(uuid, uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.resolve_x_source_identity(uuid, uuid, text, text) to service_role;
