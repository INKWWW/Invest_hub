begin;

select plan(27);

select has_table('public', 'research_threads', 'research threads table exists');
select has_table('public', 'research_messages', 'research messages table exists');
select has_table('public', 'research_thread_artifacts', 'thread artifacts table exists');
select ok((select relrowsecurity from pg_class where oid = 'public.research_threads'::regclass), 'threads use RLS');
select ok((select relrowsecurity from pg_class where oid = 'public.research_messages'::regclass), 'messages use RLS');
select ok((select relrowsecurity from pg_class where oid = 'public.research_thread_artifacts'::regclass), 'artifacts use RLS');
select ok(
  exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'research_threads_owner_updated_idx'),
  'thread list is indexed by owner and recency'
);
select ok(
  exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'research_messages_thread_created_idx'),
  'message history is indexed by thread and time'
);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at)
values
  ('00000000-0000-0000-0000-000000038001', 'authenticated', 'authenticated', 'agent-one@example.invalid', 'not-a-secret', now()),
  ('00000000-0000-0000-0000-000000038002', 'authenticated', 'authenticated', 'agent-two@example.invalid', 'not-a-secret', now())
on conflict (id) do nothing;

insert into public.profiles (id, role, display_name)
values
  ('00000000-0000-0000-0000-000000038001', 'user', 'Agent One'),
  ('00000000-0000-0000-0000-000000038002', 'user', 'Agent Two')
on conflict (id) do update set role = excluded.role;

insert into public.research_threads (id, owner_id, title, created_at, updated_at)
values ('00000000-0000-0000-0000-000000038011', '00000000-0000-0000-0000-000000038001', '宁德时代研究', '2000-01-01'::timestamptz, '2000-01-01'::timestamptz);

insert into public.research_messages (id, thread_id, owner_id, role, content)
values ('00000000-0000-0000-0000-000000038021', '00000000-0000-0000-0000-000000038011', '00000000-0000-0000-0000-000000038001', 'user', '请比较海外竞争格局');

insert into public.research_thread_artifacts (id, thread_id, owner_id, artifact_type, metadata)
values ('00000000-0000-0000-0000-000000038031', '00000000-0000-0000-0000-000000038011', '00000000-0000-0000-0000-000000038001', 'note', '{"version":1}'::jsonb);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000038001', true);
select is((select count(*)::text from public.research_threads), '1', 'owner can list own threads');
select is((select count(*)::text from public.research_messages), '1', 'owner can read own messages');
select is((select count(*)::text from public.research_thread_artifacts), '1', 'owner can read own artifacts');
select is((select count(*)::text from public.research_threads where owner_id <> auth.uid()), '0', 'owner list has no foreign rows');
select ok((select updated_at > '2000-01-01'::timestamptz from public.research_threads where id = '00000000-0000-0000-0000-000000038011'), 'message insertion updates thread activity time');
select throws_ok(
  $$insert into public.research_threads (owner_id, title) values ('00000000-0000-0000-0000-000000038002', '越权');$$,
  '42501', null, 'authenticated user cannot create a thread for another owner'
);
select throws_ok(
  $$insert into public.research_messages (thread_id, owner_id, role, content)
    values ('00000000-0000-0000-0000-000000038011', '00000000-0000-0000-0000-000000038002', 'user', '越权');$$,
  '42501', null, 'authenticated user cannot create a message for another owner'
);
update public.research_threads set title = '宁德时代海外研究' where id = '00000000-0000-0000-0000-000000038011';
select is((select title from public.research_threads where id = '00000000-0000-0000-0000-000000038011'), '宁德时代海外研究', 'owner can rename own thread');

reset role;
select throws_ok(
  $$update public.research_threads set owner_id = '00000000-0000-0000-0000-000000038002' where id = '00000000-0000-0000-0000-000000038011';$$,
  '23514', null, 'thread owner is immutable'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000038002', true);
select is((select count(*)::text from public.research_threads), '0', 'second user cannot list first user threads');
select is((select count(*)::text from public.research_messages), '0', 'second user cannot read first user messages');
select is((select count(*)::text from public.research_thread_artifacts), '0', 'second user cannot read first user artifacts');
select is((select count(*)::text from public.research_threads where id = '00000000-0000-0000-0000-000000038011'), '0', 'guessed thread id is not readable');
select is((select count(*)::text from public.research_messages where thread_id = '00000000-0000-0000-0000-000000038011'), '0', 'guessed message thread is not readable');
update public.research_threads set title = '越权重命名' where id = '00000000-0000-0000-0000-000000038011';
delete from public.research_threads where id = '00000000-0000-0000-0000-000000038011';

reset role;
select is((select title from public.research_threads where id = '00000000-0000-0000-0000-000000038011'), '宁德时代海外研究', 'second user cannot rename first user thread');
select is((select count(*)::text from public.research_threads where id = '00000000-0000-0000-0000-000000038011'), '1', 'second user cannot delete first user thread');
delete from public.research_threads where id = '00000000-0000-0000-0000-000000038011';
select is((select count(*)::text from public.research_messages where thread_id = '00000000-0000-0000-0000-000000038011'), '0', 'thread deletion cascades messages');
select is((select count(*)::text from public.research_thread_artifacts where thread_id = '00000000-0000-0000-0000-000000038011'), '0', 'thread deletion cascades thread artifacts');
select is((select count(*)::text from public.research_threads where id = '00000000-0000-0000-0000-000000038011'), '0', 'thread deletion removes the thread');

select * from finish();
rollback;
