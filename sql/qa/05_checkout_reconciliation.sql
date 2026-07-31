-- Ordered checkout-subfunnel checks.

WITH checkout_metrics AS (
  SELECT
    COUNT(*) AS checkout_rows,
    MAX(IF(stage_index = 1, sessions, NULL)) AS checkout_sessions,
    MAX(IF(stage_index = 4, sessions, NULL)) AS strict_purchase_sessions,
    MAX(purchase_after_checkout_sessions) AS any_path_purchase_sessions,
    COUNTIF(stage_index > 1 AND sessions > prior_stage_sessions)
      AS non_monotonic_rows,
    COUNTIF(
      step_conversion_rate < 0 OR step_conversion_rate > 1
      OR cumulative_conversion_rate < 0
      OR cumulative_conversion_rate > 1
      OR step_conversion_rate_ci95_lower < 0
      OR step_conversion_rate_ci95_upper > 1
    ) AS invalid_rate_rows
  FROM `{{ project_id }}.{{ dataset_id }}.mart_checkout_funnel`
)
SELECT check_result.*
FROM checkout_metrics
CROSS JOIN UNNEST([
  STRUCT(
    'checkout_stage_reconciliation' AS check_name,
    IF(
      checkout_metrics.checkout_rows = 4
      AND checkout_metrics.checkout_sessions = 5187
      AND checkout_metrics.any_path_purchase_sessions = 2491
      AND checkout_metrics.strict_purchase_sessions
        <= checkout_metrics.any_path_purchase_sessions,
      'PASS',
      'FAIL'
    ) AS status,
    FORMAT(
      '%d checkout / %d strict purchase / %d any-path purchase',
      checkout_metrics.checkout_sessions,
      checkout_metrics.strict_purchase_sessions,
      checkout_metrics.any_path_purchase_sessions
    ) AS actual_value,
    '5187 checkout / strict <= 2491 / 2491 any-path purchase'
      AS expected_value,
    'Checkout entry and outcome reconcile to the primary funnel' AS details
  ),
  STRUCT(
    'checkout_metric_validity',
    IF(
      checkout_metrics.non_monotonic_rows = 0
      AND checkout_metrics.invalid_rate_rows = 0,
      'PASS',
      'FAIL'
    ),
    FORMAT(
      '%d monotonic / %d rate',
      checkout_metrics.non_monotonic_rows,
      checkout_metrics.invalid_rate_rows
    ),
    '0 monotonic / 0 rate',
    'Strict checkout stages are monotonic with bounded rates'
  )
]) AS check_result
ORDER BY check_name;
