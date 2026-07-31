-- Completion is the final authority for a judgement lease.  HTTP preflight is
-- advisory only: this lock-held check prevents an expired Worker from writing
-- an immutable version after a race.  model_reported is safe metadata, never
-- a raw provider response or local evidence locator.

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
  if p_payload is null or jsonb_typeof(p_payload) <> 'object'
     or p_payload->>'schema_version' <> 'v2-x-cross-blogger'
     or p_payload->>'provider' not in ('codex_cli', 'mock')
     or p_payload->>'prompt_version' <> 'v2-x-cross-blogger-1'
     or not (p_payload ? 'model_reported')
     or (p_payload->'model_reported' <> 'null'::jsonb and (
       jsonb_typeof(p_payload->'model_reported') <> 'string'
       or not public.x_daily_judgement_safe_text(p_payload->>'model_reported', 160)
     ))
     or jsonb_typeof(p_payload->'stock_viewpoints') <> 'array'
     or jsonb_typeof(p_payload->'market_industry_viewpoints') <> 'array'
     or jsonb_typeof(p_payload->'uncertainties') <> 'array' then
    raise exception 'invalid_x_daily_judgement_completion' using errcode = '22023';
  end if;
  select case when count(*) filter (where settlement_status = 'excluded') > 0 then 'partial' else 'complete' end
    into v_coverage_status
  from public.x_collection_batch_sources where batch_id = v_run.batch_id;
  select jsonb_build_object('sources', coalesce(jsonb_agg(jsonb_build_object(
    'source_id', batch_source.source_id::text, 'display_name', batch_source.source_display_name,
    'settlement_status', batch_source.settlement_status,
    'segments', coalesce((select jsonb_agg(jsonb_build_object(
      'segment_id', segment.id::text,
      'analysis_ids', segment.post_analysis_refs,
      'evidence_post_ids', segment.evidence_refs
    ) order by segment.id) from public.x_daily_viewpoint_segments segment
      where segment.range_task_id = batch_source.x_sync_task_id), '[]'::jsonb)
  ) order by batch_source.source_id), '[]'::jsonb)) into v_snapshot
  from public.x_collection_batch_sources batch_source
  where batch_source.batch_id = v_run.batch_id and batch_source.settlement_status = 'included';
  v_output := p_payload - 'schema_version' - 'provider' - 'model_reported' - 'prompt_version';
  insert into public.x_daily_judgement_versions (
    batch_id, revision, coverage_status, input_snapshot, output, provider, model_reported, prompt_version, schema_version
  ) values (
    v_run.batch_id,
    (select coalesce(max(revision), 0) + 1 from public.x_daily_judgement_versions where batch_id = v_run.batch_id),
    v_coverage_status, v_snapshot, v_output, p_payload->>'provider', nullif(p_payload->>'model_reported', ''),
    p_payload->>'prompt_version', p_payload->>'schema_version'
  );
  update public.x_daily_judgement_runs
  set status = 'succeeded', lease_owner = null, lease_expires_at = null
  where id = v_run.id;
  update public.x_collection_batches set status = 'succeeded' where id = v_run.batch_id;
  return jsonb_build_object('run_id', v_run.id::text, 'attempt', v_run.attempt, 'status', 'succeeded');
end;
$$;

revoke all on function public.complete_x_daily_judgement(uuid, integer, uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.complete_x_daily_judgement(uuid, integer, uuid, jsonb)
  to service_role;
