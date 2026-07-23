-- The V1.1 claim envelope only exposed capture data for `window` scope.
-- X history work still needs the same immutable range and resumable progress.

alter function public.claim_next_task(uuid, timestamptz) rename to claim_next_task_v2_base;

create function public.claim_next_task(p_worker_id uuid, p_now timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_claim jsonb;
  v_task public.sync_tasks%rowtype;
  v_progress public.sync_task_capture_progress%rowtype;
  v_coverage public.source_collection_coverage%rowtype;
begin
  v_claim := public.claim_next_task_v2_base(p_worker_id, p_now);
  if v_claim is null or v_claim->>'task_type' <> 'x_sync' then
    return v_claim;
  end if;
  select * into v_task from public.sync_tasks where id = (v_claim->>'task_id')::uuid;
  if not found or v_task.x_source_snapshot is null or v_task.capture_range is null then
    raise exception 'x_task_snapshot_missing' using errcode = '22023';
  end if;
  if v_task.collection_scope->>'mode' = 'history' then
    select * into v_progress from public.sync_task_capture_progress where task_id = v_task.id;
    select * into v_coverage from public.source_collection_coverage where source_id = v_task.source_id;
    if not found or v_progress.task_id is null then
      raise exception 'x_history_claim_missing_progress' using errcode = '22023';
    end if;
    v_claim := v_claim || jsonb_build_object(
      'capture_range', v_task.capture_range,
      'coverage_snapshot', jsonb_build_object(
        'coverage_start_at', v_coverage.coverage_start_at,
        'coverage_through_at', v_coverage.coverage_through_at,
        'last_completed_task_id', v_coverage.last_completed_task_id
      ),
      'capture_progress', jsonb_build_object(
        'resume_cursor', v_progress.resume_cursor,
        'page_count', v_progress.page_count,
        'range_complete', v_progress.range_complete
      ),
      'author_profile_snapshot', v_task.author_profile_snapshot
    );
  end if;
  return v_claim || jsonb_build_object('source_snapshot', v_task.x_source_snapshot);
end;
$$;

revoke all on function public.claim_next_task_v2_base(uuid, timestamptz)
  from public, anon, authenticated, service_role;
revoke all on function public.claim_next_task(uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.claim_next_task(uuid, timestamptz) to service_role;
