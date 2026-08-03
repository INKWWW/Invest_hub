-- Preserve v2 records while making every new provider completion use the v3
-- investment-judgement contract.

create or replace function public.validate_x_daily_judgement_output_v3(p_output jsonb)
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
    raise exception 'invalid_v3_x_daily_judgement_output' using errcode = '22023';
  end if;

  for v_item in
    select value from jsonb_array_elements(p_output->'security_industry_viewpoints')
    union all select value from jsonb_array_elements(p_output->'market_structure_viewpoints')
    union all select value from jsonb_array_elements(p_output->'strategy_mindset_viewpoints')
  loop
    if jsonb_typeof(v_item) <> 'object'
       or not (v_item ?& array['statement', 'action_intent', 'action_scope', 'conditions', 'supporting_source_ids', 'dissenting_source_ids', 'analysis_ids', 'evidence_post_ids', 'uncertainties'])
       or (v_item - 'statement' - 'action_intent' - 'action_scope' - 'conditions' - 'supporting_source_ids' - 'dissenting_source_ids' - 'analysis_ids' - 'evidence_post_ids' - 'uncertainties') <> '{}'::jsonb
       or jsonb_typeof(v_item->'statement') <> 'string' or not public.x_daily_judgement_safe_text(v_item->>'statement', 1000)
       or jsonb_typeof(v_item->'action_intent') <> 'string' or v_item->>'action_intent' not in ('build_position', 'buy', 'add', 'hold', 'reduce', 'sell', 'watch', 'avoid', 'none')
       or jsonb_typeof(v_item->'action_scope') <> 'string'
       or (v_item->>'action_intent' = 'none' and v_item->>'action_scope' <> '')
       or (v_item->>'action_intent' <> 'none' and not public.x_daily_judgement_safe_text(v_item->>'action_scope', 300))
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
      raise exception 'invalid_v3_x_daily_judgement_output' using errcode = '22023';
    end if;
  end loop;
end;
$$;

create or replace function public.validate_x_daily_judgement_output_authority_v3(p_batch_id uuid, p_output jsonb)
returns void
language plpgsql
set search_path = public
as $$
declare
  v_legacy_output jsonb;
begin
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
  if new.schema_version <> 'v3-x-cross-blogger' then
    perform public.validate_x_daily_judgement_output(new.output);
  end if;
  v_expected_snapshot := public.build_x_daily_judgement_input_snapshot(new.batch_id);
  if new.input_snapshot <> v_expected_snapshot then
    raise exception 'invalid_x_daily_judgement_snapshot' using errcode = '22023';
  end if;
  if new.schema_version = 'v3-x-cross-blogger' then
    perform public.validate_x_daily_judgement_output_authority_v3(new.batch_id, new.output);
  else
    perform public.validate_x_daily_judgement_output_authority(new.batch_id, new.output);
  end if;
  return new;
end;
$$;

alter function public.get_x_daily_judgement_context(uuid, integer, uuid)
  rename to get_x_daily_judgement_context_v2;

create function public.get_x_daily_judgement_context(
  p_run_id uuid, p_attempt integer, p_worker_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_context jsonb;
begin
  v_context := public.get_x_daily_judgement_context_v2(p_run_id, p_attempt, p_worker_id);
  return jsonb_set(v_context, '{prompt_version}', '"v3-x-cross-blogger-1"'::jsonb);
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
       (p_payload->>'schema_version' = 'v3-x-cross-blogger' and p_payload->>'prompt_version' = 'v3-x-cross-blogger-1'
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

revoke all on function public.validate_x_daily_judgement_output_v3(jsonb), public.validate_x_daily_judgement_output_authority_v3(uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.validate_x_daily_judgement_output_v3(jsonb), public.validate_x_daily_judgement_output_authority_v3(uuid, jsonb)
  to service_role;
revoke all on function public.get_x_daily_judgement_context_v2(uuid, integer, uuid) from public, anon, authenticated, service_role;
revoke all on function public.get_x_daily_judgement_context(uuid, integer, uuid) from public, anon, authenticated;
grant execute on function public.get_x_daily_judgement_context(uuid, integer, uuid) to service_role;
