-- A terminal source failure remains immutable.  Recovery creates a new
-- bounded replacement task only when it is still exactly at the continuous
-- waterline, so a successful replacement can use the normal completion path.

alter table public.sync_tasks
  add column recovered_from_task_id uuid references public.sync_tasks(id) on delete restrict,
  add constraint sync_tasks_recovered_from_not_self check (recovered_from_task_id is null or recovered_from_task_id <> id);

create unique index sync_tasks_one_terminal_recovery
  on public.sync_tasks (recovered_from_task_id)
  where recovered_from_task_id is not null;

alter table public.sync_tasks
  drop constraint sync_tasks_capture_range_shape,
  add constraint sync_tasks_capture_range_shape check (
    capture_range is null
    or (
      jsonb_typeof(capture_range) = 'object'
      and jsonb_typeof(capture_range->'start_at') = 'string'
      and jsonb_typeof(capture_range->'end_at') = 'string'
      and nullif(capture_range->>'start_at', '') is not null
      and nullif(capture_range->>'end_at', '') is not null
      and (capture_range->>'start_at')::timestamptz < (capture_range->>'end_at')::timestamptz
      and capture_range->>'timezone' = 'Asia/Shanghai'
      and (
        (
          capture_range->>'mode' = 'window'
          and (capture_range - 'mode' - 'trigger' - 'timezone' - 'start_at' - 'end_at' - 'scheduled_window_key' - 'overlap_start_at') = '{}'::jsonb
          and capture_range->>'trigger' in ('scheduled', 'manual', 'bootstrap', 'recovery')
          and (
            not (capture_range ? 'overlap_start_at')
            or (
              jsonb_typeof(capture_range->'overlap_start_at') = 'string'
              and nullif(capture_range->>'overlap_start_at', '') is not null
              and (capture_range->>'overlap_start_at')::timestamptz <= (capture_range->>'start_at')::timestamptz
            )
          )
          and (
            (
              capture_range->>'trigger' = 'scheduled'
              and jsonb_typeof(capture_range->'scheduled_window_key') = 'string'
              and capture_range->>'scheduled_window_key' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T(00:00|08:00|12:00|16:00|20:00|20:50)[+]08:00$'
              and (capture_range->>'scheduled_window_key')::timestamptz = (capture_range->>'end_at')::timestamptz
            )
            or (
              capture_range->>'trigger' in ('manual', 'bootstrap', 'recovery')
              and jsonb_typeof(capture_range->'scheduled_window_key') = 'null'
            )
          )
        )
        or (
          capture_range->>'mode' = 'history'
          and (capture_range - 'mode' - 'trigger' - 'timezone' - 'start_at' - 'end_at') = '{}'::jsonb
          and capture_range->>'trigger' = 'history'
        )
      )
    )
  );

create function public.create_x_terminal_recovery_task(p_failed_task_id uuid, p_requested_by uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_failed public.sync_tasks%rowtype;
  v_source public.sources%rowtype;
  v_profile public.x_source_profiles%rowtype;
  v_coverage public.source_collection_coverage%rowtype;
  v_recovery public.sync_tasks%rowtype;
  v_range jsonb;
begin
  if p_requested_by is null or not exists (
    select 1 from public.profiles where id = p_requested_by and role = 'admin'
  ) then
    raise exception 'actor_not_authorized' using errcode = '42501';
  end if;

  select * into v_failed from public.sync_tasks where id = p_failed_task_id for update;
  if not found
     or v_failed.task_type <> 'x_sync'
     or v_failed.status <> 'failed'
     or v_failed.collection_scope <> '{"mode":"window"}'::jsonb
     or v_failed.capture_range->>'mode' <> 'window' then
    raise exception 'terminal_x_recovery_not_available' using errcode = '22023';
  end if;
  if exists (select 1 from public.sync_tasks where recovered_from_task_id = v_failed.id) then
    raise exception 'terminal_x_recovery_exists' using errcode = '23505';
  end if;

  select * into v_source from public.sources where id = v_failed.source_id and source_type = 'x' for update;
  if not found or not v_source.enabled then raise exception 'source_disabled' using errcode = '22023'; end if;
  if v_source.parameter_version <> v_failed.parameter_version then raise exception 'source_parameter_version_mismatch' using errcode = '22023'; end if;
  select * into v_profile from public.x_source_profiles where source_id = v_failed.source_id and enabled and resolution_status = 'resolved' for update;
  if not found then raise exception 'x_source_unresolved' using errcode = '22023'; end if;
  select * into v_coverage from public.source_collection_coverage where source_id = v_failed.source_id for update;
  if not found or v_coverage.coverage_through_at <> (v_failed.capture_range->>'start_at')::timestamptz then
    raise exception 'terminal_x_recovery_waterline_mismatch' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.sync_tasks
    where source_id = v_failed.source_id and task_type = 'x_sync'
      and status in ('queued', 'leased', 'running', 'retryable_failed')
  ) then
    raise exception 'source_has_active_task' using errcode = '23505';
  end if;

  v_range := jsonb_set(
    jsonb_set(v_failed.capture_range, '{trigger}', '"recovery"'::jsonb, true),
    '{scheduled_window_key}', 'null'::jsonb, true
  );
  insert into public.sync_tasks (
    task_type, source_id, parameter_version, requested_by, rule_snapshot,
    collection_scope, capture_range, author_profile_snapshot, x_source_snapshot, recovered_from_task_id
  ) values (
    'x_sync', v_failed.source_id, v_failed.parameter_version, p_requested_by, v_failed.rule_snapshot,
    '{"mode":"window"}'::jsonb, v_range, v_failed.author_profile_snapshot, v_failed.x_source_snapshot, v_failed.id
  ) returning * into v_recovery;
  insert into public.sync_task_capture_progress (task_id, source_id, capture_range)
  values (v_recovery.id, v_recovery.source_id, v_range);
  return to_jsonb(v_recovery) || jsonb_build_object('idempotent', false);
end;
$$;

create or replace function public.record_task_failure(
  p_task_id uuid,
  p_attempt integer,
  p_failure jsonb,
  p_context jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_task public.sync_tasks%rowtype;
  v_attempt public.task_attempts%rowtype;
  v_worker_id uuid;
  v_status text;
  v_attempt_status text;
  v_event_type text;
begin
  begin v_worker_id := nullif(p_context->>'worker_id', '')::uuid;
  exception when invalid_text_representation then raise exception 'worker_not_authorized' using errcode = '42501'; end;
  select * into v_task from public.sync_tasks where id = p_task_id for update;
  select * into v_attempt from public.task_attempts where task_id = p_task_id and attempt = p_attempt for update;
  if not found then raise exception 'attempt_not_found' using errcode = '22023'; end if;
  if v_attempt.status in ('failed', 'retryable_failed') then
    if v_attempt.failure = p_failure then return jsonb_build_object('status', v_attempt.status, 'idempotent', true, 'task_id', p_task_id::text, 'attempt', p_attempt); end if;
    raise exception 'conflicting_duplicate_failure' using errcode = '23505';
  end if;
  if v_task.id is null or v_attempt.worker_id <> v_worker_id or v_task.lease_owner <> v_worker_id
     or v_attempt.status not in ('leased', 'running') or v_task.status not in ('leased', 'running') then
    raise exception 'lease_mismatch' using errcode = '40001';
  end if;
  v_status := case when coalesce((p_failure->>'retryable')::boolean, false) then 'retryable_failed' when p_failure->>'status' = 'cancelled' then 'cancelled' else 'failed' end;
  v_attempt_status := case when v_status = 'cancelled' then 'failed' else v_status end;
  v_event_type := case when v_status = 'retryable_failed' then 'retry' else 'failed' end;
  update public.task_attempts set status = v_attempt_status, failure = p_failure, completed_at = timezone('utc', now()) where id = v_attempt.id;
  update public.sync_tasks set status = v_status, lease_owner = null, lease_expires_at = null where id = v_task.id;
  insert into public.task_events (task_id, attempt, event_type, occurred_at, details)
  values (p_task_id, p_attempt, v_event_type, timezone('utc', now()),
    jsonb_strip_nulls(jsonb_build_object('failure_class', p_failure->>'failure_class', 'failure_stage', p_failure->>'failure_stage', 'retryable', p_failure->>'retryable')));
  return jsonb_build_object('status', v_status, 'idempotent', false, 'task_id', p_task_id::text, 'attempt', p_attempt);
end;
$$;

revoke all on function public.create_x_terminal_recovery_task(uuid, uuid) from public, anon, authenticated;
grant execute on function public.create_x_terminal_recovery_task(uuid, uuid) to service_role;
