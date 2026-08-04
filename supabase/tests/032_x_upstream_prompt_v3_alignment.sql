begin;

select plan(5);

select has_column(
  'public', 'x_post_analyses', 'schema_version',
  'v3 post analyses retain their immutable schema version'
);

select has_column(
  'public', 'x_post_analyses', 'analysis_output',
  'v3 post analysis output is retained as structured immutable JSON'
);

select has_column(
  'public', 'x_daily_viewpoint_segments', 'schema_version',
  'v3 window segments retain their immutable schema version'
);

select has_column(
  'public', 'x_daily_viewpoint_segments', 'segment_output',
  'v3 window output is retained as structured immutable JSON'
);

select has_function(
  'public',
  'complete_windowed_capture_range_v3_x_core',
  array['uuid', 'integer', 'uuid', 'jsonb'],
  'v3 range completion has an isolated immutable persistence boundary'
);

select * from finish();
rollback;
