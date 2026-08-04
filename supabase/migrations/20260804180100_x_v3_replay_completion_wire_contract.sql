-- The Worker/API wire contract carries daily schema metadata.  Persist only
-- the output body; version metadata belongs in the dedicated columns.

create or replace function public.complete_x_v3_verification_replay(p_replay_id uuid, p_attempt integer, p_worker_id uuid, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_replay public.x_v3_verification_replays%rowtype;
  v_snapshot public.x_v3_verification_replay_sources%rowtype;
  v_source jsonb;
  v_analysis jsonb;
  v_segment jsonb;
  v_item jsonb;
  v_source_id uuid;
  v_post_id text;
  v_analysis_ids text[];
  v_expected_posts text[];
  v_submitted_posts text[];
  v_item_analysis_ids text[];
  v_item_source_ids text[];
  v_item_evidence_ids text[];
  v_expected_evidence_ids text[];
  v_allowed_evidence text[];
  v_canonical_id uuid;
  v_post_link text;
  v_input_snapshot jsonb;
  v_daily_output jsonb;
begin
  select * into v_replay from public.x_v3_verification_replays where id = p_replay_id for update;
  if not found or v_replay.status <> 'running' or v_replay.attempt <> p_attempt
     or v_replay.lease_owner <> p_worker_id or v_replay.lease_expires_at <= timezone('utc', now()) then
    raise exception 'lease_mismatch' using errcode = 'PT409';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object'
     or (p_payload - 'provider' - 'model_reported' - 'sources' - 'daily') <> '{}'::jsonb
     or p_payload->>'provider' <> 'codex_cli'
     or not (p_payload ? 'model_reported')
     or jsonb_typeof(p_payload->'sources') <> 'array' or jsonb_typeof(p_payload->'daily') <> 'object'
     or jsonb_array_length(p_payload->'sources') <> (select count(*) from public.x_v3_verification_replay_sources where replay_id = v_replay.id) then
    raise exception 'invalid_x_v3_verification_completion' using errcode = '22023';
  end if;
  if p_payload->'daily'->>'schema_version' <> 'v3-x-cross-blogger'
     or p_payload->'daily'->>'prompt_version' <> 'v3-x-cross-blogger-1' then
    raise exception 'invalid_x_v3_verification_completion' using errcode = '22023';
  end if;
  v_daily_output := (p_payload->'daily') - 'schema_version'::text - 'prompt_version'::text;
  perform public.validate_x_daily_judgement_output_v3(v_daily_output);

  for v_source in select value from jsonb_array_elements(p_payload->'sources') loop
    if jsonb_typeof(v_source) <> 'object' or (v_source - 'source_id' - 'analyses' - 'segment') <> '{}'::jsonb
       or jsonb_typeof(v_source->'analyses') <> 'array' or jsonb_typeof(v_source->'segment') <> 'object' then
      raise exception 'invalid_x_v3_verification_source' using errcode = '22023';
    end if;
    begin v_source_id := (v_source->>'source_id')::uuid;
    exception when invalid_text_representation then raise exception 'invalid_x_v3_verification_source' using errcode = '22023'; end;
    select * into v_snapshot from public.x_v3_verification_replay_sources
      where replay_id = v_replay.id and source_id = v_source_id;
    if not found then raise exception 'invalid_x_v3_verification_source' using errcode = '22023'; end if;
    if (select count(*) from jsonb_array_elements(p_payload->'sources') item where item->>'source_id' = v_source_id::text) <> 1 then
      raise exception 'invalid_x_v3_verification_source' using errcode = '22023';
    end if;
    select coalesce(array_agg(post->>'post_id' order by post->>'post_id'), '{}') into v_expected_posts
    from jsonb_array_elements(v_snapshot.posts) post;
    select coalesce(array_agg(item->>'post_id' order by item->>'post_id'), '{}') into v_submitted_posts
    from jsonb_array_elements(v_source->'analyses') item;
    if v_submitted_posts is distinct from v_expected_posts
       or cardinality(v_submitted_posts) <> cardinality(array(select distinct unnest(v_submitted_posts))) then
      raise exception 'x_v3_verification_analysis_coverage_mismatch' using errcode = '22023';
    end if;
    for v_analysis in select value from jsonb_array_elements(v_source->'analyses') loop
      if jsonb_typeof(v_analysis) <> 'object'
         or (v_analysis - 'post_id' - 'analysis_id' - 'analysis_version' - 'schema_version' - 'prompt_version' - 'analysis_output' - 'blogger_viewpoint' - 'arguments' - 'quoted_post_viewpoint' - 'uncertainties' - 'evidence_post_ids' - 'post_link') <> '{}'::jsonb
         or v_analysis->>'schema_version' <> 'v3-x-post-analysis'
         or v_analysis->>'prompt_version' <> 'v3-x-post-analysis-1'
         or v_analysis->>'analysis_id' <> v_analysis->>'post_id' || '@2'
         or nullif(v_analysis->>'analysis_version', '')::integer <> 2
         or jsonb_typeof(v_analysis->'analysis_output') <> 'object'
         or v_analysis->'analysis_output'->>'post_id' <> v_analysis->>'post_id'
         or jsonb_typeof(v_analysis->'arguments') <> 'array' or jsonb_typeof(v_analysis->'uncertainties') <> 'array'
         or jsonb_typeof(v_analysis->'evidence_post_ids') <> 'array' or jsonb_array_length(v_analysis->'evidence_post_ids') = 0 then
        raise exception 'invalid_x_v3_verification_analysis' using errcode = '22023';
      end if;
      v_post_id := v_analysis->>'post_id';
      select post->>'post_url', array_remove(array[post->>'post_id', post->>'quoted_post_id', post->>'reply_to_post_id', post->>'reposted_post_id'], null)
        into v_post_link, v_allowed_evidence from jsonb_array_elements(v_snapshot.posts) post where post->>'post_id' = v_post_id;
      if v_post_link is null or v_post_link <> v_analysis->>'post_link'
         or exists (select 1 from jsonb_array_elements_text(v_analysis->'evidence_post_ids') evidence where evidence <> all(v_allowed_evidence))
         or (select count(*) from jsonb_array_elements_text(v_analysis->'evidence_post_ids')) <> (select count(distinct evidence) from jsonb_array_elements_text(v_analysis->'evidence_post_ids') evidence) then
        raise exception 'invalid_x_v3_verification_evidence' using errcode = '22023';
      end if;
      select message.id into v_canonical_id from public.canonical_messages message
      where message.source_id = v_source_id and message.external_message_id = v_post_id;
      if v_canonical_id is null then raise exception 'invalid_x_v3_verification_analysis' using errcode = '22023'; end if;
      if exists (select 1 from public.x_post_analyses existing where existing.canonical_message_id = v_canonical_id and existing.analysis_version = 2
        and (existing.analysis_output, existing.evidence_refs) is distinct from (v_analysis->'analysis_output', v_analysis->'evidence_post_ids')) then
        raise exception 'conflicting_x_post_analysis' using errcode = '23505';
      end if;
    end loop;
    v_segment := v_source->'segment';
    select coalesce(array_agg(item->>'analysis_id' order by item->>'analysis_id'), '{}') into v_analysis_ids from jsonb_array_elements(v_source->'analyses') item;
    if (v_segment - 'occurred_from_at' - 'occurred_through_at' - 'schema_version' - 'prompt_version' - 'segment_output' - 'analysis_ids' - 'evidence_post_ids' - 'uncertainties') <> '{}'::jsonb
       or v_segment->>'schema_version' <> 'v3-x-window' or v_segment->>'prompt_version' <> 'v3-x-window-1'
       or jsonb_typeof(v_segment->'segment_output') <> 'object' or v_segment->'segment_output'->>'schema_version' <> 'v3-x-window'
       or jsonb_typeof(v_segment->'analysis_ids') <> 'array' or jsonb_typeof(v_segment->'evidence_post_ids') <> 'array' or jsonb_typeof(v_segment->'uncertainties') <> 'array'
       or (v_segment->>'occurred_from_at')::timestamptz <> v_snapshot.occurred_from_at or (v_segment->>'occurred_through_at')::timestamptz <> v_snapshot.occurred_through_at
       or (select array_agg(value order by value) from jsonb_array_elements_text(v_segment->'analysis_ids') value) is distinct from v_analysis_ids then
      raise exception 'invalid_x_v3_verification_segment' using errcode = '22023';
    end if;
  end loop;

  for v_item in select value from jsonb_array_elements(v_daily_output->'security_industry_viewpoints' || v_daily_output->'market_structure_viewpoints' || v_daily_output->'strategy_mindset_viewpoints') loop
    select coalesce(array_agg(value order by value), '{}') into v_item_analysis_ids from jsonb_array_elements_text(v_item->'analysis_ids') value;
    select coalesce(array_agg(value order by value), '{}') into v_item_evidence_ids from jsonb_array_elements_text(v_item->'evidence_post_ids') value;
    select coalesce(array_agg(value order by value), '{}') into v_item_source_ids from jsonb_array_elements_text(v_item->'supporting_source_ids' || v_item->'dissenting_source_ids') value;
    if cardinality(v_item_analysis_ids) <> cardinality(array(select distinct unnest(v_item_analysis_ids)))
       or cardinality(v_item_evidence_ids) <> cardinality(array(select distinct unnest(v_item_evidence_ids)))
       or cardinality(v_item_source_ids) <> cardinality(array(select distinct unnest(v_item_source_ids)))
       or exists (select 1 from unnest(v_item_source_ids) source_text where not exists (select 1 from public.x_v3_verification_replay_sources source where source.replay_id = v_replay.id and source.source_id::text = source_text))
       or exists (select 1 from unnest(v_item_analysis_ids) analysis_id where not exists (select 1 from jsonb_array_elements(p_payload->'sources') source_row cross join jsonb_array_elements(source_row->'analyses') analysis_row where analysis_row->>'analysis_id' = analysis_id and source_row->>'source_id' = any(v_item_source_ids))) then
      raise exception 'invalid_x_v3_verification_daily_authority' using errcode = '22023';
    end if;
    select coalesce(array_agg(distinct evidence order by evidence), '{}') into v_expected_evidence_ids
    from jsonb_array_elements(p_payload->'sources') source_row
    cross join jsonb_array_elements(source_row->'analyses') analysis_row
    cross join jsonb_array_elements_text(analysis_row->'evidence_post_ids') evidence
    where analysis_row->>'analysis_id' = any(v_item_analysis_ids);
    if v_item_evidence_ids is distinct from v_expected_evidence_ids then
      raise exception 'invalid_x_v3_verification_daily_authority' using errcode = '22023';
    end if;
  end loop;

  for v_source in select value from jsonb_array_elements(p_payload->'sources') loop
    v_source_id := (v_source->>'source_id')::uuid;
    for v_analysis in select value from jsonb_array_elements(v_source->'analyses') loop
      select message.id into v_canonical_id from public.canonical_messages message where message.source_id = v_source_id and message.external_message_id = v_analysis->>'post_id';
      insert into public.x_post_analyses (canonical_message_id, analysis_version, schema_version, prompt_version, analysis_output, blogger_viewpoint, arguments, quoted_post_viewpoint, uncertainties, evidence_refs)
      values (v_canonical_id, 2, 'v3-x-post-analysis', 'v3-x-post-analysis-1', v_analysis->'analysis_output', v_analysis->'blogger_viewpoint', v_analysis->'arguments', v_analysis->'quoted_post_viewpoint', v_analysis->'uncertainties', v_analysis->'evidence_post_ids')
      on conflict (canonical_message_id, analysis_version) do nothing;
    end loop;
    v_segment := v_source->'segment';
    insert into public.x_v3_verification_segments (replay_id, source_id, occurred_from_at, occurred_through_at, schema_version, prompt_version, segment_output, post_analysis_refs, evidence_refs)
    values (v_replay.id, v_source_id, (v_segment->>'occurred_from_at')::timestamptz, (v_segment->>'occurred_through_at')::timestamptz, 'v3-x-window', 'v3-x-window-1', v_segment->'segment_output', v_segment->'analysis_ids', v_segment->'evidence_post_ids');
  end loop;
  v_input_snapshot := public.get_x_v3_verification_replay_context(v_replay.id, p_attempt, p_worker_id);
  insert into public.x_v3_verification_versions (replay_id, input_snapshot, output, provider, model_reported, prompt_version, schema_version)
  values (v_replay.id, v_input_snapshot, v_daily_output, 'codex_cli', nullif(p_payload->>'model_reported', ''), 'v3-x-cross-blogger-1', 'v3-x-cross-blogger');
  update public.x_v3_verification_replays set status = 'succeeded', lease_owner = null, lease_expires_at = null, completed_at = timezone('utc', now()) where id = v_replay.id;
  return jsonb_build_object('status', 'succeeded', 'replay_id', v_replay.id::text, 'attempt', v_replay.attempt);
end;
$$;
