-- X ranges use page-level durable evidence, then atomically create immutable
-- post analyses / one appended daily segment and move the source waterline.
-- The existing V1.1 completion path remains the non-X implementation.

alter function public.complete_windowed_capture_range(uuid, integer, uuid, jsonb)
  rename to complete_windowed_capture_range_v1_1;

create function public.complete_windowed_capture_range(
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
  v_body jsonb := p_payload - 'contract_version' - 'task_id' - 'attempt';
  v_task public.sync_tasks%rowtype;
  v_attempt public.task_attempts%rowtype;
  v_progress public.sync_task_capture_progress%rowtype;
  v_coverage public.source_collection_coverage%rowtype;
  v_boundary_at timestamptz;
  v_analysis record;
  v_segment jsonb;
  v_canonical_id uuid;
  v_context public.x_post_contexts%rowtype;
  v_expected_posts text[];
  v_submitted_posts text[];
  v_analysis_refs jsonb := '[]'::jsonb;
  v_segment_version integer;
  v_segment_id uuid;
  v_post_from timestamptz;
  v_post_through timestamptz;
  v_natural_date date;
begin
  select * into v_task from public.sync_tasks where id = p_task_id for update;
  if not found then
    raise exception 'lease_mismatch' using errcode = '40001';
  end if;
  if v_task.task_type <> 'x_sync' then
    return public.complete_windowed_capture_range_v1_1(p_task_id, p_attempt, p_worker_id, v_body);
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object'
     or (v_body - 'range_complete' - 'capture_range' - 'boundary' - 'summary_batch_ids' - 'daily_summary_ids' - 'x_post_analyses' - 'x_daily_segments' - 'no_new_data') <> '{}'::jsonb
     or coalesce((v_body->>'range_complete')::boolean, false) is not true
     or v_body->'summary_batch_ids' <> '[]'::jsonb
     or v_body->'daily_summary_ids' <> '[]'::jsonb
     or jsonb_typeof(v_body->'capture_range') <> 'object'
     or jsonb_typeof(v_body->'boundary') <> 'object'
     or jsonb_typeof(v_body->'x_post_analyses') <> 'array'
     or jsonb_typeof(v_body->'x_daily_segments') <> 'array'
     or jsonb_typeof(v_body->'no_new_data') <> 'boolean' then
    raise exception 'invalid_x_range_completion' using errcode = '22023';
  end if;
  if v_body->'capture_range' <> v_task.capture_range then
    raise exception 'invalid_x_range_completion' using errcode = '22023';
  end if;
  begin
    v_boundary_at := nullif(v_body->'boundary'->>'observed_at', '')::timestamptz;
  exception when invalid_datetime_format or datetime_field_overflow then
    raise exception 'invalid_x_range_completion' using errcode = '22023';
  end;
  if v_body->'boundary'->>'kind' not in ('oldest_at_or_before_start', 'history_exhausted')
     or v_boundary_at is null
     or (v_body->'boundary'->>'kind' = 'oldest_at_or_before_start'
         and v_boundary_at > (v_task.capture_range->>'overlap_start_at')::timestamptz) then
    raise exception 'invalid_x_range_completion' using errcode = '22023';
  end if;

  select * into v_attempt from public.task_attempts where task_id = p_task_id and attempt = p_attempt for update;
  select * into v_progress from public.sync_task_capture_progress where task_id = p_task_id for update;
  select * into v_coverage from public.source_collection_coverage where source_id = v_task.source_id for update;
  if not found or v_attempt.worker_id <> p_worker_id or v_attempt.status not in ('leased', 'running')
     or v_task.lease_owner <> p_worker_id or v_task.status not in ('leased', 'running')
     or v_progress.page_count < 1
     or v_coverage.coverage_through_at <> (v_task.capture_range->>'start_at')::timestamptz then
    raise exception 'lease_mismatch' using errcode = '40001';
  end if;
  if exists (
    select 1 from public.sync_tasks predecessor
    where predecessor.source_id = v_task.source_id and predecessor.id <> v_task.id
      and predecessor.collection_scope->>'mode' = 'window'
      and (predecessor.capture_range->>'end_at')::timestamptz <= (v_task.capture_range->>'start_at')::timestamptz
      and predecessor.status <> 'succeeded'
  ) then
    raise exception 'predecessor_range_incomplete' using errcode = '40001';
  end if;

  select coalesce(array_agg(message.external_message_id order by message.external_message_id), '{}') into v_expected_posts
  from public.canonical_messages message
  where message.source_id = v_task.source_id
    and message.occurred_at > (v_task.capture_range->>'start_at')::timestamptz
    and message.occurred_at <= (v_task.capture_range->>'end_at')::timestamptz;
  select coalesce(array_agg(value->>'post_id' order by value->>'post_id'), '{}') into v_submitted_posts
  from jsonb_array_elements(v_body->'x_post_analyses') value;
  if v_submitted_posts is distinct from v_expected_posts
     or cardinality(v_submitted_posts) <> cardinality(array(select distinct unnest(v_submitted_posts)))
     or (v_body->>'no_new_data')::boolean <> (cardinality(v_expected_posts) = 0) then
    raise exception 'x_analysis_coverage_mismatch' using errcode = '22023';
  end if;
  if (cardinality(v_expected_posts) = 0 and jsonb_array_length(v_body->'x_daily_segments') <> 0)
     or (cardinality(v_expected_posts) > 0 and jsonb_array_length(v_body->'x_daily_segments') <> 1) then
    raise exception 'x_segment_coverage_mismatch' using errcode = '22023';
  end if;
  if cardinality(v_expected_posts) > 0 then
    select min(occurred_at), max(occurred_at), (min(occurred_at) at time zone 'Asia/Shanghai')::date
      into v_post_from, v_post_through, v_natural_date
    from public.canonical_messages
    where source_id = v_task.source_id and external_message_id = any(v_expected_posts);
  end if;

  for v_analysis in
    select * from jsonb_to_recordset(v_body->'x_post_analyses') as analysis(
      post_id text, analysis_id text, analysis_version integer, blogger_viewpoint text, arguments jsonb,
      quoted_post_viewpoint text, uncertainties jsonb, evidence_post_ids jsonb, post_link text
    )
  loop
    if v_analysis.analysis_version <> 1 or v_analysis.analysis_id <> v_analysis.post_id || '@1'
       or jsonb_typeof(v_analysis.arguments) <> 'array' or jsonb_typeof(v_analysis.uncertainties) <> 'array'
       or jsonb_typeof(v_analysis.evidence_post_ids) <> 'array'
       or jsonb_array_length(v_analysis.evidence_post_ids) < 1 then
      raise exception 'invalid_x_analysis' using errcode = '22023';
    end if;
    select message.id into v_canonical_id
    from public.canonical_messages message
    join public.x_post_contexts context on context.canonical_message_id = message.id
    where message.source_id = v_task.source_id and message.external_message_id = v_analysis.post_id
    for update;
    select * into v_context from public.x_post_contexts where canonical_message_id = v_canonical_id;
    if v_canonical_id is null or v_context.post_url <> v_analysis.post_link
       or exists (
         select 1 from jsonb_array_elements_text(v_analysis.evidence_post_ids) value
         where value not in (v_analysis.post_id, coalesce(v_context.quoted_post_id, ''), coalesce(v_context.reply_to_post_id, ''), coalesce(v_context.reposted_post_id, ''))
       ) then
      raise exception 'invalid_x_analysis_evidence' using errcode = '22023';
    end if;
    if exists (
      select 1 from public.x_post_analyses existing
      where existing.canonical_message_id = v_canonical_id and existing.analysis_version = 1
        and (existing.blogger_viewpoint, existing.arguments, existing.quoted_post_viewpoint, existing.uncertainties, existing.evidence_refs)
            is distinct from (v_analysis.blogger_viewpoint, v_analysis.arguments, v_analysis.quoted_post_viewpoint, v_analysis.uncertainties, v_analysis.evidence_post_ids)
    ) then
      raise exception 'conflicting_x_post_analysis' using errcode = '23505';
    end if;
    insert into public.x_post_analyses (canonical_message_id, analysis_version, blogger_viewpoint, arguments, quoted_post_viewpoint, uncertainties, evidence_refs)
    values (v_canonical_id, 1, v_analysis.blogger_viewpoint, v_analysis.arguments, v_analysis.quoted_post_viewpoint, v_analysis.uncertainties, v_analysis.evidence_post_ids)
    on conflict (canonical_message_id, analysis_version) do nothing;
    v_analysis_refs := v_analysis_refs || jsonb_build_array(jsonb_build_object('post_id', v_analysis.post_id, 'analysis_version', 1));
  end loop;

  update public.sync_task_capture_progress
  set boundary_verified_at = v_boundary_at, boundary_kind = v_body->'boundary'->>'kind', range_complete = true, last_error = null
  where task_id = p_task_id;
  update public.task_attempts
  set status = 'succeeded', result = jsonb_build_object('status', 'succeeded', 'range_complete', true, 'capture_range', v_task.capture_range, 'x_post_analysis_count', cardinality(v_expected_posts), 'no_new_data', v_body->'no_new_data'), completed_at = timezone('utc', now())
  where id = v_attempt.id;
  update public.sync_tasks set status = 'succeeded', lease_owner = null, lease_expires_at = null where id = v_task.id;
  update public.source_collection_coverage
  set coverage_through_at = (v_task.capture_range->>'end_at')::timestamptz, last_completed_task_id = v_task.id
  where source_id = v_task.source_id;

  if cardinality(v_expected_posts) > 0 then
    v_segment := (v_body->'x_daily_segments')->0;
    if (v_segment - 'natural_date' - 'occurred_from_at' - 'occurred_through_at' - 'window_viewpoints' - 'analysis_ids' - 'evidence_post_ids' - 'uncertainties') <> '{}'::jsonb
       or jsonb_typeof(v_segment->'window_viewpoints') <> 'array'
       or jsonb_typeof(v_segment->'analysis_ids') <> 'array'
       or jsonb_typeof(v_segment->'evidence_post_ids') <> 'array'
       or jsonb_typeof(v_segment->'uncertainties') <> 'array'
       or (select coalesce(array_agg(value order by value), '{}') from jsonb_array_elements_text(v_segment->'analysis_ids') value)
          is distinct from (select array_agg(post_id || '@1' order by post_id) from unnest(v_expected_posts) post_id)
       or (v_segment->>'natural_date')::date <> v_natural_date
       or (v_segment->>'occurred_from_at')::timestamptz <> v_post_from
       or (v_segment->>'occurred_through_at')::timestamptz <> v_post_through
       or exists (
         select 1 from jsonb_array_elements_text(v_segment->'evidence_post_ids') value
         where value not in (select unnest(v_expected_posts))
           and not exists (
             select 1 from public.x_post_contexts context
             join public.canonical_messages message on message.id = context.canonical_message_id
             where message.source_id = v_task.source_id
               and value in (coalesce(context.quoted_post_id, ''), coalesce(context.reply_to_post_id, ''), coalesce(context.reposted_post_id, ''))
           )
       ) then
      raise exception 'invalid_x_daily_segment' using errcode = '22023';
    end if;
    select coalesce(max(segment_version), 0) + 1 into v_segment_version
    from public.x_daily_viewpoint_segments where source_id = v_task.source_id and natural_date = (v_segment->>'natural_date')::date;
    insert into public.x_daily_viewpoint_segments (
      source_id, natural_date, range_task_id, segment_version, occurred_from_at, occurred_through_at,
      window_viewpoints, post_analysis_refs, evidence_refs
    ) values (
      v_task.source_id, (v_segment->>'natural_date')::date, v_task.id, v_segment_version,
      (v_segment->>'occurred_from_at')::timestamptz, (v_segment->>'occurred_through_at')::timestamptz,
      v_segment->'window_viewpoints', v_analysis_refs, v_segment->'evidence_post_ids'
    ) returning id into v_segment_id;
  end if;

  insert into public.task_events (task_id, attempt, event_type, occurred_at, details)
  values (p_task_id, p_attempt, 'succeeded', timezone('utc', now()), jsonb_build_object('range_complete', true, 'capture_range', v_task.capture_range, 'boundary_kind', v_body->'boundary'->>'kind', 'boundary_verified_at', v_boundary_at, 'x_daily_segment_id', v_segment_id));
  return jsonb_build_object('status', 'succeeded', 'idempotent', false, 'task_id', p_task_id::text, 'attempt', p_attempt, 'coverage_through_at', v_task.capture_range->>'end_at', 'x_daily_segment_ids', case when v_segment_id is null then '[]'::jsonb else jsonb_build_array(v_segment_id::text) end);
end;
$$;

revoke all on function public.complete_windowed_capture_range_v1_1(uuid, integer, uuid, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.complete_windowed_capture_range(uuid, integer, uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.complete_windowed_capture_range(uuid, integer, uuid, jsonb) to service_role;
