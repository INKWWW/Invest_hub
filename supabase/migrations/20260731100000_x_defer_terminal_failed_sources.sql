-- Keep terminal X failures isolated at the scheduler boundary.  A failed
-- window remains an audit record and still blocks that source's waterline,
-- but the due-window scheduler must not recreate the same failed window on
-- every tick and consume the Worker recovery loop.

create or replace function public.enqueue_due_x_tasks(p_worker_id uuid, p_now timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_source record;
  v_end_at timestamptz;
  v_window_key text;
  v_task jsonb;
  v_tasks jsonb := '[]'::jsonb;
  v_deferred_source_ids jsonb := '[]'::jsonb;
begin
  if p_now is null or not exists (
    select 1 from public.workers where id = p_worker_id and status in ('enrolled', 'online')
  ) then
    raise exception 'worker_not_authorized' using errcode = '42501';
  end if;
  for v_source in
    select source.id, source.parameter_version, coverage.coverage_through_at
    from public.sources source
    join public.x_source_profiles profile on profile.source_id = source.id
      and profile.enabled and profile.resolution_status = 'resolved'
    join public.source_collection_coverage coverage on coverage.source_id = source.id
    where source.source_type = 'x' and source.enabled
      and (source.authorized_worker_id is null or source.authorized_worker_id = p_worker_id)
  loop
    if exists (
      select 1
      from public.sync_tasks terminal_failure
      where terminal_failure.source_id = v_source.id
        and terminal_failure.task_type = 'x_sync'
        and terminal_failure.collection_scope->>'mode' = 'window'
        and terminal_failure.status = 'failed'
        and (terminal_failure.capture_range->>'start_at')::timestamptz = v_source.coverage_through_at
        and (terminal_failure.capture_range->>'end_at')::timestamptz > v_source.coverage_through_at
    ) then
      v_deferred_source_ids := v_deferred_source_ids || jsonb_build_array(v_source.id::text);
      continue;
    end if;

    select min((day_at + cutoff) at time zone 'Asia/Shanghai')
      into v_end_at
    from generate_series(
      date_trunc('day', v_source.coverage_through_at at time zone 'Asia/Shanghai'),
      date_trunc('day', p_now at time zone 'Asia/Shanghai'),
      interval '1 day'
    ) as day_at
    cross join (values (time '00:00'), (time '08:00'), (time '12:00'), (time '16:00'), (time '20:00')) as cutoffs(cutoff)
    where (day_at + cutoff) at time zone 'Asia/Shanghai' > v_source.coverage_through_at
      and (day_at + cutoff) at time zone 'Asia/Shanghai' <= p_now;
    if v_end_at is null then continue; end if;
    v_window_key := to_char(v_end_at at time zone 'Asia/Shanghai', 'YYYY-MM-DD"T"HH24:MI') || '+08:00';
    v_task := public.create_windowed_x_sync_task(
      v_source.id, v_source.parameter_version, null, 'scheduled', v_end_at, v_window_key
    );
    v_tasks := v_tasks || jsonb_build_array(jsonb_build_object(
      'id', v_task->>'id', 'source_id', v_task->>'source_id', 'idempotent', coalesce((v_task->>'idempotent')::boolean, false)
    ));
  end loop;
  return jsonb_build_object(
    'scheduled_at', p_now,
    'tasks', v_tasks,
    'deferred_source_ids', v_deferred_source_ids
  );
end;
$$;

revoke all on function public.enqueue_due_x_tasks(uuid, timestamptz)
  from public, anon, authenticated;
grant execute on function public.enqueue_due_x_tasks(uuid, timestamptz) to service_role;
