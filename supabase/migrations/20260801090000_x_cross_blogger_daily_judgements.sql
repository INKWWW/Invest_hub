-- Cross-blogger daily judgements are an additive layer over the existing
-- per-source X range/coverage contract.  Batches freeze the scheduled source
-- set; judgement work is independent from collection task completion.

create table public.x_collection_batches (
  id uuid primary key default gen_random_uuid(),
  scheduled_window_key text not null unique
    check (scheduled_window_key ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T(00:00|08:00|12:00|16:00|20:00)[+]08:00$'),
  natural_date date not null,
  cutoff_at timestamptz not null,
  settlement_deadline_at timestamptz not null,
  status text not null default 'collecting'
    check (status in ('collecting', 'judgement_pending', 'judgement_failed', 'succeeded')),
  created_at timestamptz not null default timezone('utc', now()),
  check (cutoff_at < settlement_deadline_at),
  check (cutoff_at = scheduled_window_key::timestamptz),
  check (natural_date = (cutoff_at at time zone 'Asia/Shanghai')::date)
);

create table public.x_collection_batch_sources (
  batch_id uuid not null references public.x_collection_batches(id) on delete restrict,
  source_id uuid not null references public.sources(id) on delete restrict,
  source_display_name text not null check (length(btrim(source_display_name)) > 0),
  x_sync_task_id uuid references public.sync_tasks(id) on delete restrict,
  settlement_status text not null default 'pending'
    check (settlement_status in ('pending', 'included', 'no_new_information', 'excluded')),
  exclusion_code text,
  settled_at timestamptz,
  primary key (batch_id, source_id),
  unique (x_sync_task_id),
  check (
    (settlement_status = 'pending' and exclusion_code is null and settled_at is null)
    or (settlement_status = 'included' and exclusion_code is null and settled_at is not null)
    or (settlement_status = 'no_new_information' and exclusion_code is null and settled_at is not null)
    or (settlement_status = 'excluded' and exclusion_code is not null and settled_at is not null)
  )
);

alter table public.sync_tasks
  add column collection_batch_id uuid references public.x_collection_batches(id) on delete restrict;

create index sync_tasks_collection_batch_idx
  on public.sync_tasks (collection_batch_id) where collection_batch_id is not null;

create table public.x_daily_judgement_runs (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references public.x_collection_batches(id) on delete restrict,
  status text not null default 'queued'
    check (status in ('queued', 'leased', 'running', 'succeeded', 'retryable_failed', 'failed')),
  attempt integer not null default 0 check (attempt >= 0),
  lease_owner uuid references public.workers(id) on delete set null,
  lease_expires_at timestamptz,
  available_at timestamptz not null default timezone('utc', now()),
  failure_class text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  check (
    (status in ('leased', 'running') and lease_owner is not null and lease_expires_at is not null)
    or (status not in ('leased', 'running') and lease_owner is null and lease_expires_at is null)
  )
);

create unique index x_daily_judgement_runs_one_active_per_batch
  on public.x_daily_judgement_runs (batch_id)
  where status in ('queued', 'leased', 'running', 'retryable_failed');

create index x_daily_judgement_runs_claim_idx
  on public.x_daily_judgement_runs (status, available_at, created_at);

create table public.x_daily_judgement_versions (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references public.x_collection_batches(id) on delete restrict,
  revision integer not null check (revision > 0),
  coverage_status text not null check (coverage_status in ('complete', 'partial', 'no_new_information')),
  input_snapshot jsonb not null,
  output jsonb not null,
  provider text not null check (provider in ('codex_cli', 'mock')),
  model_reported text,
  prompt_version text not null,
  schema_version text not null,
  created_at timestamptz not null default timezone('utc', now()),
  unique (batch_id, revision)
);

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
     or new.created_at is distinct from old.created_at then
    raise exception 'x_collection_batch_immutable' using errcode = '55000';
  end if;
  return new;
end;
$$;

create trigger x_collection_batches_immutable
before update on public.x_collection_batches
for each row execute function public.reject_x_collection_batch_mutation();

create or replace function public.enforce_x_collection_batch_task()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_batch public.x_collection_batches%rowtype;
begin
  if new.collection_batch_id is null then
    return new;
  end if;
  select * into v_batch from public.x_collection_batches where id = new.collection_batch_id;
  if not found
     or new.task_type <> 'x_sync'
     or new.collection_scope->>'mode' <> 'window'
     or new.capture_range->>'trigger' <> 'scheduled'
     or new.capture_range->>'scheduled_window_key' <> v_batch.scheduled_window_key then
    raise exception 'invalid_x_collection_batch_task' using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger sync_tasks_collection_batch_contract
before insert or update of collection_batch_id, task_type, collection_scope, capture_range on public.sync_tasks
for each row execute function public.enforce_x_collection_batch_task();

create or replace function public.enforce_x_collection_batch_source()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_task public.sync_tasks%rowtype;
begin
  if tg_op = 'UPDATE' then
    if new.batch_id is distinct from old.batch_id
       or new.source_id is distinct from old.source_id
       or new.source_display_name is distinct from old.source_display_name then
      raise exception 'x_collection_snapshot_immutable' using errcode = '55000';
    end if;
    if new.x_sync_task_id is distinct from old.x_sync_task_id
       and not (old.x_sync_task_id is null and new.x_sync_task_id is not null
                and old.settlement_status = 'pending' and new.settlement_status = 'pending') then
      raise exception 'x_collection_snapshot_immutable' using errcode = '55000';
    end if;
  else
    if not exists (
      select 1
      from public.sources source
      join public.x_source_profiles profile on profile.source_id = source.id
      where source.id = new.source_id and source.source_type = 'x' and source.enabled
        and profile.enabled and profile.resolution_status = 'resolved'
    ) then
      raise exception 'invalid_x_collection_batch_source' using errcode = '23514';
    end if;
  end if;

  if new.x_sync_task_id is not null then
    select * into v_task from public.sync_tasks where id = new.x_sync_task_id;
    if not found or v_task.source_id <> new.source_id or v_task.task_type <> 'x_sync'
       or v_task.collection_batch_id <> new.batch_id then
      raise exception 'x_collection_batch_task_source_mismatch' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

create trigger x_collection_batch_sources_contract
before insert or update on public.x_collection_batch_sources
for each row execute function public.enforce_x_collection_batch_source();

create or replace function public.reject_x_daily_judgement_version_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception 'x_daily_judgement_version_immutable' using errcode = '55000';
end;
$$;

create or replace function public.validate_x_daily_judgement_input_snapshot(p_snapshot jsonb)
returns void
language plpgsql
set search_path = public
as $$
declare
  v_source jsonb;
  v_segment jsonb;
  v_analysis jsonb;
begin
  if jsonb_typeof(p_snapshot) <> 'object'
     or (p_snapshot - 'sources') <> '{}'::jsonb
     or jsonb_typeof(p_snapshot->'sources') <> 'array' then
    raise exception 'invalid_x_daily_judgement_snapshot' using errcode = '22023';
  end if;
  for v_source in select value from jsonb_array_elements(p_snapshot->'sources') loop
    if jsonb_typeof(v_source) <> 'object'
       or (v_source - 'source_id' - 'display_name' - 'settlement_status' - 'segments') <> '{}'::jsonb
       or jsonb_typeof(v_source->'source_id') <> 'string'
       or jsonb_typeof(v_source->'display_name') <> 'string'
       or v_source->>'settlement_status' not in ('included', 'no_new_information', 'excluded')
       or jsonb_typeof(v_source->'segments') <> 'array' then
      raise exception 'invalid_x_daily_judgement_snapshot' using errcode = '22023';
    end if;
    for v_segment in select value from jsonb_array_elements(v_source->'segments') loop
      if jsonb_typeof(v_segment) <> 'object'
         or (v_segment - 'segment_id' - 'analysis_ids' - 'evidence_post_ids') <> '{}'::jsonb
         or jsonb_typeof(v_segment->'segment_id') <> 'string'
         or jsonb_typeof(v_segment->'analysis_ids') <> 'array'
         or jsonb_typeof(v_segment->'evidence_post_ids') <> 'array'
         or exists (select 1 from jsonb_array_elements(v_segment->'evidence_post_ids') value where jsonb_typeof(value) <> 'string') then
        raise exception 'invalid_x_daily_judgement_snapshot' using errcode = '22023';
      end if;
      for v_analysis in select value from jsonb_array_elements(v_segment->'analysis_ids') loop
        if jsonb_typeof(v_analysis) <> 'object'
           or (v_analysis - 'post_id' - 'analysis_version') <> '{}'::jsonb
           or jsonb_typeof(v_analysis->'post_id') <> 'string'
           or jsonb_typeof(v_analysis->'analysis_version') <> 'number' then
          raise exception 'invalid_x_daily_judgement_snapshot' using errcode = '22023';
        end if;
      end loop;
    end loop;
  end loop;
end;
$$;

create or replace function public.validate_x_daily_judgement_output(p_output jsonb)
returns void
language plpgsql
set search_path = public
as $$
declare
  v_item jsonb;
begin
  if jsonb_typeof(p_output) <> 'object'
     or (p_output - 'stock_viewpoints' - 'market_industry_viewpoints' - 'uncertainties') <> '{}'::jsonb
     or jsonb_typeof(p_output->'stock_viewpoints') <> 'array'
     or jsonb_typeof(p_output->'market_industry_viewpoints') <> 'array'
     or jsonb_typeof(p_output->'uncertainties') <> 'array'
     or exists (select 1 from jsonb_array_elements(p_output->'uncertainties') value where jsonb_typeof(value) <> 'string') then
    raise exception 'invalid_x_daily_judgement_output' using errcode = '22023';
  end if;
  for v_item in
    select value from jsonb_array_elements(p_output->'stock_viewpoints')
    union all
    select value from jsonb_array_elements(p_output->'market_industry_viewpoints')
  loop
    if jsonb_typeof(v_item) <> 'object'
       or (v_item - 'statement' - 'supporting_source_ids' - 'dissenting_source_ids' - 'analysis_ids' - 'evidence_post_ids' - 'uncertainties') <> '{}'::jsonb
       or jsonb_typeof(v_item->'statement') <> 'string'
       or jsonb_typeof(v_item->'supporting_source_ids') <> 'array'
       or jsonb_typeof(v_item->'dissenting_source_ids') <> 'array'
       or jsonb_typeof(v_item->'analysis_ids') <> 'array'
       or jsonb_typeof(v_item->'evidence_post_ids') <> 'array'
       or jsonb_typeof(v_item->'uncertainties') <> 'array'
       or exists (select 1 from jsonb_array_elements(v_item->'supporting_source_ids') value where jsonb_typeof(value) <> 'string')
       or exists (select 1 from jsonb_array_elements(v_item->'dissenting_source_ids') value where jsonb_typeof(value) <> 'string')
       or exists (select 1 from jsonb_array_elements(v_item->'analysis_ids') value where jsonb_typeof(value) <> 'string')
       or exists (select 1 from jsonb_array_elements(v_item->'evidence_post_ids') value where jsonb_typeof(value) <> 'string')
       or exists (select 1 from jsonb_array_elements(v_item->'uncertainties') value where jsonb_typeof(value) <> 'string') then
      raise exception 'invalid_x_daily_judgement_output' using errcode = '22023';
    end if;
  end loop;
end;
$$;

create or replace function public.enforce_x_daily_judgement_version()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_expected_revision integer;
  v_evidence_id text;
  v_allowed_evidence text[];
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
  select coalesce(array_agg(distinct value), '{}') into v_allowed_evidence
  from jsonb_path_query(new.input_snapshot, '$.sources[*].segments[*].evidence_post_ids[*]') as value_json(value_json)
  cross join lateral (select trim(both '"' from value_json::text) as value) safe;
  for v_evidence_id in
    select evidence.value
    from jsonb_array_elements(coalesce(new.output->'stock_viewpoints', '[]'::jsonb)) item
    cross join lateral jsonb_array_elements_text(coalesce(item->'evidence_post_ids', '[]'::jsonb)) evidence(value)
    union all
    select evidence.value
    from jsonb_array_elements(coalesce(new.output->'market_industry_viewpoints', '[]'::jsonb)) item
    cross join lateral jsonb_array_elements_text(coalesce(item->'evidence_post_ids', '[]'::jsonb)) evidence(value)
  loop
    if not v_evidence_id = any(v_allowed_evidence) then
      raise exception 'invalid_x_daily_judgement_evidence' using errcode = '22023';
    end if;
  end loop;
  return new;
end;
$$;

create trigger x_daily_judgement_versions_validate
before insert on public.x_daily_judgement_versions
for each row execute function public.enforce_x_daily_judgement_version();
create trigger x_daily_judgement_versions_immutable
before update or delete on public.x_daily_judgement_versions
for each row execute function public.reject_x_daily_judgement_version_mutation();

create trigger x_daily_judgement_runs_set_updated_at
before update on public.x_daily_judgement_runs
for each row execute function public.set_updated_at();

alter table public.x_collection_batches enable row level security;
alter table public.x_collection_batch_sources enable row level security;
alter table public.x_daily_judgement_runs enable row level security;
alter table public.x_daily_judgement_versions enable row level security;

create policy x_collection_batches_admin_all on public.x_collection_batches
for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy x_collection_batch_sources_admin_all on public.x_collection_batch_sources
for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy x_daily_judgement_runs_admin_all on public.x_daily_judgement_runs
for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy x_daily_judgement_versions_admin_all on public.x_daily_judgement_versions
for all to authenticated using (public.is_admin()) with check (public.is_admin());

grant select, insert, update, delete on public.x_collection_batches, public.x_collection_batch_sources,
  public.x_daily_judgement_runs, public.x_daily_judgement_versions to authenticated, service_role;

create function public.ensure_due_x_collection_batches(p_worker_id uuid, p_now timestamptz)
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
  if p_now is null or not exists (
    select 1 from public.workers where id = p_worker_id and status in ('enrolled', 'online')
  ) then
    raise exception 'worker_not_authorized' using errcode = '42501';
  end if;

  for v_window in
    with eligible as (
      select source.id, source.parameter_version, coverage.coverage_through_at
      from public.sources source
      join public.x_source_profiles profile on profile.source_id = source.id
        and profile.enabled and profile.resolution_status = 'resolved'
      join public.source_collection_coverage coverage on coverage.source_id = source.id
      where source.source_type = 'x' and source.enabled
        and (source.authorized_worker_id is null or source.authorized_worker_id = p_worker_id)
    ), due as (
      select eligible.*, (
        select min((day_at + cutoff) at time zone 'Asia/Shanghai')
        from generate_series(
          date_trunc('day', eligible.coverage_through_at at time zone 'Asia/Shanghai'),
          date_trunc('day', p_now at time zone 'Asia/Shanghai'), interval '1 day'
        ) as day_at
        cross join (values (time '00:00'), (time '08:00'), (time '12:00'), (time '16:00'), (time '20:00')) as cutoffs(cutoff)
        where (day_at + cutoff) at time zone 'Asia/Shanghai' > eligible.coverage_through_at
          and (day_at + cutoff) at time zone 'Asia/Shanghai' <= p_now
      ) as end_at
      from eligible
    )
    select distinct end_at from due where end_at is not null order by end_at
  loop
    perform pg_advisory_xact_lock(hashtextextended(v_window.end_at::text, 24001));
    select * into v_batch from public.x_collection_batches
    where scheduled_window_key = to_char(v_window.end_at at time zone 'Asia/Shanghai', 'YYYY-MM-DD"T"HH24:MI') || '+08:00'
    for update;

    if not found then
      insert into public.x_collection_batches (
        scheduled_window_key, natural_date, cutoff_at, settlement_deadline_at, status
      ) values (
        to_char(v_window.end_at at time zone 'Asia/Shanghai', 'YYYY-MM-DD"T"HH24:MI') || '+08:00',
        (v_window.end_at at time zone 'Asia/Shanghai')::date, v_window.end_at,
        v_window.end_at + interval '2 hours', 'collecting'
      ) returning * into v_batch;

      for v_source in
        with eligible as (
          select source.id, source.parameter_version, profile.display_name, coverage.coverage_through_at
          from public.sources source
          join public.x_source_profiles profile on profile.source_id = source.id
            and profile.enabled and profile.resolution_status = 'resolved'
          join public.source_collection_coverage coverage on coverage.source_id = source.id
          where source.source_type = 'x' and source.enabled
            and (source.authorized_worker_id is null or source.authorized_worker_id = p_worker_id)
        )
        select * from eligible
        where (
          select min((day_at + cutoff) at time zone 'Asia/Shanghai')
          from generate_series(
            date_trunc('day', eligible.coverage_through_at at time zone 'Asia/Shanghai'),
            date_trunc('day', p_now at time zone 'Asia/Shanghai'), interval '1 day'
          ) as day_at
          cross join (values (time '00:00'), (time '08:00'), (time '12:00'), (time '16:00'), (time '20:00')) as cutoffs(cutoff)
          where (day_at + cutoff) at time zone 'Asia/Shanghai' > eligible.coverage_through_at
            and (day_at + cutoff) at time zone 'Asia/Shanghai' <= p_now
        ) = v_window.end_at
      loop
        insert into public.x_collection_batch_sources (batch_id, source_id, source_display_name)
        values (v_batch.id, v_source.id, v_source.display_name);
      end loop;

      for v_source in
        select source_id, x_sync_task_id from public.x_collection_batch_sources
        where batch_id = v_batch.id order by source_id
      loop
        if exists (
          select 1 from public.sync_tasks task
          where task.source_id = v_source.source_id and task.task_type = 'x_sync'
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
        select to_jsonb(task) || jsonb_build_object('idempotent', true) into v_task
        from public.sync_tasks task
        join public.source_collection_coverage coverage on coverage.source_id = task.source_id
        where task.source_id = v_source.source_id and task.task_type = 'x_sync'
          and task.collection_scope->>'mode' = 'window' and task.status = 'failed'
          and (task.capture_range->>'start_at')::timestamptz = coverage.coverage_through_at
          and (task.capture_range->>'end_at')::timestamptz = v_window.end_at
          and task.capture_range->>'trigger' = 'scheduled'
          and task.capture_range->>'scheduled_window_key' = v_batch.scheduled_window_key
        order by task.queued_at, task.id limit 1;
        if v_task is null then
          select public.create_windowed_x_sync_task(
            v_source.source_id,
            (select parameter_version from public.sources where id = v_source.source_id),
            null, 'scheduled', v_window.end_at, v_batch.scheduled_window_key
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
      'batch_id', v_batch.id::text, 'scheduled_window_key', v_batch.scheduled_window_key
    ));
  end loop;
  return jsonb_build_object('scheduled_at', p_now, 'batches', v_batches);
end;
$$;

create function public.settle_x_collection_batch(p_batch_id uuid, p_now timestamptz)
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
      select 1 from public.x_daily_viewpoint_segments segment where segment.range_task_id = v_source.x_sync_task_id
    ) then
      v_status := 'included';
    elsif v_source.task_status = 'succeeded' and exists (
      select 1 from public.task_attempts attempt
      where attempt.task_id = v_source.x_sync_task_id and attempt.status = 'succeeded'
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
      'source_id', source_id::text, 'display_name', source_display_name,
      'settlement_status', settlement_status, 'segments', '[]'::jsonb
    ) order by source_id), '[]'::jsonb)) into v_snapshot
    from public.x_collection_batch_sources where batch_id = p_batch_id;
    insert into public.x_daily_judgement_versions (
      batch_id, revision, coverage_status, input_snapshot, output, provider, prompt_version, schema_version
    ) values (
      p_batch_id,
      (select coalesce(max(revision), 0) + 1 from public.x_daily_judgement_versions where batch_id = p_batch_id),
      v_coverage_status, v_snapshot,
      '{"stock_viewpoints":[],"market_industry_viewpoints":[],"uncertainties":[]}'::jsonb,
      'codex_cli', 'v2-x-cross-blogger-1', 'v2-x-cross-blogger'
    ) on conflict do nothing;
    update public.x_collection_batches set status = 'succeeded' where id = p_batch_id;
  end if;
  return jsonb_build_object('batch_id', p_batch_id::text, 'settled', true, 'coverage_status', v_coverage_status);
end;
$$;

create function public.claim_next_x_daily_judgement(p_worker_id uuid, p_now timestamptz)
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
    select 1 from public.workers where id = p_worker_id and status in ('enrolled', 'online')
  ) then
    raise exception 'worker_not_authorized' using errcode = '42501';
  end if;
  update public.x_daily_judgement_runs
  set status = 'retryable_failed', lease_owner = null, lease_expires_at = null, available_at = p_now,
      failure_class = coalesce(failure_class, 'lease_expired')
  where status in ('leased', 'running') and lease_expires_at <= p_now;
  select * into v_run from public.x_daily_judgement_runs
  where status in ('queued', 'retryable_failed') and available_at <= p_now
  order by available_at, created_at, id for update skip locked limit 1;
  if not found then return null; end if;
  update public.x_daily_judgement_runs
  set status = 'leased', attempt = v_run.attempt + 1, lease_owner = p_worker_id,
      lease_expires_at = p_now + interval '10 minutes', failure_class = null
  where id = v_run.id
  returning * into v_run;
  select case when count(*) filter (where settlement_status = 'excluded') > 0 then 'partial' else 'complete' end
    into v_coverage_status
  from public.x_collection_batch_sources where batch_id = v_run.batch_id;
  return jsonb_build_object('run_id', v_run.id::text, 'attempt', v_run.attempt,
    'lease_expires_at', v_run.lease_expires_at,
    'batch', (select jsonb_build_object('id', batch.id::text, 'natural_date', batch.natural_date,
      'cutoff_at', batch.cutoff_at, 'coverage_status', v_coverage_status)
      from public.x_collection_batches batch where batch.id = v_run.batch_id));
end;
$$;

create function public.complete_x_daily_judgement(
  p_run_id uuid, p_attempt integer, p_worker_id uuid, p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_run public.x_daily_judgement_runs%rowtype;
  v_coverage_status text;
  v_snapshot jsonb;
  v_output jsonb;
begin
  select * into v_run from public.x_daily_judgement_runs where id = p_run_id for update;
  if not found or p_attempt is null or p_worker_id is null or v_run.attempt <> p_attempt
     or v_run.status not in ('leased', 'running') or v_run.lease_owner <> p_worker_id then
    raise exception 'lease_mismatch' using errcode = 'PT409';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object'
     or p_payload->>'schema_version' <> 'v2-x-cross-blogger'
     or p_payload->>'provider' not in ('codex_cli', 'mock')
     or p_payload->>'prompt_version' <> 'v2-x-cross-blogger-1'
     or jsonb_typeof(p_payload->'stock_viewpoints') <> 'array'
     or jsonb_typeof(p_payload->'market_industry_viewpoints') <> 'array'
     or jsonb_typeof(p_payload->'uncertainties') <> 'array' then
    raise exception 'invalid_x_daily_judgement_completion' using errcode = '22023';
  end if;
  select case when count(*) filter (where settlement_status = 'excluded') > 0 then 'partial' else 'complete' end
    into v_coverage_status
  from public.x_collection_batch_sources where batch_id = v_run.batch_id;
  select jsonb_build_object('sources', coalesce(jsonb_agg(jsonb_build_object(
    'source_id', batch_source.source_id::text, 'display_name', batch_source.source_display_name,
    'settlement_status', batch_source.settlement_status,
    'segments', coalesce((select jsonb_agg(jsonb_build_object(
      'segment_id', segment.id::text,
      'analysis_ids', segment.post_analysis_refs,
      'evidence_post_ids', segment.evidence_refs
    ) order by segment.id) from public.x_daily_viewpoint_segments segment
      where segment.range_task_id = batch_source.x_sync_task_id), '[]'::jsonb)
  ) order by batch_source.source_id), '[]'::jsonb)) into v_snapshot
  from public.x_collection_batch_sources batch_source
  where batch_source.batch_id = v_run.batch_id and batch_source.settlement_status = 'included';
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

create or replace function public.complete_windowed_capture_range(
  p_task_id uuid, p_attempt integer, p_worker_id uuid, p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
set lock_timeout = '5s'
as $$
declare
  v_result jsonb;
begin
  v_result := public.complete_windowed_capture_range_v2_x_core(p_task_id, p_attempt, p_worker_id, p_payload);
  return v_result;
exception
  when sqlstate '40001' then
    raise sqlstate 'PT409' using message = sqlerrm;
end;
$$;

revoke all on function public.ensure_due_x_collection_batches(uuid, timestamptz),
  public.settle_x_collection_batch(uuid, timestamptz),
  public.claim_next_x_daily_judgement(uuid, timestamptz),
  public.complete_x_daily_judgement(uuid, integer, uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.ensure_due_x_collection_batches(uuid, timestamptz),
  public.settle_x_collection_batch(uuid, timestamptz),
  public.claim_next_x_daily_judgement(uuid, timestamptz),
  public.complete_x_daily_judgement(uuid, integer, uuid, jsonb)
  to service_role;

revoke all on function public.complete_windowed_capture_range(uuid, integer, uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.complete_windowed_capture_range(uuid, integer, uuid, jsonb) to service_role;
