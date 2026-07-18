alter table public.structured_runs
  add column attempt integer not null default 1 check (attempt > 0),
  add column chunk_key text not null default 'legacy',
  add column input_message_ids jsonb not null default '[]'::jsonb check (jsonb_typeof(input_message_ids) = 'array');

alter table public.structured_runs
  add constraint structured_runs_task_attempt_chunk_key_key unique (task_id, attempt, chunk_key);

create table public.worker_execution_receipts (
  task_id uuid not null references public.sync_tasks(id) on delete cascade,
  attempt integer not null check (attempt > 0),
  worker_id uuid not null references public.workers(id) on delete restrict,
  payload_digest text not null,
  raw_count integer not null check (raw_count >= 0),
  canonical_count integer not null check (canonical_count >= 0),
  structured_run_ids jsonb not null check (jsonb_typeof(structured_run_ids) = 'array'),
  created_at timestamptz not null default timezone('utc', now()),
  primary key (task_id, attempt)
);

create or replace function public.persist_worker_execution(
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
  v_task public.sync_tasks%rowtype;
  v_attempt public.task_attempts%rowtype;
  v_source public.sources%rowtype;
  v_struct record;
  v_run_id uuid;
  v_run_ids jsonb := '[]'::jsonb;
  v_inserted boolean := false;
  v_existing_count integer;
  v_payload_digest text;
  v_receipt public.worker_execution_receipts%rowtype;
begin
  select * into v_task from public.sync_tasks where id = p_task_id for update;
  select * into v_attempt from public.task_attempts
  where task_id = p_task_id and attempt = p_attempt for update;

  if v_task.id is null or v_attempt.id is null
     or v_task.lease_owner <> p_worker_id
     or v_attempt.worker_id <> p_worker_id
     or v_task.status not in ('leased', 'running')
     or v_attempt.status not in ('leased', 'running')
     or v_attempt.lease_expires_at <= timezone('utc', now()) then
    raise exception 'lease_mismatch' using errcode = '40001';
  end if;

  select * into v_source from public.sources where id = v_task.source_id;
  if p_payload->>'task_id' <> p_task_id::text
     or coalesce((p_payload->>'attempt')::integer, 0) <> p_attempt
     or p_payload->>'source_id' <> v_source.source_key then
    raise exception 'invalid_worker_persistence' using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(coalesce(p_payload->'raw_messages', '[]'::jsonb)) as raw(external_message_id text)
    full join jsonb_to_recordset(coalesce(p_payload->'canonical_messages', '[]'::jsonb)) as canonical(external_message_id text)
      using (external_message_id)
    where raw.external_message_id is null or canonical.external_message_id is null
  ) then
    raise exception 'raw_canonical_mismatch' using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(coalesce(p_payload->'raw_messages', '[]'::jsonb)) as incoming(
      external_message_id text,
      local_raw_ref text,
      payload_hash text
    )
    join public.raw_messages existing
      on existing.source_id = v_source.id and existing.external_message_id = incoming.external_message_id
    where existing.local_raw_ref <> incoming.local_raw_ref
       or existing.payload_hash <> incoming.payload_hash
  ) then
    raise exception 'conflicting_raw_message' using errcode = '23505';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(coalesce(p_payload->'canonical_messages', '[]'::jsonb)) as incoming(
      external_message_id text,
      content text,
      has_unparsed_media boolean,
      metadata jsonb
    )
    join public.canonical_messages existing
      on existing.source_id = v_source.id and existing.external_message_id = incoming.external_message_id
    where existing.content <> incoming.content
       or existing.has_unparsed_media <> incoming.has_unparsed_media
       or existing.metadata <> incoming.metadata
  ) then
    raise exception 'conflicting_canonical_message' using errcode = '23505';
  end if;

  insert into public.raw_messages (
    source_id, external_message_id, occurred_at, local_raw_ref, payload_hash, retention_expires_at
  )
  select
    v_source.id,
    raw.external_message_id,
    raw.occurred_at,
    raw.local_raw_ref,
    raw.payload_hash,
    raw.retention_expires_at
  from jsonb_to_recordset(coalesce(p_payload->'raw_messages', '[]'::jsonb)) as raw(
    external_message_id text,
    occurred_at timestamptz,
    local_raw_ref text,
    payload_hash text,
    retention_expires_at timestamptz
  )
  on conflict (source_id, external_message_id) do nothing;

  insert into public.canonical_messages (
    source_id, external_message_id, occurred_at, author_display, content, has_unparsed_media, metadata
  )
  select
    v_source.id,
    canonical.external_message_id,
    canonical.occurred_at,
    canonical.author_display,
    canonical.content,
    canonical.has_unparsed_media,
    canonical.metadata
  from jsonb_to_recordset(coalesce(p_payload->'canonical_messages', '[]'::jsonb)) as canonical(
    external_message_id text,
    occurred_at timestamptz,
    author_display text,
    content text,
    has_unparsed_media boolean,
    metadata jsonb
  )
  on conflict (source_id, external_message_id) do nothing;

  for v_struct in
    select *
    from jsonb_to_recordset(coalesce(p_payload->'structured_runs', '[]'::jsonb)) as run(
      chunk_key text,
      provider text,
      parameter_version text,
      input_message_ids jsonb,
      media_source_message_ids jsonb,
      output jsonb
    )
  loop
    if exists (
      select 1
      from jsonb_array_elements_text(v_struct.input_message_ids) as input(external_message_id)
      left join public.canonical_messages canonical
        on canonical.source_id = v_source.id and canonical.external_message_id = input.external_message_id
      where canonical.id is null
    ) or exists (
      select 1
      from jsonb_array_elements_text(v_struct.media_source_message_ids) as media(external_message_id)
      left join public.canonical_messages canonical
        on canonical.source_id = v_source.id
       and canonical.external_message_id = media.external_message_id
       and canonical.has_unparsed_media
      where canonical.id is null
    ) then
      raise exception 'invalid_evidence_reference' using errcode = '22023';
    end if;

    select id into v_run_id
    from public.structured_runs
    where task_id = p_task_id and attempt = p_attempt and chunk_key = v_struct.chunk_key;

    if found then
      if exists (
        select 1
        from public.structured_runs
        where id = v_run_id
          and (provider <> v_struct.provider or parameter_version <> v_struct.parameter_version
            or input_message_ids <> v_struct.input_message_ids or output <> v_struct.output)
      ) then
        raise exception 'conflicting_structured_run' using errcode = '23505';
      end if;
    else
      insert into public.structured_runs (
        task_id, attempt, chunk_key, provider, parameter_version, input_message_ids, output
      ) values (
        p_task_id, p_attempt, v_struct.chunk_key, v_struct.provider, v_struct.parameter_version,
        v_struct.input_message_ids, v_struct.output
      ) returning id into v_run_id;
      v_inserted := true;
    end if;

    insert into public.evidence_refs (structured_run_id, canonical_message_id, evidence_kind)
    select v_run_id, canonical.id, 'message'
    from jsonb_array_elements_text(v_struct.input_message_ids) as input(external_message_id)
    join public.canonical_messages canonical
      on canonical.source_id = v_source.id and canonical.external_message_id = input.external_message_id
    on conflict (structured_run_id, canonical_message_id, evidence_kind) do nothing;

    insert into public.evidence_refs (structured_run_id, canonical_message_id, evidence_kind)
    select v_run_id, canonical.id, 'unparsed_media'
    from jsonb_array_elements_text(v_struct.media_source_message_ids) as media(external_message_id)
    join public.canonical_messages canonical
      on canonical.source_id = v_source.id and canonical.external_message_id = media.external_message_id
    on conflict (structured_run_id, canonical_message_id, evidence_kind) do nothing;

    insert into public.evidence_refs (structured_run_id, canonical_message_id, evidence_kind, local_raw_ref)
    select v_run_id, canonical.id, 'local_raw_ref', raw.local_raw_ref
    from jsonb_array_elements_text(v_struct.input_message_ids) as input(external_message_id)
    join public.canonical_messages canonical
      on canonical.source_id = v_source.id and canonical.external_message_id = input.external_message_id
    join public.raw_messages raw
      on raw.source_id = v_source.id and raw.external_message_id = input.external_message_id
    on conflict (structured_run_id, canonical_message_id, evidence_kind) do nothing;

    v_run_ids := v_run_ids || to_jsonb(v_run_id::text);
  end loop;

  select count(*) into v_existing_count
  from public.structured_runs
  where task_id = p_task_id and attempt = p_attempt;
  if v_existing_count <> jsonb_array_length(coalesce(p_payload->'structured_runs', '[]'::jsonb)) then
    raise exception 'structured_run_mismatch' using errcode = '22023';
  end if;

  v_payload_digest := encode(digest(p_payload::text, 'sha256'), 'hex');
  select * into v_receipt
  from public.worker_execution_receipts
  where task_id = p_task_id and attempt = p_attempt
  for update;

  if found then
    if v_receipt.worker_id <> p_worker_id
       or v_receipt.payload_digest <> v_payload_digest
       or v_receipt.raw_count <> jsonb_array_length(coalesce(p_payload->'raw_messages', '[]'::jsonb))
       or v_receipt.canonical_count <> jsonb_array_length(coalesce(p_payload->'canonical_messages', '[]'::jsonb))
       or v_receipt.structured_run_ids <> v_run_ids then
      raise exception 'conflicting_persistence_receipt' using errcode = '23505';
    end if;
  else
    insert into public.worker_execution_receipts (
      task_id, attempt, worker_id, payload_digest, raw_count, canonical_count, structured_run_ids
    ) values (
      p_task_id,
      p_attempt,
      p_worker_id,
      v_payload_digest,
      jsonb_array_length(coalesce(p_payload->'raw_messages', '[]'::jsonb)),
      jsonb_array_length(coalesce(p_payload->'canonical_messages', '[]'::jsonb)),
      v_run_ids
    );
    v_inserted := true;
  end if;

  return jsonb_build_object(
    'persisted', true,
    'idempotent', not v_inserted,
    'structured_run_ids', v_run_ids
  );
end;
$$;

create or replace function public.accept_task_result(
  p_task_id uuid,
  p_attempt integer,
  p_result jsonb,
  p_context jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_task public.sync_tasks%rowtype;
  v_attempt public.task_attempts%rowtype;
  v_receipt public.worker_execution_receipts%rowtype;
  v_worker_id uuid;
  v_checkpoint text;
begin
  begin
    v_worker_id := nullif(p_context->>'worker_id', '')::uuid;
  exception when invalid_text_representation then
    raise exception 'worker_not_authorized' using errcode = '42501';
  end;

  if v_worker_id is null or coalesce((p_context->>'persisted')::boolean, false) is not true then
    raise exception 'persistence_not_confirmed' using errcode = '55000';
  end if;

  select * into v_task from public.sync_tasks where id = p_task_id for update;
  select * into v_attempt from public.task_attempts
  where task_id = p_task_id and attempt = p_attempt for update;

  if not found then
    raise exception 'attempt_not_found' using errcode = '22023';
  end if;

  if v_attempt.status = 'succeeded' then
    if v_attempt.result = p_result then
      return jsonb_build_object('status', 'succeeded', 'idempotent', true, 'task_id', p_task_id::text, 'attempt', p_attempt);
    end if;
    raise exception 'conflicting_duplicate_result' using errcode = '23505';
  end if;

  if v_task.id is null
     or v_attempt.worker_id <> v_worker_id
     or v_task.lease_owner <> v_worker_id
     or v_attempt.status not in ('leased', 'running')
     or v_task.status not in ('leased', 'running')
     or v_attempt.lease_expires_at <= timezone('utc', now()) then
    raise exception 'lease_mismatch' using errcode = '40001';
  end if;

  select * into v_receipt
  from public.worker_execution_receipts
  where task_id = p_task_id and attempt = p_attempt and worker_id = v_worker_id;

  if not found
     or v_receipt.raw_count <> coalesce((p_result->>'raw_count')::integer, -1)
     or v_receipt.canonical_count <> coalesce((p_result->>'canonical_count')::integer, -1)
     or v_receipt.structured_run_ids <> coalesce(p_result->'structured_run_ids', '[]'::jsonb) then
    raise exception 'persistence_not_confirmed' using errcode = '55000';
  end if;

  if p_result->>'status' <> 'succeeded' then
    raise exception 'invalid_task_result' using errcode = '22023';
  end if;

  v_checkpoint := p_result->>'safe_checkpoint';

  update public.task_attempts
  set status = 'succeeded', result = p_result, completed_at = timezone('utc', now())
  where id = v_attempt.id;

  update public.sync_tasks
  set status = 'succeeded', last_checkpoint = v_checkpoint, lease_owner = null, lease_expires_at = null
  where id = v_task.id;

  insert into public.checkpoints (source_id, safe_checkpoint, version, updated_by_task_id)
  values (v_task.source_id, v_checkpoint, 1, v_task.id)
  on conflict (source_id) do update
  set safe_checkpoint = excluded.safe_checkpoint,
      version = public.checkpoints.version + 1,
      updated_by_task_id = excluded.updated_by_task_id,
      updated_at = timezone('utc', now());

  insert into public.task_events (task_id, attempt, event_type, occurred_at, details)
  values (
    p_task_id,
    p_attempt,
    'succeeded',
    timezone('utc', now()),
    jsonb_build_object('safe_checkpoint', v_checkpoint)
  );

  return jsonb_build_object('status', 'succeeded', 'idempotent', false, 'task_id', p_task_id::text, 'attempt', p_attempt);
end;
$$;

grant execute on function public.persist_worker_execution(uuid, integer, uuid, jsonb) to service_role;
grant select, insert, update, delete on public.worker_execution_receipts to service_role;
alter table public.worker_execution_receipts enable row level security;
create policy worker_execution_receipts_admin_all on public.worker_execution_receipts
for all to authenticated using (public.is_admin()) with check (public.is_admin());
revoke all on function public.persist_worker_execution(uuid, integer, uuid, jsonb) from public, anon, authenticated;
