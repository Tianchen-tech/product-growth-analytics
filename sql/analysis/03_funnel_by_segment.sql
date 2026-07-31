SELECT *
FROM `{{ project_id }}.{{ dataset_id }}.mart_funnel_by_segment`
ORDER BY
  segment_type,
  metric_index,
  is_reportable DESC,
  denominator_sessions DESC,
  segment_value;
