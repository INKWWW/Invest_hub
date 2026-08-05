-- Manual recovery creates a new immutable batch from previously persisted
-- windows.  It must not collide with the historical scheduled batch for the
-- same cutoff, so it carries a run-scoped key instead of a timestamp key.
alter table public.x_collection_batches
  drop constraint x_collection_batches_scheduled_window_key_check,
  drop constraint x_collection_batches_check1;

alter table public.x_collection_batches
  add constraint x_collection_batches_scheduled_window_key_check
    check (
      scheduled_window_key ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T(00:00|08:00|12:00|16:00|20:00)[+]08:00$'
      or scheduled_window_key ~ '^manual:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    ),
  add constraint x_collection_batches_cutoff_key_check
    check (
      case
        when scheduled_window_key ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T(00:00|08:00|12:00|16:00|20:00)[+]08:00$'
          then cutoff_at = scheduled_window_key::timestamptz
        when scheduled_window_key ~ '^manual:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
          then true
        else false
      end
    );
