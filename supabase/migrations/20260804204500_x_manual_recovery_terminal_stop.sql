-- A manual run must finish visibly if its one bounded recovery task reaches a
-- terminal failure.  Without this guard, coverage cannot advance and the run
-- would remain "collecting" indefinitely.

alter function public.advance_x_manual_recovery_runs(uuid, timestamptz)
  rename to advance_x_manual_recovery_runs_core;

create function public.advance_x_manual_recovery_runs(p_worker_id uuid, p_now timestamptz)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_result jsonb;
begin
  v_result := public.advance_x_manual_recovery_runs_core(p_worker_id, p_now);

  update public.x_manual_recovery_runs run
  set status = 'failed', failure_code = 'terminal_recovery_failed', updated_at = p_now
  where run.status = 'collecting'
    and exists (
      select 1
      from public.x_manual_recovery_run_sources run_source
      join public.source_collection_coverage coverage on coverage.source_id = run_source.source_id
      join public.sync_tasks task on task.source_id = run_source.source_id
      where run_source.run_id = run.id
        and task.task_type = 'x_sync'
        and task.status = 'failed'
        and task.recovered_from_task_id is not null
        and (task.capture_range->>'start_at')::timestamptz = coverage.coverage_through_at
    );

  return v_result;
end $$;

revoke all on function public.advance_x_manual_recovery_runs_core(uuid, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.advance_x_manual_recovery_runs(uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.advance_x_manual_recovery_runs(uuid, timestamptz) to service_role;
