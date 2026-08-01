-- New batch dispatch remains tied to current enabled/resolved sources, while
-- claim authorization for immutable batches follows their frozen source set.
-- Archiving a source/profile after freeze must not strand already queued work.

create function public.x_daily_judgement_worker_is_frozen_claim_eligible(
  p_worker_id uuid,
  p_now timestamptz
)
returns boolean
language sql
stable
set search_path = public
as $$
  select p_now is not null
    and exists (
      select 1
      from public.workers worker
      where worker.id = p_worker_id
        and worker.status = 'online'
        and worker.last_heartbeat_at >= p_now - interval '2 minutes'
        and worker.last_heartbeat_at <= p_now + interval '2 minutes'
        and worker.capabilities @> array['x_sync']::text[]
    )
    and exists (
      select 1
      from public.x_collection_batch_sources batch_source
      join public.sources source on source.id = batch_source.source_id
      where source.source_type = 'x'
        and source.authorized_worker_id = p_worker_id
    )
$$;

create or replace function public.claim_next_x_daily_judgement(
  p_worker_id uuid,
  p_now timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public.x_daily_judgement_worker_is_frozen_claim_eligible(p_worker_id, p_now) then
    raise exception 'worker_not_authorized' using errcode = '42501';
  end if;
  perform public.terminalize_legacy_no_new_x_daily_judgement_runs();
  return public.claim_next_x_daily_judgement_state_core(p_worker_id, p_now);
end;
$$;

revoke all on function public.x_daily_judgement_worker_is_frozen_claim_eligible(uuid, timestamptz)
  from public, anon, authenticated, service_role;
revoke all on function public.claim_next_x_daily_judgement(uuid, timestamptz)
  from public, anon, authenticated;
grant execute on function public.claim_next_x_daily_judgement(uuid, timestamptz)
  to service_role;
