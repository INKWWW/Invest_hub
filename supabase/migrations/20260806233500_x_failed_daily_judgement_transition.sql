-- Permit the final batch transition only after the newest audited admin
-- recovery run has succeeded and its immutable version has been inserted.
create or replace function public.reject_x_collection_batch_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.scheduled_window_key is distinct from old.scheduled_window_key
     or new.natural_date is distinct from old.natural_date
     or new.cutoff_at is distinct from old.cutoff_at
     or new.settlement_deadline_at is distinct from old.settlement_deadline_at
     or new.created_at is distinct from old.created_at
     or new.snapshot_completeness is distinct from old.snapshot_completeness then
    raise exception 'x_collection_batch_immutable' using errcode = '55000';
  end if;
  if new.status is distinct from old.status and not (
    (old.status = 'collecting' and new.status in ('judgement_pending', 'judgement_failed', 'succeeded'))
    or (old.status = 'judgement_pending' and new.status in ('judgement_failed', 'succeeded'))
    or (old.status = 'succeeded' and old.snapshot_completeness = 'legacy_unverified'
        and new.status = 'judgement_failed')
    or (
      old.status = 'judgement_failed'
      and new.status = 'succeeded'
      and exists (
        select 1
        from public.x_daily_judgement_runs recovery
        join public.profiles actor
          on actor.id = recovery.requested_by and actor.role = 'admin'
        where recovery.id = (
          select latest.id
          from public.x_daily_judgement_runs latest
          where latest.batch_id = old.id
          order by latest.updated_at desc, latest.created_at desc, latest.id desc
          limit 1
        )
          and recovery.batch_id = old.id
          and recovery.run_kind = 'regeneration'
          and recovery.status = 'succeeded'
      )
      and exists (
        select 1 from public.x_daily_judgement_versions version where version.batch_id = old.id
      )
    )
  ) then
    raise exception 'invalid_x_collection_batch_transition' using errcode = '55000';
  end if;
  return new;
end;
$$;
