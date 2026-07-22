create or replace function public.persist_windowed_capture_page(
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
  v_segment_acknowledgement jsonb;
begin
  if p_payload is null
     or jsonb_typeof(p_payload) <> 'object'
     or (p_payload - 'contract_version' - 'task_id' - 'attempt' - 'source_id' - 'raw_messages' - 'canonical_messages' - 'structured_runs' - 'capture_segment') <> '{}'::jsonb
     or p_payload->>'contract_version' <> 'v0'
     or p_payload->>'task_id' <> p_task_id::text
     or coalesce((p_payload->>'attempt')::integer, 0) <> p_attempt
     or jsonb_typeof(p_payload->'raw_messages') <> 'array'
     or jsonb_typeof(p_payload->'canonical_messages') <> 'array'
     or jsonb_typeof(p_payload->'structured_runs') <> 'array'
     or jsonb_array_length(p_payload->'structured_runs') <> 0
     or jsonb_typeof(p_payload->'capture_segment') <> 'object' then
    raise exception 'invalid_windowed_page_persistence' using errcode = '22023';
  end if;

  -- The existing V0 core enforces source ownership, lease ownership,
  -- raw/canonical pairing, idempotent fact writes and evidence integrity.
  -- Its temporary task-level receipt is deleted before the segment is
  -- acknowledged, so only a final structured/summarized execution can create
  -- the receipt that permits coverage to advance.
  perform public.persist_worker_execution_v0(p_task_id, p_attempt, p_worker_id, p_payload);

  delete from public.worker_execution_receipts
  where task_id = p_task_id and attempt = p_attempt and worker_id = p_worker_id;

  v_segment_acknowledgement := public.record_windowed_capture_segment(
    p_task_id,
    p_attempt,
    p_worker_id,
    p_payload->'capture_segment'
  );

  return v_segment_acknowledgement || jsonb_build_object('persisted', true);
end;
$$;

revoke all on function public.persist_windowed_capture_page(uuid, integer, uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.persist_windowed_capture_page(uuid, integer, uuid, jsonb) to service_role;
