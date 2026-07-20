alter table public.sources
  add column author_rules_version integer not null default 0 check (author_rules_version >= 0);

create or replace function public.replace_source_author_rules(
  p_source_id uuid,
  p_global_target_author_ids text[],
  p_source_target_author_ids text[],
  p_source_excluded_author_ids text[],
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_global_targets text[];
  v_source_targets text[];
  v_source_excluded text[];
  v_version integer;
  v_target_author_ids jsonb;
begin
  if not exists (
    select 1 from public.profiles where id = p_actor_id and role = 'admin'
  ) then
    raise exception 'actor_not_authorized' using errcode = '42501';
  end if;

  lock table public.sources in share row exclusive mode;
  if not exists (select 1 from public.sources where id = p_source_id) then
    raise exception 'source_not_found' using errcode = '22023';
  end if;

  select coalesce(array_agg(author_id order by author_id), array[]::text[])
  into v_global_targets
  from (
    select distinct btrim(author_id) as author_id
    from unnest(coalesce(p_global_target_author_ids, array[]::text[])) as input(author_id)
    where author_id is not null and length(btrim(author_id)) > 0
  ) normalized;

  select coalesce(array_agg(author_id order by author_id), array[]::text[])
  into v_source_targets
  from (
    select distinct btrim(author_id) as author_id
    from unnest(coalesce(p_source_target_author_ids, array[]::text[])) as input(author_id)
    where author_id is not null and length(btrim(author_id)) > 0
  ) normalized;

  select coalesce(array_agg(author_id order by author_id), array[]::text[])
  into v_source_excluded
  from (
    select distinct btrim(author_id) as author_id
    from unnest(coalesce(p_source_excluded_author_ids, array[]::text[])) as input(author_id)
    where author_id is not null and length(btrim(author_id)) > 0
  ) normalized;

  select coalesce(max(author_rules_version), 0) + 1
  into v_version
  from public.sources;

  delete from public.source_author_rules
  where scope = 'global'
     or (scope = 'source' and source_id = p_source_id);

  update public.sources
  set author_rules_version = v_version;

  insert into public.source_author_rules (
    author_id, scope, source_id, policy, enabled, version, created_by
  )
  select author_id, 'global', null, 'target', true, v_version, p_actor_id
  from unnest(v_global_targets) as input(author_id);

  insert into public.source_author_rules (
    author_id, scope, source_id, policy, enabled, version, created_by
  )
  select author_id, 'source', p_source_id, 'target', true, v_version, p_actor_id
  from unnest(v_source_targets) as input(author_id);

  insert into public.source_author_rules (
    author_id, scope, source_id, policy, enabled, version, created_by
  )
  select author_id, 'source', p_source_id, 'exclude', true, v_version, p_actor_id
  from unnest(v_source_excluded) as input(author_id);

  with targets as (
    select author_id from unnest(v_global_targets) as input(author_id)
    union
    select author_id from unnest(v_source_targets) as input(author_id)
  ), effective as (
    select author_id from targets
    except
    select author_id from unnest(v_source_excluded) as input(author_id)
  )
  select coalesce(jsonb_agg(to_jsonb(author_id) order by author_id), '[]'::jsonb)
  into v_target_author_ids
  from effective;

  return jsonb_build_object(
    'version', v_version,
    'target_author_ids', v_target_author_ids
  );
end;
$$;

create or replace function public.create_discord_sync_task(
  p_source_id uuid,
  p_parameter_version text,
  p_requested_by uuid,
  p_scope jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_source public.sources%rowtype;
  v_target_author_ids jsonb;
  v_max_pages numeric;
  v_task public.sync_tasks%rowtype;
begin
  if not exists (
    select 1 from public.profiles where id = p_requested_by and role = 'admin'
  ) then
    raise exception 'actor_not_authorized' using errcode = '42501';
  end if;

  select * into v_source
  from public.sources
  where id = p_source_id
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

  if p_scope is null or jsonb_typeof(p_scope) <> 'object'
     or (p_scope - 'mode' - 'max_pages') <> '{}'::jsonb then
    raise exception 'invalid_collection_scope' using errcode = '22023';
  end if;
  if p_scope->>'mode' not in ('incremental', 'history')
     or jsonb_typeof(p_scope->'max_pages') <> 'number' then
    raise exception 'invalid_collection_scope' using errcode = '22023';
  end if;

  v_max_pages := (p_scope->>'max_pages')::numeric;
  if mod(v_max_pages, 1) <> 0
     or v_max_pages not between 1 and 25
     or (p_scope->>'mode' = 'incremental' and v_max_pages > 5) then
    raise exception 'invalid_collection_scope' using errcode = '22023';
  end if;

  with targets as (
    select author_id
    from public.source_author_rules
    where enabled
      and policy = 'target'
      and (scope = 'global' or (scope = 'source' and source_id = p_source_id))
  ), excluded as (
    select author_id
    from public.source_author_rules
    where enabled
      and policy = 'exclude'
      and scope = 'source'
      and source_id = p_source_id
  ), effective as (
    select author_id from targets
    except
    select author_id from excluded
  )
  select coalesce(jsonb_agg(to_jsonb(author_id) order by author_id), '[]'::jsonb)
  into v_target_author_ids
  from effective;

  insert into public.sync_tasks (
    task_type,
    source_id,
    parameter_version,
    requested_by,
    rule_snapshot,
    collection_scope
  ) values (
    'discord_sync',
    p_source_id,
    p_parameter_version,
    p_requested_by,
    jsonb_build_object(
      'version', v_source.author_rules_version,
      'target_author_ids', v_target_author_ids
    ),
    p_scope
  ) returning * into v_task;

  return to_jsonb(v_task);
end;
$$;

revoke all on function public.replace_source_author_rules(uuid, text[], text[], text[], uuid) from public, anon, authenticated;
revoke all on function public.create_discord_sync_task(uuid, text, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.replace_source_author_rules(uuid, text[], text[], text[], uuid) to service_role;
grant execute on function public.create_discord_sync_task(uuid, text, uuid, jsonb) to service_role;
