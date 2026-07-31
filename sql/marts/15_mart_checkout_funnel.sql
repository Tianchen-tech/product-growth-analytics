-- Grain: one stage in the strict checkout telemetry sequence.
-- The any-intermediate purchase count is repeated as a diagnostic because some
-- valid purchases do not contain every shipping/payment event.

CREATE OR REPLACE TABLE
  `{{ project_id }}.{{ dataset_id }}.mart_checkout_funnel`
OPTIONS (
  description = 'Ordered checkout telemetry from begin checkout through clean purchase'
)
AS
WITH eligible_checkouts AS (
  SELECT
    session_key,
    begin_checkout_event_timestamp,
    reached_purchase_after_checkout,
    purchase_event_timestamp
  FROM `{{ project_id }}.{{ dataset_id }}.int_checkout_sessions`
),
shipping_added AS (
  SELECT
    eligible_checkouts.session_key,
    eligible_checkouts.begin_checkout_event_timestamp,
    eligible_checkouts.reached_purchase_after_checkout,
    eligible_checkouts.purchase_event_timestamp,
    MIN(events.event_timestamp) AS shipping_event_timestamp
  FROM eligible_checkouts
  JOIN `{{ project_id }}.{{ dataset_id }}.stg_events` AS events
    ON events.session_key = eligible_checkouts.session_key
   AND events.event_name = 'add_shipping_info'
   AND events.event_timestamp
     > eligible_checkouts.begin_checkout_event_timestamp
  GROUP BY
    eligible_checkouts.session_key,
    eligible_checkouts.begin_checkout_event_timestamp,
    eligible_checkouts.reached_purchase_after_checkout,
    eligible_checkouts.purchase_event_timestamp
),
payment_added AS (
  SELECT
    shipping_added.session_key,
    shipping_added.reached_purchase_after_checkout,
    shipping_added.purchase_event_timestamp,
    shipping_added.shipping_event_timestamp,
    MIN(events.event_timestamp) AS payment_event_timestamp
  FROM shipping_added
  JOIN `{{ project_id }}.{{ dataset_id }}.stg_events` AS events
    ON events.session_key = shipping_added.session_key
   AND events.event_name = 'add_payment_info'
   AND events.event_timestamp > shipping_added.shipping_event_timestamp
  GROUP BY
    shipping_added.session_key,
    shipping_added.reached_purchase_after_checkout,
    shipping_added.purchase_event_timestamp,
    shipping_added.shipping_event_timestamp
),
strict_purchased AS (
  SELECT
    payment_added.session_key
  FROM payment_added
  WHERE payment_added.purchase_event_timestamp
    > payment_added.payment_event_timestamp
),
counts AS (
  SELECT
    (SELECT COUNT(*) FROM eligible_checkouts) AS checkout_sessions,
    (SELECT COUNT(*) FROM shipping_added) AS shipping_sessions,
    (SELECT COUNT(*) FROM payment_added) AS payment_sessions,
    (SELECT COUNT(*) FROM strict_purchased) AS strict_purchase_sessions,
    (
      SELECT COUNTIF(reached_purchase_after_checkout)
      FROM eligible_checkouts
    ) AS any_intermediate_purchase_sessions
),
stages AS (
  SELECT 1 AS stage_index, 'begin_checkout' AS stage_name,
    checkout_sessions AS sessions
  FROM counts
  UNION ALL
  SELECT 2, 'add_shipping_info', shipping_sessions
  FROM counts
  UNION ALL
  SELECT 3, 'add_payment_info', payment_sessions
  FROM counts
  UNION ALL
  SELECT 4, 'purchase_after_payment', strict_purchase_sessions
  FROM counts
),
sequenced AS (
  SELECT
    stage_index,
    stage_name,
    sessions,
    LAG(sessions) OVER (ORDER BY stage_index) AS prior_stage_sessions,
    FIRST_VALUE(sessions) OVER (ORDER BY stage_index) AS first_stage_sessions
  FROM stages
),
rates AS (
  SELECT
    *,
    IF(
      stage_index = 1,
      1.0,
      SAFE_DIVIDE(sessions, prior_stage_sessions)
    ) AS step_conversion_rate
  FROM sequenced
)
SELECT
  stage_index,
  stage_name,
  sessions,
  prior_stage_sessions,
  step_conversion_rate,
  CASE
    WHEN stage_index = 1 THEN 1.0
    WHEN prior_stage_sessions = 0 THEN NULL
    ELSE GREATEST(
      0.0,
      (
        step_conversion_rate
        + 3.841458820694124 / (2 * prior_stage_sessions)
        - 1.959963984540054 * SQRT(
          step_conversion_rate * (1 - step_conversion_rate)
            / prior_stage_sessions
          + 3.841458820694124 / (4 * POW(prior_stage_sessions, 2))
        )
      )
      / (1 + 3.841458820694124 / prior_stage_sessions)
    )
  END AS step_conversion_rate_ci95_lower,
  CASE
    WHEN stage_index = 1 THEN 1.0
    WHEN prior_stage_sessions = 0 THEN NULL
    ELSE LEAST(
      1.0,
      (
        step_conversion_rate
        + 3.841458820694124 / (2 * prior_stage_sessions)
        + 1.959963984540054 * SQRT(
          step_conversion_rate * (1 - step_conversion_rate)
            / prior_stage_sessions
          + 3.841458820694124 / (4 * POW(prior_stage_sessions, 2))
        )
      )
      / (1 + 3.841458820694124 / prior_stage_sessions)
    )
  END AS step_conversion_rate_ci95_upper,
  SAFE_DIVIDE(sessions, first_stage_sessions) AS cumulative_conversion_rate,
  IF(stage_index = 1, 0, prior_stage_sessions - sessions)
    AS lost_sessions_from_prior_stage,
  (SELECT any_intermediate_purchase_sessions FROM counts)
    AS purchase_after_checkout_sessions,
  SAFE_DIVIDE(
    (SELECT any_intermediate_purchase_sessions FROM counts),
    (SELECT checkout_sessions FROM counts)
  ) AS purchase_after_checkout_rate,
  'Strict same-session event ordering; clean purchase required'
    AS measurement_rule
FROM rates;
