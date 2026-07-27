-- Identity failures need operator attention, but must never prevent another
-- newly configured source from being activated in the same Worker loop.

alter table public.x_source_activations
  drop constraint x_source_activations_stage_check,
  add constraint x_source_activations_stage_check
    check (stage in ('pending_identity', 'pending_initialization', 'collecting', 'completed', 'retryable_failed', 'identity_failed'));

create function public.mark_x_source_activation_identity_failed(
  p_source_id uuid,
  p_worker_id uuid,
  p_error_code text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_error_code not in ('identity_mismatch', 'invalid_x_identity', 'profile_timeout', 'profile_invocation_failed', 'activation_protocol_failure', 'identity_resolution_failed') then
    raise exception 'invalid_activation_failure' using errcode = '22023';
  end if;
  update public.x_source_activations
  set stage = 'identity_failed', last_error_code = p_error_code
  where source_id = p_source_id and worker_id = p_worker_id
    and stage in ('pending_identity', 'retryable_failed');
  if not found then raise exception 'worker_not_authorized' using errcode = '42501'; end if;
  return jsonb_build_object('source_id', p_source_id::text, 'stage', 'identity_failed');
end;
$$;

revoke all on function public.mark_x_source_activation_identity_failed(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.mark_x_source_activation_identity_failed(uuid, uuid, text) to service_role;
