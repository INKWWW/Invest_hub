-- Expired X windows are bounded recovery facts, not an unlimited retry source.
-- The existing gap transition remains the single writer for coverage advancement.

create or replace function public.reap_expired_x_window_tasks(p_worker_id uuid, p_now timestamptz)
returns integer
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_source record;
  v_task public.sync_tasks%rowtype;
  v_attempt public.task_attempts%rowtype;
  v_failure jsonb;
  v_reaped integer := 0;
begin
  if p_now is null then
    raise exception 'invalid_expired_x_window_time' using errcode = '22023';
  end if;

  for v_source in
    select source.id
    from public.sources source
    where source.source_type = 'x'
      and source.enabled
      and source.authorized_worker_id = p_worker_id
    order by source.id
  loop
    perform pg_advisory_xact_lock(hashtextextended(v_source.id::text, 24005));

    loop
      select task.* into v_task
      from public.sync_tasks task
      where task.source_id = v_source.id
        and task.task_type = 'x_sync'
        and task.collection_scope->>'mode' = 'window'
        and task.status in ('leased', 'running')
        and task.lease_expires_at <= p_now
        and (
          select coalesce(max(attempt), 0)
          from public.task_attempts attempt
          where attempt.task_id = task.id
        ) >= 2
      order by task.queued_at, task.id
      limit 1
      for update of task skip locked;

      if not found then
        exit;
      end if;

      select * into v_attempt
      from public.task_attempts
      where task_id = v_task.id
        and status in ('leased', 'running')
        and lease_expires_at <= p_now
      order by attempt desc
      limit 1
      for update;

      if not found or v_attempt.attempt < 2 then
        exit;
      end if;

      v_failure := jsonb_build_object(
        'contract_version', 'v0',
        'task_id', v_task.id::text,
        'attempt', v_attempt.attempt,
        'status', 'retryable_failed',
        'failure_class', 'lease_expired',
        'failure_stage', 'lease_expiry',
        'retryable', false
      );

      update public.task_attempts
      set status = 'failed', failure = v_failure, completed_at = p_now
      where id = v_attempt.id;

      update public.sync_tasks
      set status = 'failed', lease_owner = null, lease_expires_at = null
      where id = v_task.id;

      insert into public.task_events (task_id, attempt, event_type, occurred_at, details)
      values (
        v_task.id, v_attempt.attempt, 'failed', p_now,
        jsonb_build_object('failure_class', 'lease_expired', 'failure_stage', 'lease_expiry', 'retryable', false)
      );

      perform public.advance_x_failed_window_unchecked(v_task.id, v_failure, p_now);
      v_reaped := v_reaped + 1;
    end loop;
  end loop;

  return v_reaped;
end;
$$;

alter function public.claim_next_task_v2_base(uuid, timestamptz)
  rename to claim_next_task_v2_base_without_lease_reap;

create function public.claim_next_task_v2_base(p_worker_id uuid, p_now timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  perform public.reap_expired_x_window_tasks(p_worker_id, p_now);
  return public.claim_next_task_v2_base_without_lease_reap(p_worker_id, p_now);
end;
$$;

revoke all on function public.reap_expired_x_window_tasks(uuid, timestamptz)
  from public, anon, authenticated, service_role;
revoke all on function public.claim_next_task_v2_base_without_lease_reap(uuid, timestamptz)
  from public, anon, authenticated, service_role;
revoke all on function public.claim_next_task_v2_base(uuid, timestamptz)
  from public, anon, authenticated, service_role;
