alter table public.sources
  add column authorized_worker_id uuid references public.workers(id) on delete set null;

create index sources_authorized_worker_idx on public.sources (authorized_worker_id) where authorized_worker_id is not null;

alter table public.sync_tasks
  add column rule_snapshot jsonb not null default '{"version":0,"target_author_ids":[]}'::jsonb,
  add column collection_scope jsonb not null default '{"mode":"incremental","max_pages":1}'::jsonb,
  add constraint sync_tasks_rule_snapshot_shape check (
    jsonb_typeof(rule_snapshot) = 'object'
    and jsonb_typeof(rule_snapshot->'version') = 'number'
    and (rule_snapshot->>'version')::numeric >= 0
    and mod((rule_snapshot->>'version')::numeric, 1) = 0
    and jsonb_typeof(rule_snapshot->'target_author_ids') = 'array'
  ),
  add constraint sync_tasks_collection_scope_shape check (
    jsonb_typeof(collection_scope) = 'object'
    and collection_scope->>'mode' in ('incremental', 'history')
    and jsonb_typeof(collection_scope->'max_pages') = 'number'
    and (collection_scope->>'max_pages')::numeric between 1 and 25
    and mod((collection_scope->>'max_pages')::numeric, 1) = 0
  );

create table public.source_author_rules (
  id uuid primary key default gen_random_uuid(),
  author_id text not null check (length(trim(author_id)) > 0),
  scope text not null check (scope in ('global', 'source')),
  source_id uuid references public.sources(id) on delete cascade,
  policy text not null check (policy in ('target', 'exclude')),
  enabled boolean not null default true,
  version integer not null check (version > 0),
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  check (
    (scope = 'global' and source_id is null)
    or (scope = 'source' and source_id is not null)
  )
);

create unique index source_author_rules_identity_idx
  on public.source_author_rules (author_id, scope, coalesce(source_id, '00000000-0000-0000-0000-000000000000'::uuid), policy);
create index source_author_rules_lookup_idx
  on public.source_author_rules (scope, source_id, enabled, version desc);
create trigger source_author_rules_set_updated_at before update on public.source_author_rules
for each row execute function public.set_updated_at();

create table public.summary_batches (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.sync_tasks(id) on delete cascade,
  source_id uuid not null references public.sources(id) on delete cascade,
  natural_date date not null,
  input_message_ids jsonb not null check (jsonb_typeof(input_message_ids) = 'array' and jsonb_array_length(input_message_ids) > 0),
  structured_run_ids jsonb not null check (jsonb_typeof(structured_run_ids) = 'array' and jsonb_array_length(structured_run_ids) > 0),
  output jsonb not null check (jsonb_typeof(output) = 'object'),
  coverage jsonb not null check (jsonb_typeof(coverage) = 'object'),
  created_at timestamptz not null default timezone('utc', now()),
  unique (task_id, natural_date)
);

create index summary_batches_source_date_idx on public.summary_batches (source_id, natural_date desc, created_at desc);

create table public.daily_summaries (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null references public.sources(id) on delete cascade,
  natural_date date not null,
  version integer not null check (version > 0),
  is_current boolean not null default true,
  batch_ids jsonb not null check (jsonb_typeof(batch_ids) = 'array' and jsonb_array_length(batch_ids) > 0),
  output jsonb not null check (jsonb_typeof(output) = 'object'),
  coverage jsonb not null check (jsonb_typeof(coverage) = 'object'),
  created_at timestamptz not null default timezone('utc', now()),
  unique (source_id, natural_date, version)
);

create unique index daily_summaries_current_idx
  on public.daily_summaries (source_id, natural_date) where is_current;
create index daily_summaries_reader_idx
  on public.daily_summaries (source_id, natural_date desc, version desc);

create or replace function public.claim_next_task(p_worker_id uuid, p_now timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_task public.sync_tasks%rowtype;
  v_attempt integer;
  v_checkpoint text;
  v_lease_expires_at timestamptz;
begin
  if not exists (
    select 1 from public.workers
    where id = p_worker_id and status in ('enrolled', 'online')
  ) then
    raise exception 'worker_not_authorized' using errcode = '42501';
  end if;

  select t.* into v_task
  from public.sync_tasks t
  join public.sources s on s.id = t.source_id and s.enabled
  where (
    t.status = 'queued'
    or (t.status in ('leased', 'running') and t.lease_expires_at <= p_now)
  )
    and (s.authorized_worker_id is null or s.authorized_worker_id = p_worker_id)
  order by t.queued_at, t.id
  for update of t skip locked
  limit 1;

  if not found then
    return null;
  end if;

  update public.task_attempts
  set status = 'retryable_failed', completed_at = p_now
  where task_id = v_task.id
    and status in ('leased', 'running')
    and lease_expires_at <= p_now;

  select coalesce(max(attempt), 0) + 1 into v_attempt
  from public.task_attempts
  where task_id = v_task.id;

  v_lease_expires_at := p_now + interval '10 minutes';

  insert into public.task_attempts (task_id, attempt, worker_id, status, lease_expires_at, started_at)
  values (v_task.id, v_attempt, p_worker_id, 'leased', v_lease_expires_at, p_now);

  update public.sync_tasks
  set status = 'leased', lease_owner = p_worker_id, lease_expires_at = v_lease_expires_at
  where id = v_task.id;

  select c.safe_checkpoint into v_checkpoint
  from public.checkpoints c
  where c.source_id = v_task.source_id;

  insert into public.task_events (task_id, attempt, event_type, occurred_at, details)
  values (
    v_task.id,
    v_attempt,
    'claimed',
    p_now,
    jsonb_build_object('worker_id', p_worker_id::text, 'lease_expires_at', v_lease_expires_at)
  );

  return jsonb_build_object(
    'contract_version', 'v0',
    'task_id', v_task.id::text,
    'attempt', v_attempt,
    'task_type', v_task.task_type,
    'source_id', (select source_key from public.sources where id = v_task.source_id),
    'parameter_version', v_task.parameter_version,
    'lease_expires_at', v_lease_expires_at,
    'safe_checkpoint', v_checkpoint,
    'rule_snapshot', v_task.rule_snapshot,
    'collection_scope', v_task.collection_scope
  );
end;
$$;

alter function public.persist_worker_execution(uuid, integer, uuid, jsonb)
  rename to persist_worker_execution_v0;

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
  v_source public.sources%rowtype;
  v_batch record;
  v_batch_id uuid;
  v_existing public.summary_batches%rowtype;
  v_batch_run_ids jsonb;
  v_batch_ids jsonb := '[]'::jsonb;
  v_daily_ids jsonb := '[]'::jsonb;
  v_new_dates date[] := array[]::date[];
  v_date date;
  v_daily_version integer;
  v_daily_id uuid;
  v_daily_batches jsonb;
  v_daily_output jsonb;
  v_daily_coverage jsonb;
begin
  v_result := public.persist_worker_execution_v0(p_task_id, p_attempt, p_worker_id, p_payload);

  select t.* into v_task from public.sync_tasks t where t.id = p_task_id;
  select s.* into v_source from public.sources s where s.id = v_task.source_id;

  if jsonb_typeof(coalesce(p_payload->'batch_summaries', '[]'::jsonb)) <> 'array' then
    raise exception 'invalid_batch_summaries' using errcode = '22023';
  end if;

  for v_batch in
    select *
    from jsonb_to_recordset(coalesce(p_payload->'batch_summaries', '[]'::jsonb)) as batch(
      natural_date date,
      input_message_ids jsonb,
      structured_run_keys jsonb,
      output jsonb,
      coverage jsonb
    )
  loop
    if v_batch.natural_date is null
       or jsonb_typeof(v_batch.input_message_ids) <> 'array'
       or jsonb_array_length(v_batch.input_message_ids) = 0
       or jsonb_typeof(v_batch.structured_run_keys) <> 'array'
       or jsonb_array_length(v_batch.structured_run_keys) = 0
       or jsonb_typeof(v_batch.output) <> 'object'
       or jsonb_typeof(v_batch.coverage) <> 'object' then
      raise exception 'invalid_batch_summary' using errcode = '22023';
    end if;

    if exists (
      select 1
      from jsonb_array_elements_text(v_batch.input_message_ids) as input(external_message_id)
      left join public.canonical_messages canonical
        on canonical.source_id = v_source.id and canonical.external_message_id = input.external_message_id
      where canonical.id is null
         or canonical.occurred_at is null
         or (canonical.occurred_at at time zone 'UTC')::date <> v_batch.natural_date
    ) then
      raise exception 'invalid_batch_message_evidence' using errcode = '22023';
    end if;

    select coalesce(jsonb_agg(to_jsonb(run.id::text) order by key.ordinality), '[]'::jsonb)
    into v_batch_run_ids
    from jsonb_array_elements_text(v_batch.structured_run_keys) with ordinality as key(chunk_key, ordinality)
    left join public.structured_runs run
      on run.task_id = p_task_id
     and run.attempt = p_attempt
     and run.chunk_key = key.chunk_key;

    if jsonb_array_length(v_batch_run_ids) <> jsonb_array_length(v_batch.structured_run_keys)
       or exists (
         select 1
         from jsonb_array_elements(v_batch_run_ids) as run_id(value)
         where run_id.value = 'null'::jsonb
       ) then
      raise exception 'invalid_batch_run_evidence' using errcode = '22023';
    end if;

    if exists (
      select 1
      from jsonb_array_elements_text(v_batch.input_message_ids) as input(external_message_id)
      where not exists (
        select 1
        from jsonb_array_elements_text(v_batch_run_ids) as selected(run_id)
        join public.structured_runs run on run.id::text = selected.run_id
        where run.input_message_ids ? input.external_message_id
      )
    ) then
      raise exception 'batch_message_not_structured' using errcode = '22023';
    end if;

    select * into v_existing
    from public.summary_batches
    where task_id = p_task_id and natural_date = v_batch.natural_date
    for update;

    if found then
      if v_existing.source_id <> v_source.id
         or v_existing.input_message_ids <> v_batch.input_message_ids
         or v_existing.structured_run_ids <> v_batch_run_ids
         or v_existing.output <> v_batch.output
         or v_existing.coverage <> v_batch.coverage then
        raise exception 'conflicting_batch_summary' using errcode = '23505';
      end if;
      v_batch_id := v_existing.id;
    else
      insert into public.summary_batches (
        task_id, source_id, natural_date, input_message_ids, structured_run_ids, output, coverage
      ) values (
        p_task_id, v_source.id, v_batch.natural_date, v_batch.input_message_ids, v_batch_run_ids, v_batch.output, v_batch.coverage
      ) returning id into v_batch_id;
      if not v_batch.natural_date = any(v_new_dates) then
        v_new_dates := array_append(v_new_dates, v_batch.natural_date);
      end if;
    end if;
    v_batch_ids := v_batch_ids || to_jsonb(v_batch_id::text);
  end loop;

  foreach v_date in array v_new_dates
  loop
    select coalesce(jsonb_agg(to_jsonb(batch.id::text) order by batch.created_at), '[]'::jsonb),
           coalesce(jsonb_agg(jsonb_build_object('batch_id', batch.id::text, 'output', batch.output) order by batch.created_at), '[]'::jsonb),
           jsonb_build_object(
             'batch_count', count(*)::integer,
             'unparsed_media', coalesce(bool_or(coalesce((batch.coverage->>'unparsed_media')::boolean, false)), false)
           )
    into v_daily_batches, v_daily_output, v_daily_coverage
    from public.summary_batches batch
    where batch.source_id = v_source.id and batch.natural_date = v_date;

    update public.daily_summaries
    set is_current = false
    where source_id = v_source.id and natural_date = v_date and is_current;

    select coalesce(max(version), 0) + 1 into v_daily_version
    from public.daily_summaries
    where source_id = v_source.id and natural_date = v_date;

    insert into public.daily_summaries (
      source_id, natural_date, version, is_current, batch_ids, output, coverage
    ) values (
      v_source.id,
      v_date,
      v_daily_version,
      true,
      v_daily_batches,
      jsonb_build_object('natural_date', v_date::text, 'batches', v_daily_output),
      v_daily_coverage
    ) returning id into v_daily_id;
    v_daily_ids := v_daily_ids || to_jsonb(v_daily_id::text);
  end loop;

  return v_result || jsonb_build_object(
    'summary_batch_ids', v_batch_ids,
    'daily_summary_ids', v_daily_ids
  );
end;
$$;

grant select, insert, update, delete on public.source_author_rules, public.summary_batches, public.daily_summaries to authenticated, service_role;
grant execute on function public.persist_worker_execution(uuid, integer, uuid, jsonb) to service_role;

alter table public.source_author_rules enable row level security;
alter table public.summary_batches enable row level security;
alter table public.daily_summaries enable row level security;

create policy source_author_rules_admin_all on public.source_author_rules
for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy summary_batches_authenticated_select on public.summary_batches
for select to authenticated using (true);
create policy summary_batches_admin_all on public.summary_batches
for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy daily_summaries_authenticated_select on public.daily_summaries
for select to authenticated using (true);
create policy daily_summaries_admin_all on public.daily_summaries
for all to authenticated using (public.is_admin()) with check (public.is_admin());

revoke all on function public.persist_worker_execution(uuid, integer, uuid, jsonb) from public, anon, authenticated;
revoke all on function public.persist_worker_execution_v0(uuid, integer, uuid, jsonb) from public, anon, authenticated;
