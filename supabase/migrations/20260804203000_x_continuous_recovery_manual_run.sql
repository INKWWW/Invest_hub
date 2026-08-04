create table public.x_manual_recovery_runs (
  id uuid primary key default gen_random_uuid(),
  requested_by uuid not null references public.profiles(id),
  target_cutoff_at timestamptz not null,
  status text not null default 'queued' check (status in ('queued', 'collecting', 'summarizing', 'succeeded', 'failed')),
  batch_id uuid unique references public.x_collection_batches(id),
  failure_code text check (failure_code in ('source_unavailable', 'terminal_recovery_failed', 'manual_batch_unavailable', 'judgement_failed')),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table public.x_manual_recovery_run_sources (
  run_id uuid not null references public.x_manual_recovery_runs(id) on delete cascade,
  source_id uuid not null references public.sources(id),
  source_display_name text not null,
  primary key (run_id, source_id)
);

create unique index x_manual_recovery_runs_one_active_cutoff
  on public.x_manual_recovery_runs(target_cutoff_at)
  where status in ('queued', 'collecting', 'summarizing');

alter table public.x_manual_recovery_runs enable row level security;
alter table public.x_manual_recovery_run_sources enable row level security;
create policy "admins read x manual recovery runs" on public.x_manual_recovery_runs for select to authenticated using (public.is_admin());
create policy "admins read x manual recovery sources" on public.x_manual_recovery_run_sources for select to authenticated using (public.is_admin());

alter function public.create_x_terminal_recovery_task(uuid, uuid) rename to create_x_terminal_recovery_task_unchecked;

create or replace function public.create_x_terminal_recovery_task_unchecked(p_failed_task_id uuid, p_requested_by uuid)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_failed public.sync_tasks%rowtype; v_source public.sources%rowtype; v_profile public.x_source_profiles%rowtype;
  v_coverage public.source_collection_coverage%rowtype; v_recovery public.sync_tasks%rowtype; v_range jsonb;
begin
  select * into v_failed from public.sync_tasks where id = p_failed_task_id for update;
  if not found or v_failed.task_type <> 'x_sync' or v_failed.status <> 'failed'
    or v_failed.collection_scope <> '{"mode":"window"}'::jsonb or v_failed.capture_range->>'mode' <> 'window'
    or v_failed.recovered_from_task_id is not null then raise exception 'terminal_x_recovery_not_available' using errcode = '22023'; end if;
  if exists (select 1 from public.sync_tasks where recovered_from_task_id = v_failed.id) then raise exception 'terminal_x_recovery_exists' using errcode = '23505'; end if;
  select * into v_source from public.sources where id = v_failed.source_id and source_type = 'x' for update;
  if not found or not v_source.enabled then raise exception 'source_disabled' using errcode = '22023'; end if;
  if v_source.parameter_version <> v_failed.parameter_version then raise exception 'source_parameter_version_mismatch' using errcode = '22023'; end if;
  select * into v_profile from public.x_source_profiles where source_id = v_failed.source_id and enabled and resolution_status = 'resolved' for update;
  if not found then raise exception 'x_source_unresolved' using errcode = '22023'; end if;
  select * into v_coverage from public.source_collection_coverage where source_id = v_failed.source_id for update;
  if not found or v_coverage.coverage_through_at <> (v_failed.capture_range->>'start_at')::timestamptz then raise exception 'terminal_x_recovery_waterline_mismatch' using errcode = '22023'; end if;
  if exists (select 1 from public.sync_tasks where source_id = v_failed.source_id and task_type = 'x_sync' and status in ('queued','leased','running','retryable_failed')) then raise exception 'source_has_active_task' using errcode = '23505'; end if;
  v_range := jsonb_set(jsonb_set(v_failed.capture_range, '{trigger}', '"recovery"'::jsonb, true), '{scheduled_window_key}', 'null'::jsonb, true);
  insert into public.sync_tasks (task_type,source_id,parameter_version,requested_by,rule_snapshot,collection_scope,capture_range,author_profile_snapshot,x_source_snapshot,recovered_from_task_id)
  values ('x_sync',v_failed.source_id,v_failed.parameter_version,p_requested_by,v_failed.rule_snapshot,'{"mode":"window"}'::jsonb,v_range,v_failed.author_profile_snapshot,v_failed.x_source_snapshot,v_failed.id)
  returning * into v_recovery;
  insert into public.sync_task_capture_progress (task_id,source_id,capture_range) values (v_recovery.id,v_recovery.source_id,v_range);
  return to_jsonb(v_recovery) || jsonb_build_object('idempotent',false);
end $$;

create or replace function public.create_x_terminal_recovery_task(p_failed_task_id uuid, p_requested_by uuid)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
begin
  if p_requested_by is null or not exists (select 1 from public.profiles where id=p_requested_by and role='admin') then raise exception 'actor_not_authorized' using errcode='42501'; end if;
  return public.create_x_terminal_recovery_task_unchecked(p_failed_task_id,p_requested_by);
end $$;

create or replace function public.enqueue_due_x_tasks(p_worker_id uuid, p_now timestamptz)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_source record; v_end_at timestamptz; v_window_key text; v_task jsonb; v_failed_task_id uuid;
  v_tasks jsonb := '[]'::jsonb; v_deferred_source_ids jsonb := '[]'::jsonb;
begin
  if p_now is null or not exists (select 1 from public.workers where id=p_worker_id and status in ('enrolled','online')) then raise exception 'worker_not_authorized' using errcode='42501'; end if;
  for v_source in select source.id,source.parameter_version,coverage.coverage_through_at from public.sources source join public.x_source_profiles profile on profile.source_id=source.id and profile.enabled and profile.resolution_status='resolved' join public.source_collection_coverage coverage on coverage.source_id=source.id where source.source_type='x' and source.enabled and source.authorized_worker_id=p_worker_id loop
    select task.id into v_failed_task_id from public.sync_tasks task where task.source_id=v_source.id and task.task_type='x_sync' and task.collection_scope->>'mode'='window' and task.status='failed' and task.recovered_from_task_id is null and (task.capture_range->>'start_at')::timestamptz=v_source.coverage_through_at and (task.capture_range->>'end_at')::timestamptz>v_source.coverage_through_at order by task.queued_at,task.id limit 1;
    if v_failed_task_id is not null then
      if not exists (select 1 from public.sync_tasks where recovered_from_task_id=v_failed_task_id) then
        select public.create_x_terminal_recovery_task_unchecked(v_failed_task_id,null) into v_task;
        v_tasks := v_tasks || jsonb_build_array(jsonb_build_object('id',v_task->>'id','source_id',v_task->>'source_id','idempotent',false));
      else v_deferred_source_ids := v_deferred_source_ids || jsonb_build_array(v_source.id::text); end if;
      continue;
    end if;
    if exists (select 1 from public.sync_tasks task where task.source_id=v_source.id and task.task_type='x_sync' and task.collection_scope->>'mode'='window' and task.status='failed' and (task.capture_range->>'start_at')::timestamptz=v_source.coverage_through_at) then v_deferred_source_ids := v_deferred_source_ids || jsonb_build_array(v_source.id::text); continue; end if;
    select min((day_at+cutoff) at time zone 'Asia/Shanghai') into v_end_at from generate_series(date_trunc('day',v_source.coverage_through_at at time zone 'Asia/Shanghai'),date_trunc('day',p_now at time zone 'Asia/Shanghai'),interval '1 day') day_at cross join (values (time '00:00'),(time '08:00'),(time '12:00'),(time '16:00'),(time '20:00')) cutoffs(cutoff) where (day_at+cutoff) at time zone 'Asia/Shanghai'>v_source.coverage_through_at and (day_at+cutoff) at time zone 'Asia/Shanghai'<=p_now;
    if v_end_at is null then continue; end if;
    v_window_key:=to_char(v_end_at at time zone 'Asia/Shanghai','YYYY-MM-DD"T"HH24:MI')||'+08:00';
    select public.create_windowed_x_sync_task(v_source.id,v_source.parameter_version,null,'scheduled',v_end_at,v_window_key) into v_task;
    v_tasks:=v_tasks||jsonb_build_array(jsonb_build_object('id',v_task->>'id','source_id',v_task->>'source_id','idempotent',coalesce((v_task->>'idempotent')::boolean,false)));
  end loop;
  return jsonb_build_object('scheduled_at',p_now,'tasks',v_tasks,'deferred_source_ids',v_deferred_source_ids);
end $$;

create function public.create_x_manual_recovery_run(p_requested_by uuid, p_now timestamptz)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_cutoff timestamptz; v_run public.x_manual_recovery_runs%rowtype;
begin
  if p_requested_by is null or p_now is null or not exists (select 1 from public.profiles where id=p_requested_by and role='admin') then raise exception 'actor_not_authorized' using errcode='42501'; end if;
  select max((day_at+cutoff) at time zone 'Asia/Shanghai') into v_cutoff from generate_series(date_trunc('day',p_now at time zone 'Asia/Shanghai')-interval '1 day',date_trunc('day',p_now at time zone 'Asia/Shanghai'),interval '1 day') day_at cross join (values (time '00:00'),(time '08:00'),(time '12:00'),(time '16:00'),(time '20:00')) cutoffs(cutoff) where (day_at+cutoff) at time zone 'Asia/Shanghai'<=p_now;
  perform pg_advisory_xact_lock(hashtextextended(v_cutoff::text,24002));
  select * into v_run from public.x_manual_recovery_runs where target_cutoff_at=v_cutoff and status in ('queued','collecting','summarizing') for update;
  if found then return jsonb_build_object('id',v_run.id::text,'status',v_run.status,'target_cutoff_at',v_run.target_cutoff_at,'idempotent',true); end if;
  insert into public.x_manual_recovery_runs(requested_by,target_cutoff_at) values(p_requested_by,v_cutoff) returning * into v_run;
  insert into public.x_manual_recovery_run_sources(run_id,source_id,source_display_name) select v_run.id,source.id,profile.display_name from public.sources source join public.x_source_profiles profile on profile.source_id=source.id and profile.enabled and profile.resolution_status='resolved' where source.source_type='x' and source.enabled;
  if not exists(select 1 from public.x_manual_recovery_run_sources where run_id=v_run.id) then raise exception 'manual_x_recovery_no_sources' using errcode='22023'; end if;
  return jsonb_build_object('id',v_run.id::text,'status',v_run.status,'target_cutoff_at',v_run.target_cutoff_at,'idempotent',false);
end $$;

create function public.advance_x_manual_recovery_runs(p_worker_id uuid, p_now timestamptz)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_run public.x_manual_recovery_runs%rowtype; v_source record; v_task_id uuid; v_batch_id uuid; v_complete boolean; v_batch_status text; v_runs jsonb:='[]'::jsonb;
begin
  if p_now is null or not exists(select 1 from public.workers where id=p_worker_id and status in ('enrolled','online')) then raise exception 'worker_not_authorized' using errcode='42501'; end if;
  for v_run in select * from public.x_manual_recovery_runs where status in ('queued','collecting','summarizing') order by created_at for update loop
    if exists(select 1 from public.x_manual_recovery_run_sources rs left join public.sources s on s.id=rs.source_id and s.source_type='x' and s.enabled left join public.x_source_profiles p on p.source_id=rs.source_id and p.enabled and p.resolution_status='resolved' left join public.source_collection_coverage c on c.source_id=rs.source_id where rs.run_id=v_run.id and (s.id is null or p.source_id is null or c.source_id is null)) then update public.x_manual_recovery_runs set status='failed',failure_code='source_unavailable',updated_at=p_now where id=v_run.id; continue; end if;
    select bool_and(c.coverage_through_at>=v_run.target_cutoff_at) into v_complete from public.x_manual_recovery_run_sources rs join public.source_collection_coverage c on c.source_id=rs.source_id where rs.run_id=v_run.id;
    if not coalesce(v_complete,false) then update public.x_manual_recovery_runs set status='collecting',updated_at=p_now where id=v_run.id; v_runs:=v_runs||jsonb_build_array(jsonb_build_object('id',v_run.id::text,'status','collecting')); continue; end if;
    if v_run.batch_id is null then
      insert into public.x_collection_batches(scheduled_window_key,natural_date,cutoff_at,settlement_deadline_at,status) values ('manual:'||v_run.id::text,public.x_collection_batch_logical_date(v_run.target_cutoff_at),v_run.target_cutoff_at,p_now,'collecting') returning id into v_batch_id;
      for v_source in select rs.source_id,rs.source_display_name from public.x_manual_recovery_run_sources rs where rs.run_id=v_run.id loop
        select task.id into v_task_id from public.sync_tasks task where task.source_id=v_source.source_id and task.task_type='x_sync' and task.status='succeeded' and task.collection_scope->>'mode'='window' and (task.capture_range->>'end_at')::timestamptz=v_run.target_cutoff_at order by task.updated_at desc limit 1;
        if v_task_id is null then update public.x_manual_recovery_runs set status='failed',failure_code='manual_batch_unavailable',updated_at=p_now where id=v_run.id; exit; end if;
        insert into public.x_collection_batch_sources(batch_id,source_id,source_display_name,x_sync_task_id) values(v_batch_id,v_source.source_id,v_source.source_display_name,v_task_id);
      end loop;
      if (select status from public.x_manual_recovery_runs where id=v_run.id)='failed' then delete from public.x_collection_batches where id=v_batch_id; continue; end if;
      perform public.settle_x_collection_batch(v_batch_id,p_now);
      select status into v_batch_status from public.x_collection_batches where id=v_batch_id;
      update public.x_manual_recovery_runs set batch_id=v_batch_id,status=case when v_batch_status='succeeded' then 'succeeded' else 'summarizing' end,updated_at=p_now where id=v_run.id;
    else
      select status into v_batch_status from public.x_collection_batches where id=v_run.batch_id;
      update public.x_manual_recovery_runs set status=case when v_batch_status='succeeded' then 'succeeded' when v_batch_status='judgement_failed' then 'failed' else 'summarizing' end,failure_code=case when v_batch_status='judgement_failed' then 'judgement_failed' else failure_code end,updated_at=p_now where id=v_run.id;
    end if;
    select status into v_batch_status from public.x_manual_recovery_runs where id=v_run.id;
    v_runs:=v_runs||jsonb_build_array(jsonb_build_object('id',v_run.id::text,'status',v_batch_status));
  end loop;
  return jsonb_build_object('runs',v_runs);
end $$;

revoke all on function public.create_x_terminal_recovery_task_unchecked(uuid,uuid), public.advance_x_manual_recovery_runs(uuid,timestamptz) from public,anon,authenticated;
revoke all on function public.create_x_terminal_recovery_task(uuid,uuid), public.create_x_manual_recovery_run(uuid,timestamptz) from public,anon,authenticated;
grant execute on function public.create_x_terminal_recovery_task(uuid,uuid), public.create_x_manual_recovery_run(uuid,timestamptz) to service_role;
grant execute on function public.advance_x_manual_recovery_runs(uuid,timestamptz) to service_role;
