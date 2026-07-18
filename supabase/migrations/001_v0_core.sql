create extension if not exists pgcrypto;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'user' check (role in ('admin', 'user')),
  display_name text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table public.invites (
  id uuid primary key default gen_random_uuid(),
  code_hash text not null unique,
  role text not null default 'user' check (role in ('admin', 'user')),
  purpose text not null default 'user' check (purpose in ('user', 'worker')),
  created_by uuid references public.profiles(id) on delete set null,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  consumed_by uuid,
  created_at timestamptz not null default timezone('utc', now()),
  check ((consumed_at is null and consumed_by is null) or (consumed_at is not null and consumed_by is not null))
);

create table public.workers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  device_secret_hash text not null unique,
  status text not null default 'enrolled' check (status in ('enrolled', 'online', 'offline', 'revoked')),
  last_heartbeat_at timestamptz,
  enrolled_at timestamptz not null default timezone('utc', now()),
  revoked_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table public.sources (
  id uuid primary key default gen_random_uuid(),
  source_key text not null unique,
  source_type text not null check (source_type = 'discord'),
  display_name text not null,
  parameter_version text not null,
  enabled boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table public.sync_tasks (
  id uuid primary key default gen_random_uuid(),
  task_type text not null check (task_type = 'discord_sync'),
  source_id uuid not null references public.sources(id) on delete restrict,
  status text not null default 'queued' check (status in ('queued', 'leased', 'running', 'retryable_failed', 'succeeded', 'failed', 'cancelled')),
  parameter_version text not null,
  requested_by uuid references auth.users(id) on delete set null,
  queued_at timestamptz not null default timezone('utc', now()),
  lease_owner uuid references public.workers(id) on delete set null,
  lease_expires_at timestamptz,
  last_checkpoint text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table public.task_attempts (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.sync_tasks(id) on delete cascade,
  attempt integer not null check (attempt > 0),
  worker_id uuid not null references public.workers(id) on delete restrict,
  status text not null check (status in ('leased', 'running', 'succeeded', 'retryable_failed', 'failed')),
  lease_expires_at timestamptz not null,
  result jsonb,
  failure jsonb,
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (task_id, attempt)
);

create table public.checkpoints (
  source_id uuid primary key references public.sources(id) on delete cascade,
  safe_checkpoint text,
  version bigint not null default 0 check (version >= 0),
  updated_by_task_id uuid references public.sync_tasks(id) on delete set null,
  updated_at timestamptz not null default timezone('utc', now())
);

create table public.raw_messages (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null references public.sources(id) on delete cascade,
  external_message_id text not null,
  occurred_at timestamptz,
  local_raw_ref text not null,
  payload_hash text not null,
  retention_expires_at timestamptz not null,
  created_at timestamptz not null default timezone('utc', now()),
  unique (source_id, external_message_id)
);

create table public.canonical_messages (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null references public.sources(id) on delete cascade,
  external_message_id text not null,
  occurred_at timestamptz,
  author_display text,
  content text not null,
  has_unparsed_media boolean not null default false,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default timezone('utc', now()),
  unique (source_id, external_message_id)
);

create table public.structured_runs (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.sync_tasks(id) on delete cascade,
  provider text not null check (provider in ('mock', 'codex_cli')),
  parameter_version text not null,
  output jsonb not null check (jsonb_typeof(output) = 'object'),
  created_at timestamptz not null default timezone('utc', now())
);

create table public.evidence_refs (
  id uuid primary key default gen_random_uuid(),
  structured_run_id uuid not null references public.structured_runs(id) on delete cascade,
  canonical_message_id uuid not null references public.canonical_messages(id) on delete cascade,
  evidence_kind text not null check (evidence_kind in ('message', 'unparsed_media', 'local_raw_ref')),
  local_raw_ref text,
  created_at timestamptz not null default timezone('utc', now()),
  unique (structured_run_id, canonical_message_id, evidence_kind)
);

create table public.task_events (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.sync_tasks(id) on delete cascade,
  attempt integer not null check (attempt > 0),
  event_type text not null check (event_type in ('claimed', 'heartbeat', 'phase_started', 'phase_completed', 'retry', 'checkpoint_safe', 'failed', 'succeeded')),
  occurred_at timestamptz not null default timezone('utc', now()),
  details jsonb not null default '{}'::jsonb check (jsonb_typeof(details) = 'object'),
  created_at timestamptz not null default timezone('utc', now())
);

create index sync_tasks_claim_idx on public.sync_tasks (status, queued_at, lease_expires_at);
create index task_attempts_task_idx on public.task_attempts (task_id, attempt desc);
create index task_events_task_idx on public.task_events (task_id, occurred_at);
create index canonical_messages_source_time_idx on public.canonical_messages (source_id, occurred_at);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

create trigger profiles_set_updated_at before update on public.profiles
for each row execute function public.set_updated_at();
create trigger workers_set_updated_at before update on public.workers
for each row execute function public.set_updated_at();
create trigger sources_set_updated_at before update on public.sources
for each row execute function public.set_updated_at();
create trigger sync_tasks_set_updated_at before update on public.sync_tasks
for each row execute function public.set_updated_at();
create trigger task_attempts_set_updated_at before update on public.task_attempts
for each row execute function public.set_updated_at();

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

create or replace function public.consume_invite(
  p_code_hash text,
  p_purpose text,
  p_user_id uuid,
  p_now timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_invite public.invites%rowtype;
begin
  update public.invites
  set consumed_at = p_now, consumed_by = p_user_id
  where code_hash = p_code_hash
    and purpose = p_purpose
    and consumed_at is null
    and expires_at > p_now
  returning * into v_invite;

  if not found then
    return null;
  end if;

  return jsonb_build_object(
    'invite_id', v_invite.id::text,
    'role', v_invite.role,
    'purpose', v_invite.purpose,
    'expires_at', v_invite.expires_at
  );
end;
$$;

create or replace function public.consume_invite(
  p_code_hash text,
  p_user_id uuid,
  p_now timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  return public.consume_invite(p_code_hash, 'user', p_user_id, p_now);
end;
$$;

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

  insert into public.task_attempts (
    task_id, attempt, worker_id, status, lease_expires_at, started_at
  ) values (
    v_task.id, v_attempt, p_worker_id, 'leased', v_lease_expires_at, p_now
  );

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
    'safe_checkpoint', v_checkpoint
  );
end;
$$;

create or replace function public.renew_task_lease(
  p_task_id uuid,
  p_attempt integer,
  p_worker_id uuid,
  p_now timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_lease_expires_at timestamptz := p_now + interval '10 minutes';
begin
  update public.task_attempts
  set status = 'running', lease_expires_at = v_lease_expires_at
  where task_id = p_task_id
    and attempt = p_attempt
    and worker_id = p_worker_id
    and status in ('leased', 'running')
    and lease_expires_at > p_now;

  if not found then
    raise exception 'lease_mismatch' using errcode = '40001';
  end if;

  update public.sync_tasks
  set status = 'running', lease_expires_at = v_lease_expires_at
  where id = p_task_id and lease_owner = p_worker_id;

  insert into public.task_events (task_id, attempt, event_type, occurred_at, details)
  values (
    p_task_id,
    p_attempt,
    'heartbeat',
    p_now,
    jsonb_build_object('worker_id', p_worker_id::text, 'lease_expires_at', v_lease_expires_at)
  );

  return jsonb_build_object('task_id', p_task_id::text, 'attempt', p_attempt, 'lease_expires_at', v_lease_expires_at);
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

create or replace function public.record_task_failure(
  p_task_id uuid,
  p_attempt integer,
  p_failure jsonb,
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
  v_worker_id uuid;
  v_status text;
  v_attempt_status text;
  v_event_type text;
begin
  begin
    v_worker_id := nullif(p_context->>'worker_id', '')::uuid;
  exception when invalid_text_representation then
    raise exception 'worker_not_authorized' using errcode = '42501';
  end;

  select * into v_task from public.sync_tasks where id = p_task_id for update;
  select * into v_attempt from public.task_attempts
  where task_id = p_task_id and attempt = p_attempt for update;

  if not found then
    raise exception 'attempt_not_found' using errcode = '22023';
  end if;

  if v_attempt.status in ('failed', 'retryable_failed') then
    if v_attempt.failure = p_failure then
      return jsonb_build_object('status', v_attempt.status, 'idempotent', true, 'task_id', p_task_id::text, 'attempt', p_attempt);
    end if;
    raise exception 'conflicting_duplicate_failure' using errcode = '23505';
  end if;

  if v_task.id is null
     or v_attempt.worker_id <> v_worker_id
     or v_task.lease_owner <> v_worker_id
     or v_attempt.status not in ('leased', 'running')
     or v_task.status not in ('leased', 'running') then
    raise exception 'lease_mismatch' using errcode = '40001';
  end if;

  v_status := case
    when coalesce((p_failure->>'retryable')::boolean, false) then 'retryable_failed'
    when p_failure->>'status' = 'cancelled' then 'cancelled'
    else 'failed'
  end;
  v_attempt_status := case when v_status = 'cancelled' then 'failed' else v_status end;
  v_event_type := case when v_status = 'retryable_failed' then 'retry' else 'failed' end;

  update public.task_attempts
  set status = v_attempt_status, failure = p_failure, completed_at = timezone('utc', now())
  where id = v_attempt.id;

  update public.sync_tasks
  set status = v_status, lease_owner = null, lease_expires_at = null
  where id = v_task.id;

  insert into public.task_events (task_id, attempt, event_type, occurred_at, details)
  values (
    p_task_id,
    p_attempt,
    v_event_type,
    timezone('utc', now()),
    jsonb_build_object('failure_class', p_failure->>'failure_class', 'retryable', p_failure->>'retryable')
  );

  return jsonb_build_object('status', v_status, 'idempotent', false, 'task_id', p_task_id::text, 'attempt', p_attempt);
end;
$$;

alter table public.profiles enable row level security;
alter table public.invites enable row level security;
alter table public.workers enable row level security;
alter table public.sources enable row level security;
alter table public.sync_tasks enable row level security;
alter table public.task_attempts enable row level security;
alter table public.checkpoints enable row level security;
alter table public.raw_messages enable row level security;
alter table public.canonical_messages enable row level security;
alter table public.structured_runs enable row level security;
alter table public.evidence_refs enable row level security;
alter table public.task_events enable row level security;

grant usage on schema public to authenticated, service_role;
grant select, insert, update, delete on all tables in schema public to authenticated, service_role;
grant usage, select on all sequences in schema public to authenticated, service_role;
grant execute on function public.is_admin() to authenticated, service_role;
grant execute on function public.consume_invite(text, uuid, timestamptz) to service_role;
grant execute on function public.consume_invite(text, text, uuid, timestamptz) to service_role;
grant execute on function public.claim_next_task(uuid, timestamptz) to service_role;
grant execute on function public.renew_task_lease(uuid, integer, uuid, timestamptz) to service_role;
grant execute on function public.accept_task_result(uuid, integer, jsonb, jsonb) to service_role;
grant execute on function public.record_task_failure(uuid, integer, jsonb, jsonb) to service_role;

create policy profiles_self_select on public.profiles
for select to authenticated using (id = auth.uid());
create policy profiles_admin_all on public.profiles
for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy invites_admin_all on public.invites
for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy workers_admin_all on public.workers
for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy sources_admin_all on public.sources
for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy sync_tasks_admin_all on public.sync_tasks
for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy task_attempts_admin_all on public.task_attempts
for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy checkpoints_admin_all on public.checkpoints
for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy raw_messages_admin_all on public.raw_messages
for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy canonical_messages_admin_all on public.canonical_messages
for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy structured_runs_admin_all on public.structured_runs
for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy evidence_refs_admin_all on public.evidence_refs
for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy task_events_admin_all on public.task_events
for all to authenticated using (public.is_admin()) with check (public.is_admin());

revoke all on function public.claim_next_task(uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.consume_invite(text, uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.consume_invite(text, text, uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.renew_task_lease(uuid, integer, uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.accept_task_result(uuid, integer, jsonb, jsonb) from public, anon, authenticated;
revoke all on function public.record_task_failure(uuid, integer, jsonb, jsonb) from public, anon, authenticated;
