-- SQLSTATE 40001 is PostgreSQL's serialization_failure and is eligible for
-- transport retry.  X range completion used it for deterministic business
-- conflicts (lease/predecessor checks), which can leave the HTTP RPC waiting
-- after the caller has already established that it cannot make progress.
-- Preserve the atomic core and expose those conflicts as PostgREST's explicit
-- HTTP 409 SQLSTATE instead.

alter function public.complete_windowed_capture_range(uuid, integer, uuid, jsonb)
  rename to complete_windowed_capture_range_v2_x_core;

create function public.complete_windowed_capture_range(
  p_task_id uuid,
  p_attempt integer,
  p_worker_id uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
set lock_timeout = '5s'
as $$
begin
  return public.complete_windowed_capture_range_v2_x_core(
    p_task_id,
    p_attempt,
    p_worker_id,
    p_payload
  );
exception
  when sqlstate '40001' then
    raise sqlstate 'PT409' using message = sqlerrm;
end;
$$;

revoke all on function public.complete_windowed_capture_range_v2_x_core(uuid, integer, uuid, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.complete_windowed_capture_range(uuid, integer, uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.complete_windowed_capture_range(uuid, integer, uuid, jsonb) to service_role;
