-- X daily judgement lifecycle and evidence authority.  This migration is
-- additive: frozen collection inputs and immutable versions are never
-- rewritten.  Client roles lose direct DML and every remaining service-role
-- transition is constrained by table state plus the lease-owning RPCs.

drop policy if exists x_collection_batches_admin_all on public.x_collection_batches;
drop policy if exists x_collection_batch_sources_admin_all on public.x_collection_batch_sources;
drop policy if exists x_daily_judgement_runs_admin_all on public.x_daily_judgement_runs;
drop policy if exists x_daily_judgement_versions_admin_all on public.x_daily_judgement_versions;

create policy x_collection_batches_admin_select on public.x_collection_batches
for select to authenticated using (public.is_admin());
create policy x_collection_batch_sources_admin_select on public.x_collection_batch_sources
for select to authenticated using (public.is_admin());
create policy x_daily_judgement_runs_admin_select on public.x_daily_judgement_runs
for select to authenticated using (public.is_admin());
create policy x_daily_judgement_versions_admin_select on public.x_daily_judgement_versions
for select to authenticated using (public.is_admin());

revoke insert, update, delete on public.x_collection_batches, public.x_collection_batch_sources,
  public.x_daily_judgement_runs, public.x_daily_judgement_versions from authenticated;

create or replace function public.reject_x_collection_batch_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.scheduled_window_key is distinct from old.scheduled_window_key
     or new.natural_date is distinct from old.natural_date
     or new.cutoff_at is distinct from old.cutoff_at
     or new.settlement_deadline_at is distinct from old.settlement_deadline_at
     or new.created_at is distinct from old.created_at
     or new.snapshot_completeness is distinct from old.snapshot_completeness then
    raise exception 'x_collection_batch_immutable' using errcode = '55000';
  end if;
  if new.status is distinct from old.status and not (
    (old.status = 'collecting' and new.status in ('judgement_pending', 'judgement_failed', 'succeeded'))
    or (old.status = 'judgement_pending' and new.status in ('judgement_failed', 'succeeded'))
    or (old.status = 'succeeded' and old.snapshot_completeness = 'legacy_unverified'
        and new.status = 'judgement_failed')
  ) then
    raise exception 'invalid_x_collection_batch_transition' using errcode = '55000';
  end if;
  return new;
end;
$$;

create or replace function public.enforce_x_collection_batch_source()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_task public.sync_tasks%rowtype;
begin
  if tg_op = 'UPDATE' then
    if new.batch_id is distinct from old.batch_id
       or new.source_id is distinct from old.source_id
       or new.source_display_name is distinct from old.source_display_name then
      raise exception 'x_collection_snapshot_immutable' using errcode = '55000';
    end if;
    if old.settlement_status <> 'pending' then
      raise exception 'x_collection_snapshot_terminal' using errcode = '55000';
    end if;
    if new.x_sync_task_id is distinct from old.x_sync_task_id
       and not (old.x_sync_task_id is null and new.x_sync_task_id is not null
                and old.settlement_status = 'pending' and new.settlement_status = 'pending') then
      raise exception 'x_collection_snapshot_immutable' using errcode = '55000';
    end if;
  else
    if not exists (
      select 1
      from public.sources source
      join public.x_source_profiles profile on profile.source_id = source.id
      where source.id = new.source_id and source.source_type = 'x' and source.enabled
        and profile.enabled and profile.resolution_status = 'resolved'
    ) then
      raise exception 'invalid_x_collection_batch_source' using errcode = '23514';
    end if;
  end if;

  if new.x_sync_task_id is not null then
    select * into v_task from public.sync_tasks where id = new.x_sync_task_id;
    if not found or v_task.source_id <> new.source_id or v_task.task_type <> 'x_sync'
       or v_task.collection_batch_id <> new.batch_id then
      raise exception 'x_collection_batch_task_source_mismatch' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

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
  ) then
    raise exception 'invalid_x_daily_judgement_run_transition' using errcode = '55000';
  end if;
  return new;
end;
$$;

create trigger x_daily_judgement_runs_state_contract
before update on public.x_daily_judgement_runs
for each row execute function public.enforce_x_daily_judgement_run_transition();

with terminalized as (
  update public.x_daily_judgement_runs
  set status = 'failed',
      failure_class = coalesce(failure_class, 'lease_expired')
  where status = 'retryable_failed' and attempt >= 3
  returning batch_id, run_kind
)
update public.x_collection_batches batch
set status = 'judgement_failed'
from terminalized
where batch.id = terminalized.batch_id
  and terminalized.run_kind = 'initial'
  and batch.status = 'judgement_pending'
  and not exists (
    select 1 from public.x_daily_judgement_versions version where version.batch_id = batch.id
  );

create function public.reject_x_daily_judgement_lifecycle_delete()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception 'x_daily_judgement_lifecycle_append_only' using errcode = '55000';
end;
$$;

create trigger x_collection_batches_append_only
before delete on public.x_collection_batches
for each row execute function public.reject_x_daily_judgement_lifecycle_delete();
create trigger x_collection_batch_sources_append_only
before delete on public.x_collection_batch_sources
for each row execute function public.reject_x_daily_judgement_lifecycle_delete();
create trigger x_daily_judgement_runs_append_only
before delete on public.x_daily_judgement_runs
for each row execute function public.reject_x_daily_judgement_lifecycle_delete();

alter function public.settle_x_collection_batch(uuid, timestamptz)
  rename to settle_x_collection_batch_state_core;

create function public.settle_x_collection_batch(p_batch_id uuid, p_now timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_batch public.x_collection_batches%rowtype;
  v_coverage_status text;
begin
  if p_now is null then
    raise exception 'invalid_x_collection_batch_settlement' using errcode = '22023';
  end if;
  select * into v_batch
  from public.x_collection_batches
  where id = p_batch_id
  for update;
  if not found then
    raise exception 'x_collection_batch_not_found' using errcode = '22023';
  end if;
  if v_batch.snapshot_completeness <> 'complete' then
    return public.settle_x_collection_batch_state_core(p_batch_id, p_now);
  end if;
  if v_batch.status <> 'collecting' then
    select coverage_status into v_coverage_status
    from public.x_daily_judgement_versions
    where batch_id = p_batch_id
    order by revision desc
    limit 1;
    return jsonb_build_object(
      'batch_id', p_batch_id::text,
      'settled', v_batch.status in ('judgement_pending', 'succeeded'),
      'coverage_status', v_coverage_status,
      'already_settled', true,
      'status', v_batch.status
    );
  end if;
  return public.settle_x_collection_batch_state_core(p_batch_id, p_now);
end;
$$;

revoke all on function public.settle_x_collection_batch_state_core(uuid, timestamptz)
  from public, anon, authenticated, service_role;
revoke all on function public.settle_x_collection_batch(uuid, timestamptz)
  from public, anon, authenticated;
grant execute on function public.settle_x_collection_batch(uuid, timestamptz)
  to service_role;

create or replace function public.claim_next_x_daily_judgement(p_worker_id uuid, p_now timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_run public.x_daily_judgement_runs%rowtype;
  v_coverage_status text;
begin
  if p_now is null or not exists (
    select 1
    from public.workers worker
    where worker.id = p_worker_id
      and worker.status in ('enrolled', 'online')
      and worker.capabilities @> array['x_sync']::text[]
  ) or not exists (
    select 1
    from public.sources source
    where source.source_type = 'x' and source.authorized_worker_id = p_worker_id
  ) then
    raise exception 'worker_not_authorized' using errcode = '42501';
  end if;

  with expired as (
    update public.x_daily_judgement_runs
    set status = case when attempt >= 3 then 'failed' else 'retryable_failed' end,
        lease_owner = null,
        lease_expires_at = null,
        available_at = p_now,
        failure_class = coalesce(failure_class, 'lease_expired')
    where (status in ('leased', 'running') and lease_expires_at <= p_now)
       or (status = 'retryable_failed' and attempt >= 3)
    returning batch_id, run_kind, status
  )
  update public.x_collection_batches batch
  set status = 'judgement_failed'
  from expired
  where batch.id = expired.batch_id
    and expired.status = 'failed'
    and expired.run_kind = 'initial'
    and batch.status = 'judgement_pending'
    and not exists (
      select 1 from public.x_daily_judgement_versions version where version.batch_id = batch.id
    );

  select run.* into v_run
  from public.x_daily_judgement_runs run
  join public.x_collection_batches batch on batch.id = run.batch_id
  where run.status in ('queued', 'retryable_failed')
    and run.attempt < 3
    and run.available_at <= p_now
    and batch.snapshot_completeness = 'complete'
    and exists (
      select 1
      from public.x_collection_batch_sources batch_source
      join public.sources source on source.id = batch_source.source_id
      where batch_source.batch_id = run.batch_id
        and source.source_type = 'x'
        and source.authorized_worker_id = p_worker_id
    )
  order by run.available_at, run.created_at, run.id
  for update of run skip locked
  limit 1;
  if not found then return null; end if;

  update public.x_daily_judgement_runs
  set status = 'leased', attempt = v_run.attempt + 1, lease_owner = p_worker_id,
      lease_expires_at = p_now + interval '10 minutes', failure_class = null
  where id = v_run.id
  returning * into v_run;

  select case when count(*) filter (where settlement_status = 'excluded') > 0 then 'partial' else 'complete' end
  into v_coverage_status
  from public.x_collection_batch_sources where batch_id = v_run.batch_id;

  return jsonb_build_object(
    'run_id', v_run.id::text,
    'attempt', v_run.attempt,
    'lease_expires_at', v_run.lease_expires_at,
    'batch', (
      select jsonb_build_object(
        'id', batch.id::text,
        'natural_date', batch.natural_date,
        'cutoff_at', batch.cutoff_at,
        'coverage_status', v_coverage_status
      )
      from public.x_collection_batches batch where batch.id = v_run.batch_id
    )
  );
end;
$$;

create or replace function public.get_x_daily_judgement_context(
  p_run_id uuid, p_attempt integer, p_worker_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_run public.x_daily_judgement_runs%rowtype;
  v_batch public.x_collection_batches%rowtype;
  v_context jsonb;
begin
  select * into v_run from public.x_daily_judgement_runs where id = p_run_id;
  if not found or p_attempt is null or p_worker_id is null or v_run.attempt <> p_attempt
     or v_run.status not in ('leased', 'running') or v_run.lease_owner <> p_worker_id
     or v_run.lease_expires_at <= timezone('utc', now()) then
    raise exception 'lease_mismatch' using errcode = 'PT409';
  end if;
  select * into v_batch from public.x_collection_batches where id = v_run.batch_id;
  if not found or v_batch.snapshot_completeness <> 'complete' then
    raise exception 'x_collection_batch_snapshot_unavailable' using errcode = '55000';
  end if;

  select jsonb_build_object(
    'run_id', v_run.id::text,
    'attempt', v_run.attempt,
    'prompt_version', 'v2-x-cross-blogger-1',
    'sources', coalesce((
      select jsonb_agg(jsonb_build_object(
        'source_id', batch_source.source_id::text,
        'display_name', batch_source.source_display_name,
        'window_segments', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', segment.id::text,
            'occurred_from_at', segment.occurred_from_at,
            'occurred_through_at', segment.occurred_through_at,
            'viewpoints', segment.window_viewpoints,
            'uncertainties', '[]'::jsonb,
            'analyses', coalesce((
              select jsonb_agg(jsonb_build_object(
                'post_id', message.external_message_id || '@' || analysis.analysis_version::text,
                'blogger_viewpoint', analysis.blogger_viewpoint,
                'arguments', analysis.arguments,
                'quoted_post_viewpoint', analysis.quoted_post_viewpoint,
                'uncertainties', analysis.uncertainties,
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
      ) order by batch_source.source_id)
      from public.x_collection_batch_sources batch_source
      where batch_source.batch_id = v_run.batch_id and batch_source.settlement_status = 'included'
    ), '[]'::jsonb),
    'excluded_sources', coalesce((
      select jsonb_agg(jsonb_build_object(
        'source_id', batch_source.source_id::text,
        'display_name', batch_source.source_display_name,
        'reason', coalesce(batch_source.exclusion_code, batch_source.settlement_status)
      ) order by batch_source.source_id)
      from public.x_collection_batch_sources batch_source
      where batch_source.batch_id = v_run.batch_id
        and batch_source.settlement_status in ('excluded', 'no_new_information')
    ), '[]'::jsonb)
  ) into v_context;
  return v_context;
end;
$$;

create or replace function public.fail_x_daily_judgement(
  p_run_id uuid, p_attempt integer, p_worker_id uuid, p_failure_class text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_run public.x_daily_judgement_runs%rowtype;
  v_status text;
begin
  if p_failure_class not in ('timeout', 'provider_failure', 'empty_response', 'invalid_json', 'schema_error', 'persistence_failure') then
    raise exception 'invalid_x_daily_judgement_failure' using errcode = '22023';
  end if;
  select * into v_run from public.x_daily_judgement_runs where id = p_run_id for update;
  if not found or p_attempt is null or p_worker_id is null or v_run.attempt <> p_attempt
     or v_run.status not in ('leased', 'running') or v_run.lease_owner <> p_worker_id
     or v_run.lease_expires_at <= timezone('utc', now()) then
    raise exception 'lease_mismatch' using errcode = 'PT409';
  end if;

  v_status := case when v_run.attempt >= 3 then 'failed' else 'retryable_failed' end;
  update public.x_daily_judgement_runs
  set status = v_status,
      lease_owner = null,
      lease_expires_at = null,
      available_at = timezone('utc', now()),
      failure_class = p_failure_class
  where id = v_run.id;

  if v_status = 'failed' and v_run.run_kind = 'initial'
     and not exists (
       select 1 from public.x_daily_judgement_versions version where version.batch_id = v_run.batch_id
     ) then
    update public.x_collection_batches
    set status = 'judgement_failed'
    where id = v_run.batch_id and status = 'judgement_pending';
  end if;

  return jsonb_build_object('run_id', v_run.id::text, 'attempt', v_run.attempt, 'status', v_status, 'failure_class', p_failure_class);
end;
$$;

create function public.validate_x_daily_judgement_output_authority(p_batch_id uuid, p_output jsonb)
returns void
language plpgsql
set search_path = public
as $$
declare
  v_item jsonb;
  v_text text;
  v_supporting text[];
  v_dissenting text[];
  v_item_sources text[];
  v_analysis_ids text[];
  v_evidence_ids text[];
  v_expected_sources text[];
  v_expected_evidence text[];
  v_opaque_ids text[];
  v_matched_analysis_rows integer;
begin
  select coalesce(array_agg(distinct token order by token), '{}'::text[])
  into v_opaque_ids
  from (
    select batch_source.source_id::text as token
    from public.x_collection_batch_sources batch_source
    where batch_source.batch_id = p_batch_id
    union all
    select ref.post_id || '@' || ref.analysis_version::text
    from public.x_collection_batches batch
    join public.x_collection_batch_sources batch_source on batch_source.batch_id = batch.id
    join public.x_daily_viewpoint_segments segment
      on segment.source_id = batch_source.source_id
     and segment.range_task_id = batch_source.x_sync_task_id
     and segment.natural_date = batch.natural_date
    cross join lateral jsonb_to_recordset(segment.post_analysis_refs) as ref(post_id text, analysis_version integer)
    where batch.id = p_batch_id and batch_source.settlement_status = 'included'
    union all
    select evidence.value
    from public.x_collection_batches batch
    join public.x_collection_batch_sources batch_source on batch_source.batch_id = batch.id
    join public.x_daily_viewpoint_segments segment
      on segment.source_id = batch_source.source_id
     and segment.range_task_id = batch_source.x_sync_task_id
     and segment.natural_date = batch.natural_date
    cross join lateral jsonb_array_elements_text(segment.evidence_refs) evidence(value)
    where batch.id = p_batch_id and batch_source.settlement_status = 'included'
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
    where batch.id = p_batch_id and batch_source.settlement_status = 'included'
  ) tokens;

  if exists (
    select 1
    from public.x_collection_batches batch
    join public.x_collection_batch_sources batch_source on batch_source.batch_id = batch.id
    join public.x_daily_viewpoint_segments segment
      on segment.source_id = batch_source.source_id
     and segment.range_task_id = batch_source.x_sync_task_id
     and segment.natural_date = batch.natural_date
    where batch.id = p_batch_id
      and batch_source.settlement_status = 'included'
      and (
        jsonb_array_length(segment.post_analysis_refs) <> (
          select count(*)
          from jsonb_to_recordset(segment.post_analysis_refs) as ref(post_id text, analysis_version integer)
          join public.canonical_messages message
            on message.source_id = batch_source.source_id and message.external_message_id = ref.post_id
          join public.x_post_analyses analysis
            on analysis.canonical_message_id = message.id and analysis.analysis_version = ref.analysis_version
        )
        or array(
          select distinct evidence.value
          from jsonb_array_elements_text(segment.evidence_refs) evidence(value)
          order by evidence.value
        ) is distinct from array(
          select distinct evidence.value
          from jsonb_to_recordset(segment.post_analysis_refs) as ref(post_id text, analysis_version integer)
          join public.canonical_messages message
            on message.source_id = batch_source.source_id and message.external_message_id = ref.post_id
          join public.x_post_analyses analysis
            on analysis.canonical_message_id = message.id and analysis.analysis_version = ref.analysis_version
          cross join lateral jsonb_array_elements_text(analysis.evidence_refs) evidence(value)
          order by evidence.value
        )
      )
  ) then
    raise exception 'invalid_x_daily_judgement_evidence' using errcode = '22023';
  end if;

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
      select 1 from unnest(v_opaque_ids) opaque_id where position(opaque_id in v_text) > 0
    ) then
      raise exception 'invalid_x_daily_judgement_evidence' using errcode = '22023';
    end if;
  end loop;

  for v_item in
    select value from jsonb_array_elements(p_output->'stock_viewpoints')
    union all
    select value from jsonb_array_elements(p_output->'market_industry_viewpoints')
  loop
    select coalesce(array_agg(value), '{}'::text[]) into v_supporting
    from jsonb_array_elements_text(v_item->'supporting_source_ids') source(value);
    select coalesce(array_agg(value), '{}'::text[]) into v_dissenting
    from jsonb_array_elements_text(v_item->'dissenting_source_ids') source(value);
    select coalesce(array_agg(value), '{}'::text[]) into v_analysis_ids
    from jsonb_array_elements_text(v_item->'analysis_ids') analysis(value);
    select coalesce(array_agg(value), '{}'::text[]) into v_evidence_ids
    from jsonb_array_elements_text(v_item->'evidence_post_ids') evidence(value);

    if cardinality(v_analysis_ids) = 0 or cardinality(v_evidence_ids) = 0
       or cardinality(v_supporting) <> (select count(distinct value) from unnest(v_supporting) source(value))
       or cardinality(v_dissenting) <> (select count(distinct value) from unnest(v_dissenting) source(value))
       or cardinality(v_analysis_ids) <> (select count(distinct value) from unnest(v_analysis_ids) analysis(value))
       or cardinality(v_evidence_ids) <> (select count(distinct value) from unnest(v_evidence_ids) evidence(value))
       or exists (select 1 from unnest(v_supporting) source(value) where value = any(v_dissenting)) then
      raise exception 'invalid_x_daily_judgement_evidence' using errcode = '22023';
    end if;

    select array(select distinct value from unnest(v_supporting || v_dissenting) source(value) order by value)
    into v_item_sources;

    with authoritative as (
      select batch_source.source_id::text as source_id,
        ref.post_id || '@' || ref.analysis_version::text as analysis_id,
        analysis.evidence_refs
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
      where batch.id = p_batch_id and batch_source.settlement_status = 'included'
    )
    select
      count(*),
      array(select distinct source_id from authoritative where analysis_id = any(v_analysis_ids) order by source_id),
      array(
        select distinct evidence.value
        from authoritative
        cross join lateral jsonb_array_elements_text(authoritative.evidence_refs) evidence(value)
        where authoritative.analysis_id = any(v_analysis_ids)
        order by evidence.value
      )
    into v_matched_analysis_rows, v_expected_sources, v_expected_evidence
    from authoritative
    where analysis_id = any(v_analysis_ids);

    if v_matched_analysis_rows <> cardinality(v_analysis_ids)
       or v_item_sources is distinct from v_expected_sources
       or array(select distinct value from unnest(v_evidence_ids) evidence(value) order by value) is distinct from v_expected_evidence then
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
  perform public.validate_x_daily_judgement_output(new.output);
  v_expected_snapshot := public.build_x_daily_judgement_input_snapshot(new.batch_id);
  if new.input_snapshot <> v_expected_snapshot then
    raise exception 'invalid_x_daily_judgement_snapshot' using errcode = '22023';
  end if;
  perform public.validate_x_daily_judgement_output_authority(new.batch_id, new.output);
  return new;
end;
$$;

revoke all on function public.validate_x_daily_judgement_output_authority(uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.validate_x_daily_judgement_output_authority(uuid, jsonb)
  to service_role;
