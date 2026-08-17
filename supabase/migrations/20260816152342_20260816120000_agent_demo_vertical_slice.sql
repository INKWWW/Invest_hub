create table public.agent_demo_runs (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  thread_id uuid not null,
  request_id text not null check (length(btrim(request_id)) between 1 and 200),
  user_message_id uuid not null,
  assistant_message_id uuid,
  worker_id uuid references public.workers(id) on delete set null,
  question text not null check (length(btrim(question)) between 1 and 20000),
  invocation_mode text not null default 'auto' check (invocation_mode in ('explicit', 'auto')),
  skill_id text check (skill_id is null or skill_id in ('investment-research', 'portfolio-review', 'investment-checklist')),
  status text not null default 'queued' check (status in ('queued', 'running', 'succeeded', 'failed')),
  provider text,
  failure_code text,
  created_at timestamptz not null default timezone('utc', now()),
  started_at timestamptz,
  completed_at timestamptz,
  updated_at timestamptz not null default timezone('utc', now()),
  unique (id, owner_id),
  unique (user_message_id),
  unique (assistant_message_id),
  unique (owner_id, request_id),
  foreign key (thread_id, owner_id) references public.research_threads(id, owner_id) on delete cascade,
  foreign key (user_message_id) references public.research_messages(id) on delete cascade,
  foreign key (assistant_message_id) references public.research_messages(id) on delete set null
);

create index agent_demo_runs_owner_created_idx
  on public.agent_demo_runs (owner_id, created_at desc, id desc);
create index agent_demo_runs_owner_request_idx
  on public.agent_demo_runs (owner_id, request_id);
create unique index agent_demo_runs_one_active_idx
  on public.agent_demo_runs ((1))
  where status in ('queued', 'running');

create trigger agent_demo_runs_set_updated_at
before update on public.agent_demo_runs
for each row execute function public.set_updated_at();

alter table public.agent_demo_runs enable row level security;
grant select on public.agent_demo_runs to authenticated;
grant select, insert, update on public.agent_demo_runs to service_role;

create policy agent_demo_runs_owner_select on public.agent_demo_runs
for select to authenticated using (owner_id = auth.uid());

create or replace function public.admit_agent_demo_run(
  p_owner_id uuid,
  p_thread_id uuid,
  p_request_id text,
  p_question text,
  p_invocation_mode text default 'auto',
  p_skill_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_existing public.agent_demo_runs%rowtype;
  v_message public.research_messages%rowtype;
  v_run public.agent_demo_runs%rowtype;
begin
  if p_request_id is null or length(btrim(p_request_id)) not between 1 and 200
     or p_question is null or length(btrim(p_question)) not between 1 and 20000
     or p_invocation_mode not in ('explicit', 'auto')
     or p_skill_id is not null and p_skill_id not in ('investment-research', 'portfolio-review', 'investment-checklist')
     or p_invocation_mode = 'explicit' and p_skill_id is null then
    raise exception 'invalid_demo_message' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('invest-hub-agent-demo-global', 0));
  select * into v_existing
  from public.agent_demo_runs
  where owner_id = p_owner_id and request_id = btrim(p_request_id)
  for update;
  if found then
    if auth.uid() is distinct from p_owner_id then
      raise exception 'demo_owner_forbidden' using errcode = '42501';
    end if;
    if v_existing.thread_id is distinct from p_thread_id or v_existing.question is distinct from btrim(p_question) then
      raise exception 'demo_request_conflict' using errcode = 'P0001';
    end if;
    return jsonb_build_object(
      'idempotent', true, 'run_id', v_existing.id, 'user_message_id', v_existing.user_message_id,
      'assistant_message_id', v_existing.assistant_message_id, 'status', v_existing.status,
      'invocation_mode', v_existing.invocation_mode, 'skill_id', v_existing.skill_id,
      'created_at', v_existing.created_at, 'started_at', v_existing.started_at,
      'completed_at', v_existing.completed_at
    );
  end if;

  if exists (select 1 from public.agent_demo_runs where status in ('queued', 'running')) then
    raise exception 'demo_runner_busy' using errcode = 'P0001';
  end if;
  if auth.uid() is distinct from p_owner_id then
    raise exception 'demo_owner_forbidden' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.workers w
    where w.status = 'online'
      and w.last_heartbeat_at between timezone('utc', now()) - interval '2 minutes' and timezone('utc', now()) + interval '2 minutes'
  ) then
    raise exception 'demo_runner_unavailable' using errcode = 'P0001';
  end if;

  insert into public.research_messages (thread_id, owner_id, role, content)
  values (p_thread_id, p_owner_id, 'user', btrim(p_question))
  returning * into v_message;

  insert into public.agent_demo_runs (owner_id, thread_id, request_id, user_message_id, question, invocation_mode, skill_id)
  values (p_owner_id, p_thread_id, btrim(p_request_id), v_message.id, btrim(p_question), p_invocation_mode, p_skill_id)
  returning * into v_run;

  return jsonb_build_object(
    'idempotent', false, 'run_id', v_run.id, 'user_message_id', v_run.user_message_id,
    'assistant_message_id', null, 'status', v_run.status, 'invocation_mode', v_run.invocation_mode,
    'skill_id', v_run.skill_id, 'created_at', v_run.created_at,
    'started_at', null, 'completed_at', null
  );
end;
$$;

revoke all on function public.admit_agent_demo_run(uuid, uuid, text, text, text, text) from public, anon;
grant execute on function public.admit_agent_demo_run(uuid, uuid, text, text, text, text) to authenticated;

create or replace function public.claim_agent_demo_run(p_run_id uuid, p_worker_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_run public.agent_demo_runs%rowtype;
begin
  update public.agent_demo_runs
  set status = 'running', worker_id = p_worker_id, started_at = coalesce(started_at, timezone('utc', now()))
  where id = p_run_id and status = 'queued' and exists (
    select 1 from public.workers w
    where w.id = p_worker_id and w.status = 'online'
      and w.last_heartbeat_at between timezone('utc', now()) - interval '2 minutes' and timezone('utc', now()) + interval '2 minutes'
  )
  returning * into v_run;
  if not found then return null; end if;
  return jsonb_build_object(
    'run_id', v_run.id, 'owner_id', v_run.owner_id, 'thread_id', v_run.thread_id,
    'user_message_id', v_run.user_message_id, 'question', v_run.question,
    'invocation_mode', v_run.invocation_mode, 'skill_id', v_run.skill_id,
    'status', v_run.status, 'started_at', v_run.started_at,
    'history', coalesce((select jsonb_agg(jsonb_build_object('role', m.role, 'content', m.content) order by m.created_at, m.id)
      from public.research_messages m where m.thread_id = v_run.thread_id and m.owner_id = v_run.owner_id), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.claim_agent_demo_run(uuid, uuid) from public, anon, authenticated;
grant execute on function public.claim_agent_demo_run(uuid, uuid) to service_role;

create or replace function public.complete_agent_demo_run(
  p_run_id uuid,
  p_worker_id uuid,
  p_content text,
  p_provider text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_run public.agent_demo_runs%rowtype;
  v_message public.research_messages%rowtype;
begin
  if p_content is null or length(btrim(p_content)) not between 1 and 20000
     or p_provider is null or length(btrim(p_provider)) < 1
     or lower(p_content) like '%/users/%' or lower(p_content) like '%/home/%'
     or lower(p_content) like '%/private/%' or lower(p_content) like '%/tmp/%' then
    raise exception 'invalid_demo_completion' using errcode = '22023';
  end if;
  select * into v_run from public.agent_demo_runs where id = p_run_id and worker_id = p_worker_id for update;
  if not found then raise exception 'demo_run_not_found' using errcode = 'P0001'; end if;
  if v_run.status <> 'running' then raise exception 'demo_run_not_running' using errcode = 'P0001'; end if;

  insert into public.research_messages (thread_id, owner_id, role, content)
  values (v_run.thread_id, v_run.owner_id, 'assistant', btrim(p_content))
  returning * into v_message;

  update public.agent_demo_runs
  set status = 'succeeded', provider = btrim(p_provider), assistant_message_id = v_message.id,
      completed_at = timezone('utc', now()), updated_at = timezone('utc', now())
  where id = v_run.id
  returning * into v_run;

  return jsonb_build_object(
    'run_id', v_run.id, 'assistant_message_id', v_run.assistant_message_id,
    'status', v_run.status, 'provider', v_run.provider, 'completed_at', v_run.completed_at
  );
end;
$$;

revoke all on function public.complete_agent_demo_run(uuid, uuid, text, text) from public, anon, authenticated;
grant execute on function public.complete_agent_demo_run(uuid, uuid, text, text) to service_role;
