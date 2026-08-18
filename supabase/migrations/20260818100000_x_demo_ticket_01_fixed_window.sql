-- Ticket 01 keeps source configuration independent from Worker availability and
-- adds one explicit fixed-window task contract.  Legacy tables and facts remain
-- readable; this path does not use the continuous-waterline scheduler.

alter table public.x_source_activations
  alter column worker_id drop not null;

create table public.x_demo_fixed_window_tasks (
  task_id uuid primary key references public.sync_tasks(id) on delete cascade,
  source_id uuid not null references public.sources(id) on delete cascade,
  cutoff_at timestamptz not null,
  natural_date date not null,
  start_at timestamptz not null,
  end_at timestamptz not null,
  created_at timestamptz not null default timezone('utc', now()),
  unique (source_id, cutoff_at),
  check (start_at < end_at),
  check (end_at = cutoff_at)
);

alter table public.x_demo_fixed_window_tasks enable row level security;
create policy x_demo_fixed_window_tasks_admin_read on public.x_demo_fixed_window_tasks
for select to authenticated using (public.is_admin());
revoke all on table public.x_demo_fixed_window_tasks from public, anon, authenticated;
grant select on public.x_demo_fixed_window_tasks to service_role;

create or replace function public.create_x_source(
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
  v_initial_end_at timestamptz;
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

  v_initial_end_at := date_trunc('day', timezone('Asia/Shanghai', now())) at time zone 'Asia/Shanghai';
  insert into public.sources (source_key, source_type, display_name, parameter_version, enabled, authorized_worker_id, created_by)
  values (p_source_key, 'x', p_display_name, p_parameter_version, true, null, p_actor_id)
  returning * into v_source;
  insert into public.x_source_profiles (source_id, requested_handle, display_name, resolution_status, enabled)
  values (v_source.id, p_requested_handle, p_display_name, 'pending', true);
  insert into public.x_source_activations (source_id, worker_id, stage, initial_end_at)
  values (v_source.id, null, 'pending_identity', v_initial_end_at);
  return jsonb_build_object(
    'id', v_source.id::text, 'source_key', v_source.source_key, 'source_type', 'x',
    'display_name', v_source.display_name, 'parameter_version', v_source.parameter_version,
    'enabled', v_source.enabled, 'resolution_status', 'pending'
  );
end;
$$;

create or replace function public.claim_next_x_activation(p_worker_id uuid, p_now timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_activation public.x_source_activations%rowtype;
  v_profile public.x_source_profiles%rowtype;
  v_source public.sources%rowtype;
  v_local_created timestamp;
  v_initial_end_at timestamptz;
begin
  if not exists (
    select 1 from public.workers
    where id = p_worker_id and status = 'online'
      and last_heartbeat_at >= p_now - interval '2 minutes'
      and capabilities @> array['x_sync']::text[]
  ) then
    raise exception 'worker_not_authorized' using errcode = '42501';
  end if;

  select activation.* into v_activation
  from public.x_source_activations activation
  join public.sources source on source.id = activation.source_id
  where activation.stage in ('pending_identity', 'retryable_failed')
    and source.source_type = 'x' and source.enabled
    and (activation.worker_id = p_worker_id or activation.worker_id is null)
  order by activation.requested_at, activation.source_id
  for update of activation skip locked limit 1;
  if not found then
    select source.* into v_source
    from public.sources source
    join public.x_source_profiles profile on profile.source_id = source.id
    left join public.x_source_activations activation on activation.source_id = source.id
    where source.source_type = 'x' and source.enabled and source.authorized_worker_id is null
      and profile.enabled and profile.resolution_status = 'pending' and activation.source_id is null
    order by source.created_at, source.id
    for update of source, profile skip locked
    limit 1;
    if not found then return null; end if;
    select * into v_profile from public.x_source_profiles where source_id = v_source.id for update;
    v_local_created := timezone('Asia/Shanghai', v_source.created_at);
    v_initial_end_at := date_trunc('day', v_local_created) at time zone 'Asia/Shanghai';
    insert into public.x_source_activations (source_id, worker_id, stage, initial_end_at)
    values (v_source.id, p_worker_id, 'pending_identity', v_initial_end_at)
    returning * into v_activation;
  end if;

  if v_source.id is null then
    select * into v_source from public.sources where id = v_activation.source_id and enabled for update;
    select * into v_profile from public.x_source_profiles where source_id = v_activation.source_id and enabled for update;
  end if;
  if not found or v_source.source_type <> 'x' then
    raise exception 'worker_not_authorized' using errcode = '42501';
  end if;
  if v_source.authorized_worker_id is not null and v_source.authorized_worker_id <> p_worker_id then
    raise exception 'worker_not_authorized' using errcode = '42501';
  end if;
  update public.sources set authorized_worker_id = p_worker_id where id = v_source.id;
  update public.x_source_activations set worker_id = p_worker_id where source_id = v_source.id;

  return jsonb_build_object(
    'source_id', v_source.id::text,
    'requested_handle', v_profile.requested_handle,
    'parameter_version', v_source.parameter_version,
    'initial_end_at', v_activation.initial_end_at,
    'idempotent', v_profile.resolution_status = 'resolved'
  );
end;
$$;

create or replace function public.x_demo_fixed_window_bounds(p_cutoff_at timestamptz)
returns jsonb
language plpgsql
immutable
set search_path = public
as $$
declare
  v_local timestamp;
  v_start_local timestamp;
  v_cutoff_key text;
  v_previous_time time;
  v_natural_date date;
begin
  if p_cutoff_at is null then
    raise exception 'invalid_x_demo_cutoff' using errcode = '22023';
  end if;
  v_local := p_cutoff_at at time zone 'Asia/Shanghai';
  if extract(second from v_local) <> 0 or to_char(v_local, 'HH24:MI') not in ('00:00', '08:00', '12:00', '16:00', '20:00') then
    raise exception 'invalid_x_demo_cutoff' using errcode = '22023';
  end if;
  v_cutoff_key := to_char(v_local, 'YYYY-MM-DD"T"HH24:MI') || '+08:00';
  v_previous_time := case to_char(v_local, 'HH24:MI')
    when '00:00' then time '20:00'
    when '08:00' then time '00:00'
    when '12:00' then time '08:00'
    when '16:00' then time '12:00'
    else time '16:00'
  end;
  v_natural_date := case when v_previous_time = time '20:00' then v_local::date - 1 else v_local::date end;
  v_start_local := v_natural_date + v_previous_time;
  return jsonb_build_object(
    'start_at', v_start_local at time zone 'Asia/Shanghai',
    'end_at', p_cutoff_at,
    'scheduled_window_key', v_cutoff_key,
    'natural_date', v_natural_date
  );
end;
$$;

create or replace function public.create_x_demo_fixed_window_task(
  p_source_id uuid,
  p_cutoff_at timestamptz,
  p_requested_by uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_source public.sources%rowtype;
  v_profile public.x_source_profiles%rowtype;
  v_bounds jsonb;
  v_existing public.x_demo_fixed_window_tasks%rowtype;
  v_task public.sync_tasks%rowtype;
begin
  if not exists (select 1 from public.profiles where id = p_requested_by and role = 'admin') then
    raise exception 'actor_not_authorized' using errcode = '42501';
  end if;
  select * into v_source from public.sources where id = p_source_id and source_type = 'x' and enabled for update;
  if not found then raise exception 'source_not_found' using errcode = '22023'; end if;
  select * into v_profile from public.x_source_profiles where source_id = p_source_id and enabled for update;
  if not found or v_profile.resolution_status <> 'resolved' or v_profile.account_id is null then
    raise exception 'x_source_unresolved' using errcode = '22023';
  end if;
  v_bounds := public.x_demo_fixed_window_bounds(p_cutoff_at);

  select * into v_existing from public.x_demo_fixed_window_tasks
  where source_id = p_source_id and cutoff_at = p_cutoff_at for update;
  if found then
    select * into v_task from public.sync_tasks where id = v_existing.task_id;
    return to_jsonb(v_task) || jsonb_build_object('idempotent', true, 'demo_fixed_window', v_bounds);
  end if;

  insert into public.sync_tasks (
    task_type, source_id, status, parameter_version, requested_by, collection_scope,
    capture_range, author_profile_snapshot, x_source_snapshot
  ) values (
    'x_sync', p_source_id, 'queued', v_source.parameter_version, p_requested_by,
    '{"mode":"window"}'::jsonb,
    jsonb_build_object(
      'mode', 'window', 'trigger', 'scheduled', 'timezone', 'Asia/Shanghai',
      'start_at', v_bounds->'start_at', 'end_at', v_bounds->'end_at',
      'scheduled_window_key', v_bounds->'scheduled_window_key',
      'overlap_start_at', v_bounds->'start_at'
    ),
    '[]'::jsonb,
    jsonb_build_object('source_type', 'x', 'account_id', v_profile.account_id,
      'display_name', v_profile.display_name, 'parameter_version', v_source.parameter_version)
  ) returning * into v_task;
  insert into public.sync_task_capture_progress (task_id, source_id, capture_range)
  values (v_task.id, p_source_id, v_task.capture_range);
  insert into public.x_demo_fixed_window_tasks (task_id, source_id, cutoff_at, natural_date, start_at, end_at)
  values (v_task.id, p_source_id, p_cutoff_at, (v_bounds->>'natural_date')::date,
    (v_bounds->>'start_at')::timestamptz, p_cutoff_at);
  return to_jsonb(v_task) || jsonb_build_object('idempotent', false, 'demo_fixed_window', v_bounds);
end;
$$;

revoke all on function public.x_demo_fixed_window_bounds(timestamptz) from public, anon, authenticated;
revoke all on function public.create_x_demo_fixed_window_task(uuid, timestamptz, uuid) from public, anon, authenticated;
grant execute on function public.x_demo_fixed_window_bounds(timestamptz), public.create_x_demo_fixed_window_task(uuid, timestamptz, uuid) to service_role;
