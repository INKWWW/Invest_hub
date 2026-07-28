begin;

select plan(18);

select has_column('public', 'invites', 'code_mask', 'invites retain a safe display mask');
select has_column('public', 'invites', 'validity_hours', 'invites retain the configured duration');
select has_table('public', 'invite_redemption_attempts', 'invite redemption throttle table exists');

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at)
values
  ('00000000-0000-0000-0000-000000021001', 'authenticated', 'authenticated', 'invite-mask-admin@example.invalid', 'not-a-secret', now()),
  ('00000000-0000-0000-0000-000000021002', 'authenticated', 'authenticated', 'invite-mask-user@example.invalid', 'not-a-secret', now())
on conflict (id) do nothing;

insert into public.profiles (id, role, display_name)
values
  ('00000000-0000-0000-0000-000000021001', 'admin', 'Invite Mask Admin'),
  ('00000000-0000-0000-0000-000000021002', 'user', 'Invite Mask User')
on conflict (id) do update set role = excluded.role;

insert into public.invites (id, code_hash, role, purpose, created_by, expires_at)
values (
  '00000000-0000-0000-0000-000000021011',
  'legacy-invite-hash',
  'user',
  'user',
  '00000000-0000-0000-0000-000000021001',
  '2099-01-02T00:00:00Z'
);

insert into public.invites (id, code_hash, role, purpose, created_by, expires_at, code_mask, validity_hours)
values (
  '00000000-0000-0000-0000-000000021012',
  'new-invite-hash',
  'user',
  'user',
  '00000000-0000-0000-0000-000000021001',
  '2099-01-02T00:00:00Z',
  'Ab••••7Q',
  24
);

insert into public.invites (id, code_hash, role, purpose, created_by, expires_at)
values (
  '00000000-0000-0000-0000-000000021013',
  'worker-invite-hash',
  'user',
  'worker',
  '00000000-0000-0000-0000-000000021001',
  '2099-01-02T00:00:00Z'
);

select is((select code_mask from public.invites where id = '00000000-0000-0000-0000-000000021012'), 'Ab••••7Q', 'new invite stores only its mask');
select is((select validity_hours::text from public.invites where id = '00000000-0000-0000-0000-000000021012'), '24', 'new invite stores its configured duration');
select is((select code_mask from public.invites where id = '00000000-0000-0000-0000-000000021011'), null, 'legacy invite remains without a recoverable mask');
select throws_ok(
  $$insert into public.invites (code_hash, role, purpose, expires_at, validity_hours)
    values ('invalid-hours-zero', 'user', 'user', '2099-01-02T00:00:00Z', 0)$$,
  '23514', null, 'invite duration cannot be zero'
);
select throws_ok(
  $$insert into public.invites (code_hash, role, purpose, expires_at, validity_hours)
    values ('invalid-hours-high', 'user', 'user', '2099-01-02T00:00:00Z', 169)$$,
  '23514', null, 'invite duration has an upper bound'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000021002', true);
select is((select count(*)::text from public.invites), '0', 'ordinary user cannot read invite metadata');
reset role;

select is(public.can_attempt_invite_redemption('source-hmac-a', '2099-01-01T00:00:00Z')::text, 'true', 'first redemption attempt is allowed');
select is(public.record_failed_invite_redemption('source-hmac-a', '2099-01-01T00:00:00Z')::text, 'true', 'first failed attempt is recorded');
select is(public.record_failed_invite_redemption('source-hmac-a', '2099-01-01T00:01:00Z')::text, 'true', 'second failed attempt is recorded');
select is(public.record_failed_invite_redemption('source-hmac-a', '2099-01-01T00:02:00Z')::text, 'true', 'third failed attempt is recorded');
select is(public.record_failed_invite_redemption('source-hmac-a', '2099-01-01T00:03:00Z')::text, 'true', 'fourth failed attempt is recorded');
select is(public.record_failed_invite_redemption('source-hmac-a', '2099-01-01T00:04:00Z')::text, 'false', 'fifth failed attempt starts the block');
select is(public.can_attempt_invite_redemption('source-hmac-a', '2099-01-01T00:04:01Z')::text, 'false', 'blocked source cannot retry');
select is(public.can_attempt_invite_redemption('source-hmac-b', '2099-01-01T00:04:01Z')::text, 'true', 'another source is not blocked');
select is(public.can_attempt_invite_redemption('source-hmac-a', '2099-01-01T00:19:01Z')::text, 'true', 'source can retry after the block expires');

select * from finish();
rollback;
