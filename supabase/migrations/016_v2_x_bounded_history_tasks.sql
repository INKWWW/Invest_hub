-- Explicit X history work is bounded and source-local.  Unlike a continuous
-- window, an out-of-order history range must never move the live waterline.

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
          and capture_range->>'trigger' in ('scheduled', 'manual', 'bootstrap')
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
              capture_range->>'trigger' in ('manual', 'bootstrap')
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

alter table public.sync_tasks
  drop constraint sync_tasks_collection_scope_shape,
  add constraint sync_tasks_collection_scope_shape check (
    (
      capture_range is null
      and jsonb_typeof(collection_scope) = 'object'
      and collection_scope->>'mode' in ('incremental', 'history')
      and jsonb_typeof(collection_scope->'max_pages') = 'number'
      and (collection_scope->>'max_pages')::numeric between 1 and 25
      and mod((collection_scope->>'max_pages')::numeric, 1) = 0
    )
    or (
      capture_range is not null
      and (
        (collection_scope = '{"mode":"window"}'::jsonb and capture_range->>'mode' = 'window')
        or (collection_scope = '{"mode":"history"}'::jsonb and capture_range->>'mode' = 'history')
      )
    )
  );

create function public.create_bounded_x_history_task(
  p_source_id uuid,
  p_parameter_version text,
  p_requested_by uuid,
  p_start_at timestamptz,
  p_end_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_source public.sources%rowtype;
  v_profile public.x_source_profiles%rowtype;
  v_existing public.sync_tasks%rowtype;
  v_task public.sync_tasks%rowtype;
  v_capture_range jsonb;
begin
  if not exists (select 1 from public.profiles where id = p_requested_by and role = 'admin') then
    raise exception 'actor_not_authorized' using errcode = '42501';
  end if;
  if p_start_at is null or p_end_at is null or p_start_at >= p_end_at or p_end_at > timezone('utc', now())
     or (p_start_at at time zone 'Asia/Shanghai')::date <> (p_end_at at time zone 'Asia/Shanghai')::date then
    raise exception 'invalid_capture_range' using errcode = '22023';
  end if;
  select * into v_source from public.sources where id = p_source_id and source_type = 'x' for update;
  if not found then raise exception 'source_not_found' using errcode = '22023'; end if;
  if not v_source.enabled then raise exception 'source_disabled' using errcode = '22023'; end if;
  if p_parameter_version is null or p_parameter_version <> v_source.parameter_version then
    raise exception 'source_parameter_version_mismatch' using errcode = '22023';
  end if;
  select * into v_profile from public.x_source_profiles
  where source_id = p_source_id and enabled and resolution_status = 'resolved' for update;
  if not found then raise exception 'x_source_unresolved' using errcode = '22023'; end if;
  if exists (
    select 1 from public.sync_tasks task
    where task.source_id = p_source_id and task.task_type = 'x_sync'
      and task.status in ('queued', 'leased', 'running', 'retryable_failed')
      and (task.capture_range->>'start_at')::timestamptz < p_end_at
      and (task.capture_range->>'end_at')::timestamptz > p_start_at
  ) then
    raise exception 'active_x_range_overlap' using errcode = '23505';
  end if;
  v_capture_range := jsonb_build_object(
    'mode', 'history', 'trigger', 'history', 'timezone', 'Asia/Shanghai',
    'start_at', p_start_at, 'end_at', p_end_at
  );
  insert into public.sync_tasks (
    task_type, source_id, parameter_version, requested_by, rule_snapshot,
    collection_scope, capture_range, author_profile_snapshot, x_source_snapshot
  ) values (
    'x_sync', p_source_id, p_parameter_version, p_requested_by,
    '{"version":0,"target_author_ids":[]}'::jsonb, '{"mode":"history"}'::jsonb,
    v_capture_range, '[]'::jsonb,
    jsonb_build_object('source_type', 'x', 'account_id', v_profile.account_id,
      'display_name', v_profile.display_name, 'parameter_version', v_source.parameter_version)
  ) returning * into v_task;
  insert into public.sync_task_capture_progress (task_id, source_id, capture_range)
  values (v_task.id, p_source_id, v_capture_range);
  return to_jsonb(v_task) || jsonb_build_object('idempotent', false);
end;
$$;

revoke all on function public.create_bounded_x_history_task(uuid, text, uuid, timestamptz, timestamptz)
  from public, anon, authenticated;
grant execute on function public.create_bounded_x_history_task(uuid, text, uuid, timestamptz, timestamptz)
  to service_role;
