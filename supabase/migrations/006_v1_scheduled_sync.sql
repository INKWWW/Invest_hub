create table public.scheduled_sync_windows (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null references public.sources(id) on delete cascade,
  window_key text not null check (
    window_key ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T(08:00|20:50)[+]08:00$'
  ),
  worker_id uuid not null references public.workers(id) on delete restrict,
  task_id uuid not null unique references public.sync_tasks(id) on delete restrict,
  created_at timestamptz not null default timezone('utc', now()),
  unique (source_id, window_key)
);

alter table public.scheduled_sync_windows enable row level security;

create function public.enqueue_scheduled_discord_tasks(
  p_worker_id uuid,
  p_window_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_source public.sources%rowtype;
  v_window public.scheduled_sync_windows%rowtype;
  v_task public.sync_tasks%rowtype;
  v_target_author_ids jsonb;
  v_tasks jsonb := '[]'::jsonb;
  v_date_text text;
begin
  if not exists (
    select 1 from public.workers
    where id = p_worker_id and status in ('enrolled', 'online')
  ) then
    raise exception 'worker_not_authorized' using errcode = '42501';
  end if;

  if p_window_key is null
     or p_window_key !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T(08:00|20:50)[+]08:00$' then
    raise exception 'invalid_schedule_window' using errcode = '22023';
  end if;
  v_date_text := substring(p_window_key from 1 for 10);
  if to_char(to_date(v_date_text, 'YYYY-MM-DD'), 'YYYY-MM-DD') <> v_date_text then
    raise exception 'invalid_schedule_window' using errcode = '22023';
  end if;

  for v_source in
    select *
    from public.sources
    where enabled
      and authorized_worker_id = p_worker_id
    order by id
  loop
    perform pg_advisory_xact_lock(hashtextextended(v_source.id::text || ':' || p_window_key, 0));

    select * into v_window
    from public.scheduled_sync_windows
    where source_id = v_source.id and window_key = p_window_key;

    if found then
      v_tasks := v_tasks || jsonb_build_array(jsonb_build_object(
        'id', v_window.task_id::text,
        'source_id', v_source.id::text,
        'idempotent', true
      ));
      continue;
    end if;

    with targets as (
      select author_id
      from public.source_author_rules
      where enabled
        and policy = 'target'
        and (scope = 'global' or (scope = 'source' and source_id = v_source.id))
    ), excluded as (
      select author_id
      from public.source_author_rules
      where enabled
        and policy = 'exclude'
        and scope = 'source'
        and source_id = v_source.id
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
      v_source.id,
      v_source.parameter_version,
      null,
      jsonb_build_object(
        'version', v_source.author_rules_version,
        'target_author_ids', v_target_author_ids
      ),
      '{"mode":"incremental","max_pages":5}'::jsonb
    ) returning * into v_task;

    insert into public.scheduled_sync_windows (source_id, window_key, worker_id, task_id)
    values (v_source.id, p_window_key, p_worker_id, v_task.id);

    v_tasks := v_tasks || jsonb_build_array(jsonb_build_object(
      'id', v_task.id::text,
      'source_id', v_source.id::text,
      'idempotent', false
    ));
  end loop;

  return jsonb_build_object('window_key', p_window_key, 'tasks', v_tasks);
end;
$$;

revoke all on table public.scheduled_sync_windows from public, anon, authenticated;
revoke all on function public.enqueue_scheduled_discord_tasks(uuid, text) from public, anon, authenticated;
grant execute on function public.enqueue_scheduled_discord_tasks(uuid, text) to service_role;
