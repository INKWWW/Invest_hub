-- Final authority for X daily judgements.  This migration adds only gates
-- around the existing immutable batch/version state machine: it never rewrites
-- source tasks, collection coverage, checkpoints, or prior judgement versions.

create function public.x_daily_judgement_worker_is_eligible(p_worker_id uuid, p_now timestamptz)
returns boolean
language sql
stable
set search_path = public
as $$
  select p_now is not null
    and exists (
      select 1
      from public.workers worker
      where worker.id = p_worker_id
        and worker.status = 'online'
        and worker.last_heartbeat_at >= p_now - interval '2 minutes'
        and worker.last_heartbeat_at <= p_now + interval '2 minutes'
        and worker.capabilities @> array['x_sync']::text[]
    )
    and exists (
      select 1
      from public.sources source
      join public.x_source_profiles profile on profile.source_id = source.id
      where source.authorized_worker_id = p_worker_id
        and source.source_type = 'x'
        and source.enabled
        and profile.enabled
        and profile.resolution_status = 'resolved'
    )
$$;

create function public.x_daily_judgement_batch_has_provider_input(p_batch_id uuid)
returns boolean
language sql
stable
set search_path = public
as $$
  select exists (
    select 1
    from public.x_collection_batch_sources batch_source
    where batch_source.batch_id = p_batch_id
      and batch_source.settlement_status = 'included'
  ) and coalesce((
    select version.coverage_status <> 'no_new_information'
    from public.x_daily_judgement_versions version
    where version.batch_id = p_batch_id
    order by version.revision desc
    limit 1
  ), true)
$$;

-- The only pre-existing poison work this migration may terminalize is an
-- explicit regeneration whose authoritative latest version is already no-new.
-- Preserve the state machine and add one narrow queued/retryable transition.
create or replace function public.enforce_x_daily_judgement_run_transition()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.id is distinct from old.id
     or new.batch_id is distinct from old.batch_id
     or new.run_kind is distinct from old.run_kind
     or new.requested_by is distinct from old.requested_by
     or new.created_at is distinct from old.created_at then
    raise exception 'x_daily_judgement_run_immutable' using errcode = '55000';
  end if;
  if old.status in ('succeeded', 'failed') then
    raise exception 'x_daily_judgement_run_terminal' using errcode = '55000';
  end if;
  if new.attempt < old.attempt or new.attempt > old.attempt + 1
     or (new.attempt = old.attempt + 1 and new.status <> 'leased')
     or (new.status <> 'leased' and new.attempt <> old.attempt) then
    raise exception 'invalid_x_daily_judgement_attempt_transition' using errcode = '55000';
  end if;
  if new.status is distinct from old.status and not (
    (old.status in ('queued', 'retryable_failed') and new.status = 'leased')
    or (old.status = 'retryable_failed' and old.attempt >= 3 and new.status = 'failed')
    or (old.status in ('leased', 'running') and new.status in ('running', 'retryable_failed', 'failed', 'succeeded'))
    or (
      old.run_kind = 'regeneration'
      and old.status in ('queued', 'retryable_failed')
      and new.status = 'failed'
      and new.failure_class = 'schema_error'
      and (
        select version.coverage_status
        from public.x_daily_judgement_versions version
        where version.batch_id = old.batch_id
        order by version.revision desc
        limit 1
      ) = 'no_new_information'
    )
  ) then
    raise exception 'invalid_x_daily_judgement_run_transition' using errcode = '55000';
  end if;
  return new;
end;
$$;

create function public.terminalize_legacy_no_new_x_daily_judgement_runs()
returns integer
language plpgsql
set search_path = public
as $$
declare
  v_count integer;
begin
  update public.x_daily_judgement_runs run
  set status = 'failed',
      failure_class = 'schema_error',
      lease_owner = null,
      lease_expires_at = null
  where run.run_kind = 'regeneration'
    and run.status in ('queued', 'leased', 'running', 'retryable_failed')
    and (
      select version.coverage_status
      from public.x_daily_judgement_versions version
      where version.batch_id = run.batch_id
      order by version.revision desc
      limit 1
    ) = 'no_new_information';
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Deployment cleanup is idempotent and mutates only unsafe active run rows.
select public.terminalize_legacy_no_new_x_daily_judgement_runs();

-- Keep the approved dispatcher unchanged behind a stricter authority gate.
alter function public.ensure_due_x_collection_batches_core(uuid, timestamptz)
  rename to ensure_due_x_collection_batches_dispatch_core;

create function public.ensure_due_x_collection_batches_core(p_worker_id uuid, p_now timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public.x_daily_judgement_worker_is_eligible(p_worker_id, p_now) then
    raise exception 'worker_not_authorized' using errcode = '42501';
  end if;
  return public.ensure_due_x_collection_batches_dispatch_core(p_worker_id, p_now);
end;
$$;

-- Claim remains atomic in the existing core, but no enrolled or stale Worker
-- may reach lease expiry recovery or mutate a queued run.
alter function public.claim_next_x_daily_judgement(uuid, timestamptz)
  rename to claim_next_x_daily_judgement_state_core;

create function public.claim_next_x_daily_judgement(p_worker_id uuid, p_now timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public.x_daily_judgement_worker_is_eligible(p_worker_id, p_now) then
    raise exception 'worker_not_authorized' using errcode = '42501';
  end if;
  perform public.terminalize_legacy_no_new_x_daily_judgement_runs();
  return public.claim_next_x_daily_judgement_state_core(p_worker_id, p_now);
end;
$$;

-- HTTP and Worker validators need the same batch identity that the database
-- validator already derives from the run.  The lease checks stay in the core.
alter function public.get_x_daily_judgement_context(uuid, integer, uuid)
  rename to get_x_daily_judgement_context_lease_core;

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
  v_batch_id uuid;
begin
  v_context := public.get_x_daily_judgement_context_lease_core(p_run_id, p_attempt, p_worker_id);
  select run.batch_id into strict v_batch_id
  from public.x_daily_judgement_runs run
  where run.id = p_run_id;
  if not public.x_daily_judgement_batch_has_provider_input(v_batch_id) then
    raise exception 'x_daily_judgement_no_provider_input' using errcode = '22023';
  end if;
  return v_context || jsonb_build_object('batch_id', v_batch_id::text);
end;
$$;

-- A database-authored no-new version is already the complete judgement for
-- that frozen input.  Regeneration cannot turn it into Provider work or a
-- complete/partial revision.
create or replace function public.regenerate_x_daily_judgement(p_batch_id uuid, p_requested_by uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_batch public.x_collection_batches%rowtype;
  v_run public.x_daily_judgement_runs%rowtype;
  v_latest_coverage_status text;
begin
  if p_requested_by is null or not exists (
    select 1 from public.profiles where id = p_requested_by
  ) then
    raise exception 'invalid_x_daily_judgement_regeneration_actor' using errcode = '22023';
  end if;

  if not exists (
    select 1 from public.profiles where id = p_requested_by and role = 'admin'
  ) then
    raise exception 'actor_not_authorized' using errcode = '42501';
  end if;

  select * into v_batch
  from public.x_collection_batches
  where id = p_batch_id
  for update;

  if not found or v_batch.status <> 'succeeded' then
    raise exception 'x_daily_judgement_regeneration_not_available' using errcode = '22023';
  end if;

  select version.coverage_status into v_latest_coverage_status
  from public.x_daily_judgement_versions version
  where version.batch_id = v_batch.id
  order by version.revision desc
  limit 1;
  if not found then
    raise exception 'x_daily_judgement_regeneration_requires_successful_version' using errcode = '22023';
  end if;
  if v_latest_coverage_status = 'no_new_information' then
    raise exception 'x_daily_judgement_regeneration_no_new_information' using errcode = '22023';
  end if;
  if not public.x_daily_judgement_batch_has_provider_input(v_batch.id) then
    raise exception 'x_daily_judgement_no_provider_input' using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.x_daily_judgement_runs
    where batch_id = v_batch.id
      and status in ('queued', 'leased', 'running', 'retryable_failed')
  ) then
    raise exception 'x_daily_judgement_regeneration_active' using errcode = 'PT409';
  end if;

  insert into public.x_daily_judgement_runs (batch_id, status, attempt, run_kind, requested_by)
  values (v_batch.id, 'queued', 0, 'regeneration', p_requested_by)
  returning * into v_run;

  return jsonb_build_object('run_id', v_run.id::text, 'status', v_run.status, 'attempt', v_run.attempt);
end;
$$;

-- Keep the existing completion OID/RPC grant and add the final no-input gate
-- before payload validation or any version/run/batch write.
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
  if not public.x_daily_judgement_batch_has_provider_input(v_run.batch_id) then
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
  update public.x_daily_judgement_runs
  set status = 'succeeded', lease_owner = null, lease_expires_at = null
  where id = v_run.id;
  update public.x_collection_batches set status = 'succeeded' where id = v_run.batch_id;
  return jsonb_build_object('run_id', v_run.id::text, 'attempt', v_run.attempt, 'status', 'succeeded');
end;
$$;

-- Preserve the complete source/analysis/evidence authority and add the three
-- remaining context identities plus deterministic consensus semantics.
alter function public.validate_x_daily_judgement_output_authority(uuid, jsonb)
  rename to validate_x_daily_judgement_output_evidence_core;

create function public.validate_x_daily_judgement_output_authority(p_batch_id uuid, p_output jsonb)
returns void
language plpgsql
set search_path = public
as $$
declare
  v_item jsonb;
  v_text text;
  v_opaque_ids text[];
begin
  perform public.validate_x_daily_judgement_output_evidence_core(p_batch_id, p_output);

  select coalesce(array_agg(distinct token order by token), '{}'::text[])
  into v_opaque_ids
  from (
    select p_batch_id::text as token
    union all
    select run.id::text
    from public.x_daily_judgement_runs run
    where run.batch_id = p_batch_id
    union all
    select batch_source.source_id::text
    from public.x_collection_batch_sources batch_source
    where batch_source.batch_id = p_batch_id
    union all
    select segment.id::text
    from public.x_collection_batches batch
    join public.x_collection_batch_sources batch_source on batch_source.batch_id = batch.id
    join public.x_daily_viewpoint_segments segment
      on segment.source_id = batch_source.source_id
     and segment.range_task_id = batch_source.x_sync_task_id
     and segment.natural_date = batch.natural_date
    where batch.id = p_batch_id
      and batch_source.settlement_status = 'included'
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
      and batch_source.settlement_status = 'included'
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
      and batch_source.settlement_status = 'included'
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
      and batch_source.settlement_status = 'included'
  ) opaque_tokens;

  for v_text in
    select value from jsonb_array_elements_text(p_output->'uncertainties')
    union all
    select item->>'statement'
    from jsonb_array_elements(p_output->'stock_viewpoints') item
    union all
    select item->>'statement'
    from jsonb_array_elements(p_output->'market_industry_viewpoints') item
    union all
    select uncertainty.value
    from jsonb_array_elements(p_output->'stock_viewpoints') item
    cross join lateral jsonb_array_elements_text(item->'uncertainties') uncertainty(value)
    union all
    select uncertainty.value
    from jsonb_array_elements(p_output->'market_industry_viewpoints') item
    cross join lateral jsonb_array_elements_text(item->'uncertainties') uncertainty(value)
  loop
    if exists (
      select 1 from unnest(v_opaque_ids) opaque_id where position(lower(opaque_id) in lower(v_text)) > 0
    ) then
      raise exception 'invalid_x_daily_judgement_evidence' using errcode = '22023';
    end if;
  end loop;

  for v_item in
    select value from jsonb_array_elements(p_output->'stock_viewpoints')
    union all
    select value from jsonb_array_elements(p_output->'market_industry_viewpoints')
  loop
    if (v_item->>'statement') ~ '(共识|一致认为|共同认为|市场(已经|已)?确认)'
       and (
         jsonb_array_length(v_item->'supporting_source_ids') < 2
         or jsonb_array_length(v_item->'dissenting_source_ids') > 0
       ) then
      raise exception 'invalid_x_daily_judgement_evidence' using errcode = '22023';
    end if;
  end loop;
end;
$$;

revoke all on function public.x_daily_judgement_worker_is_eligible(uuid, timestamptz)
  from public, anon, authenticated, service_role;
revoke all on function public.x_daily_judgement_batch_has_provider_input(uuid),
  public.terminalize_legacy_no_new_x_daily_judgement_runs()
  from public, anon, authenticated, service_role;
revoke all on function public.ensure_due_x_collection_batches_dispatch_core(uuid, timestamptz),
  public.ensure_due_x_collection_batches_core(uuid, timestamptz)
  from public, anon, authenticated, service_role;
revoke all on function public.claim_next_x_daily_judgement_state_core(uuid, timestamptz)
  from public, anon, authenticated, service_role;
revoke all on function public.claim_next_x_daily_judgement(uuid, timestamptz)
  from public, anon, authenticated;
grant execute on function public.claim_next_x_daily_judgement(uuid, timestamptz)
  to service_role;
revoke all on function public.get_x_daily_judgement_context_lease_core(uuid, integer, uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.get_x_daily_judgement_context(uuid, integer, uuid)
  from public, anon, authenticated;
grant execute on function public.get_x_daily_judgement_context(uuid, integer, uuid)
  to service_role;
revoke all on function public.regenerate_x_daily_judgement(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.regenerate_x_daily_judgement(uuid, uuid)
  to service_role;
revoke all on function public.complete_x_daily_judgement(uuid, integer, uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.complete_x_daily_judgement(uuid, integer, uuid, jsonb)
  to service_role;
revoke all on function public.validate_x_daily_judgement_output_evidence_core(uuid, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.validate_x_daily_judgement_output_authority(uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.validate_x_daily_judgement_output_authority(uuid, jsonb)
  to service_role;
