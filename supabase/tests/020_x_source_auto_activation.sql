begin;

select plan(6);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at)
values ('00000000-0000-0000-0000-000000020001', 'authenticated', 'authenticated', 'auto-x-admin@example.invalid', 'not-a-secret', now());

insert into public.profiles (id, role, display_name)
values ('00000000-0000-0000-0000-000000020001', 'admin', 'Auto X admin');

select lives_ok(
  $$select public.create_x_source('x:auto-no-worker', 'Auto X', 'fixture_handle', 'x-standard-v2', '00000000-0000-0000-0000-000000020001')$$,
  'X creation remains available while no Worker is online'
);

insert into public.workers (id, name, device_secret_hash, status, last_heartbeat_at, capabilities)
values ('00000000-0000-0000-0000-000000020002', 'auto X worker', 'auto-x-worker-secret', 'online', now(), array['x_sync']);

create temporary table auto_x_source as
select public.create_x_source('x:auto-ready', 'Auto X ready', 'fixture_handle', 'x-standard-v2', '00000000-0000-0000-0000-000000020001') as payload;

select is(
  (select authorized_worker_id::text from public.sources where id = (select (payload->>'id')::uuid from auto_x_source)),
  null,
  'source creation does not bind an online Worker before activation'
);

select is(
  (select stage from public.x_source_activations where source_id = (select (payload->>'id')::uuid from auto_x_source)),
  'pending_identity',
  'creation records an identity activation'
);

select ok(
  (select initial_end_at <= timezone('utc', now()) from public.x_source_activations where source_id = (select (payload->>'id')::uuid from auto_x_source)),
  'initial activation boundary is never later than creation time'
);

-- Keep this legacy-adoption assertion focused on a source created before the
-- Ticket 01 offline-save path; the newly created source is intentionally the
-- first activation candidate under the new contract.
update public.sources set enabled = false where source_key = 'x:auto-no-worker';

update public.x_source_activations
set stage = 'completed'
where source_id = (select (payload->>'id')::uuid from auto_x_source);

insert into public.sources (id, source_key, source_type, display_name, parameter_version, enabled, created_by, created_at)
values ('00000000-0000-0000-0000-000000020003', 'x:legacy-pending', 'x', 'Legacy pending', 'x-standard-v2', true, '00000000-0000-0000-0000-000000020001', '2026-07-26 15:30:00+08');
insert into public.x_source_profiles (source_id, requested_handle, display_name, resolution_status, enabled)
values ('00000000-0000-0000-0000-000000020003', 'legacy_fixture', 'Legacy pending', 'pending', true);

select is(
  public.claim_next_x_activation('00000000-0000-0000-0000-000000020002', timezone('utc', now()))->>'source_id',
  '00000000-0000-0000-0000-000000020003',
  'an existing unbound pending X source is claimed by the eligible Worker'
);

select is(
  (select authorized_worker_id::text from public.sources where id = '00000000-0000-0000-0000-000000020003'),
  '00000000-0000-0000-0000-000000020002',
  'legacy pending source binding is persisted before identity verification'
);

select * from finish();
rollback;
