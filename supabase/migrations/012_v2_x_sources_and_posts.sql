-- V2 adds X facts alongside the existing Discord model.  It is deliberately
-- additive: disabling X sources is the rollback path; completed facts remain.

alter table public.sources
  drop constraint sources_source_type_check,
  add constraint sources_source_type_check check (source_type in ('discord', 'x'));

alter table public.sync_tasks
  drop constraint sync_tasks_task_type_check,
  add constraint sync_tasks_task_type_check check (task_type in ('discord_sync', 'x_sync'));

alter table public.sync_tasks
  add column x_source_snapshot jsonb,
  add constraint sync_tasks_x_source_snapshot_shape check (
    (task_type = 'x_sync'
      and jsonb_typeof(x_source_snapshot) = 'object'
      and (x_source_snapshot - 'source_type' - 'account_id' - 'display_name' - 'parameter_version') = '{}'::jsonb
      and x_source_snapshot->>'source_type' = 'x'
      and nullif(x_source_snapshot->>'account_id', '') is not null
      and nullif(x_source_snapshot->>'display_name', '') is not null
      and nullif(x_source_snapshot->>'parameter_version', '') is not null)
    or (task_type <> 'x_sync' and x_source_snapshot is null)
  );

create or replace function public.enforce_source_task_type_match()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_source_type text;
begin
  select source_type into v_source_type from public.sources where id = new.source_id;
  if (new.task_type = 'discord_sync' and v_source_type <> 'discord')
     or (new.task_type = 'x_sync' and v_source_type <> 'x') then
    raise exception 'source_task_type_mismatch' using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger sync_tasks_source_task_type_match
before insert or update of task_type, source_id on public.sync_tasks
for each row execute function public.enforce_source_task_type_match();

create table public.x_source_profiles (
  source_id uuid primary key references public.sources(id) on delete cascade,
  requested_handle text not null check (length(btrim(requested_handle)) > 0),
  account_id text,
  display_name text not null check (length(btrim(display_name)) > 0),
  resolution_status text not null default 'pending'
    check (resolution_status in ('pending', 'resolved', 'ambiguous')),
  enabled boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  check (
    (resolution_status = 'resolved' and account_id is not null and length(btrim(account_id)) > 0)
    or (resolution_status in ('pending', 'ambiguous') and account_id is null)
  )
);

create trigger x_source_profiles_set_updated_at before update on public.x_source_profiles
for each row execute function public.set_updated_at();

create or replace function public.enforce_x_profile_source()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if not exists (select 1 from public.sources where id = new.source_id and source_type = 'x') then
    raise exception 'x_profile_requires_x_source' using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger x_source_profiles_x_source
before insert or update of source_id on public.x_source_profiles
for each row execute function public.enforce_x_profile_source();

create table public.x_post_contexts (
  canonical_message_id uuid primary key references public.canonical_messages(id) on delete cascade,
  post_type text not null check (post_type in ('original', 'quote', 'reply', 'repost')),
  post_url text not null check (post_url ~ '^https://(www[.])?(x[.]com|twitter[.]com)/.+/status/[0-9]+/?([?#].*)?$'),
  quoted_post_id text,
  reply_to_post_id text,
  reposted_post_id text,
  context_status text not null check (context_status in ('complete', 'unavailable', 'deleted', 'unresolved')),
  attachments jsonb not null default '[]'::jsonb check (jsonb_typeof(attachments) = 'array'),
  created_at timestamptz not null default timezone('utc', now()),
  check (
    (post_type = 'original' and quoted_post_id is null and reply_to_post_id is null and reposted_post_id is null)
    or (post_type = 'quote' and quoted_post_id is not null and reply_to_post_id is null and reposted_post_id is null)
    or (post_type = 'reply' and quoted_post_id is null and reply_to_post_id is not null and reposted_post_id is null)
    or (post_type = 'repost' and quoted_post_id is null and reply_to_post_id is null and reposted_post_id is not null)
  )
);

create index x_post_contexts_post_type_idx on public.x_post_contexts (post_type, context_status);

create or replace function public.enforce_x_context_source()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.canonical_messages message
    join public.sources source on source.id = message.source_id
    where message.id = new.canonical_message_id and source.source_type = 'x'
  ) then
    raise exception 'x_context_requires_x_canonical_message' using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger x_post_contexts_x_canonical
before insert or update of canonical_message_id on public.x_post_contexts
for each row execute function public.enforce_x_context_source();

create or replace function public.enforce_x_raw_retention()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if exists (select 1 from public.sources where id = new.source_id and source_type = 'x')
     and (new.occurred_at is null or new.retention_expires_at <> new.occurred_at + interval '1 year') then
    raise exception 'x_raw_retention_must_be_one_year' using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger raw_messages_x_retention
before insert or update of source_id, occurred_at, retention_expires_at on public.raw_messages
for each row execute function public.enforce_x_raw_retention();

create table public.x_post_analyses (
  canonical_message_id uuid not null references public.canonical_messages(id) on delete restrict,
  analysis_version integer not null check (analysis_version > 0),
  blogger_viewpoint text,
  arguments jsonb not null check (jsonb_typeof(arguments) = 'array'),
  quoted_post_viewpoint text,
  uncertainties jsonb not null check (jsonb_typeof(uncertainties) = 'array'),
  evidence_refs jsonb not null check (jsonb_typeof(evidence_refs) = 'array'),
  created_at timestamptz not null default timezone('utc', now()),
  primary key (canonical_message_id, analysis_version)
);

create or replace function public.enforce_x_analysis_source()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if not exists (select 1 from public.x_post_contexts where canonical_message_id = new.canonical_message_id) then
    raise exception 'x_analysis_requires_x_context' using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger x_post_analyses_x_context
before insert on public.x_post_analyses
for each row execute function public.enforce_x_analysis_source();

create or replace function public.reject_x_fact_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception 'x_immutable_fact' using errcode = '55000';
end;
$$;

create trigger x_post_analyses_immutable
before update or delete on public.x_post_analyses
for each row execute function public.reject_x_fact_mutation();

create table public.x_daily_viewpoint_segments (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null references public.sources(id) on delete restrict,
  natural_date date not null,
  range_task_id uuid not null references public.sync_tasks(id) on delete restrict,
  segment_version integer not null check (segment_version > 0),
  occurred_from_at timestamptz not null,
  occurred_through_at timestamptz not null,
  window_viewpoints jsonb not null check (jsonb_typeof(window_viewpoints) = 'array'),
  post_analysis_refs jsonb not null check (jsonb_typeof(post_analysis_refs) = 'array'),
  evidence_refs jsonb not null check (jsonb_typeof(evidence_refs) = 'array'),
  created_at timestamptz not null default timezone('utc', now()),
  check (occurred_from_at <= occurred_through_at),
  unique (source_id, natural_date, range_task_id),
  unique (source_id, natural_date, segment_version)
);

create index x_daily_viewpoint_segments_reader_idx
  on public.x_daily_viewpoint_segments (source_id, natural_date desc, occurred_from_at, segment_version);

create or replace function public.enforce_x_segment_task()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.sync_tasks
    where id = new.range_task_id and source_id = new.source_id and task_type = 'x_sync' and status = 'succeeded'
  ) then
    raise exception 'x_segment_requires_completed_x_range_task' using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger x_daily_viewpoint_segments_completed_range
before insert on public.x_daily_viewpoint_segments
for each row execute function public.enforce_x_segment_task();

create trigger x_daily_viewpoint_segments_immutable
before update or delete on public.x_daily_viewpoint_segments
for each row execute function public.reject_x_fact_mutation();

alter table public.x_source_profiles enable row level security;
alter table public.x_post_contexts enable row level security;
alter table public.x_post_analyses enable row level security;
alter table public.x_daily_viewpoint_segments enable row level security;

create policy x_source_profiles_admin_all on public.x_source_profiles
for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy x_post_contexts_admin_all on public.x_post_contexts
for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy x_post_analyses_admin_all on public.x_post_analyses
for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy x_daily_viewpoint_segments_admin_all on public.x_daily_viewpoint_segments
for all to authenticated using (public.is_admin()) with check (public.is_admin());

grant select, insert, update, delete on public.x_source_profiles, public.x_post_contexts,
  public.x_post_analyses, public.x_daily_viewpoint_segments to authenticated, service_role;
