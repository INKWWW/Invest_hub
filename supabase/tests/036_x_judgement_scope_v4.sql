begin;

select plan(5);

select has_function(
  'public', 'validate_x_daily_judgement_output_v4', array['jsonb'],
  'v4 daily judgement validator is installed'
);

select has_function(
  'public', 'complete_windowed_capture_range_v4_x_core', array['uuid', 'integer', 'uuid', 'jsonb'],
  'v4 range completion has its own persistence boundary'
);

select lives_ok(
  $$select public.validate_x_daily_judgement_output_v4(
    '{"security_industry_viewpoints":[{"statement":"明确提出建仓。","action_intent":"build_position","action_scope_status":"unspecified","action_scope":"","conditions":[],"supporting_source_ids":["source-a"],"dissenting_source_ids":[],"analysis_ids":["post-a@2"],"evidence_post_ids":["post-a"],"uncertainties":["对象未说明"]}],"market_structure_viewpoints":[],"strategy_mindset_viewpoints":[],"uncertainties":[]}'::jsonb
  )$$,
  'v4 preserves a clear action while marking its object unspecified'
);

select throws_ok(
  $$select public.validate_x_daily_judgement_output_v4(
    '{"security_industry_viewpoints":[{"statement":"明确提出建仓。","action_intent":"build_position","action_scope_status":"unspecified","action_scope":"对象未说明","conditions":[],"supporting_source_ids":["source-a"],"dissenting_source_ids":[],"analysis_ids":["post-a@2"],"evidence_post_ids":["post-a"],"uncertainties":[] }],"market_structure_viewpoints":[],"strategy_mindset_viewpoints":[],"uncertainties":[]}'::jsonb
  )$$,
  '22023', 'invalid_v4_x_daily_judgement_output',
  'v4 rejects explanations placed in action_scope'
);

select throws_ok(
  $$select public.validate_x_daily_judgement_output_v4(
    '{"security_industry_viewpoints":[{"statement":"走势观察。","action_intent":"none","action_scope_status":"unspecified","action_scope":"","conditions":[],"supporting_source_ids":["source-a"],"dissenting_source_ids":[],"analysis_ids":["post-a@2"],"evidence_post_ids":["post-a"],"uncertainties":[] }],"market_structure_viewpoints":[],"strategy_mindset_viewpoints":[],"uncertainties":[]}'::jsonb
  )$$,
  '22023', 'invalid_v4_x_daily_judgement_output',
  'v4 requires not_applicable for no action tendency'
);

select * from finish();
rollback;
