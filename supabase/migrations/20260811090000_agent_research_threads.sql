create table public.research_threads (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (length(btrim(title)) between 1 and 80),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (id, owner_id)
);

create table public.research_messages (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null,
  owner_id uuid not null,
  role text not null check (role in ('user', 'assistant')),
  content text not null check (length(btrim(content)) between 1 and 20000),
  created_at timestamptz not null default timezone('utc', now()),
  foreign key (thread_id, owner_id) references public.research_threads(id, owner_id) on delete cascade
);

create table public.research_thread_artifacts (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null,
  owner_id uuid not null,
  artifact_type text not null check (length(btrim(artifact_type)) between 1 and 80),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default timezone('utc', now()),
  foreign key (thread_id, owner_id) references public.research_threads(id, owner_id) on delete cascade
);

create index research_threads_owner_updated_idx
  on public.research_threads (owner_id, updated_at desc, id desc);
create index research_messages_thread_created_idx
  on public.research_messages (thread_id, created_at asc, id asc);
create index research_thread_artifacts_thread_created_idx
  on public.research_thread_artifacts (thread_id, created_at asc, id asc);

create or replace function public.prevent_research_owner_change()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.owner_id is distinct from old.owner_id then
    raise exception 'research_owner_immutable' using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger research_threads_owner_immutable
before update on public.research_threads
for each row execute function public.prevent_research_owner_change();

create trigger research_messages_owner_immutable
before update on public.research_messages
for each row execute function public.prevent_research_owner_change();

create trigger research_thread_artifacts_owner_immutable
before update on public.research_thread_artifacts
for each row execute function public.prevent_research_owner_change();

create trigger research_threads_set_updated_at
before update on public.research_threads
for each row execute function public.set_updated_at();

alter table public.research_threads enable row level security;
alter table public.research_messages enable row level security;
alter table public.research_thread_artifacts enable row level security;

grant select, insert, update, delete on public.research_threads to authenticated, service_role;
grant select, insert on public.research_messages to authenticated, service_role;
grant select, insert, delete on public.research_thread_artifacts to authenticated, service_role;

create policy research_threads_owner_access on public.research_threads
for all to authenticated
using (owner_id = auth.uid())
with check (owner_id = auth.uid());

create policy research_messages_owner_select on public.research_messages
for select to authenticated
using (owner_id = auth.uid());

create policy research_messages_owner_insert on public.research_messages
for insert to authenticated
with check (owner_id = auth.uid());

create policy research_thread_artifacts_owner_select on public.research_thread_artifacts
for select to authenticated
using (owner_id = auth.uid());

create policy research_thread_artifacts_owner_insert on public.research_thread_artifacts
for insert to authenticated
with check (owner_id = auth.uid());

create policy research_thread_artifacts_owner_delete on public.research_thread_artifacts
for delete to authenticated
using (owner_id = auth.uid());
