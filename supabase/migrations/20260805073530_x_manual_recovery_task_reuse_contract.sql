-- A historical X window may be evidence for its original scheduled batch and
-- for a later manual recovery batch.  Source identity is still checked by the
-- trigger, so uniqueness belongs to each batch rather than globally.
alter table public.x_collection_batch_sources
  drop constraint x_collection_batch_sources_x_sync_task_id_key;

alter table public.x_collection_batch_sources
  add constraint x_collection_batch_sources_batch_task_key unique (batch_id, x_sync_task_id);
