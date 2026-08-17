-- Establish one immutable, auditable X collection epoch for the 2026-08-17
-- Demo recovery.  The event is the historical bridge; the coverage row is
-- the live frontier.  Neither old tasks nor old facts are rewritten.

create table public.x_collection_rebaseline_events (
  source_id uuid primary key references public.sources(id) on delete restrict,
  old_coverage_start_at timestamptz not null,
  old_coverage_through_at timestamptz not null,
  old_last_completed_task_id uuid references public.sync_tasks(id) on delete restrict,
  new_baseline_at timestamptz not null,
  reason_code text not null check (reason_code = 'x_collection_demo_rebaseline_2026_08_17'),
  actor_id uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default timezone('utc', now()),
  check (old_coverage_start_at <= old_coverage_through_at),
  check (new_baseline_at = '2026-08-17T00:00:00+08:00'::timestamptz)
);

create or replace function public.prevent_x_collection_rebaseline_event_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception 'x_collection_rebaseline_immutable' using errcode = '55000';
end;
$$;

create trigger x_collection_rebaseline_events_immutable
before update or delete on public.x_collection_rebaseline_events
for each row execute function public.prevent_x_collection_rebaseline_event_mutation();

alter table public.x_collection_rebaseline_events enable row level security;
revoke all on table public.x_collection_rebaseline_events from public, anon, authenticated;
grant select on table public.x_collection_rebaseline_events to authenticated, service_role;
create policy x_collection_rebaseline_events_admin_select
on public.x_collection_rebaseline_events
for select to authenticated, service_role
using (
  exists (
    select 1 from public.profiles
    where profiles.id = auth.uid() and profiles.role = 'admin'
  )
);

create or replace function public.rebaseline_x_collection(
  p_actor_id uuid,
  p_expected_source_count integer,
  p_target_baseline timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_source_id uuid;
  v_source_ids uuid[] := '{}'::uuid[];
  v_coverage public.source_collection_coverage%rowtype;
  v_event public.x_collection_rebaseline_events%rowtype;
  v_old_task public.sync_tasks%rowtype;
  v_old_attempt public.task_attempts%rowtype;
  v_event_projection jsonb;
  v_count integer;
  v_idempotent boolean := true;
  v_results jsonb := '[]'::jsonb;
begin
  if not exists (
    select 1 from public.profiles
    where id = p_actor_id and role = 'admin'
  ) then
    raise exception 'actor_not_authorized' using errcode = '42501';
  end if;
  if p_target_baseline is null
     or p_target_baseline <> '2026-08-17T00:00:00+08:00'::timestamptz then
    raise exception 'x_collection_rebaseline_target' using errcode = 'P0001';
  end if;
  if p_expected_source_count is null or p_expected_source_count < 1 then
    raise exception 'x_collection_rebaseline_source_count' using errcode = 'P0001';
  end if;

  -- Serialize all calls for this fixed release.  Source and profile rows are
  -- then locked together in UUID order, so the expected count, coverage, and
  -- event projection all use one stable source set while profile drift waits.
  perform pg_advisory_xact_lock(hashtextextended('x_collection_rebaseline:2026-08-17', 24005));
  for v_source_id in
    select source.id
    from public.sources source
    join public.x_source_profiles profile
      on profile.source_id = source.id
     and profile.enabled
     and profile.resolution_status = 'resolved'
    where source.source_type = 'x'
      and source.enabled
      and source.archived_at is null
    order by source.id
    for update of source, profile
  loop
    v_source_ids := array_append(v_source_ids, v_source_id);
  end loop;

  v_count := coalesce(cardinality(v_source_ids), 0);
  if v_count <> p_expected_source_count then
    raise exception 'x_collection_rebaseline_source_count' using errcode = 'P0001';
  end if;

  foreach v_source_id in array v_source_ids
  loop
    select * into v_coverage
    from public.source_collection_coverage
    where source_id = v_source_id
    for update;
    if not found then
      raise exception 'x_collection_rebaseline_coverage_missing' using errcode = 'P0001';
    end if;

    -- Claim and reap paths lock the task first and then its attempt rows. Lock
    -- the complete source history in the same order before checking leases so
    -- no old task can be selected in the gap before this epoch is written.
    for v_old_task in
      select task.*
      from public.sync_tasks task
      where task.source_id = v_source_id
      order by task.id
      for update
    loop
      for v_old_attempt in
        select attempt.*
        from public.task_attempts attempt
        where attempt.task_id = v_old_task.id
        order by attempt.id
        for update
      loop
        null;
      end loop;
    end loop;

    select * into v_event
    from public.x_collection_rebaseline_events
    where source_id = v_source_id
    for update;
    if found then
      if v_coverage.coverage_start_at = p_target_baseline
         and v_coverage.coverage_through_at = p_target_baseline
         and v_coverage.last_completed_task_id is null
         and v_event.new_baseline_at = p_target_baseline
         and v_event.reason_code = 'x_collection_demo_rebaseline_2026_08_17' then
        null;
      else
        raise exception 'x_collection_rebaseline_event_conflict' using errcode = 'P0001';
      end if;
    else
      if v_coverage.coverage_through_at > p_target_baseline then
        raise exception 'x_collection_rebaseline_waterline_ahead' using errcode = 'P0001';
      end if;
      if exists (
        select 1 from public.sync_tasks task
        where task.source_id = v_source_id
          and task.status in ('leased', 'running')
          and (task.lease_expires_at is null or task.lease_expires_at > timezone('utc', now()))
      ) or exists (
        select 1 from public.task_attempts attempt
        where attempt.task_id in (select id from public.sync_tasks where source_id = v_source_id)
          and attempt.status in ('leased', 'running')
          and attempt.lease_expires_at > timezone('utc', now())
      ) then
        raise exception 'x_collection_rebaseline_active_lease' using errcode = 'P0001';
      end if;

      insert into public.x_collection_rebaseline_events (
        source_id, old_coverage_start_at, old_coverage_through_at,
        old_last_completed_task_id, new_baseline_at, reason_code, actor_id
      ) values (
        v_source_id, v_coverage.coverage_start_at, v_coverage.coverage_through_at,
        v_coverage.last_completed_task_id, p_target_baseline,
        'x_collection_demo_rebaseline_2026_08_17', p_actor_id
      ) returning * into v_event;

      update public.source_collection_coverage
      set coverage_start_at = p_target_baseline,
          coverage_through_at = p_target_baseline,
          last_completed_task_id = null
      where source_id = v_source_id;
      v_idempotent := false;
    end if;

    v_event_projection := jsonb_build_object(
      'source_id', v_source_id::text,
      'old_coverage_start_at', v_event.old_coverage_start_at,
      'old_coverage_through_at', v_event.old_coverage_through_at,
      'old_last_completed_task_id', v_event.old_last_completed_task_id,
      'new_baseline_at', v_event.new_baseline_at,
      'reason_code', v_event.reason_code,
      'actor_id', v_event.actor_id,
      'created_at', v_event.created_at
    );
    v_results := v_results || jsonb_build_array(v_event_projection);
  end loop;

  return jsonb_build_object(
    'idempotent', v_idempotent,
    'source_count', v_count,
    'target_baseline', p_target_baseline,
    'reason_code', 'x_collection_demo_rebaseline_2026_08_17',
    'sources', v_results
  );
end;
$$;

revoke all on function public.rebaseline_x_collection(uuid, integer, timestamptz) from public, anon, authenticated;
grant execute on function public.rebaseline_x_collection(uuid, integer, timestamptz) to service_role;

-- The old task rows remain audit history.  Once the waterline moves, only an
-- active task whose range starts at the current waterline may be reused by a
-- new scheduler call; an older queued row must not make the new epoch
-- idempotent.
create or replace function public.create_windowed_x_sync_task_without_source_lock(
  p_source_id uuid,
  p_parameter_version text,
  p_requested_by uuid,
  p_trigger text,
  p_end_at timestamptz,
  p_scheduled_window_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_source public.sources%rowtype;
  v_profile public.x_source_profiles%rowtype;
  v_coverage public.source_collection_coverage%rowtype;
  v_existing public.sync_tasks%rowtype;
  v_task public.sync_tasks%rowtype;
  v_overlap_start timestamptz;
  v_day_start timestamptz;
  v_capture_range jsonb;
begin
  if p_trigger not in ('scheduled', 'manual', 'bootstrap') or p_end_at is null then
    raise exception 'invalid_capture_range' using errcode = '22023';
  end if;
  if p_trigger in ('manual', 'bootstrap') and not exists (
    select 1 from public.profiles where id = p_requested_by and role = 'admin'
  ) then
    raise exception 'actor_not_authorized' using errcode = '42501';
  end if;
  if p_trigger = 'scheduled' then
    if p_requested_by is not null
       or p_scheduled_window_key is null
       or p_scheduled_window_key !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T(00:00|08:00|12:00|16:00|20:00)[+]08:00$'
       or p_scheduled_window_key::timestamptz <> p_end_at then
      raise exception 'invalid_capture_range' using errcode = '22023';
    end if;
  elsif p_scheduled_window_key is not null then
    raise exception 'invalid_capture_range' using errcode = '22023';
  end if;

  select * into v_source from public.sources
  where id = p_source_id and source_type = 'x' for update;
  if not found then raise exception 'source_not_found' using errcode = '22023'; end if;
  if not v_source.enabled then raise exception 'source_disabled' using errcode = '22023'; end if;
  if p_parameter_version is null or p_parameter_version <> v_source.parameter_version then
    raise exception 'source_parameter_version_mismatch' using errcode = '22023';
  end if;
  select * into v_profile from public.x_source_profiles
  where source_id = p_source_id and enabled and resolution_status = 'resolved' for update;
  if not found then raise exception 'x_source_unresolved' using errcode = '22023'; end if;
  select * into v_coverage from public.source_collection_coverage
  where source_id = p_source_id for update;
  if not found then raise exception 'coverage_not_initialized' using errcode = '22023'; end if;
  if p_end_at <= v_coverage.coverage_through_at then
    raise exception 'invalid_capture_range' using errcode = '22023';
  end if;

  select * into v_existing from public.sync_tasks
  where source_id = p_source_id
    and task_type = 'x_sync'
    and collection_scope->>'mode' = 'window'
    and status in ('queued', 'leased', 'running', 'retryable_failed')
    and (capture_range->>'start_at')::timestamptz = v_coverage.coverage_through_at
  order by (capture_range->>'end_at')::timestamptz, queued_at, id
  for update limit 1;
  if found then return to_jsonb(v_existing) || jsonb_build_object('idempotent', true); end if;

  v_day_start := date_trunc('day', v_coverage.coverage_through_at at time zone 'Asia/Shanghai') at time zone 'Asia/Shanghai';
  v_overlap_start := greatest(v_coverage.coverage_through_at - interval '30 minutes', v_day_start);
  v_capture_range := jsonb_build_object(
    'mode', 'window', 'trigger', p_trigger, 'timezone', 'Asia/Shanghai',
    'start_at', v_coverage.coverage_through_at, 'end_at', p_end_at,
    'scheduled_window_key', case when p_trigger = 'scheduled' then to_jsonb(p_scheduled_window_key) else 'null'::jsonb end,
    'overlap_start_at', v_overlap_start
  );
  insert into public.sync_tasks (
    task_type, source_id, parameter_version, requested_by, rule_snapshot,
    collection_scope, capture_range, author_profile_snapshot, x_source_snapshot
  ) values (
    'x_sync', p_source_id, p_parameter_version, p_requested_by,
    '{"version":0,"target_author_ids":[]}'::jsonb, '{"mode":"window"}'::jsonb,
    v_capture_range, '[]'::jsonb,
    jsonb_build_object('source_type', 'x', 'account_id', v_profile.account_id,
      'display_name', v_profile.display_name, 'parameter_version', v_source.parameter_version)
  ) returning * into v_task;
  insert into public.sync_task_capture_progress (task_id, source_id, capture_range)
  values (v_task.id, p_source_id, v_capture_range);
  return to_jsonb(v_task) || jsonb_build_object('idempotent', false);
end;
$$;

revoke all on function public.create_windowed_x_sync_task_without_source_lock(uuid,text,uuid,text,timestamptz,text) from public, anon, authenticated, service_role;
