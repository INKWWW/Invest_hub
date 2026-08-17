-- Agent Demo runs use the same enrolled Worker registry but require an
-- explicit capability that must not be accepted by the X-only constraint.
alter table public.workers
  drop constraint workers_capabilities_check;

alter table public.workers
  add constraint workers_capabilities_check
  check (capabilities <@ array['discord_sync', 'x_sync', 'agent_demo']::text[]);
