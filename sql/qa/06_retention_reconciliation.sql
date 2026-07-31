-- Weekly retention eligibility, censoring, and rate checks.

WITH retention_metrics AS (
  SELECT
    COUNT(*) AS retention_cells,
    MIN(retention_week) AS minimum_retention_week,
    MAX(retention_week) AS maximum_retention_week,
    COUNTIF(
      retention_rate < 0 OR retention_rate > 1
      OR retention_rate_ci95_lower < 0
      OR retention_rate_ci95_upper > 1
      OR active_users > cohort_users
    ) AS invalid_rate_rows,
    COUNTIF(retention_week = 0 AND active_users != cohort_users)
      AS invalid_week_zero_cells,
    COUNTIF(NOT is_complete_followup_cell) AS incomplete_cells,
    COUNTIF(cohort_week = DATE '2020-10-26') AS partial_cohort_cells,
    COUNTIF(activity_week_end > DATE '2021-01-31')
      AS right_censored_cells
  FROM `{{ project_id }}.{{ dataset_id }}.mart_retention_weekly`
)
SELECT check_result.*
FROM retention_metrics
CROSS JOIN UNNEST([
  STRUCT(
    'retention_complete_cells' AS check_name,
    IF(
      retention_metrics.retention_cells > 0
      AND retention_metrics.minimum_retention_week = 0
      AND retention_metrics.maximum_retention_week = 8
      AND retention_metrics.incomplete_cells = 0
      AND retention_metrics.partial_cohort_cells = 0
      AND retention_metrics.right_censored_cells = 0,
      'PASS',
      'FAIL'
    ) AS status,
    FORMAT(
      '%d cells / W%d-W%d / %d partial / %d censored',
      retention_metrics.retention_cells,
      retention_metrics.minimum_retention_week,
      retention_metrics.maximum_retention_week,
      retention_metrics.partial_cohort_cells,
      retention_metrics.right_censored_cells
    ) AS actual_value,
    'positive cells / W0-W8 / 0 partial / 0 censored'
      AS expected_value,
    'Only complete non-partial cohort cells are retained' AS details
  ),
  STRUCT(
    'retention_metric_validity',
    IF(
      retention_metrics.invalid_rate_rows = 0
      AND retention_metrics.invalid_week_zero_cells = 0,
      'PASS',
      'FAIL'
    ),
    FORMAT(
      '%d rate / %d W0',
      retention_metrics.invalid_rate_rows,
      retention_metrics.invalid_week_zero_cells
    ),
    '0 rate / 0 W0',
    'Retention rates are bounded and W0 equals cohort size'
  )
]) AS check_result
ORDER BY check_name;
