-- Administrator-only source registration and initial coverage for X.  These
-- operations never store a browser URL/profile and never invoke collection.

create function public.create_x_source(
  p_source_key text,
  p_display_name text,
  p_requested_handle text,
  p_parameter_version text,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_source public.sources%rowtype;
begin
  if not exists (select 1 from public.profiles where id = p_actor_id and role = 'admin') then
    raise exception 'actor_not_authorized' using errcode = '42501';
  end if;
  if p_source_key is null or length(btrim(p_source_key)) = 0
     or p_display_name is null or length(btrim(p_display_name)) = 0
     or p_requested_handle is null or length(btrim(p_requested_handle)) = 0
     or p_parameter_version is null or length(btrim(p_parameter_version)) = 0 then
    raise exception 'invalid_x_source' using errcode = '22023';
  end if;
  insert into public.sources (source_key, source_type, display_name, parameter_version, enabled, created_by)
  values (p_source_key, 'x', p_display_name, p_parameter_version, true, p_actor_id)
  returning * into v_source;
  insert into public.x_source_profiles (source_id, requested_handle, display_name, resolution_status, enabled)
  values (v_source.id, p_requested_handle, p_display_name, 'pending', true);
  return jsonb_build_object(
    'id', v_source.id::text, 'source_key', v_source.source_key, 'source_type', 'x',
    'display_name', v_source.display_name, 'parameter_version', v_source.parameter_version,
    'enabled', v_source.enabled, 'resolution_status', 'pending'
  );
end;
$$;

create function public.initialize_x_collection_coverage(
  p_source_id uuid,
  p_actor_id uuid,
  p_boundary timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_coverage public.source_collection_coverage%rowtype;
begin
  if not exists (select 1 from public.profiles where id = p_actor_id and role = 'admin') then
    raise exception 'actor_not_authorized' using errcode = '42501';
  end if;
  if p_boundary is null or to_char(p_boundary at time zone 'Asia/Shanghai', 'HH24:MI:SS') not in ('00:00:00', '08:00:00', '12:00:00', '16:00:00', '20:00:00') then
    raise exception 'invalid_coverage_boundary' using errcode = '22023';
  end if;
  if not exists (select 1 from public.sources where id = p_source_id and source_type = 'x') then
    raise exception 'source_not_found' using errcode = '22023';
  end if;
  select * into v_coverage from public.source_collection_coverage where source_id = p_source_id for update;
  if found then
    if v_coverage.coverage_start_at = p_boundary and v_coverage.coverage_through_at = p_boundary and v_coverage.last_completed_task_id is null then
      return jsonb_build_object('source_id', p_source_id::text, 'coverage_start_at', v_coverage.coverage_start_at, 'coverage_through_at', v_coverage.coverage_through_at, 'idempotent', true);
    end if;
    raise exception 'coverage_already_initialized' using errcode = '23505';
  end if;
  insert into public.source_collection_coverage (source_id, coverage_start_at, coverage_through_at, initialized_by)
  values (p_source_id, p_boundary, p_boundary, p_actor_id)
  returning * into v_coverage;
  return jsonb_build_object('source_id', p_source_id::text, 'coverage_start_at', v_coverage.coverage_start_at, 'coverage_through_at', v_coverage.coverage_through_at, 'idempotent', false);
end;
$$;

revoke all on function public.create_x_source(text, text, text, text, uuid) from public, anon, authenticated;
revoke all on function public.initialize_x_collection_coverage(uuid, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.create_x_source(text, text, text, text, uuid) to service_role;
grant execute on function public.initialize_x_collection_coverage(uuid, uuid, timestamptz) to service_role;
