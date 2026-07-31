alter table public.invites
  add column if not exists code_mask text,
  add column if not exists validity_hours integer;

alter table public.invites
  add constraint invites_code_mask_format
  check (code_mask is null or code_mask ~ '^[A-Za-z0-9]{2}••••[A-Za-z0-9]{2}$');

alter table public.invites
  add constraint invites_validity_hours_range
  check (validity_hours is null or validity_hours between 1 and 168);

create table public.invite_redemption_attempts (
  source_hash text primary key,
  window_started_at timestamptz not null,
  failure_count integer not null check (failure_count > 0),
  blocked_until timestamptz,
  expires_at timestamptz not null
);

alter table public.invite_redemption_attempts enable row level security;

create or replace function public.can_attempt_invite_redemption(
  p_source_hash text,
  p_now timestamptz
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.invite_redemption_attempts
  where expires_at <= p_now;

  return not exists (
    select 1
    from public.invite_redemption_attempts
    where source_hash = p_source_hash
      and blocked_until > p_now
  );
end;
$$;

create or replace function public.record_failed_invite_redemption(
  p_source_hash text,
  p_now timestamptz
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_blocked_until timestamptz;
begin
  delete from public.invite_redemption_attempts
  where expires_at <= p_now;

  insert into public.invite_redemption_attempts (
    source_hash,
    window_started_at,
    failure_count,
    blocked_until,
    expires_at
  )
  values (p_source_hash, p_now, 1, null, p_now + interval '1 day')
  on conflict (source_hash) do update
  set window_started_at = case
        when public.invite_redemption_attempts.window_started_at + interval '15 minutes' <= excluded.window_started_at
          then excluded.window_started_at
        else public.invite_redemption_attempts.window_started_at
      end,
      failure_count = case
        when public.invite_redemption_attempts.window_started_at + interval '15 minutes' <= excluded.window_started_at
          then 1
        else public.invite_redemption_attempts.failure_count + 1
      end,
      blocked_until = case
        when public.invite_redemption_attempts.window_started_at + interval '15 minutes' <= excluded.window_started_at
          then null
        when public.invite_redemption_attempts.failure_count + 1 >= 5
          then excluded.window_started_at + interval '15 minutes'
        else public.invite_redemption_attempts.blocked_until
      end,
      expires_at = excluded.expires_at
  returning blocked_until into v_blocked_until;

  return v_blocked_until is null or v_blocked_until <= p_now;
end;
$$;

revoke all on table public.invite_redemption_attempts from public, anon, authenticated;
grant select, insert, update, delete on table public.invite_redemption_attempts to service_role;
revoke all on function public.can_attempt_invite_redemption(text, timestamptz) from public, anon, authenticated;
revoke all on function public.record_failed_invite_redemption(text, timestamptz) from public, anon, authenticated;
grant execute on function public.can_attempt_invite_redemption(text, timestamptz) to service_role;
grant execute on function public.record_failed_invite_redemption(text, timestamptz) to service_role;
