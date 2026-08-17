-- A queued or leased non-scheduled range at the current waterline is real
-- work, but it is not evidence that the source's oldest scheduled cutoff was
-- enqueued.  Keep that source deferred while allowing every other source to
-- create its own oldest due window.  This also prevents a null manual/recovery
-- window key from entering the health probe's authoritative window envelope.

create or replace function public.enqueue_due_x_tasks(p_worker_id uuid, p_now timestamptz)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_source record;
  v_end_at timestamptz;
  v_window_key text;
  v_task jsonb;
  v_failed_task_id uuid;
  v_failed_window_key text;
  v_active_task_id uuid;
  v_active_window_key text;
  v_tasks jsonb := '[]'::jsonb;
  v_deferred_source_ids jsonb := '[]'::jsonb;
  v_window_work jsonb := '[]'::jsonb;
begin
  if p_now is null or not exists (
    select 1 from public.workers where id = p_worker_id and status in ('enrolled', 'online')
  ) then
    raise exception 'worker_not_authorized' using errcode = '42501';
  end if;

  for v_source in
    select source.id, source.parameter_version, coverage.coverage_through_at
      from public.sources source
      join public.x_source_profiles profile
        on profile.source_id = source.id and profile.enabled and profile.resolution_status = 'resolved'
      join public.source_collection_coverage coverage on coverage.source_id = source.id
     where source.source_type = 'x' and source.enabled and source.authorized_worker_id = p_worker_id
  loop
    v_failed_task_id := null;
    v_failed_window_key := null;
    select task.id, task.capture_range->>'scheduled_window_key'
      into v_failed_task_id, v_failed_window_key
      from public.sync_tasks task
     where task.source_id = v_source.id
       and task.task_type = 'x_sync'
       and task.collection_scope->>'mode' = 'window'
       and task.status = 'failed'
       and task.recovered_from_task_id is null
       and (task.capture_range->>'start_at')::timestamptz = v_source.coverage_through_at
       and (task.capture_range->>'end_at')::timestamptz > v_source.coverage_through_at
     order by task.queued_at, task.id
     limit 1;
    if v_failed_task_id is not null then
      if v_failed_window_key is not null then
        v_window_work := v_window_work || jsonb_build_array(jsonb_build_object(
          'window_key', v_failed_window_key,
          'tasks', jsonb_build_array(jsonb_build_object(
            'task_id', v_failed_task_id::text,
            'status', 'terminal_failed'
          ))
        ));
      end if;
      if not exists (select 1 from public.sync_tasks where recovered_from_task_id = v_failed_task_id) then
        select public.create_x_terminal_recovery_task_unchecked(v_failed_task_id, null) into v_task;
        v_tasks := v_tasks || jsonb_build_array(jsonb_build_object(
          'id', v_task->>'id', 'source_id', v_task->>'source_id', 'idempotent', false
        ));
      else
        v_deferred_source_ids := v_deferred_source_ids || jsonb_build_array(v_source.id::text);
      end if;
      continue;
    end if;

    if exists (
      select 1 from public.sync_tasks task
       where task.source_id = v_source.id and task.task_type = 'x_sync'
         and task.collection_scope->>'mode' = 'window' and task.status = 'failed'
         and (task.capture_range->>'start_at')::timestamptz = v_source.coverage_through_at
    ) then
      v_deferred_source_ids := v_deferred_source_ids || jsonb_build_array(v_source.id::text);
      continue;
    end if;

    select min((day_at + cutoff) at time zone 'Asia/Shanghai')
      into v_end_at
      from generate_series(
        date_trunc('day', v_source.coverage_through_at at time zone 'Asia/Shanghai'),
        date_trunc('day', p_now at time zone 'Asia/Shanghai'), interval '1 day'
      ) day_at
      cross join (values (time '00:00'), (time '08:00'), (time '12:00'), (time '16:00'), (time '20:00')) cutoffs(cutoff)
     where (day_at + cutoff) at time zone 'Asia/Shanghai' > v_source.coverage_through_at
       and (day_at + cutoff) at time zone 'Asia/Shanghai' <= p_now;
    if v_end_at is null then
      continue;
    end if;
    v_window_key := to_char(v_end_at at time zone 'Asia/Shanghai', 'YYYY-MM-DD"T"HH24:MI') || '+08:00';

    v_active_task_id := null;
    v_active_window_key := null;
    select task.id, task.capture_range->>'scheduled_window_key'
      into v_active_task_id, v_active_window_key
      from public.sync_tasks task
     where task.source_id = v_source.id
       and task.task_type = 'x_sync'
       and task.collection_scope->>'mode' = 'window'
       and task.status in ('queued', 'leased', 'running', 'retryable_failed')
       and (task.capture_range->>'start_at')::timestamptz = v_source.coverage_through_at
       and (task.capture_range->>'end_at')::timestamptz > v_source.coverage_through_at
     order by (task.capture_range->>'end_at')::timestamptz, task.queued_at, task.id
     limit 1;
    if v_active_task_id is not null
       and v_active_window_key is distinct from v_window_key then
      v_deferred_source_ids := v_deferred_source_ids || jsonb_build_array(v_source.id::text);
      continue;
    end if;

    select public.create_windowed_x_sync_task(
      v_source.id, v_source.parameter_version, null, 'scheduled', v_end_at, v_window_key
    ) into v_task;
    v_tasks := v_tasks || jsonb_build_array(jsonb_build_object(
      'id', v_task->>'id', 'source_id', v_task->>'source_id',
      'idempotent', coalesce((v_task->>'idempotent')::boolean, false)
    ));
    v_window_work := v_window_work || jsonb_build_array(jsonb_build_object(
      'window_key', v_window_key,
      'tasks', jsonb_build_array(jsonb_build_object(
        'task_id', v_task->>'id',
        'status', case
          when v_task->>'status' = 'succeeded' then 'succeeded'
          when v_task->>'status' = 'failed' then 'terminal_failed'
          else 'pending'
        end
      ))
    ));
  end loop;

  with tick_task_ids as (
    select (task_item->>'task_id')::uuid as task_id
      from jsonb_array_elements(v_window_work) window_item
      cross join lateral jsonb_array_elements(window_item->'tasks') task_item
  ), frontier_task_ids as (
    select task.id as task_id
      from public.sources source
      join public.x_source_profiles profile
        on profile.source_id = source.id and profile.enabled and profile.resolution_status = 'resolved'
      join public.source_collection_coverage coverage on coverage.source_id = source.id
      join public.sync_tasks task
        on task.source_id = source.id
       and task.task_type = 'x_sync'
       and task.collection_scope->>'mode' = 'window'
     where source.source_type = 'x'
       and source.enabled
       and source.authorized_worker_id = p_worker_id
       and task.capture_range->>'scheduled_window_key' is not null
       and (
         task.status in ('queued', 'leased', 'running', 'retryable_failed')
         or (task.id = coverage.last_completed_task_id and task.status = 'succeeded')
         or (
           task.status = 'failed'
           and task.recovered_from_task_id is null
           and (task.capture_range->>'start_at')::timestamptz = coverage.coverage_through_at
           and (task.capture_range->>'end_at')::timestamptz > coverage.coverage_through_at
           and not exists (
             select 1 from public.sync_tasks recovery where recovery.recovered_from_task_id = task.id
           )
         )
       )
  ), candidate_task_ids as (
    select task_id from tick_task_ids
    union
    select task_id from frontier_task_ids
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'window_key', observed.window_key,
    'tasks', observed.tasks
  ) order by observed.window_key), '[]'::jsonb)
    into v_window_work
    from (
      select
        task.capture_range->>'scheduled_window_key' as window_key,
        jsonb_agg(jsonb_build_object(
          'task_id', task.id::text,
          'status', case
            when task.status = 'succeeded' then 'succeeded'
            when task.status = 'failed' then 'terminal_failed'
            else 'pending'
          end
        ) order by task.id) as tasks
      from public.sync_tasks task
      join candidate_task_ids candidate on candidate.task_id = task.id
     group by task.capture_range->>'scheduled_window_key'
    ) observed;

  return jsonb_build_object(
    'scheduled_at', p_now,
    'tasks', v_tasks,
    'deferred_source_ids', v_deferred_source_ids,
    'window_work', v_window_work
  );
end $$;

revoke all on function public.enqueue_due_x_tasks(uuid, timestamptz)
  from public, anon, authenticated;
grant execute on function public.enqueue_due_x_tasks(uuid, timestamptz)
  to service_role;
