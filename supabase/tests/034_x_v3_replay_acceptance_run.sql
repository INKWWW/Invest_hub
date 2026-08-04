begin;

select plan(7);

select has_table('public', 'x_v3_verification_acceptance_runs', 'acceptance lifecycle is separate from the failed replay');
select has_table('public', 'x_v3_verification_acceptance_segments', 'acceptance windows are stored separately');
select has_table('public', 'x_v3_verification_acceptance_versions', 'acceptance daily output is stored separately');
select has_function('public', 'create_x_v3_verification_acceptance_run', array['uuid', 'uuid'], 'admin can create one acceptance run from a failed replay');
select has_function('public', 'claim_x_v3_verification_acceptance_run', array['uuid', 'uuid'], 'only an explicit Worker can claim an acceptance run');
select has_function('public', 'get_x_v3_verification_acceptance_context', array['uuid', 'integer', 'uuid'], 'acceptance context reads only frozen parent replay input');
select has_function('public', 'complete_x_v3_verification_acceptance_run', array['uuid', 'integer', 'uuid', 'jsonb'], 'acceptance completion is an independent atomic boundary');

select * from finish();
rollback;
