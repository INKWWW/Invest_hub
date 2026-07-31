-- Harden the Task 1 boundary without re-entering judgement settlement from a
-- source-completion transaction.  A subsequent scheduler tick dispatches only
-- already-committed batch work.

create or replace function public.x_daily_judgement_safe_text(p_value text, p_max integer)
returns boolean
language sql
immutable
set search_path = public
as $$
  select p_value is not null
    and length(p_value) between 1 and p_max
    and p_value !~ '[[:cntrl:]]'
    and p_value !~* '(^/|[\\/]|file:|local_|raw_|cookie|browser.?profile)'
$$;

create or replace function public.validate_x_daily_judgement_output(p_output jsonb)
returns void language plpgsql set search_path = public as $$
declare v_item jsonb; begin
  if jsonb_typeof(p_output) <> 'object' or not (p_output ?& array['stock_viewpoints','market_industry_viewpoints','uncertainties'])
     or (p_output - 'stock_viewpoints' - 'market_industry_viewpoints' - 'uncertainties') <> '{}'::jsonb
     or jsonb_typeof(p_output->'stock_viewpoints') <> 'array'
     or jsonb_typeof(p_output->'market_industry_viewpoints') <> 'array'
     or jsonb_typeof(p_output->'uncertainties') <> 'array'
     or exists (select 1 from jsonb_array_elements(p_output->'uncertainties') value where jsonb_typeof(value) <> 'string' or not public.x_daily_judgement_safe_text(value #>> '{}', 500)) then
    raise exception 'invalid_x_daily_judgement_output' using errcode = '22023';
  end if;
  for v_item in select value from jsonb_array_elements(p_output->'stock_viewpoints') union all select value from jsonb_array_elements(p_output->'market_industry_viewpoints') loop
    if jsonb_typeof(v_item) <> 'object' or not (v_item ?& array['statement','supporting_source_ids','dissenting_source_ids','analysis_ids','evidence_post_ids','uncertainties'])
       or (v_item - 'statement' - 'supporting_source_ids' - 'dissenting_source_ids' - 'analysis_ids' - 'evidence_post_ids' - 'uncertainties') <> '{}'::jsonb
       or jsonb_typeof(v_item->'statement') <> 'string' or not public.x_daily_judgement_safe_text(v_item->>'statement', 1000)
       or jsonb_typeof(v_item->'supporting_source_ids') <> 'array' or jsonb_typeof(v_item->'dissenting_source_ids') <> 'array'
       or jsonb_typeof(v_item->'analysis_ids') <> 'array' or jsonb_typeof(v_item->'evidence_post_ids') <> 'array' or jsonb_typeof(v_item->'uncertainties') <> 'array'
       or exists (select 1 from jsonb_array_elements_text(v_item->'supporting_source_ids') value where value !~ '^[0-9a-f-]{36}$')
       or exists (select 1 from jsonb_array_elements_text(v_item->'dissenting_source_ids') value where value !~ '^[0-9a-f-]{36}$')
       or exists (select 1 from jsonb_array_elements_text(v_item->'analysis_ids') value where value !~ '^[A-Za-z0-9_.@-]{1,128}$')
       or exists (select 1 from jsonb_array_elements_text(v_item->'evidence_post_ids') value where value !~ '^[A-Za-z0-9_.@-]{1,128}$')
       or exists (select 1 from jsonb_array_elements_text(v_item->'uncertainties') value where not public.x_daily_judgement_safe_text(value, 500)) then
      raise exception 'invalid_x_daily_judgement_output' using errcode = '22023';
    end if;
  end loop;
end;
$$;

create or replace function public.validate_x_daily_judgement_input_snapshot(p_snapshot jsonb)
returns void language plpgsql set search_path = public as $$
declare v_source jsonb; v_segment jsonb; v_analysis jsonb; begin
  if jsonb_typeof(p_snapshot) <> 'object' or not (p_snapshot ? 'sources') or (p_snapshot - 'sources') <> '{}'::jsonb or jsonb_typeof(p_snapshot->'sources') <> 'array' then raise exception 'invalid_x_daily_judgement_snapshot' using errcode = '22023'; end if;
  for v_source in select value from jsonb_array_elements(p_snapshot->'sources') loop
    if jsonb_typeof(v_source) <> 'object' or not (v_source ?& array['source_id','display_name','settlement_status','segments']) or (v_source - 'source_id' - 'display_name' - 'settlement_status' - 'segments') <> '{}'::jsonb
       or jsonb_typeof(v_source->'source_id') <> 'string' or (v_source->>'source_id') !~ '^[0-9a-f-]{36}$'
       or jsonb_typeof(v_source->'display_name') <> 'string' or not public.x_daily_judgement_safe_text(v_source->>'display_name', 160)
       or jsonb_typeof(v_source->'settlement_status') <> 'string' or v_source->>'settlement_status' not in ('included', 'no_new_information', 'excluded')
       or jsonb_typeof(v_source->'segments') <> 'array' then raise exception 'invalid_x_daily_judgement_snapshot' using errcode = '22023'; end if;
    for v_segment in select value from jsonb_array_elements(v_source->'segments') loop
      if jsonb_typeof(v_segment) <> 'object' or not (v_segment ?& array['segment_id','analysis_ids','evidence_post_ids']) or (v_segment - 'segment_id' - 'analysis_ids' - 'evidence_post_ids') <> '{}'::jsonb
         or jsonb_typeof(v_segment->'segment_id') <> 'string' or (v_segment->>'segment_id') !~ '^[0-9a-f-]{36}$'
         or jsonb_typeof(v_segment->'analysis_ids') <> 'array' or jsonb_typeof(v_segment->'evidence_post_ids') <> 'array'
         or exists (select 1 from jsonb_array_elements_text(v_segment->'evidence_post_ids') value where value !~ '^[A-Za-z0-9_.@-]{1,128}$') then raise exception 'invalid_x_daily_judgement_snapshot' using errcode = '22023'; end if;
      for v_analysis in select value from jsonb_array_elements(v_segment->'analysis_ids') loop
        if jsonb_typeof(v_analysis) <> 'object' or not (v_analysis ?& array['post_id','analysis_version']) or (v_analysis - 'post_id' - 'analysis_version') <> '{}'::jsonb
           or jsonb_typeof(v_analysis->'post_id') <> 'string' or (v_analysis->>'post_id') !~ '^[A-Za-z0-9_.@-]{1,128}$'
           or jsonb_typeof(v_analysis->'analysis_version') <> 'number' then raise exception 'invalid_x_daily_judgement_snapshot' using errcode = '22023'; end if;
      end loop;
    end loop;
  end loop;
end;
$$;

create or replace function public.dispatch_due_x_collection_batch_settlements(p_now timestamptz)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_batch record; v_results jsonb := '[]'::jsonb; begin
  if p_now is null then raise exception 'invalid_x_collection_batch_settlement' using errcode = '22023'; end if;
  for v_batch in select id from public.x_collection_batches where status = 'collecting' order by cutoff_at for update skip locked loop
    v_results := v_results || jsonb_build_array(public.settle_x_collection_batch(v_batch.id, p_now));
  end loop;
  return jsonb_build_object('settled_at', p_now, 'batches', v_results);
end;
$$;

-- A judgement version is an immutable rendering of the frozen batch, not an
-- arbitrary JSON document that merely has UUID-shaped fields.  Rebuild the
-- only admissible snapshot from the batch rows and the persisted segment
-- references, then require byte-for-byte JSONB equality.  This also prevents
-- duplicate, omitted, or cross-batch identities from being smuggled in.
create or replace function public.enforce_x_daily_judgement_version()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_expected_revision integer;
  v_expected_snapshot jsonb;
  v_has_included boolean;
  v_evidence_id text;
  v_source_id text;
  v_analysis_id text;
  v_allowed_evidence text[];
  v_allowed_sources text[];
  v_allowed_analysis text[];
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
  perform public.validate_x_daily_judgement_output(new.output);

  select exists(
    select 1 from public.x_collection_batch_sources
    where batch_id = new.batch_id and settlement_status = 'included'
  ) into v_has_included;

  if v_has_included then
    select jsonb_build_object('sources', coalesce(jsonb_agg(jsonb_build_object(
      'source_id', batch_source.source_id::text,
      'display_name', batch_source.source_display_name,
      'settlement_status', batch_source.settlement_status,
      'segments', coalesce((
        select jsonb_agg(jsonb_build_object(
          'segment_id', segment.id::text,
          'analysis_ids', segment.post_analysis_refs,
          'evidence_post_ids', segment.evidence_refs
        ) order by segment.id)
        from public.x_daily_viewpoint_segments segment
        where segment.source_id = batch_source.source_id
          and segment.range_task_id = batch_source.x_sync_task_id
      ), '[]'::jsonb)
    ) order by batch_source.source_id), '[]'::jsonb))
    into v_expected_snapshot
    from public.x_collection_batch_sources batch_source
    where batch_source.batch_id = new.batch_id
      and batch_source.settlement_status = 'included';
  else
    select jsonb_build_object('sources', coalesce(jsonb_agg(jsonb_build_object(
      'source_id', source_id::text,
      'display_name', source_display_name,
      'settlement_status', settlement_status,
      'segments', '[]'::jsonb
    ) order by source_id), '[]'::jsonb))
    into v_expected_snapshot
    from public.x_collection_batch_sources
    where batch_id = new.batch_id;
  end if;

  if new.input_snapshot <> v_expected_snapshot then
    raise exception 'invalid_x_daily_judgement_snapshot' using errcode = '22023';
  end if;

  select coalesce(array_agg(distinct value), '{}') into v_allowed_sources
  from jsonb_path_query(new.input_snapshot, '$.sources[*].source_id') as value_json(value_json)
  cross join lateral (select trim(both '"' from value_json::text) as value) safe;
  select coalesce(array_agg(distinct value), '{}') into v_allowed_evidence
  from jsonb_path_query(new.input_snapshot, '$.sources[*].segments[*].evidence_post_ids[*]') as value_json(value_json)
  cross join lateral (select trim(both '"' from value_json::text) as value) safe;
  select coalesce(array_agg(distinct analysis_value.value), '{}') into v_allowed_analysis
  from jsonb_path_query(new.input_snapshot, '$.sources[*].segments[*].analysis_ids[*]') as analysis_json(value_json)
  cross join lateral jsonb_to_record(analysis_json.value_json) as analysis_ref(post_id text, analysis_version integer)
  cross join lateral (select analysis_ref.post_id || '@' || analysis_ref.analysis_version::text as value) analysis_value;

  for v_source_id in
    select source.value
    from jsonb_array_elements(coalesce(new.output->'stock_viewpoints', '[]'::jsonb)) item
    cross join lateral jsonb_array_elements_text(item->'supporting_source_ids') source(value)
    union all
    select source.value
    from jsonb_array_elements(coalesce(new.output->'stock_viewpoints', '[]'::jsonb)) item
    cross join lateral jsonb_array_elements_text(item->'dissenting_source_ids') source(value)
    union all
    select source.value
    from jsonb_array_elements(coalesce(new.output->'market_industry_viewpoints', '[]'::jsonb)) item
    cross join lateral jsonb_array_elements_text(item->'supporting_source_ids') source(value)
    union all
    select source.value
    from jsonb_array_elements(coalesce(new.output->'market_industry_viewpoints', '[]'::jsonb)) item
    cross join lateral jsonb_array_elements_text(item->'dissenting_source_ids') source(value)
  loop
    if not v_source_id = any(v_allowed_sources) then
      raise exception 'invalid_x_daily_judgement_evidence' using errcode = '22023';
    end if;
  end loop;

  for v_analysis_id in
    select analysis.value
    from jsonb_array_elements(coalesce(new.output->'stock_viewpoints', '[]'::jsonb)) item
    cross join lateral jsonb_array_elements_text(item->'analysis_ids') analysis(value)
    union all
    select analysis.value
    from jsonb_array_elements(coalesce(new.output->'market_industry_viewpoints', '[]'::jsonb)) item
    cross join lateral jsonb_array_elements_text(item->'analysis_ids') analysis(value)
  loop
    if not v_analysis_id = any(v_allowed_analysis) then
      raise exception 'invalid_x_daily_judgement_evidence' using errcode = '22023';
    end if;
  end loop;

  for v_evidence_id in
    select evidence.value
    from jsonb_array_elements(coalesce(new.output->'stock_viewpoints', '[]'::jsonb)) item
    cross join lateral jsonb_array_elements_text(item->'evidence_post_ids') evidence(value)
    union all
    select evidence.value
    from jsonb_array_elements(coalesce(new.output->'market_industry_viewpoints', '[]'::jsonb)) item
    cross join lateral jsonb_array_elements_text(item->'evidence_post_ids') evidence(value)
  loop
    if not v_evidence_id = any(v_allowed_evidence) then
      raise exception 'invalid_x_daily_judgement_evidence' using errcode = '22023';
    end if;
  end loop;
  return new;
end;
$$;

alter function public.ensure_due_x_collection_batches(uuid, timestamptz)
  rename to ensure_due_x_collection_batches_core;

create or replace function public.ensure_due_x_collection_batches(p_worker_id uuid, p_now timestamptz)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_created jsonb; v_settled jsonb; begin
  -- Preserve the previously-defined source scheduling behaviour by calling its
  -- body through the renamed implementation installed below.
  v_created := public.ensure_due_x_collection_batches_core(p_worker_id, p_now);
  -- This runs only after a preceding source completion was committed.  It does
  -- not share that transaction's source/task locks.
  v_settled := public.dispatch_due_x_collection_batch_settlements(p_now);
  return v_created || jsonb_build_object('settlements', v_settled->'batches');
end;
$$;

revoke all on function public.dispatch_due_x_collection_batch_settlements(timestamptz), public.ensure_due_x_collection_batches_core(uuid, timestamptz)
  from public, anon, authenticated;
revoke all on function public.ensure_due_x_collection_batches(uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.dispatch_due_x_collection_batch_settlements(timestamptz), public.ensure_due_x_collection_batches(uuid, timestamptz) to service_role;
