create or replace function public.enqueue_due_discord_tasks(
  p_worker_id uuid,
  p_now timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_source public.sources%rowtype;
  v_coverage public.source_collection_coverage%rowtype;
  v_window public.scheduled_sync_windows%rowtype;
  v_task public.sync_tasks%rowtype;
  v_author_profiles jsonb;
  v_tasks jsonb := '[]'::jsonb;
  v_deferred_source_ids jsonb := '[]'::jsonb;
  v_candidate timestamptz;
  v_range_start timestamptz;
  v_capture_range jsonb;
  v_window_key text;
begin
  if p_now is null then
    raise exception 'invalid_schedule_time' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.workers
    where id = p_worker_id and status in ('enrolled', 'online')
  ) then
    raise exception 'worker_not_authorized' using errcode = '42501';
  end if;

  for v_source in
    select *
    from public.sources
    where enabled
      and source_type = 'discord'
      and authorized_worker_id = p_worker_id
    order by id
  loop
    perform pg_advisory_xact_lock(hashtextextended(v_source.id::text || ':due-windows', 0));

    select * into v_coverage
    from public.source_collection_coverage
    where source_id = v_source.id
    for update;
    if not found then
      continue;
    end if;

    -- A queued manual range is already the next immutable range for this
    -- source.  Do not manufacture a scheduled range from an older waterline
    -- around it; a later tick will enumerate every missed boundary after that
    -- manual range has either completed or been recovered.
    if exists (
      select 1
      from public.sync_tasks pending
      where pending.source_id = v_source.id
        and pending.collection_scope->>'mode' = 'window'
        and pending.capture_range->>'trigger' in ('manual', 'bootstrap')
        and pending.status in ('queued', 'leased', 'running', 'retryable_failed')
    ) then
      v_deferred_source_ids := v_deferred_source_ids || to_jsonb(v_source.id::text);
      continue;
    end if;

    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'author_id', profile.author_id,
          'author_display', profile.author_display,
          'author_handle', profile.author_handle,
          'enabled', profile.enabled
        ) order by profile.author_id
      ),
      '[]'::jsonb
    ) into v_author_profiles
    from public.source_author_profiles profile
    where profile.source_id = v_source.id and profile.enabled;

    v_range_start := v_coverage.coverage_through_at;
    for v_candidate in
      select boundary
      from (
        select ((day_value::date + time_value) at time zone 'Asia/Shanghai') as boundary
        from generate_series(
          (v_coverage.coverage_through_at at time zone 'Asia/Shanghai')::date,
          (p_now at time zone 'Asia/Shanghai')::date,
          interval '1 day'
        ) as day_value
        cross join (values (time '00:00'), (time '08:00'), (time '16:00'), (time '20:50')) as times(time_value)
      ) as boundaries
      where boundary > v_coverage.coverage_through_at
        and boundary <= p_now
      order by boundary
    loop
      v_window_key := to_char(v_candidate at time zone 'Asia/Shanghai', 'YYYY-MM-DD"T"HH24:MI') || '+08:00';
      select * into v_window
      from public.scheduled_sync_windows
      where source_id = v_source.id and window_key = v_window_key
      for update;

      if found then
        select * into v_task from public.sync_tasks where id = v_window.task_id;
        if not found
           or (v_task.capture_range->>'start_at')::timestamptz <> v_range_start
           or (v_task.capture_range->>'end_at')::timestamptz <> v_candidate then
          raise exception 'scheduled_window_chain_mismatch' using errcode = '55000';
        end if;
        v_tasks := v_tasks || jsonb_build_array(jsonb_build_object(
          'id', v_task.id::text,
          'source_id', v_source.id::text,
          'idempotent', true
        ));
      else
        v_capture_range := jsonb_build_object(
          'mode', 'window',
          'trigger', 'scheduled',
          'timezone', 'Asia/Shanghai',
          'start_at', v_range_start,
          'end_at', v_candidate,
          'scheduled_window_key', v_window_key
        );
        insert into public.sync_tasks (
          task_type,
          source_id,
          parameter_version,
          requested_by,
          rule_snapshot,
          collection_scope,
          capture_range,
          author_profile_snapshot
        ) values (
          'discord_sync',
          v_source.id,
          v_source.parameter_version,
          null,
          jsonb_build_object('version', v_source.author_rules_version, 'target_author_ids', '[]'::jsonb),
          '{"mode":"window"}'::jsonb,
          v_capture_range,
          v_author_profiles
        ) returning * into v_task;

        insert into public.sync_task_capture_progress (task_id, source_id, capture_range)
        values (v_task.id, v_source.id, v_capture_range);

        insert into public.scheduled_sync_windows (source_id, window_key, worker_id, task_id)
        values (v_source.id, v_window_key, p_worker_id, v_task.id);

        v_tasks := v_tasks || jsonb_build_array(jsonb_build_object(
          'id', v_task.id::text,
          'source_id', v_source.id::text,
          'idempotent', false
        ));
      end if;
      v_range_start := v_candidate;
    end loop;
  end loop;

  return jsonb_build_object(
    'scheduled_at', p_now,
    'tasks', v_tasks,
    'deferred_source_ids', v_deferred_source_ids
  );
end;
$$;

revoke all on function public.enqueue_due_discord_tasks(uuid, timestamptz)
  from public, anon, authenticated;
grant execute on function public.enqueue_due_discord_tasks(uuid, timestamptz) to service_role;
