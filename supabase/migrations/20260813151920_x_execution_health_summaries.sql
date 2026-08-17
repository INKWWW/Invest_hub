create table public.x_execution_health_summaries (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid not null references public.workers(id) on delete restrict,
  occurred_at timestamptz not null,
  -- Derived from the Ticket 01 failure/recovery fields so the control-plane
  -- persisted detail remains a strict subset of the local safe summary.
  health_status text generated always as (
    case
      when recovered_at is not null then 'recovered'
      when failure_category = 'task_execution_failed' then 'degraded'
      when failure_category is not null then 'unavailable'
      else 'healthy'
    end
  ) stored,
  failure_category text check (failure_category in (
    'configuration_error', 'controlled_runtime_missing', 'unknown_failure',
    'preflight_failed', 'loop_unhandled_exception', 'task_execution_failed'
  )),
  last_healthy_at timestamptz,
  recovered_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  constraint x_execution_health_summary_state check (
    (failure_category is null and last_healthy_at is not null and recovered_at is null)
    or (failure_category = 'task_execution_failed' and recovered_at is null)
    or (failure_category is not null and failure_category <> 'task_execution_failed' and recovered_at is null)
    or (failure_category is null and last_healthy_at is not null and recovered_at is not null)
  ),
  constraint x_execution_health_summary_time check (
    (last_healthy_at is null or last_healthy_at <= occurred_at)
    and (recovered_at is null or recovered_at <= occurred_at)
    and occurred_at <= created_at + interval '1 minute'
  ),
  unique (worker_id, occurred_at)
);

create index x_execution_health_summaries_latest_idx
on public.x_execution_health_summaries (created_at desc, id desc);

create function public.enforce_x_execution_health_worker_authority()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.sources source
    where source.source_type = 'x'
      and source.enabled
      and source.archived_at is null
      and source.authorized_worker_id = new.worker_id
  ) then
    raise exception using errcode = '42501', message = 'x_execution_health_worker_not_authorized';
  end if;
  return new;
end;
$$;

create trigger x_execution_health_worker_authority
before insert on public.x_execution_health_summaries
for each row execute function public.enforce_x_execution_health_worker_authority();

create function public.latest_x_execution_health_summary()
returns table (
  worker_id uuid,
  occurred_at timestamptz,
  health_status text,
  failure_category text,
  last_healthy_at timestamptz,
  recovered_at timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$
  select summary.worker_id, summary.occurred_at, summary.health_status,
         summary.failure_category, summary.last_healthy_at, summary.recovered_at
  from public.x_execution_health_summaries summary
  where exists (
    select 1 from public.sources source
    where source.source_type = 'x'
      and source.enabled
      and source.archived_at is null
      and source.authorized_worker_id = summary.worker_id
  )
  order by summary.created_at desc, summary.id desc
  limit 1
$$;

alter table public.x_execution_health_summaries enable row level security;
revoke all on table public.x_execution_health_summaries from public, anon, authenticated, service_role;
grant select on table public.x_execution_health_summaries to authenticated, service_role;
grant insert on table public.x_execution_health_summaries to service_role;
revoke all on function public.enforce_x_execution_health_worker_authority() from public, anon, authenticated, service_role;
grant execute on function public.enforce_x_execution_health_worker_authority() to service_role;
revoke all on function public.latest_x_execution_health_summary() from public, anon, authenticated, service_role;
grant execute on function public.latest_x_execution_health_summary() to service_role;

create policy x_execution_health_summaries_admin_select
on public.x_execution_health_summaries
for select to authenticated
using (public.is_admin());
