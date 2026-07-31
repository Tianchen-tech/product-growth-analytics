-- Metric-tree and primary-funnel hard reconciliations.

WITH daily_metrics AS (
  SELECT
    COUNT(*) AS daily_rows,
    SUM(sessions) AS sessions,
    SUM(product_view_sessions) AS viewed_sessions,
    SUM(ordered_add_to_cart_sessions) AS added_sessions,
    SUM(ordered_checkout_sessions) AS checkout_sessions,
    SUM(ordered_purchase_sessions) AS ordered_purchase_sessions,
    SUM(purchasing_sessions) AS purchasing_sessions,
    SUM(orders) AS orders,
    SUM(revenue_usd) AS revenue_usd
  FROM `{{ project_id }}.{{ dataset_id }}.mart_metric_tree_daily`
),
summary_metrics AS (
  SELECT
    COUNT(*) AS summary_rows,
    ANY_VALUE(observed_calendar_days) AS observed_calendar_days,
    ANY_VALUE(pseudonymous_users) AS users,
    ANY_VALUE(sessions) AS sessions,
    ANY_VALUE(orders) AS orders,
    ANY_VALUE(revenue_usd) AS revenue_usd
  FROM `{{ project_id }}.{{ dataset_id }}.mart_metric_tree_summary`
),
funnel_metrics AS (
  SELECT
    COUNT(*) AS funnel_rows,
    MAX(IF(stage_name = 'view_item', sessions, NULL)) AS viewed_sessions,
    MAX(IF(stage_name = 'add_to_cart', sessions, NULL)) AS added_sessions,
    MAX(IF(stage_name = 'begin_checkout', sessions, NULL))
      AS checkout_sessions,
    MAX(IF(stage_name = 'purchase', sessions, NULL))
      AS ordered_purchase_sessions,
    COUNTIF(
      step_conversion_rate < 0 OR step_conversion_rate > 1
      OR cumulative_conversion_rate < 0
      OR cumulative_conversion_rate > 1
    ) AS invalid_rate_rows
  FROM `{{ project_id }}.{{ dataset_id }}.mart_funnel_overall`
)
SELECT check_result.*
FROM daily_metrics
CROSS JOIN summary_metrics
CROSS JOIN funnel_metrics
CROSS JOIN UNNEST([
  STRUCT(
    'daily_calendar_rows' AS check_name,
    IF(daily_metrics.daily_rows = 92, 'PASS', 'FAIL') AS status,
    CAST(daily_metrics.daily_rows AS STRING) AS actual_value,
    '92' AS expected_value,
    'One daily row per observed source date' AS details
  ),
  STRUCT(
    'daily_session_reconciliation',
    IF(daily_metrics.sessions = 360129, 'PASS', 'FAIL'),
    CAST(daily_metrics.sessions AS STRING),
    '360129',
    'Daily session sum equals session fact'
  ),
  STRUCT(
    'daily_funnel_reconciliation',
    IF(
      daily_metrics.viewed_sessions = 77020
      AND daily_metrics.added_sessions = 14380
      AND daily_metrics.checkout_sessions = 5187
      AND daily_metrics.ordered_purchase_sessions = 2491,
      'PASS',
      'FAIL'
    ),
    FORMAT(
      '%d>%d>%d>%d',
      daily_metrics.viewed_sessions,
      daily_metrics.added_sessions,
      daily_metrics.checkout_sessions,
      daily_metrics.ordered_purchase_sessions
    ),
    '77020>14380>5187>2491',
    'Daily funnel sums equal the governed ordered path'
  ),
  STRUCT(
    'daily_order_reconciliation',
    IF(
      daily_metrics.purchasing_sessions = 4021
      AND daily_metrics.orders = 4436
      AND ABS(daily_metrics.revenue_usd - 306678.0) < 0.01,
      'PASS',
      'FAIL'
    ),
    FORMAT(
      '%d sessions / %d orders / %.2f revenue',
      daily_metrics.purchasing_sessions,
      daily_metrics.orders,
      daily_metrics.revenue_usd
    ),
    '4021 sessions / 4436 orders / 306678.00 revenue',
    'Daily order metrics reconcile to governed facts'
  ),
  STRUCT(
    'summary_single_row',
    IF(
      summary_metrics.summary_rows = 1
      AND summary_metrics.observed_calendar_days = 92,
      'PASS',
      'FAIL'
    ),
    FORMAT(
      '%d rows / %d days',
      summary_metrics.summary_rows,
      summary_metrics.observed_calendar_days
    ),
    '1 rows / 92 days',
    'Summary has one complete-window row'
  ),
  STRUCT(
    'summary_core_totals',
    IF(
      summary_metrics.users = 270154
      AND summary_metrics.sessions = 360129
      AND summary_metrics.orders = 4436
      AND ABS(summary_metrics.revenue_usd - 306678.0) < 0.01,
      'PASS',
      'FAIL'
    ),
    FORMAT(
      '%d users / %d sessions / %d orders / %.2f revenue',
      summary_metrics.users,
      summary_metrics.sessions,
      summary_metrics.orders,
      summary_metrics.revenue_usd
    ),
    '270154 users / 360129 sessions / 4436 orders / 306678.00 revenue',
    'Summary reconciles to governed core totals'
  ),
  STRUCT(
    'overall_funnel_totals',
    IF(
      funnel_metrics.funnel_rows = 4
      AND funnel_metrics.viewed_sessions = 77020
      AND funnel_metrics.added_sessions = 14380
      AND funnel_metrics.checkout_sessions = 5187
      AND funnel_metrics.ordered_purchase_sessions = 2491,
      'PASS',
      'FAIL'
    ),
    FORMAT(
      '%d>%d>%d>%d',
      funnel_metrics.viewed_sessions,
      funnel_metrics.added_sessions,
      funnel_metrics.checkout_sessions,
      funnel_metrics.ordered_purchase_sessions
    ),
    '77020>14380>5187>2491',
    'Overall funnel reproduces locked ordered counts'
  ),
  STRUCT(
    'overall_funnel_rate_bounds',
    IF(funnel_metrics.invalid_rate_rows = 0, 'PASS', 'FAIL'),
    CAST(funnel_metrics.invalid_rate_rows AS STRING),
    '0',
    'Overall funnel proportions remain within zero and one'
  )
]) AS check_result
ORDER BY check_name;
