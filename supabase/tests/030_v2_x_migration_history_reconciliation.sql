begin;

select plan(3);

select ok(
  exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260731084640'
  ),
  'the historical remote marker is recorded locally'
);

select ok(
  exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260731100000'
  ),
  'the canonical scheduler migration follows the marker'
);

select ok(
  position(
    'deferred_source_ids' in pg_get_functiondef('public.enqueue_due_x_tasks(uuid,timestamp with time zone)'::regprocedure)
  ) > 0,
  'the canonical scheduler definition preserves terminal-failure isolation output'
);

select * from finish();
rollback;
