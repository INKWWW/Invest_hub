-- A page identity is stable across task attempts.  Retrying a task must be able
-- to reuse a page already durably persisted by a previous attempt, but only
-- when every page-boundary field matches exactly.
create or replace function public.record_windowed_capture_segment(
  p_task_id uuid,
  p_attempt integer,
  p_worker_id uuid,
  p_segment jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_task public.sync_tasks%rowtype;
  v_attempt public.task_attempts%rowtype;
  v_progress public.sync_task_capture_progress%rowtype;
  v_existing public.sync_task_capture_segments%rowtype;
  v_request_cursor text;
  v_next_cursor text;
  v_oldest_at timestamptz;
  v_newest_at timestamptz;
  v_segment_id uuid;
begin
  if p_segment is null
     or jsonb_typeof(p_segment) <> 'object'
     or (p_segment - 'idempotency_key' - 'request_cursor' - 'next_cursor' - 'oldest_occurred_at' - 'newest_occurred_at' - 'response_matched' - 'response_fresh') <> '{}'::jsonb
     or jsonb_typeof(p_segment->'idempotency_key') <> 'string'
     or jsonb_typeof(p_segment->'request_cursor') not in ('string', 'null')
     or jsonb_typeof(p_segment->'next_cursor') not in ('string', 'null')
     or jsonb_typeof(p_segment->'oldest_occurred_at') not in ('string', 'null')
     or jsonb_typeof(p_segment->'newest_occurred_at') not in ('string', 'null')
     or jsonb_typeof(p_segment->'response_matched') <> 'boolean'
     or jsonb_typeof(p_segment->'response_fresh') <> 'boolean'
     or coalesce((p_segment->>'response_matched')::boolean, false) is not true
     or coalesce((p_segment->>'response_fresh')::boolean, false) is not true then
    raise exception 'invalid_capture_segment' using errcode = '22023';
  end if;

  v_request_cursor := p_segment->>'request_cursor';
  v_next_cursor := p_segment->>'next_cursor';
  begin
    v_oldest_at := nullif(p_segment->>'oldest_occurred_at', '')::timestamptz;
    v_newest_at := nullif(p_segment->>'newest_occurred_at', '')::timestamptz;
  exception when invalid_datetime_format or datetime_field_overflow then
    raise exception 'invalid_capture_segment' using errcode = '22023';
  end;

  if v_next_cursor is not null and v_next_cursor = v_request_cursor then
    raise exception 'invalid_capture_segment' using errcode = '22023';
  end if;

  select * into v_task
  from public.sync_tasks
  where id = p_task_id
  for update;

  select * into v_attempt
  from public.task_attempts
  where task_id = p_task_id and attempt = p_attempt
  for update;

  if not found
     or v_task.collection_scope->>'mode' <> 'window'
     or v_task.lease_owner <> p_worker_id
     or v_task.status not in ('leased', 'running')
     or v_attempt.worker_id <> p_worker_id
     or v_attempt.status not in ('leased', 'running') then
    raise exception 'lease_mismatch' using errcode = '40001';
  end if;

  select * into v_progress
  from public.sync_task_capture_progress
  where task_id = p_task_id
  for update;

  if not found then
    raise exception 'capture_progress_missing' using errcode = '55000';
  end if;

  select * into v_existing
  from public.sync_task_capture_segments
  where task_id = p_task_id and idempotency_key = p_segment->>'idempotency_key'
  for update;

  if found then
    if v_existing.request_cursor is distinct from v_request_cursor
       or v_existing.next_cursor is distinct from v_next_cursor
       or v_existing.oldest_occurred_at is distinct from v_oldest_at
       or v_existing.newest_occurred_at is distinct from v_newest_at
       or not v_existing.response_matched
       or not v_existing.response_fresh then
      raise exception 'conflicting_capture_segment' using errcode = '23505';
    end if;
    return jsonb_build_object(
      'task_id', p_task_id::text,
      'idempotency_key', v_existing.idempotency_key,
      'idempotent', true,
      'resume_cursor', v_progress.resume_cursor
    );
  end if;

  if v_progress.resume_cursor is distinct from v_request_cursor then
    raise exception 'resume_cursor_mismatch' using errcode = '40001';
  end if;

  insert into public.sync_task_capture_segments (
    task_id, attempt, idempotency_key, request_cursor, next_cursor, oldest_occurred_at, newest_occurred_at, response_matched, response_fresh
  ) values (
    p_task_id, p_attempt, p_segment->>'idempotency_key', v_request_cursor, v_next_cursor, v_oldest_at, v_newest_at, true, true
  ) returning id into v_segment_id;

  update public.sync_task_capture_progress
  set resume_cursor = v_next_cursor,
      page_count = page_count + 1,
      oldest_verified_at = case
        when v_oldest_at is null then oldest_verified_at
        when oldest_verified_at is null or v_oldest_at < oldest_verified_at then v_oldest_at
        else oldest_verified_at
      end,
      newest_verified_at = case
        when v_newest_at is null then newest_verified_at
        when newest_verified_at is null or v_newest_at > newest_verified_at then v_newest_at
        else newest_verified_at
      end
  where task_id = p_task_id;

  return jsonb_build_object(
    'task_id', p_task_id::text,
    'segment_id', v_segment_id::text,
    'idempotent', false,
    'resume_cursor', v_next_cursor
  );
end;
$$;
