-- Ticket 01 only: an explicit, already-ended target cutoff gets a scoped
-- claim before the legacy continuous-waterline queue.  No drain or scheduler
-- policy is changed here.

create or replace function public.create_x_demo_fixed_window_task_for_worker(
  p_source_id uuid,
  p_cutoff_at timestamptz,
  p_worker_id uuid,
  p_account_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_source public.sources%rowtype;
  v_profile public.x_source_profiles%rowtype;
begin
  if not exists (
    select 1 from public.workers
    where id = p_worker_id and status in ('enrolled', 'online')
  ) then
    raise exception 'worker_not_authorized' using errcode = '42501';
  end if;
  select * into v_source from public.sources
  where id = p_source_id and source_type = 'x' and enabled and authorized_worker_id = p_worker_id
  for update;
  if not found then raise exception 'worker_not_authorized' using errcode = '42501'; end if;
  select * into v_profile from public.x_source_profiles
  where source_id = p_source_id and enabled
  for update;
  if not found or v_profile.resolution_status <> 'resolved' or v_profile.account_id is null then
    raise exception 'x_source_unresolved' using errcode = '22023';
  end if;
  if p_account_id is null or v_profile.account_id <> p_account_id then
    raise exception 'x_source_identity_mismatch' using errcode = '22023';
  end if;
  return public.create_x_demo_fixed_window_task(p_source_id, p_cutoff_at, v_source.created_by);
end;
$$;

revoke all on function public.create_x_demo_fixed_window_task_for_worker(uuid, timestamptz, uuid, text) from public, anon, authenticated;
grant execute on function public.create_x_demo_fixed_window_task_for_worker(uuid, timestamptz, uuid, text) to service_role;

create or replace function public.claim_x_demo_fixed_window_task(
  p_task_id uuid,
  p_worker_id uuid,
  p_now timestamptz
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
  ) then
    raise exception 'worker_not_authorized' using errcode = '42501';
  end if;

  select task.* into v_task
  from public.sync_tasks task
  join public.x_demo_fixed_window_tasks demo on demo.task_id = task.id
  join public.sources source on source.id = task.source_id
  where task.id = p_task_id
    and task.task_type = 'x_sync'
    and source.source_type = 'x'
    and source.enabled
    and source.authorized_worker_id = p_worker_id
    and demo.cutoff_at <= clock_timestamp()
    and (
      task.status in ('queued', 'retryable_failed')
      or (task.status in ('leased', 'running') and task.lease_expires_at <= p_now)
    )
  for update of task skip locked;
  if not found then return null; end if;

  update public.task_attempts
  set status = 'retryable_failed', completed_at = p_now
  where task_id = v_task.id
    and status in ('leased', 'running')
    and lease_expires_at <= p_now;
  select coalesce(max(attempt), 0) + 1 into v_attempt from public.task_attempts where task_id = v_task.id;
  v_lease_expires_at := p_now + interval '10 minutes';
  insert into public.task_attempts (task_id, attempt, worker_id, status, lease_expires_at, started_at)
  values (v_task.id, v_attempt, p_worker_id, 'leased', v_lease_expires_at, p_now);
  update public.sync_tasks
  set status = 'leased', lease_owner = p_worker_id, lease_expires_at = v_lease_expires_at
  where id = v_task.id;

  select safe_checkpoint into v_checkpoint from public.checkpoints where source_id = v_task.source_id;
  select * into v_coverage from public.source_collection_coverage where source_id = v_task.source_id;
  select * into v_progress from public.sync_task_capture_progress where task_id = v_task.id;
  insert into public.task_events (task_id, attempt, event_type, occurred_at, details)
  values (v_task.id, v_attempt, 'claimed', p_now,
    jsonb_build_object('worker_id', p_worker_id::text, 'lease_expires_at', v_lease_expires_at, 'scope', 'ticket_01_demo_fixed_window'));

  return jsonb_build_object(
    'contract_version', 'v0', 'task_id', v_task.id::text, 'attempt', v_attempt,
    'task_type', v_task.task_type, 'source_id', v_task.source_id::text,
    'parameter_version', v_task.parameter_version, 'lease_expires_at', v_lease_expires_at,
    'safe_checkpoint', v_checkpoint, 'rule_snapshot', v_task.rule_snapshot,
    'collection_scope', v_task.collection_scope, 'capture_range', v_task.capture_range,
    'coverage_snapshot', jsonb_build_object(
      'coverage_start_at', v_coverage.coverage_start_at,
      'coverage_through_at', v_coverage.coverage_through_at,
      'last_completed_task_id', v_coverage.last_completed_task_id
    ),
    'capture_progress', jsonb_build_object(
      'resume_cursor', v_progress.resume_cursor, 'page_count', v_progress.page_count, 'range_complete', v_progress.range_complete
    ),
    'author_profile_snapshot', v_task.author_profile_snapshot,
    'source_snapshot', v_task.x_source_snapshot
  );
end;
$$;

revoke all on function public.claim_x_demo_fixed_window_task(uuid, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.claim_x_demo_fixed_window_task(uuid, uuid, timestamptz) to service_role;

create or replace function public.claim_next_x_demo_fixed_window_task(
  p_worker_id uuid,
  p_now timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_task public.sync_tasks%rowtype;
  v_source public.sources%rowtype;
  v_attempt integer;
  v_lease_expires_at timestamptz;
  v_checkpoint text;
  v_coverage public.source_collection_coverage%rowtype;
  v_progress public.sync_task_capture_progress%rowtype;
begin
  if not exists (
    select 1 from public.workers
    where id = p_worker_id and status in ('enrolled', 'online')
  ) then
    raise exception 'worker_not_authorized' using errcode = '42501';
  end if;

  select task.* into v_task
  from public.sync_tasks task
  join public.x_demo_fixed_window_tasks demo on demo.task_id = task.id
  join public.sources source on source.id = task.source_id
  where task.task_type = 'x_sync'
    and source.source_type = 'x'
    and source.enabled
    and source.authorized_worker_id = p_worker_id
    and demo.cutoff_at <= clock_timestamp()
    and (
      task.status in ('queued', 'retryable_failed')
      or (task.status in ('leased', 'running') and task.lease_expires_at <= p_now)
    )
  order by demo.cutoff_at, task.queued_at, task.id
  for update of task skip locked
  limit 1;
  if not found then return null; end if;

  update public.task_attempts
  set status = 'retryable_failed', completed_at = p_now
  where task_id = v_task.id
    and status in ('leased', 'running')
    and lease_expires_at <= p_now;
  select coalesce(max(attempt), 0) + 1 into v_attempt from public.task_attempts where task_id = v_task.id;
  v_lease_expires_at := p_now + interval '10 minutes';
  insert into public.task_attempts (task_id, attempt, worker_id, status, lease_expires_at, started_at)
  values (v_task.id, v_attempt, p_worker_id, 'leased', v_lease_expires_at, p_now);
  update public.sync_tasks
  set status = 'leased', lease_owner = p_worker_id, lease_expires_at = v_lease_expires_at
  where id = v_task.id;

  select safe_checkpoint into v_checkpoint from public.checkpoints where source_id = v_task.source_id;
  select * into v_coverage from public.source_collection_coverage where source_id = v_task.source_id;
  select * into v_progress from public.sync_task_capture_progress where task_id = v_task.id;
  insert into public.task_events (task_id, attempt, event_type, occurred_at, details)
  values (v_task.id, v_attempt, 'claimed', p_now,
    jsonb_build_object('worker_id', p_worker_id::text, 'lease_expires_at', v_lease_expires_at, 'scope', 'ticket_01_demo_fixed_window'));

  return jsonb_build_object(
    'contract_version', 'v0', 'task_id', v_task.id::text, 'attempt', v_attempt,
    'task_type', v_task.task_type, 'source_id', v_task.source_id::text,
    'parameter_version', v_task.parameter_version, 'lease_expires_at', v_lease_expires_at,
    'safe_checkpoint', v_checkpoint, 'rule_snapshot', v_task.rule_snapshot,
    'collection_scope', v_task.collection_scope, 'capture_range', v_task.capture_range,
    'coverage_snapshot', jsonb_build_object(
      'coverage_start_at', v_coverage.coverage_start_at,
      'coverage_through_at', v_coverage.coverage_through_at,
      'last_completed_task_id', v_coverage.last_completed_task_id
    ),
    'capture_progress', jsonb_build_object(
      'resume_cursor', v_progress.resume_cursor, 'page_count', v_progress.page_count, 'range_complete', v_progress.range_complete
    ),
    'author_profile_snapshot', v_task.author_profile_snapshot,
    'source_snapshot', v_task.x_source_snapshot
  );
end;
$$;

revoke all on function public.claim_next_x_demo_fixed_window_task(uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.claim_next_x_demo_fixed_window_task(uuid, timestamptz) to service_role;

create or replace function public.claim_next_task(
  p_worker_id uuid,
  p_now timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_demo_claim jsonb;
  v_claim jsonb;
  v_task public.sync_tasks%rowtype;
  v_progress public.sync_task_capture_progress%rowtype;
  v_coverage public.source_collection_coverage%rowtype;
begin
  v_demo_claim := public.claim_next_x_demo_fixed_window_task(p_worker_id, p_now);
  if v_demo_claim is not null then return v_demo_claim; end if;

  v_claim := public.claim_next_task_v2_base(p_worker_id, p_now);
  if v_claim is null or v_claim->>'task_type' <> 'x_sync' then return v_claim; end if;
  select * into v_task from public.sync_tasks where id = (v_claim->>'task_id')::uuid;
  if not found or v_task.x_source_snapshot is null or v_task.capture_range is null then
    raise exception 'x_task_snapshot_missing' using errcode = '22023';
  end if;
  if v_task.collection_scope->>'mode' = 'history' then
    select * into v_progress from public.sync_task_capture_progress where task_id = v_task.id;
    select * into v_coverage from public.source_collection_coverage where source_id = v_task.source_id;
    if not found or v_progress.task_id is null then
      raise exception 'x_history_claim_missing_progress' using errcode = '22023';
    end if;
    v_claim := v_claim || jsonb_build_object(
      'capture_range', v_task.capture_range,
      'coverage_snapshot', jsonb_build_object(
        'coverage_start_at', v_coverage.coverage_start_at,
        'coverage_through_at', v_coverage.coverage_through_at,
        'last_completed_task_id', v_coverage.last_completed_task_id
      ),
      'capture_progress', jsonb_build_object(
        'resume_cursor', v_progress.resume_cursor, 'page_count', v_progress.page_count, 'range_complete', v_progress.range_complete
      ),
      'author_profile_snapshot', v_task.author_profile_snapshot
    );
  end if;
  return v_claim || jsonb_build_object('source_id', v_task.source_id::text, 'source_snapshot', v_task.x_source_snapshot);
end;
$$;

revoke all on function public.claim_next_task(uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.claim_next_task(uuid, timestamptz) to service_role;

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
  v_demo boolean;
  v_task public.sync_tasks%rowtype;
  v_original_coverage public.source_collection_coverage%rowtype;
  v_result jsonb;
begin
  select exists (select 1 from public.x_demo_fixed_window_tasks where task_id = p_task_id) into v_demo;
  if not v_demo then
    if exists (
      select 1 from jsonb_array_elements(coalesce(p_payload->'x_post_analyses', '[]'::jsonb)) item
      where item->>'schema_version' = 'v4-x-post-analysis'
    ) then
      return public.complete_windowed_capture_range_v4_x_core(p_task_id, p_attempt, p_worker_id, p_payload);
    end if;
    if exists (select 1 from jsonb_array_elements(coalesce(p_payload->'x_post_analyses', '[]'::jsonb)) item where item->>'schema_version' = 'v3-x-post-analysis') then
      return public.complete_windowed_capture_range_v3_x_core(p_task_id, p_attempt, p_worker_id, p_payload);
    end if;
    return public.complete_windowed_capture_range_v2_x_core(p_task_id, p_attempt, p_worker_id, p_payload);
  end if;

  select * into v_task from public.sync_tasks where id = p_task_id for update;
  if not found or v_task.task_type <> 'x_sync' then raise exception 'invalid_x_range_completion' using errcode = '22023'; end if;
  select * into v_original_coverage from public.source_collection_coverage where source_id = v_task.source_id for update;
  if not found then raise exception 'coverage_not_initialized' using errcode = '55000'; end if;

  -- The demo task is intentionally non-contiguous.  The v4 core still owns
  -- all receipt, evidence, analysis and segment validation; this temporary
  -- waterline lets it ignore only predecessor ranges fully before this task.
  update public.source_collection_coverage
  set coverage_through_at = (v_task.capture_range->>'start_at')::timestamptz,
      last_completed_task_id = null
  where source_id = v_task.source_id;
  if exists (
    select 1 from jsonb_array_elements(coalesce(p_payload->'x_post_analyses', '[]'::jsonb)) item
    where item->>'schema_version' = 'v4-x-post-analysis'
  ) then
    v_result := public.complete_windowed_capture_range_v4_x_core(p_task_id, p_attempt, p_worker_id, p_payload);
  elsif exists (select 1 from jsonb_array_elements(coalesce(p_payload->'x_post_analyses', '[]'::jsonb)) item where item->>'schema_version' = 'v3-x-post-analysis') then
    v_result := public.complete_windowed_capture_range_v3_x_core(p_task_id, p_attempt, p_worker_id, p_payload);
  else
    v_result := public.complete_windowed_capture_range_v2_x_core(p_task_id, p_attempt, p_worker_id, p_payload);
  end if;
  update public.source_collection_coverage
  set coverage_start_at = v_original_coverage.coverage_start_at,
      coverage_through_at = v_original_coverage.coverage_through_at,
      last_completed_task_id = v_original_coverage.last_completed_task_id
  where source_id = v_task.source_id;
  return v_result
    || jsonb_build_object('demo_fixed_window', true, 'history_contiguous', false,
      'coverage_through_at', v_original_coverage.coverage_through_at::text);
exception when sqlstate '40001' then
  raise sqlstate 'PT409' using message = sqlerrm;
end;
$$;

revoke all on function public.complete_windowed_capture_range(uuid, integer, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.complete_windowed_capture_range(uuid, integer, uuid, jsonb) to service_role;
