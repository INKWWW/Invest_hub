-- `coverage_through_at` is the durable X collection waterline.  A window
-- whose start precedes that waterline has already been superseded: it may
-- remain as audit evidence, but it cannot be reused for a new schedule tick
-- or leased again.  Keeping this condition at both creation and claim makes
-- the scheduler idempotent without letting a retryable stale task preempt the
-- current range.

create or replace function public.create_windowed_x_sync_task(
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
  where source_id = p_source_id and enabled and resolution_status = 'resolved'
  for update;
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

  v_day_start := date_trunc('day', v_coverage.coverage_through_at at time zone 'Asia/Shanghai')
    at time zone 'Asia/Shanghai';
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

create or replace function public.claim_next_task_v2_base(p_worker_id uuid, p_now timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_task public.sync_tasks%rowtype;
  v_attempt integer;
  v_checkpoint text;
  v_lease_expires_at timestamptz;
  v_coverage public.source_collection_coverage%rowtype;
  v_progress public.sync_task_capture_progress%rowtype;
begin
  if not exists (
    select 1 from public.workers
    where id = p_worker_id and status in ('enrolled', 'online')
  ) then
    raise exception 'worker_not_authorized' using errcode = '42501';
  end if;

  select t.* into v_task
  from public.sync_tasks t
  join public.sources s on s.id = t.source_id and s.enabled
  where (
    t.status in ('queued', 'retryable_failed')
    or (t.status in ('leased', 'running') and t.lease_expires_at <= p_now)
  )
    and (
      (s.source_type = 'x' and s.authorized_worker_id = p_worker_id)
      or (
        s.source_type <> 'x'
        and (s.authorized_worker_id is null or s.authorized_worker_id = p_worker_id)
      )
    )
    and (
      s.source_type <> 'x'
      or t.collection_scope->>'mode' <> 'window'
      or exists (
        select 1
        from public.source_collection_coverage current_coverage
        where current_coverage.source_id = t.source_id
          and (t.capture_range->>'start_at')::timestamptz = current_coverage.coverage_through_at
      )
    )
    and (
      t.collection_scope->>'mode' <> 'window'
      or not exists (
        select 1
        from public.sync_tasks predecessor
        left join public.source_collection_coverage predecessor_coverage
          on predecessor_coverage.source_id = predecessor.source_id
        where predecessor.source_id = t.source_id
          and predecessor.id <> t.id
          and predecessor.collection_scope->>'mode' = 'window'
          and (predecessor.capture_range->>'end_at')::timestamptz <= (t.capture_range->>'start_at')::timestamptz
          and predecessor.status <> 'succeeded'
          and (
            predecessor_coverage.coverage_through_at is null
            or (predecessor.capture_range->>'end_at')::timestamptz > predecessor_coverage.coverage_through_at
          )
      )
    )
  order by t.queued_at, t.id
  for update of t skip locked
  limit 1;

  if not found then
    return null;
  end if;

  update public.task_attempts
  set status = 'retryable_failed', completed_at = p_now
  where task_id = v_task.id
    and status in ('leased', 'running')
    and lease_expires_at <= p_now;

  select coalesce(max(attempt), 0) + 1 into v_attempt
  from public.task_attempts
  where task_id = v_task.id;

  v_lease_expires_at := p_now + interval '10 minutes';

  insert into public.task_attempts (task_id, attempt, worker_id, status, lease_expires_at, started_at)
  values (v_task.id, v_attempt, p_worker_id, 'leased', v_lease_expires_at, p_now);

  update public.sync_tasks
  set status = 'leased', lease_owner = p_worker_id, lease_expires_at = v_lease_expires_at
  where id = v_task.id;

  select c.safe_checkpoint into v_checkpoint
  from public.checkpoints c
  where c.source_id = v_task.source_id;

  if v_task.collection_scope->>'mode' = 'window' then
    select * into v_coverage
    from public.source_collection_coverage
    where source_id = v_task.source_id;
    select * into v_progress
    from public.sync_task_capture_progress
    where task_id = v_task.id;
  end if;

  insert into public.task_events (task_id, attempt, event_type, occurred_at, details)
  values (
    v_task.id,
    v_attempt,
    'claimed',
    p_now,
    jsonb_build_object('worker_id', p_worker_id::text, 'lease_expires_at', v_lease_expires_at)
  );

  return jsonb_build_object(
    'contract_version', 'v0',
    'task_id', v_task.id::text,
    'attempt', v_attempt,
    'task_type', v_task.task_type,
    'source_id', (select source_key from public.sources where id = v_task.source_id),
    'parameter_version', v_task.parameter_version,
    'lease_expires_at', v_lease_expires_at,
    'safe_checkpoint', v_checkpoint,
    'rule_snapshot', v_task.rule_snapshot,
    'collection_scope', v_task.collection_scope
  ) || case when v_task.collection_scope->>'mode' = 'window' then jsonb_build_object(
    'capture_range', v_task.capture_range,
    'coverage_snapshot', jsonb_build_object(
      'coverage_start_at', v_coverage.coverage_start_at,
      'coverage_through_at', v_coverage.coverage_through_at,
      'last_completed_task_id', v_coverage.last_completed_task_id
    ),
    'capture_progress', jsonb_build_object(
      'resume_cursor', v_progress.resume_cursor,
      'page_count', v_progress.page_count,
      'range_complete', v_progress.range_complete
    ),
    'author_profile_snapshot', v_task.author_profile_snapshot
  ) else '{}'::jsonb end;
end;
$$;
