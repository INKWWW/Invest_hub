begin;

select plan(4);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at)
values ('00000000-0000-0000-0000-000000016001', 'authenticated', 'authenticated', 'v2-x-history-admin@example.invalid', 'not-a-secret', now());
insert into public.profiles (id, role, display_name)
values ('00000000-0000-0000-0000-000000016001', 'admin', 'X History Admin');
insert into public.sources (id, source_key, source_type, display_name, parameter_version)
values ('00000000-0000-0000-0000-000000016011', 'x-history-source', 'x', 'X History Source', 'v2-history');
insert into public.x_source_profiles (source_id, requested_handle, account_id, display_name, resolution_status)
values ('00000000-0000-0000-0000-000000016011', 'history_fixture', 'history_fixture', 'X History Source', 'resolved');

create temporary table x_history_task as
select public.create_bounded_x_history_task(
  '00000000-0000-0000-0000-000000016011', 'v2-history', '00000000-0000-0000-0000-000000016001',
  '2026-07-20T00:00:00+08:00', '2026-07-20T08:00:00+08:00'
) as payload;
select is((select payload->'capture_range'->>'mode' from x_history_task), 'history', 'creates an explicit X history task');
select is((select payload->'capture_range'->>'trigger' from x_history_task), 'history', 'history task has no scheduled or manual trigger');
select throws_ok(
  $$select public.create_bounded_x_history_task(
    '00000000-0000-0000-0000-000000016011', 'v2-history', '00000000-0000-0000-0000-000000016001',
    '2026-07-20T04:00:00+08:00', '2026-07-20T12:00:00+08:00'
  )$$,
  '23505', null, 'active overlapping X history range is rejected'
);
select throws_ok(
  $$select public.create_bounded_x_history_task(
    '00000000-0000-0000-0000-000000016011', 'v2-history', '00000000-0000-0000-0000-000000016001',
    timezone('utc', now()) + interval '1 day', timezone('utc', now()) + interval '2 days'
  )$$,
  '22023', null, 'future history range is rejected'
);

select * from finish();
rollback;
