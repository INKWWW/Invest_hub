-- An X source can be physically deleted only before it owns any task,
-- coverage or fact.  Otherwise it is stopped and archived so the existing
-- retention and evidence graph remains intact.

alter table public.sources
  add column archived_at timestamptz,
  add column archived_by uuid references public.profiles(id) on delete set null,
  add column archive_reason text;

comment on column public.sources.archived_at is
  'Administrator archive timestamp. Archived sources remain retained and disabled.';
comment on column public.sources.archive_reason is
  'Safe administrator lifecycle receipt; never a replacement for retained facts or task history.';

create function public.remove_x_source(
  p_source_id uuid,
  p_actor_id uuid,
  p_confirmation_name text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_source public.sources%rowtype;
begin
  if not exists (
    select 1 from public.profiles
    where id = p_actor_id and role = 'admin'
  ) then
    raise exception 'actor_not_authorized' using errcode = '42501';
  end if;

  -- X task creators already acquire this source row with FOR UPDATE before
  -- checking enabled. Holding the same lock serializes archive/delete against
  -- task creation: a creator that resumes after archive sees source_disabled.
  select * into v_source
  from public.sources
  where id = p_source_id
  for update;

  if not found then
    raise exception 'source_not_found' using errcode = '22023';
  end if;
  if v_source.source_type <> 'x' then
    raise exception 'source_not_x' using errcode = '22023';
  end if;
  if btrim(coalesce(p_confirmation_name, '')) <> v_source.display_name then
    raise exception 'confirmation_mismatch' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.sync_tasks
    where source_id = p_source_id
      and status in ('queued', 'leased', 'running', 'retryable_failed')
  ) then
    raise exception 'source_has_active_task' using errcode = '23505';
  end if;

  if exists (select 1 from public.sync_tasks where source_id = p_source_id)
     or exists (select 1 from public.source_collection_coverage where source_id = p_source_id)
     or exists (select 1 from public.raw_messages where source_id = p_source_id)
     or exists (select 1 from public.canonical_messages where source_id = p_source_id)
     or exists (select 1 from public.x_daily_viewpoint_segments where source_id = p_source_id) then
    update public.sources
    set enabled = false,
        archived_at = timezone('utc', now()),
        archived_by = p_actor_id,
        archive_reason = 'administrator_removed'
    where id = p_source_id;

    update public.x_source_profiles
    set enabled = false
    where source_id = p_source_id;

    return jsonb_build_object(
      'action', 'archived',
      'source_id', v_source.id::text,
      'display_name', v_source.display_name
    );
  end if;

  delete from public.sources where id = p_source_id;
  return jsonb_build_object(
    'action', 'deleted',
    'source_id', v_source.id::text,
    'display_name', v_source.display_name
  );
end;
$$;

revoke all on function public.remove_x_source(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.remove_x_source(uuid, uuid, text)
  to service_role;
