alter table public.worker_execution_receipts
  add column summary_batch_ids jsonb not null default '[]'::jsonb check (jsonb_typeof(summary_batch_ids) = 'array'),
  add column daily_summary_ids jsonb not null default '[]'::jsonb check (jsonb_typeof(daily_summary_ids) = 'array');

alter function public.persist_worker_execution(uuid, integer, uuid, jsonb)
  rename to persist_worker_execution_summary_core;
alter function public.accept_task_result(uuid, integer, jsonb, jsonb)
  rename to accept_task_result_summary_core;

create function public.persist_worker_execution(
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
  v_result jsonb;
  v_receipt public.worker_execution_receipts%rowtype;
  v_summary_batch_ids jsonb;
  v_daily_summary_ids jsonb;
begin
  v_result := public.persist_worker_execution_summary_core(p_task_id, p_attempt, p_worker_id, p_payload);
  select * into v_receipt
  from public.worker_execution_receipts
  where task_id = p_task_id and attempt = p_attempt
  for update;

  if not found then
    raise exception 'persistence_receipt_missing' using errcode = '55000';
  end if;
  if jsonb_array_length(v_receipt.summary_batch_ids) > 0 or jsonb_array_length(v_receipt.daily_summary_ids) > 0 then
    if v_receipt.summary_batch_ids <> coalesce(v_result->'summary_batch_ids', '[]'::jsonb) then
      raise exception 'conflicting_summary_receipt' using errcode = '23505';
    end if;
    return v_result || jsonb_build_object(
      'summary_batch_ids', v_receipt.summary_batch_ids,
      'daily_summary_ids', v_receipt.daily_summary_ids
    );
  end if;

  v_summary_batch_ids := coalesce(v_result->'summary_batch_ids', '[]'::jsonb);
  v_daily_summary_ids := coalesce(v_result->'daily_summary_ids', '[]'::jsonb);
  update public.worker_execution_receipts
  set summary_batch_ids = v_summary_batch_ids,
      daily_summary_ids = v_daily_summary_ids
  where task_id = p_task_id and attempt = p_attempt;

  return v_result || jsonb_build_object(
    'summary_batch_ids', v_summary_batch_ids,
    'daily_summary_ids', v_daily_summary_ids
  );
end;
$$;

create function public.accept_task_result(
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
  v_receipt public.worker_execution_receipts%rowtype;
begin
  select * into v_receipt
  from public.worker_execution_receipts
  where task_id = p_task_id and attempt = p_attempt
  for update;

  if found and (
    v_receipt.summary_batch_ids <> coalesce(p_result->'summary_batch_ids', '[]'::jsonb)
    or v_receipt.daily_summary_ids <> coalesce(p_result->'daily_summary_ids', '[]'::jsonb)
  ) then
    raise exception 'summary_receipt_mismatch' using errcode = '55000';
  end if;
  return public.accept_task_result_summary_core(p_task_id, p_attempt, p_result, p_context);
end;
$$;

revoke all on function public.persist_worker_execution_summary_core(uuid, integer, uuid, jsonb) from public, anon, authenticated, service_role;
revoke all on function public.accept_task_result_summary_core(uuid, integer, jsonb, jsonb) from public, anon, authenticated, service_role;
revoke all on function public.persist_worker_execution(uuid, integer, uuid, jsonb) from public, anon, authenticated;
revoke all on function public.accept_task_result(uuid, integer, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.persist_worker_execution(uuid, integer, uuid, jsonb) to service_role;
grant execute on function public.accept_task_result(uuid, integer, jsonb, jsonb) to service_role;
