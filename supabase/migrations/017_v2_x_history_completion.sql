-- Reuse the already verified X completion validator for a bounded history
-- range inside one transaction.  Its temporary window representation is
-- never committed: the immutable task snapshot and non-contiguous waterline
-- are restored before the transaction returns.

create function public.complete_bounded_x_history_range(
  p_task_id uuid,
  p_attempt integer,
  p_worker_id uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_task public.sync_tasks%rowtype;
  v_coverage public.source_collection_coverage%rowtype;
  v_original_range jsonb;
  v_window_range jsonb;
  v_window_payload jsonb;
  v_result jsonb;
  v_contiguous boolean;
  v_result_coverage timestamptz;
begin
  select * into v_task from public.sync_tasks where id = p_task_id for update;
  if not found then
    raise exception 'history_task_not_found' using errcode = '22023';
  end if;
  if v_task.task_type <> 'x_sync' then
    raise exception 'history_task_type_mismatch' using errcode = '22023';
  end if;
  if v_task.collection_scope <> '{"mode":"history"}'::jsonb then
    raise exception 'history_scope_mismatch' using errcode = '22023';
  end if;
  if v_task.capture_range->>'mode' <> 'history' then
    raise exception 'invalid_x_history_completion' using errcode = '22023';
  end if;
  if p_payload is null then
    raise exception 'invalid_x_history_completion' using errcode = '22023';
  end if;
  if jsonb_typeof(p_payload->'capture_range') <> 'object'
     or p_payload->'capture_range'->>'mode' <> 'history'
     or p_payload->'capture_range'->>'trigger' <> 'history'
     or p_payload->'capture_range'->>'timezone' <> 'Asia/Shanghai'
     or (p_payload->'capture_range'->>'start_at')::timestamptz <> (v_task.capture_range->>'start_at')::timestamptz
     or (p_payload->'capture_range'->>'end_at')::timestamptz <> (v_task.capture_range->>'end_at')::timestamptz then
    raise exception 'history_payload_range_mismatch' using errcode = '22023';
  end if;
  select * into v_coverage from public.source_collection_coverage
  where source_id = v_task.source_id for update;
  if not found then raise exception 'coverage_not_initialized' using errcode = '22023'; end if;

  v_original_range := v_task.capture_range;
  v_contiguous := v_coverage.coverage_through_at = (v_original_range->>'start_at')::timestamptz;
  v_window_range := jsonb_build_object(
    'mode', 'window', 'trigger', 'manual', 'timezone', 'Asia/Shanghai',
    'start_at', v_original_range->'start_at', 'end_at', v_original_range->'end_at',
    'scheduled_window_key', null, 'overlap_start_at', v_original_range->'start_at'
  );
  v_window_payload := jsonb_set(p_payload, '{capture_range}', v_window_range, true);

  update public.sync_tasks
  set collection_scope = '{"mode":"window"}'::jsonb, capture_range = v_window_range
  where id = p_task_id;
  update public.source_collection_coverage
  set coverage_start_at = (v_original_range->>'start_at')::timestamptz,
      coverage_through_at = (v_original_range->>'start_at')::timestamptz,
      last_completed_task_id = null
  where source_id = v_task.source_id;

  v_result := public.complete_windowed_capture_range(p_task_id, p_attempt, p_worker_id, v_window_payload);

  update public.sync_tasks
  set collection_scope = '{"mode":"history"}'::jsonb, capture_range = v_original_range
  where id = p_task_id;
  update public.task_attempts
  set result = jsonb_set(result, '{capture_range}', v_original_range, true)
  where task_id = p_task_id and attempt = p_attempt;
  update public.task_events
  set details = jsonb_set(details, '{capture_range}', v_original_range, true)
  where task_id = p_task_id and attempt = p_attempt and event_type = 'succeeded';

  if v_contiguous then
    v_result_coverage := (v_original_range->>'end_at')::timestamptz;
    update public.source_collection_coverage
    set coverage_start_at = v_coverage.coverage_start_at,
        coverage_through_at = v_result_coverage,
        last_completed_task_id = p_task_id
    where source_id = v_task.source_id;
  else
    v_result_coverage := v_coverage.coverage_through_at;
    update public.source_collection_coverage
    set coverage_start_at = v_coverage.coverage_start_at,
        coverage_through_at = v_coverage.coverage_through_at,
        last_completed_task_id = v_coverage.last_completed_task_id
    where source_id = v_task.source_id;
  end if;
  return jsonb_set(
    jsonb_set(v_result, '{coverage_through_at}', to_jsonb(v_result_coverage::text), true),
    '{history_contiguous}', to_jsonb(v_contiguous), true
  );
end;
$$;

revoke all on function public.complete_bounded_x_history_range(uuid, integer, uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.complete_bounded_x_history_range(uuid, integer, uuid, jsonb) to service_role;
