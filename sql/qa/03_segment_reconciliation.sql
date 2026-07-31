-- Segment partition, uncertainty, and reporting-threshold checks.

WITH segment_metrics AS (
  SELECT
    COUNT(*) AS metric_rows,
    COUNTIF(is_reportable) AS reportable_rows,
    COUNTIF(
      conversion_rate < 0 OR conversion_rate > 1
      OR conversion_rate_ci95_lower < 0
      OR conversion_rate_ci95_upper > 1
      OR conversion_rate_ci95_lower > conversion_rate
      OR conversion_rate_ci95_upper < conversion_rate
    ) AS invalid_rate_rows,
    COUNTIF(
      numerator_sessions > denominator_sessions OR lost_sessions < 0
    ) AS invalid_count_rows,
    COUNTIF(
      is_reportable
      AND (
        sessions < 500
        OR denominator_sessions < minimum_denominator
      )
    ) AS invalid_reportable_rows
  FROM `{{ project_id }}.{{ dataset_id }}.mart_funnel_by_segment`
),
partition_metrics AS (
  SELECT
    COUNT(*) AS segment_types,
    COUNTIF(segment_sessions = 360129) AS reconciled_segment_types
  FROM (
    SELECT
      segment_type,
      SUM(sessions) AS segment_sessions
    FROM `{{ project_id }}.{{ dataset_id }}.mart_funnel_by_segment`
    WHERE metric_name = 'purchase_session_conversion'
    GROUP BY segment_type
  )
)
SELECT check_result.*
FROM segment_metrics
CROSS JOIN partition_metrics
CROSS JOIN UNNEST([
  STRUCT(
    'segment_session_reconciliation' AS check_name,
    IF(
      partition_metrics.segment_types = 4
      AND partition_metrics.reconciled_segment_types
        = partition_metrics.segment_types,
      'PASS',
      'FAIL'
    ) AS status,
    FORMAT(
      '%d of %d',
      partition_metrics.reconciled_segment_types,
      partition_metrics.segment_types
    ) AS actual_value,
    '4 of 4' AS expected_value,
    'Every segmentation exhaustively partitions all valid sessions' AS details
  ),
  STRUCT(
    'segment_metric_validity',
    IF(
      segment_metrics.invalid_rate_rows = 0
      AND segment_metrics.invalid_count_rows = 0
      AND segment_metrics.invalid_reportable_rows = 0,
      'PASS',
      'FAIL'
    ),
    FORMAT(
      '%d rate / %d count / %d threshold',
      segment_metrics.invalid_rate_rows,
      segment_metrics.invalid_count_rows,
      segment_metrics.invalid_reportable_rows
    ),
    '0 rate / 0 count / 0 threshold',
    'Rates, Wilson intervals, counts, and thresholds are valid'
  ),
  STRUCT(
    'segment_reportable_population',
    IF(
      segment_metrics.metric_rows > 0
      AND segment_metrics.reportable_rows > 0,
      'PASS',
      'FAIL'
    ),
    FORMAT(
      '%d of %d metric rows',
      segment_metrics.reportable_rows,
      segment_metrics.metric_rows
    ),
    'positive reportable population',
    'Preselected denominator rules retain analyzable comparisons'
  )
]) AS check_result
ORDER BY check_name;
