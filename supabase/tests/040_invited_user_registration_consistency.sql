begin;

select plan(13);

select has_function(
  'public',
  'complete_invited_user_registration',
  array['text[]', 'uuid', 'timestamptz'],
  'invited registration consistency RPC exists'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.complete_invited_user_registration(text[], uuid, timestamp with time zone)',
    'EXECUTE'
  ),
  'only the service role is allowed to execute the registration RPC'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.complete_invited_user_registration(text[], uuid, timestamp with time zone)',
    'EXECUTE'
  ),
  'anonymous clients cannot execute the registration RPC'
);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at)
values
  ('00000000-0000-0000-0000-000000040001', 'authenticated', 'authenticated', 'registration-admin@example.invalid', 'not-a-secret', now()),
  ('00000000-0000-0000-0000-000000040002', 'authenticated', 'authenticated', 'registration-user@example.invalid', 'not-a-secret', now()),
  ('00000000-0000-0000-0000-000000040003', 'authenticated', 'authenticated', 'registration-retry@example.invalid', 'not-a-secret', now()),
  ('00000000-0000-0000-0000-000000040004', 'authenticated', 'authenticated', 'registration-fault@example.invalid', 'not-a-secret', now())
on conflict (id) do nothing;

insert into public.profiles (id, role)
values ('00000000-0000-0000-0000-000000040001', 'admin')
on conflict (id) do nothing;

insert into public.invites (id, code_hash, role, purpose, created_by, expires_at)
values
  ('00000000-0000-0000-0000-000000040011', 'registration-hmac-hash', 'user', 'user', '00000000-0000-0000-0000-000000040001', '2099-01-02T00:00:00Z'),
  ('00000000-0000-0000-0000-000000040012', 'registration-legacy-hash', 'user', 'user', '00000000-0000-0000-0000-000000040001', '2099-01-02T00:00:00Z'),
  ('00000000-0000-0000-0000-000000040013', 'registration-expired-hash', 'user', 'user', '00000000-0000-0000-0000-000000040001', '2000-01-02T00:00:00Z'),
  ('00000000-0000-0000-0000-000000040014', 'registration-consumed-hash', 'user', 'user', '00000000-0000-0000-0000-000000040001', '2099-01-02T00:00:00Z');

update public.invites
set consumed_at = '2099-01-01T00:00:00Z', consumed_by = '00000000-0000-0000-0000-000000040002'
where id = '00000000-0000-0000-0000-000000040014';

select is(
  public.complete_invited_user_registration(
    array['registration-hmac-hash', 'registration-legacy-hash'],
    '00000000-0000-0000-0000-000000040002',
    '2099-01-01T00:00:00Z'
  )->>'invite_id',
  '00000000-0000-0000-0000-000000040011',
  'valid HMAC invite creates the requested user Profile'
);
select is(
  (select consumed_by::text from public.invites where id = '00000000-0000-0000-0000-000000040011'),
  '00000000-0000-0000-0000-000000040002',
  'the matching invite is consumed by the new Auth identity'
);
select is(
  (select role from public.profiles where id = '00000000-0000-0000-0000-000000040002'),
  'user',
  'the new Profile receives the invite role'
);
select is(
  public.complete_invited_user_registration(
    array['registration-hmac-hash'],
    '00000000-0000-0000-0000-000000040003',
    '2099-01-01T00:00:01Z'
  ),
  null,
  'a consumed invite cannot create a second account'
);
select is(
  public.complete_invited_user_registration(
    array['registration-expired-hash'],
    '00000000-0000-0000-0000-000000040003',
    '2099-01-01T00:00:00Z'
  ),
  null,
  'an expired invite cannot create an account'
);
select is(
  public.complete_invited_user_registration(
    array['registration-missing-hash'],
    '00000000-0000-0000-0000-000000040003',
    '2099-01-01T00:00:00Z'
  ),
  null,
  'a missing invite cannot create an account'
);

create or replace function public.test_invited_registration_fault()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_setting('test.invited_registration_fault', true) = 'on' then
    raise exception 'registration_boundary_injected';
  end if;
  return new;
end;
$$;

create trigger test_invited_registration_fault_trigger
before insert on public.profiles
for each row execute function public.test_invited_registration_fault();

select set_config('test.invited_registration_fault', 'on', true);
select throws_ok(
  $$select public.complete_invited_user_registration(
    array['registration-legacy-hash'],
    '00000000-0000-0000-0000-000000040004',
    '2099-01-01T00:00:00Z'
  );$$,
  'P0001',
  'registration_boundary_injected',
  'Profile failure aborts the registration boundary'
);
select is(
  (select consumed_at from public.invites where id = '00000000-0000-0000-0000-000000040012'),
  null,
  'Profile failure rolls back invite consumption'
);
select is(
  (select count(*)::integer from public.profiles where id = '00000000-0000-0000-0000-000000040004'),
  0,
  'Profile failure leaves no new Profile'
);
select ok(
  not exists (
    select 1
    from public.profiles profile
    join public.invites invite on invite.consumed_by = profile.id
    where profile.id = '00000000-0000-0000-0000-000000040004'
  ),
  'the failed identity has neither a Profile nor a consumed invite'
);

drop trigger test_invited_registration_fault_trigger on public.profiles;
drop function public.test_invited_registration_fault();

select * from finish();
rollback;
