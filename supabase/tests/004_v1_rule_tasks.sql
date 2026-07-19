begin;

select plan(15);

select has_column('public', 'sources', 'author_rules_version', 'sources retain the current rule-set version');
select has_function('public', 'replace_source_author_rules', array['uuid', 'text[]', 'text[]', 'text[]', 'uuid'], 'rule replacement function exists');
select has_function('public', 'create_discord_sync_task', array['uuid', 'text', 'uuid', 'jsonb'], 'atomic task creation function exists');

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at)
values
  ('00000000-0000-0000-0000-000000004001', 'authenticated', 'authenticated', 'v1-rules-admin@example.invalid', 'not-a-secret', now()),
  ('00000000-0000-0000-0000-000000004002', 'authenticated', 'authenticated', 'v1-rules-user@example.invalid', 'not-a-secret', now());

insert into public.profiles (id, role, display_name)
values
  ('00000000-0000-0000-0000-000000004001', 'admin', 'V1 Rules Admin'),
  ('00000000-0000-0000-0000-000000004002', 'user', 'V1 Rules User');

insert into public.sources (id, source_key, source_type, display_name, parameter_version)
values ('00000000-0000-0000-0000-000000004011', 'discord-v1-rules', 'discord', 'V1 rules source', 'v1-source-1');

select throws_ok(
  $$select public.replace_source_author_rules(
    '00000000-0000-0000-0000-000000004011', array['global-a'], array[]::text[], array[]::text[], '00000000-0000-0000-0000-000000004002'
  );$$,
  '42501',
  null,
  'non-admin actors cannot replace source rules'
);

create temporary table first_rule_snapshot as
select public.replace_source_author_rules(
  '00000000-0000-0000-0000-000000004011',
  array['global-b', 'global-a', 'global-a'],
  array['source-a', 'shared'],
  array['global-b', 'shared'],
  '00000000-0000-0000-0000-000000004001'
) as payload;

select is(
  (select payload -> 'target_author_ids' from first_rule_snapshot),
  '["global-a", "source-a"]'::jsonb,
  'source exclusions win and effective targets are sorted and deduplicated'
);
select is((select payload ->> 'version' from first_rule_snapshot), '1', 'first replacement assigns rule-set version one');

create temporary table first_task as
select public.create_discord_sync_task(
  '00000000-0000-0000-0000-000000004011',
  'v1-source-1',
  '00000000-0000-0000-0000-000000004001',
  '{"mode":"incremental","max_pages":5}'::jsonb
) as payload;

select is(
  (select payload -> 'rule_snapshot' -> 'target_author_ids' from first_task),
  '["global-a", "source-a"]'::jsonb,
  'task creation freezes the effective target author set'
);
select is(
  (select payload -> 'collection_scope' from first_task),
  '{"mode":"incremental","max_pages":5}'::jsonb,
  'task creation persists the requested bounded collection scope'
);

create temporary table second_rule_snapshot as
select public.replace_source_author_rules(
  '00000000-0000-0000-0000-000000004011',
  array['global-c'],
  array['source-b'],
  array[]::text[],
  '00000000-0000-0000-0000-000000004001'
) as payload;

select is((select payload ->> 'version' from second_rule_snapshot), '2', 'replacement increments the source rule-set version');
select is(
  (select rule_snapshot -> 'target_author_ids' from public.sync_tasks where id = (select (payload ->> 'id')::uuid from first_task)),
  '["global-a", "source-a"]'::jsonb,
  'a completed rule replacement cannot rewrite an already queued task snapshot'
);

select is(
  public.create_discord_sync_task(
    '00000000-0000-0000-0000-000000004011',
    'v1-source-1',
    '00000000-0000-0000-0000-000000004001',
    '{"mode":"history","max_pages":9}'::jsonb
  ) -> 'rule_snapshot' ->> 'version',
  '2',
  'new task creation observes the latest source rule-set version'
);
select is(
  (select author_rules_version::text from public.sources where id = '00000000-0000-0000-0000-000000004011'),
  '2',
  'source retains the latest rule-set version for future task snapshots'
);

select throws_ok(
  $$select public.create_discord_sync_task(
    '00000000-0000-0000-0000-000000004011', 'wrong-version', '00000000-0000-0000-0000-000000004001', '{"mode":"incremental","max_pages":5}'::jsonb
  );$$,
  '22023',
  null,
  'task creation rejects a parameter version that does not match its source'
);
select throws_ok(
  $$select public.create_discord_sync_task(
    '00000000-0000-0000-0000-000000004011', 'v1-source-1', '00000000-0000-0000-0000-000000004001', '{"mode":"history","max_pages":26}'::jsonb
  );$$,
  '22023',
  null,
  'task creation rejects an unbounded history scope'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004002', true);
select throws_ok(
  $$select public.replace_source_author_rules(
    '00000000-0000-0000-0000-000000004011', array[]::text[], array[]::text[], array[]::text[], '00000000-0000-0000-0000-000000004002'
  );$$,
  '42501',
  null,
  'ordinary authenticated users cannot directly execute rule replacement'
);
reset role;

select * from finish();
rollback;
