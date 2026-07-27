-- New X sources are only useful when the resident, authenticated X Worker can
-- immediately own their activation.  Keep that binding and the first fixed
-- window atomic with source creation.

alter table public.workers
  add column capabilities text[] not null default '{}'::text[]
  check (capabilities <@ array['discord_sync', 'x_sync']::text[]);

create table public.x_source_activations (
  source_id uuid primary key references public.sources(id) on delete cascade,
  worker_id uuid not null references public.workers(id),
  stage text not null check (stage in ('pending_identity', 'pending_initialization', 'collecting', 'completed', 'retryable_failed')),
  requested_at timestamptz not null default timezone('utc', now()),
  initial_end_at timestamptz not null,
  initial_task_id uuid references public.sync_tasks(id),
  last_error_code text,
  completed_at timestamptz
);

alter table public.x_source_activations enable row level security;

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
  v_worker_id uuid;
  v_worker_count integer;
  v_local_now timestamp;
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

  select count(*), min(id::text)::uuid into v_worker_count, v_worker_id
  from public.workers
  where status = 'online'
    and last_heartbeat_at >= timezone('utc', now()) - interval '2 minutes'
    and capabilities @> array['x_sync']::text[];
  if v_worker_count <> 1 then
    raise exception 'x_worker_unavailable' using errcode = 'P0001';
  end if;

  v_local_now := timezone('Asia/Shanghai', now());
  v_initial_end_at := (
    date_trunc('day', v_local_now) + case
      when v_local_now::time >= time '20:00' then time '20:00'
      when v_local_now::time >= time '16:00' then time '16:00'
      when v_local_now::time >= time '12:00' then time '12:00'
      when v_local_now::time >= time '08:00' then time '08:00'
      else time '00:00'
    end
  ) at time zone 'Asia/Shanghai';

  insert into public.sources (source_key, source_type, display_name, parameter_version, enabled, authorized_worker_id, created_by)
  values (p_source_key, 'x', p_display_name, p_parameter_version, true, v_worker_id, p_actor_id)
  returning * into v_source;
  insert into public.x_source_profiles (source_id, requested_handle, display_name, resolution_status, enabled)
  values (v_source.id, p_requested_handle, p_display_name, 'pending', true);
  insert into public.x_source_activations (source_id, worker_id, stage, initial_end_at)
  values (v_source.id, v_worker_id, 'pending_identity', v_initial_end_at);
  return jsonb_build_object(
    'id', v_source.id::text, 'source_key', v_source.source_key, 'source_type', 'x',
    'display_name', v_source.display_name, 'parameter_version', v_source.parameter_version,
    'enabled', v_source.enabled, 'resolution_status', 'pending'
  );
end;
$$;

create function public.claim_next_x_activation(p_worker_id uuid, p_now timestamptz)
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
  select * into v_activation from public.x_source_activations
  where worker_id = p_worker_id and stage in ('pending_identity', 'retryable_failed')
  order by requested_at, source_id for update skip locked limit 1;
  if found then
    select * into v_source from public.sources where id = v_activation.source_id and enabled for update;
    if not found or v_source.authorized_worker_id <> p_worker_id then
      raise exception 'worker_not_authorized' using errcode = '42501';
    end if;
    select * into v_profile from public.x_source_profiles where source_id = v_activation.source_id and enabled for update;
    if not found then raise exception 'worker_not_authorized' using errcode = '42501'; end if;
  else
    -- Adopt sources created before this release only when they are still
    -- pending and unbound.  Existing explicit bindings are never overridden.
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
    if not found then raise exception 'worker_not_authorized' using errcode = '42501'; end if;
    v_local_created := timezone('Asia/Shanghai', v_source.created_at);
    v_initial_end_at := (
      date_trunc('day', v_local_created) + case
        when v_local_created::time >= time '20:00' then time '20:00'
        when v_local_created::time >= time '16:00' then time '16:00'
        when v_local_created::time >= time '12:00' then time '12:00'
        when v_local_created::time >= time '08:00' then time '08:00'
        else time '00:00'
      end
    ) at time zone 'Asia/Shanghai';
    update public.sources set authorized_worker_id = p_worker_id where id = v_source.id;
    v_source.authorized_worker_id := p_worker_id;
    insert into public.x_source_activations (source_id, worker_id, stage, initial_end_at)
    values (v_source.id, p_worker_id, 'pending_identity', v_initial_end_at)
    returning * into v_activation;
  end if;
  if v_source.authorized_worker_id <> p_worker_id then
    raise exception 'worker_not_authorized' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'source_id', v_activation.source_id::text,
    'requested_handle', v_profile.requested_handle,
    'parameter_version', v_source.parameter_version,
    'initial_end_at', v_activation.initial_end_at,
    'idempotent', v_profile.resolution_status = 'resolved'
  );
end;
$$;

create function public.initialize_x_source_activation(p_source_id uuid, p_worker_id uuid, p_now timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_activation public.x_source_activations%rowtype;
  v_source public.sources%rowtype;
  v_profile public.x_source_profiles%rowtype;
  v_boundary timestamptz;
  v_task jsonb;
begin
  if not exists (
    select 1 from public.workers
    where id = p_worker_id and status = 'online'
      and last_heartbeat_at >= p_now - interval '2 minutes'
      and capabilities @> array['x_sync']::text[]
  ) then raise exception 'worker_not_authorized' using errcode = '42501'; end if;
  select * into v_activation from public.x_source_activations where source_id = p_source_id for update;
  if not found or v_activation.worker_id <> p_worker_id then raise exception 'worker_not_authorized' using errcode = '42501'; end if;
  if v_activation.initial_task_id is not null then
    return jsonb_build_object('task_id', v_activation.initial_task_id::text, 'source_id', p_source_id::text, 'initial_end_at', v_activation.initial_end_at, 'idempotent', true);
  end if;
  select * into v_source from public.sources where id = p_source_id and enabled for update;
  select * into v_profile from public.x_source_profiles where source_id = p_source_id and enabled for update;
  if not found or v_source.authorized_worker_id <> p_worker_id then raise exception 'worker_not_authorized' using errcode = '42501'; end if;
  if v_profile.resolution_status <> 'resolved' then raise exception 'x_source_unresolved' using errcode = '22023'; end if;
  v_boundary := date_trunc('day', v_activation.initial_end_at at time zone 'Asia/Shanghai') at time zone 'Asia/Shanghai';
  insert into public.source_collection_coverage (source_id, coverage_start_at, coverage_through_at, initialized_by)
  values (p_source_id, v_boundary, v_boundary, null)
  on conflict (source_id) do nothing;
  -- A source added before the first same-day cutoff has no completed interval
  -- to capture yet.  Initialize its watermark now; the regular 08:00 tick
  -- will create the first non-empty task.
  if v_activation.initial_end_at <= v_boundary then
    update public.x_source_activations
    set stage = 'collecting', last_error_code = null
    where source_id = p_source_id;
    return jsonb_build_object('task_id', null, 'source_id', p_source_id::text, 'initial_end_at', v_activation.initial_end_at, 'idempotent', false);
  end if;
  v_task := public.create_windowed_x_sync_task(
    p_source_id, v_source.parameter_version, null, 'scheduled', v_activation.initial_end_at,
    to_char(v_activation.initial_end_at at time zone 'Asia/Shanghai', 'YYYY-MM-DD"T"HH24:MI') || '+08:00'
  );
  update public.x_source_activations
  set stage = 'collecting', initial_task_id = (v_task->>'id')::uuid, last_error_code = null
  where source_id = p_source_id;
  return jsonb_build_object('task_id', v_task->>'id', 'source_id', p_source_id::text, 'initial_end_at', v_activation.initial_end_at, 'idempotent', coalesce((v_task->>'idempotent')::boolean, false));
end;
$$;

create function public.mark_x_source_activation_completed()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.status = 'succeeded' and old.status <> 'succeeded' then
    update public.x_source_activations
    set stage = 'completed', completed_at = timezone('utc', now()), last_error_code = null
    where initial_task_id = new.id and stage = 'collecting';
  end if;
  return new;
end;
$$;

create trigger x_source_activation_completed
after update of status on public.sync_tasks
for each row execute function public.mark_x_source_activation_completed();

revoke all on table public.x_source_activations from public, anon, authenticated;
grant select, insert, update, delete on table public.x_source_activations to service_role;
revoke all on function public.claim_next_x_activation(uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.initialize_x_source_activation(uuid, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.claim_next_x_activation(uuid, timestamptz) to service_role;
grant execute on function public.initialize_x_source_activation(uuid, uuid, timestamptz) to service_role;
