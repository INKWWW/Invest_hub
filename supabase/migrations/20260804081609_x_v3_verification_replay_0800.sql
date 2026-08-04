-- An explicit, one-off v3 replay.  It is deliberately separate from the
-- immutable scheduled batch/run/segment lifecycle.

create table public.x_v3_verification_replays (
  id uuid primary key default gen_random_uuid(),
  source_batch_id uuid not null unique references public.x_collection_batches(id) on delete restrict,
  requested_by uuid not null references public.profiles(id) on delete restrict,
  status text not null default 'queued' check (status in ('queued', 'running', 'succeeded', 'failed')),
  attempt integer not null default 0 check (attempt between 0 and 1),
  lease_owner uuid references public.workers(id) on delete set null,
  lease_expires_at timestamptz,
  failure_class text check (failure_class is null or failure_class in ('timeout', 'provider_failure', 'empty_response', 'invalid_json', 'schema_error', 'persistence_failure')),
  created_at timestamptz not null default timezone('utc', now()),
  started_at timestamptz,
  completed_at timestamptz,
  check ((status = 'running') = (lease_owner is not null and lease_expires_at is not null)),
  check ((status <> 'succeeded') or completed_at is not null)
);

create table public.x_v3_verification_replay_sources (
  replay_id uuid not null references public.x_v3_verification_replays(id) on delete restrict,
  source_id uuid not null references public.sources(id) on delete restrict,
  display_name text not null check (length(btrim(display_name)) > 0),
  original_range_task_id uuid not null references public.sync_tasks(id) on delete restrict,
  original_segment_id uuid not null references public.x_daily_viewpoint_segments(id) on delete restrict,
  occurred_from_at timestamptz not null,
  occurred_through_at timestamptz not null,
  posts jsonb not null check (jsonb_typeof(posts) = 'array' and jsonb_array_length(posts) > 0),
  primary key (replay_id, source_id),
  unique (replay_id, original_range_task_id),
  check (occurred_from_at <= occurred_through_at)
);

create table public.x_v3_verification_segments (
  id uuid primary key default gen_random_uuid(),
  replay_id uuid not null references public.x_v3_verification_replays(id) on delete restrict,
  source_id uuid not null references public.sources(id) on delete restrict,
  occurred_from_at timestamptz not null,
  occurred_through_at timestamptz not null,
  schema_version text not null check (schema_version = 'v3-x-window'),
  prompt_version text not null check (prompt_version = 'v3-x-window-1'),
  segment_output jsonb not null check (jsonb_typeof(segment_output) = 'object'),
  post_analysis_refs jsonb not null check (jsonb_typeof(post_analysis_refs) = 'array'),
  evidence_refs jsonb not null check (jsonb_typeof(evidence_refs) = 'array'),
  created_at timestamptz not null default timezone('utc', now()),
  unique (replay_id, source_id),
  check (occurred_from_at <= occurred_through_at)
);

create table public.x_v3_verification_versions (
  id uuid primary key default gen_random_uuid(),
  replay_id uuid not null unique references public.x_v3_verification_replays(id) on delete restrict,
  input_snapshot jsonb not null check (jsonb_typeof(input_snapshot) = 'object'),
  output jsonb not null check (jsonb_typeof(output) = 'object'),
  provider text not null check (provider = 'codex_cli'),
  model_reported text,
  prompt_version text not null check (prompt_version = 'v3-x-cross-blogger-1'),
  schema_version text not null check (schema_version = 'v3-x-cross-blogger'),
  created_at timestamptz not null default timezone('utc', now())
);

create trigger x_v3_verification_replay_sources_immutable before update or delete on public.x_v3_verification_replay_sources
for each row execute function public.reject_x_fact_mutation();
create trigger x_v3_verification_segments_immutable before update or delete on public.x_v3_verification_segments
for each row execute function public.reject_x_fact_mutation();
create trigger x_v3_verification_versions_immutable before update or delete on public.x_v3_verification_versions
for each row execute function public.reject_x_fact_mutation();

alter table public.x_v3_verification_replays enable row level security;
alter table public.x_v3_verification_replay_sources enable row level security;
alter table public.x_v3_verification_segments enable row level security;
alter table public.x_v3_verification_versions enable row level security;

create or replace function public.create_x_v3_verification_replay(p_source_batch_id uuid, p_requested_by uuid)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_batch public.x_collection_batches%rowtype;
  v_replay public.x_v3_verification_replays%rowtype;
begin
  if p_requested_by is null or not exists (select 1 from public.profiles where id = p_requested_by and role = 'admin') then
    raise exception 'actor_not_authorized' using errcode = '42501';
  end if;
  select * into v_batch from public.x_collection_batches where id = p_source_batch_id for update;
  if not found or v_batch.status <> 'judgement_failed' or v_batch.scheduled_window_key <> '2026-08-04T08:00+08:00' then
    raise exception 'x_v3_verification_source_batch_not_available' using errcode = '22023';
  end if;
  insert into public.x_v3_verification_replays (source_batch_id, requested_by)
  values (p_source_batch_id, p_requested_by) returning * into v_replay;
  insert into public.x_v3_verification_replay_sources
    (replay_id, source_id, display_name, original_range_task_id, original_segment_id, occurred_from_at, occurred_through_at, posts)
  select v_replay.id, batch_source.source_id, batch_source.source_display_name, batch_source.x_sync_task_id, segment.id,
         segment.occurred_from_at, segment.occurred_through_at,
         jsonb_agg(jsonb_build_object(
           'post_id', message.external_message_id, 'content', message.content, 'occurred_at', message.occurred_at,
           'post_url', context.post_url, 'post_type', context.post_type, 'quoted_post_id', context.quoted_post_id,
           'reply_to_post_id', context.reply_to_post_id, 'reposted_post_id', context.reposted_post_id,
           'context_status', context.context_status, 'attachments', context.attachments
         ) order by message.external_message_id)
  from public.x_collection_batch_sources batch_source
  join public.x_daily_viewpoint_segments segment on segment.source_id = batch_source.source_id
    and segment.range_task_id = batch_source.x_sync_task_id and segment.natural_date = v_batch.natural_date
  join public.sync_tasks range_task on range_task.id = batch_source.x_sync_task_id
  join public.canonical_messages message on message.source_id = batch_source.source_id
    and message.occurred_at > (range_task.capture_range->>'start_at')::timestamptz
    and message.occurred_at <= (range_task.capture_range->>'end_at')::timestamptz
  join public.x_post_contexts context on context.canonical_message_id = message.id
  where batch_source.batch_id = v_batch.id and batch_source.settlement_status = 'included'
  group by batch_source.source_id, batch_source.source_display_name, batch_source.x_sync_task_id, segment.id,
           segment.occurred_from_at, segment.occurred_through_at;
  if (select count(*) from public.x_v3_verification_replay_sources where replay_id = v_replay.id) <>
     (select count(*) from public.x_collection_batch_sources where batch_id = v_batch.id and settlement_status = 'included') then
    raise exception 'x_v3_verification_source_snapshot_invalid' using errcode = '22023';
  end if;
  return jsonb_build_object('replay_id', v_replay.id::text, 'status', v_replay.status);
end;
$$;

create or replace function public.claim_x_v3_verification_replay(p_replay_id uuid, p_worker_id uuid)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_replay public.x_v3_verification_replays%rowtype;
begin
  if p_worker_id is null or not exists (select 1 from public.workers where id = p_worker_id and status in ('enrolled', 'online')) then
    raise exception 'invalid_x_v3_verification_worker' using errcode = '22023';
  end if;
  select * into v_replay from public.x_v3_verification_replays where id = p_replay_id for update;
  if not found or v_replay.status <> 'queued' then return null; end if;
  update public.x_v3_verification_replays set status = 'running', attempt = 1, lease_owner = p_worker_id,
    lease_expires_at = timezone('utc', now()) + interval '15 minutes', started_at = timezone('utc', now())
  where id = p_replay_id returning * into v_replay;
  return jsonb_build_object('replay_id', v_replay.id::text, 'attempt', v_replay.attempt, 'lease_expires_at', v_replay.lease_expires_at);
end;
$$;

create or replace function public.get_x_v3_verification_replay_context(p_replay_id uuid, p_attempt integer, p_worker_id uuid)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_replay public.x_v3_verification_replays%rowtype;
begin
  select * into v_replay from public.x_v3_verification_replays where id = p_replay_id;
  if not found or v_replay.status <> 'running' or v_replay.attempt <> p_attempt or v_replay.lease_owner <> p_worker_id or v_replay.lease_expires_at <= timezone('utc', now()) then
    raise exception 'lease_mismatch' using errcode = 'PT409';
  end if;
  return jsonb_build_object('replay_id', v_replay.id::text, 'attempt', v_replay.attempt,
    'sources', coalesce((select jsonb_agg(jsonb_build_object(
      'source_id', source_id::text, 'display_name', display_name, 'posts', posts,
      'occurred_from_at', occurred_from_at, 'occurred_through_at', occurred_through_at
    ) order by source_id) from public.x_v3_verification_replay_sources where replay_id = v_replay.id), '[]'::jsonb));
end;
$$;

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
  perform public.validate_x_daily_judgement_output_v3(p_payload->'daily');

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

  for v_item in select value from jsonb_array_elements(p_payload->'daily'->'security_industry_viewpoints' || p_payload->'daily'->'market_structure_viewpoints' || p_payload->'daily'->'strategy_mindset_viewpoints') loop
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
    select * into v_snapshot from public.x_v3_verification_replay_sources where replay_id = v_replay.id and source_id = v_source_id;
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
  values (v_replay.id, v_input_snapshot, p_payload->'daily', 'codex_cli', nullif(p_payload->>'model_reported', ''), 'v3-x-cross-blogger-1', 'v3-x-cross-blogger');
  update public.x_v3_verification_replays set status = 'succeeded', lease_owner = null, lease_expires_at = null, completed_at = timezone('utc', now()) where id = v_replay.id;
  return jsonb_build_object('status', 'succeeded', 'replay_id', v_replay.id::text, 'attempt', v_replay.attempt);
end;
$$;

create or replace function public.fail_x_v3_verification_replay(p_replay_id uuid, p_attempt integer, p_worker_id uuid, p_failure_class text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_replay public.x_v3_verification_replays%rowtype;
begin
  if p_failure_class not in ('timeout', 'provider_failure', 'empty_response', 'invalid_json', 'schema_error', 'persistence_failure') then
    raise exception 'invalid_x_v3_verification_failure' using errcode = '22023';
  end if;
  select * into v_replay from public.x_v3_verification_replays where id = p_replay_id for update;
  if not found or v_replay.status <> 'running' or v_replay.attempt <> p_attempt or v_replay.lease_owner <> p_worker_id then
    raise exception 'lease_mismatch' using errcode = 'PT409';
  end if;
  update public.x_v3_verification_replays set status = 'failed', lease_owner = null, lease_expires_at = null, failure_class = p_failure_class
  where id = p_replay_id;
  return jsonb_build_object('status', 'failed', 'failure_class', p_failure_class);
end;
$$;

revoke all on table public.x_v3_verification_replays, public.x_v3_verification_replay_sources,
  public.x_v3_verification_segments, public.x_v3_verification_versions from public, anon, authenticated;
revoke all on function public.create_x_v3_verification_replay(uuid, uuid), public.claim_x_v3_verification_replay(uuid, uuid),
  public.get_x_v3_verification_replay_context(uuid, integer, uuid), public.complete_x_v3_verification_replay(uuid, integer, uuid, jsonb),
  public.fail_x_v3_verification_replay(uuid, integer, uuid, text) from public, anon, authenticated;
grant execute on function public.create_x_v3_verification_replay(uuid, uuid), public.claim_x_v3_verification_replay(uuid, uuid),
  public.get_x_v3_verification_replay_context(uuid, integer, uuid), public.complete_x_v3_verification_replay(uuid, integer, uuid, jsonb),
  public.fail_x_v3_verification_replay(uuid, integer, uuid, text) to service_role;
