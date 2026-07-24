begin;

select plan(12);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at)
values
  ('00000000-0000-0000-0000-000000020901', 'authenticated', 'authenticated', 'admin-x-removal@example.invalid', 'not-a-secret', now()),
  ('00000000-0000-0000-0000-000000020902', 'authenticated', 'authenticated', 'member-x-removal@example.invalid', 'not-a-secret', now());

insert into public.profiles (id, role, display_name)
values
  ('00000000-0000-0000-0000-000000020901', 'admin', 'X removal admin'),
  ('00000000-0000-0000-0000-000000020902', 'user', 'X removal member');

insert into public.sources (id, source_key, source_type, display_name, parameter_version)
values
  ('00000000-0000-0000-0000-000000020911', 'x-removal-empty', 'x', 'Empty X', 'v2-removal'),
  ('00000000-0000-0000-0000-000000020912', 'x-removal-persisted', 'x', 'Persisted X', 'v2-removal'),
  ('00000000-0000-0000-0000-000000020913', 'x-removal-running', 'x', 'Running X', 'v2-removal'),
  ('00000000-0000-0000-0000-000000020914', 'discord-removal', 'discord', 'Discord source', 'v1-removal');

insert into public.x_source_profiles (source_id, requested_handle, account_id, display_name, resolution_status)
values
  ('00000000-0000-0000-0000-000000020911', 'empty_x', 'empty_x', 'Empty X', 'resolved'),
  ('00000000-0000-0000-0000-000000020912', 'persisted_x', 'persisted_x', 'Persisted X', 'resolved'),
  ('00000000-0000-0000-0000-000000020913', 'running_x', 'running_x', 'Running X', 'resolved');

insert into public.canonical_messages (id, source_id, external_message_id, occurred_at, content)
values ('00000000-0000-0000-0000-000000020921', '00000000-0000-0000-0000-000000020912', 'persisted-post', '2026-07-24T00:00:00Z', 'fixture fact');

insert into public.sync_tasks (id, task_type, source_id, status, parameter_version, x_source_snapshot)
values (
  '00000000-0000-0000-0000-000000020931', 'x_sync', '00000000-0000-0000-0000-000000020913', 'running', 'v2-removal',
  jsonb_build_object('source_type', 'x', 'account_id', 'running_x', 'display_name', 'Running X', 'parameter_version', 'v2-removal')
);

select throws_ok(
  $$select public.remove_x_source('00000000-0000-0000-0000-000000020911', '00000000-0000-0000-0000-000000020901', ' Empty X ')$$,
  'confirmation_mismatch', 'confirmation must exactly match the displayed name'
);
select is(
  public.remove_x_source('00000000-0000-0000-0000-000000020911', '00000000-0000-0000-0000-000000020901', 'Empty X')->>'action',
  'deleted', 'an empty X source is deleted'
);
select ok(
  not exists(select 1 from public.sources where id = '00000000-0000-0000-0000-000000020911'),
  'deleting an empty X source removes its source row'
);
select ok(
  not exists(select 1 from public.x_source_profiles where source_id = '00000000-0000-0000-0000-000000020911'),
  'deleting an empty X source cascades its profile'
);
select is(
  public.remove_x_source('00000000-0000-0000-0000-000000020912', '00000000-0000-0000-0000-000000020901', 'Persisted X')->>'action',
  'archived', 'an X source with persisted facts is archived'
);
select ok(
  exists(select 1 from public.sources where id = '00000000-0000-0000-0000-000000020912' and not enabled and archived_at is not null and archived_by = '00000000-0000-0000-0000-000000020901'),
  'archiving retains and disables the source'
);
select ok(
  exists(select 1 from public.x_source_profiles where source_id = '00000000-0000-0000-0000-000000020912' and not enabled),
  'archiving disables the X profile'
);
select ok(
  exists(select 1 from public.canonical_messages where id = '00000000-0000-0000-0000-000000020921'),
  'archiving retains canonical facts'
);
select throws_ok(
  $$select public.remove_x_source('00000000-0000-0000-0000-000000020913', '00000000-0000-0000-0000-000000020901', 'Running X')$$,
  'source_has_active_task', 'an active X task blocks removal'
);
select throws_ok(
  $$select public.remove_x_source('00000000-0000-0000-0000-000000020912', '00000000-0000-0000-0000-000000020902', 'Persisted X')$$,
  '42501', 'actor_not_authorized', 'a non-admin cannot remove an X source'
);
select throws_ok(
  $$select public.remove_x_source('00000000-0000-0000-0000-000000020914', '00000000-0000-0000-0000-000000020901', 'Discord source')$$,
  'source_not_x', 'a Discord source cannot use the X removal function'
);
select throws_ok(
  $$select public.create_windowed_x_sync_task('00000000-0000-0000-0000-000000020912', 'v2-removal', null, 'scheduled', '2026-07-24T08:00:00+08:00', '2026-07-24T08:00+08:00')$$,
  '22023', 'source_disabled', 'an archived X source cannot receive a new X task'
);

select * from finish();
rollback;
