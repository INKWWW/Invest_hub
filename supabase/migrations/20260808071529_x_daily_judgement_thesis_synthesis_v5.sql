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
    'prompt_version', 'v5-x-cross-blogger-1',
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

create or replace function public.x_daily_judgement_jsonb_leaf_text(p_value jsonb)
returns text
language sql
immutable
security invoker
set search_path = public
as $$
  with recursive nodes(value) as (
    select p_value
    union all
    select child.value
    from nodes
    cross join lateral (
      select entry.value
      from jsonb_each(
        case when jsonb_typeof(nodes.value) = 'object' then nodes.value else '{}'::jsonb end
      ) entry
      union all
      select entry.value
      from jsonb_array_elements(
        case when jsonb_typeof(nodes.value) = 'array' then nodes.value else '[]'::jsonb end
      ) entry
    ) child
  )
  select coalesce(string_agg(value #>> '{}', ' '), '')
  from nodes
  where jsonb_typeof(value) = 'string';
$$;

create or replace function public.validate_x_daily_judgement_output_v5(p_output jsonb)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_rec record;
  v_child record;
  v_grandchild record;
  v_all_thesis_ids text[] := '{}'::text[];
  v_integration_ids text[] := '{}'::text[];
  v_assessment_ids text[] := '{}'::text[];
  v_text text;
begin
  if jsonb_typeof(p_output) <> 'object'
     or not (p_output ?& array['ai_synthesis', 'security_industry_theses', 'market_structure_theses', 'strategy_mindset_theses', 'uncertainties'])
     or (p_output - 'ai_synthesis' - 'security_industry_theses' - 'market_structure_theses' - 'strategy_mindset_theses' - 'uncertainties') <> '{}'::jsonb
     or jsonb_typeof(p_output->'ai_synthesis') <> 'object'
     or ((p_output->'ai_synthesis') - 'cross_blogger_integrations'::text - 'ai_assessments'::text) <> '{}'::jsonb
     or jsonb_typeof(p_output->'ai_synthesis'->'cross_blogger_integrations') <> 'array'
     or jsonb_typeof(p_output->'ai_synthesis'->'ai_assessments') <> 'array'
     or jsonb_typeof(p_output->'security_industry_theses') <> 'array'
     or jsonb_typeof(p_output->'market_structure_theses') <> 'array'
     or jsonb_typeof(p_output->'strategy_mindset_theses') <> 'array'
     or jsonb_typeof(p_output->'uncertainties') <> 'array'
     or exists (
       select 1
       from jsonb_array_elements_text(p_output->'uncertainties') value
       where not public.x_daily_judgement_safe_text(value, 500)
          or value ~* '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|[A-Za-z0-9_.-]{1,64}@[0-9]{1,3})'
          or value ~ '(?:系统\\s*)?(?:建议|应当|应该|必须|请|立即).{0,24}(?:买入|卖出|加仓|减仓|建仓|清仓|抄底|追涨)'
     ) then
    raise exception 'invalid_v5_x_daily_judgement_output' using errcode = '22023';
  end if;

  for v_rec in
    select 'security'::text as prefix, value, ordinality
    from jsonb_array_elements(p_output->'security_industry_theses') with ordinality
    union all
    select 'market'::text as prefix, value, ordinality
    from jsonb_array_elements(p_output->'market_structure_theses') with ordinality
    union all
    select 'strategy'::text as prefix, value, ordinality
    from jsonb_array_elements(p_output->'strategy_mindset_theses') with ordinality
  loop
    if jsonb_typeof(v_rec.value) <> 'object'
       or not (v_rec.value ?& array['thesis_id', 'headline', 'synthesis', 'scenario_branches', 'attributed_actions', 'supporting_source_ids', 'dissenting_source_ids', 'analysis_ids', 'evidence_post_ids', 'uncertainties'])
       or (v_rec.value - 'thesis_id' - 'headline' - 'synthesis' - 'scenario_branches' - 'attributed_actions' - 'supporting_source_ids' - 'dissenting_source_ids' - 'analysis_ids' - 'evidence_post_ids' - 'uncertainties') <> '{}'::jsonb
       or v_rec.value->>'thesis_id' <> format('%s-%s', v_rec.prefix, lpad(v_rec.ordinality::text, 2, '0'))
       or v_rec.value->>'thesis_id' = any(v_all_thesis_ids)
       or jsonb_typeof(v_rec.value->'headline') <> 'string' or not public.x_daily_judgement_safe_text(v_rec.value->>'headline', 300)
       or jsonb_typeof(v_rec.value->'synthesis') <> 'string' or not public.x_daily_judgement_safe_text(v_rec.value->>'synthesis', 2000)
       or jsonb_typeof(v_rec.value->'scenario_branches') <> 'array'
       or jsonb_typeof(v_rec.value->'attributed_actions') <> 'array'
       or jsonb_typeof(v_rec.value->'supporting_source_ids') <> 'array'
       or jsonb_typeof(v_rec.value->'dissenting_source_ids') <> 'array'
       or jsonb_typeof(v_rec.value->'analysis_ids') <> 'array'
       or jsonb_typeof(v_rec.value->'evidence_post_ids') <> 'array'
       or jsonb_typeof(v_rec.value->'uncertainties') <> 'array'
       or jsonb_array_length(v_rec.value->'supporting_source_ids') = 0
       or jsonb_array_length(v_rec.value->'analysis_ids') = 0
       or jsonb_array_length(v_rec.value->'evidence_post_ids') = 0
       or exists (select 1 from jsonb_array_elements_text(v_rec.value->'supporting_source_ids') value where not public.x_daily_judgement_safe_text(value, 160))
       or exists (select 1 from jsonb_array_elements_text(v_rec.value->'dissenting_source_ids') value where not public.x_daily_judgement_safe_text(value, 160))
       or exists (select 1 from jsonb_array_elements_text(v_rec.value->'analysis_ids') value where not public.x_daily_judgement_safe_text(value, 160))
       or exists (select 1 from jsonb_array_elements_text(v_rec.value->'evidence_post_ids') value where not public.x_daily_judgement_safe_text(value, 160))
       or exists (select 1 from jsonb_array_elements_text(v_rec.value->'uncertainties') value where not public.x_daily_judgement_safe_text(value, 500))
    then
      raise exception 'invalid_v5_x_daily_judgement_output' using errcode = '22023';
    end if;

    if (
      select count(*) <> count(distinct value)
      from jsonb_array_elements_text(v_rec.value->'supporting_source_ids') value
    ) or (
      select count(*) <> count(distinct value)
      from jsonb_array_elements_text(v_rec.value->'dissenting_source_ids') value
    ) or (
      select count(*) <> count(distinct value)
      from jsonb_array_elements_text(v_rec.value->'analysis_ids') value
    ) or (
      select count(*) <> count(distinct value)
      from jsonb_array_elements_text(v_rec.value->'evidence_post_ids') value
    ) or exists (
      select 1
      from jsonb_array_elements_text(v_rec.value->'supporting_source_ids') support(value)
      join jsonb_array_elements_text(v_rec.value->'dissenting_source_ids') dissent(value)
        on dissent.value = support.value
    ) then
      raise exception 'invalid_v5_x_daily_judgement_output' using errcode = '22023';
    end if;

    v_all_thesis_ids := array_append(v_all_thesis_ids, v_rec.value->>'thesis_id');

    for v_text in
      select v_rec.value->>'headline'
      union all select v_rec.value->>'synthesis'
      union all select value from jsonb_array_elements_text(v_rec.value->'uncertainties')
    loop
      if v_text ~* '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|[A-Za-z0-9_.-]{1,64}@[0-9]{1,3})'
         or v_text ~ '(?:系统\\s*)?(?:建议|应当|应该|必须|请|立即).{0,24}(?:买入|卖出|加仓|减仓|建仓|清仓|抄底|追涨)' then
        raise exception 'invalid_v5_x_daily_judgement_output' using errcode = '22023';
      end if;
    end loop;

    for v_child in
      select value, ordinality
      from jsonb_array_elements(v_rec.value->'scenario_branches') with ordinality
    loop
      if jsonb_typeof(v_child.value) <> 'object'
         or not (v_child.value ?& array['condition', 'outcome', 'source_ids', 'analysis_ids', 'evidence_post_ids', 'uncertainties'])
         or (v_child.value - 'condition' - 'outcome' - 'source_ids' - 'analysis_ids' - 'evidence_post_ids' - 'uncertainties') <> '{}'::jsonb
         or jsonb_typeof(v_child.value->'condition') <> 'string' or not public.x_daily_judgement_safe_text(v_child.value->>'condition', 500)
         or jsonb_typeof(v_child.value->'outcome') <> 'string' or not public.x_daily_judgement_safe_text(v_child.value->>'outcome', 1000)
         or jsonb_typeof(v_child.value->'source_ids') <> 'array'
         or jsonb_typeof(v_child.value->'analysis_ids') <> 'array'
         or jsonb_typeof(v_child.value->'evidence_post_ids') <> 'array'
         or jsonb_typeof(v_child.value->'uncertainties') <> 'array'
         or jsonb_array_length(v_child.value->'source_ids') = 0
         or jsonb_array_length(v_child.value->'analysis_ids') = 0
         or jsonb_array_length(v_child.value->'evidence_post_ids') = 0
         or exists (select 1 from jsonb_array_elements_text(v_child.value->'source_ids') value where not public.x_daily_judgement_safe_text(value, 160))
         or exists (select 1 from jsonb_array_elements_text(v_child.value->'analysis_ids') value where not public.x_daily_judgement_safe_text(value, 160))
         or exists (select 1 from jsonb_array_elements_text(v_child.value->'evidence_post_ids') value where not public.x_daily_judgement_safe_text(value, 160))
         or exists (select 1 from jsonb_array_elements_text(v_child.value->'uncertainties') value where not public.x_daily_judgement_safe_text(value, 500))
      then
        raise exception 'invalid_v5_x_daily_judgement_output' using errcode = '22023';
      end if;

      if (
        select count(*) <> count(distinct value)
        from jsonb_array_elements_text(v_child.value->'source_ids') value
      ) or (
        select count(*) <> count(distinct value)
        from jsonb_array_elements_text(v_child.value->'analysis_ids') value
      ) or (
        select count(*) <> count(distinct value)
        from jsonb_array_elements_text(v_child.value->'evidence_post_ids') value
      ) then
        raise exception 'invalid_v5_x_daily_judgement_output' using errcode = '22023';
      end if;

      for v_text in
        select v_child.value->>'condition'
        union all select v_child.value->>'outcome'
        union all select value from jsonb_array_elements_text(v_child.value->'uncertainties')
      loop
        if v_text ~* '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|[A-Za-z0-9_.-]{1,64}@[0-9]{1,3})'
           or v_text ~ '(?:系统\\s*)?(?:建议|应当|应该|必须|请|立即).{0,24}(?:买入|卖出|加仓|减仓|建仓|清仓|抄底|追涨)' then
          raise exception 'invalid_v5_x_daily_judgement_output' using errcode = '22023';
        end if;
      end loop;
    end loop;

    for v_child in
      select value, ordinality
      from jsonb_array_elements(v_rec.value->'attributed_actions') with ordinality
    loop
      if jsonb_typeof(v_child.value) <> 'object'
         or not (v_child.value ?& array['source_id', 'action_intent', 'action_scope_status', 'action_scope', 'conditions', 'analysis_ids', 'evidence_post_ids', 'uncertainties'])
         or (v_child.value - 'source_id' - 'action_intent' - 'action_scope_status' - 'action_scope' - 'conditions' - 'analysis_ids' - 'evidence_post_ids' - 'uncertainties') <> '{}'::jsonb
         or jsonb_typeof(v_child.value->'source_id') <> 'string' or not public.x_daily_judgement_safe_text(v_child.value->>'source_id', 160)
         or jsonb_typeof(v_child.value->'action_intent') <> 'string' or v_child.value->>'action_intent' not in ('build_position', 'buy', 'add', 'hold', 'reduce', 'sell', 'watch', 'avoid')
         or jsonb_typeof(v_child.value->'action_scope_status') <> 'string' or v_child.value->>'action_scope_status' not in ('specified', 'unspecified')
         or jsonb_typeof(v_child.value->'action_scope') <> 'string'
         or (v_child.value->>'action_scope_status' = 'specified' and (not public.x_daily_judgement_safe_text(v_child.value->>'action_scope', 300) or v_child.value->>'action_scope' = '' or v_child.value->>'action_scope' ~ '(未|不|无法)(明确|说明|提供|确认).{0,24}(标的|对象|资产|范围)|(标的|对象|资产|范围).{0,24}(未|不|无法)(明确|说明|提供|确认|知)'))
         or (v_child.value->>'action_scope_status' = 'unspecified' and v_child.value->>'action_scope' <> '')
         or jsonb_typeof(v_child.value->'conditions') <> 'array'
         or jsonb_typeof(v_child.value->'analysis_ids') <> 'array'
         or jsonb_typeof(v_child.value->'evidence_post_ids') <> 'array'
         or jsonb_typeof(v_child.value->'uncertainties') <> 'array'
         or jsonb_array_length(v_child.value->'analysis_ids') = 0
         or jsonb_array_length(v_child.value->'evidence_post_ids') = 0
         or exists (select 1 from jsonb_array_elements_text(v_child.value->'conditions') value where not public.x_daily_judgement_safe_text(value, 500))
         or exists (select 1 from jsonb_array_elements_text(v_child.value->'analysis_ids') value where not public.x_daily_judgement_safe_text(value, 160))
         or exists (select 1 from jsonb_array_elements_text(v_child.value->'evidence_post_ids') value where not public.x_daily_judgement_safe_text(value, 160))
         or exists (select 1 from jsonb_array_elements_text(v_child.value->'uncertainties') value where not public.x_daily_judgement_safe_text(value, 500))
      then
        raise exception 'invalid_v5_x_daily_judgement_output' using errcode = '22023';
      end if;

      if (
        select count(*) <> count(distinct value)
        from jsonb_array_elements_text(v_child.value->'conditions') value
      ) or (
        select count(*) <> count(distinct value)
        from jsonb_array_elements_text(v_child.value->'analysis_ids') value
      ) or (
        select count(*) <> count(distinct value)
        from jsonb_array_elements_text(v_child.value->'evidence_post_ids') value
      ) then
        raise exception 'invalid_v5_x_daily_judgement_output' using errcode = '22023';
      end if;

      for v_text in
        select coalesce(nullif(v_child.value->>'action_scope', ''), null)
        union all select value from jsonb_array_elements_text(v_child.value->'conditions')
        union all select value from jsonb_array_elements_text(v_child.value->'uncertainties')
      loop
        if v_text is not null and (
          v_text ~* '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|[A-Za-z0-9_.-]{1,64}@[0-9]{1,3})'
          or v_text ~ '(?:系统\\s*)?(?:建议|应当|应该|必须|请|立即).{0,24}(?:买入|卖出|加仓|减仓|建仓|清仓|抄底|追涨)'
        ) then
          raise exception 'invalid_v5_x_daily_judgement_output' using errcode = '22023';
        end if;
      end loop;
    end loop;
  end loop;

  for v_rec in
    select value, ordinality
    from jsonb_array_elements(p_output->'ai_synthesis'->'cross_blogger_integrations') with ordinality
  loop
    if jsonb_typeof(v_rec.value) <> 'object'
       or not (v_rec.value ?& array['integration_id', 'headline', 'synthesis', 'common_points', 'conflict_points', 'related_thesis_ids', 'uncertainties'])
       or (v_rec.value - 'integration_id' - 'headline' - 'synthesis' - 'common_points' - 'conflict_points' - 'related_thesis_ids' - 'uncertainties') <> '{}'::jsonb
       or v_rec.value->>'integration_id' <> format('integration-%s', lpad(v_rec.ordinality::text, 2, '0'))
       or v_rec.value->>'integration_id' = any(v_integration_ids)
       or jsonb_typeof(v_rec.value->'headline') <> 'string' or not public.x_daily_judgement_safe_text(v_rec.value->>'headline', 300)
       or jsonb_typeof(v_rec.value->'synthesis') <> 'string' or not public.x_daily_judgement_safe_text(v_rec.value->>'synthesis', 2000)
       or jsonb_typeof(v_rec.value->'common_points') <> 'array'
       or jsonb_typeof(v_rec.value->'conflict_points') <> 'array'
       or jsonb_typeof(v_rec.value->'related_thesis_ids') <> 'array'
       or jsonb_typeof(v_rec.value->'uncertainties') <> 'array'
       or jsonb_array_length(v_rec.value->'related_thesis_ids') = 0
       or exists (select 1 from jsonb_array_elements_text(v_rec.value->'related_thesis_ids') value where not public.x_daily_judgement_safe_text(value, 160))
       or exists (select 1 from jsonb_array_elements_text(v_rec.value->'uncertainties') value where not public.x_daily_judgement_safe_text(value, 500))
    then
      raise exception 'invalid_v5_x_daily_judgement_output' using errcode = '22023';
    end if;

    if (
      select count(*) <> count(distinct value)
      from jsonb_array_elements_text(v_rec.value->'related_thesis_ids') value
    ) then
      raise exception 'invalid_v5_x_daily_judgement_output' using errcode = '22023';
    end if;

    v_integration_ids := array_append(v_integration_ids, v_rec.value->>'integration_id');

    for v_text in
      select v_rec.value->>'headline'
      union all select v_rec.value->>'synthesis'
      union all select value from jsonb_array_elements_text(v_rec.value->'uncertainties')
    loop
      if v_text ~* '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|[A-Za-z0-9_.-]{1,64}@[0-9]{1,3})'
         or v_text ~ '(?:系统\\s*)?(?:建议|应当|应该|必须|请|立即).{0,24}(?:买入|卖出|加仓|减仓|建仓|清仓|抄底|追涨)' then
        raise exception 'invalid_v5_x_daily_judgement_output' using errcode = '22023';
      end if;
    end loop;

    for v_child in
      select value, ordinality
      from jsonb_array_elements(v_rec.value->'common_points') with ordinality
    loop
      if jsonb_typeof(v_child.value) <> 'object'
         or not (v_child.value ?& array['statement', 'source_ids', 'related_thesis_ids'])
         or (v_child.value - 'statement' - 'source_ids' - 'related_thesis_ids') <> '{}'::jsonb
         or jsonb_typeof(v_child.value->'statement') <> 'string' or not public.x_daily_judgement_safe_text(v_child.value->>'statement', 1000)
         or jsonb_typeof(v_child.value->'source_ids') <> 'array'
         or jsonb_typeof(v_child.value->'related_thesis_ids') <> 'array'
         or jsonb_array_length(v_child.value->'source_ids') = 0
         or jsonb_array_length(v_child.value->'related_thesis_ids') = 0
         or exists (select 1 from jsonb_array_elements_text(v_child.value->'source_ids') value where not public.x_daily_judgement_safe_text(value, 160))
         or exists (select 1 from jsonb_array_elements_text(v_child.value->'related_thesis_ids') value where not public.x_daily_judgement_safe_text(value, 160))
      then
        raise exception 'invalid_v5_x_daily_judgement_output' using errcode = '22023';
      end if;
      if (
        select count(*) <> count(distinct value)
        from jsonb_array_elements_text(v_child.value->'source_ids') value
      ) or (
        select count(*) <> count(distinct value)
        from jsonb_array_elements_text(v_child.value->'related_thesis_ids') value
      ) then
        raise exception 'invalid_v5_x_daily_judgement_output' using errcode = '22023';
      end if;
      if v_child.value->>'statement' ~* '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|[A-Za-z0-9_.-]{1,64}@[0-9]{1,3})'
         or v_child.value->>'statement' ~ '(?:系统\\s*)?(?:建议|应当|应该|必须|请|立即).{0,24}(?:买入|卖出|加仓|减仓|建仓|清仓|抄底|追涨)' then
        raise exception 'invalid_v5_x_daily_judgement_output' using errcode = '22023';
      end if;
    end loop;

    for v_child in
      select value, ordinality
      from jsonb_array_elements(v_rec.value->'conflict_points') with ordinality
    loop
      if jsonb_typeof(v_child.value) <> 'object'
         or not (v_child.value ?& array['issue', 'positions'])
         or (v_child.value - 'issue' - 'positions') <> '{}'::jsonb
         or jsonb_typeof(v_child.value->'issue') <> 'string' or not public.x_daily_judgement_safe_text(v_child.value->>'issue', 1000)
         or jsonb_typeof(v_child.value->'positions') <> 'array'
      then
        raise exception 'invalid_v5_x_daily_judgement_output' using errcode = '22023';
      end if;
      if v_child.value->>'issue' ~* '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|[A-Za-z0-9_.-]{1,64}@[0-9]{1,3})'
         or v_child.value->>'issue' ~ '(?:系统\\s*)?(?:建议|应当|应该|必须|请|立即).{0,24}(?:买入|卖出|加仓|减仓|建仓|清仓|抄底|追涨)' then
        raise exception 'invalid_v5_x_daily_judgement_output' using errcode = '22023';
      end if;

      for v_grandchild in
        select value, ordinality
        from jsonb_array_elements(v_child.value->'positions') with ordinality
      loop
        if jsonb_typeof(v_grandchild.value) <> 'object'
           or not (v_grandchild.value ?& array['position', 'source_ids', 'related_thesis_ids'])
           or (v_grandchild.value - 'position' - 'source_ids' - 'related_thesis_ids') <> '{}'::jsonb
           or jsonb_typeof(v_grandchild.value->'position') <> 'string' or not public.x_daily_judgement_safe_text(v_grandchild.value->>'position', 1000)
           or jsonb_typeof(v_grandchild.value->'source_ids') <> 'array'
           or jsonb_typeof(v_grandchild.value->'related_thesis_ids') <> 'array'
           or jsonb_array_length(v_grandchild.value->'source_ids') = 0
           or jsonb_array_length(v_grandchild.value->'related_thesis_ids') = 0
           or exists (select 1 from jsonb_array_elements_text(v_grandchild.value->'source_ids') value where not public.x_daily_judgement_safe_text(value, 160))
           or exists (select 1 from jsonb_array_elements_text(v_grandchild.value->'related_thesis_ids') value where not public.x_daily_judgement_safe_text(value, 160))
        then
          raise exception 'invalid_v5_x_daily_judgement_output' using errcode = '22023';
        end if;
        if (
          select count(*) <> count(distinct value)
          from jsonb_array_elements_text(v_grandchild.value->'source_ids') value
        ) or (
          select count(*) <> count(distinct value)
          from jsonb_array_elements_text(v_grandchild.value->'related_thesis_ids') value
        ) then
          raise exception 'invalid_v5_x_daily_judgement_output' using errcode = '22023';
        end if;
        if v_grandchild.value->>'position' ~* '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|[A-Za-z0-9_.-]{1,64}@[0-9]{1,3})'
           or v_grandchild.value->>'position' ~ '(?:系统\\s*)?(?:建议|应当|应该|必须|请|立即).{0,24}(?:买入|卖出|加仓|减仓|建仓|清仓|抄底|追涨)' then
          raise exception 'invalid_v5_x_daily_judgement_output' using errcode = '22023';
        end if;
      end loop;
    end loop;
  end loop;

  for v_rec in
    select value, ordinality
    from jsonb_array_elements(p_output->'ai_synthesis'->'ai_assessments') with ordinality
  loop
    if jsonb_typeof(v_rec.value) <> 'object'
       or not (v_rec.value ?& array['assessment_id', 'headline', 'judgement', 'importance_reason', 'reasoning', 'key_assumptions', 'risks', 'watch_variables', 'related_thesis_ids', 'uncertainties'])
       or (v_rec.value - 'assessment_id' - 'headline' - 'judgement' - 'importance_reason' - 'reasoning' - 'key_assumptions' - 'risks' - 'watch_variables' - 'related_thesis_ids' - 'uncertainties') <> '{}'::jsonb
       or v_rec.value->>'assessment_id' <> format('assessment-%s', lpad(v_rec.ordinality::text, 2, '0'))
       or v_rec.value->>'assessment_id' = any(v_assessment_ids)
       or jsonb_typeof(v_rec.value->'headline') <> 'string' or not public.x_daily_judgement_safe_text(v_rec.value->>'headline', 300)
       or jsonb_typeof(v_rec.value->'judgement') <> 'string' or not public.x_daily_judgement_safe_text(v_rec.value->>'judgement', 2000)
       or jsonb_typeof(v_rec.value->'importance_reason') <> 'string' or not public.x_daily_judgement_safe_text(v_rec.value->>'importance_reason', 1000)
       or jsonb_typeof(v_rec.value->'reasoning') <> 'string' or not public.x_daily_judgement_safe_text(v_rec.value->>'reasoning', 2000)
       or jsonb_typeof(v_rec.value->'key_assumptions') <> 'array'
       or jsonb_typeof(v_rec.value->'risks') <> 'array'
       or jsonb_typeof(v_rec.value->'watch_variables') <> 'array'
       or jsonb_typeof(v_rec.value->'related_thesis_ids') <> 'array'
       or jsonb_typeof(v_rec.value->'uncertainties') <> 'array'
       or jsonb_array_length(v_rec.value->'related_thesis_ids') = 0
       or exists (select 1 from jsonb_array_elements_text(v_rec.value->'key_assumptions') value where not public.x_daily_judgement_safe_text(value, 500))
       or exists (select 1 from jsonb_array_elements_text(v_rec.value->'risks') value where not public.x_daily_judgement_safe_text(value, 500))
       or exists (select 1 from jsonb_array_elements_text(v_rec.value->'watch_variables') value where not public.x_daily_judgement_safe_text(value, 500))
       or exists (select 1 from jsonb_array_elements_text(v_rec.value->'related_thesis_ids') value where not public.x_daily_judgement_safe_text(value, 160))
       or exists (select 1 from jsonb_array_elements_text(v_rec.value->'uncertainties') value where not public.x_daily_judgement_safe_text(value, 500))
    then
      raise exception 'invalid_v5_x_daily_judgement_output' using errcode = '22023';
    end if;
    if (
      select count(*) <> count(distinct value)
      from jsonb_array_elements_text(v_rec.value->'related_thesis_ids') value
    ) then
      raise exception 'invalid_v5_x_daily_judgement_output' using errcode = '22023';
    end if;

    v_assessment_ids := array_append(v_assessment_ids, v_rec.value->>'assessment_id');

    for v_text in
      select v_rec.value->>'headline'
      union all select v_rec.value->>'judgement'
      union all select v_rec.value->>'importance_reason'
      union all select v_rec.value->>'reasoning'
      union all select value from jsonb_array_elements_text(v_rec.value->'key_assumptions')
      union all select value from jsonb_array_elements_text(v_rec.value->'risks')
      union all select value from jsonb_array_elements_text(v_rec.value->'watch_variables')
      union all select value from jsonb_array_elements_text(v_rec.value->'uncertainties')
    loop
      if v_text ~* '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|[A-Za-z0-9_.-]{1,64}@[0-9]{1,3})'
         or v_text ~ '(?:系统\\s*)?(?:建议|应当|应该|必须|请|立即).{0,24}(?:买入|卖出|加仓|减仓|建仓|清仓|抄底|追涨)' then
        raise exception 'invalid_v5_x_daily_judgement_output' using errcode = '22023';
      end if;
    end loop;
  end loop;
end;
$$;

create or replace function public.validate_x_daily_judgement_output_authority_v5(p_batch_id uuid, p_output jsonb)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_rec record;
  v_child record;
  v_grandchild record;
  v_text text;
  v_input_text text;
  v_opaque_ids text[];
  v_all_source_ids text[];
  v_expected_sources text[];
  v_expected_evidence text[];
  v_declared_sources text[];
  v_declared_evidence text[];
  v_analysis_source text;
  v_analysis_evidence text[];
  v_parent_sources text[];
  v_parent_evidence text[];
  v_parent_supporting text[];
  v_parent_dissenting text[];
  v_top_related text[];
  v_related_sources text[];
  v_related_supporting text[];
  v_related_dissenting text[];
  v_child_related text[];
  v_child_union text[];
  v_position_union text[];
  v_thesis_sources jsonb := '{}'::jsonb;
  v_thesis_supporting jsonb := '{}'::jsonb;
  v_thesis_dissenting jsonb := '{}'::jsonb;
  v_token_match text[];
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

  perform public.validate_x_daily_judgement_output_v5(p_output);

  if exists (
    select 1
    from public.x_collection_batch_sources
    where batch_id = p_batch_id
      and settlement_status in ('excluded', 'no_new_information')
  ) and jsonb_array_length(p_output->'uncertainties') = 0 then
    raise exception 'invalid_x_daily_judgement_evidence' using errcode = '22023';
  end if;

  select coalesce(array_agg(distinct batch_source.source_id::text order by batch_source.source_id::text), '{}'::text[])
  into v_all_source_ids
  from public.x_collection_batch_sources batch_source
  where batch_source.batch_id = p_batch_id
    and batch_source.settlement_status = 'included';

  select coalesce(string_agg(
    public.x_daily_judgement_jsonb_leaf_text(segment.segment_output) || ' ' ||
    public.x_daily_judgement_jsonb_leaf_text(analysis.analysis_output),
    ' '
  ), '')
  into v_input_text
  from public.x_collection_batches batch
  join public.x_collection_batch_sources batch_source on batch_source.batch_id = batch.id
  join public.x_daily_viewpoint_segments segment
    on segment.source_id = batch_source.source_id
   and segment.range_task_id = batch_source.x_sync_task_id
   and segment.natural_date = batch.natural_date
  cross join lateral jsonb_to_recordset(segment.post_analysis_refs) as ref(post_id text, analysis_version integer)
  join public.canonical_messages message
    on message.source_id = batch_source.source_id and message.external_message_id = ref.post_id
  join public.x_post_analyses analysis
    on analysis.canonical_message_id = message.id and analysis.analysis_version = ref.analysis_version
  where batch.id = p_batch_id
    and batch_source.settlement_status = 'included';

  select coalesce(array_agg(distinct token order by token), '{}'::text[])
  into v_opaque_ids
  from (
    select p_batch_id::text as token
    union all
    select run.id::text from public.x_daily_judgement_runs run where run.batch_id = p_batch_id
    union all
    select batch_source.source_id::text from public.x_collection_batch_sources batch_source where batch_source.batch_id = p_batch_id
    union all
    select segment.id::text
    from public.x_collection_batches batch
    join public.x_collection_batch_sources batch_source on batch_source.batch_id = batch.id
    join public.x_daily_viewpoint_segments segment
      on segment.source_id = batch_source.source_id
     and segment.range_task_id = batch_source.x_sync_task_id
     and segment.natural_date = batch.natural_date
    where batch.id = p_batch_id
    union all
    select ref.post_id || '@' || ref.analysis_version::text
    from public.x_collection_batches batch
    join public.x_collection_batch_sources batch_source on batch_source.batch_id = batch.id
    join public.x_daily_viewpoint_segments segment
      on segment.source_id = batch_source.source_id
     and segment.range_task_id = batch_source.x_sync_task_id
     and segment.natural_date = batch.natural_date
    cross join lateral jsonb_to_recordset(segment.post_analysis_refs) as ref(post_id text, analysis_version integer)
    where batch.id = p_batch_id
    union all
    select evidence.value
    from public.x_collection_batches batch
    join public.x_collection_batch_sources batch_source on batch_source.batch_id = batch.id
    join public.x_daily_viewpoint_segments segment
      on segment.source_id = batch_source.source_id
     and segment.range_task_id = batch_source.x_sync_task_id
     and segment.natural_date = batch.natural_date
    cross join lateral jsonb_array_elements_text(segment.evidence_refs) evidence(value)
    where batch.id = p_batch_id
    union all
    select evidence.value
    from public.x_collection_batches batch
    join public.x_collection_batch_sources batch_source on batch_source.batch_id = batch.id
    join public.x_daily_viewpoint_segments segment
      on segment.source_id = batch_source.source_id
     and segment.range_task_id = batch_source.x_sync_task_id
     and segment.natural_date = batch.natural_date
    cross join lateral jsonb_to_recordset(segment.post_analysis_refs) as ref(post_id text, analysis_version integer)
    join public.canonical_messages message
      on message.source_id = batch_source.source_id and message.external_message_id = ref.post_id
    join public.x_post_analyses analysis
      on analysis.canonical_message_id = message.id and analysis.analysis_version = ref.analysis_version
    cross join lateral jsonb_array_elements_text(analysis.evidence_refs) evidence(value)
    where batch.id = p_batch_id
  ) opaque_tokens;

  for v_rec in
    select value
    from jsonb_array_elements(p_output->'security_industry_theses')
    union all
    select value
    from jsonb_array_elements(p_output->'market_structure_theses')
    union all
    select value
    from jsonb_array_elements(p_output->'strategy_mindset_theses')
  loop
    v_expected_sources := '{}'::text[];
    v_expected_evidence := '{}'::text[];

    for v_text in
      select v_rec.value->>'headline'
      union all select v_rec.value->>'synthesis'
      union all select value from jsonb_array_elements_text(v_rec.value->'uncertainties')
      union all select child.value->>'condition'
      from jsonb_array_elements(v_rec.value->'scenario_branches') child
      union all select child.value->>'outcome'
      from jsonb_array_elements(v_rec.value->'scenario_branches') child
      union all select uncertainty.value
      from jsonb_array_elements(v_rec.value->'scenario_branches') child
      cross join lateral jsonb_array_elements_text(child.value->'uncertainties') uncertainty(value)
      union all select condition.value
      from jsonb_array_elements(v_rec.value->'attributed_actions') child
      cross join lateral jsonb_array_elements_text(child.value->'conditions') condition(value)
      union all select uncertainty.value
      from jsonb_array_elements(v_rec.value->'attributed_actions') child
      cross join lateral jsonb_array_elements_text(child.value->'uncertainties') uncertainty(value)
      union all select nullif(child.value->>'action_scope', '')
      from jsonb_array_elements(v_rec.value->'attributed_actions') child
    loop
      if v_text is not null and exists (
        select 1 from unnest(v_opaque_ids) opaque_id where position(lower(opaque_id) in lower(v_text)) > 0
      ) then
        raise exception 'invalid_x_daily_judgement_evidence' using errcode = '22023';
      end if;
      if v_text is not null then
        for v_token_match in
          select regexp_matches(v_text, '([$¥€]\d+(?:\.\d+)?|\m\d+(?:\.\d+)?%?\M|\m[A-Z]{2,5}\M)', 'g')
        loop
          if position(lower(v_token_match[1]) in lower(v_input_text)) = 0 then
            raise exception 'invalid_x_daily_judgement_evidence' using errcode = '22023';
          end if;
        end loop;
      end if;
    end loop;

    for v_child in
      select value
      from jsonb_array_elements_text(v_rec.value->'analysis_ids') value
    loop
      select batch_source.source_id::text,
             coalesce(array_agg(distinct evidence.value order by evidence.value), '{}'::text[])
      into v_analysis_source, v_analysis_evidence
      from public.x_collection_batches batch
      join public.x_collection_batch_sources batch_source on batch_source.batch_id = batch.id
      join public.x_daily_viewpoint_segments segment
        on segment.source_id = batch_source.source_id
       and segment.range_task_id = batch_source.x_sync_task_id
       and segment.natural_date = batch.natural_date
      cross join lateral jsonb_to_recordset(segment.post_analysis_refs) as ref(post_id text, analysis_version integer)
      join public.canonical_messages message
        on message.source_id = batch_source.source_id and message.external_message_id = ref.post_id
      join public.x_post_analyses analysis
        on analysis.canonical_message_id = message.id and analysis.analysis_version = ref.analysis_version
      cross join lateral jsonb_array_elements_text(analysis.evidence_refs) evidence(value)
      where batch.id = p_batch_id
        and batch_source.settlement_status = 'included'
        and (ref.post_id || '@' || ref.analysis_version::text) = v_child.value
      group by batch_source.source_id;

      if v_analysis_source is null then
        raise exception 'invalid_x_daily_judgement_evidence' using errcode = '22023';
      end if;

      select array_agg(distinct value order by value) into v_expected_sources
      from unnest(v_expected_sources || array[v_analysis_source]) value;
      select array_agg(distinct value order by value) into v_expected_evidence
      from unnest(v_expected_evidence || coalesce(v_analysis_evidence, '{}'::text[])) value;
    end loop;

    select array_agg(value order by value) into v_declared_sources
    from (
      select distinct value from jsonb_array_elements_text(v_rec.value->'supporting_source_ids')
      union
      select distinct value from jsonb_array_elements_text(v_rec.value->'dissenting_source_ids')
    ) s(value);
    select array_agg(value order by value) into v_declared_evidence
    from (
      select distinct value from jsonb_array_elements_text(v_rec.value->'evidence_post_ids')
    ) s(value);
    select array_agg(value order by value) into v_parent_supporting
    from (
      select distinct value from jsonb_array_elements_text(v_rec.value->'supporting_source_ids')
    ) s(value);
    select array_agg(value order by value) into v_parent_dissenting
    from (
      select distinct value from jsonb_array_elements_text(v_rec.value->'dissenting_source_ids')
    ) s(value);

    if coalesce(v_declared_sources, '{}'::text[]) is distinct from coalesce(v_expected_sources, '{}'::text[])
       or coalesce(v_declared_evidence, '{}'::text[]) is distinct from coalesce(v_expected_evidence, '{}'::text[]) then
      raise exception 'invalid_x_daily_judgement_evidence' using errcode = '22023';
    end if;

    if (
      (v_rec.value->>'headline') ~ '(共识|一致认为|共同认为|市场(已经|已)?确认)'
      or (v_rec.value->>'synthesis') ~ '(共识|一致认为|共同认为|市场(已经|已)?确认)'
    ) and (
      coalesce(cardinality(v_parent_supporting), 0) < 2
      or coalesce(cardinality(v_parent_dissenting), 0) > 0
    ) then
      raise exception 'invalid_x_daily_judgement_evidence' using errcode = '22023';
    end if;

    v_thesis_sources := v_thesis_sources || jsonb_build_object(v_rec.value->>'thesis_id', to_jsonb(coalesce(v_declared_sources, '{}'::text[])));
    v_thesis_supporting := v_thesis_supporting || jsonb_build_object(v_rec.value->>'thesis_id', to_jsonb(coalesce(v_parent_supporting, '{}'::text[])));
    v_thesis_dissenting := v_thesis_dissenting || jsonb_build_object(v_rec.value->>'thesis_id', to_jsonb(coalesce(v_parent_dissenting, '{}'::text[])));

    v_parent_sources := v_declared_sources;
    v_parent_evidence := v_declared_evidence;

    for v_child in
      select value
      from jsonb_array_elements(v_rec.value->'scenario_branches')
    loop
      v_expected_sources := '{}'::text[];
      v_expected_evidence := '{}'::text[];

      for v_text in
        select v_child.value->>'condition'
        union all select v_child.value->>'outcome'
        union all select value from jsonb_array_elements_text(v_child.value->'uncertainties')
      loop
        if exists (
          select 1 from unnest(v_opaque_ids) opaque_id where position(lower(opaque_id) in lower(v_text)) > 0
        ) then
          raise exception 'invalid_x_daily_judgement_evidence' using errcode = '22023';
        end if;
        for v_token_match in
          select regexp_matches(v_text, '([$¥€]\d+(?:\.\d+)?|\m\d+(?:\.\d+)?%?\M|\m[A-Z]{2,5}\M)', 'g')
        loop
          if position(lower(v_token_match[1]) in lower(v_input_text)) = 0 then
            raise exception 'invalid_x_daily_judgement_evidence' using errcode = '22023';
          end if;
        end loop;
      end loop;

      for v_text in
        select value
        from jsonb_array_elements_text(v_child.value->'analysis_ids') value
      loop
        select batch_source.source_id::text,
               coalesce(array_agg(distinct evidence.value order by evidence.value), '{}'::text[])
        into v_analysis_source, v_analysis_evidence
        from public.x_collection_batches batch
        join public.x_collection_batch_sources batch_source on batch_source.batch_id = batch.id
        join public.x_daily_viewpoint_segments segment
          on segment.source_id = batch_source.source_id
         and segment.range_task_id = batch_source.x_sync_task_id
         and segment.natural_date = batch.natural_date
        cross join lateral jsonb_to_recordset(segment.post_analysis_refs) as ref(post_id text, analysis_version integer)
        join public.canonical_messages message
          on message.source_id = batch_source.source_id and message.external_message_id = ref.post_id
        join public.x_post_analyses analysis
          on analysis.canonical_message_id = message.id and analysis.analysis_version = ref.analysis_version
        cross join lateral jsonb_array_elements_text(analysis.evidence_refs) evidence(value)
        where batch.id = p_batch_id
          and batch_source.settlement_status = 'included'
          and (ref.post_id || '@' || ref.analysis_version::text) = v_text
        group by batch_source.source_id;

        if v_analysis_source is null then
          raise exception 'invalid_x_daily_judgement_evidence' using errcode = '22023';
        end if;
        select array_agg(distinct value order by value) into v_expected_sources
        from unnest(v_expected_sources || array[v_analysis_source]) value;
        select array_agg(distinct value order by value) into v_expected_evidence
        from unnest(v_expected_evidence || coalesce(v_analysis_evidence, '{}'::text[])) value;
      end loop;

      select array_agg(value order by value) into v_declared_sources
      from (select distinct value from jsonb_array_elements_text(v_child.value->'source_ids')) s(value);
      select array_agg(value order by value) into v_declared_evidence
      from (select distinct value from jsonb_array_elements_text(v_child.value->'evidence_post_ids')) s(value);

      if coalesce(v_declared_sources, '{}'::text[]) is distinct from coalesce(v_expected_sources, '{}'::text[])
         or coalesce(v_declared_evidence, '{}'::text[]) is distinct from coalesce(v_expected_evidence, '{}'::text[])
         or exists (select 1 from unnest(coalesce(v_declared_sources, '{}'::text[])) value where not value = any(coalesce(v_parent_sources, '{}'::text[])))
         or exists (select 1 from unnest(coalesce(v_declared_evidence, '{}'::text[])) value where not value = any(coalesce(v_parent_evidence, '{}'::text[]))) then
        raise exception 'invalid_x_daily_judgement_evidence' using errcode = '22023';
      end if;
    end loop;

    for v_child in
      select value
      from jsonb_array_elements(v_rec.value->'attributed_actions')
    loop
      v_expected_evidence := '{}'::text[];
      if not (v_child.value->>'source_id' = any(coalesce(v_parent_sources, '{}'::text[]))) then
        raise exception 'invalid_x_daily_judgement_evidence' using errcode = '22023';
      end if;

      for v_text in
        select value
        from jsonb_array_elements_text(v_child.value->'analysis_ids') value
      loop
        select batch_source.source_id::text,
               coalesce(array_agg(distinct evidence.value order by evidence.value), '{}'::text[])
        into v_analysis_source, v_analysis_evidence
        from public.x_collection_batches batch
        join public.x_collection_batch_sources batch_source on batch_source.batch_id = batch.id
        join public.x_daily_viewpoint_segments segment
          on segment.source_id = batch_source.source_id
         and segment.range_task_id = batch_source.x_sync_task_id
         and segment.natural_date = batch.natural_date
        cross join lateral jsonb_to_recordset(segment.post_analysis_refs) as ref(post_id text, analysis_version integer)
        join public.canonical_messages message
          on message.source_id = batch_source.source_id and message.external_message_id = ref.post_id
        join public.x_post_analyses analysis
          on analysis.canonical_message_id = message.id and analysis.analysis_version = ref.analysis_version
        cross join lateral jsonb_array_elements_text(analysis.evidence_refs) evidence(value)
        where batch.id = p_batch_id
          and batch_source.settlement_status = 'included'
          and (ref.post_id || '@' || ref.analysis_version::text) = v_text
        group by batch_source.source_id;
        if v_analysis_source is null or v_analysis_source <> v_child.value->>'source_id' then
          raise exception 'invalid_x_daily_judgement_evidence' using errcode = '22023';
        end if;
        select array_agg(distinct value order by value) into v_expected_evidence
        from unnest(v_expected_evidence || coalesce(v_analysis_evidence, '{}'::text[])) value;
      end loop;

      select array_agg(value order by value) into v_declared_evidence
      from (select distinct value from jsonb_array_elements_text(v_child.value->'evidence_post_ids')) s(value);
      if coalesce(v_declared_evidence, '{}'::text[]) is distinct from coalesce(v_expected_evidence, '{}'::text[])
         or exists (select 1 from unnest(coalesce(v_declared_evidence, '{}'::text[])) value where not value = any(coalesce(v_parent_evidence, '{}'::text[]))) then
        raise exception 'invalid_x_daily_judgement_evidence' using errcode = '22023';
      end if;
    end loop;
  end loop;

  for v_rec in
    select value
    from jsonb_array_elements(p_output->'ai_synthesis'->'cross_blogger_integrations')
  loop
    select array_agg(value order by value) into v_child_related
    from (select distinct value from jsonb_array_elements_text(v_rec.value->'related_thesis_ids')) s(value);
    v_top_related := v_child_related;

    if exists (
      select 1 from unnest(coalesce(v_top_related, '{}'::text[])) thesis_id
      where not (v_thesis_sources ? thesis_id)
    ) then
      raise exception 'invalid_x_daily_judgement_evidence' using errcode = '22023';
    end if;

    select array_agg(distinct value order by value) into v_related_sources
    from (
      select jsonb_array_elements_text(v_thesis_sources->thesis_id) as value
      from unnest(coalesce(v_child_related, '{}'::text[])) thesis_id
    ) s;
    select array_agg(distinct value order by value) into v_related_supporting
    from (
      select jsonb_array_elements_text(v_thesis_supporting->thesis_id) as value
      from unnest(coalesce(v_child_related, '{}'::text[])) thesis_id
    ) s;
    select array_agg(distinct value order by value) into v_related_dissenting
    from (
      select jsonb_array_elements_text(v_thesis_dissenting->thesis_id) as value
      from unnest(coalesce(v_child_related, '{}'::text[])) thesis_id
    ) s;

    if coalesce(cardinality(v_related_sources), 0) < 2
       or (jsonb_array_length(v_rec.value->'common_points') = 0 and jsonb_array_length(v_rec.value->'conflict_points') = 0) then
      raise exception 'invalid_x_daily_judgement_evidence' using errcode = '22023';
    end if;

    for v_text in
      select v_rec.value->>'headline'
      union all select v_rec.value->>'synthesis'
      union all select value from jsonb_array_elements_text(v_rec.value->'uncertainties')
    loop
      if exists (
        select 1 from unnest(v_opaque_ids) opaque_id where position(lower(opaque_id) in lower(v_text)) > 0
      ) then
        raise exception 'invalid_x_daily_judgement_evidence' using errcode = '22023';
      end if;
      for v_token_match in
        select regexp_matches(v_text, '([$¥€]\d+(?:\.\d+)?|\m\d+(?:\.\d+)?%?\M|\m[A-Z]{2,5}\M)', 'g')
      loop
        if position(lower(v_token_match[1]) in lower(v_input_text)) = 0 then
          raise exception 'invalid_x_daily_judgement_evidence' using errcode = '22023';
        end if;
      end loop;
    end loop;

    if (
      (v_rec.value->>'headline') ~ '(共识|一致认为|共同认为|市场(已经|已)?确认)'
      or (v_rec.value->>'synthesis') ~ '(共识|一致认为|共同认为|市场(已经|已)?确认)'
    ) and (
      coalesce(cardinality(v_related_supporting), 0) < 2
      or coalesce(cardinality(v_related_dissenting), 0) > 0
    ) then
      raise exception 'invalid_x_daily_judgement_evidence' using errcode = '22023';
    end if;

    v_child_union := '{}'::text[];

    for v_child in
      select value
      from jsonb_array_elements(v_rec.value->'common_points')
    loop
      select array_agg(value order by value) into v_declared_sources
      from (select distinct value from jsonb_array_elements_text(v_child.value->'source_ids')) s(value);
      select array_agg(value order by value) into v_child_related
      from (select distinct value from jsonb_array_elements_text(v_child.value->'related_thesis_ids')) s(value);
      if exists (
        select 1 from unnest(coalesce(v_child_related, '{}'::text[])) thesis_id
        where not (v_thesis_sources ? thesis_id)
           or not thesis_id = any(coalesce(v_top_related, '{}'::text[]))
      ) then
        raise exception 'invalid_x_daily_judgement_evidence' using errcode = '22023';
      end if;
      select array_agg(distinct value order by value) into v_expected_sources
      from (
        select jsonb_array_elements_text(v_thesis_sources->thesis_id) as value
        from unnest(coalesce(v_child_related, '{}'::text[])) thesis_id
      ) s;
      if coalesce(cardinality(v_declared_sources), 0) < 2
         or exists (select 1 from unnest(coalesce(v_declared_sources, '{}'::text[])) value where not value = any(coalesce(v_expected_sources, '{}'::text[])))
      then
        raise exception 'invalid_x_daily_judgement_evidence' using errcode = '22023';
      end if;
      if v_child.value->>'statement' ~ '(共识|一致认为|共同认为|市场(已经|已)?确认)'
         and (coalesce(cardinality(v_related_supporting), 0) < 2 or coalesce(cardinality(v_related_dissenting), 0) > 0) then
        raise exception 'invalid_x_daily_judgement_evidence' using errcode = '22023';
      end if;
      select array_agg(distinct value order by value) into v_child_union
      from unnest(coalesce(v_child_union, '{}'::text[]) || coalesce(v_child_related, '{}'::text[])) value;
    end loop;

    for v_child in
      select value
      from jsonb_array_elements(v_rec.value->'conflict_points')
    loop
      if jsonb_array_length(v_child.value->'positions') < 2 then
        raise exception 'invalid_x_daily_judgement_evidence' using errcode = '22023';
      end if;
      v_position_union := '{}'::text[];
      for v_grandchild in
        select value
        from jsonb_array_elements(v_child.value->'positions')
      loop
        select array_agg(value order by value) into v_declared_sources
        from (select distinct value from jsonb_array_elements_text(v_grandchild.value->'source_ids')) s(value);
        select array_agg(value order by value) into v_child_related
        from (select distinct value from jsonb_array_elements_text(v_grandchild.value->'related_thesis_ids')) s(value);
        if exists (
          select 1 from unnest(coalesce(v_child_related, '{}'::text[])) thesis_id
          where not (v_thesis_sources ? thesis_id)
             or not thesis_id = any(coalesce(v_top_related, '{}'::text[]))
        ) then
          raise exception 'invalid_x_daily_judgement_evidence' using errcode = '22023';
        end if;
        select array_agg(distinct value order by value) into v_expected_sources
        from (
          select jsonb_array_elements_text(v_thesis_sources->thesis_id) as value
          from unnest(coalesce(v_child_related, '{}'::text[])) thesis_id
        ) s;
        if exists (select 1 from unnest(coalesce(v_declared_sources, '{}'::text[])) value where not value = any(coalesce(v_expected_sources, '{}'::text[]))) then
          raise exception 'invalid_x_daily_judgement_evidence' using errcode = '22023';
        end if;
        select array_agg(distinct value order by value) into v_position_union
        from unnest(coalesce(v_position_union, '{}'::text[]) || coalesce(v_declared_sources, '{}'::text[])) value;
        select array_agg(distinct value order by value) into v_child_union
        from unnest(coalesce(v_child_union, '{}'::text[]) || coalesce(v_child_related, '{}'::text[])) value;
      end loop;
      if coalesce(cardinality(v_position_union), 0) < 2 then
        raise exception 'invalid_x_daily_judgement_evidence' using errcode = '22023';
      end if;
    end loop;

    if coalesce(v_child_union, '{}'::text[]) is distinct from coalesce(v_top_related, '{}'::text[]) then
      raise exception 'invalid_x_daily_judgement_evidence' using errcode = '22023';
    end if;
  end loop;

  for v_rec in
    select value
    from jsonb_array_elements(p_output->'ai_synthesis'->'ai_assessments')
  loop
    select array_agg(value order by value) into v_child_related
    from (select distinct value from jsonb_array_elements_text(v_rec.value->'related_thesis_ids')) s(value);
    if exists (
      select 1 from unnest(coalesce(v_child_related, '{}'::text[])) thesis_id
      where not (v_thesis_sources ? thesis_id)
    ) then
      raise exception 'invalid_x_daily_judgement_evidence' using errcode = '22023';
    end if;

    select array_agg(distinct value order by value) into v_related_supporting
    from (
      select jsonb_array_elements_text(v_thesis_supporting->thesis_id) as value
      from unnest(coalesce(v_child_related, '{}'::text[])) thesis_id
    ) s;
    select array_agg(distinct value order by value) into v_related_dissenting
    from (
      select jsonb_array_elements_text(v_thesis_dissenting->thesis_id) as value
      from unnest(coalesce(v_child_related, '{}'::text[])) thesis_id
    ) s;

    for v_text in
      select v_rec.value->>'headline'
      union all select v_rec.value->>'judgement'
      union all select v_rec.value->>'importance_reason'
      union all select v_rec.value->>'reasoning'
      union all select value from jsonb_array_elements_text(v_rec.value->'key_assumptions')
      union all select value from jsonb_array_elements_text(v_rec.value->'risks')
      union all select value from jsonb_array_elements_text(v_rec.value->'watch_variables')
      union all select value from jsonb_array_elements_text(v_rec.value->'uncertainties')
    loop
      if exists (
        select 1 from unnest(v_opaque_ids) opaque_id where position(lower(opaque_id) in lower(v_text)) > 0
      ) then
        raise exception 'invalid_x_daily_judgement_evidence' using errcode = '22023';
      end if;
      for v_token_match in
        select regexp_matches(v_text, '([$¥€]\d+(?:\.\d+)?|\m\d+(?:\.\d+)?%?\M|\m[A-Z]{2,5}\M)', 'g')
      loop
        if position(lower(v_token_match[1]) in lower(v_input_text)) = 0 then
          raise exception 'invalid_x_daily_judgement_evidence' using errcode = '22023';
        end if;
      end loop;
    end loop;

    if (
      (v_rec.value->>'headline') ~ '(共识|一致认为|共同认为|市场(已经|已)?确认)'
      or (v_rec.value->>'judgement') ~ '(共识|一致认为|共同认为|市场(已经|已)?确认)'
      or (v_rec.value->>'reasoning') ~ '(共识|一致认为|共同认为|市场(已经|已)?确认)'
    ) and (
      coalesce(cardinality(v_related_supporting), 0) < 2
      or coalesce(cardinality(v_related_dissenting), 0) > 0
    ) then
      raise exception 'invalid_x_daily_judgement_evidence' using errcode = '22023';
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
  if new.schema_version not in ('v4-x-cross-blogger', 'v5-x-cross-blogger') then
    perform public.validate_x_daily_judgement_output(new.output);
  end if;
  v_expected_snapshot := public.build_x_daily_judgement_input_snapshot(new.batch_id);
  if new.input_snapshot <> v_expected_snapshot then
    raise exception 'invalid_x_daily_judgement_snapshot' using errcode = '22023';
  end if;
  if new.schema_version = 'v5-x-cross-blogger' then
    perform public.validate_x_daily_judgement_output_authority_v5(new.batch_id, new.output);
  elsif new.schema_version = 'v4-x-cross-blogger' then
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
       (p_payload->>'schema_version' = 'v5-x-cross-blogger' and p_payload->>'prompt_version' = 'v5-x-cross-blogger-1'
        and jsonb_typeof(p_payload->'ai_synthesis') = 'object'
        and jsonb_typeof(p_payload->'security_industry_theses') = 'array'
        and jsonb_typeof(p_payload->'market_structure_theses') = 'array'
        and jsonb_typeof(p_payload->'strategy_mindset_theses') = 'array')
       or (p_payload->>'schema_version' = 'v4-x-cross-blogger' and p_payload->>'prompt_version' = 'v4-x-cross-blogger-1'
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
  select case
    when count(*) filter (where settlement_status in ('excluded', 'no_new_information')) > 0 then 'partial'
    else 'complete'
  end
  into v_coverage_status
  from public.x_collection_batch_sources
  where batch_id = v_run.batch_id;
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

revoke all on function public.validate_x_daily_judgement_output_v5(jsonb),
  public.validate_x_daily_judgement_output_authority_v5(uuid, jsonb),
  public.x_daily_judgement_jsonb_leaf_text(jsonb)
  from public, anon, authenticated;
grant execute on function public.validate_x_daily_judgement_output_v5(jsonb),
  public.validate_x_daily_judgement_output_authority_v5(uuid, jsonb),
  public.x_daily_judgement_jsonb_leaf_text(jsonb)
  to service_role;
