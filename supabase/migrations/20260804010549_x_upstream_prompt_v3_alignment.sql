alter table public.x_post_analyses
  add column schema_version text not null default 'v2-x-chunk',
  add column prompt_version text not null default 'v2-x-chunk-legacy',
  add column analysis_output jsonb;

alter table public.x_post_analyses
  add constraint x_post_analyses_versioned_output check (
    (schema_version = 'v2-x-chunk' and analysis_output is null)
    or (schema_version = 'v3-x-post-analysis' and prompt_version = 'v3-x-post-analysis-1' and jsonb_typeof(analysis_output) = 'object')
  );

alter table public.x_daily_viewpoint_segments
  add column schema_version text not null default 'v2-x-window',
  add column prompt_version text not null default 'v2-x-window-legacy',
  add column segment_output jsonb;

alter table public.x_daily_viewpoint_segments
  add constraint x_daily_viewpoint_segments_versioned_output check (
    (schema_version = 'v2-x-window' and segment_output is null)
    or (schema_version = 'v3-x-window' and prompt_version = 'v3-x-window-1' and jsonb_typeof(segment_output) = 'object')
  );

create or replace function public.complete_windowed_capture_range_v3_x_core(
  p_task_id uuid,
  p_attempt integer,
  p_worker_id uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
set lock_timeout = '5s'
as $$
declare
  v_body jsonb := p_payload - 'contract_version' - 'task_id' - 'attempt';
  v_task public.sync_tasks%rowtype;
  v_attempt public.task_attempts%rowtype;
  v_progress public.sync_task_capture_progress%rowtype;
  v_coverage public.source_collection_coverage%rowtype;
  v_boundary_at timestamptz;
  v_analysis jsonb;
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
  if not found then raise exception 'lease_mismatch' using errcode = '40001'; end if;
  if v_task.task_type <> 'x_sync' then raise exception 'invalid_x_range_completion' using errcode = '22023'; end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object'
     or (v_body - 'range_complete' - 'capture_range' - 'boundary' - 'summary_batch_ids' - 'daily_summary_ids' - 'x_post_analyses' - 'x_daily_segments' - 'no_new_data') <> '{}'::jsonb
     or coalesce((v_body->>'range_complete')::boolean, false) is not true
     or v_body->'summary_batch_ids' <> '[]'::jsonb or v_body->'daily_summary_ids' <> '[]'::jsonb
     or jsonb_typeof(v_body->'capture_range') <> 'object' or jsonb_typeof(v_body->'boundary') <> 'object'
     or jsonb_typeof(v_body->'x_post_analyses') <> 'array' or jsonb_typeof(v_body->'x_daily_segments') <> 'array'
     or jsonb_typeof(v_body->'no_new_data') <> 'boolean'
     or v_body->'capture_range' <> v_task.capture_range then
    raise exception 'invalid_x_range_completion' using errcode = '22023';
  end if;
  begin v_boundary_at := nullif(v_body->'boundary'->>'observed_at', '')::timestamptz;
  exception when invalid_datetime_format or datetime_field_overflow then raise exception 'invalid_x_range_completion' using errcode = '22023'; end;
  if v_body->'boundary'->>'kind' not in ('oldest_at_or_before_start', 'history_exhausted') or v_boundary_at is null
     or (v_body->'boundary'->>'kind' = 'oldest_at_or_before_start' and v_boundary_at > (v_task.capture_range->>'overlap_start_at')::timestamptz) then
    raise exception 'invalid_x_range_completion' using errcode = '22023';
  end if;
  select * into v_attempt from public.task_attempts where task_id = p_task_id and attempt = p_attempt for update;
  select * into v_progress from public.sync_task_capture_progress where task_id = p_task_id for update;
  select * into v_coverage from public.source_collection_coverage where source_id = v_task.source_id for update;
  if not found or v_attempt.worker_id <> p_worker_id or v_attempt.status not in ('leased','running')
     or v_task.lease_owner <> p_worker_id or v_task.status not in ('leased','running')
     or v_progress.page_count < 1 or v_coverage.coverage_through_at <> (v_task.capture_range->>'start_at')::timestamptz then
    raise exception 'lease_mismatch' using errcode = '40001';
  end if;
  if exists (
    select 1 from public.sync_tasks predecessor where predecessor.source_id = v_task.source_id and predecessor.id <> v_task.id
      and predecessor.collection_scope->>'mode' = 'window'
      and (predecessor.capture_range->>'end_at')::timestamptz <= (v_task.capture_range->>'start_at')::timestamptz
      and predecessor.status <> 'succeeded'
      and (v_coverage.coverage_through_at is null or (predecessor.capture_range->>'end_at')::timestamptz > v_coverage.coverage_through_at)
  ) then raise exception 'predecessor_range_incomplete' using errcode = '40001'; end if;
  select coalesce(array_agg(external_message_id order by external_message_id), '{}') into v_expected_posts
  from public.canonical_messages where source_id = v_task.source_id
    and occurred_at > (v_task.capture_range->>'start_at')::timestamptz and occurred_at <= (v_task.capture_range->>'end_at')::timestamptz;
  select coalesce(array_agg(value->>'post_id' order by value->>'post_id'), '{}') into v_submitted_posts
  from jsonb_array_elements(v_body->'x_post_analyses') value;
  if v_submitted_posts is distinct from v_expected_posts or cardinality(v_submitted_posts) <> cardinality(array(select distinct unnest(v_submitted_posts)))
     or (v_body->>'no_new_data')::boolean <> (cardinality(v_expected_posts) = 0)
     or (cardinality(v_expected_posts) = 0 and jsonb_array_length(v_body->'x_daily_segments') <> 0)
     or (cardinality(v_expected_posts) > 0 and jsonb_array_length(v_body->'x_daily_segments') <> 1) then
    raise exception 'x_analysis_coverage_mismatch' using errcode = '22023';
  end if;
  if cardinality(v_expected_posts) > 0 then
    select min(occurred_at), max(occurred_at), (min(occurred_at) at time zone 'Asia/Shanghai')::date into v_post_from, v_post_through, v_natural_date
    from public.canonical_messages where source_id = v_task.source_id and external_message_id = any(v_expected_posts);
  end if;
  for v_analysis in select value from jsonb_array_elements(v_body->'x_post_analyses') loop
    if jsonb_typeof(v_analysis) <> 'object'
       or (v_analysis - 'post_id' - 'analysis_id' - 'analysis_version' - 'schema_version' - 'prompt_version' - 'analysis_output' - 'blogger_viewpoint' - 'arguments' - 'quoted_post_viewpoint' - 'uncertainties' - 'evidence_post_ids' - 'post_link') <> '{}'::jsonb
       or v_analysis->>'schema_version' <> 'v3-x-post-analysis' or v_analysis->>'prompt_version' <> 'v3-x-post-analysis-1'
       or v_analysis->>'analysis_id' <> v_analysis->>'post_id' || '@2' or (v_analysis->>'analysis_version')::integer <> 2
       or jsonb_typeof(v_analysis->'analysis_output') <> 'object' or v_analysis->'analysis_output'->>'post_id' <> v_analysis->>'post_id'
       or jsonb_typeof(v_analysis->'arguments') <> 'array' or jsonb_typeof(v_analysis->'uncertainties') <> 'array'
       or jsonb_typeof(v_analysis->'evidence_post_ids') <> 'array' or jsonb_array_length(v_analysis->'evidence_post_ids') < 1 then
      raise exception 'invalid_x_analysis' using errcode = '22023';
    end if;
    select message.id into v_canonical_id from public.canonical_messages message join public.x_post_contexts context on context.canonical_message_id = message.id
      where message.source_id = v_task.source_id and message.external_message_id = v_analysis->>'post_id' for update;
    select * into v_context from public.x_post_contexts where canonical_message_id = v_canonical_id;
    if v_canonical_id is null or v_context.post_url <> v_analysis->>'post_link'
       or exists (select 1 from jsonb_array_elements_text(v_analysis->'evidence_post_ids') value
          where value not in (v_analysis->>'post_id', coalesce(v_context.quoted_post_id,''), coalesce(v_context.reply_to_post_id,''), coalesce(v_context.reposted_post_id,''))) then
      raise exception 'invalid_x_analysis_evidence' using errcode = '22023';
    end if;
    if exists (select 1 from public.x_post_analyses existing where existing.canonical_message_id = v_canonical_id and existing.analysis_version = 2
      and (existing.analysis_output, existing.evidence_refs) is distinct from (v_analysis->'analysis_output', v_analysis->'evidence_post_ids')) then
      raise exception 'conflicting_x_post_analysis' using errcode = '23505';
    end if;
    insert into public.x_post_analyses (canonical_message_id, analysis_version, schema_version, prompt_version, analysis_output, blogger_viewpoint, arguments, quoted_post_viewpoint, uncertainties, evidence_refs)
    values (v_canonical_id, 2, 'v3-x-post-analysis', 'v3-x-post-analysis-1', v_analysis->'analysis_output', v_analysis->'blogger_viewpoint', v_analysis->'arguments', v_analysis->'quoted_post_viewpoint', v_analysis->'uncertainties', v_analysis->'evidence_post_ids')
    on conflict (canonical_message_id, analysis_version) do nothing;
    v_analysis_refs := v_analysis_refs || jsonb_build_array(jsonb_build_object('post_id', v_analysis->>'post_id', 'analysis_version', 2));
  end loop;
  update public.sync_task_capture_progress set boundary_verified_at=v_boundary_at, boundary_kind=v_body->'boundary'->>'kind', range_complete=true, last_error=null where task_id=p_task_id;
  update public.task_attempts set status='succeeded', result=jsonb_build_object('status','succeeded','range_complete',true,'capture_range',v_task.capture_range,'x_post_analysis_count',cardinality(v_expected_posts),'no_new_data',v_body->'no_new_data'), completed_at=timezone('utc',now()) where id=v_attempt.id;
  update public.sync_tasks set status='succeeded', lease_owner=null, lease_expires_at=null where id=v_task.id;
  update public.source_collection_coverage set coverage_through_at=(v_task.capture_range->>'end_at')::timestamptz, last_completed_task_id=v_task.id where source_id=v_task.source_id;
  if cardinality(v_expected_posts) > 0 then
    v_segment := (v_body->'x_daily_segments')->0;
    if jsonb_typeof(v_segment) <> 'object'
       or (v_segment - 'natural_date' - 'occurred_from_at' - 'occurred_through_at' - 'schema_version' - 'prompt_version' - 'segment_output' - 'window_viewpoints' - 'analysis_ids' - 'evidence_post_ids' - 'uncertainties') <> '{}'::jsonb
       or v_segment->>'schema_version' <> 'v3-x-window' or v_segment->>'prompt_version' <> 'v3-x-window-1'
       or jsonb_typeof(v_segment->'segment_output') <> 'object' or jsonb_typeof(v_segment->'window_viewpoints') <> 'array' or jsonb_array_length(v_segment->'window_viewpoints') <> 0
       or jsonb_typeof(v_segment->'analysis_ids') <> 'array' or jsonb_typeof(v_segment->'evidence_post_ids') <> 'array' or jsonb_typeof(v_segment->'uncertainties') <> 'array'
       or (select coalesce(array_agg(value order by value),'{}') from jsonb_array_elements_text(v_segment->'analysis_ids') value) is distinct from (select array_agg(post_id || '@2' order by post_id) from unnest(v_expected_posts) post_id)
       or (v_segment->>'natural_date')::date <> v_natural_date or (v_segment->>'occurred_from_at')::timestamptz <> v_post_from or (v_segment->>'occurred_through_at')::timestamptz <> v_post_through
       or v_segment->'segment_output'->>'schema_version' <> 'v3-x-window' then
      raise exception 'invalid_x_daily_segment' using errcode = '22023';
    end if;
    select coalesce(max(segment_version),0)+1 into v_segment_version from public.x_daily_viewpoint_segments where source_id=v_task.source_id and natural_date=(v_segment->>'natural_date')::date;
    insert into public.x_daily_viewpoint_segments (source_id,natural_date,range_task_id,segment_version,occurred_from_at,occurred_through_at,schema_version,prompt_version,segment_output,window_viewpoints,post_analysis_refs,evidence_refs)
    values (v_task.source_id,(v_segment->>'natural_date')::date,v_task.id,v_segment_version,(v_segment->>'occurred_from_at')::timestamptz,(v_segment->>'occurred_through_at')::timestamptz,'v3-x-window','v3-x-window-1',v_segment->'segment_output','[]'::jsonb,v_analysis_refs,v_segment->'evidence_post_ids') returning id into v_segment_id;
  end if;
  insert into public.task_events (task_id,attempt,event_type,occurred_at,details) values (p_task_id,p_attempt,'succeeded',timezone('utc',now()),jsonb_build_object('range_complete',true,'capture_range',v_task.capture_range,'boundary_kind',v_body->'boundary'->>'kind','boundary_verified_at',v_boundary_at,'x_daily_segment_id',v_segment_id));
  return jsonb_build_object('status','succeeded','idempotent',false,'task_id',p_task_id::text,'attempt',p_attempt,'coverage_through_at',v_task.capture_range->>'end_at','x_daily_segment_ids',case when v_segment_id is null then '[]'::jsonb else jsonb_build_array(v_segment_id::text) end);
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
begin
  if exists (
    select 1 from jsonb_array_elements(coalesce(p_payload->'x_post_analyses', '[]'::jsonb)) item
    where item->>'schema_version' = 'v3-x-post-analysis'
  ) then
    return public.complete_windowed_capture_range_v3_x_core(p_task_id, p_attempt, p_worker_id, p_payload);
  end if;
  return public.complete_windowed_capture_range_v2_x_core(p_task_id, p_attempt, p_worker_id, p_payload);
exception when sqlstate '40001' then
  raise sqlstate 'PT409' using message = sqlerrm;
end;
$$;

-- The v3 daily judgement must receive the persisted v3 objects themselves,
-- never the compatibility projection stored in the legacy columns.  Calling
-- the previous wrapper first preserves its lease and provider-input checks.
create or replace function public.get_x_daily_judgement_context(
  p_run_id uuid, p_attempt integer, p_worker_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_checked_context jsonb;
  v_run public.x_daily_judgement_runs%rowtype;
  v_batch public.x_collection_batches%rowtype;
  v_context jsonb;
begin
  v_checked_context := public.get_x_daily_judgement_context_v2(p_run_id, p_attempt, p_worker_id);
  select * into strict v_run from public.x_daily_judgement_runs where id = p_run_id;
  select * into strict v_batch from public.x_collection_batches where id = v_run.batch_id;

  if exists (
    select 1
    from public.x_collection_batch_sources batch_source
    join public.x_daily_viewpoint_segments segment
      on segment.source_id = batch_source.source_id
     and segment.range_task_id = batch_source.x_sync_task_id
     and segment.natural_date = v_batch.natural_date
    where batch_source.batch_id = v_run.batch_id
      and batch_source.settlement_status = 'included'
      and (segment.schema_version <> 'v3-x-window' or segment.prompt_version <> 'v3-x-window-1'
           or jsonb_typeof(segment.segment_output) <> 'object')
  ) then
    -- Historical and already leased v2 batches retain their original context
    -- and completion contract.  The current v3 Worker rejects this shape
    -- before Provider invocation; new v3 batches take the branch below.
    return v_checked_context;
  end if;

  if exists (
    select 1
    from public.x_collection_batch_sources batch_source
    join public.x_daily_viewpoint_segments segment
      on segment.source_id = batch_source.source_id
     and segment.range_task_id = batch_source.x_sync_task_id
     and segment.natural_date = v_batch.natural_date
    cross join lateral jsonb_to_recordset(segment.post_analysis_refs) as ref(post_id text, analysis_version integer)
    join public.canonical_messages message
      on message.source_id = batch_source.source_id and message.external_message_id = ref.post_id
    join public.x_post_analyses analysis
      on analysis.canonical_message_id = message.id and analysis.analysis_version = ref.analysis_version
    where batch_source.batch_id = v_run.batch_id
      and batch_source.settlement_status = 'included'
      and (ref.analysis_version <> 2 or analysis.schema_version <> 'v3-x-post-analysis'
           or analysis.prompt_version <> 'v3-x-post-analysis-1' or jsonb_typeof(analysis.analysis_output) <> 'object')
  ) then
    raise exception 'x_daily_judgement_requires_v3_upstream' using errcode = '22023';
  end if;

  select jsonb_build_object(
    'run_id', v_run.id::text,
    'batch_id', v_run.batch_id::text,
    'attempt', v_run.attempt,
    'prompt_version', 'v3-x-cross-blogger-1',
    'sources', coalesce(jsonb_agg(jsonb_build_object(
      'source_id', batch_source.source_id::text,
      'display_name', batch_source.source_display_name,
      'window_segments', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', segment.id::text,
          'schema_version', segment.schema_version,
          'prompt_version', segment.prompt_version,
          'occurred_from_at', segment.occurred_from_at,
          'occurred_through_at', segment.occurred_through_at,
          'segment_output', segment.segment_output,
          'analyses', coalesce((
            select jsonb_agg(jsonb_build_object(
              'analysis_id', message.external_message_id || '@' || analysis.analysis_version::text,
              'schema_version', analysis.schema_version,
              'prompt_version', analysis.prompt_version,
              'analysis_output', analysis.analysis_output,
              'evidence_post_ids', analysis.evidence_refs
            ) order by message.external_message_id)
            from jsonb_to_recordset(segment.post_analysis_refs) as ref(post_id text, analysis_version integer)
            join public.canonical_messages message
              on message.source_id = batch_source.source_id and message.external_message_id = ref.post_id
            join public.x_post_analyses analysis
              on analysis.canonical_message_id = message.id and analysis.analysis_version = ref.analysis_version
          ), '[]'::jsonb)
        ) order by segment.id)
        from public.x_daily_viewpoint_segments segment
        where segment.source_id = batch_source.source_id
          and segment.range_task_id = batch_source.x_sync_task_id
          and segment.natural_date = v_batch.natural_date
      ), '[]'::jsonb)
    ) order by batch_source.source_id), '[]'::jsonb),
    'excluded_sources', coalesce((
      select jsonb_agg(jsonb_build_object(
        'source_id', excluded.source_id::text,
        'display_name', excluded.source_display_name,
        'reason', coalesce(excluded.exclusion_code, excluded.settlement_status)
      ) order by excluded.source_id)
      from public.x_collection_batch_sources excluded
      where excluded.batch_id = v_run.batch_id
        and excluded.settlement_status in ('excluded', 'no_new_information')
    ), '[]'::jsonb)
  ) into v_context
  from public.x_collection_batch_sources batch_source
  where batch_source.batch_id = v_run.batch_id
    and batch_source.settlement_status = 'included';
  return v_context;
end;
$$;

-- A v3 judgement cannot be completed from a frozen v2 batch.  The existing
-- validator still supplies the shared source/evidence and opaque-ID checks.
create or replace function public.validate_x_daily_judgement_output_authority_v3(p_batch_id uuid, p_output jsonb)
returns void
language plpgsql
set search_path = public
as $$
declare
  v_legacy_output jsonb;
begin
  if exists (
    select 1
    from public.x_collection_batch_sources batch_source
    join public.x_collection_batches batch on batch.id = batch_source.batch_id
    join public.x_daily_viewpoint_segments segment
      on segment.source_id = batch_source.source_id
     and segment.range_task_id = batch_source.x_sync_task_id
     and segment.natural_date = batch.natural_date
    cross join lateral jsonb_to_recordset(segment.post_analysis_refs) as ref(post_id text, analysis_version integer)
    join public.canonical_messages message
      on message.source_id = batch_source.source_id and message.external_message_id = ref.post_id
    join public.x_post_analyses analysis
      on analysis.canonical_message_id = message.id and analysis.analysis_version = ref.analysis_version
    where batch_source.batch_id = p_batch_id
      and batch_source.settlement_status = 'included'
      and (segment.schema_version <> 'v3-x-window' or segment.prompt_version <> 'v3-x-window-1'
           or jsonb_typeof(segment.segment_output) <> 'object'
           or ref.analysis_version <> 2 or analysis.schema_version <> 'v3-x-post-analysis'
           or analysis.prompt_version <> 'v3-x-post-analysis-1' or jsonb_typeof(analysis.analysis_output) <> 'object')
  ) then
    raise exception 'x_daily_judgement_requires_v3_upstream' using errcode = '22023';
  end if;
  perform public.validate_x_daily_judgement_output_v3(p_output);
  select jsonb_build_object(
    'stock_viewpoints', coalesce(jsonb_agg(
      item - 'action_intent' - 'action_scope' - 'conditions'
      || jsonb_build_object('uncertainties',
        coalesce(item->'uncertainties', '[]'::jsonb)
        || case when item->>'action_scope' = '' then '[]'::jsonb else jsonb_build_array(item->>'action_scope') end
        || coalesce(item->'conditions', '[]'::jsonb)
      )
    ), '[]'::jsonb),
    'market_industry_viewpoints', '[]'::jsonb,
    'uncertainties', p_output->'uncertainties'
  ) into v_legacy_output
  from jsonb_array_elements(
    p_output->'security_industry_viewpoints'
    || p_output->'market_structure_viewpoints'
    || p_output->'strategy_mindset_viewpoints'
  ) item;
  perform public.validate_x_daily_judgement_output_authority(p_batch_id, v_legacy_output);
end;
$$;
