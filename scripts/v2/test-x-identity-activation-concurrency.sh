#!/usr/bin/env bash
set -euo pipefail

: "${LOCAL_SUPABASE_DB_CONTAINER:?Set LOCAL_SUPABASE_DB_CONTAINER to the local Supabase DB container name.}"

fixture_source_id='00000000-0000-0000-0000-000000019081'
fixture_worker_id='00000000-0000-0000-0000-000000019082'
fixture_actor_id='00000000-0000-0000-0000-000000019083'
fixture_sql_dir="$(mktemp -d)"

psql_local() {
  docker exec -i "$LOCAL_SUPABASE_DB_CONTAINER" psql -v ON_ERROR_STOP=1 -U postgres -d postgres "$@"
}

cleanup() {
  psql_local >/dev/null 2>&1 <<SQL || true
delete from public.sync_tasks where source_id = '$fixture_source_id';
delete from public.source_collection_coverage where source_id = '$fixture_source_id';
delete from public.x_source_profiles where source_id = '$fixture_source_id';
delete from public.sources where id = '$fixture_source_id';
delete from public.workers where id = '$fixture_worker_id';
delete from public.profiles where id = '$fixture_actor_id';
delete from auth.users where id = '$fixture_actor_id';
SQL
  rm -rf "$fixture_sql_dir"
}
trap cleanup EXIT

psql_local <<SQL
delete from public.sync_tasks where source_id = '$fixture_source_id';
delete from public.source_collection_coverage where source_id = '$fixture_source_id';
delete from public.x_source_profiles where source_id = '$fixture_source_id';
delete from public.sources where id = '$fixture_source_id';
delete from public.workers where id = '$fixture_worker_id';
delete from public.profiles where id = '$fixture_actor_id';
delete from auth.users where id = '$fixture_actor_id';

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at)
values ('$fixture_actor_id', 'authenticated', 'authenticated', 'x-identity-concurrency@example.invalid', 'not-a-secret', now());
insert into public.profiles (id, role, display_name)
values ('$fixture_actor_id', 'admin', 'X identity concurrency admin');
insert into public.workers (id, name, device_secret_hash, status)
values ('$fixture_worker_id', 'x-identity-concurrency-worker', 'x-identity-concurrency-worker-hash', 'online');
insert into public.sources (id, source_key, source_type, display_name, parameter_version, authorized_worker_id)
values ('$fixture_source_id', 'x-identity-concurrency', 'x', 'X Identity Concurrency', 'v2-identity', '$fixture_worker_id');
insert into public.x_source_profiles (source_id, requested_handle, display_name, resolution_status)
values ('$fixture_source_id', 'fixture_handle', 'X Identity Concurrency', 'pending');
SQL

run_coverage() {
  trap - EXIT
  psql_local <<SQL
begin;
select 1 from public.sources where id = '$fixture_source_id' for update;
select pg_sleep(2);
do \$\$
begin
  perform public.initialize_x_collection_coverage(
    '$fixture_source_id', '$fixture_actor_id', '2026-07-23T12:00:00+08:00'
  );
  raise exception 'coverage unexpectedly initialized while identity was pending';
exception
  when sqlstate '23505' then
    if sqlerrm <> 'x_identity_activation_blocked' then
      raise;
    end if;
  when sqlstate '22023' then
    if sqlerrm <> 'x_source_unresolved' then
      raise;
    end if;
end;
\$\$;
commit;
SQL
}

run_coverage >"$fixture_sql_dir/coverage.out" 2>&1 &
coverage_pid=$!

sleep 0.2
run_identity() {
  trap - EXIT
  psql_local <<SQL
begin;
select public.resolve_x_source_identity(
  '$fixture_source_id', '$fixture_worker_id', 'v2-identity', 'fixture_handle'
);
commit;
SQL
}

run_identity >"$fixture_sql_dir/identity.out" 2>&1 &
identity_pid=$!

if ! wait "$coverage_pid"; then
  sed -n '1,160p' "$fixture_sql_dir/coverage.out" >&2
  exit 1
fi
if ! wait "$identity_pid"; then
  sed -n '1,160p' "$fixture_sql_dir/identity.out" >&2
  exit 1
fi

psql_local -At <<SQL | rg -qx 'identity_activation_concurrency:pass'
select case
  when (select resolution_status from public.x_source_profiles where source_id = '$fixture_source_id') = 'resolved'
   and not exists (select 1 from public.source_collection_coverage where source_id = '$fixture_source_id')
  then 'identity_activation_concurrency:pass'
  else 'identity_activation_concurrency:fail'
end;
SQL
echo 'identity_activation_concurrency:pass'
