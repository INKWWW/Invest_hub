-- X collection requires an explicit Worker binding.  Unlike the legacy
-- Discord path, an unbound X source cannot be safely collected by a generic
-- Worker because the local X configuration contains one authenticated source.

create or replace function public.claim_next_task_base(p_worker_id uuid, p_now timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_task public.sync_tasks%rowtype;
  v_attempt integer;
  v_checkpoint text;
  v_lease_expires_at timestamptz;
  v_coverage public.source_collection_coverage%rowtype;
  v_progress public.sync_task_capture_progress%rowtype;
begin
  if not exists (
    select 1 from public.workers
    where id = p_worker_id and status in ('enrolled', 'online')
  ) then
    raise exception 'worker_not_authorized' using errcode = '42501';
  end if;

  select t.* into v_task
  from public.sync_tasks t
  join public.sources s on s.id = t.source_id and s.enabled
  where (
    t.status in ('queued', 'retryable_failed')
    or (t.status in ('leased', 'running') and t.lease_expires_at <= p_now)
  )
    and (
      (s.source_type = 'x' and s.authorized_worker_id = p_worker_id)
      or (
        s.source_type <> 'x'
        and (s.authorized_worker_id is null or s.authorized_worker_id = p_worker_id)
      )
    )
    and (
      t.collection_scope->>'mode' <> 'window'
      or not exists (
        select 1
        from public.sync_tasks predecessor
        where predecessor.source_id = t.source_id
          and predecessor.id <> t.id
          and predecessor.collection_scope->>'mode' = 'window'
          and (predecessor.capture_range->>'end_at')::timestamptz <= (t.capture_range->>'start_at')::timestamptz
          and predecessor.status <> 'succeeded'
      )
    )
  order by t.queued_at, t.id
  for update of t skip locked
  limit 1;

  if not found then
    return null;
  end if;

  update public.task_attempts
  set status = 'retryable_failed', completed_at = p_now
  where task_id = v_task.id
    and status in ('leased', 'running')
    and lease_expires_at <= p_now;

  select coalesce(max(attempt), 0) + 1 into v_attempt
  from public.task_attempts
  where task_id = v_task.id;

  v_lease_expires_at := p_now + interval '10 minutes';

  insert into public.task_attempts (task_id, attempt, worker_id, status, lease_expires_at, started_at)
  values (v_task.id, v_attempt, p_worker_id, 'leased', v_lease_expires_at, p_now);

  update public.sync_tasks
  set status = 'leased', lease_owner = p_worker_id, lease_expires_at = v_lease_expires_at
  where id = v_task.id;

  select c.safe_checkpoint into v_checkpoint
  from public.checkpoints c
  where c.source_id = v_task.source_id;

  if v_task.collection_scope->>'mode' = 'window' then
    select * into v_coverage
    from public.source_collection_coverage
    where source_id = v_task.source_id;
    select * into v_progress
    from public.sync_task_capture_progress
    where task_id = v_task.id;
  end if;

  insert into public.task_events (task_id, attempt, event_type, occurred_at, details)
  values (
    v_task.id,
    v_attempt,
    'claimed',
    p_now,
    jsonb_build_object('worker_id', p_worker_id::text, 'lease_expires_at', v_lease_expires_at)
  );

  return jsonb_build_object(
    'contract_version', 'v0',
    'task_id', v_task.id::text,
    'attempt', v_attempt,
    'task_type', v_task.task_type,
    'source_id', (select source_key from public.sources where id = v_task.source_id),
    'parameter_version', v_task.parameter_version,
    'lease_expires_at', v_lease_expires_at,
    'safe_checkpoint', v_checkpoint,
    'rule_snapshot', v_task.rule_snapshot,
    'collection_scope', v_task.collection_scope
  ) || case when v_task.collection_scope->>'mode' = 'window' then jsonb_build_object(
    'capture_range', v_task.capture_range,
    'coverage_snapshot', jsonb_build_object(
      'coverage_start_at', v_coverage.coverage_start_at,
      'coverage_through_at', v_coverage.coverage_through_at,
      'last_completed_task_id', v_coverage.last_completed_task_id
    ),
    'capture_progress', jsonb_build_object(
      'resume_cursor', v_progress.resume_cursor,
      'page_count', v_progress.page_count,
      'range_complete', v_progress.range_complete
    ),
    'author_profile_snapshot', v_task.author_profile_snapshot
  ) else '{}'::jsonb end;
end;
$$;

create or replace function public.claim_next_task(p_worker_id uuid, p_now timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_claim jsonb;
  v_task public.sync_tasks%rowtype;
  v_progress public.sync_task_capture_progress%rowtype;
  v_coverage public.source_collection_coverage%rowtype;
begin
  v_claim := public.claim_next_task_v2_base(p_worker_id, p_now);
  if v_claim is null or v_claim->>'task_type' <> 'x_sync' then
    return v_claim;
  end if;
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
        'resume_cursor', v_progress.resume_cursor,
        'page_count', v_progress.page_count,
        'range_complete', v_progress.range_complete
      ),
      'author_profile_snapshot', v_task.author_profile_snapshot
    );
  end if;
  return v_claim || jsonb_build_object(
    'source_id', v_task.source_id::text,
    'source_snapshot', v_task.x_source_snapshot
  );
end;
$$;

revoke all on function public.claim_next_task_base(uuid, timestamptz)
  from public, anon, authenticated, service_role;
revoke all on function public.claim_next_task(uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.claim_next_task(uuid, timestamptz) to service_role;
