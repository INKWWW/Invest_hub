begin;

select plan(3);

select lives_ok(
  $$select public.validate_x_daily_judgement_output_v3(
    '{"security_industry_viewpoints":[{"statement":"一位博主认为估值存在修复机会。","action_intent":"buy","action_scope":"该标的","conditions":["需求继续改善"],"supporting_source_ids":["source-a"],"dissenting_source_ids":[],"analysis_ids":["post-a@1"],"evidence_post_ids":["post-a"],"uncertainties":[]}],"market_structure_viewpoints":[],"strategy_mindset_viewpoints":[],"uncertainties":[]}'::jsonb
  )$$,
  'v3 accepts a grounded blogger action tendency contract'
);

select throws_ok(
  $$select public.validate_x_daily_judgement_output_v3(
    '{"security_industry_viewpoints":[{"statement":"一位博主认为估值存在修复机会。","action_intent":"accumulate","action_scope":"该标的","conditions":[],"supporting_source_ids":["source-a"],"dissenting_source_ids":[],"analysis_ids":["post-a@1"],"evidence_post_ids":["post-a"],"uncertainties":[]}],"market_structure_viewpoints":[],"strategy_mindset_viewpoints":[],"uncertainties":[]}'::jsonb
  )$$,
  '22023', 'invalid_v3_x_daily_judgement_output', 'v3 rejects an unlisted action tendency'
);

select throws_ok(
  $$select public.validate_x_daily_judgement_output_v3(
    '{"security_industry_viewpoints":[],"market_structure_viewpoints":[{"statement":"一位博主认为行业机会需继续观察。","action_intent":"none","action_scope":"该行业","conditions":[],"supporting_source_ids":["source-a"],"dissenting_source_ids":[],"analysis_ids":["post-a@1"],"evidence_post_ids":["post-a"],"uncertainties":[]}],"strategy_mindset_viewpoints":[],"uncertainties":[]}'::jsonb
  )$$,
  '22023', 'invalid_v3_x_daily_judgement_output', 'v3 rejects a fabricated scope when there is no explicit action tendency'
);

select * from finish();
rollback;
