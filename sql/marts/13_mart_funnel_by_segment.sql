-- Grain: one segment value by one funnel/conversion metric.
-- Wilson intervals use z = 1.959963984540054. Segment comparisons are
-- descriptive associations, not causal effects.

CREATE OR REPLACE TABLE
  `{{ project_id }}.{{ dataset_id }}.mart_funnel_by_segment`
OPTIONS (
  description = 'Device, tenure, country, and channel conversion with Wilson intervals'
)
AS
WITH segmented_sessions AS (
  SELECT
    'Device' AS segment_type,
    device_category AS segment_value,
    sessions.*
  FROM `{{ project_id }}.{{ dataset_id }}.fct_sessions` AS sessions

  UNION ALL

  SELECT
    'User tenure',
    user_tenure,
    sessions.*
  FROM `{{ project_id }}.{{ dataset_id }}.fct_sessions` AS sessions

  UNION ALL

  SELECT
    'Country',
    CASE
      WHEN country IN (
        'United States',
        'India',
        'Canada',
        'United Kingdom',
        'France',
        'Spain',
        'Germany',
        'China',
        'Taiwan',
        'Italy',
        'Singapore',
        'Japan',
        'South Korea',
        'Netherlands',
        'Turkey'
      ) THEN country
      WHEN country IN ('[missing]', '[placeholder]') THEN country
      ELSE 'Other countries'
    END,
    sessions.*
  FROM `{{ project_id }}.{{ dataset_id }}.fct_sessions` AS sessions

  UNION ALL

  SELECT
    'Session channel proxy',
    channel_reporting_group,
    sessions.*
  FROM `{{ project_id }}.{{ dataset_id }}.fct_sessions` AS sessions
),
segment_rollup AS (
  SELECT
    segment_type,
    segment_value,
    COUNT(DISTINCT user_key) AS users,
    COUNT(*) AS sessions,
    COUNTIF(reached_view_item) AS view_sessions,
    COUNTIF(reached_add_to_cart_after_view) AS add_sessions,
    COUNTIF(reached_checkout_after_add_to_cart) AS checkout_sessions,
    COUNTIF(reached_purchase_after_checkout) AS ordered_purchase_sessions,
    COUNTIF(has_clean_purchase) AS purchasing_sessions,
    SUM(clean_orders) AS orders,
    SUM(clean_order_revenue_usd) AS revenue_usd
  FROM segmented_sessions
  GROUP BY segment_type, segment_value
),
long_metrics AS (
  SELECT
    segment_rollup.*,
    metric.metric_index,
    metric.metric_name,
    metric.numerator_sessions,
    metric.denominator_sessions,
    metric.minimum_denominator
  FROM segment_rollup
  CROSS JOIN UNNEST([
    STRUCT(
      1 AS metric_index,
      'purchase_session_conversion' AS metric_name,
      purchasing_sessions AS numerator_sessions,
      sessions AS denominator_sessions,
      500 AS minimum_denominator
    ),
    STRUCT(
      2,
      'view_to_cart',
      add_sessions,
      view_sessions,
      200
    ),
    STRUCT(
      3,
      'cart_to_checkout',
      checkout_sessions,
      add_sessions,
      200
    ),
    STRUCT(
      4,
      'checkout_to_purchase',
      ordered_purchase_sessions,
      checkout_sessions,
      200
    ),
    STRUCT(
      5,
      'ordered_view_to_purchase',
      ordered_purchase_sessions,
      view_sessions,
      200
    )
  ]) AS metric
),
rates AS (
  SELECT
    *,
    SAFE_DIVIDE(numerator_sessions, denominator_sessions) AS conversion_rate
  FROM long_metrics
)
SELECT
  segment_type,
  segment_value,
  metric_index,
  metric_name,
  users,
  sessions,
  view_sessions,
  add_sessions,
  checkout_sessions,
  ordered_purchase_sessions,
  purchasing_sessions,
  orders,
  revenue_usd,
  SAFE_DIVIDE(revenue_usd, orders) AS average_order_value_usd,
  SAFE_DIVIDE(revenue_usd, sessions) AS revenue_per_session_usd,
  numerator_sessions,
  denominator_sessions,
  conversion_rate,
  CASE
    WHEN denominator_sessions = 0 THEN NULL
    ELSE GREATEST(
      0.0,
      (
        conversion_rate
        + 3.841458820694124 / (2 * denominator_sessions)
        - 1.959963984540054 * SQRT(
          conversion_rate * (1 - conversion_rate) / denominator_sessions
          + 3.841458820694124
            / (4 * POW(denominator_sessions, 2))
        )
      )
      / (1 + 3.841458820694124 / denominator_sessions)
    )
  END AS conversion_rate_ci95_lower,
  CASE
    WHEN denominator_sessions = 0 THEN NULL
    ELSE LEAST(
      1.0,
      (
        conversion_rate
        + 3.841458820694124 / (2 * denominator_sessions)
        + 1.959963984540054 * SQRT(
          conversion_rate * (1 - conversion_rate) / denominator_sessions
          + 3.841458820694124
            / (4 * POW(denominator_sessions, 2))
        )
      )
      / (1 + 3.841458820694124 / denominator_sessions)
    )
  END AS conversion_rate_ci95_upper,
  denominator_sessions - numerator_sessions AS lost_sessions,
  minimum_denominator,
  sessions >= 500 AND denominator_sessions >= minimum_denominator
    AS is_reportable
FROM rates;
