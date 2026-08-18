-- Ticket 02R: one explicit fixed-window runner identity and its frozen source
-- snapshot.  The existing Ticket 01 task creator and range completion remain
-- the authority for each individual source.

create table public.x_demo_fixed_window_runs (
  id uuid primary key default gen_random_uuid(),
  cutoff_at timestamptz not null unique,
  batch_id uuid not null references public.x_collection_batches(id) on delete restrict,
  owner_worker_id uuid not null references public.workers(id) on delete restrict,
  status text not null default 'running'
    check (status in ('running', 'complete', 'partial', 'no_new', 'failed')),
  source_snapshot jsonb not null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  check (jsonb_typeof(source_snapshot) = 'array')
);

alter table public.x_demo_fixed_window_runs enable row level security;
create policy x_demo_fixed_window_runs_admin_read on public.x_demo_fixed_window_runs
for select to authenticated using (public.is_admin());
revoke all on table public.x_demo_fixed_window_runs from public, anon, authenticated;
grant select on public.x_demo_fixed_window_runs to service_role;

create or replace function public.enforce_x_collection_batch_source()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_task public.sync_tasks%rowtype;
  v_batch public.x_collection_batches%rowtype;
begin
  if tg_op = 'UPDATE' then
    if new.batch_id is distinct from old.batch_id
       or new.source_id is distinct from old.source_id
       or new.source_display_name is distinct from old.source_display_name then
      raise exception 'x_collection_snapshot_immutable' using errcode = '55000';
    end if;
    if old.settlement_status <> 'pending' then
      raise exception 'x_collection_snapshot_terminal' using errcode = '55000';
    end if;
    if new.x_sync_task_id is distinct from old.x_sync_task_id
       and not (old.x_sync_task_id is null and new.x_sync_task_id is not null
                and old.settlement_status = 'pending' and new.settlement_status = 'pending') then
      raise exception 'x_collection_snapshot_immutable' using errcode = '55000';
    end if;
  elsif not exists (
    select 1
    from public.sources source
    join public.x_source_profiles profile on profile.source_id = source.id
    where source.id = new.source_id and source.source_type = 'x' and source.enabled
      and profile.enabled and profile.resolution_status = 'resolved'
  ) and not exists (
    select 1 from public.x_demo_fixed_window_runs demo
    where demo.batch_id = new.batch_id
  ) then
    raise exception 'invalid_x_collection_batch_source' using errcode = '23514';
  end if;

  if new.x_sync_task_id is not null then
    select * into v_task from public.sync_tasks where id = new.x_sync_task_id;
    if not found or v_task.source_id <> new.source_id or v_task.task_type <> 'x_sync' then
      raise exception 'x_collection_batch_task_source_mismatch' using errcode = '23514';
    end if;
    select * into v_batch from public.x_collection_batches where id = new.batch_id;
    if not found then
      raise exception 'x_collection_batch_task_source_mismatch' using errcode = '23514';
    end if;
    if v_batch.scheduled_window_key ~ '^manual:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      if v_task.status <> 'succeeded'
         or v_task.collection_scope->>'mode' <> 'window'
         or (v_task.capture_range->>'end_at')::timestamptz <> v_batch.cutoff_at then
        raise exception 'x_collection_batch_task_source_mismatch' using errcode = '23514';
      end if;
    elsif v_task.collection_batch_id <> new.batch_id then
      raise exception 'x_collection_batch_task_source_mismatch' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.start_x_demo_fixed_window_run(
  p_cutoff_at timestamptz,
  p_worker_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_bounds jsonb;
  v_existing public.x_demo_fixed_window_runs%rowtype;
  v_batch public.x_collection_batches%rowtype;
  v_run public.x_demo_fixed_window_runs%rowtype;
  v_snapshot jsonb;
  v_source record;
begin
  if not exists (
    select 1 from public.workers
    where id = p_worker_id and status in ('enrolled', 'online') and capabilities @> array['x_sync']::text[]
  ) then
    raise exception 'worker_not_authorized' using errcode = '42501';
  end if;
  if p_cutoff_at is null or p_cutoff_at > clock_timestamp() then
    raise exception 'invalid_x_demo_cutoff' using errcode = '22023';
  end if;
  v_bounds := public.x_demo_fixed_window_bounds(p_cutoff_at);

  perform pg_advisory_xact_lock(hashtextextended(p_cutoff_at::text, 24002));
  select * into v_existing from public.x_demo_fixed_window_runs where cutoff_at = p_cutoff_at for update;
  if found then
    if v_existing.owner_worker_id <> p_worker_id then
      raise exception 'worker_not_authorized' using errcode = '42501';
    end if;
    return jsonb_build_object(
      'run_id', v_existing.id::text, 'status', v_existing.status, 'idempotent', true,
      'cutoff_at', p_cutoff_at, 'sources', v_existing.source_snapshot
    );
  end if;

  if not exists (
    select 1 from public.sources source
    where source.source_type = 'x' and source.enabled
  ) or exists (
    select 1
    from public.sources source
    left join public.x_source_profiles profile on profile.source_id = source.id
    where source.source_type = 'x' and source.enabled
      and (
        profile.source_id is null
        or not profile.enabled
        or profile.resolution_status is distinct from 'resolved'
        or nullif(btrim(profile.account_id), '') is null
      )
  ) then
    raise exception 'x_demo_sources_not_ready' using errcode = 'PT409';
  end if;

  select * into v_batch from public.x_collection_batches
  where scheduled_window_key = v_bounds->>'scheduled_window_key' for update;
  if not found then
    insert into public.x_collection_batches (
      scheduled_window_key, natural_date, cutoff_at, settlement_deadline_at, status, snapshot_completeness
    ) values (
      v_bounds->>'scheduled_window_key', (v_bounds->>'natural_date')::date, p_cutoff_at,
      p_cutoff_at + interval '2 hours', 'collecting', 'complete'
    ) returning * into v_batch;
  elsif v_batch.status <> 'collecting' then
    raise exception 'x_demo_fixed_window_batch_not_available' using errcode = 'PT409';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'source_id', source.id::text,
    'display_name', source.display_name,
    'requested_handle', profile.requested_handle,
    'resolution_status', profile.resolution_status,
    'parameter_version', source.parameter_version,
    'account_id', profile.account_id
  ) order by source.id), '[]'::jsonb)
  into v_snapshot
  from public.sources source
  join public.x_source_profiles profile on profile.source_id = source.id and profile.enabled
  where source.source_type = 'x' and source.enabled;

  insert into public.x_demo_fixed_window_runs (cutoff_at, batch_id, owner_worker_id, source_snapshot)
  values (p_cutoff_at, v_batch.id, p_worker_id, v_snapshot)
  returning * into v_run;

  for v_source in
    select (item->>'source_id')::uuid as source_id, item->>'display_name' as display_name,
           item->>'resolution_status' as resolution_status
    from jsonb_array_elements(v_snapshot) item
  loop
    if not exists (
      select 1 from public.sources source
      where source.id = v_source.source_id
        and (source.authorized_worker_id is null or source.authorized_worker_id = p_worker_id)
    ) then
      raise exception 'worker_not_authorized' using errcode = '42501';
    end if;
    update public.sources set authorized_worker_id = p_worker_id where id = v_source.source_id;
    insert into public.x_collection_batch_sources (
      batch_id, source_id, source_display_name, settlement_status, exclusion_code, settled_at
    ) values (
      v_batch.id, v_source.source_id, v_source.display_name,
      'pending', null, null
    );
  end loop;

  return jsonb_build_object(
    'run_id', v_run.id::text, 'status', v_run.status, 'idempotent', false,
    'cutoff_at', p_cutoff_at, 'sources', v_snapshot
  );
end;
$$;

create or replace function public.bind_x_demo_fixed_window_task(
  p_run_id uuid, p_source_id uuid, p_task_id uuid, p_worker_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_run public.x_demo_fixed_window_runs%rowtype;
  v_task public.sync_tasks%rowtype;
begin
  select * into v_run from public.x_demo_fixed_window_runs where id = p_run_id for update;
  select * into v_task from public.sync_tasks where id = p_task_id for update;
  if not found or v_run.id is null or v_run.status <> 'running' or v_run.owner_worker_id <> p_worker_id
     or not exists (select 1 from public.workers where id = p_worker_id and status in ('enrolled', 'online') and capabilities @> array['x_sync']::text[])
     or not exists (select 1 from public.sources where id = p_source_id and authorized_worker_id = p_worker_id)
     or v_task.source_id <> p_source_id
     or v_task.task_type <> 'x_sync' or v_task.collection_batch_id is not null then
    raise exception 'worker_not_authorized' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.x_demo_fixed_window_tasks demo
    where demo.task_id = p_task_id and demo.source_id = p_source_id and demo.cutoff_at = v_run.cutoff_at
      and demo.end_at = v_run.cutoff_at and (v_task.capture_range->>'end_at')::timestamptz = v_run.cutoff_at
  ) then
    raise exception 'invalid_x_demo_fixed_window_task' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.x_collection_batch_sources
    where batch_id = v_run.batch_id and source_id = p_source_id and settlement_status = 'pending'
  ) then
    raise exception 'invalid_x_demo_fixed_window_source' using errcode = '22023';
  end if;
  update public.sync_tasks set collection_batch_id = v_run.batch_id where id = p_task_id;
  update public.x_collection_batch_sources
  set x_sync_task_id = p_task_id
  where batch_id = v_run.batch_id and source_id = p_source_id;
  return jsonb_build_object('status', 'attached', 'run_id', p_run_id::text, 'source_id', p_source_id::text, 'task_id', p_task_id::text);
end;
$$;

create or replace function public.fail_x_demo_fixed_window_source(
  p_run_id uuid, p_source_id uuid, p_reason text, p_worker_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_run public.x_demo_fixed_window_runs%rowtype;
begin
  select * into v_run from public.x_demo_fixed_window_runs where id = p_run_id for update;
  if not found or v_run.status <> 'running' or v_run.owner_worker_id <> p_worker_id
     or not exists (select 1 from public.workers where id = p_worker_id and status in ('enrolled', 'online') and capabilities @> array['x_sync']::text[])
     or not exists (select 1 from public.sources where id = p_source_id and authorized_worker_id = p_worker_id)
     or p_reason is null or length(btrim(p_reason)) = 0 then
    raise exception 'invalid_x_demo_fixed_window_source_failure' using errcode = '22023';
  end if;
  update public.x_collection_batch_sources
  set settlement_status = 'excluded', exclusion_code = left(p_reason, 120), settled_at = clock_timestamp()
  where batch_id = v_run.batch_id and source_id = p_source_id and settlement_status = 'pending';
  return jsonb_build_object('status', 'excluded', 'run_id', p_run_id::text, 'source_id', p_source_id::text);
end;
$$;

create or replace function public.settle_x_demo_fixed_window_run(p_run_id uuid, p_worker_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_run public.x_demo_fixed_window_runs%rowtype;
  v_batch public.x_collection_batches%rowtype;
  v_pending integer;
  v_included integer;
  v_excluded integer;
  v_no_new integer;
  v_status text;
  v_coverage text;
begin
  select * into v_run from public.x_demo_fixed_window_runs where id = p_run_id for update;
  if not found then raise exception 'x_demo_fixed_window_run_not_found' using errcode = '22023'; end if;
  if v_run.owner_worker_id <> p_worker_id
     or not exists (select 1 from public.workers where id = p_worker_id and status in ('enrolled', 'online') and capabilities @> array['x_sync']::text[])
     or exists (select 1 from public.x_collection_batch_sources batch_source join public.sources source on source.id = batch_source.source_id where batch_source.batch_id = v_run.batch_id and source.authorized_worker_id is distinct from p_worker_id) then
    raise exception 'worker_not_authorized' using errcode = '42501';
  end if;
  select * into v_batch from public.x_collection_batches where id = v_run.batch_id for update;
  update public.x_collection_batch_sources batch_source
  set settlement_status = 'excluded', exclusion_code = 'terminal_failure', settled_at = clock_timestamp()
  where batch_source.batch_id = v_run.batch_id and batch_source.settlement_status = 'pending'
    and exists (
      select 1 from public.sync_tasks task
      where task.id = batch_source.x_sync_task_id and task.status in ('failed', 'cancelled')
    );

  update public.x_collection_batch_sources batch_source
  set settlement_status = 'included', settled_at = clock_timestamp()
  where batch_source.batch_id = v_run.batch_id and batch_source.settlement_status = 'pending'
    and exists (
      select 1 from public.sync_tasks task
      join public.x_daily_viewpoint_segments segment on segment.range_task_id = task.id
      where task.id = batch_source.x_sync_task_id and task.status = 'succeeded'
        and segment.source_id = batch_source.source_id and segment.natural_date = v_batch.natural_date
    );
  update public.x_collection_batch_sources batch_source
  set settlement_status = 'no_new_information', settled_at = clock_timestamp()
  where batch_source.batch_id = v_run.batch_id and batch_source.settlement_status = 'pending'
    and exists (
      select 1 from public.sync_tasks task
      join public.task_attempts attempt on attempt.task_id = task.id and attempt.status = 'succeeded'
      where task.id = batch_source.x_sync_task_id and task.status = 'succeeded'
        and coalesce((attempt.result->>'no_new_data')::boolean, false)
    );

  select count(*) filter (where settlement_status = 'pending'),
         count(*) filter (where settlement_status = 'included'),
         count(*) filter (where settlement_status = 'excluded'),
         count(*) filter (where settlement_status = 'no_new_information')
  into v_pending, v_included, v_excluded, v_no_new
  from public.x_collection_batch_sources where batch_id = v_run.batch_id;
  if v_pending > 0 then return jsonb_build_object('status', 'running', 'run_id', p_run_id::text); end if;

  if v_included > 0 then
    v_coverage := case when v_excluded > 0 then 'partial' else 'complete' end;
    update public.x_collection_batches set status = 'judgement_pending' where id = v_run.batch_id;
    insert into public.x_daily_judgement_runs (batch_id, status, available_at)
    values (v_run.batch_id, 'queued', clock_timestamp()) on conflict do nothing;
    update public.x_demo_fixed_window_runs set status = v_coverage, updated_at = clock_timestamp() where id = p_run_id;
    return jsonb_build_object('status', 'judgement_pending', 'coverage_status', v_coverage, 'run_id', p_run_id::text);
  end if;
  if v_excluded > 0 then
    update public.x_collection_batches set status = 'judgement_failed' where id = v_run.batch_id;
    update public.x_demo_fixed_window_runs set status = 'failed', updated_at = clock_timestamp() where id = p_run_id;
    return jsonb_build_object('status', 'failed', 'run_id', p_run_id::text, 'error', 'no_available_input');
  end if;

  if jsonb_array_length(v_run.source_snapshot) = 0 then
    update public.x_collection_batches set status = 'judgement_failed' where id = v_run.batch_id;
    update public.x_demo_fixed_window_runs set status = 'failed', updated_at = clock_timestamp() where id = p_run_id;
    return jsonb_build_object('status', 'failed', 'run_id', p_run_id::text, 'error', 'no_available_input');
  end if;

  -- Preserve the existing no-new database judgement projection without
  -- invoking a Provider or fabricating a cross-blogger conclusion.
  insert into public.x_daily_judgement_versions (
    batch_id, revision, coverage_status, input_snapshot, output, provider, prompt_version, schema_version
  ) values (
    v_run.batch_id,
    (select coalesce(max(revision), 0) + 1 from public.x_daily_judgement_versions where batch_id = v_run.batch_id),
    'no_new_information', public.build_x_daily_judgement_input_snapshot(v_run.batch_id),
    '{"security_industry_viewpoints":[],"market_structure_viewpoints":[],"strategy_mindset_viewpoints":[],"uncertainties":[]}'::jsonb,
    'codex_cli', 'v4-x-cross-blogger-1', 'v4-x-cross-blogger'
  ) on conflict do nothing;
  update public.x_collection_batches set status = 'succeeded' where id = v_run.batch_id;
  update public.x_demo_fixed_window_runs set status = 'no_new', updated_at = clock_timestamp() where id = p_run_id;
  return jsonb_build_object('status', 'no_new', 'coverage_status', 'no_new_information', 'run_id', p_run_id::text);
end;
$$;

create or replace function public.claim_x_demo_fixed_window_judgement(
  p_run_id uuid, p_worker_id uuid, p_now timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_run public.x_demo_fixed_window_runs%rowtype;
  v_judgement public.x_daily_judgement_runs%rowtype;
  v_coverage text;
begin
  select * into v_run from public.x_demo_fixed_window_runs where id = p_run_id for update;
  if not found or v_run.status not in ('complete', 'partial') then return null; end if;
  if v_run.owner_worker_id <> p_worker_id
     or not exists (select 1 from public.workers where id = p_worker_id and status in ('enrolled', 'online') and capabilities @> array['x_sync']::text[])
     or exists (select 1 from public.x_collection_batch_sources batch_source join public.sources source on source.id = batch_source.source_id where batch_source.batch_id = v_run.batch_id and source.authorized_worker_id is distinct from p_worker_id) then
    raise exception 'worker_not_authorized' using errcode = '42501';
  end if;
  select * into v_judgement from public.x_daily_judgement_runs
  where batch_id = v_run.batch_id and status in ('queued', 'retryable_failed')
  order by created_at, id for update skip locked limit 1;
  if not found then return null; end if;
  update public.x_daily_judgement_runs
  set status = 'leased', attempt = attempt + 1, lease_owner = p_worker_id,
      lease_expires_at = p_now + interval '10 minutes', failure_class = null
  where id = v_judgement.id returning * into v_judgement;
  select case when count(*) filter (where settlement_status = 'excluded') > 0 then 'partial' else 'complete' end
  into v_coverage from public.x_collection_batch_sources where batch_id = v_run.batch_id;
  return jsonb_build_object(
    'run_id', v_judgement.id::text, 'attempt', v_judgement.attempt,
    'lease_expires_at', v_judgement.lease_expires_at,
    'batch', (select jsonb_build_object('id', batch.id::text, 'natural_date', batch.natural_date,
      'cutoff_at', batch.cutoff_at, 'coverage_status', v_coverage)
      from public.x_collection_batches batch where batch.id = v_run.batch_id)
  );
end;
$$;

revoke all on function public.start_x_demo_fixed_window_run(timestamptz, uuid),
  public.bind_x_demo_fixed_window_task(uuid, uuid, uuid, uuid),
  public.fail_x_demo_fixed_window_source(uuid, uuid, text, uuid),
  public.settle_x_demo_fixed_window_run(uuid, uuid),
  public.claim_x_demo_fixed_window_judgement(uuid, uuid, timestamptz)
  from public, anon, authenticated;
grant execute on function public.start_x_demo_fixed_window_run(timestamptz, uuid),
  public.bind_x_demo_fixed_window_task(uuid, uuid, uuid, uuid),
  public.fail_x_demo_fixed_window_source(uuid, uuid, text, uuid),
  public.settle_x_demo_fixed_window_run(uuid, uuid),
  public.claim_x_demo_fixed_window_judgement(uuid, uuid, timestamptz)
  to service_role;

create or replace function public.create_x_demo_fixed_window_task_for_run(
  p_run_id uuid, p_source_id uuid, p_cutoff_at timestamptz, p_worker_id uuid, p_account_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_run public.x_demo_fixed_window_runs%rowtype;
  v_snapshot jsonb;
  v_source public.sources%rowtype;
  v_bounds jsonb;
  v_existing public.x_demo_fixed_window_tasks%rowtype;
  v_task public.sync_tasks%rowtype;
begin
  select * into v_run from public.x_demo_fixed_window_runs where id = p_run_id for update;
  select item into v_snapshot from jsonb_array_elements(v_run.source_snapshot) item where item->>'source_id' = p_source_id::text;
  if not found or v_run.owner_worker_id <> p_worker_id or v_run.status <> 'running' or p_cutoff_at <> v_run.cutoff_at
     or not exists (select 1 from public.workers where id = p_worker_id and status in ('enrolled', 'online') and capabilities @> array['x_sync']::text[])
     or not exists (select 1 from public.sources where id = p_source_id and source_type = 'x' and authorized_worker_id = p_worker_id) then
    raise exception 'worker_not_authorized' using errcode = '42501';
  end if;
  select * into v_source from public.sources where id = p_source_id and source_type = 'x' for update;
  if not found or v_source.id is null then
    raise exception 'x_demo_fixed_window_snapshot_changed' using errcode = '22023';
  end if;
  if p_account_id is null or p_account_id <> v_snapshot->>'account_id' then
    raise exception 'x_demo_fixed_window_snapshot_changed' using errcode = '22023';
  end if;
  v_bounds := public.x_demo_fixed_window_bounds(p_cutoff_at);
  select * into v_existing from public.x_demo_fixed_window_tasks
  where source_id = p_source_id and cutoff_at = p_cutoff_at for update;
  if found then
    select * into v_task from public.sync_tasks where id = v_existing.task_id;
    return to_jsonb(v_task) || jsonb_build_object('idempotent', true, 'demo_fixed_window', v_bounds);
  end if;
  insert into public.sync_tasks (
    task_type, source_id, status, parameter_version, requested_by, collection_scope,
    capture_range, author_profile_snapshot, x_source_snapshot
  ) values (
    'x_sync', p_source_id, 'queued', v_snapshot->>'parameter_version', v_source.created_by,
    '{"mode":"window"}'::jsonb,
    jsonb_build_object(
      'mode', 'window', 'trigger', 'scheduled', 'timezone', 'Asia/Shanghai',
      'start_at', v_bounds->'start_at', 'end_at', v_bounds->'end_at',
      'scheduled_window_key', v_bounds->'scheduled_window_key', 'overlap_start_at', v_bounds->'start_at'
    ),
    '[]'::jsonb,
    jsonb_build_object('source_type', 'x', 'account_id', p_account_id,
      'display_name', v_snapshot->>'display_name', 'parameter_version', v_snapshot->>'parameter_version')
  ) returning * into v_task;
  insert into public.sync_task_capture_progress (task_id, source_id, capture_range)
  values (v_task.id, p_source_id, v_task.capture_range);
  insert into public.x_demo_fixed_window_tasks (task_id, source_id, cutoff_at, natural_date, start_at, end_at)
  values (v_task.id, p_source_id, p_cutoff_at, (v_bounds->>'natural_date')::date,
    (v_bounds->>'start_at')::timestamptz, p_cutoff_at);
  return to_jsonb(v_task) || jsonb_build_object('idempotent', false, 'demo_fixed_window', v_bounds);
end;
$$;

revoke all on function public.create_x_demo_fixed_window_task_for_run(uuid, uuid, timestamptz, uuid, text) from public, anon, authenticated;
grant execute on function public.create_x_demo_fixed_window_task_for_run(uuid, uuid, timestamptz, uuid, text) to service_role;

create or replace function public.claim_x_demo_fixed_window_task(
  p_task_id uuid, p_worker_id uuid, p_now timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_task public.sync_tasks%rowtype;
  v_attempt integer;
  v_lease_expires_at timestamptz;
  v_checkpoint text;
  v_coverage public.source_collection_coverage%rowtype;
  v_progress public.sync_task_capture_progress%rowtype;
begin
  if not exists (
    select 1 from public.workers
    where id = p_worker_id and status in ('enrolled', 'online')
      and capabilities @> array['x_sync']::text[]
  ) then
    raise exception 'worker_not_authorized' using errcode = '42501';
  end if;
  select task.* into v_task
  from public.sync_tasks task
  join public.x_demo_fixed_window_tasks demo on demo.task_id = task.id
  join public.sources source on source.id = task.source_id
  where task.id = p_task_id and task.task_type = 'x_sync' and source.source_type = 'x'
    and source.authorized_worker_id = p_worker_id and demo.cutoff_at <= clock_timestamp()
    and (task.status in ('queued', 'retryable_failed') or (task.status in ('leased', 'running') and task.lease_expires_at <= p_now))
  for update of task skip locked;
  if not found then return null; end if;
  update public.task_attempts set status = 'retryable_failed', completed_at = p_now
  where task_id = v_task.id and status in ('leased', 'running') and lease_expires_at <= p_now;
  select coalesce(max(attempt), 0) + 1 into v_attempt from public.task_attempts where task_id = v_task.id;
  v_lease_expires_at := p_now + interval '10 minutes';
  insert into public.task_attempts (task_id, attempt, worker_id, status, lease_expires_at, started_at)
  values (v_task.id, v_attempt, p_worker_id, 'leased', v_lease_expires_at, p_now);
  update public.sync_tasks set status = 'leased', lease_owner = p_worker_id, lease_expires_at = v_lease_expires_at where id = v_task.id;
  select safe_checkpoint into v_checkpoint from public.checkpoints where source_id = v_task.source_id;
  select * into v_coverage from public.source_collection_coverage where source_id = v_task.source_id;
  select * into v_progress from public.sync_task_capture_progress where task_id = v_task.id;
  insert into public.task_events (task_id, attempt, event_type, occurred_at, details)
  values (v_task.id, v_attempt, 'claimed', p_now, jsonb_build_object('worker_id', p_worker_id::text, 'lease_expires_at', v_lease_expires_at, 'scope', 'ticket_01_demo_fixed_window'));
  return jsonb_build_object(
    'contract_version', 'v0', 'task_id', v_task.id::text, 'attempt', v_attempt, 'task_type', v_task.task_type,
    'source_id', v_task.source_id::text, 'parameter_version', v_task.parameter_version, 'lease_expires_at', v_lease_expires_at,
    'safe_checkpoint', v_checkpoint, 'rule_snapshot', v_task.rule_snapshot, 'collection_scope', v_task.collection_scope,
    'capture_range', v_task.capture_range, 'coverage_snapshot', jsonb_build_object(
      'coverage_start_at', v_coverage.coverage_start_at, 'coverage_through_at', v_coverage.coverage_through_at,
      'last_completed_task_id', v_coverage.last_completed_task_id
    ), 'capture_progress', jsonb_build_object(
      'resume_cursor', v_progress.resume_cursor, 'page_count', v_progress.page_count, 'range_complete', v_progress.range_complete
    ), 'author_profile_snapshot', v_task.author_profile_snapshot, 'source_snapshot', v_task.x_source_snapshot
  );
end;
$$;

revoke all on function public.claim_x_demo_fixed_window_task(uuid, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.claim_x_demo_fixed_window_task(uuid, uuid, timestamptz) to service_role;

create or replace function public.terminalize_x_demo_fixed_window_judgement(
  p_demo_run_id uuid, p_judgement_run_id uuid, p_worker_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_demo public.x_demo_fixed_window_runs%rowtype;
  v_judgement public.x_daily_judgement_runs%rowtype;
begin
  select * into v_demo from public.x_demo_fixed_window_runs where id = p_demo_run_id for update;
  select * into v_judgement from public.x_daily_judgement_runs where id = p_judgement_run_id for update;
  if v_demo.id is null or v_judgement.id is null then
    raise exception 'invalid_x_demo_fixed_window_judgement' using errcode = '22023';
  end if;
  if v_demo.owner_worker_id <> p_worker_id
     or not exists (select 1 from public.workers where id = p_worker_id and status in ('enrolled', 'online') and capabilities @> array['x_sync']::text[])
     or exists (
       select 1 from public.x_collection_batch_sources batch_source
       join public.sources source on source.id = batch_source.source_id
       where batch_source.batch_id = v_demo.batch_id and source.authorized_worker_id is distinct from p_worker_id
     ) then
    raise exception 'worker_not_authorized' using errcode = '42501';
  end if;
  if v_judgement.batch_id <> v_demo.batch_id then
    raise exception 'invalid_x_demo_fixed_window_judgement' using errcode = '22023';
  end if;
  if v_judgement.status = 'failed' and v_judgement.attempt = 2 and v_judgement.lease_owner is null
     and v_demo.status = 'failed' then
    return jsonb_build_object('status', 'failed', 'demo_run_id', p_demo_run_id::text,
      'judgement_run_id', p_judgement_run_id::text, 'idempotent', true);
  end if;
  if v_demo.status not in ('complete', 'partial')
     or v_judgement.attempt <> 2 or v_judgement.status <> 'retryable_failed'
     or v_judgement.lease_owner is not null or v_judgement.lease_expires_at is not null then
    raise exception 'invalid_x_demo_fixed_window_judgement' using errcode = '22023';
  end if;
  perform set_config('invest_hub.ticket_02r_demo_run_id', p_demo_run_id::text, true);
  perform set_config('invest_hub.ticket_02r_judgement_run_id', p_judgement_run_id::text, true);
  update public.x_daily_judgement_runs set status = 'failed' where id = v_judgement.id;
  update public.x_collection_batches set status = 'judgement_failed' where id = v_demo.batch_id;
  update public.x_demo_fixed_window_runs set status = 'failed', updated_at = clock_timestamp() where id = v_demo.id;
  return jsonb_build_object('status', 'failed', 'demo_run_id', p_demo_run_id::text,
    'judgement_run_id', p_judgement_run_id::text, 'idempotent', false);
end;
$$;

revoke all on function public.terminalize_x_demo_fixed_window_judgement(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.terminalize_x_demo_fixed_window_judgement(uuid, uuid, uuid) to service_role;

create or replace function public.enforce_x_daily_judgement_run_transition()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.id is distinct from old.id
     or new.batch_id is distinct from old.batch_id
     or new.run_kind is distinct from old.run_kind
     or new.requested_by is distinct from old.requested_by
     or new.created_at is distinct from old.created_at then
    raise exception 'x_daily_judgement_run_immutable' using errcode = '55000';
  end if;
  if old.status in ('succeeded', 'failed') then
    raise exception 'x_daily_judgement_run_terminal' using errcode = '55000';
  end if;
  if new.attempt < old.attempt or new.attempt > old.attempt + 1
     or (new.attempt = old.attempt + 1 and new.status <> 'leased')
     or (new.status <> 'leased' and new.attempt <> old.attempt) then
    raise exception 'invalid_x_daily_judgement_attempt_transition' using errcode = '55000';
  end if;
  if new.status is distinct from old.status and not (
    (old.status in ('queued', 'retryable_failed') and new.status = 'leased')
    or (old.status = 'retryable_failed' and old.attempt >= 3 and new.status = 'failed')
    or (old.status in ('leased', 'running') and new.status in ('running', 'retryable_failed', 'failed', 'succeeded'))
    or (
      old.run_kind = 'regeneration'
      and old.status in ('queued', 'retryable_failed')
      and new.status = 'failed'
      and new.failure_class = 'schema_error'
      and (
        select version.coverage_status
        from public.x_daily_judgement_versions version
        where version.batch_id = old.batch_id
        order by version.revision desc
        limit 1
      ) = 'no_new_information'
    )
    or (
      old.run_kind = 'initial'
      and old.status = 'retryable_failed'
      and old.attempt = 2
      and new.status = 'failed'
      and new.attempt = old.attempt
      and coalesce(current_setting('invest_hub.ticket_02r_demo_run_id', true), '') <> ''
      and exists (select 1 from public.x_demo_fixed_window_runs demo where demo.id::text = current_setting('invest_hub.ticket_02r_demo_run_id', true) and demo.batch_id = old.batch_id and demo.status in ('complete', 'partial'))
      and coalesce(current_setting('invest_hub.ticket_02r_judgement_run_id', true), '') = old.id::text
      and new.failure_class is not distinct from old.failure_class
      and new.lease_owner is not distinct from old.lease_owner
      and new.lease_expires_at is not distinct from old.lease_expires_at
      and new.available_at is not distinct from old.available_at
    )
  ) then
    raise exception 'invalid_x_daily_judgement_run_transition' using errcode = '55000';
  end if;
  return new;
end;
$$;
