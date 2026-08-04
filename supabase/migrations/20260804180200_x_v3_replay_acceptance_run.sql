-- A failed replay is immutable.  This separately auditable lifecycle is the
-- sole permitted production acceptance path over its already frozen inputs.

create table public.x_v3_verification_acceptance_runs (
  id uuid primary key default gen_random_uuid(),
  parent_replay_id uuid not null unique references public.x_v3_verification_replays(id) on delete restrict,
  requested_by uuid not null references public.profiles(id) on delete restrict,
  status text not null default 'queued' check (status in ('queued', 'running', 'succeeded', 'failed')),
  attempt integer not null default 0 check (attempt between 0 and 1),
  lease_owner uuid references public.workers(id) on delete restrict,
  lease_expires_at timestamptz,
  failure_class text check (failure_class in ('timeout', 'provider_failure', 'empty_response', 'invalid_json', 'schema_error', 'persistence_failure')),
  created_at timestamptz not null default timezone('utc', now()),
  started_at timestamptz,
  completed_at timestamptz,
  check ((status = 'queued' and attempt = 0 and lease_owner is null and lease_expires_at is null and failure_class is null)
    or (status = 'running' and attempt = 1 and lease_owner is not null and lease_expires_at is not null and failure_class is null)
    or (status = 'succeeded' and attempt = 1 and lease_owner is null and lease_expires_at is null and failure_class is null and completed_at is not null)
    or (status = 'failed' and attempt = 1 and lease_owner is null and lease_expires_at is null and failure_class is not null))
);

create table public.x_v3_verification_acceptance_segments (
  id uuid primary key default gen_random_uuid(),
  acceptance_run_id uuid not null references public.x_v3_verification_acceptance_runs(id) on delete restrict,
  source_id uuid not null references public.sources(id) on delete restrict,
  occurred_from_at timestamptz not null,
  occurred_through_at timestamptz not null,
  schema_version text not null check (schema_version = 'v3-x-window'),
  prompt_version text not null check (prompt_version = 'v3-x-window-1'),
  segment_output jsonb not null check (jsonb_typeof(segment_output) = 'object'),
  post_analysis_refs jsonb not null check (jsonb_typeof(post_analysis_refs) = 'array'),
  evidence_refs jsonb not null check (jsonb_typeof(evidence_refs) = 'array'),
  created_at timestamptz not null default timezone('utc', now()),
  unique (acceptance_run_id, source_id),
  check (occurred_from_at <= occurred_through_at)
);

create table public.x_v3_verification_acceptance_versions (
  id uuid primary key default gen_random_uuid(),
  acceptance_run_id uuid not null unique references public.x_v3_verification_acceptance_runs(id) on delete restrict,
  input_snapshot jsonb not null check (jsonb_typeof(input_snapshot) = 'object'),
  output jsonb not null check (jsonb_typeof(output) = 'object'),
  provider text not null check (provider = 'codex_cli'),
  model_reported text,
  prompt_version text not null check (prompt_version = 'v3-x-cross-blogger-1'),
  schema_version text not null check (schema_version = 'v3-x-cross-blogger'),
  created_at timestamptz not null default timezone('utc', now())
);

create trigger x_v3_verification_acceptance_segments_immutable before update or delete on public.x_v3_verification_acceptance_segments
for each row execute function public.reject_x_fact_mutation();
create trigger x_v3_verification_acceptance_versions_immutable before update or delete on public.x_v3_verification_acceptance_versions
for each row execute function public.reject_x_fact_mutation();

alter table public.x_v3_verification_acceptance_runs enable row level security;
alter table public.x_v3_verification_acceptance_segments enable row level security;
alter table public.x_v3_verification_acceptance_versions enable row level security;
revoke all on table public.x_v3_verification_acceptance_runs, public.x_v3_verification_acceptance_segments, public.x_v3_verification_acceptance_versions from public, anon, authenticated;

create or replace function public.create_x_v3_verification_acceptance_run(p_parent_replay_id uuid, p_requested_by uuid)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_parent public.x_v3_verification_replays%rowtype; v_run public.x_v3_verification_acceptance_runs%rowtype;
begin
  if p_requested_by is null or not exists (select 1 from public.profiles where id = p_requested_by and role = 'admin') then raise exception 'actor_not_authorized' using errcode = '42501'; end if;
  select * into v_parent from public.x_v3_verification_replays where id = p_parent_replay_id;
  if not found or v_parent.status <> 'failed' then raise exception 'x_v3_verification_parent_replay_not_available' using errcode = '22023'; end if;
  if not exists (select 1 from public.x_v3_verification_replay_sources where replay_id = v_parent.id) then raise exception 'x_v3_verification_parent_snapshot_unavailable' using errcode = '22023'; end if;
  insert into public.x_v3_verification_acceptance_runs (parent_replay_id, requested_by) values (v_parent.id, p_requested_by) returning * into v_run;
  return jsonb_build_object('acceptance_run_id', v_run.id::text, 'status', v_run.status);
end;
$$;

create or replace function public.claim_x_v3_verification_acceptance_run(p_acceptance_run_id uuid, p_worker_id uuid)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_run public.x_v3_verification_acceptance_runs%rowtype;
begin
  if p_worker_id is null or not exists (select 1 from public.workers where id = p_worker_id and status in ('enrolled', 'online')) then raise exception 'invalid_x_v3_verification_worker' using errcode = '22023'; end if;
  select * into v_run from public.x_v3_verification_acceptance_runs where id = p_acceptance_run_id for update;
  if not found or v_run.status <> 'queued' then return null; end if;
  update public.x_v3_verification_acceptance_runs set status = 'running', attempt = 1, lease_owner = p_worker_id, lease_expires_at = timezone('utc', now()) + interval '15 minutes', started_at = timezone('utc', now()) where id = p_acceptance_run_id returning * into v_run;
  return jsonb_build_object('acceptance_run_id', v_run.id::text, 'attempt', v_run.attempt, 'lease_expires_at', v_run.lease_expires_at);
end;
$$;

create or replace function public.get_x_v3_verification_acceptance_context(p_acceptance_run_id uuid, p_attempt integer, p_worker_id uuid)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_run public.x_v3_verification_acceptance_runs%rowtype;
begin
  select * into v_run from public.x_v3_verification_acceptance_runs where id = p_acceptance_run_id;
  if not found or v_run.status <> 'running' or v_run.attempt <> p_attempt or v_run.lease_owner <> p_worker_id or v_run.lease_expires_at <= timezone('utc', now()) then raise exception 'lease_mismatch' using errcode = 'PT409'; end if;
  return jsonb_build_object('acceptance_run_id', v_run.id::text, 'attempt', v_run.attempt, 'sources', coalesce((
    select jsonb_agg(jsonb_build_object('source_id', source.source_id::text, 'display_name', source.display_name, 'occurred_from_at', source.occurred_from_at, 'occurred_through_at', source.occurred_through_at, 'posts', source.posts) order by source.source_id)
    from public.x_v3_verification_replay_sources source where source.replay_id = v_run.parent_replay_id
  ), '[]'::jsonb));
end;
$$;

create or replace function public.fail_x_v3_verification_acceptance_run(p_acceptance_run_id uuid, p_attempt integer, p_worker_id uuid, p_failure_class text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_run public.x_v3_verification_acceptance_runs%rowtype;
begin
  if p_failure_class not in ('timeout', 'provider_failure', 'empty_response', 'invalid_json', 'schema_error', 'persistence_failure') then raise exception 'invalid_x_v3_verification_failure' using errcode = '22023'; end if;
  select * into v_run from public.x_v3_verification_acceptance_runs where id = p_acceptance_run_id for update;
  if not found or v_run.status <> 'running' or v_run.attempt <> p_attempt or v_run.lease_owner <> p_worker_id then raise exception 'lease_mismatch' using errcode = 'PT409'; end if;
  update public.x_v3_verification_acceptance_runs set status = 'failed', lease_owner = null, lease_expires_at = null, failure_class = p_failure_class where id = p_acceptance_run_id;
  return jsonb_build_object('status', 'failed', 'failure_class', p_failure_class);
end;
$$;

revoke all on function public.create_x_v3_verification_acceptance_run(uuid, uuid), public.claim_x_v3_verification_acceptance_run(uuid, uuid), public.get_x_v3_verification_acceptance_context(uuid, integer, uuid), public.fail_x_v3_verification_acceptance_run(uuid, integer, uuid, text) from public, anon, authenticated;
grant execute on function public.create_x_v3_verification_acceptance_run(uuid, uuid), public.claim_x_v3_verification_acceptance_run(uuid, uuid), public.get_x_v3_verification_acceptance_context(uuid, integer, uuid), public.fail_x_v3_verification_acceptance_run(uuid, integer, uuid, text) to service_role;

create or replace function public.complete_x_v3_verification_acceptance_run(p_acceptance_run_id uuid, p_attempt integer, p_worker_id uuid, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_run public.x_v3_verification_acceptance_runs%rowtype; v_snapshot public.x_v3_verification_replay_sources%rowtype;
  v_source jsonb; v_analysis jsonb; v_segment jsonb; v_item jsonb; v_source_id uuid; v_post_id text; v_analysis_ids text[];
  v_expected_posts text[]; v_submitted_posts text[]; v_item_analysis_ids text[]; v_item_source_ids text[]; v_item_evidence_ids text[];
  v_expected_evidence_ids text[]; v_allowed_evidence text[]; v_canonical_id uuid; v_post_link text; v_input_snapshot jsonb; v_daily_output jsonb;
begin
  select * into v_run from public.x_v3_verification_acceptance_runs where id = p_acceptance_run_id for update;
  if not found or v_run.status <> 'running' or v_run.attempt <> p_attempt or v_run.lease_owner <> p_worker_id or v_run.lease_expires_at <= timezone('utc', now()) then raise exception 'lease_mismatch' using errcode = 'PT409'; end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' or (p_payload - 'provider' - 'model_reported' - 'sources' - 'daily') <> '{}'::jsonb or p_payload->>'provider' <> 'codex_cli' or not (p_payload ? 'model_reported') or jsonb_typeof(p_payload->'sources') <> 'array' or jsonb_typeof(p_payload->'daily') <> 'object' or jsonb_array_length(p_payload->'sources') <> (select count(*) from public.x_v3_verification_replay_sources where replay_id = v_run.parent_replay_id) then raise exception 'invalid_x_v3_verification_completion' using errcode = '22023'; end if;
  if p_payload->'daily'->>'schema_version' <> 'v3-x-cross-blogger' or p_payload->'daily'->>'prompt_version' <> 'v3-x-cross-blogger-1' then raise exception 'invalid_x_v3_verification_completion' using errcode = '22023'; end if;
  v_daily_output := (p_payload->'daily') - 'schema_version'::text - 'prompt_version'::text;
  perform public.validate_x_daily_judgement_output_v3(v_daily_output);
  for v_source in select value from jsonb_array_elements(p_payload->'sources') loop
    if jsonb_typeof(v_source) <> 'object' or (v_source - 'source_id' - 'analyses' - 'segment') <> '{}'::jsonb or jsonb_typeof(v_source->'analyses') <> 'array' or jsonb_typeof(v_source->'segment') <> 'object' then raise exception 'invalid_x_v3_verification_source' using errcode = '22023'; end if;
    begin v_source_id := (v_source->>'source_id')::uuid; exception when invalid_text_representation then raise exception 'invalid_x_v3_verification_source' using errcode = '22023'; end;
    select * into v_snapshot from public.x_v3_verification_replay_sources where replay_id = v_run.parent_replay_id and source_id = v_source_id;
    if not found or (select count(*) from jsonb_array_elements(p_payload->'sources') item where item->>'source_id' = v_source_id::text) <> 1 then raise exception 'invalid_x_v3_verification_source' using errcode = '22023'; end if;
    select coalesce(array_agg(post->>'post_id' order by post->>'post_id'), '{}') into v_expected_posts from jsonb_array_elements(v_snapshot.posts) post;
    select coalesce(array_agg(item->>'post_id' order by item->>'post_id'), '{}') into v_submitted_posts from jsonb_array_elements(v_source->'analyses') item;
    if v_submitted_posts is distinct from v_expected_posts or cardinality(v_submitted_posts) <> cardinality(array(select distinct unnest(v_submitted_posts))) then raise exception 'x_v3_verification_analysis_coverage_mismatch' using errcode = '22023'; end if;
    for v_analysis in select value from jsonb_array_elements(v_source->'analyses') loop
      if jsonb_typeof(v_analysis) <> 'object' or (v_analysis - 'post_id' - 'analysis_id' - 'analysis_version' - 'schema_version' - 'prompt_version' - 'analysis_output' - 'blogger_viewpoint' - 'arguments' - 'quoted_post_viewpoint' - 'uncertainties' - 'evidence_post_ids' - 'post_link') <> '{}'::jsonb or v_analysis->>'schema_version' <> 'v3-x-post-analysis' or v_analysis->>'prompt_version' <> 'v3-x-post-analysis-1' or v_analysis->>'analysis_id' <> v_analysis->>'post_id' || '@2' or nullif(v_analysis->>'analysis_version', '')::integer <> 2 or jsonb_typeof(v_analysis->'analysis_output') <> 'object' or v_analysis->'analysis_output'->>'post_id' <> v_analysis->>'post_id' or jsonb_typeof(v_analysis->'arguments') <> 'array' or jsonb_typeof(v_analysis->'uncertainties') <> 'array' or jsonb_typeof(v_analysis->'evidence_post_ids') <> 'array' or jsonb_array_length(v_analysis->'evidence_post_ids') = 0 then raise exception 'invalid_x_v3_verification_analysis' using errcode = '22023'; end if;
      v_post_id := v_analysis->>'post_id';
      select post->>'post_url', array_remove(array[post->>'post_id', post->>'quoted_post_id', post->>'reply_to_post_id', post->>'reposted_post_id'], null) into v_post_link, v_allowed_evidence from jsonb_array_elements(v_snapshot.posts) post where post->>'post_id' = v_post_id;
      if v_post_link is null or v_post_link <> v_analysis->>'post_link' or exists (select 1 from jsonb_array_elements_text(v_analysis->'evidence_post_ids') evidence where evidence <> all(v_allowed_evidence)) or (select count(*) from jsonb_array_elements_text(v_analysis->'evidence_post_ids')) <> (select count(distinct evidence) from jsonb_array_elements_text(v_analysis->'evidence_post_ids') evidence) then raise exception 'invalid_x_v3_verification_evidence' using errcode = '22023'; end if;
      select message.id into v_canonical_id from public.canonical_messages message where message.source_id = v_source_id and message.external_message_id = v_post_id;
      if v_canonical_id is null then raise exception 'invalid_x_v3_verification_analysis' using errcode = '22023'; end if;
      if exists (select 1 from public.x_post_analyses existing where existing.canonical_message_id = v_canonical_id and existing.analysis_version = 2 and (existing.analysis_output, existing.evidence_refs) is distinct from (v_analysis->'analysis_output', v_analysis->'evidence_post_ids')) then raise exception 'conflicting_x_post_analysis' using errcode = '23505'; end if;
    end loop;
    v_segment := v_source->'segment'; select coalesce(array_agg(item->>'analysis_id' order by item->>'analysis_id'), '{}') into v_analysis_ids from jsonb_array_elements(v_source->'analyses') item;
    if (v_segment - 'occurred_from_at' - 'occurred_through_at' - 'schema_version' - 'prompt_version' - 'segment_output' - 'analysis_ids' - 'evidence_post_ids' - 'uncertainties') <> '{}'::jsonb or v_segment->>'schema_version' <> 'v3-x-window' or v_segment->>'prompt_version' <> 'v3-x-window-1' or jsonb_typeof(v_segment->'segment_output') <> 'object' or v_segment->'segment_output'->>'schema_version' <> 'v3-x-window' or jsonb_typeof(v_segment->'analysis_ids') <> 'array' or jsonb_typeof(v_segment->'evidence_post_ids') <> 'array' or jsonb_typeof(v_segment->'uncertainties') <> 'array' or (v_segment->>'occurred_from_at')::timestamptz <> v_snapshot.occurred_from_at or (v_segment->>'occurred_through_at')::timestamptz <> v_snapshot.occurred_through_at or (select array_agg(value order by value) from jsonb_array_elements_text(v_segment->'analysis_ids') value) is distinct from v_analysis_ids then raise exception 'invalid_x_v3_verification_segment' using errcode = '22023'; end if;
  end loop;
  for v_item in select value from jsonb_array_elements(v_daily_output->'security_industry_viewpoints' || v_daily_output->'market_structure_viewpoints' || v_daily_output->'strategy_mindset_viewpoints') loop
    select coalesce(array_agg(value order by value), '{}') into v_item_analysis_ids from jsonb_array_elements_text(v_item->'analysis_ids') value; select coalesce(array_agg(value order by value), '{}') into v_item_evidence_ids from jsonb_array_elements_text(v_item->'evidence_post_ids') value; select coalesce(array_agg(value order by value), '{}') into v_item_source_ids from jsonb_array_elements_text(v_item->'supporting_source_ids' || v_item->'dissenting_source_ids') value;
    if cardinality(v_item_analysis_ids) <> cardinality(array(select distinct unnest(v_item_analysis_ids))) or cardinality(v_item_evidence_ids) <> cardinality(array(select distinct unnest(v_item_evidence_ids))) or cardinality(v_item_source_ids) <> cardinality(array(select distinct unnest(v_item_source_ids))) or exists (select 1 from unnest(v_item_source_ids) source_text where not exists (select 1 from public.x_v3_verification_replay_sources source where source.replay_id = v_run.parent_replay_id and source.source_id::text = source_text)) or exists (select 1 from unnest(v_item_analysis_ids) analysis_id where not exists (select 1 from jsonb_array_elements(p_payload->'sources') source_row cross join jsonb_array_elements(source_row->'analyses') analysis_row where analysis_row->>'analysis_id' = analysis_id and source_row->>'source_id' = any(v_item_source_ids))) then raise exception 'invalid_x_v3_verification_daily_authority' using errcode = '22023'; end if;
    select coalesce(array_agg(distinct evidence order by evidence), '{}') into v_expected_evidence_ids from jsonb_array_elements(p_payload->'sources') source_row cross join jsonb_array_elements(source_row->'analyses') analysis_row cross join jsonb_array_elements_text(analysis_row->'evidence_post_ids') evidence where analysis_row->>'analysis_id' = any(v_item_analysis_ids);
    if v_item_evidence_ids is distinct from v_expected_evidence_ids then raise exception 'invalid_x_v3_verification_daily_authority' using errcode = '22023'; end if;
  end loop;
  for v_source in select value from jsonb_array_elements(p_payload->'sources') loop
    v_source_id := (v_source->>'source_id')::uuid;
    for v_analysis in select value from jsonb_array_elements(v_source->'analyses') loop
      select message.id into v_canonical_id from public.canonical_messages message where message.source_id = v_source_id and message.external_message_id = v_analysis->>'post_id';
      insert into public.x_post_analyses (canonical_message_id, analysis_version, schema_version, prompt_version, analysis_output, blogger_viewpoint, arguments, quoted_post_viewpoint, uncertainties, evidence_refs) values (v_canonical_id, 2, 'v3-x-post-analysis', 'v3-x-post-analysis-1', v_analysis->'analysis_output', v_analysis->'blogger_viewpoint', v_analysis->'arguments', v_analysis->'quoted_post_viewpoint', v_analysis->'uncertainties', v_analysis->'evidence_post_ids') on conflict (canonical_message_id, analysis_version) do nothing;
    end loop;
    v_segment := v_source->'segment';
    insert into public.x_v3_verification_acceptance_segments (acceptance_run_id, source_id, occurred_from_at, occurred_through_at, schema_version, prompt_version, segment_output, post_analysis_refs, evidence_refs) values (v_run.id, v_source_id, (v_segment->>'occurred_from_at')::timestamptz, (v_segment->>'occurred_through_at')::timestamptz, 'v3-x-window', 'v3-x-window-1', v_segment->'segment_output', v_segment->'analysis_ids', v_segment->'evidence_post_ids');
  end loop;
  v_input_snapshot := public.get_x_v3_verification_acceptance_context(v_run.id, p_attempt, p_worker_id);
  insert into public.x_v3_verification_acceptance_versions (acceptance_run_id, input_snapshot, output, provider, model_reported, prompt_version, schema_version) values (v_run.id, v_input_snapshot, v_daily_output, 'codex_cli', nullif(p_payload->>'model_reported', ''), 'v3-x-cross-blogger-1', 'v3-x-cross-blogger');
  update public.x_v3_verification_acceptance_runs set status = 'succeeded', lease_owner = null, lease_expires_at = null, completed_at = timezone('utc', now()) where id = v_run.id;
  return jsonb_build_object('status', 'succeeded', 'acceptance_run_id', v_run.id::text, 'attempt', v_run.attempt);
end;
$$;

revoke all on function public.complete_x_v3_verification_acceptance_run(uuid, integer, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.complete_x_v3_verification_acceptance_run(uuid, integer, uuid, jsonb) to service_role;
