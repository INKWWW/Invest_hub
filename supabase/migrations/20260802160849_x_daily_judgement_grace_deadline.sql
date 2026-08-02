-- Batches represent a Shanghai natural day, including the 00:00 cutoff that
-- follows it.  The deadline is therefore owned by the natural day rather
-- than by any individual cutoff.  This affects only future inserts; the
-- immutable history remains untouched.
create function public.x_collection_batch_settlement_deadline(p_natural_date date)
returns timestamptz
language sql
immutable
strict
set search_path = public
as $$
  select ((p_natural_date + 1)::timestamp + time '01:00') at time zone 'Asia/Shanghai'
$$;

create function public.apply_x_collection_batch_settlement_deadline()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if current_setting('app.x_collection_batch_grace_deadline', true) = 'true' then
    new.settlement_deadline_at := public.x_collection_batch_settlement_deadline(new.natural_date);
  end if;
  return new;
end;
$$;

create trigger x_collection_batches_apply_settlement_deadline
before insert on public.x_collection_batches
for each row execute function public.apply_x_collection_batch_settlement_deadline();

-- Keep the existing scheduler implementation intact and scope the new insert
-- rule to scheduler-created batches.  Historical/admin inserts retain their
-- explicitly supplied immutable deadline.
alter function public.ensure_due_x_collection_batches_dispatch_core(uuid, timestamptz)
  rename to ensure_due_x_collection_batches_dispatch_legacy_core;

create function public.ensure_due_x_collection_batches_dispatch_core(p_worker_id uuid, p_now timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_result jsonb;
begin
  perform set_config('app.x_collection_batch_grace_deadline', 'true', true);
  v_result := public.ensure_due_x_collection_batches_dispatch_legacy_core(p_worker_id, p_now);
  perform set_config('app.x_collection_batch_grace_deadline', 'false', true);
  return v_result;
exception when others then
  perform set_config('app.x_collection_batch_grace_deadline', 'false', true);
  raise;
end;
$$;

-- Recreate the existing authorization wrapper after the rename so previously
-- cached function plans also resolve the new dispatch wrapper.
create or replace function public.ensure_due_x_collection_batches_core(p_worker_id uuid, p_now timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public.x_daily_judgement_worker_is_eligible(p_worker_id, p_now) then
    raise exception 'worker_not_authorized' using errcode = '42501';
  end if;
  return public.ensure_due_x_collection_batches_dispatch_core(p_worker_id, p_now);
end;
$$;

revoke all on function public.x_collection_batch_settlement_deadline(date),
  public.apply_x_collection_batch_settlement_deadline(),
  public.ensure_due_x_collection_batches_dispatch_core(uuid, timestamptz) from public, anon, authenticated, service_role;
grant execute on function public.x_collection_batch_settlement_deadline(date) to service_role;
