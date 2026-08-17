-- Agent Demo claims require the explicit capability; X-only workers must not
-- receive user research context through this privileged RPC.
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
    where w.id = p_worker_id
      and w.status = 'online'
      and 'agent_demo' = any(w.capabilities)
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
