-- V1.1 author selectors are administrator-entered display names or handles.
-- A stable Discord author id is resolved only after the Worker has persisted
-- the task's captured pages.  The selector remains durable even when no
-- historical canonical message currently matches it.

alter table public.source_author_profiles
  add column requested_author text,
  add column resolution_status text;

update public.source_author_profiles
set requested_author = author_display,
    resolution_status = 'resolved';

alter table public.source_author_profiles
  alter column requested_author set not null,
  alter column resolution_status set not null,
  alter column author_id drop not null,
  drop constraint if exists source_author_profiles_author_id_check,
  drop constraint if exists source_author_profiles_source_id_author_id_key,
  add constraint source_author_profiles_requested_author_check
    check (length(btrim(requested_author)) > 0),
  add constraint source_author_profiles_author_id_check
    check (author_id is null or length(btrim(author_id)) > 0),
  add constraint source_author_profiles_resolution_status_check
    check (resolution_status in ('pending', 'resolved', 'ambiguous')),
  add constraint source_author_profiles_resolution_identity_check
    check (
      (resolution_status = 'resolved' and author_id is not null)
      or (resolution_status in ('pending', 'ambiguous') and author_id is null)
    );

create unique index source_author_profiles_source_requested_author_key
  on public.source_author_profiles (source_id, lower(btrim(requested_author)));

create unique index source_author_profiles_source_resolved_author_key
  on public.source_author_profiles (source_id, author_id)
  where author_id is not null;

create or replace function public.create_windowed_discord_sync_task(
  p_source_id uuid,
  p_parameter_version text,
  p_requested_by uuid,
  p_trigger text,
  p_end_at timestamptz,
  p_scheduled_window_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_source public.sources%rowtype;
  v_coverage public.source_collection_coverage%rowtype;
  v_existing public.sync_tasks%rowtype;
  v_task public.sync_tasks%rowtype;
  v_author_profiles jsonb;
  v_capture_range jsonb;
begin
  if p_trigger not in ('scheduled', 'manual', 'bootstrap') or p_end_at is null then
    raise exception 'invalid_capture_range' using errcode = '22023';
  end if;

  if p_trigger in ('manual', 'bootstrap') and not exists (
    select 1 from public.profiles where id = p_requested_by and role = 'admin'
  ) then
    raise exception 'actor_not_authorized' using errcode = '42501';
  end if;

  if p_trigger = 'scheduled' then
    if p_requested_by is not null
       or p_scheduled_window_key is null
       or p_scheduled_window_key !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T(00:00|08:00|16:00|20:50)[+]08:00$'
       or p_scheduled_window_key::timestamptz <> p_end_at then
      raise exception 'invalid_capture_range' using errcode = '22023';
    end if;
  elsif p_scheduled_window_key is not null then
    raise exception 'invalid_capture_range' using errcode = '22023';
  end if;

  select * into v_source
  from public.sources
  where id = p_source_id and source_type = 'discord'
  for update;

  if not found then
    raise exception 'source_not_found' using errcode = '22023';
  end if;
  if not v_source.enabled then
    raise exception 'source_disabled' using errcode = '22023';
  end if;
  if p_parameter_version is null or p_parameter_version <> v_source.parameter_version then
    raise exception 'source_parameter_version_mismatch' using errcode = '22023';
  end if;

  select * into v_coverage
  from public.source_collection_coverage
  where source_id = p_source_id
  for update;

  if not found then
    raise exception 'coverage_not_initialized' using errcode = '22023';
  end if;
  if p_end_at <= v_coverage.coverage_through_at then
    raise exception 'invalid_capture_range' using errcode = '22023';
  end if;

  select * into v_existing
  from public.sync_tasks
  where source_id = p_source_id
    and collection_scope->>'mode' = 'window'
    and status in ('queued', 'leased', 'running', 'retryable_failed')
  order by (capture_range->>'end_at')::timestamptz, queued_at, id
  for update
  limit 1;

  if found then
    return to_jsonb(v_existing) || jsonb_build_object('idempotent', true);
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'profile_id', profile.id::text,
        'requested_author', profile.requested_author,
        'resolution_status', profile.resolution_status,
        'author_id', profile.author_id,
        'author_display', profile.author_display,
        'author_handle', profile.author_handle,
        'enabled', profile.enabled
      )
      order by profile.requested_author, profile.id
    ),
    '[]'::jsonb
  )
  into v_author_profiles
  from public.source_author_profiles profile
  where profile.source_id = p_source_id and profile.enabled;

  v_capture_range := jsonb_build_object(
    'mode', 'window',
    'trigger', p_trigger,
    'timezone', 'Asia/Shanghai',
    'start_at', v_coverage.coverage_through_at,
    'end_at', p_end_at,
    'scheduled_window_key', case when p_trigger = 'scheduled' then to_jsonb(p_scheduled_window_key) else 'null'::jsonb end
  );

  insert into public.sync_tasks (
    task_type,
    source_id,
    parameter_version,
    requested_by,
    rule_snapshot,
    collection_scope,
    capture_range,
    author_profile_snapshot
  ) values (
    'discord_sync',
    p_source_id,
    p_parameter_version,
    p_requested_by,
    jsonb_build_object('version', v_source.author_rules_version, 'target_author_ids', '[]'::jsonb),
    '{"mode":"window"}'::jsonb,
    v_capture_range,
    v_author_profiles
  ) returning * into v_task;

  insert into public.sync_task_capture_progress (
    task_id, source_id, capture_range
  ) values (
    v_task.id, p_source_id, v_capture_range
  );

  return to_jsonb(v_task) || jsonb_build_object('idempotent', false);
end;
$$;

create or replace function public.resolve_windowed_author_profiles(
  p_task_id uuid,
  p_attempt integer,
  p_worker_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_task public.sync_tasks%rowtype;
  v_snapshot jsonb;
  v_profile_id uuid;
  v_requested_author text;
  v_candidate_count integer;
  v_author_id text;
  v_author_display text;
  v_author_handle text;
  v_resolved jsonb := '[]'::jsonb;
begin
  select task.* into v_task
  from public.sync_tasks task
  join public.task_attempts attempt
    on attempt.task_id = task.id and attempt.attempt = p_attempt
  where task.id = p_task_id
    and task.collection_scope->>'mode' = 'window'
    and task.lease_owner = p_worker_id
    and task.status in ('leased', 'running')
    and attempt.worker_id = p_worker_id
    and attempt.status in ('leased', 'running')
  for update of task, attempt;

  if not found then
    raise exception 'lease_mismatch' using errcode = '40001';
  end if;

  for v_snapshot in select value from jsonb_array_elements(v_task.author_profile_snapshot)
  loop
    if jsonb_typeof(v_snapshot) <> 'object'
       or (v_snapshot - 'profile_id' - 'requested_author' - 'resolution_status' - 'author_id' - 'author_display' - 'author_handle' - 'enabled') <> '{}'::jsonb
       or nullif(v_snapshot->>'profile_id', '') is null
       or nullif(v_snapshot->>'requested_author', '') is null
       or v_snapshot->>'resolution_status' not in ('pending', 'resolved', 'ambiguous')
       or v_snapshot->>'enabled' <> 'true' then
      raise exception 'invalid_author_profile_snapshot' using errcode = '22023';
    end if;
    begin
      v_profile_id := (v_snapshot->>'profile_id')::uuid;
    exception when invalid_text_representation then
      raise exception 'invalid_author_profile_snapshot' using errcode = '22023';
    end;
    v_requested_author := v_snapshot->>'requested_author';

    select count(*), max(candidate.author_id), max(candidate.author_display), max(candidate.author_handle)
    into v_candidate_count, v_author_id, v_author_display, v_author_handle
    from (
      select distinct
        nullif(message.metadata->>'author_id', '') as author_id,
        coalesce(nullif(message.author_display, ''), nullif(message.metadata->>'author_display', '')) as author_display,
        coalesce(nullif(message.metadata->>'author_handle', ''), nullif(message.metadata->>'author_username', '')) as author_handle
      from public.canonical_messages message
      where message.source_id = v_task.source_id
        and nullif(message.metadata->>'author_id', '') is not null
        and (
          lower(btrim(coalesce(message.author_display, message.metadata->>'author_display', ''))) = lower(btrim(v_requested_author))
          or lower(ltrim(btrim(coalesce(message.metadata->>'author_handle', message.metadata->>'author_username', '')), '@'))
            = lower(ltrim(btrim(v_requested_author), '@'))
        )
    ) candidate;

    if v_candidate_count = 1 and not exists (
      select 1 from public.source_author_profiles profile
      where profile.source_id = v_task.source_id
        and profile.author_id = v_author_id
        and profile.id <> v_profile_id
    ) then
      update public.source_author_profiles profile
      set resolution_status = 'resolved',
          author_id = v_author_id,
          author_display = v_author_display,
          author_handle = v_author_handle
      where profile.id = v_profile_id
        and profile.source_id = v_task.source_id
        and lower(btrim(profile.requested_author)) = lower(btrim(v_requested_author));
      v_resolved := v_resolved || jsonb_build_array(jsonb_build_object(
        'profile_id', v_profile_id::text,
        'requested_author', v_requested_author,
        'resolution_status', 'resolved',
        'author_id', v_author_id,
        'author_display', v_author_display,
        'author_handle', v_author_handle,
        'enabled', true
      ));
    elsif v_candidate_count = 0 then
      update public.source_author_profiles profile
      set resolution_status = 'pending', author_id = null,
          author_display = v_requested_author, author_handle = null
      where profile.id = v_profile_id and profile.source_id = v_task.source_id;
    else
      update public.source_author_profiles profile
      set resolution_status = 'ambiguous', author_id = null,
          author_display = v_requested_author, author_handle = null
      where profile.id = v_profile_id and profile.source_id = v_task.source_id;
    end if;
  end loop;

  return jsonb_build_object('author_profiles', v_resolved);
end;
$$;

revoke all on function public.resolve_windowed_author_profiles(uuid, integer, uuid)
  from public, anon, authenticated;
grant execute on function public.resolve_windowed_author_profiles(uuid, integer, uuid) to service_role;
