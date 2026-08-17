-- Every mutation of an X source's task/coverage frontier uses one transaction
-- advisory lock.  The wrappers keep the existing validated behavior while
-- making scheduler decisions atomic with completion and failure transitions.

alter function public.create_windowed_x_sync_task(uuid,text,uuid,text,timestamptz,text)
  rename to create_windowed_x_sync_task_without_source_lock;
create function public.create_windowed_x_sync_task(
  p_source_id uuid, p_parameter_version text, p_requested_by uuid, p_trigger text,
  p_end_at timestamptz, p_scheduled_window_key text
) returns jsonb language plpgsql security definer set search_path=public,extensions as $$
begin
  perform pg_advisory_xact_lock(hashtextextended(p_source_id::text,24005));
  return public.create_windowed_x_sync_task_without_source_lock(
    p_source_id,p_parameter_version,p_requested_by,p_trigger,p_end_at,p_scheduled_window_key
  );
end $$;

alter function public.complete_windowed_capture_range(uuid,integer,uuid,jsonb)
  rename to complete_windowed_capture_range_without_source_lock;
create function public.complete_windowed_capture_range(
  p_task_id uuid,p_attempt integer,p_worker_id uuid,p_payload jsonb
) returns jsonb language plpgsql security definer set search_path=public,extensions set lock_timeout='5s' as $$
declare v_source_id uuid;
begin
  select source_id into v_source_id from public.sync_tasks where id=p_task_id;
  if v_source_id is not null then
    perform pg_advisory_xact_lock(hashtextextended(v_source_id::text,24005));
  end if;
  return public.complete_windowed_capture_range_without_source_lock(p_task_id,p_attempt,p_worker_id,p_payload);
exception when sqlstate '40001' then raise sqlstate 'PT409' using message=sqlerrm;
end $$;

alter function public.record_task_failure(uuid,integer,jsonb,jsonb)
  rename to record_task_failure_without_source_lock;
create function public.record_task_failure(
  p_task_id uuid,p_attempt integer,p_failure jsonb,p_context jsonb
) returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_source_id uuid;
begin
  select source_id into v_source_id from public.sync_tasks where id=p_task_id;
  if v_source_id is not null then
    perform pg_advisory_xact_lock(hashtextextended(v_source_id::text,24005));
  end if;
  return public.record_task_failure_without_source_lock(p_task_id,p_attempt,p_failure,p_context);
end $$;

alter function public.create_x_terminal_recovery_task_unchecked(uuid,uuid)
  rename to create_x_terminal_recovery_task_unchecked_without_source_lock;
create function public.create_x_terminal_recovery_task_unchecked(p_failed_task_id uuid,p_requested_by uuid)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_source_id uuid;
begin
  select source_id into v_source_id from public.sync_tasks where id=p_failed_task_id;
  if v_source_id is not null then
    perform pg_advisory_xact_lock(hashtextextended(v_source_id::text,24005));
  end if;
  return public.create_x_terminal_recovery_task_unchecked_without_source_lock(p_failed_task_id,p_requested_by);
end $$;

alter function public.create_bounded_x_history_task(uuid,text,uuid,timestamptz,timestamptz)
  rename to create_bounded_x_history_task_without_source_lock;
create function public.create_bounded_x_history_task(p_source_id uuid,p_parameter_version text,p_requested_by uuid,p_start_at timestamptz,p_end_at timestamptz)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
begin
  perform pg_advisory_xact_lock(hashtextextended(p_source_id::text,24005));
  return public.create_bounded_x_history_task_without_source_lock(p_source_id,p_parameter_version,p_requested_by,p_start_at,p_end_at);
end $$;

alter function public.complete_bounded_x_history_range(uuid,integer,uuid,jsonb)
  rename to complete_bounded_x_history_range_without_source_lock;
create function public.complete_bounded_x_history_range(p_task_id uuid,p_attempt integer,p_worker_id uuid,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_source_id uuid;
begin
  select source_id into v_source_id from public.sync_tasks where id=p_task_id;
  if v_source_id is not null then perform pg_advisory_xact_lock(hashtextextended(v_source_id::text,24005)); end if;
  return public.complete_bounded_x_history_range_without_source_lock(p_task_id,p_attempt,p_worker_id,p_payload);
end $$;

alter function public.initialize_x_source_activation(uuid,uuid,timestamptz)
  rename to initialize_x_source_activation_without_source_lock;
create function public.initialize_x_source_activation(p_source_id uuid,p_worker_id uuid,p_now timestamptz)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
begin
  perform pg_advisory_xact_lock(hashtextextended(p_source_id::text,24005));
  return public.initialize_x_source_activation_without_source_lock(p_source_id,p_worker_id,p_now);
end $$;

alter function public.initialize_x_collection_coverage(uuid,uuid,timestamptz)
  rename to initialize_x_collection_coverage_without_source_lock;
create function public.initialize_x_collection_coverage(p_source_id uuid,p_actor_id uuid,p_boundary timestamptz)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
begin
  perform pg_advisory_xact_lock(hashtextextended(p_source_id::text,24005));
  return public.initialize_x_collection_coverage_without_source_lock(p_source_id,p_actor_id,p_boundary);
end $$;

create or replace function public.enqueue_due_x_tasks(p_worker_id uuid,p_now timestamptz)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare
  v_source record; v_coverage public.source_collection_coverage%rowtype;
  v_end_at timestamptz; v_window_key text; v_task jsonb;
  v_failed public.sync_tasks%rowtype; v_recovery public.sync_tasks%rowtype;
  v_active public.sync_tasks%rowtype; v_completed public.sync_tasks%rowtype;
  v_cutoff timestamptz; v_settlement_end timestamptz; v_status text;
  v_tasks jsonb:='[]'::jsonb; v_deferred jsonb:='[]'::jsonb; v_work jsonb:='[]'::jsonb;
begin
  if p_now is null or not exists(select 1 from public.workers where id=p_worker_id and status in('enrolled','online')) then
    raise exception 'worker_not_authorized' using errcode='42501';
  end if;
  for v_source in
    select source.id,source.parameter_version from public.sources source
    join public.x_source_profiles profile on profile.source_id=source.id and profile.enabled and profile.resolution_status='resolved'
    where source.source_type='x' and source.enabled and source.authorized_worker_id=p_worker_id
    order by source.id
  loop
    perform pg_advisory_xact_lock(hashtextextended(v_source.id::text,24005));
    select * into v_coverage from public.source_collection_coverage where source_id=v_source.id;
    if not found then continue; end if;

    -- Re-state a completed null-key range as success for every fixed cutoff it
    -- actually covered.  This is the authenticated settlement seam consumed
    -- by the local health ledger after an interrupted manual/recovery ack.
    select * into v_completed from public.sync_tasks
      where id=v_coverage.last_completed_task_id and status='succeeded';
    if found then
      if v_completed.capture_range->>'scheduled_window_key' is null then
        select min((day_at+cutoff) at time zone 'Asia/Shanghai') into v_settlement_end
        from generate_series(date_trunc('day',(v_completed.capture_range->>'end_at')::timestamptz at time zone 'Asia/Shanghai'),date_trunc('day',(v_completed.capture_range->>'end_at')::timestamptz at time zone 'Asia/Shanghai')+interval '1 day',interval '1 day') day_at
        cross join (values(time '00:00'),(time '08:00'),(time '12:00'),(time '16:00'),(time '20:00')) c(cutoff)
        where (day_at+cutoff) at time zone 'Asia/Shanghai'>=(v_completed.capture_range->>'end_at')::timestamptz;
        for v_cutoff in
          select (day_at+cutoff) at time zone 'Asia/Shanghai'
          from generate_series(date_trunc('day',(v_completed.capture_range->>'start_at')::timestamptz at time zone 'Asia/Shanghai'),date_trunc('day',(v_completed.capture_range->>'end_at')::timestamptz at time zone 'Asia/Shanghai'),interval '1 day') day_at
          cross join (values(time '00:00'),(time '08:00'),(time '12:00'),(time '16:00'),(time '20:00')) c(cutoff)
          where (day_at+cutoff) at time zone 'Asia/Shanghai' > (v_completed.capture_range->>'start_at')::timestamptz
            and (day_at+cutoff) at time zone 'Asia/Shanghai' <= v_settlement_end
          order by 1
        loop
          v_work:=v_work||jsonb_build_array(jsonb_build_object('window_key',to_char(v_cutoff at time zone 'Asia/Shanghai','YYYY-MM-DD"T"HH24:MI')||'+08:00','tasks',jsonb_build_array(jsonb_build_object('task_id',v_completed.id::text,'status','succeeded'))));
        end loop;
      else
        v_work:=v_work||jsonb_build_array(jsonb_build_object('window_key',v_completed.capture_range->>'scheduled_window_key','tasks',jsonb_build_array(jsonb_build_object('task_id',v_completed.id::text,'status','succeeded'))));
      end if;
    end if;

    select * into v_failed from public.sync_tasks task
    where task.source_id=v_source.id and task.task_type='x_sync' and task.collection_scope->>'mode'='window'
      and task.status='failed' and task.recovered_from_task_id is null
      and (task.capture_range->>'start_at')::timestamptz=v_coverage.coverage_through_at
      and (task.capture_range->>'end_at')::timestamptz>v_coverage.coverage_through_at
    order by task.queued_at,task.id limit 1;
    if found then
      select * into v_recovery from public.sync_tasks where recovered_from_task_id=v_failed.id;
      if not found then
        select public.create_x_terminal_recovery_task_unchecked(v_failed.id,null) into v_task;
        select * into v_recovery from public.sync_tasks where id=(v_task->>'id')::uuid;
        v_tasks:=v_tasks||jsonb_build_array(jsonb_build_object('id',v_recovery.id::text,'source_id',v_source.id::text,'idempotent',false));
      else v_deferred:=v_deferred||jsonb_build_array(v_source.id::text); end if;
      v_status:=case when v_recovery.status='succeeded' then 'succeeded' when v_recovery.status='failed' then 'terminal_failed' else 'pending' end;
      v_work:=v_work||jsonb_build_array(jsonb_build_object('window_key',v_failed.capture_range->>'scheduled_window_key','tasks',jsonb_build_array(jsonb_build_object('task_id',v_failed.id::text,'status',v_status))));
      continue;
    end if;
    if exists(select 1 from public.sync_tasks task where task.source_id=v_source.id and task.task_type='x_sync' and task.collection_scope->>'mode'='window' and task.status='failed' and (task.capture_range->>'start_at')::timestamptz=v_coverage.coverage_through_at) then
      v_deferred:=v_deferred||jsonb_build_array(v_source.id::text); continue;
    end if;

    select min((day_at+cutoff) at time zone 'Asia/Shanghai') into v_end_at
    from generate_series(date_trunc('day',v_coverage.coverage_through_at at time zone 'Asia/Shanghai'),date_trunc('day',p_now at time zone 'Asia/Shanghai'),interval '1 day') day_at
    cross join (values(time '00:00'),(time '08:00'),(time '12:00'),(time '16:00'),(time '20:00')) c(cutoff)
    where (day_at+cutoff) at time zone 'Asia/Shanghai'>v_coverage.coverage_through_at and (day_at+cutoff) at time zone 'Asia/Shanghai'<=p_now;
    if v_end_at is null then continue; end if;
    v_window_key:=to_char(v_end_at at time zone 'Asia/Shanghai','YYYY-MM-DD"T"HH24:MI')||'+08:00';
    select * into v_active from public.sync_tasks task where task.source_id=v_source.id and task.task_type='x_sync' and task.collection_scope->>'mode'='window'
      and task.status in('queued','leased','running','retryable_failed') and (task.capture_range->>'start_at')::timestamptz=v_coverage.coverage_through_at
      and (task.capture_range->>'end_at')::timestamptz>v_coverage.coverage_through_at order by (task.capture_range->>'end_at')::timestamptz,task.queued_at,task.id limit 1;
    if found and v_active.capture_range->>'scheduled_window_key' is distinct from v_window_key then
      v_deferred:=v_deferred||jsonb_build_array(v_source.id::text);
      for v_cutoff in
        select (day_at+cutoff) at time zone 'Asia/Shanghai'
        from generate_series(date_trunc('day',v_coverage.coverage_through_at at time zone 'Asia/Shanghai'),date_trunc('day',least((v_active.capture_range->>'end_at')::timestamptz,p_now) at time zone 'Asia/Shanghai'),interval '1 day') day_at
        cross join (values(time '00:00'),(time '08:00'),(time '12:00'),(time '16:00'),(time '20:00')) c(cutoff)
        where (day_at+cutoff) at time zone 'Asia/Shanghai'>v_coverage.coverage_through_at and (day_at+cutoff) at time zone 'Asia/Shanghai'<=greatest(least((v_active.capture_range->>'end_at')::timestamptz,p_now),v_end_at) order by 1
      loop
        v_work:=v_work||jsonb_build_array(jsonb_build_object('window_key',to_char(v_cutoff at time zone 'Asia/Shanghai','YYYY-MM-DD"T"HH24:MI')||'+08:00','tasks',jsonb_build_array(jsonb_build_object('task_id',v_active.id::text,'status','pending'))));
      end loop;
      continue;
    end if;
    select public.create_windowed_x_sync_task(v_source.id,v_source.parameter_version,null,'scheduled',v_end_at,v_window_key) into v_task;
    v_tasks:=v_tasks||jsonb_build_array(jsonb_build_object('id',v_task->>'id','source_id',v_task->>'source_id','idempotent',coalesce((v_task->>'idempotent')::boolean,false)));
    v_work:=v_work||jsonb_build_array(jsonb_build_object('window_key',v_window_key,'tasks',jsonb_build_array(jsonb_build_object('task_id',v_task->>'id','status',case when v_task->>'status'='succeeded' then 'succeeded' when v_task->>'status'='failed' then 'terminal_failed' else 'pending' end))));
  end loop;

  select coalesce(jsonb_agg(jsonb_build_object('window_key',window_key,'tasks',tasks) order by window_key),'[]'::jsonb) into v_work
  from (select window_item->>'window_key' window_key,jsonb_agg(task_item order by task_item->>'task_id') tasks
    from jsonb_array_elements(v_work) window_item cross join lateral jsonb_array_elements(window_item->'tasks') task_item
    group by window_item->>'window_key') grouped;
  return jsonb_build_object('scheduled_at',p_now,'tasks',v_tasks,'deferred_source_ids',v_deferred,'window_work',v_work);
end $$;

revoke all on function public.create_windowed_x_sync_task_without_source_lock(uuid,text,uuid,text,timestamptz,text),public.complete_windowed_capture_range_without_source_lock(uuid,integer,uuid,jsonb),public.record_task_failure_without_source_lock(uuid,integer,jsonb,jsonb),public.create_x_terminal_recovery_task_unchecked_without_source_lock(uuid,uuid) from public,anon,authenticated,service_role;
revoke all on function public.create_bounded_x_history_task_without_source_lock(uuid,text,uuid,timestamptz,timestamptz),public.complete_bounded_x_history_range_without_source_lock(uuid,integer,uuid,jsonb),public.initialize_x_source_activation_without_source_lock(uuid,uuid,timestamptz),public.initialize_x_collection_coverage_without_source_lock(uuid,uuid,timestamptz) from public,anon,authenticated,service_role;
revoke all on function public.create_windowed_x_sync_task(uuid,text,uuid,text,timestamptz,text),public.complete_windowed_capture_range(uuid,integer,uuid,jsonb),public.record_task_failure(uuid,integer,jsonb,jsonb),public.create_x_terminal_recovery_task_unchecked(uuid,uuid),public.enqueue_due_x_tasks(uuid,timestamptz) from public,anon,authenticated;
revoke all on function public.create_bounded_x_history_task(uuid,text,uuid,timestamptz,timestamptz),public.complete_bounded_x_history_range(uuid,integer,uuid,jsonb),public.initialize_x_source_activation(uuid,uuid,timestamptz),public.initialize_x_collection_coverage(uuid,uuid,timestamptz) from public,anon,authenticated;
grant execute on function public.create_windowed_x_sync_task(uuid,text,uuid,text,timestamptz,text),public.complete_windowed_capture_range(uuid,integer,uuid,jsonb),public.record_task_failure(uuid,integer,jsonb,jsonb),public.enqueue_due_x_tasks(uuid,timestamptz) to service_role;
grant execute on function public.create_bounded_x_history_task(uuid,text,uuid,timestamptz,timestamptz),public.complete_bounded_x_history_range(uuid,integer,uuid,jsonb),public.initialize_x_source_activation(uuid,uuid,timestamptz),public.initialize_x_collection_coverage(uuid,uuid,timestamptz) to service_role;
