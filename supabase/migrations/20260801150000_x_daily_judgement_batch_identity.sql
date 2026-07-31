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

-- A batch that already produced settlement or judgement evidence has an
-- immutable historical identity.  Re-dating it would silently relabel that
-- evidence, so migration must stop before touching any such row.
create function public.assert_x_collection_batch_identity_migration_safe()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1
    from public.x_collection_batches batch
    where batch.natural_date <> public.x_collection_batch_logical_date(batch.cutoff_at)
      and (
        batch.status <> 'collecting'
        or exists (
          select 1
          from public.x_collection_batch_sources batch_source
          where batch_source.batch_id = batch.id
            and (
              batch_source.settlement_status <> 'pending'
              or batch_source.settled_at is not null
            )
        )
        or exists (
          select 1 from public.x_daily_judgement_runs run
          where run.batch_id = batch.id
        )
        or exists (
          select 1 from public.x_daily_judgement_versions version
          where version.batch_id = batch.id
        )
      )
  ) then
    raise exception 'unsafe_legacy_x_collection_batch_identity' using errcode = '55000';
  end if;
end;
$$;

-- Hold the strongest table locks for the remainder of the migration
-- transaction.  The fixed order is part of the migration authority: no
-- settlement or judgement DML may commit between the legacy identity read and
-- the natural-date correction below.
create function public.lock_and_assert_x_collection_batch_identity_migration_safe()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  lock table public.x_collection_batches in access exclusive mode;
  lock table public.x_collection_batch_sources in access exclusive mode;
  lock table public.x_daily_judgement_runs in access exclusive mode;
  lock table public.x_daily_judgement_versions in access exclusive mode;
  perform public.assert_x_collection_batch_identity_migration_safe();
end;
$$;

select public.lock_and_assert_x_collection_batch_identity_migration_safe();

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
where natural_date <> public.x_collection_batch_logical_date(cutoff_at)
  and status = 'collecting'
  and not exists (
    select 1
    from public.x_collection_batch_sources batch_source
    where batch_source.batch_id = x_collection_batches.id
      and (
        batch_source.settlement_status <> 'pending'
        or batch_source.settled_at is not null
      )
  )
  and not exists (
    select 1 from public.x_daily_judgement_runs run
    where run.batch_id = x_collection_batches.id
  )
  and not exists (
    select 1 from public.x_daily_judgement_versions version
    where version.batch_id = x_collection_batches.id
  );
alter table public.x_collection_batches enable trigger x_collection_batches_immutable;

alter table public.x_collection_batches
  add constraint x_collection_batches_logical_date_check
  check (natural_date = public.x_collection_batch_logical_date(cutoff_at));

-- No pre-remediation batch can prove that its frozen source universe was
-- complete: the old scheduler selected sources through the calling Worker and
-- per-source next-cutoff filters.  Mark every existing row fail-closed without
-- filling it from today's source configuration; only rows inserted after this
-- migration receive the verified default.
alter table public.x_collection_batches
  add column snapshot_completeness text not null default 'legacy_unverified'
    check (snapshot_completeness in ('complete', 'legacy_unverified'));
alter table public.x_collection_batches
  alter column snapshot_completeness set default 'complete';
update public.x_collection_batches
set status = 'judgement_failed'
where snapshot_completeness = 'legacy_unverified'
  and status <> 'judgement_failed';

create or replace function public.reject_x_collection_batch_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.scheduled_window_key is distinct from old.scheduled_window_key
     or new.natural_date is distinct from old.natural_date
     or new.cutoff_at is distinct from old.cutoff_at
     or new.settlement_deadline_at is distinct from old.settlement_deadline_at
     or new.created_at is distinct from old.created_at
     or (
       new.snapshot_completeness is distinct from old.snapshot_completeness
       and not (
         old.snapshot_completeness = 'complete'
         and new.snapshot_completeness = 'legacy_unverified'
       )
     ) then
    raise exception 'x_collection_batch_immutable' using errcode = '55000';
  end if;
  return new;
end;
$$;

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
  v_unavailable_batches jsonb := '[]'::jsonb;
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

    if found and v_batch.snapshot_completeness <> 'complete' then
      update public.x_collection_batches
      set status = 'judgement_failed'
      where id = v_batch.id and status <> 'judgement_failed';
      v_unavailable_batches := v_unavailable_batches || jsonb_build_array(jsonb_build_object(
        'batch_id', v_batch.id::text,
        'scheduled_window_key', v_batch.scheduled_window_key,
        'reason', 'legacy_snapshot_unverified'
      ));
      continue;
    end if;

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

  return jsonb_build_object(
    'scheduled_at', p_now,
    'batches', v_batches,
    'unavailable_batches', v_unavailable_batches
  );
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
  if v_batch.snapshot_completeness <> 'complete' then
    update public.x_collection_batches
    set status = 'judgement_failed'
    where id = p_batch_id and status <> 'judgement_failed';
    return jsonb_build_object(
      'batch_id', p_batch_id::text,
      'settled', false,
      'coverage_status', null,
      'legacy_snapshot_unverified', true
    );
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

-- Completion and the immutable version trigger consume one canonical snapshot
-- builder.  A segment is admissible only when source, range task and the
-- batch's logical natural date all match.
create function public.build_x_daily_judgement_input_snapshot(p_batch_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_batch public.x_collection_batches%rowtype;
  v_snapshot jsonb;
  v_has_included boolean;
begin
  select * into v_batch
  from public.x_collection_batches
  where id = p_batch_id;
  if not found or v_batch.snapshot_completeness <> 'complete' then
    raise exception 'x_collection_batch_snapshot_unavailable' using errcode = '55000';
  end if;

  select exists(
    select 1 from public.x_collection_batch_sources
    where batch_id = p_batch_id and settlement_status = 'included'
  ) into v_has_included;

  if v_has_included then
    select jsonb_build_object('sources', coalesce(jsonb_agg(jsonb_build_object(
      'source_id', batch_source.source_id::text,
      'display_name', batch_source.source_display_name,
      'settlement_status', batch_source.settlement_status,
      'segments', coalesce((
        select jsonb_agg(jsonb_build_object(
          'segment_id', segment.id::text,
          'analysis_ids', segment.post_analysis_refs,
          'evidence_post_ids', segment.evidence_refs
        ) order by segment.id)
        from public.x_daily_viewpoint_segments segment
        where segment.source_id = batch_source.source_id
          and segment.range_task_id = batch_source.x_sync_task_id
          and segment.natural_date = v_batch.natural_date
      ), '[]'::jsonb)
    ) order by batch_source.source_id), '[]'::jsonb))
    into v_snapshot
    from public.x_collection_batch_sources batch_source
    where batch_source.batch_id = p_batch_id
      and batch_source.settlement_status = 'included';
  else
    select jsonb_build_object('sources', coalesce(jsonb_agg(jsonb_build_object(
      'source_id', source_id::text,
      'display_name', source_display_name,
      'settlement_status', settlement_status,
      'segments', '[]'::jsonb
    ) order by source_id), '[]'::jsonb))
    into v_snapshot
    from public.x_collection_batch_sources
    where batch_id = p_batch_id;
  end if;

  return v_snapshot;
end;
$$;

create or replace function public.enforce_x_daily_judgement_version()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_expected_revision integer;
  v_expected_snapshot jsonb;
  v_evidence_id text;
  v_source_id text;
  v_analysis_id text;
  v_allowed_evidence text[];
  v_allowed_sources text[];
  v_allowed_analysis text[];
begin
  select coalesce(max(revision), 0) + 1 into v_expected_revision
  from public.x_daily_judgement_versions where batch_id = new.batch_id;
  if new.revision <> v_expected_revision then
    raise exception 'invalid_x_daily_judgement_revision' using errcode = '23514';
  end if;

  perform public.validate_x_daily_judgement_input_snapshot(new.input_snapshot);
  if new.coverage_status = 'complete' and jsonb_array_length(new.input_snapshot->'sources') = 0 then
    raise exception 'invalid_x_daily_judgement_evidence' using errcode = '22023';
  end if;
  perform public.validate_x_daily_judgement_output(new.output);

  v_expected_snapshot := public.build_x_daily_judgement_input_snapshot(new.batch_id);
  if new.input_snapshot <> v_expected_snapshot then
    raise exception 'invalid_x_daily_judgement_snapshot' using errcode = '22023';
  end if;

  select coalesce(array_agg(distinct value), '{}') into v_allowed_sources
  from jsonb_path_query(new.input_snapshot, '$.sources[*].source_id') as value_json(value_json)
  cross join lateral (select trim(both '"' from value_json::text) as value) safe;
  select coalesce(array_agg(distinct value), '{}') into v_allowed_evidence
  from jsonb_path_query(new.input_snapshot, '$.sources[*].segments[*].evidence_post_ids[*]') as value_json(value_json)
  cross join lateral (select trim(both '"' from value_json::text) as value) safe;
  select coalesce(array_agg(distinct analysis_value.value), '{}') into v_allowed_analysis
  from jsonb_path_query(new.input_snapshot, '$.sources[*].segments[*].analysis_ids[*]') as analysis_json(value_json)
  cross join lateral jsonb_to_record(analysis_json.value_json) as analysis_ref(post_id text, analysis_version integer)
  cross join lateral (select analysis_ref.post_id || '@' || analysis_ref.analysis_version::text as value) analysis_value;

  for v_source_id in
    select source.value
    from jsonb_array_elements(coalesce(new.output->'stock_viewpoints', '[]'::jsonb)) item
    cross join lateral jsonb_array_elements_text(item->'supporting_source_ids') source(value)
    union all
    select source.value
    from jsonb_array_elements(coalesce(new.output->'stock_viewpoints', '[]'::jsonb)) item
    cross join lateral jsonb_array_elements_text(item->'dissenting_source_ids') source(value)
    union all
    select source.value
    from jsonb_array_elements(coalesce(new.output->'market_industry_viewpoints', '[]'::jsonb)) item
    cross join lateral jsonb_array_elements_text(item->'supporting_source_ids') source(value)
    union all
    select source.value
    from jsonb_array_elements(coalesce(new.output->'market_industry_viewpoints', '[]'::jsonb)) item
    cross join lateral jsonb_array_elements_text(item->'dissenting_source_ids') source(value)
  loop
    if not v_source_id = any(v_allowed_sources) then
      raise exception 'invalid_x_daily_judgement_evidence' using errcode = '22023';
    end if;
  end loop;

  for v_analysis_id in
    select analysis.value
    from jsonb_array_elements(coalesce(new.output->'stock_viewpoints', '[]'::jsonb)) item
    cross join lateral jsonb_array_elements_text(item->'analysis_ids') analysis(value)
    union all
    select analysis.value
    from jsonb_array_elements(coalesce(new.output->'market_industry_viewpoints', '[]'::jsonb)) item
    cross join lateral jsonb_array_elements_text(item->'analysis_ids') analysis(value)
  loop
    if not v_analysis_id = any(v_allowed_analysis) then
      raise exception 'invalid_x_daily_judgement_evidence' using errcode = '22023';
    end if;
  end loop;

  for v_evidence_id in
    select evidence.value
    from jsonb_array_elements(coalesce(new.output->'stock_viewpoints', '[]'::jsonb)) item
    cross join lateral jsonb_array_elements_text(item->'evidence_post_ids') evidence(value)
    union all
    select evidence.value
    from jsonb_array_elements(coalesce(new.output->'market_industry_viewpoints', '[]'::jsonb)) item
    cross join lateral jsonb_array_elements_text(item->'evidence_post_ids') evidence(value)
  loop
    if not v_evidence_id = any(v_allowed_evidence) then
      raise exception 'invalid_x_daily_judgement_evidence' using errcode = '22023';
    end if;
  end loop;
  return new;
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
  join public.x_collection_batches batch on batch.id = run.batch_id
  where run.status in ('queued', 'retryable_failed')
    and run.available_at <= p_now
    and batch.snapshot_completeness = 'complete'
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

create or replace function public.get_x_daily_judgement_context(
  p_run_id uuid, p_attempt integer, p_worker_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_run public.x_daily_judgement_runs%rowtype;
  v_batch public.x_collection_batches%rowtype;
  v_context jsonb;
begin
  select * into v_run from public.x_daily_judgement_runs where id = p_run_id;
  if not found or p_attempt is null or p_worker_id is null or v_run.attempt <> p_attempt
     or v_run.status not in ('leased', 'running') or v_run.lease_owner <> p_worker_id
     or v_run.lease_expires_at <= timezone('utc', now()) then
    raise exception 'lease_mismatch' using errcode = 'PT409';
  end if;
  select * into v_batch from public.x_collection_batches where id = v_run.batch_id;
  if not found or v_batch.snapshot_completeness <> 'complete' then
    raise exception 'x_collection_batch_snapshot_unavailable' using errcode = '55000';
  end if;

  select jsonb_build_object(
    'run_id', v_run.id::text,
    'attempt', v_run.attempt,
    'prompt_version', 'v2-x-cross-blogger-1',
    'sources', coalesce((
      select jsonb_agg(jsonb_build_object(
        'source_id', batch_source.source_id::text,
        'display_name', batch_source.source_display_name,
        'window_segments', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', segment.id::text,
            'occurred_from_at', segment.occurred_from_at,
            'occurred_through_at', segment.occurred_through_at,
            'viewpoints', segment.window_viewpoints,
            'uncertainties', '[]'::jsonb,
            'analyses', coalesce((
              select jsonb_agg(jsonb_build_object(
                'post_id', message.external_message_id || '@' || analysis.analysis_version::text,
                'blogger_viewpoint', analysis.blogger_viewpoint,
                'arguments', analysis.arguments,
                'quoted_post_viewpoint', analysis.quoted_post_viewpoint,
                'uncertainties', analysis.uncertainties,
                'evidence_post_ids', analysis.evidence_refs
              ) order by message.external_message_id)
              from jsonb_to_recordset(segment.post_analysis_refs) as ref(post_id text, analysis_version integer)
              join public.canonical_messages message
                on message.source_id = batch_source.source_id and message.external_message_id = ref.post_id
              join public.x_post_analyses analysis
                on analysis.canonical_message_id = message.id and analysis.analysis_version = ref.analysis_version
            ), '[]'::jsonb)
          ) order by segment.id)
          from public.x_daily_viewpoint_segments segment
          where segment.source_id = batch_source.source_id
            and segment.range_task_id = batch_source.x_sync_task_id
            and segment.natural_date = v_batch.natural_date
        ), '[]'::jsonb)
      ) order by batch_source.source_id)
      from public.x_collection_batch_sources batch_source
      where batch_source.batch_id = v_run.batch_id and batch_source.settlement_status = 'included'
    ), '[]'::jsonb),
    'excluded_sources', coalesce((
      select jsonb_agg(jsonb_build_object(
        'source_id', batch_source.source_id::text,
        'display_name', batch_source.source_display_name,
        'reason', batch_source.exclusion_code
      ) order by batch_source.source_id)
      from public.x_collection_batch_sources batch_source
      where batch_source.batch_id = v_run.batch_id and batch_source.settlement_status = 'excluded'
    ), '[]'::jsonb)
  ) into v_context;
  return v_context;
end;
$$;

create or replace function public.complete_x_daily_judgement(
  p_run_id uuid, p_attempt integer, p_worker_id uuid, p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_run public.x_daily_judgement_runs%rowtype;
  v_batch public.x_collection_batches%rowtype;
  v_coverage_status text;
  v_snapshot jsonb;
  v_output jsonb;
begin
  select * into v_run from public.x_daily_judgement_runs where id = p_run_id for update;
  if not found or p_attempt is null or p_worker_id is null or v_run.attempt <> p_attempt
     or v_run.status not in ('leased', 'running') or v_run.lease_owner <> p_worker_id
     or v_run.lease_expires_at <= timezone('utc', now()) then
    raise exception 'lease_mismatch' using errcode = 'PT409';
  end if;
  select * into v_batch from public.x_collection_batches where id = v_run.batch_id for update;
  if not found or v_batch.snapshot_completeness <> 'complete' then
    raise exception 'x_collection_batch_snapshot_unavailable' using errcode = '55000';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object'
     or p_payload->>'schema_version' <> 'v2-x-cross-blogger'
     or p_payload->>'provider' not in ('codex_cli', 'mock')
     or p_payload->>'prompt_version' <> 'v2-x-cross-blogger-1'
     or not (p_payload ? 'model_reported')
     or (p_payload->'model_reported' <> 'null'::jsonb and (
       jsonb_typeof(p_payload->'model_reported') <> 'string'
       or not public.x_daily_judgement_safe_text(p_payload->>'model_reported', 160)
     ))
     or jsonb_typeof(p_payload->'stock_viewpoints') <> 'array'
     or jsonb_typeof(p_payload->'market_industry_viewpoints') <> 'array'
     or jsonb_typeof(p_payload->'uncertainties') <> 'array' then
    raise exception 'invalid_x_daily_judgement_completion' using errcode = '22023';
  end if;

  select case when count(*) filter (where settlement_status = 'excluded') > 0 then 'partial' else 'complete' end
  into v_coverage_status
  from public.x_collection_batch_sources where batch_id = v_run.batch_id;
  v_snapshot := public.build_x_daily_judgement_input_snapshot(v_run.batch_id);
  v_output := p_payload - 'schema_version' - 'provider' - 'model_reported' - 'prompt_version';
  insert into public.x_daily_judgement_versions (
    batch_id, revision, coverage_status, input_snapshot, output, provider, model_reported, prompt_version, schema_version
  ) values (
    v_run.batch_id,
    (select coalesce(max(revision), 0) + 1 from public.x_daily_judgement_versions where batch_id = v_run.batch_id),
    v_coverage_status, v_snapshot, v_output, p_payload->>'provider', nullif(p_payload->>'model_reported', ''),
    p_payload->>'prompt_version', p_payload->>'schema_version'
  );
  update public.x_daily_judgement_runs
  set status = 'succeeded', lease_owner = null, lease_expires_at = null
  where id = v_run.id;
  update public.x_collection_batches set status = 'succeeded' where id = v_run.batch_id;
  return jsonb_build_object('run_id', v_run.id::text, 'attempt', v_run.attempt, 'status', 'succeeded');
end;
$$;

revoke all on function public.x_collection_batch_logical_date(timestamptz) from public, anon, authenticated;
grant execute on function public.x_collection_batch_logical_date(timestamptz) to service_role;
revoke all on function public.assert_x_collection_batch_identity_migration_safe(),
  public.lock_and_assert_x_collection_batch_identity_migration_safe(),
  public.build_x_daily_judgement_input_snapshot(uuid)
  from public, anon, authenticated;
grant execute on function public.build_x_daily_judgement_input_snapshot(uuid)
  to service_role;
