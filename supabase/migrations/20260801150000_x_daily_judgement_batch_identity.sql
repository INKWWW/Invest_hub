-- A Shanghai 00:00 cutoff closes the preceding natural day.  Keep that
-- identity in one immutable helper so batch creation, constraints and segment
-- matching cannot drift independently.
create function public.x_collection_batch_logical_date(p_cutoff_at timestamptz)
returns date
language sql
immutable
strict
set search_path = public
as $$
  select case
    when (p_cutoff_at at time zone 'Asia/Shanghai')::time = time '00:00'
      then (p_cutoff_at at time zone 'Asia/Shanghai')::date - 1
    else (p_cutoff_at at time zone 'Asia/Shanghai')::date
  end
$$;

do $$
declare
  v_constraint_name text;
begin
  select constraint_row.conname
  into v_constraint_name
  from pg_constraint constraint_row
  where constraint_row.conrelid = 'public.x_collection_batches'::regclass
    and constraint_row.contype = 'c'
    and pg_get_expr(constraint_row.conbin, constraint_row.conrelid) like '%natural_date%cutoff_at%'
  limit 1;

  if v_constraint_name is not null then
    execute format('alter table public.x_collection_batches drop constraint %I', v_constraint_name);
  end if;
end;
$$;

alter table public.x_collection_batches disable trigger x_collection_batches_immutable;
update public.x_collection_batches
set natural_date = public.x_collection_batch_logical_date(cutoff_at)
where natural_date <> public.x_collection_batch_logical_date(cutoff_at);
alter table public.x_collection_batches enable trigger x_collection_batches_immutable;

alter table public.x_collection_batches
  add constraint x_collection_batches_logical_date_check
  check (natural_date = public.x_collection_batch_logical_date(cutoff_at));

-- The scheduler caller is an authority to dispatch X work, not a filter for
-- the batch's source universe.  Every enabled/resolved X source is frozen for
-- every due cutoff.  Only a source whose next exact range matches that cutoff
-- receives a batch-bound collection task; every other source remains visible
-- as an explicit safe exclusion.
create or replace function public.ensure_due_x_collection_batches_core(p_worker_id uuid, p_now timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_window record;
  v_source record;
  v_batch public.x_collection_batches%rowtype;
  v_task jsonb;
  v_batches jsonb := '[]'::jsonb;
begin
  if p_now is null
     or not exists (
       select 1
       from public.workers worker
       where worker.id = p_worker_id
         and worker.status in ('enrolled', 'online')
         and worker.capabilities @> array['x_sync']::text[]
     )
     or not exists (
       select 1
       from public.sources source
       join public.x_source_profiles profile on profile.source_id = source.id
       where source.authorized_worker_id = p_worker_id
         and source.source_type = 'x'
         and source.enabled
         and profile.enabled
         and profile.resolution_status = 'resolved'
     ) then
    raise exception 'worker_not_authorized' using errcode = '42501';
  end if;

  for v_window in
    with source_due as (
      select due.end_at
      from public.sources source
      join public.x_source_profiles profile on profile.source_id = source.id
        and profile.enabled and profile.resolution_status = 'resolved'
      join public.source_collection_coverage coverage on coverage.source_id = source.id
      cross join lateral (
        select min((day_at + cutoff) at time zone 'Asia/Shanghai') as end_at
        from generate_series(
          date_trunc('day', coverage.coverage_through_at at time zone 'Asia/Shanghai'),
          date_trunc('day', p_now at time zone 'Asia/Shanghai'),
          interval '1 day'
        ) as day_at
        cross join (values (time '00:00'), (time '08:00'), (time '12:00'), (time '16:00'), (time '20:00')) as cutoffs(cutoff)
        where (day_at + cutoff) at time zone 'Asia/Shanghai' > coverage.coverage_through_at
          and (day_at + cutoff) at time zone 'Asia/Shanghai' <= p_now
      ) due
      where source.source_type = 'x' and source.enabled and due.end_at is not null
    )
    select distinct end_at from source_due order by end_at
  loop
    perform pg_advisory_xact_lock(hashtextextended(v_window.end_at::text, 24001));
    select * into v_batch
    from public.x_collection_batches
    where scheduled_window_key = to_char(v_window.end_at at time zone 'Asia/Shanghai', 'YYYY-MM-DD"T"HH24:MI') || '+08:00'
    for update;

    if not found then
      insert into public.x_collection_batches (
        scheduled_window_key, natural_date, cutoff_at, settlement_deadline_at, status
      ) values (
        to_char(v_window.end_at at time zone 'Asia/Shanghai', 'YYYY-MM-DD"T"HH24:MI') || '+08:00',
        public.x_collection_batch_logical_date(v_window.end_at),
        v_window.end_at,
        v_window.end_at + interval '2 hours',
        'collecting'
      ) returning * into v_batch;

      for v_source in
        select
          source.id,
          source.parameter_version,
          profile.display_name,
          coverage.coverage_through_at,
          due.end_at
        from public.sources source
        join public.x_source_profiles profile on profile.source_id = source.id
          and profile.enabled and profile.resolution_status = 'resolved'
        left join public.source_collection_coverage coverage on coverage.source_id = source.id
        left join lateral (
          select min((day_at + cutoff) at time zone 'Asia/Shanghai') as end_at
          from generate_series(
            date_trunc('day', coverage.coverage_through_at at time zone 'Asia/Shanghai'),
            date_trunc('day', p_now at time zone 'Asia/Shanghai'),
            interval '1 day'
          ) as day_at
          cross join (values (time '00:00'), (time '08:00'), (time '12:00'), (time '16:00'), (time '20:00')) as cutoffs(cutoff)
          where coverage.coverage_through_at is not null
            and (day_at + cutoff) at time zone 'Asia/Shanghai' > coverage.coverage_through_at
            and (day_at + cutoff) at time zone 'Asia/Shanghai' <= p_now
        ) due on true
        where source.source_type = 'x' and source.enabled
        order by source.id
      loop
        if v_source.coverage_through_at is null then
          insert into public.x_collection_batch_sources (
            batch_id, source_id, source_display_name, settlement_status, exclusion_code, settled_at
          ) values (
            v_batch.id, v_source.id, v_source.display_name,
            'excluded', 'coverage_not_initialized', p_now
          );
          continue;
        end if;

        if v_source.end_at is distinct from v_window.end_at then
          insert into public.x_collection_batch_sources (
            batch_id, source_id, source_display_name, settlement_status, exclusion_code, settled_at
          ) values (
            v_batch.id, v_source.id, v_source.display_name,
            'excluded',
            case
              when v_source.end_at < v_window.end_at then 'source_behind_cutoff'
              else 'source_not_due_for_cutoff'
            end,
            p_now
          );
          continue;
        end if;

        insert into public.x_collection_batch_sources (batch_id, source_id, source_display_name)
        values (v_batch.id, v_source.id, v_source.display_name);
      end loop;

      for v_source in
        select batch_source.source_id
        from public.x_collection_batch_sources batch_source
        where batch_source.batch_id = v_batch.id
          and batch_source.settlement_status = 'pending'
        order by batch_source.source_id
      loop
        if exists (
          select 1
          from public.sync_tasks task
          where task.source_id = v_source.source_id
            and task.task_type = 'x_sync'
            and task.status in ('queued', 'leased', 'running', 'retryable_failed')
            and (
              task.collection_scope->>'mode' <> 'window'
              or task.capture_range->>'trigger' <> 'scheduled'
              or task.capture_range->>'scheduled_window_key' <> v_batch.scheduled_window_key
            )
        ) then
          update public.x_collection_batch_sources
          set settlement_status = 'excluded', exclusion_code = 'collection_conflict', settled_at = p_now
          where batch_id = v_batch.id and source_id = v_source.source_id;
          continue;
        end if;

        v_task := null;
        select to_jsonb(task) || jsonb_build_object('idempotent', true)
        into v_task
        from public.sync_tasks task
        join public.source_collection_coverage coverage on coverage.source_id = task.source_id
        where task.source_id = v_source.source_id
          and task.task_type = 'x_sync'
          and task.collection_scope->>'mode' = 'window'
          and task.status = 'failed'
          and (task.capture_range->>'start_at')::timestamptz = coverage.coverage_through_at
          and (task.capture_range->>'end_at')::timestamptz = v_window.end_at
          and task.capture_range->>'trigger' = 'scheduled'
          and task.capture_range->>'scheduled_window_key' = v_batch.scheduled_window_key
        order by task.queued_at, task.id
        limit 1;

        if v_task is null then
          select public.create_windowed_x_sync_task(
            v_source.source_id,
            (select parameter_version from public.sources where id = v_source.source_id),
            null,
            'scheduled',
            v_window.end_at,
            v_batch.scheduled_window_key
          ) into v_task;
        end if;

        update public.sync_tasks
        set collection_batch_id = v_batch.id
        where id = (v_task->>'id')::uuid;
        update public.x_collection_batch_sources
        set x_sync_task_id = (v_task->>'id')::uuid
        where batch_id = v_batch.id and source_id = v_source.source_id;
      end loop;
    end if;

    v_batches := v_batches || jsonb_build_array(jsonb_build_object(
      'batch_id', v_batch.id::text,
      'scheduled_window_key', v_batch.scheduled_window_key
    ));
  end loop;

  return jsonb_build_object('scheduled_at', p_now, 'batches', v_batches);
end;
$$;

create or replace function public.settle_x_collection_batch(p_batch_id uuid, p_now timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_batch public.x_collection_batches%rowtype;
  v_source record;
  v_status text;
  v_exclusion_code text;
  v_pending integer;
  v_included integer;
  v_excluded integer;
  v_no_new integer;
  v_coverage_status text;
  v_snapshot jsonb;
begin
  if p_now is null then
    raise exception 'invalid_x_collection_batch_settlement' using errcode = '22023';
  end if;
  select * into v_batch from public.x_collection_batches where id = p_batch_id for update;
  if not found then
    raise exception 'x_collection_batch_not_found' using errcode = '22023';
  end if;

  for v_source in
    select batch_source.*, task.status as task_status
    from public.x_collection_batch_sources batch_source
    join public.sync_tasks task on task.id = batch_source.x_sync_task_id
    where batch_source.batch_id = p_batch_id and batch_source.settlement_status = 'pending'
    for update of batch_source, task
  loop
    v_status := null;
    v_exclusion_code := null;
    if v_source.task_status = 'succeeded' and exists (
      select 1
      from public.x_daily_viewpoint_segments segment
      where segment.source_id = v_source.source_id
        and segment.range_task_id = v_source.x_sync_task_id
        and segment.natural_date = v_batch.natural_date
    ) then
      v_status := 'included';
    elsif v_source.task_status = 'succeeded' and exists (
      select 1
      from public.task_attempts attempt
      where attempt.task_id = v_source.x_sync_task_id
        and attempt.status = 'succeeded'
        and coalesce((attempt.result->>'no_new_data')::boolean, false)
    ) then
      v_status := 'no_new_information';
    elsif v_source.task_status in ('failed', 'cancelled') then
      v_status := 'excluded';
      v_exclusion_code := 'terminal_failure';
    elsif p_now >= v_batch.settlement_deadline_at then
      v_status := 'excluded';
      v_exclusion_code := 'settlement_deadline_exceeded';
    end if;
    if v_status is not null then
      update public.x_collection_batch_sources
      set settlement_status = v_status, exclusion_code = v_exclusion_code, settled_at = p_now
      where batch_id = p_batch_id and source_id = v_source.source_id;
    end if;
  end loop;

  select
    count(*) filter (where settlement_status = 'pending'),
    count(*) filter (where settlement_status = 'included'),
    count(*) filter (where settlement_status = 'excluded'),
    count(*) filter (where settlement_status = 'no_new_information')
  into v_pending, v_included, v_excluded, v_no_new
  from public.x_collection_batch_sources where batch_id = p_batch_id;
  if v_pending > 0 then
    return jsonb_build_object('batch_id', p_batch_id::text, 'settled', false, 'coverage_status', null);
  end if;

  v_coverage_status := case
    when v_excluded > 0 then 'partial'
    when v_included = 0 then 'no_new_information'
    else 'complete'
  end;
  if v_included > 0 then
    update public.x_collection_batches set status = 'judgement_pending' where id = p_batch_id;
    insert into public.x_daily_judgement_runs (batch_id, status, available_at)
    values (p_batch_id, 'queued', p_now)
    on conflict do nothing;
  else
    select jsonb_build_object('sources', coalesce(jsonb_agg(jsonb_build_object(
      'source_id', source_id::text,
      'display_name', source_display_name,
      'settlement_status', settlement_status,
      'segments', '[]'::jsonb
    ) order by source_id), '[]'::jsonb))
    into v_snapshot
    from public.x_collection_batch_sources where batch_id = p_batch_id;
    insert into public.x_daily_judgement_versions (
      batch_id, revision, coverage_status, input_snapshot, output, provider, prompt_version, schema_version
    ) values (
      p_batch_id,
      (select coalesce(max(revision), 0) + 1 from public.x_daily_judgement_versions where batch_id = p_batch_id),
      v_coverage_status,
      v_snapshot,
      '{"stock_viewpoints":[],"market_industry_viewpoints":[],"uncertainties":[]}'::jsonb,
      'codex_cli',
      'v2-x-cross-blogger-1',
      'v2-x-cross-blogger'
    ) on conflict do nothing;
    update public.x_collection_batches set status = 'succeeded' where id = p_batch_id;
  end if;
  return jsonb_build_object('batch_id', p_batch_id::text, 'settled', true, 'coverage_status', v_coverage_status);
end;
$$;

create or replace function public.claim_next_x_daily_judgement(p_worker_id uuid, p_now timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_run public.x_daily_judgement_runs%rowtype;
  v_coverage_status text;
begin
  if p_now is null or not exists (
    select 1
    from public.workers worker
    where worker.id = p_worker_id
      and worker.status in ('enrolled', 'online')
      and worker.capabilities @> array['x_sync']::text[]
  ) or not exists (
    select 1
    from public.sources source
    where source.source_type = 'x' and source.authorized_worker_id = p_worker_id
  ) then
    raise exception 'worker_not_authorized' using errcode = '42501';
  end if;

  update public.x_daily_judgement_runs
  set status = 'retryable_failed', lease_owner = null, lease_expires_at = null, available_at = p_now,
      failure_class = coalesce(failure_class, 'lease_expired')
  where status in ('leased', 'running') and lease_expires_at <= p_now;

  select run.* into v_run
  from public.x_daily_judgement_runs run
  where run.status in ('queued', 'retryable_failed')
    and run.available_at <= p_now
    and exists (
      select 1
      from public.x_collection_batch_sources batch_source
      join public.sources source on source.id = batch_source.source_id
      where batch_source.batch_id = run.batch_id
        and source.source_type = 'x'
        and source.authorized_worker_id = p_worker_id
    )
  order by run.available_at, run.created_at, run.id
  for update of run skip locked
  limit 1;
  if not found then return null; end if;

  update public.x_daily_judgement_runs
  set status = 'leased', attempt = v_run.attempt + 1, lease_owner = p_worker_id,
      lease_expires_at = p_now + interval '10 minutes', failure_class = null
  where id = v_run.id
  returning * into v_run;

  select case when count(*) filter (where settlement_status = 'excluded') > 0 then 'partial' else 'complete' end
  into v_coverage_status
  from public.x_collection_batch_sources where batch_id = v_run.batch_id;

  return jsonb_build_object(
    'run_id', v_run.id::text,
    'attempt', v_run.attempt,
    'lease_expires_at', v_run.lease_expires_at,
    'batch', (
      select jsonb_build_object(
        'id', batch.id::text,
        'natural_date', batch.natural_date,
        'cutoff_at', batch.cutoff_at,
        'coverage_status', v_coverage_status
      )
      from public.x_collection_batches batch where batch.id = v_run.batch_id
    )
  );
end;
$$;

revoke all on function public.x_collection_batch_logical_date(timestamptz) from public, anon, authenticated;
grant execute on function public.x_collection_batch_logical_date(timestamptz) to service_role;
