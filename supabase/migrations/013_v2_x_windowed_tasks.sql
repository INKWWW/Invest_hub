-- X window creation is independent from the V1.1 Discord functions.  The
-- continuous waterline remains shared only as a per-source table, never as a
-- cross-source cursor.

alter table public.sync_tasks
  drop constraint sync_tasks_capture_range_shape,
  add constraint sync_tasks_capture_range_shape check (
    capture_range is null
    or (
      jsonb_typeof(capture_range) = 'object'
      and (capture_range - 'mode' - 'trigger' - 'timezone' - 'start_at' - 'end_at' - 'scheduled_window_key' - 'overlap_start_at') = '{}'::jsonb
      and capture_range->>'mode' = 'window'
      and capture_range->>'trigger' in ('scheduled', 'manual', 'bootstrap')
      and capture_range->>'timezone' = 'Asia/Shanghai'
      and jsonb_typeof(capture_range->'start_at') = 'string'
      and jsonb_typeof(capture_range->'end_at') = 'string'
      and nullif(capture_range->>'start_at', '') is not null
      and nullif(capture_range->>'end_at', '') is not null
      and (capture_range->>'start_at')::timestamptz < (capture_range->>'end_at')::timestamptz
      and (
        not (capture_range ? 'overlap_start_at')
        or (
          jsonb_typeof(capture_range->'overlap_start_at') = 'string'
          and nullif(capture_range->>'overlap_start_at', '') is not null
          and (capture_range->>'overlap_start_at')::timestamptz <= (capture_range->>'start_at')::timestamptz
        )
      )
      and (
        (
          capture_range->>'trigger' = 'scheduled'
          and jsonb_typeof(capture_range->'scheduled_window_key') = 'string'
          and capture_range->>'scheduled_window_key' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T(00:00|08:00|12:00|16:00|20:00|20:50)[+]08:00$'
          and (capture_range->>'scheduled_window_key')::timestamptz = (capture_range->>'end_at')::timestamptz
        )
        or (
          capture_range->>'trigger' in ('manual', 'bootstrap')
          and jsonb_typeof(capture_range->'scheduled_window_key') = 'null'
        )
      )
    )
  );

create or replace function public.create_windowed_x_sync_task(
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
  v_profile public.x_source_profiles%rowtype;
  v_coverage public.source_collection_coverage%rowtype;
  v_existing public.sync_tasks%rowtype;
  v_task public.sync_tasks%rowtype;
  v_overlap_start timestamptz;
  v_day_start timestamptz;
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
       or p_scheduled_window_key !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T(00:00|08:00|12:00|16:00|20:00)[+]08:00$'
       or p_scheduled_window_key::timestamptz <> p_end_at then
      raise exception 'invalid_capture_range' using errcode = '22023';
    end if;
  elsif p_scheduled_window_key is not null then
    raise exception 'invalid_capture_range' using errcode = '22023';
  end if;

  select * into v_source from public.sources
  where id = p_source_id and source_type = 'x' for update;
  if not found then raise exception 'source_not_found' using errcode = '22023'; end if;
  if not v_source.enabled then raise exception 'source_disabled' using errcode = '22023'; end if;
  if p_parameter_version is null or p_parameter_version <> v_source.parameter_version then
    raise exception 'source_parameter_version_mismatch' using errcode = '22023';
  end if;

  select * into v_profile from public.x_source_profiles
  where source_id = p_source_id and enabled and resolution_status = 'resolved'
  for update;
  if not found then raise exception 'x_source_unresolved' using errcode = '22023'; end if;

  select * into v_coverage from public.source_collection_coverage
  where source_id = p_source_id for update;
  if not found then raise exception 'coverage_not_initialized' using errcode = '22023'; end if;
  if p_end_at <= v_coverage.coverage_through_at then
    raise exception 'invalid_capture_range' using errcode = '22023';
  end if;

  select * into v_existing from public.sync_tasks
  where source_id = p_source_id and task_type = 'x_sync'
    and status in ('queued', 'leased', 'running', 'retryable_failed')
  order by (capture_range->>'end_at')::timestamptz, queued_at, id
  for update limit 1;
  if found then return to_jsonb(v_existing) || jsonb_build_object('idempotent', true); end if;

  v_day_start := date_trunc('day', v_coverage.coverage_through_at at time zone 'Asia/Shanghai')
    at time zone 'Asia/Shanghai';
  v_overlap_start := greatest(v_coverage.coverage_through_at - interval '30 minutes', v_day_start);
  v_capture_range := jsonb_build_object(
    'mode', 'window', 'trigger', p_trigger, 'timezone', 'Asia/Shanghai',
    'start_at', v_coverage.coverage_through_at, 'end_at', p_end_at,
    'scheduled_window_key', case when p_trigger = 'scheduled' then to_jsonb(p_scheduled_window_key) else 'null'::jsonb end,
    'overlap_start_at', v_overlap_start
  );

  insert into public.sync_tasks (
    task_type, source_id, parameter_version, requested_by, rule_snapshot,
    collection_scope, capture_range, author_profile_snapshot, x_source_snapshot
  ) values (
    'x_sync', p_source_id, p_parameter_version, p_requested_by,
    '{"version":0,"target_author_ids":[]}'::jsonb, '{"mode":"window"}'::jsonb,
    v_capture_range, '[]'::jsonb,
    jsonb_build_object('source_type', 'x', 'account_id', v_profile.account_id,
      'display_name', v_profile.display_name, 'parameter_version', v_source.parameter_version)
  ) returning * into v_task;

  insert into public.sync_task_capture_progress (task_id, source_id, capture_range)
  values (v_task.id, p_source_id, v_capture_range);
  return to_jsonb(v_task) || jsonb_build_object('idempotent', false);
end;
$$;

revoke all on function public.create_windowed_x_sync_task(uuid, text, uuid, text, timestamptz, text)
  from public, anon, authenticated;
grant execute on function public.create_windowed_x_sync_task(uuid, text, uuid, text, timestamptz, text)
  to service_role;

-- Keep the proven V1.1 lease/claim procedure intact and add only the
-- X-only snapshot required by the shared task-claim contract.
alter function public.claim_next_task(uuid, timestamptz) rename to claim_next_task_base;

create function public.claim_next_task(p_worker_id uuid, p_now timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_claim jsonb;
  v_snapshot jsonb;
begin
  v_claim := public.claim_next_task_base(p_worker_id, p_now);
  if v_claim is null then
    return null;
  end if;
  if v_claim->>'task_type' <> 'x_sync' then
    return v_claim;
  end if;
  select x_source_snapshot into v_snapshot
  from public.sync_tasks
  where id = (v_claim->>'task_id')::uuid;
  if v_snapshot is null then
    raise exception 'x_task_snapshot_missing' using errcode = '22023';
  end if;
  return v_claim || jsonb_build_object('source_snapshot', v_snapshot);
end;
$$;

revoke all on function public.claim_next_task(uuid, timestamptz)
  from public, anon, authenticated;
grant execute on function public.claim_next_task(uuid, timestamptz) to service_role;

create function public.enqueue_due_x_tasks(p_worker_id uuid, p_now timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_source record;
  v_end_at timestamptz;
  v_window_key text;
  v_task jsonb;
  v_tasks jsonb := '[]'::jsonb;
begin
  if p_now is null or not exists (
    select 1 from public.workers where id = p_worker_id and status in ('enrolled', 'online')
  ) then
    raise exception 'worker_not_authorized' using errcode = '42501';
  end if;
  for v_source in
    select source.id, source.parameter_version, coverage.coverage_through_at
    from public.sources source
    join public.x_source_profiles profile on profile.source_id = source.id
      and profile.enabled and profile.resolution_status = 'resolved'
    join public.source_collection_coverage coverage on coverage.source_id = source.id
    where source.source_type = 'x' and source.enabled
      and (source.authorized_worker_id is null or source.authorized_worker_id = p_worker_id)
  loop
    select min((day_at + cutoff) at time zone 'Asia/Shanghai')
      into v_end_at
    from generate_series(
      date_trunc('day', v_source.coverage_through_at at time zone 'Asia/Shanghai'),
      date_trunc('day', p_now at time zone 'Asia/Shanghai'),
      interval '1 day'
    ) as day_at
    cross join (values (time '00:00'), (time '08:00'), (time '12:00'), (time '16:00'), (time '20:00')) as cutoffs(cutoff)
    where (day_at + cutoff) at time zone 'Asia/Shanghai' > v_source.coverage_through_at
      and (day_at + cutoff) at time zone 'Asia/Shanghai' <= p_now;
    if v_end_at is null then continue; end if;
    v_window_key := to_char(v_end_at at time zone 'Asia/Shanghai', 'YYYY-MM-DD"T"HH24:MI') || '+08:00';
    v_task := public.create_windowed_x_sync_task(
      v_source.id, v_source.parameter_version, null, 'scheduled', v_end_at, v_window_key
    );
    v_tasks := v_tasks || jsonb_build_array(jsonb_build_object(
      'id', v_task->>'id', 'source_id', v_task->>'source_id', 'idempotent', coalesce((v_task->>'idempotent')::boolean, false)
    ));
  end loop;
  return jsonb_build_object('scheduled_at', p_now, 'tasks', v_tasks, 'deferred_source_ids', '[]'::jsonb);
end;
$$;

revoke all on function public.enqueue_due_x_tasks(uuid, timestamptz)
  from public, anon, authenticated;
grant execute on function public.enqueue_due_x_tasks(uuid, timestamptz) to service_role;

alter function public.persist_windowed_capture_page(uuid, integer, uuid, jsonb)
  rename to persist_windowed_capture_page_base;

create function public.persist_windowed_capture_page(
  p_task_id uuid, p_attempt integer, p_worker_id uuid, p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_source_id uuid;
  v_source_type text;
  v_context record;
  v_ack jsonb;
  v_canonical_id uuid;
begin
  select source.id, source.source_type into v_source_id, v_source_type
  from public.sync_tasks task join public.sources source on source.id = task.source_id
  where task.id = p_task_id;
  if not found then raise exception 'lease_mismatch' using errcode = '40001'; end if;
  if v_source_type <> 'x' then
    return public.persist_windowed_capture_page_base(p_task_id, p_attempt, p_worker_id, p_payload);
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object'
     or (p_payload - 'contract_version' - 'task_id' - 'attempt' - 'source_id' - 'raw_messages' - 'canonical_messages' - 'structured_runs' - 'capture_segment' - 'x_post_contexts') <> '{}'::jsonb
     or jsonb_typeof(coalesce(p_payload->'x_post_contexts', '[]'::jsonb)) <> 'array' then
    raise exception 'invalid_x_windowed_page_persistence' using errcode = '22023';
  end if;
  v_ack := public.persist_windowed_capture_page_base(p_task_id, p_attempt, p_worker_id, p_payload - 'x_post_contexts');
  for v_context in
    select * from jsonb_to_recordset(coalesce(p_payload->'x_post_contexts', '[]'::jsonb)) as context(
      external_message_id text, post_type text, post_url text, quoted_post_id text,
      reply_to_post_id text, reposted_post_id text, context_status text, attachments jsonb
    )
  loop
    select id into v_canonical_id from public.canonical_messages
    where source_id = v_source_id and external_message_id = v_context.external_message_id;
    if v_canonical_id is null then raise exception 'x_context_without_canonical_post' using errcode = '22023'; end if;
    if exists (
      select 1 from public.x_post_contexts existing
      where existing.canonical_message_id = v_canonical_id
        and (existing.post_type, existing.post_url, existing.quoted_post_id, existing.reply_to_post_id,
          existing.reposted_post_id, existing.context_status, existing.attachments)
          is distinct from
          (v_context.post_type, v_context.post_url, v_context.quoted_post_id, v_context.reply_to_post_id,
            v_context.reposted_post_id, v_context.context_status, v_context.attachments)
    ) then
      raise exception 'conflicting_x_post_context' using errcode = '23505';
    end if;
    insert into public.x_post_contexts (
      canonical_message_id, post_type, post_url, quoted_post_id, reply_to_post_id,
      reposted_post_id, context_status, attachments
    ) values (
      v_canonical_id, v_context.post_type, v_context.post_url, v_context.quoted_post_id,
      v_context.reply_to_post_id, v_context.reposted_post_id, v_context.context_status,
      coalesce(v_context.attachments, '[]'::jsonb)
    ) on conflict (canonical_message_id) do nothing;
  end loop;
  return v_ack;
end;
$$;

revoke all on function public.persist_windowed_capture_page(uuid, integer, uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.persist_windowed_capture_page(uuid, integer, uuid, jsonb) to service_role;
