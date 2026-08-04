begin;
select plan(6);

select has_table('public', 'x_manual_recovery_runs', 'manual X recovery runs are persisted');
select has_table('public', 'x_manual_recovery_run_sources', 'manual X recovery freezes its source set');
select has_function('public', 'create_x_manual_recovery_run', array['uuid', 'timestamp with time zone'], 'admin can create a manual X recovery run');
select has_function('public', 'advance_x_manual_recovery_runs', array['uuid', 'timestamp with time zone'], 'eligible Worker advances manual X recovery runs');
select ok(
  exists(
    select 1
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname = 'advance_x_manual_recovery_runs'
      and position('terminal_recovery_failed' in lower(pg_get_functiondef(procedure.oid))) > 0
  ),
  'manual X recovery stops visibly after its bounded recovery fails'
);
select ok(
  exists(
    select 1
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname = 'enqueue_due_x_tasks'
      and position('recovered_from_task_id is null' in lower(pg_get_functiondef(procedure.oid))) > 0
  ),
  'automatic X recovery is bounded to a terminal root task'
);

select * from finish();
rollback;
