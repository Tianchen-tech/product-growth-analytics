-- Aggregate checkout telemetry diagnostic.
--
-- Purpose:
--   1. classify every governed ordered checkout session into one exclusive
--      shipping/payment/purchase path;
--   2. measure intermediate-event coverage by device, user tenure, purchase
--      outcome, calendar week, and flagged source-volume dates; and
--   3. surface timing and duplication signals that can distinguish product
--      behavior from instrumentation risk.
--
-- Privacy:
--   The final output is aggregate only. Session and user identifiers are used
--   for joins but are never selected.

-- The governed views are deliberately materialized into session-scoped
-- temporary tables. This prevents BigQuery from repeatedly expanding the
-- complete nested view graph during one query-planning step.

CREATE TEMP TABLE eligible_sessions AS
SELECT
  checkout.session_key,
  checkout.begin_checkout_event_timestamp,
  checkout.reached_purchase_after_checkout,
  checkout.purchase_event_timestamp,
  sessions.session_end_event_timestamp,
  sessions.session_date,
  sessions.device_category,
  sessions.user_tenure,
  sessions.is_low_volume_date,
  sessions.is_high_volume_date
FROM `{{ project_id }}.{{ dataset_id }}.int_checkout_sessions` AS checkout
JOIN `{{ project_id }}.{{ dataset_id }}.fct_sessions` AS sessions
  USING (session_key);

CREATE TEMP TABLE relevant_events AS
SELECT
  eligible_sessions.*,
  events.event_name,
  events.event_timestamp
FROM eligible_sessions
LEFT JOIN `{{ project_id }}.{{ dataset_id }}.stg_events` AS events
  ON events.session_key = eligible_sessions.session_key
 AND events.event_name IN (
   'begin_checkout',
   'add_shipping_info',
   'add_payment_info'
 );

CREATE TEMP TABLE event_rollup AS
SELECT
  session_key,
  begin_checkout_event_timestamp,
  reached_purchase_after_checkout,
  purchase_event_timestamp,
  session_end_event_timestamp,
  session_date,
  device_category,
  user_tenure,
  is_low_volume_date,
  is_high_volume_date,
  COUNTIF(event_name = 'begin_checkout') AS begin_checkout_event_rows,
  COUNTIF(
    event_name = 'add_shipping_info'
    AND event_timestamp > begin_checkout_event_timestamp
    AND (
      purchase_event_timestamp IS NULL
      OR event_timestamp < purchase_event_timestamp
    )
  ) AS shipping_event_rows_in_observation_window,
  COUNTIF(
    event_name = 'add_payment_info'
    AND event_timestamp > begin_checkout_event_timestamp
    AND (
      purchase_event_timestamp IS NULL
      OR event_timestamp < purchase_event_timestamp
    )
  ) AS payment_event_rows_in_observation_window,
  MIN(
    IF(
      event_name = 'add_shipping_info'
      AND event_timestamp > begin_checkout_event_timestamp
      AND (
        purchase_event_timestamp IS NULL
        OR event_timestamp < purchase_event_timestamp
      ),
      event_timestamp,
      NULL
    )
  ) AS first_shipping_event_timestamp,
  MIN(
    IF(
      event_name = 'add_payment_info'
      AND event_timestamp > begin_checkout_event_timestamp
      AND (
        purchase_event_timestamp IS NULL
        OR event_timestamp < purchase_event_timestamp
      ),
      event_timestamp,
      NULL
    )
  ) AS first_payment_event_timestamp,
  COUNTIF(
    event_name = 'add_shipping_info'
    AND event_timestamp <= begin_checkout_event_timestamp
  ) AS shipping_event_rows_at_or_before_checkout,
  COUNTIF(
    event_name = 'add_payment_info'
    AND event_timestamp <= begin_checkout_event_timestamp
  ) AS payment_event_rows_at_or_before_checkout,
  COUNTIF(
    event_name = 'add_shipping_info'
    AND purchase_event_timestamp IS NOT NULL
    AND event_timestamp >= purchase_event_timestamp
  ) AS shipping_event_rows_at_or_after_purchase,
  COUNTIF(
    event_name = 'add_payment_info'
    AND purchase_event_timestamp IS NOT NULL
    AND event_timestamp >= purchase_event_timestamp
  ) AS payment_event_rows_at_or_after_purchase
FROM relevant_events
GROUP BY
  session_key,
  begin_checkout_event_timestamp,
  reached_purchase_after_checkout,
  purchase_event_timestamp,
  session_end_event_timestamp,
  session_date,
  device_category,
  user_tenure,
  is_low_volume_date,
  is_high_volume_date;

CREATE TEMP TABLE classified AS
WITH ordered_intermediate AS (
  SELECT
    event_rollup.session_key,
    MIN(events.event_timestamp) AS payment_after_shipping_event_timestamp
  FROM event_rollup
  JOIN relevant_events AS events
    ON events.session_key = event_rollup.session_key
   AND events.event_name = 'add_payment_info'
   AND events.event_timestamp
     > event_rollup.first_shipping_event_timestamp
   AND (
     event_rollup.purchase_event_timestamp IS NULL
     OR events.event_timestamp < event_rollup.purchase_event_timestamp
   )
  WHERE event_rollup.first_shipping_event_timestamp IS NOT NULL
  GROUP BY event_rollup.session_key
),
features AS (
  SELECT
    event_rollup.*,
    event_rollup.first_shipping_event_timestamp IS NOT NULL
      AS has_shipping_in_observation_window,
    event_rollup.first_payment_event_timestamp IS NOT NULL
      AS has_payment_in_observation_window,
    ordered_intermediate.payment_after_shipping_event_timestamp IS NOT NULL
      AS has_ordered_shipping_payment,
    event_rollup.reached_purchase_after_checkout
      AND ordered_intermediate.payment_after_shipping_event_timestamp
        IS NOT NULL
      AS has_strict_sequence_purchase
  FROM event_rollup
  LEFT JOIN ordered_intermediate USING (session_key)
)
SELECT
  *,
  CASE
    WHEN reached_purchase_after_checkout
      AND has_ordered_shipping_payment
      THEN '01_purchase_full_shipping_payment'
    WHEN reached_purchase_after_checkout
      AND has_shipping_in_observation_window
      AND NOT has_payment_in_observation_window
      THEN '02_purchase_shipping_only'
    WHEN reached_purchase_after_checkout
      AND NOT has_shipping_in_observation_window
      AND has_payment_in_observation_window
      THEN '03_purchase_payment_only'
    WHEN reached_purchase_after_checkout
      AND NOT has_shipping_in_observation_window
      AND NOT has_payment_in_observation_window
      THEN '04_purchase_no_intermediate'
    WHEN reached_purchase_after_checkout
      THEN '05_purchase_intermediate_order_anomaly'
    WHEN has_ordered_shipping_payment
      THEN '06_no_purchase_full_shipping_payment'
    WHEN has_shipping_in_observation_window
      AND NOT has_payment_in_observation_window
      THEN '07_no_purchase_shipping_only'
    WHEN NOT has_shipping_in_observation_window
      AND has_payment_in_observation_window
      THEN '08_no_purchase_payment_only'
    WHEN NOT has_shipping_in_observation_window
      AND NOT has_payment_in_observation_window
      THEN '09_no_purchase_no_intermediate'
    ELSE '10_no_purchase_intermediate_order_anomaly'
  END AS telemetry_path_class
FROM features;

WITH classified_totals AS (
  SELECT
    COUNT(*) AS checkout_sessions,
    COUNTIF(reached_purchase_after_checkout) AS purchase_sessions,
    COUNTIF(has_strict_sequence_purchase) AS strict_purchase_sessions
  FROM classified
),
mart_reference AS (
  SELECT
    MAX(IF(stage_name = 'begin_checkout', sessions, NULL))
      AS checkout_sessions,
    MAX(purchase_after_checkout_sessions) AS purchase_sessions,
    MAX(IF(stage_name = 'purchase_after_payment', sessions, NULL))
      AS strict_purchase_sessions
  FROM `{{ project_id }}.{{ dataset_id }}.mart_checkout_funnel`
),
reconciliation AS (
  SELECT
    IF(
      classified_totals.checkout_sessions
        = mart_reference.checkout_sessions
      AND classified_totals.purchase_sessions
        = mart_reference.purchase_sessions
      AND classified_totals.strict_purchase_sessions
        = mart_reference.strict_purchase_sessions,
      'PASS',
      'FAIL'
    ) AS reconciliation_status
  FROM classified_totals
  CROSS JOIN mart_reference
),
dimension_rows AS (
  SELECT
    1 AS dimension_index,
    'Overall' AS dimension_type,
    'All checkout sessions' AS dimension_value,
    1 AS minimum_denominator,
    classified.*
  FROM classified

  UNION ALL

  SELECT
    2,
    'Device',
    device_category,
    50,
    classified.*
  FROM classified

  UNION ALL

  SELECT
    3,
    'User tenure',
    user_tenure,
    50,
    classified.*
  FROM classified

  UNION ALL

  SELECT
    4,
    'Purchase outcome',
    IF(
      reached_purchase_after_checkout,
      'Purchased after checkout',
      'No purchase after checkout'
    ),
    50,
    classified.*
  FROM classified

  UNION ALL

  SELECT
    5,
    'Session week',
    CAST(DATE_TRUNC(session_date, WEEK(MONDAY)) AS STRING),
    50,
    classified.*
  FROM classified

  UNION ALL

  SELECT
    6,
    'Source volume date status',
    CASE
      WHEN is_low_volume_date THEN 'Low-volume flagged date'
      WHEN is_high_volume_date THEN 'High-volume flagged date'
      ELSE 'Regular-volume date'
    END,
    50,
    classified.*
  FROM classified
),
coverage_counts AS (
  SELECT
    dimension_index,
    dimension_type,
    dimension_value,
    minimum_denominator,
    COUNT(*) AS checkout_sessions,
    COUNTIF(reached_purchase_after_checkout) AS purchase_sessions,
    COUNTIF(has_shipping_in_observation_window) AS shipping_sessions,
    COUNTIF(has_payment_in_observation_window) AS payment_sessions,
    COUNTIF(has_ordered_shipping_payment)
      AS ordered_shipping_payment_sessions,
    COUNTIF(has_strict_sequence_purchase) AS strict_purchase_sessions
  FROM dimension_rows
  GROUP BY
    dimension_index,
    dimension_type,
    dimension_value,
    minimum_denominator
),
coverage_metrics AS (
  SELECT
    2 AS section_index,
    'coverage_by_dimension' AS diagnostic_section,
    dimension_index,
    dimension_type,
    dimension_value,
    metrics.metric_index,
    metrics.metric_name,
    metrics.numerator_sessions,
    metrics.denominator_sessions,
    minimum_denominator,
    metrics.measurement_rule
  FROM coverage_counts
  CROSS JOIN UNNEST([
    STRUCT(
      1 AS metric_index,
      'purchase_after_checkout_rate' AS metric_name,
      purchase_sessions AS numerator_sessions,
      checkout_sessions AS denominator_sessions,
      'Clean purchase after ordered checkout; intermediate events optional'
        AS measurement_rule
    ),
    STRUCT(
      2,
      'shipping_event_coverage_rate',
      shipping_sessions,
      checkout_sessions,
      'At least one add_shipping_info after checkout and before purchase/session end'
    ),
    STRUCT(
      3,
      'payment_event_coverage_rate',
      payment_sessions,
      checkout_sessions,
      'At least one add_payment_info after checkout and before purchase/session end'
    ),
    STRUCT(
      4,
      'ordered_shipping_payment_coverage_rate',
      ordered_shipping_payment_sessions,
      checkout_sessions,
      'Recorded add_shipping_info followed by add_payment_info before purchase/session end'
    ),
    STRUCT(
      5,
      'strict_sequence_purchase_rate_of_checkout',
      strict_purchase_sessions,
      checkout_sessions,
      'Clean purchase after recorded ordered shipping and payment events'
    ),
    STRUCT(
      6,
      'strict_intermediate_coverage_rate_of_purchases',
      strict_purchase_sessions,
      purchase_sessions,
      'Purchases containing the full recorded shipping then payment sequence'
    ),
    STRUCT(
      7,
      'purchase_telemetry_gap_rate',
      purchase_sessions - strict_purchase_sessions,
      purchase_sessions,
      'Purchases missing the full recorded shipping then payment sequence'
    )
  ]) AS metrics
),
path_counts AS (
  SELECT
    telemetry_path_class,
    COUNT(*) AS path_sessions
  FROM classified
  GROUP BY telemetry_path_class
),
path_metrics AS (
  SELECT
    1 AS section_index,
    'exclusive_path_distribution' AS diagnostic_section,
    1 AS dimension_index,
    'Overall' AS dimension_type,
    'All checkout sessions' AS dimension_value,
    ROW_NUMBER() OVER (ORDER BY telemetry_path_class) AS metric_index,
    telemetry_path_class AS metric_name,
    path_sessions AS numerator_sessions,
    SUM(path_sessions) OVER () AS denominator_sessions,
    1 AS minimum_denominator,
    'Mutually exclusive events after ordered checkout and before purchase/session end'
      AS measurement_rule
  FROM path_counts
),
quality_flag_metrics AS (
  SELECT
    3 AS section_index,
    'timing_and_duplication_flags' AS diagnostic_section,
    1 AS dimension_index,
    'Overall' AS dimension_type,
    'All checkout sessions' AS dimension_value,
    flags.metric_index,
    flags.metric_name,
    COUNTIF(flags.is_flagged) AS numerator_sessions,
    COUNT(*) AS denominator_sessions,
    1 AS minimum_denominator,
    flags.measurement_rule
  FROM classified
  CROSS JOIN UNNEST([
    STRUCT(
      1 AS metric_index,
      'multiple_begin_checkout_events' AS metric_name,
      begin_checkout_event_rows > 1 AS is_flagged,
      'More than one begin_checkout event anywhere in the eligible session'
        AS measurement_rule
    ),
    STRUCT(
      2,
      'multiple_shipping_events_in_observation_window',
      shipping_event_rows_in_observation_window > 1,
      'More than one qualifying add_shipping_info before purchase/session end'
    ),
    STRUCT(
      3,
      'multiple_payment_events_in_observation_window',
      payment_event_rows_in_observation_window > 1,
      'More than one qualifying add_payment_info before purchase/session end'
    ),
    STRUCT(
      4,
      'shipping_event_at_or_before_checkout',
      shipping_event_rows_at_or_before_checkout > 0,
      'Recorded add_shipping_info is not strictly after the governed checkout start'
    ),
    STRUCT(
      5,
      'payment_event_at_or_before_checkout',
      payment_event_rows_at_or_before_checkout > 0,
      'Recorded add_payment_info is not strictly after the governed checkout start'
    ),
    STRUCT(
      6,
      'shipping_event_at_or_after_purchase',
      shipping_event_rows_at_or_after_purchase > 0,
      'Recorded add_shipping_info is not strictly before the clean purchase'
    ),
    STRUCT(
      7,
      'payment_event_at_or_after_purchase',
      payment_event_rows_at_or_after_purchase > 0,
      'Recorded add_payment_info is not strictly before the clean purchase'
    ),
    STRUCT(
      8,
      'intermediate_event_order_anomaly',
      has_shipping_in_observation_window
        AND has_payment_in_observation_window
        AND NOT has_ordered_shipping_payment,
      'Both intermediate event types exist but no shipping-to-payment order exists'
    ),
    STRUCT(
      9,
      'purchase_missing_full_intermediate_sequence',
      reached_purchase_after_checkout
        AND NOT has_strict_sequence_purchase,
      'Clean purchase exists without the full recorded shipping-to-payment sequence'
    )
  ]) AS flags
  GROUP BY
    flags.metric_index,
    flags.metric_name,
    flags.measurement_rule
),
gap_context_metrics AS (
  SELECT
    3 AS section_index,
    'timing_and_duplication_flags' AS diagnostic_section,
    1 AS dimension_index,
    'Purchase telemetry gap' AS dimension_type,
    'Purchases missing the full intermediate sequence' AS dimension_value,
    flags.metric_index,
    flags.metric_name,
    COUNTIF(
      reached_purchase_after_checkout
      AND NOT has_strict_sequence_purchase
      AND flags.has_context
    ) AS numerator_sessions,
    COUNTIF(
      reached_purchase_after_checkout
      AND NOT has_strict_sequence_purchase
    ) AS denominator_sessions,
    1 AS minimum_denominator,
    flags.measurement_rule
  FROM classified
  CROSS JOIN UNNEST([
    STRUCT(
      10 AS metric_index,
      'gap_has_shipping_at_or_before_checkout' AS metric_name,
      shipping_event_rows_at_or_before_checkout > 0 AS has_context,
      'Gap purchase also has add_shipping_info at or before the governed checkout start'
        AS measurement_rule
    ),
    STRUCT(
      11,
      'gap_has_shipping_at_or_after_purchase',
      shipping_event_rows_at_or_after_purchase > 0,
      'Gap purchase also has add_shipping_info at or after the clean purchase'
    ),
    STRUCT(
      12,
      'gap_has_no_shipping_event_anywhere',
      shipping_event_rows_at_or_before_checkout = 0
        AND shipping_event_rows_in_observation_window = 0
        AND shipping_event_rows_at_or_after_purchase = 0,
      'Gap purchase contains no add_shipping_info anywhere in the eligible session'
    ),
    STRUCT(
      13,
      'gap_has_payment_before_purchase',
      payment_event_rows_in_observation_window > 0,
      'Gap purchase still has add_payment_info after checkout and before purchase'
    ),
    STRUCT(
      14,
      'gap_has_no_payment_before_purchase',
      payment_event_rows_in_observation_window = 0,
      'Gap purchase has no add_payment_info after checkout and before purchase'
    ),
    STRUCT(
      15,
      'gap_has_any_pre_checkout_intermediate_event',
      shipping_event_rows_at_or_before_checkout > 0
        OR payment_event_rows_at_or_before_checkout > 0,
      'Gap purchase has shipping or payment telemetry at or before the governed checkout start'
    )
  ]) AS flags
  GROUP BY
    flags.metric_index,
    flags.metric_name,
    flags.measurement_rule
),
all_metrics AS (
  SELECT * FROM path_metrics
  UNION ALL
  SELECT * FROM coverage_metrics
  UNION ALL
  SELECT * FROM quality_flag_metrics
  UNION ALL
  SELECT * FROM gap_context_metrics
),
rates AS (
  SELECT
    *,
    SAFE_DIVIDE(numerator_sessions, denominator_sessions) AS metric_rate
  FROM all_metrics
)
SELECT
  diagnostic_section,
  dimension_type,
  dimension_value,
  metric_name,
  numerator_sessions,
  denominator_sessions,
  metric_rate,
  CASE
    WHEN denominator_sessions = 0 THEN NULL
    ELSE GREATEST(
      0.0,
      (
        metric_rate
        + 3.841458820694124 / (2 * denominator_sessions)
        - 1.959963984540054 * SQRT(
          metric_rate * (1 - metric_rate) / denominator_sessions
          + 3.841458820694124
            / (4 * POW(denominator_sessions, 2))
        )
      )
      / (1 + 3.841458820694124 / denominator_sessions)
    )
  END AS metric_rate_ci95_lower,
  CASE
    WHEN denominator_sessions = 0 THEN NULL
    ELSE LEAST(
      1.0,
      (
        metric_rate
        + 3.841458820694124 / (2 * denominator_sessions)
        + 1.959963984540054 * SQRT(
          metric_rate * (1 - metric_rate) / denominator_sessions
          + 3.841458820694124
            / (4 * POW(denominator_sessions, 2))
        )
      )
      / (1 + 3.841458820694124 / denominator_sessions)
    )
  END AS metric_rate_ci95_upper,
  minimum_denominator,
  denominator_sessions >= minimum_denominator AS is_reportable,
  measurement_rule,
  reconciliation.reconciliation_status
FROM rates
CROSS JOIN reconciliation
ORDER BY
  section_index,
  dimension_index,
  dimension_value,
  metric_index;
