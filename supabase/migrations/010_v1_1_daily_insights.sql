create or replace function public.get_window_daily_fact_context(
  p_task_id uuid,
  p_attempt integer,
  p_worker_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_task public.sync_tasks%rowtype;
  v_catalog jsonb;
  v_prior_batches jsonb;
begin
  select task.* into v_task
  from public.sync_tasks task
  join public.task_attempts attempt
    on attempt.task_id = task.id and attempt.attempt = p_attempt
  where task.id = p_task_id
    and task.collection_scope->>'mode' = 'window'
    and task.lease_owner = p_worker_id
    and task.status in ('leased', 'running')
    and attempt.worker_id = p_worker_id
    and attempt.status in ('leased', 'running')
  for update of task, attempt;

  if not found then
    raise exception 'lease_mismatch' using errcode = '40001';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'external_message_id', message.external_message_id,
        'natural_date', (message.occurred_at at time zone 'Asia/Shanghai')::date::text,
        'author_id', message.metadata->>'author_id',
        'author_display', message.author_display,
        'has_unparsed_media', message.has_unparsed_media
      )
      order by message.occurred_at, message.external_message_id
    ),
    '[]'::jsonb
  ) into v_catalog
  from public.canonical_messages message
  where message.source_id = v_task.source_id
    and (message.occurred_at at time zone 'Asia/Shanghai')::date between
      ((v_task.capture_range->>'start_at')::timestamptz at time zone 'Asia/Shanghai')::date
      and ((v_task.capture_range->>'end_at')::timestamptz at time zone 'Asia/Shanghai')::date;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'natural_date', batch.natural_date::text,
        'facts', batch.output->'facts',
        'warnings', batch.output->'warnings',
        'unparsed_media_message_ids', batch.coverage->'unparsed_media_message_ids'
      )
      order by batch.natural_date, batch.created_at, batch.id
    ),
    '[]'::jsonb
  ) into v_prior_batches
  from public.summary_batches batch
  join public.sync_tasks completed_task on completed_task.id = batch.task_id
  where batch.source_id = v_task.source_id
    and batch.task_id <> v_task.id
    and completed_task.status = 'succeeded'
    and batch.output->>'schema_version' = 'v1.1-batch'
    and batch.natural_date between
      ((v_task.capture_range->>'start_at')::timestamptz at time zone 'Asia/Shanghai')::date
      and ((v_task.capture_range->>'end_at')::timestamptz at time zone 'Asia/Shanghai')::date;

  return jsonb_build_object('message_catalog', v_catalog, 'prior_batches', v_prior_batches);
end;
$$;

alter function public.persist_worker_execution(uuid, integer, uuid, jsonb)
  rename to persist_worker_execution_v1_1_daily_core;

create function public.persist_worker_execution(
  p_task_id uuid,
  p_attempt integer,
  p_worker_id uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_result jsonb;
  v_task public.sync_tasks%rowtype;
  v_batch record;
  v_daily_output jsonb;
  v_daily_batches jsonb;
  v_daily_coverage jsonb;
  v_daily_id uuid;
  v_existing public.daily_summaries%rowtype;
  v_daily_version integer;
  v_daily_ids jsonb := '[]'::jsonb;
  v_evidence_ids jsonb;
  v_prior_current_ids jsonb := '[]'::jsonb;
  v_legacy_daily_ids jsonb := '[]'::jsonb;
  v_has_v1_1_batch boolean := false;
begin
  select exists (
    select 1
    from jsonb_to_recordset(coalesce(p_payload->'batch_summaries', '[]'::jsonb)) as batch(output jsonb)
    where batch.output->>'schema_version' = 'v1.1-batch'
  ) into v_has_v1_1_batch;

  if not v_has_v1_1_batch then
    return public.persist_worker_execution_v1_1_daily_core(
      p_task_id, p_attempt, p_worker_id, p_payload
    );
  end if;

  select * into v_task from public.sync_tasks where id = p_task_id;
  select coalesce(jsonb_agg(to_jsonb(summary.id::text)), '[]'::jsonb)
  into v_prior_current_ids
  from public.daily_summaries summary
  join jsonb_to_recordset(coalesce(p_payload->'batch_summaries', '[]'::jsonb)) as batch(
    natural_date date,
    output jsonb
  ) on batch.natural_date = summary.natural_date
  where summary.source_id = v_task.source_id
    and summary.is_current
    and batch.output->>'schema_version' = 'v1.1-batch';

  v_result := public.persist_worker_execution_v1_1_daily_core(
    p_task_id, p_attempt, p_worker_id, p_payload
  );

  v_legacy_daily_ids := coalesce(v_result->'daily_summary_ids', '[]'::jsonb);
  update public.daily_summaries summary
  set is_current = false
  where summary.id::text in (
    select value from jsonb_array_elements_text(v_legacy_daily_ids)
  );
  update public.daily_summaries summary
  set is_current = true
  where summary.id::text in (
    select value from jsonb_array_elements_text(v_prior_current_ids)
  );

  for v_batch in
    select *
    from jsonb_to_recordset(coalesce(p_payload->'batch_summaries', '[]'::jsonb)) as batch(
      natural_date date,
      output jsonb,
      coverage jsonb
    )
    where batch.output->>'schema_version' = 'v1.1-batch'
  loop
    v_daily_output := v_batch.output->'daily_summary';
    if v_daily_output is null
       or jsonb_typeof(v_daily_output) <> 'object'
       or (v_daily_output - 'schema_version' - 'natural_date' - 'as_of' - 'author_cards' - 'topic_discussions' - 'warnings') <> '{}'::jsonb
       or v_daily_output->>'schema_version' <> 'v1.1'
       or v_daily_output->>'natural_date' <> v_batch.natural_date::text
       or jsonb_typeof(v_daily_output->'author_cards') <> 'array'
       or jsonb_typeof(v_daily_output->'topic_discussions') <> 'array'
       or jsonb_typeof(v_daily_output->'warnings') <> 'array' then
      raise exception 'invalid_v1_1_daily_summary' using errcode = '22023';
    end if;
    begin
      perform (v_daily_output->>'as_of')::timestamptz;
    exception when invalid_datetime_format or datetime_field_overflow then
      raise exception 'invalid_v1_1_daily_summary' using errcode = '22023';
    end;

    v_evidence_ids := coalesce(jsonb_path_query_array(v_daily_output, '$.author_cards[*].source_message_ids[*]'), '[]'::jsonb)
      || coalesce(jsonb_path_query_array(v_daily_output, '$.author_cards[*].core_logic.stock_judgments[*].source_message_ids[*]'), '[]'::jsonb)
      || coalesce(jsonb_path_query_array(v_daily_output, '$.topic_discussions[*].source_message_ids[*]'), '[]'::jsonb)
      || coalesce(jsonb_path_query_array(v_daily_output, '$.topic_discussions[*].viewpoints[*].source_message_ids[*]'), '[]'::jsonb);
    if exists (
      select 1
      from jsonb_array_elements_text(v_evidence_ids) as evidence(external_message_id)
      left join public.canonical_messages message
        on message.source_id = v_task.source_id
       and message.external_message_id = evidence.external_message_id
      where message.id is null
         or (message.occurred_at at time zone 'Asia/Shanghai')::date <> v_batch.natural_date
    ) then
      raise exception 'invalid_v1_1_daily_evidence' using errcode = '22023';
    end if;

    select coalesce(jsonb_agg(to_jsonb(batch.id::text) order by batch.created_at, batch.id), '[]'::jsonb)
    into v_daily_batches
    from public.summary_batches batch
    where batch.source_id = v_task.source_id and batch.natural_date = v_batch.natural_date;
    v_daily_coverage := jsonb_build_object(
      'as_of', v_daily_output->>'as_of',
      'unparsed_media', coalesce((v_batch.coverage->>'unparsed_media')::boolean, false)
    );

    select * into v_existing
    from public.daily_summaries summary
    where summary.source_id = v_task.source_id
      and summary.natural_date = v_batch.natural_date
      and summary.output = v_daily_output
      and summary.batch_ids = v_daily_batches
      and summary.coverage = v_daily_coverage
    order by summary.version desc
    limit 1;
    if found then
      v_daily_id := v_existing.id;
    else
      select coalesce(max(version), 0) + 1 into v_daily_version
      from public.daily_summaries
      where source_id = v_task.source_id and natural_date = v_batch.natural_date;
      insert into public.daily_summaries (
        source_id, natural_date, version, is_current, batch_ids, output, coverage
      ) values (
        v_task.source_id, v_batch.natural_date, v_daily_version, false,
        v_daily_batches, v_daily_output, v_daily_coverage
      ) returning id into v_daily_id;
    end if;
    v_daily_ids := v_daily_ids || to_jsonb(v_daily_id::text);
  end loop;

  if jsonb_array_length(v_daily_ids) > 0 then
    update public.worker_execution_receipts
    set daily_summary_ids = v_daily_ids
    where task_id = p_task_id and attempt = p_attempt and worker_id = p_worker_id;
    return v_result || jsonb_build_object('daily_summary_ids', v_daily_ids);
  end if;
  return v_result;
end;
$$;

alter function public.complete_windowed_capture_range(uuid, integer, uuid, jsonb)
  rename to complete_windowed_capture_range_v1_1_daily_core;

create function public.complete_windowed_capture_range(
  p_task_id uuid,
  p_attempt integer,
  p_worker_id uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_result jsonb;
  v_summary_id text;
  v_summary public.daily_summaries%rowtype;
begin
  v_result := public.complete_windowed_capture_range_v1_1_daily_core(
    p_task_id, p_attempt, p_worker_id, p_payload
  );

  for v_summary_id in
    select value
    from jsonb_array_elements_text(coalesce(p_payload->'daily_summary_ids', '[]'::jsonb))
  loop
    select * into v_summary
    from public.daily_summaries
    where id = v_summary_id::uuid and output->>'schema_version' = 'v1.1'
    for update;
    if found then
      update public.daily_summaries
      set is_current = false
      where source_id = v_summary.source_id
        and natural_date = v_summary.natural_date
        and is_current
        and id <> v_summary.id;
      update public.daily_summaries set is_current = true where id = v_summary.id;
    end if;
  end loop;
  return v_result;
end;
$$;

revoke all on function public.get_window_daily_fact_context(uuid, integer, uuid)
  from public, anon, authenticated;
revoke all on function public.persist_worker_execution_v1_1_daily_core(uuid, integer, uuid, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.complete_windowed_capture_range_v1_1_daily_core(uuid, integer, uuid, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.persist_worker_execution(uuid, integer, uuid, jsonb)
  from public, anon, authenticated;
revoke all on function public.complete_windowed_capture_range(uuid, integer, uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.get_window_daily_fact_context(uuid, integer, uuid) to service_role;
grant execute on function public.persist_worker_execution(uuid, integer, uuid, jsonb) to service_role;
grant execute on function public.complete_windowed_capture_range(uuid, integer, uuid, jsonb) to service_role;
