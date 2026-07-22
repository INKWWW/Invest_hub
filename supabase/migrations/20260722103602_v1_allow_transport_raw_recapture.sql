-- Discord responses can change transport-only fields for an unchanged message.
-- Preserve the first durable raw reference for a stable external message ID;
-- the canonical fact comparison in the core persistence function remains the
-- integrity boundary for meaningful message changes.
create or replace function public.persist_worker_execution_v0(
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
  v_source_id uuid;
  v_raw_messages jsonb;
  v_payload jsonb;
begin
  select source_id into v_source_id
  from public.sync_tasks
  where id = p_task_id;

  select coalesce(
    jsonb_agg(
      case
        when existing.external_message_id is not null
          then jsonb_set(
            jsonb_set(incoming.message, '{local_raw_ref}', to_jsonb(existing.local_raw_ref), false),
            '{payload_hash}', to_jsonb(existing.payload_hash), false
          )
        else incoming.message
      end
      order by incoming.ordinality
    ),
    '[]'::jsonb
  )
  into v_raw_messages
  from jsonb_array_elements(coalesce(p_payload->'raw_messages', '[]'::jsonb)) with ordinality
    as incoming(message, ordinality)
  left join public.raw_messages existing
    on existing.source_id = v_source_id
   and existing.external_message_id = incoming.message->>'external_message_id';

  v_payload := jsonb_set(p_payload, '{raw_messages}', v_raw_messages);
  return public.persist_worker_execution_v0_core(p_task_id, p_attempt, p_worker_id, v_payload);
end;
$$;

revoke all on function public.persist_worker_execution_v0(uuid, integer, uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.persist_worker_execution_v0(uuid, integer, uuid, jsonb) to service_role;
