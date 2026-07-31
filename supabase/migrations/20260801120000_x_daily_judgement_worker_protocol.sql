-- Task 2's Worker protocol needs atomic lease verification for context reads
-- and independent retry accounting.  Neither function reads raw message text
-- or touches source tasks, coverage, or batch membership.

create function public.get_x_daily_judgement_context(
  p_run_id uuid, p_attempt integer, p_worker_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_run public.x_daily_judgement_runs%rowtype;
  v_context jsonb;
begin
  select * into v_run from public.x_daily_judgement_runs where id = p_run_id;
  if not found or p_attempt is null or p_worker_id is null or v_run.attempt <> p_attempt
     or v_run.status not in ('leased', 'running') or v_run.lease_owner <> p_worker_id
     or v_run.lease_expires_at <= timezone('utc', now()) then
    raise exception 'lease_mismatch' using errcode = 'PT409';
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
                -- The field is the completion-facing analysis identity.  It
                -- deliberately matches the frozen post_id@analysis_version
                -- reference checked by Task 1's immutable version trigger.
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
        ), '[]'::jsonb)
      ) order by batch_source.source_id)
      from public.x_collection_batch_sources batch_source
      where batch_source.batch_id = v_run.batch_id and batch_source.settlement_status = 'included'
    ), '[]'::jsonb),
    'excluded_sources', coalesce((
      select jsonb_agg(jsonb_build_object(
        'source_id', batch_source.source_id::text,
        'display_name', batch_source.source_display_name,
        'reason', batch_source.exclusion_code
      ) order by batch_source.source_id)
      from public.x_collection_batch_sources batch_source
      where batch_source.batch_id = v_run.batch_id and batch_source.settlement_status = 'excluded'
    ), '[]'::jsonb)
  ) into v_context;
  return v_context;
end;
$$;

create function public.fail_x_daily_judgement(
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

  -- The independently persisted judgement run has three attempts, including
  -- the leased attempt being reported.  It cannot alter source work or batch
  -- settlement; operators retain the frozen batch for review on terminal run.
  v_status := case when v_run.attempt >= 3 then 'failed' else 'retryable_failed' end;
  update public.x_daily_judgement_runs
  set status = v_status,
      lease_owner = null,
      lease_expires_at = null,
      available_at = timezone('utc', now()),
      failure_class = p_failure_class
  where id = v_run.id;
  return jsonb_build_object('run_id', v_run.id::text, 'attempt', v_run.attempt, 'status', v_status, 'failure_class', p_failure_class);
end;
$$;

revoke all on function public.get_x_daily_judgement_context(uuid, integer, uuid),
  public.fail_x_daily_judgement(uuid, integer, uuid, text)
  from public, anon, authenticated;
grant execute on function public.get_x_daily_judgement_context(uuid, integer, uuid),
  public.fail_x_daily_judgement(uuid, integer, uuid, text)
  to service_role;
