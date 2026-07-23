begin;

select plan(20);

select has_table('public', 'x_source_profiles', 'V2 keeps X account identity in a source-specific table');
select has_table('public', 'x_post_contexts', 'V2 records X post context separately from canonical content');
select has_table('public', 'x_post_analyses', 'V2 persists immutable per-post analyses');
select has_table('public', 'x_daily_viewpoint_segments', 'V2 persists immutable window viewpoint segments');

insert into public.sources (id, source_key, source_type, display_name, parameter_version)
values ('00000000-0000-0000-0000-000000012001', 'x-test-source', 'x', 'X test source', 'v2-test');

insert into public.sources (id, source_key, source_type, display_name, parameter_version)
values ('00000000-0000-0000-0000-000000012002', 'discord-test-source', 'discord', 'Discord test source', 'v2-test');

select lives_ok(
  $$insert into public.x_source_profiles (source_id, requested_handle, resolution_status, display_name)
    values ('00000000-0000-0000-0000-000000012001', 'invest_test', 'pending', 'X test source')$$,
  'a new X source can have one pending account profile'
);
select throws_ok(
  $$update public.x_source_profiles set account_id = 'stable-id'
    where source_id = '00000000-0000-0000-0000-000000012001'$$,
  '23514', null,
  'only a resolved X profile may carry an account id'
);
select throws_ok(
  $$update public.x_source_profiles set resolution_status = 'resolved'
    where source_id = '00000000-0000-0000-0000-000000012001'$$,
  '23514', null,
  'a resolved X profile requires an account id'
);

select throws_ok(
  $$insert into public.sync_tasks (task_type, source_id, parameter_version)
    values ('x_sync', '00000000-0000-0000-0000-000000012001', 'v2-test')$$,
  '23514', null,
  'an X task must include the matching X task snapshot'
);
select throws_ok(
  $$insert into public.sync_tasks (task_type, source_id, parameter_version)
    values ('x_sync', '00000000-0000-0000-0000-000000012002', 'v2-test')$$,
  '23514', null,
  'a Discord source cannot be used by an X task'
);

insert into public.canonical_messages (id, source_id, external_message_id, occurred_at, author_display, content)
values ('00000000-0000-0000-0000-000000012101', '00000000-0000-0000-0000-000000012001', 'x-post-1', '2099-01-01T01:00:00Z', 'X author', 'private X body');

select lives_ok(
  $$insert into public.x_post_contexts (canonical_message_id, post_type, post_url, context_status, attachments)
    values ('00000000-0000-0000-0000-000000012101', 'original', 'https://x.com/invest_test/status/1', 'complete', '[]'::jsonb)$$,
  'an original X post has an explicit context fact'
);
select throws_ok(
  $$insert into public.x_post_contexts (canonical_message_id, post_type, post_url, quoted_post_id, context_status, attachments)
    values ('00000000-0000-0000-0000-000000012101', 'reply', 'https://x.com/invest_test/status/1', 'quoted-1', 'complete', '[]'::jsonb)$$,
  '23514', null,
  'post type determines the only permitted context relation'
);
select throws_ok(
  $$insert into public.x_post_contexts (canonical_message_id, post_type, post_url, context_status, attachments)
    values ('00000000-0000-0000-0000-000000012101', 'original', 'http://x.com/invest_test/status/1', 'complete', '[]'::jsonb)$$,
  '23514', null,
  'X post links must be HTTPS'
);

select throws_ok(
  $$insert into public.raw_messages (source_id, external_message_id, occurred_at, local_raw_ref, payload_hash, retention_expires_at)
    values ('00000000-0000-0000-0000-000000012001', 'x-retention', '2099-01-01T01:00:00Z', 'local://x-retention', repeat('a', 64), '2099-06-01T01:00:00Z')$$,
  '23514', null,
  'X raw facts expire after exactly one year'
);

select lives_ok(
  $$insert into public.x_post_analyses (
      canonical_message_id, analysis_version, blogger_viewpoint, arguments, quoted_post_viewpoint, uncertainties, evidence_refs
    ) values (
      '00000000-0000-0000-0000-000000012101', 1, 'author viewpoint', '[]'::jsonb, null, '[]'::jsonb, '["x-post-1"]'::jsonb
    )$$,
  'a per-post analysis records only the blogger viewpoint for an original post'
);
select throws_ok(
  $$update public.x_post_analyses set blogger_viewpoint = 'rewritten' where canonical_message_id = '00000000-0000-0000-0000-000000012101' and analysis_version = 1$$,
  '55000', null,
  'accepted post analyses are immutable'
);

select throws_ok(
  $$insert into public.x_daily_viewpoint_segments (
      source_id, natural_date, range_task_id, segment_version, occurred_from_at, occurred_through_at, window_viewpoints, post_analysis_refs, evidence_refs
    ) values (
      '00000000-0000-0000-0000-000000012001', '2099-01-01', gen_random_uuid(), 1,
      '2099-01-01T01:00:00Z', '2099-01-01T01:00:00Z', '[]'::jsonb, '[]'::jsonb, '[]'::jsonb
    )$$,
  '23514', null,
  'a viewpoint segment is linked to its completed X range task'
);

select ok((select relrowsecurity from pg_class where oid = 'public.x_source_profiles'::regclass), 'X source profiles use RLS');
select ok((select relrowsecurity from pg_class where oid = 'public.x_post_contexts'::regclass), 'X post context facts use RLS');
select ok((select relrowsecurity from pg_class where oid = 'public.x_post_analyses'::regclass), 'X analyses use RLS');
select ok((select relrowsecurity from pg_class where oid = 'public.x_daily_viewpoint_segments'::regclass), 'X viewpoint segments use RLS');

select * from finish();
rollback;
