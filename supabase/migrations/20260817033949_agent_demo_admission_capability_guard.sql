-- Admission and claim must use the same explicit Agent Demo capability.
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
      and 'agent_demo' = any(w.capabilities)
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
