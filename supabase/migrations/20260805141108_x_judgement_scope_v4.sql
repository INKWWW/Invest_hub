-- Keep v2/v3 records readable and permit the normal v4 rows.
alter table public.x_post_analyses drop constraint if exists x_post_analyses_versioned_output;
alter table public.x_post_analyses add constraint x_post_analyses_versioned_output check (
  (schema_version = 'v2-x-chunk' and analysis_output is null)
  or (schema_version = 'v3-x-post-analysis' and prompt_version = 'v3-x-post-analysis-1' and jsonb_typeof(analysis_output) = 'object')
  or (schema_version = 'v4-x-post-analysis' and prompt_version = 'v4-x-post-analysis-1' and jsonb_typeof(analysis_output) = 'object')
);
alter table public.x_daily_viewpoint_segments drop constraint if exists x_daily_viewpoint_segments_versioned_output;
alter table public.x_daily_viewpoint_segments add constraint x_daily_viewpoint_segments_versioned_output check (
  (schema_version = 'v2-x-window' and segment_output is null)
  or (schema_version = 'v3-x-window' and prompt_version = 'v3-x-window-1' and jsonb_typeof(segment_output) = 'object')
  or (schema_version = 'v4-x-window' and prompt_version = 'v4-x-window-1' and jsonb_typeof(segment_output) = 'object')
);

create or replace function public.complete_windowed_capture_range_v4_x_core(
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
       or v_analysis->>'schema_version' <> 'v4-x-post-analysis' or v_analysis->>'prompt_version' <> 'v4-x-post-analysis-1'
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
    values (v_canonical_id, 2, 'v4-x-post-analysis', 'v4-x-post-analysis-1', v_analysis->'analysis_output', v_analysis->'blogger_viewpoint', v_analysis->'arguments', v_analysis->'quoted_post_viewpoint', v_analysis->'uncertainties', v_analysis->'evidence_post_ids')
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
       or v_segment->>'schema_version' <> 'v4-x-window' or v_segment->>'prompt_version' <> 'v4-x-window-1'
       or jsonb_typeof(v_segment->'segment_output') <> 'object' or jsonb_typeof(v_segment->'window_viewpoints') <> 'array' or jsonb_array_length(v_segment->'window_viewpoints') <> 0
       or jsonb_typeof(v_segment->'analysis_ids') <> 'array' or jsonb_typeof(v_segment->'evidence_post_ids') <> 'array' or jsonb_typeof(v_segment->'uncertainties') <> 'array'
       or (select coalesce(array_agg(value order by value),'{}') from jsonb_array_elements_text(v_segment->'analysis_ids') value) is distinct from (select array_agg(post_id || '@2' order by post_id) from unnest(v_expected_posts) post_id)
       or (v_segment->>'natural_date')::date <> v_natural_date or (v_segment->>'occurred_from_at')::timestamptz <> v_post_from or (v_segment->>'occurred_through_at')::timestamptz <> v_post_through
       or v_segment->'segment_output'->>'schema_version' <> 'v4-x-window' then
      raise exception 'invalid_x_daily_segment' using errcode = '22023';
    end if;
    select coalesce(max(segment_version),0)+1 into v_segment_version from public.x_daily_viewpoint_segments where source_id=v_task.source_id and natural_date=(v_segment->>'natural_date')::date;
    insert into public.x_daily_viewpoint_segments (source_id,natural_date,range_task_id,segment_version,occurred_from_at,occurred_through_at,schema_version,prompt_version,segment_output,window_viewpoints,post_analysis_refs,evidence_refs)
    values (v_task.source_id,(v_segment->>'natural_date')::date,v_task.id,v_segment_version,(v_segment->>'occurred_from_at')::timestamptz,(v_segment->>'occurred_through_at')::timestamptz,'v4-x-window','v4-x-window-1',v_segment->'segment_output','[]'::jsonb,v_analysis_refs,v_segment->'evidence_post_ids') returning id into v_segment_id;
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
    where item->>'schema_version' = 'v4-x-post-analysis'
  ) then
    return public.complete_windowed_capture_range_v4_x_core(p_task_id, p_attempt, p_worker_id, p_payload);
  end if;
  if exists (select 1 from jsonb_array_elements(coalesce(p_payload->'x_post_analyses', '[]'::jsonb)) item where item->>'schema_version' = 'v3-x-post-analysis') then
    return public.complete_windowed_capture_range_v3_x_core(p_task_id, p_attempt, p_worker_id, p_payload);
  end if;
  return public.complete_windowed_capture_range_v2_x_core(p_task_id, p_attempt, p_worker_id, p_payload);
exception when sqlstate '40001' then
  raise sqlstate 'PT409' using message = sqlerrm;
end;
$$;

-- The v4 daily judgement must receive the persisted v4 objects themselves,
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
      and (segment.schema_version <> 'v4-x-window' or segment.prompt_version <> 'v4-x-window-1'
           or jsonb_typeof(segment.segment_output) <> 'object')
  ) then
    -- Historical and already leased v2 batches retain their original context
    -- and completion contract.  The current v4 Worker rejects this shape
    -- before Provider invocation; new v4 batches take the branch below.
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
      and (ref.analysis_version <> 2 or analysis.schema_version <> 'v4-x-post-analysis'
           or analysis.prompt_version <> 'v4-x-post-analysis-1' or jsonb_typeof(analysis.analysis_output) <> 'object')
  ) then
    raise exception 'x_daily_judgement_requires_v4_upstream' using errcode = '22023';
  end if;

  select jsonb_build_object(
    'run_id', v_run.id::text,
    'batch_id', v_run.batch_id::text,
    'attempt', v_run.attempt,
    'prompt_version', 'v4-x-cross-blogger-1',
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

-- A v4 judgement cannot be completed from a frozen v2 batch.  The existing
-- validator still supplies the shared source/evidence and opaque-ID checks.
create or replace function public.validate_x_daily_judgement_output_authority_v4(p_batch_id uuid, p_output jsonb)
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
      and (segment.schema_version <> 'v4-x-window' or segment.prompt_version <> 'v4-x-window-1'
           or jsonb_typeof(segment.segment_output) <> 'object'
           or ref.analysis_version <> 2 or analysis.schema_version <> 'v4-x-post-analysis'
           or analysis.prompt_version <> 'v4-x-post-analysis-1' or jsonb_typeof(analysis.analysis_output) <> 'object')
  ) then
    raise exception 'x_daily_judgement_requires_v4_upstream' using errcode = '22023';
  end if;
  perform public.validate_x_daily_judgement_output_v4(p_output);
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
-- Preserve v2 records while making every new provider completion use the v4
-- investment-judgement contract.

create or replace function public.validate_x_daily_judgement_output_v4(p_output jsonb)
returns void
language plpgsql
set search_path = public
as $$
declare
  v_item jsonb;
begin
  if jsonb_typeof(p_output) <> 'object'
     or not (p_output ?& array['security_industry_viewpoints', 'market_structure_viewpoints', 'strategy_mindset_viewpoints', 'uncertainties'])
     or (p_output - 'security_industry_viewpoints' - 'market_structure_viewpoints' - 'strategy_mindset_viewpoints' - 'uncertainties') <> '{}'::jsonb
     or jsonb_typeof(p_output->'security_industry_viewpoints') <> 'array'
     or jsonb_typeof(p_output->'market_structure_viewpoints') <> 'array'
     or jsonb_typeof(p_output->'strategy_mindset_viewpoints') <> 'array'
     or jsonb_typeof(p_output->'uncertainties') <> 'array'
     or exists (
       select 1 from jsonb_array_elements(p_output->'uncertainties') value
       where jsonb_typeof(value) <> 'string' or not public.x_daily_judgement_safe_text(value #>> '{}', 500)
     ) then
    raise exception 'invalid_v4_x_daily_judgement_output' using errcode = '22023';
  end if;

  for v_item in
    select value from jsonb_array_elements(p_output->'security_industry_viewpoints')
    union all select value from jsonb_array_elements(p_output->'market_structure_viewpoints')
    union all select value from jsonb_array_elements(p_output->'strategy_mindset_viewpoints')
  loop
    if jsonb_typeof(v_item) <> 'object'
       or not (v_item ?& array['statement', 'action_intent', 'action_scope_status', 'action_scope', 'conditions', 'supporting_source_ids', 'dissenting_source_ids', 'analysis_ids', 'evidence_post_ids', 'uncertainties'])
       or (v_item - 'statement' - 'action_intent' - 'action_scope_status' - 'action_scope' - 'conditions' - 'supporting_source_ids' - 'dissenting_source_ids' - 'analysis_ids' - 'evidence_post_ids' - 'uncertainties') <> '{}'::jsonb
       or jsonb_typeof(v_item->'statement') <> 'string' or not public.x_daily_judgement_safe_text(v_item->>'statement', 1000)
       or jsonb_typeof(v_item->'action_intent') <> 'string' or v_item->>'action_intent' not in ('build_position', 'buy', 'add', 'hold', 'reduce', 'sell', 'watch', 'avoid', 'none')
       or jsonb_typeof(v_item->'action_scope_status') <> 'string'
       or v_item->>'action_scope_status' not in ('specified', 'unspecified', 'not_applicable')
       or jsonb_typeof(v_item->'action_scope') <> 'string'
       or (v_item->>'action_intent' = 'none' and (v_item->>'action_scope_status' <> 'not_applicable' or v_item->>'action_scope' <> ''))
       or (v_item->>'action_intent' <> 'none' and v_item->>'action_scope_status' = 'specified' and (not public.x_daily_judgement_safe_text(v_item->>'action_scope', 300) or v_item->>'action_scope' ~ '(未|不|无法)(明确|说明|提供|确认).{0,24}(标的|对象|资产|范围)|(标的|对象|资产|范围).{0,24}(未|不|无法)(明确|说明|提供|确认|知)'))
       or (v_item->>'action_intent' <> 'none' and v_item->>'action_scope_status' = 'unspecified' and v_item->>'action_scope' <> '')
       or (v_item->>'action_intent' <> 'none' and v_item->>'action_scope_status' = 'not_applicable')
       or jsonb_typeof(v_item->'conditions') <> 'array'
       or exists (select 1 from jsonb_array_elements(v_item->'conditions') value where jsonb_typeof(value) <> 'string' or not public.x_daily_judgement_safe_text(value #>> '{}', 500))
       or jsonb_typeof(v_item->'supporting_source_ids') <> 'array'
       or jsonb_typeof(v_item->'dissenting_source_ids') <> 'array'
       or jsonb_typeof(v_item->'analysis_ids') <> 'array'
       or jsonb_typeof(v_item->'evidence_post_ids') <> 'array'
       or jsonb_typeof(v_item->'uncertainties') <> 'array'
       or jsonb_array_length(v_item->'analysis_ids') = 0
       or jsonb_array_length(v_item->'evidence_post_ids') = 0
       or exists (select 1 from jsonb_array_elements(v_item->'supporting_source_ids') value where jsonb_typeof(value) <> 'string' or not public.x_daily_judgement_safe_text(value #>> '{}', 160))
       or exists (select 1 from jsonb_array_elements(v_item->'dissenting_source_ids') value where jsonb_typeof(value) <> 'string' or not public.x_daily_judgement_safe_text(value #>> '{}', 160))
       or exists (select 1 from jsonb_array_elements(v_item->'analysis_ids') value where jsonb_typeof(value) <> 'string' or not public.x_daily_judgement_safe_text(value #>> '{}', 160))
       or exists (select 1 from jsonb_array_elements(v_item->'evidence_post_ids') value where jsonb_typeof(value) <> 'string' or not public.x_daily_judgement_safe_text(value #>> '{}', 160))
       or exists (select 1 from jsonb_array_elements(v_item->'uncertainties') value where jsonb_typeof(value) <> 'string' or not public.x_daily_judgement_safe_text(value #>> '{}', 500))
       or v_item->>'statement' ~ '(?:系统\\s*)?(?:建议|应当|应该|必须|请|立即).{0,24}(?:买入|卖出|加仓|减仓|建仓|清仓|抄底|追涨)'
    then
      raise exception 'invalid_v4_x_daily_judgement_output' using errcode = '22023';
    end if;
  end loop;
end;
$$;
create or replace function public.enforce_x_daily_judgement_version()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_expected_revision integer;
  v_expected_snapshot jsonb;
begin
  select coalesce(max(revision), 0) + 1 into v_expected_revision
  from public.x_daily_judgement_versions where batch_id = new.batch_id;
  if new.revision <> v_expected_revision then
    raise exception 'invalid_x_daily_judgement_revision' using errcode = '23514';
  end if;
  perform public.validate_x_daily_judgement_input_snapshot(new.input_snapshot);
  if new.coverage_status = 'complete' and jsonb_array_length(new.input_snapshot->'sources') = 0 then
    raise exception 'invalid_x_daily_judgement_evidence' using errcode = '22023';
  end if;
  if new.schema_version <> 'v4-x-cross-blogger' then
    perform public.validate_x_daily_judgement_output(new.output);
  end if;
  v_expected_snapshot := public.build_x_daily_judgement_input_snapshot(new.batch_id);
  if new.input_snapshot <> v_expected_snapshot then
    raise exception 'invalid_x_daily_judgement_snapshot' using errcode = '22023';
  end if;
  if new.schema_version = 'v4-x-cross-blogger' then
    perform public.validate_x_daily_judgement_output_authority_v4(new.batch_id, new.output);
  else
    perform public.validate_x_daily_judgement_output_authority(new.batch_id, new.output);
  end if;
  return new;
end;
$$;
create or replace function public.complete_x_daily_judgement(
  p_run_id uuid, p_attempt integer, p_worker_id uuid, p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_run public.x_daily_judgement_runs%rowtype;
  v_batch public.x_collection_batches%rowtype;
  v_coverage_status text;
  v_snapshot jsonb;
  v_output jsonb;
begin
  select * into v_run from public.x_daily_judgement_runs where id = p_run_id for update;
  if not found or p_attempt is null or p_worker_id is null or v_run.attempt <> p_attempt
     or v_run.status not in ('leased', 'running') or v_run.lease_owner <> p_worker_id
     or v_run.lease_expires_at <= timezone('utc', now()) then
    raise exception 'lease_mismatch' using errcode = 'PT409';
  end if;
  select * into v_batch from public.x_collection_batches where id = v_run.batch_id for update;
  if not found or v_batch.snapshot_completeness <> 'complete' then
    raise exception 'x_collection_batch_snapshot_unavailable' using errcode = '55000';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object'
     or not (
       (p_payload->>'schema_version' = 'v4-x-cross-blogger' and p_payload->>'prompt_version' = 'v4-x-cross-blogger-1'
        and jsonb_typeof(p_payload->'security_industry_viewpoints') = 'array'
        and jsonb_typeof(p_payload->'market_structure_viewpoints') = 'array'
        and jsonb_typeof(p_payload->'strategy_mindset_viewpoints') = 'array')
       or (p_payload->>'schema_version' = 'v2-x-cross-blogger' and p_payload->>'prompt_version' = 'v2-x-cross-blogger-1'
        and jsonb_typeof(p_payload->'stock_viewpoints') = 'array'
        and jsonb_typeof(p_payload->'market_industry_viewpoints') = 'array')
     )
     or p_payload->>'provider' not in ('codex_cli', 'mock')
     or not (p_payload ? 'model_reported')
     or (p_payload->'model_reported' <> 'null'::jsonb and (
       jsonb_typeof(p_payload->'model_reported') <> 'string'
       or not public.x_daily_judgement_safe_text(p_payload->>'model_reported', 160)
     ))
     or jsonb_typeof(p_payload->'uncertainties') <> 'array' then
    raise exception 'invalid_x_daily_judgement_completion' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.x_collection_batch_sources
    where batch_id = v_run.batch_id and settlement_status = 'included'
  ) then
    raise exception 'x_daily_judgement_no_provider_input' using errcode = '22023';
  end if;
  select case when count(*) filter (where settlement_status = 'excluded') > 0 then 'partial' else 'complete' end
  into v_coverage_status
  from public.x_collection_batch_sources where batch_id = v_run.batch_id;
  v_snapshot := public.build_x_daily_judgement_input_snapshot(v_run.batch_id);
  v_output := p_payload - 'schema_version' - 'provider' - 'model_reported' - 'prompt_version';
  insert into public.x_daily_judgement_versions (
    batch_id, revision, coverage_status, input_snapshot, output, provider, model_reported, prompt_version, schema_version
  ) values (
    v_run.batch_id,
    (select coalesce(max(revision), 0) + 1 from public.x_daily_judgement_versions where batch_id = v_run.batch_id),
    v_coverage_status, v_snapshot, v_output, p_payload->>'provider', nullif(p_payload->>'model_reported', ''),
    p_payload->>'prompt_version', p_payload->>'schema_version'
  );
  update public.x_daily_judgement_runs set status = 'succeeded', lease_owner = null, lease_expires_at = null where id = v_run.id;
  update public.x_collection_batches set status = 'succeeded' where id = v_run.batch_id;
  return jsonb_build_object('run_id', v_run.id::text, 'attempt', v_run.attempt, 'status', 'succeeded');
end;
$$;

revoke all on function public.validate_x_daily_judgement_output_v4(jsonb), public.validate_x_daily_judgement_output_authority_v4(uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.validate_x_daily_judgement_output_v4(jsonb), public.validate_x_daily_judgement_output_authority_v4(uuid, jsonb)
  to service_role;
revoke all on function public.get_x_daily_judgement_context_v2(uuid, integer, uuid) from public, anon, authenticated, service_role;
revoke all on function public.get_x_daily_judgement_context(uuid, integer, uuid) from public, anon, authenticated;
grant execute on function public.get_x_daily_judgement_context(uuid, integer, uuid) to service_role;
