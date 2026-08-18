begin;

create or replace function public.complete_invited_user_registration(
  p_code_hashes text[],
  p_user_id uuid,
  p_now timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_invite public.invites%rowtype;
begin
  if p_user_id is null or p_code_hashes is null or cardinality(p_code_hashes) = 0 then
    return null;
  end if;

  select invite.*
  into v_invite
  from public.invites invite
  where invite.code_hash = any(p_code_hashes)
    and invite.purpose = 'user'
    and invite.consumed_at is null
    and invite.expires_at > p_now
  order by array_position(p_code_hashes, invite.code_hash)
  limit 1
  for update;

  if not found then
    return null;
  end if;

  update public.invites
  set consumed_at = p_now, consumed_by = p_user_id
  where id = v_invite.id;

  insert into public.profiles (id, role)
  values (p_user_id, v_invite.role);

  return jsonb_build_object(
    'invite_id', v_invite.id::text,
    'role', v_invite.role,
    'purpose', v_invite.purpose,
    'expires_at', v_invite.expires_at
  );
end;
$$;

revoke all on function public.complete_invited_user_registration(text[], uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.complete_invited_user_registration(text[], uuid, timestamptz) to service_role;

commit;
