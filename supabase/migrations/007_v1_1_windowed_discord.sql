alter table public.sync_tasks
  add column capture_range jsonb,
  add column author_profile_snapshot jsonb not null default '[]'::jsonb;

alter table public.sync_tasks
  drop constraint sync_tasks_collection_scope_shape;

alter table public.sync_tasks
  add constraint sync_tasks_capture_range_shape check (
    capture_range is null
    or (
      jsonb_typeof(capture_range) = 'object'
      and (capture_range - 'mode' - 'trigger' - 'timezone' - 'start_at' - 'end_at' - 'scheduled_window_key') = '{}'::jsonb
      and capture_range->>'mode' = 'window'
      and capture_range->>'trigger' in ('scheduled', 'manual', 'bootstrap')
      and capture_range->>'timezone' = 'Asia/Shanghai'
      and jsonb_typeof(capture_range->'start_at') = 'string'
      and jsonb_typeof(capture_range->'end_at') = 'string'
      and nullif(capture_range->>'start_at', '') is not null
      and nullif(capture_range->>'end_at', '') is not null
      and (capture_range->>'start_at')::timestamptz < (capture_range->>'end_at')::timestamptz
      and (
        (
          capture_range->>'trigger' = 'scheduled'
          and jsonb_typeof(capture_range->'scheduled_window_key') = 'string'
          and capture_range->>'scheduled_window_key' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T(00:00|08:00|16:00|20:50)[+]08:00$'
          and (capture_range->>'scheduled_window_key')::timestamptz = (capture_range->>'end_at')::timestamptz
        )
        or (
          capture_range->>'trigger' in ('manual', 'bootstrap')
          and jsonb_typeof(capture_range->'scheduled_window_key') = 'null'
        )
      )
    )
  ),
  add constraint sync_tasks_author_profile_snapshot_shape check (
    jsonb_typeof(author_profile_snapshot) = 'array'
  ),
  add constraint sync_tasks_collection_scope_shape check (
    (
      capture_range is null
      and jsonb_typeof(collection_scope) = 'object'
      and collection_scope->>'mode' in ('incremental', 'history')
      and jsonb_typeof(collection_scope->'max_pages') = 'number'
      and (collection_scope->>'max_pages')::numeric between 1 and 25
      and mod((collection_scope->>'max_pages')::numeric, 1) = 0
    )
    or (
      capture_range is not null
      and collection_scope = '{"mode":"window"}'::jsonb
    )
  );

create table public.source_collection_coverage (
  source_id uuid primary key references public.sources(id) on delete cascade,
  coverage_start_at timestamptz not null,
  coverage_through_at timestamptz not null,
  last_completed_task_id uuid references public.sync_tasks(id) on delete set null,
  initialized_by uuid references public.profiles(id) on delete set null,
  initialized_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  check (coverage_start_at <= coverage_through_at)
);

create trigger source_collection_coverage_set_updated_at before update on public.source_collection_coverage
for each row execute function public.set_updated_at();

create table public.sync_task_capture_progress (
  task_id uuid primary key references public.sync_tasks(id) on delete cascade,
  source_id uuid not null references public.sources(id) on delete cascade,
  capture_range jsonb not null,
  resume_cursor text,
  page_count integer not null default 0 check (page_count >= 0),
  oldest_verified_at timestamptz,
  newest_verified_at timestamptz,
  boundary_verified_at timestamptz,
  boundary_kind text check (boundary_kind in ('oldest_at_or_before_start', 'history_exhausted')),
  range_complete boolean not null default false,
  last_error jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  check (jsonb_typeof(capture_range) = 'object'),
  check (last_error is null or jsonb_typeof(last_error) = 'object'),
  check ((boundary_verified_at is null and boundary_kind is null) or (boundary_verified_at is not null and boundary_kind is not null))
);

create trigger sync_task_capture_progress_set_updated_at before update on public.sync_task_capture_progress
for each row execute function public.set_updated_at();

create table public.sync_task_capture_segments (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.sync_tasks(id) on delete cascade,
  attempt integer not null check (attempt > 0),
  idempotency_key text not null check (length(trim(idempotency_key)) > 0),
  request_cursor text,
  next_cursor text,
  oldest_occurred_at timestamptz,
  newest_occurred_at timestamptz,
  response_matched boolean not null,
  response_fresh boolean not null,
  created_at timestamptz not null default timezone('utc', now()),
  check (oldest_occurred_at is null or newest_occurred_at is null or oldest_occurred_at <= newest_occurred_at),
  check (next_cursor is null or request_cursor is null or next_cursor <> request_cursor),
  unique (task_id, idempotency_key)
);

create index sync_task_capture_segments_task_idx
  on public.sync_task_capture_segments (task_id, created_at);

create table public.source_author_profiles (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null references public.sources(id) on delete cascade,
  author_id text not null check (length(trim(author_id)) > 0),
  author_display text not null check (length(trim(author_display)) > 0),
  author_handle text,
  enabled boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (source_id, author_id)
);

create index source_author_profiles_source_enabled_idx
  on public.source_author_profiles (source_id, enabled, author_id);

create trigger source_author_profiles_set_updated_at before update on public.source_author_profiles
for each row execute function public.set_updated_at();

alter table public.scheduled_sync_windows
  drop constraint scheduled_sync_windows_window_key_check;

alter table public.scheduled_sync_windows
  add constraint scheduled_sync_windows_window_key_check check (
    window_key ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T(00:00|08:00|16:00|20:50)[+]08:00$'
  );

create or replace function public.initialize_discord_collection_coverage(
  p_source_id uuid,
  p_actor_id uuid,
  p_boundary timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_coverage public.source_collection_coverage%rowtype;
begin
  if not exists (
    select 1 from public.profiles where id = p_actor_id and role = 'admin'
  ) then
    raise exception 'actor_not_authorized' using errcode = '42501';
  end if;

  if p_boundary is null
     or to_char(p_boundary at time zone 'Asia/Shanghai', 'HH24:MI:SS') not in ('00:00:00', '08:00:00', '16:00:00', '20:50:00') then
    raise exception 'invalid_coverage_boundary' using errcode = '22023';
  end if;

  if not exists (
    select 1 from public.sources
    where id = p_source_id and source_type = 'discord'
  ) then
    raise exception 'source_not_found' using errcode = '22023';
  end if;

  select * into v_coverage
  from public.source_collection_coverage
  where source_id = p_source_id
  for update;

  if found then
    if v_coverage.coverage_start_at = p_boundary
       and v_coverage.coverage_through_at = p_boundary
       and v_coverage.last_completed_task_id is null then
      return jsonb_build_object(
        'source_id', p_source_id::text,
        'coverage_start_at', v_coverage.coverage_start_at,
        'coverage_through_at', v_coverage.coverage_through_at,
        'idempotent', true
      );
    end if;
    raise exception 'coverage_already_initialized' using errcode = '23505';
  end if;

  insert into public.source_collection_coverage (
    source_id, coverage_start_at, coverage_through_at, initialized_by
  ) values (
    p_source_id, p_boundary, p_boundary, p_actor_id
  ) returning * into v_coverage;

  return jsonb_build_object(
    'source_id', p_source_id::text,
    'coverage_start_at', v_coverage.coverage_start_at,
    'coverage_through_at', v_coverage.coverage_through_at,
    'idempotent', false
  );
end;
$$;

create or replace function public.create_windowed_discord_sync_task(
  p_source_id uuid,
  p_parameter_version text,
  p_requested_by uuid,
  p_trigger text,
  p_end_at timestamptz,
  p_scheduled_window_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_source public.sources%rowtype;
  v_coverage public.source_collection_coverage%rowtype;
  v_existing public.sync_tasks%rowtype;
  v_task public.sync_tasks%rowtype;
  v_author_profiles jsonb;
  v_capture_range jsonb;
begin
  if p_trigger not in ('scheduled', 'manual', 'bootstrap') or p_end_at is null then
    raise exception 'invalid_capture_range' using errcode = '22023';
  end if;

  if p_trigger in ('manual', 'bootstrap') and not exists (
    select 1 from public.profiles where id = p_requested_by and role = 'admin'
  ) then
    raise exception 'actor_not_authorized' using errcode = '42501';
  end if;

  if p_trigger = 'scheduled' then
    if p_requested_by is not null
       or p_scheduled_window_key is null
       or p_scheduled_window_key !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T(00:00|08:00|16:00|20:50)[+]08:00$'
       or p_scheduled_window_key::timestamptz <> p_end_at then
      raise exception 'invalid_capture_range' using errcode = '22023';
    end if;
  elsif p_scheduled_window_key is not null then
    raise exception 'invalid_capture_range' using errcode = '22023';
  end if;

  select * into v_source
  from public.sources
  where id = p_source_id and source_type = 'discord'
  for update;

  if not found then
    raise exception 'source_not_found' using errcode = '22023';
  end if;
  if not v_source.enabled then
    raise exception 'source_disabled' using errcode = '22023';
  end if;
  if p_parameter_version is null or p_parameter_version <> v_source.parameter_version then
    raise exception 'source_parameter_version_mismatch' using errcode = '22023';
  end if;

  select * into v_coverage
  from public.source_collection_coverage
  where source_id = p_source_id
  for update;

  if not found then
    raise exception 'coverage_not_initialized' using errcode = '22023';
  end if;
  if p_end_at <= v_coverage.coverage_through_at then
    raise exception 'invalid_capture_range' using errcode = '22023';
  end if;

  select * into v_existing
  from public.sync_tasks
  where source_id = p_source_id
    and collection_scope->>'mode' = 'window'
    and status in ('queued', 'leased', 'running', 'retryable_failed')
  order by (capture_range->>'end_at')::timestamptz, queued_at, id
  for update
  limit 1;

  if found then
    return to_jsonb(v_existing) || jsonb_build_object('idempotent', true);
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'author_id', profile.author_id,
        'author_display', profile.author_display,
        'author_handle', profile.author_handle,
        'enabled', profile.enabled
      )
      order by profile.author_id
    ),
    '[]'::jsonb
  )
  into v_author_profiles
  from public.source_author_profiles profile
  where profile.source_id = p_source_id and profile.enabled;

  v_capture_range := jsonb_build_object(
    'mode', 'window',
    'trigger', p_trigger,
    'timezone', 'Asia/Shanghai',
    'start_at', v_coverage.coverage_through_at,
    'end_at', p_end_at,
    'scheduled_window_key', case when p_trigger = 'scheduled' then to_jsonb(p_scheduled_window_key) else 'null'::jsonb end
  );

  insert into public.sync_tasks (
    task_type,
    source_id,
    parameter_version,
    requested_by,
    rule_snapshot,
    collection_scope,
    capture_range,
    author_profile_snapshot
  ) values (
    'discord_sync',
    p_source_id,
    p_parameter_version,
    p_requested_by,
    jsonb_build_object('version', v_source.author_rules_version, 'target_author_ids', '[]'::jsonb),
    '{"mode":"window"}'::jsonb,
    v_capture_range,
    v_author_profiles
  ) returning * into v_task;

  insert into public.sync_task_capture_progress (
    task_id, source_id, capture_range
  ) values (
    v_task.id, p_source_id, v_capture_range
  );

  return to_jsonb(v_task) || jsonb_build_object('idempotent', false);
end;
$$;

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
    if v_existing.attempt <> p_attempt
       or v_existing.request_cursor is distinct from v_request_cursor
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

create or replace function public.complete_windowed_capture_range(
  p_task_id uuid,
  p_attempt integer,
  p_worker_id uuid,
  p_payload jsonb
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
  v_coverage public.source_collection_coverage%rowtype;
  v_receipt public.worker_execution_receipts%rowtype;
  v_boundary_kind text;
  v_boundary_at timestamptz;
  v_capture_range jsonb;
begin
  if p_payload is null
     or jsonb_typeof(p_payload) <> 'object'
     or (p_payload - 'range_complete' - 'capture_range' - 'boundary' - 'summary_batch_ids' - 'daily_summary_ids' - 'no_new_data') <> '{}'::jsonb
     or coalesce((p_payload->>'range_complete')::boolean, false) is not true
     or jsonb_typeof(p_payload->'capture_range') <> 'object'
     or jsonb_typeof(p_payload->'boundary') <> 'object'
     or jsonb_typeof(p_payload->'summary_batch_ids') <> 'array'
     or jsonb_typeof(p_payload->'daily_summary_ids') <> 'array'
     or jsonb_typeof(p_payload->'no_new_data') <> 'boolean' then
    raise exception 'invalid_range_completion' using errcode = '22023';
  end if;

  v_capture_range := p_payload->'capture_range';
  v_boundary_kind := p_payload->'boundary'->>'kind';
  begin
    v_boundary_at := nullif(p_payload->'boundary'->>'observed_at', '')::timestamptz;
  exception when invalid_datetime_format or datetime_field_overflow then
    raise exception 'invalid_range_completion' using errcode = '22023';
  end;

  if v_boundary_kind not in ('oldest_at_or_before_start', 'history_exhausted')
     or v_boundary_at is null then
    raise exception 'invalid_range_completion' using errcode = '22023';
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

  begin
    if v_capture_range->>'mode' <> 'window'
       or v_capture_range->>'trigger' is distinct from v_task.capture_range->>'trigger'
       or v_capture_range->>'timezone' <> 'Asia/Shanghai'
       or (v_capture_range->>'start_at')::timestamptz <> (v_task.capture_range->>'start_at')::timestamptz
       or (v_capture_range->>'end_at')::timestamptz <> (v_task.capture_range->>'end_at')::timestamptz
       or v_capture_range->>'scheduled_window_key' is distinct from v_task.capture_range->>'scheduled_window_key' then
      raise exception 'invalid_range_completion' using errcode = '22023';
    end if;
  exception when invalid_datetime_format or datetime_field_overflow then
    raise exception 'invalid_range_completion' using errcode = '22023';
  end;

  if v_boundary_kind = 'oldest_at_or_before_start'
     and v_boundary_at > (v_task.capture_range->>'start_at')::timestamptz then
    raise exception 'invalid_range_completion' using errcode = '22023';
  end if;

  select * into v_progress
  from public.sync_task_capture_progress
  where task_id = p_task_id
  for update;

  select * into v_coverage
  from public.source_collection_coverage
  where source_id = v_task.source_id
  for update;

  if not found or v_coverage.coverage_through_at <> (v_task.capture_range->>'start_at')::timestamptz then
    raise exception 'coverage_waterline_mismatch' using errcode = '40001';
  end if;

  if exists (
    select 1
    from public.sync_tasks predecessor
    where predecessor.source_id = v_task.source_id
      and predecessor.id <> v_task.id
      and predecessor.collection_scope->>'mode' = 'window'
      and (predecessor.capture_range->>'end_at')::timestamptz <= (v_task.capture_range->>'start_at')::timestamptz
      and predecessor.status <> 'succeeded'
  ) then
    raise exception 'predecessor_range_incomplete' using errcode = '40001';
  end if;

  select * into v_receipt
  from public.worker_execution_receipts
  where task_id = p_task_id and attempt = p_attempt and worker_id = p_worker_id
  for update;

  if not found
     or v_receipt.summary_batch_ids <> p_payload->'summary_batch_ids'
     or v_receipt.daily_summary_ids <> p_payload->'daily_summary_ids' then
    raise exception 'persistence_not_confirmed' using errcode = '55000';
  end if;

  update public.sync_task_capture_progress
  set boundary_verified_at = v_boundary_at,
      boundary_kind = v_boundary_kind,
      range_complete = true,
      last_error = null
  where task_id = p_task_id;

  update public.task_attempts
  set status = 'succeeded',
      result = jsonb_build_object(
        'status', 'succeeded',
        'range_complete', true,
        'capture_range', v_task.capture_range,
        'summary_batch_ids', p_payload->'summary_batch_ids',
        'daily_summary_ids', p_payload->'daily_summary_ids',
        'no_new_data', p_payload->'no_new_data'
      ),
      completed_at = timezone('utc', now())
  where id = v_attempt.id;

  update public.sync_tasks
  set status = 'succeeded',
      lease_owner = null,
      lease_expires_at = null
  where id = v_task.id;

  update public.source_collection_coverage
  set coverage_through_at = (v_task.capture_range->>'end_at')::timestamptz,
      last_completed_task_id = v_task.id
  where source_id = v_task.source_id;

  insert into public.task_events (task_id, attempt, event_type, occurred_at, details)
  values (
    p_task_id,
    p_attempt,
    'succeeded',
    timezone('utc', now()),
    jsonb_build_object(
      'range_complete', true,
      'capture_range', v_task.capture_range,
      'boundary_kind', v_boundary_kind,
      'boundary_verified_at', v_boundary_at
    )
  );

  return jsonb_build_object(
    'status', 'succeeded',
    'idempotent', false,
    'task_id', p_task_id::text,
    'attempt', p_attempt,
    'coverage_through_at', v_task.capture_range->>'end_at'
  );
end;
$$;

create or replace function public.claim_next_task(p_worker_id uuid, p_now timestamptz)
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
    and (s.authorized_worker_id is null or s.authorized_worker_id = p_worker_id)
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

  return jsonb_strip_nulls(jsonb_build_object(
    'contract_version', 'v0',
    'task_id', v_task.id::text,
    'attempt', v_attempt,
    'task_type', v_task.task_type,
    'source_id', (select source_key from public.sources where id = v_task.source_id),
    'parameter_version', v_task.parameter_version,
    'lease_expires_at', v_lease_expires_at,
    'safe_checkpoint', v_checkpoint,
    'rule_snapshot', v_task.rule_snapshot,
    'collection_scope', v_task.collection_scope,
    'capture_range', v_task.capture_range,
    'coverage_snapshot', case when v_task.collection_scope->>'mode' = 'window' then jsonb_build_object(
      'coverage_start_at', v_coverage.coverage_start_at,
      'coverage_through_at', v_coverage.coverage_through_at,
      'last_completed_task_id', v_coverage.last_completed_task_id
    ) else null end,
    'capture_progress', case when v_task.collection_scope->>'mode' = 'window' then jsonb_build_object(
      'resume_cursor', v_progress.resume_cursor,
      'page_count', v_progress.page_count,
      'range_complete', v_progress.range_complete
    ) else null end,
    'author_profile_snapshot', case when v_task.collection_scope->>'mode' = 'window' then v_task.author_profile_snapshot else null end
  ));
end;
$$;

revoke all on function public.initialize_discord_collection_coverage(uuid, uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.create_windowed_discord_sync_task(uuid, text, uuid, text, timestamptz, text) from public, anon, authenticated;
revoke all on function public.record_windowed_capture_segment(uuid, integer, uuid, jsonb) from public, anon, authenticated;
revoke all on function public.complete_windowed_capture_range(uuid, integer, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.initialize_discord_collection_coverage(uuid, uuid, timestamptz) to service_role;
grant execute on function public.create_windowed_discord_sync_task(uuid, text, uuid, text, timestamptz, text) to service_role;
grant execute on function public.record_windowed_capture_segment(uuid, integer, uuid, jsonb) to service_role;
grant execute on function public.complete_windowed_capture_range(uuid, integer, uuid, jsonb) to service_role;

revoke all on table public.source_collection_coverage, public.sync_task_capture_progress, public.sync_task_capture_segments, public.source_author_profiles from public, anon, authenticated;
grant select, insert, update, delete on table public.source_collection_coverage, public.sync_task_capture_progress, public.sync_task_capture_segments, public.source_author_profiles to service_role;
grant select, insert, update, delete on table public.source_collection_coverage, public.sync_task_capture_progress, public.sync_task_capture_segments, public.source_author_profiles to authenticated;

alter table public.source_collection_coverage enable row level security;
alter table public.sync_task_capture_progress enable row level security;
alter table public.sync_task_capture_segments enable row level security;
alter table public.source_author_profiles enable row level security;

create policy source_collection_coverage_admin_all on public.source_collection_coverage
for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy sync_task_capture_progress_admin_all on public.sync_task_capture_progress
for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy sync_task_capture_segments_admin_all on public.sync_task_capture_segments
for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy source_author_profiles_admin_all on public.source_author_profiles
for all to authenticated using (public.is_admin()) with check (public.is_admin());
