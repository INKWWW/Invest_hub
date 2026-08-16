-- A terminal X window is an explicit coverage gap, not a successful capture.
-- The ledger is append-only and is written only from the source-locked failure
-- transition or the separately authorized historical skip function.

create table public.x_collection_gaps (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null references public.sources(id) on delete restrict,
  failed_task_id uuid not null unique references public.sync_tasks(id) on delete restrict,
  natural_date date not null,
  window_start_at timestamptz not null,
  window_end_at timestamptz not null,
  failure_class text not null check (failure_class in (
    'timeout', 'provider_failure', 'empty_response', 'invalid_json',
    'schema_error', 'persistence_failure', 'lease_expired', 'network_error',
    'preflight', 'unauthorized', 'opencli_contract', 'opencli_missing',
    'opencli_stale', 'unknown', 'historical_skip'
  )),
  skipped_at timestamptz not null,
  created_at timestamptz not null default timezone('utc', now()),
  unique (source_id, window_start_at, window_end_at),
  check (window_start_at < window_end_at),
  check (natural_date = public.x_collection_batch_logical_date(window_end_at))
);

create index x_collection_gaps_natural_date_source_idx
  on public.x_collection_gaps (natural_date, source_id, window_start_at);

alter table public.x_collection_gaps enable row level security;

create policy x_collection_gaps_admin_select on public.x_collection_gaps
for select to authenticated using (public.is_admin());

revoke insert, update, delete on public.x_collection_gaps from public, anon, authenticated, service_role;
grant select on public.x_collection_gaps to authenticated, service_role;

create or replace function public.reject_x_collection_gap_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception 'x_collection_gap_immutable' using errcode = '55000';
end;
$$;

create trigger x_collection_gaps_immutable
before update or delete on public.x_collection_gaps
for each row execute function public.reject_x_collection_gap_mutation();

create or replace function public.advance_x_failed_window_unchecked(
  p_failed_task_id uuid,
  p_failure jsonb,
  p_now timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_task public.sync_tasks%rowtype;
  v_coverage public.source_collection_coverage%rowtype;
  v_gap public.x_collection_gaps%rowtype;
  v_failure_class text;
  v_start_at timestamptz;
  v_end_at timestamptz;
  v_natural_date date;
  v_updated integer;
begin
  if p_failed_task_id is null or p_failure is null or jsonb_typeof(p_failure) <> 'object' or p_now is null then
    raise exception 'invalid_x_failed_window_transition' using errcode = '22023';
  end if;

  v_failure_class := p_failure->>'failure_class';
  if v_failure_class is null or v_failure_class not in (
    'timeout', 'provider_failure', 'empty_response', 'invalid_json',
    'schema_error', 'persistence_failure', 'lease_expired', 'network_error',
    'preflight', 'unauthorized', 'opencli_contract', 'opencli_missing',
    'opencli_stale', 'unknown', 'historical_skip'
  ) then
    raise exception 'unsafe_x_failure_class' using errcode = '22023';
  end if;

  select * into v_task
  from public.sync_tasks
  where id = p_failed_task_id
  for update;
  if not found
     or v_task.task_type <> 'x_sync'
     or v_task.status <> 'failed'
     or v_task.collection_scope->>'mode' <> 'window'
     or v_task.capture_range->>'mode' <> 'window'
     or v_task.capture_range->>'scheduled_window_key' is null then
    raise exception 'invalid_x_failed_window_task' using errcode = '22023';
  end if;

  v_start_at := (v_task.capture_range->>'start_at')::timestamptz;
  v_end_at := (v_task.capture_range->>'end_at')::timestamptz;
  if v_start_at is null or v_end_at is null or v_start_at >= v_end_at then
    raise exception 'invalid_x_failed_window_range' using errcode = '22023';
  end if;
  v_natural_date := public.x_collection_batch_logical_date(v_end_at);

  select * into v_gap
  from public.x_collection_gaps
  where failed_task_id = p_failed_task_id
  for update;
  if found then
    if v_gap.source_id <> v_task.source_id
       or v_gap.window_start_at <> v_start_at
       or v_gap.window_end_at <> v_end_at then
      raise exception 'conflicting_x_collection_gap' using errcode = '23505';
    end if;
    return jsonb_build_object('id', v_gap.id, 'task_id', p_failed_task_id, 'status', 'failed', 'idempotent', true);
  end if;

  select * into v_coverage
  from public.source_collection_coverage
  where source_id = v_task.source_id
  for update;
  if not found or v_coverage.coverage_through_at <> v_start_at then
    raise exception 'x_failed_window_waterline_mismatch' using errcode = '22023';
  end if;

  insert into public.x_collection_gaps (
    source_id, failed_task_id, natural_date, window_start_at, window_end_at,
    failure_class, skipped_at
  ) values (
    v_task.source_id, v_task.id, v_natural_date, v_start_at, v_end_at,
    v_failure_class, p_now
  ) returning * into v_gap;

  update public.source_collection_coverage
  set coverage_through_at = v_end_at
  where source_id = v_task.source_id
    and coverage_through_at = v_start_at;
  get diagnostics v_updated = row_count;
  if v_updated <> 1 then
    raise exception 'x_failed_window_waterline_mismatch' using errcode = '22023';
  end if;

  return jsonb_build_object(
    'id', v_gap.id, 'task_id', p_failed_task_id, 'status', 'failed',
    'coverage_through_at', v_end_at, 'idempotent', false
  );
end;
$$;

create or replace function public.record_task_failure_without_source_lock(
  p_task_id uuid,
  p_attempt integer,
  p_failure jsonb,
  p_context jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_task public.sync_tasks%rowtype;
  v_attempt public.task_attempts%rowtype;
  v_worker_id uuid;
  v_status text;
  v_attempt_status text;
  v_event_type text;
begin
  begin v_worker_id := nullif(p_context->>'worker_id', '')::uuid;
  exception when invalid_text_representation then raise exception 'worker_not_authorized' using errcode = '42501'; end;
  select * into v_task from public.sync_tasks where id = p_task_id for update;
  select * into v_attempt from public.task_attempts where task_id = p_task_id and attempt = p_attempt for update;
  if not found then raise exception 'attempt_not_found' using errcode = '22023'; end if;
  if v_attempt.status in ('failed', 'retryable_failed') then
    if v_attempt.failure = p_failure then return jsonb_build_object('status', v_attempt.status, 'idempotent', true, 'task_id', p_task_id::text, 'attempt', p_attempt); end if;
    raise exception 'conflicting_duplicate_failure' using errcode = '23505';
  end if;
  if v_task.id is null or v_attempt.worker_id <> v_worker_id or v_task.lease_owner <> v_worker_id
     or v_attempt.status not in ('leased', 'running') or v_task.status not in ('leased', 'running') then
    raise exception 'lease_mismatch' using errcode = '40001';
  end if;
  v_status := case when coalesce((p_failure->>'retryable')::boolean, false) then 'retryable_failed' when p_failure->>'status' = 'cancelled' then 'cancelled' else 'failed' end;
  v_attempt_status := case when v_status = 'cancelled' then 'failed' else v_status end;
  v_event_type := case when v_status = 'retryable_failed' then 'retry' else 'failed' end;
  update public.task_attempts set status = v_attempt_status, failure = p_failure, completed_at = timezone('utc', now()) where id = v_attempt.id;
  update public.sync_tasks set status = v_status, lease_owner = null, lease_expires_at = null where id = v_task.id;
  insert into public.task_events (task_id, attempt, event_type, occurred_at, details)
  values (p_task_id, p_attempt, v_event_type, timezone('utc', now()),
    jsonb_strip_nulls(jsonb_build_object('failure_class', p_failure->>'failure_class', 'failure_stage', p_failure->>'failure_stage', 'retryable', p_failure->>'retryable')));

  if v_task.task_type = 'x_sync'
     and v_task.collection_scope->>'mode' = 'window'
     and p_failure->>'status' = 'retryable_failed'
     and coalesce((p_failure->>'retryable')::boolean, false) = false then
    perform public.advance_x_failed_window_unchecked(p_task_id, p_failure, timezone('utc', now()));
  end if;

  return jsonb_build_object('status', v_status, 'idempotent', false, 'task_id', p_task_id::text, 'attempt', p_attempt);
end;
$$;

create or replace function public.skip_terminal_x_window(
  p_failed_task_id uuid,
  p_actor_id uuid,
  p_now timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_source_id uuid;
begin
  if p_actor_id is null or not exists (
    select 1 from public.profiles where id = p_actor_id and role = 'admin'
  ) then
    raise exception 'actor_not_authorized' using errcode = '42501';
  end if;
  select source_id into v_source_id from public.sync_tasks where id = p_failed_task_id;
  if v_source_id is null then
    raise exception 'terminal_x_window_not_found' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(v_source_id::text, 24005));
  return public.advance_x_failed_window_unchecked(
    p_failed_task_id,
    jsonb_build_object('status', 'retryable_failed', 'failure_class', 'historical_skip', 'retryable', false),
    p_now
  );
end;
$$;

revoke all on function public.advance_x_failed_window_unchecked(uuid, jsonb, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.record_task_failure_without_source_lock(uuid, integer, jsonb, jsonb) from public, anon, authenticated, service_role;
revoke all on function public.skip_terminal_x_window(uuid, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.skip_terminal_x_window(uuid, uuid, timestamptz) to service_role;
