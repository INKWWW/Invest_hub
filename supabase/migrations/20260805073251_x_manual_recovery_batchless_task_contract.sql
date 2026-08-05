-- Some historical successful X windows predate batch binding.  A manual
-- recovery already freezes its own source set, so it may safely reuse either a
-- batch-bound or batchless successful window when source and cutoff agree.
create or replace function public.enforce_x_collection_batch_source()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_task public.sync_tasks%rowtype;
  v_batch public.x_collection_batches%rowtype;
begin
  if tg_op = 'UPDATE' then
    if new.batch_id is distinct from old.batch_id
       or new.source_id is distinct from old.source_id
       or new.source_display_name is distinct from old.source_display_name then
      raise exception 'x_collection_snapshot_immutable' using errcode = '55000';
    end if;
    if old.settlement_status <> 'pending' then
      raise exception 'x_collection_snapshot_terminal' using errcode = '55000';
    end if;
    if new.x_sync_task_id is distinct from old.x_sync_task_id
       and not (old.x_sync_task_id is null and new.x_sync_task_id is not null
                and old.settlement_status = 'pending' and new.settlement_status = 'pending') then
      raise exception 'x_collection_snapshot_immutable' using errcode = '55000';
    end if;
  elsif not exists (
    select 1
    from public.sources source
    join public.x_source_profiles profile on profile.source_id = source.id
    where source.id = new.source_id and source.source_type = 'x' and source.enabled
      and profile.enabled and profile.resolution_status = 'resolved'
  ) then
    raise exception 'invalid_x_collection_batch_source' using errcode = '23514';
  end if;

  if new.x_sync_task_id is not null then
    select * into v_task from public.sync_tasks where id = new.x_sync_task_id;
    if not found then
      raise exception 'x_collection_batch_task_source_mismatch' using errcode = '23514';
    end if;
    select * into v_batch from public.x_collection_batches where id = new.batch_id;
    if not found or v_task.source_id <> new.source_id or v_task.task_type <> 'x_sync' then
      raise exception 'x_collection_batch_task_source_mismatch' using errcode = '23514';
    end if;
    if v_batch.scheduled_window_key ~ '^manual:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      if v_task.status <> 'succeeded'
         or v_task.collection_scope->>'mode' <> 'window'
         or (v_task.capture_range->>'end_at')::timestamptz <> v_batch.cutoff_at then
        raise exception 'x_collection_batch_task_source_mismatch' using errcode = '23514';
      end if;
    elsif v_task.collection_batch_id <> new.batch_id then
      raise exception 'x_collection_batch_task_source_mismatch' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;
