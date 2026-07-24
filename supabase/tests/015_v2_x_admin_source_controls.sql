begin;

select plan(6);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at)
values ('00000000-0000-0000-0000-000000015001', 'authenticated', 'authenticated', 'v2-x-admin@example.invalid', 'not-a-secret', now());

insert into public.profiles (id, role, display_name)
values ('00000000-0000-0000-0000-000000015001', 'admin', 'X admin');

create temporary table x_admin_source as
select public.create_x_source('x-admin-source', 'X Admin Source', 'fixture_handle', 'v2-admin', '00000000-0000-0000-0000-000000015001') as payload;
select is((select payload->>'source_type' from x_admin_source), 'x', 'admin source creation creates an X source');
select is((select resolution_status from public.x_source_profiles where source_id = (select (payload->>'id')::uuid from x_admin_source)), 'pending', 'new X source remains pending until local identity verification');
select throws_ok(
  $$select public.initialize_x_collection_coverage((select (payload->>'id')::uuid from x_admin_source), '00000000-0000-0000-0000-000000015001', '2026-07-23T12:00:00+08:00')$$,
  '22023', 'x_source_unresolved', 'coverage cannot initialize before X identity resolution'
);
update public.x_source_profiles
set account_id = 'fixture_handle', resolution_status = 'resolved'
where source_id = (select (payload->>'id')::uuid from x_admin_source);
select throws_ok(
  $$select public.initialize_x_collection_coverage('00000000-0000-0000-0000-000000015101', '00000000-0000-0000-0000-000000015001', '2026-07-23T10:00:00+08:00')$$,
  '22023', null, 'X coverage only accepts fixed X boundaries'
);
select lives_ok(
  $$select public.initialize_x_collection_coverage((select (payload->>'id')::uuid from x_admin_source), '00000000-0000-0000-0000-000000015001', '2026-07-23T12:00:00+08:00')$$,
  'admin can initialize a fixed X coverage boundary'
);
select throws_ok(
  $$select public.create_x_source('x-admin-source-2', 'X', 'h', 'v', '00000000-0000-0000-0000-000000015999')$$,
  '42501', null, 'non-admin cannot create an X source'
);

select * from finish();
rollback;
