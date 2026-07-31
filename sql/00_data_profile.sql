-- Product Growth Analytics
-- File: sql/00_data_profile.sql
-- Dialect: BigQuery Standard SQL
-- Source: bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*
-- Observation window: 2020-11-01 through 2021-01-31
--
-- PURPOSE
-- -------
-- Validate the source fields and analytical assumptions before building any
-- downstream model or making a product recommendation.
--
-- EXECUTION
-- ---------
-- Run one numbered query at a time in BigQuery Studio. Each query is read-only.
-- Check the estimated bytes processed before running. Keep the date filter on
-- _TABLE_SUFFIX so BigQuery can prune the daily wildcard tables.
--
-- IMPORTANT MODELING RULES
-- ------------------------
-- 1. A session is identified by user_pseudo_id + ga_session_id. ga_session_id
--    alone is not assumed to be globally unique.
-- 2. event_params and items are repeated records. Do not unnest both in the
--    same fact query without first controlling the resulting grain.
-- 3. Purchase revenue is measured at the event/order grain. Unnesting items
--    before summing event revenue can multiply revenue.
-- 4. Empty transaction IDs and missing session IDs are surfaced, not silently
--    replaced.
-- 5. The ordered funnel requires a later timestamp at every subsequent step.


-- ============================================================================
-- 00.1 TABLE COVERAGE AND TOP-LINE VOLUME
-- Expected date range: 2020-11-01 through 2021-01-31.
-- Review any difference before continuing.
-- ============================================================================

SELECT
  MIN(PARSE_DATE('%Y%m%d', event_date)) AS min_event_date,
  MAX(PARSE_DATE('%Y%m%d', event_date)) AS max_event_date,
  COUNT(DISTINCT event_date) AS observed_calendar_days,
  COUNT(DISTINCT _TABLE_SUFFIX) AS source_tables,
  COUNT(*) AS event_rows,
  COUNT(DISTINCT user_pseudo_id) AS pseudonymous_users,
  COUNTIF(user_pseudo_id IS NULL OR user_pseudo_id = '') AS rows_missing_user_pseudo_id
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131';


-- ============================================================================
-- 00.2 DAILY COMPLETENESS
-- Returns one reconciliation row plus compact lists of extreme-volume dates.
-- A zero event count indicates a missing or empty daily table in the window.
-- The 50% / 200% median thresholds are diagnostic flags, not exclusion rules.
-- ============================================================================

WITH calendar AS (
  SELECT day
  FROM UNNEST(
    GENERATE_DATE_ARRAY(DATE '2020-11-01', DATE '2021-01-31')
  ) AS day
),
daily AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS day,
    COUNT(*) AS event_rows,
    COUNT(DISTINCT user_pseudo_id) AS users
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
  GROUP BY 1
),
daily_complete AS (
  SELECT
    calendar.day,
    COALESCE(daily.event_rows, 0) AS event_rows,
    COALESCE(daily.users, 0) AS users
  FROM calendar
  LEFT JOIN daily USING (day)
),
daily_with_stats AS (
  SELECT
    *,
    PERCENTILE_CONT(
      CAST(NULLIF(event_rows, 0) AS FLOAT64),
      0.05
    ) OVER () AS p05_event_rows,
    PERCENTILE_CONT(
      CAST(NULLIF(event_rows, 0) AS FLOAT64),
      0.50
    ) OVER () AS median_event_rows,
    PERCENTILE_CONT(
      CAST(NULLIF(event_rows, 0) AS FLOAT64),
      0.95
    ) OVER () AS p95_event_rows
  FROM daily_complete
)
SELECT
  COUNT(*) AS expected_calendar_days,
  COUNTIF(event_rows > 0) AS observed_event_days,
  COUNTIF(event_rows = 0) AS missing_or_empty_days,
  SUM(event_rows) AS total_event_rows,
  ROUND(AVG(NULLIF(event_rows, 0)), 2) AS avg_observed_daily_event_rows,
  MIN(NULLIF(event_rows, 0)) AS min_observed_daily_event_rows,
  ARRAY_AGG(
    IF(event_rows > 0, day, NULL) IGNORE NULLS
    ORDER BY event_rows, day
    LIMIT 1
  )[SAFE_OFFSET(0)] AS min_volume_day,
  ROUND(MAX(p05_event_rows), 2) AS p05_daily_event_rows,
  ROUND(MAX(median_event_rows), 2) AS median_daily_event_rows,
  ROUND(MAX(p95_event_rows), 2) AS p95_daily_event_rows,
  MAX(event_rows) AS max_daily_event_rows,
  ARRAY_AGG(
    IF(event_rows > 0, day, NULL) IGNORE NULLS
    ORDER BY event_rows DESC, day
    LIMIT 1
  )[SAFE_OFFSET(0)] AS max_volume_day,
  COUNTIF(
    event_rows > 0
    AND event_rows < 0.5 * median_event_rows
  ) AS low_volume_days,
  COUNTIF(
    event_rows > 2.0 * median_event_rows
  ) AS high_volume_days,
  STRING_AGG(
    IF(event_rows = 0, FORMAT_DATE('%F', day), NULL),
    ', ' ORDER BY day
  ) AS missing_or_empty_dates,
  STRING_AGG(
    IF(
      event_rows > 0 AND event_rows < 0.5 * median_event_rows,
      FORMAT('%s (%d)', FORMAT_DATE('%F', day), event_rows),
      NULL
    ),
    ', ' ORDER BY day
  ) AS low_volume_dates,
  STRING_AGG(
    IF(
      event_rows > 2.0 * median_event_rows,
      FORMAT('%s (%d)', FORMAT_DATE('%F', day), event_rows),
      NULL
    ),
    ', ' ORDER BY day
  ) AS high_volume_dates
FROM daily_with_stats;


-- ============================================================================
-- 00.3 EVENT INVENTORY
-- Shows the event taxonomy, volume, user reach, and valid composite-session
-- reach. Pay particular attention to the four funnel events.
-- ============================================================================

WITH event_base AS (
  SELECT
    event_name,
    user_pseudo_id,
    (
      SELECT ANY_VALUE(value.int_value)
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
)
SELECT
  event_name,
  COUNT(*) AS event_rows,
  COUNT(DISTINCT user_pseudo_id) AS users,
  COUNT(
    DISTINCT IF(
      user_pseudo_id IS NOT NULL AND ga_session_id IS NOT NULL,
      CONCAT(user_pseudo_id, '#', CAST(ga_session_id AS STRING)),
      NULL
    )
  ) AS sessions,
  ROUND(100 * SAFE_DIVIDE(COUNT(*), SUM(COUNT(*)) OVER ()), 2) AS event_row_share_pct
FROM event_base
GROUP BY event_name
ORDER BY event_rows DESC, event_name;


-- ============================================================================
-- 00.4 EVENT PARAMETER INVENTORY
-- Confirms which implementation-specific keys actually exist and which value
-- field stores each parameter. This can return many rows.
-- ============================================================================

SELECT
  parameter.key AS parameter_key,
  COUNT(*) AS parameter_occurrences,
  COUNT(DISTINCT event_name) AS event_types_using_parameter,
  COUNTIF(parameter.value.string_value IS NOT NULL) AS string_value_occurrences,
  COUNTIF(parameter.value.int_value IS NOT NULL) AS int_value_occurrences,
  COUNTIF(parameter.value.double_value IS NOT NULL) AS double_value_occurrences,
  COUNTIF(parameter.value.float_value IS NOT NULL) AS float_value_occurrences
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`,
UNNEST(event_params) AS parameter
WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
GROUP BY parameter_key
ORDER BY parameter_occurrences DESC, parameter_key;


-- ============================================================================
-- 00.5 CRITICAL PARAMETER COVERAGE
-- Missing or sparse values can change the metric definitions. In particular:
-- - ga_session_id is required for the primary session grain.
-- - ga_session_number / first_visit support new-versus-returning analysis.
-- - page_location / page_title determine whether a page-level claim is valid.
-- - source / medium may support session-source analysis only after validation.
-- ============================================================================

WITH total AS (
  SELECT COUNT(*) AS event_rows
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
),
parameter_hits AS (
  SELECT
    parameter.key AS parameter_key,
    COUNT(*) AS parameter_occurrences,
    COUNT(DISTINCT event_name) AS event_types_using_parameter
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`,
  UNNEST(event_params) AS parameter
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND parameter.key IN (
      'ga_session_id',
      'ga_session_number',
      'session_engaged',
      'page_location',
      'page_title',
      'source',
      'medium'
    )
  GROUP BY parameter_key
),
required_parameters AS (
  SELECT parameter_key
  FROM UNNEST([
    'ga_session_id',
    'ga_session_number',
    'session_engaged',
    'page_location',
    'page_title',
    'source',
    'medium'
  ]) AS parameter_key
)
SELECT
  required_parameters.parameter_key,
  COALESCE(parameter_hits.parameter_occurrences, 0) AS parameter_occurrences,
  COALESCE(parameter_hits.event_types_using_parameter, 0) AS event_types_using_parameter,
  ROUND(
    100 * SAFE_DIVIDE(
      COALESCE(parameter_hits.parameter_occurrences, 0),
      total.event_rows
    ),
    2
  ) AS occurrences_per_100_event_rows
FROM required_parameters
CROSS JOIN total
LEFT JOIN parameter_hits USING (parameter_key)
ORDER BY required_parameters.parameter_key;


-- ============================================================================
-- 00.6 SESSION IDENTIFIER COVERAGE AND COLLISION RISK
-- If composite_sessions exceeds raw_ga_session_ids, ga_session_id values are
-- reused across users and must not be used alone.
-- ============================================================================

WITH event_base AS (
  SELECT
    user_pseudo_id,
    (
      SELECT ANY_VALUE(value.int_value)
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
)
SELECT
  COUNT(*) AS event_rows,
  COUNTIF(ga_session_id IS NULL) AS rows_missing_ga_session_id,
  ROUND(
    100 * SAFE_DIVIDE(COUNTIF(ga_session_id IS NULL), COUNT(*)),
    2
  ) AS rows_missing_ga_session_id_pct,
  COUNT(DISTINCT ga_session_id) AS raw_ga_session_ids,
  COUNT(
    DISTINCT IF(
      user_pseudo_id IS NOT NULL AND ga_session_id IS NOT NULL,
      CONCAT(user_pseudo_id, '#', CAST(ga_session_id AS STRING)),
      NULL
    )
  ) AS composite_sessions
FROM event_base;


-- ============================================================================
-- 00.7 SESSION-START CONSISTENCY
-- Valid sessions can have telemetry imperfections. Report sessions with zero or
-- multiple session_start events rather than deleting them automatically.
-- ============================================================================

WITH event_base AS (
  SELECT
    event_name,
    event_timestamp,
    user_pseudo_id,
    (
      SELECT ANY_VALUE(value.int_value)
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
),
session_rollup AS (
  SELECT
    CONCAT(user_pseudo_id, '#', CAST(ga_session_id AS STRING)) AS session_key,
    COUNT(*) AS event_rows,
    COUNTIF(event_name = 'session_start') AS session_start_events,
    MIN(event_timestamp) AS first_event_timestamp,
    MAX(event_timestamp) AS last_event_timestamp
  FROM event_base
  WHERE user_pseudo_id IS NOT NULL
    AND ga_session_id IS NOT NULL
  GROUP BY session_key
)
SELECT
  COUNT(*) AS valid_sessions,
  COUNTIF(session_start_events = 0) AS sessions_without_session_start,
  COUNTIF(session_start_events = 1) AS sessions_with_one_session_start,
  COUNTIF(session_start_events > 1) AS sessions_with_multiple_session_starts,
  MIN(event_rows) AS min_events_per_session,
  APPROX_QUANTILES(event_rows, 100)[OFFSET(50)] AS median_events_per_session,
  APPROX_QUANTILES(event_rows, 100)[OFFSET(95)] AS p95_events_per_session,
  MAX(event_rows) AS max_events_per_session,
  ROUND(
    AVG((last_event_timestamp - first_event_timestamp) / 1000000.0 / 60.0),
    2
  ) AS avg_observed_session_minutes
FROM session_rollup;


-- ============================================================================
-- 00.8 NEW-VERSUS-RETURNING FEASIBILITY
-- Primary proposed definition:
--   new       = ga_session_number = 1
--   returning = ga_session_number > 1
--   unknown   = missing parameter
-- first_visit is a corroborating signal, not a silent replacement.
-- ============================================================================

WITH event_base AS (
  SELECT
    event_name,
    user_pseudo_id,
    (
      SELECT ANY_VALUE(value.int_value)
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id,
    (
      SELECT ANY_VALUE(value.int_value)
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_number'
    ) AS ga_session_number
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
),
session_rollup AS (
  SELECT
    CONCAT(user_pseudo_id, '#', CAST(ga_session_id AS STRING)) AS session_key,
    MAX(ga_session_number) AS ga_session_number,
    LOGICAL_OR(event_name = 'first_visit') AS has_first_visit_event
  FROM event_base
  WHERE user_pseudo_id IS NOT NULL
    AND ga_session_id IS NOT NULL
  GROUP BY session_key
)
SELECT
  CASE
    WHEN ga_session_number = 1 THEN 'new'
    WHEN ga_session_number > 1 THEN 'returning'
    ELSE 'unknown'
  END AS user_tenure_segment,
  has_first_visit_event,
  COUNT(*) AS sessions,
  ROUND(100 * SAFE_DIVIDE(COUNT(*), SUM(COUNT(*)) OVER ()), 2) AS session_share_pct
FROM session_rollup
GROUP BY user_tenure_segment, has_first_visit_event
ORDER BY user_tenure_segment, has_first_visit_event DESC;


-- ============================================================================
-- 00.9 ECOMMERCE EVENT AND ITEM COVERAGE
-- ARRAY_LENGTH(items) preserves the event grain while reporting item coverage.
-- ============================================================================

WITH ecommerce_events AS (
  SELECT
    event_name,
    user_pseudo_id,
    ARRAY_LENGTH(items) AS item_count,
    (
      SELECT ANY_VALUE(value.int_value)
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND event_name IN (
      'view_item',
      'add_to_cart',
      'begin_checkout',
      'purchase',
      'refund'
    )
)
SELECT
  event_name,
  COUNT(*) AS event_rows,
  COUNT(DISTINCT user_pseudo_id) AS users,
  COUNT(
    DISTINCT IF(
      user_pseudo_id IS NOT NULL AND ga_session_id IS NOT NULL,
      CONCAT(user_pseudo_id, '#', CAST(ga_session_id AS STRING)),
      NULL
    )
  ) AS sessions,
  COUNTIF(item_count > 0) AS events_with_items,
  COUNTIF(item_count = 0 OR item_count IS NULL) AS events_without_items,
  SUM(COALESCE(item_count, 0)) AS item_rows_if_unnested
FROM ecommerce_events
GROUP BY event_name
ORDER BY
  CASE event_name
    WHEN 'view_item' THEN 1
    WHEN 'add_to_cart' THEN 2
    WHEN 'begin_checkout' THEN 3
    WHEN 'purchase' THEN 4
    WHEN 'refund' THEN 5
    ELSE 6
  END;


-- ============================================================================
-- 00.10 PRELIMINARY ORDERED SESSION FUNNEL
-- A session qualifies for each step only when at least one qualifying event
-- occurs after the timestamp selected for the preceding step. This avoids
-- treating unordered event presence as a completed journey.
-- ============================================================================

WITH event_base AS (
  SELECT
    event_name,
    event_timestamp,
    user_pseudo_id,
    NULLIF(TRIM(ecommerce.transaction_id), '') AS transaction_id,
    ecommerce.purchase_revenue_in_usd AS purchase_revenue_in_usd,
    CONCAT(
      user_pseudo_id,
      '#',
      CAST(
        (
          SELECT ANY_VALUE(value.int_value)
          FROM UNNEST(event_params)
          WHERE key = 'ga_session_id'
        ) AS STRING
      )
    ) AS session_key
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND user_pseudo_id IS NOT NULL
    AND (
      SELECT ANY_VALUE(value.int_value)
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) IS NOT NULL
),
all_sessions AS (
  SELECT DISTINCT session_key
  FROM event_base
),
transaction_rollup AS (
  SELECT
    transaction_id,
    COUNT(DISTINCT user_pseudo_id) AS users,
    COUNT(DISTINCT purchase_revenue_in_usd) AS distinct_revenue_values,
    ARRAY_AGG(
      STRUCT(
        session_key AS session_key,
        event_timestamp AS event_timestamp
      )
      ORDER BY event_timestamp
      LIMIT 1
    )[OFFSET(0)] AS canonical_event
  FROM event_base
  WHERE event_name = 'purchase'
    AND transaction_id IS NOT NULL
  GROUP BY transaction_id
),
canonical_clean_purchases AS (
  SELECT
    transaction_id,
    canonical_event.session_key AS session_key,
    canonical_event.event_timestamp AS event_timestamp
  FROM transaction_rollup
  WHERE users = 1
    AND distinct_revenue_values = 1
),
viewed AS (
  SELECT
    session_key,
    MIN(event_timestamp) AS view_item_timestamp
  FROM event_base
  WHERE event_name = 'view_item'
  GROUP BY session_key
),
added AS (
  SELECT
    viewed.session_key,
    viewed.view_item_timestamp,
    MIN(event_base.event_timestamp) AS add_to_cart_timestamp
  FROM viewed
  JOIN event_base
    ON event_base.session_key = viewed.session_key
   AND event_base.event_name = 'add_to_cart'
   AND event_base.event_timestamp > viewed.view_item_timestamp
  GROUP BY viewed.session_key, viewed.view_item_timestamp
),
checkout_started AS (
  SELECT
    added.session_key,
    added.view_item_timestamp,
    added.add_to_cart_timestamp,
    MIN(event_base.event_timestamp) AS begin_checkout_timestamp
  FROM added
  JOIN event_base
    ON event_base.session_key = added.session_key
   AND event_base.event_name = 'begin_checkout'
   AND event_base.event_timestamp > added.add_to_cart_timestamp
  GROUP BY
    added.session_key,
    added.view_item_timestamp,
    added.add_to_cart_timestamp
),
purchased AS (
  SELECT
    checkout_started.session_key,
    MIN(canonical_clean_purchases.event_timestamp) AS purchase_timestamp
  FROM checkout_started
  JOIN canonical_clean_purchases
    ON canonical_clean_purchases.session_key = checkout_started.session_key
   AND canonical_clean_purchases.event_timestamp
     > checkout_started.begin_checkout_timestamp
  GROUP BY checkout_started.session_key
),
all_purchase_sessions AS (
  SELECT DISTINCT session_key
  FROM canonical_clean_purchases
)
SELECT 'all_valid_sessions' AS stage, COUNT(*) AS sessions FROM all_sessions
UNION ALL
SELECT 'view_item', COUNT(*) FROM viewed
UNION ALL
SELECT 'add_to_cart_after_view_item', COUNT(*) FROM added
UNION ALL
SELECT 'begin_checkout_after_add_to_cart', COUNT(*) FROM checkout_started
UNION ALL
SELECT 'purchase_after_begin_checkout', COUNT(*) FROM purchased
UNION ALL
SELECT 'all_purchase_sessions_regardless_of_path', COUNT(*) FROM all_purchase_sessions;


-- ============================================================================
-- 00.11 PURCHASE AND TRANSACTION-ID QUALITY
-- Primary order metrics require a non-empty transaction_id. Empty IDs remain a
-- separately reported telemetry-quality issue.
-- ============================================================================

WITH purchases AS (
  SELECT
    event_timestamp,
    user_pseudo_id,
    NULLIF(TRIM(ecommerce.transaction_id), '') AS transaction_id,
    ecommerce.purchase_revenue_in_usd AS purchase_revenue_in_usd
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND event_name = 'purchase'
)
SELECT
  COUNT(*) AS purchase_event_rows,
  COUNTIF(transaction_id IS NULL) AS purchase_rows_missing_transaction_id,
  COUNT(DISTINCT transaction_id) AS distinct_valid_transaction_ids,
  COUNTIF(purchase_revenue_in_usd IS NULL) AS purchase_rows_missing_revenue,
  COUNTIF(purchase_revenue_in_usd < 0) AS purchase_rows_with_negative_revenue,
  ROUND(SUM(purchase_revenue_in_usd), 2) AS raw_purchase_event_revenue_usd
FROM purchases;


-- ============================================================================
-- 00.12 DUPLICATE TRANSACTIONS
-- Produces one summary row. The provisional canonical-order rule retains the
-- earliest purchase event for each valid transaction ID. Review cross-user and
-- inconsistent-revenue counts before adopting that rule in fct_orders.
-- ============================================================================

WITH purchases AS (
  SELECT
    event_timestamp,
    user_pseudo_id,
    NULLIF(TRIM(ecommerce.transaction_id), '') AS transaction_id,
    ecommerce.purchase_revenue_in_usd AS purchase_revenue_in_usd
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND event_name = 'purchase'
),
valid_purchases AS (
  SELECT *
  FROM purchases
  WHERE transaction_id IS NOT NULL
),
transaction_rollup AS (
  SELECT
    transaction_id,
    COUNT(*) AS purchase_event_rows,
    COUNT(DISTINCT user_pseudo_id) AS users,
    COUNT(DISTINCT purchase_revenue_in_usd) AS distinct_revenue_values,
    ARRAY_AGG(
      purchase_revenue_in_usd IGNORE NULLS
      ORDER BY event_timestamp
      LIMIT 1
    )[SAFE_OFFSET(0)] AS canonical_revenue_usd
  FROM valid_purchases
  GROUP BY transaction_id
)
SELECT
  (SELECT COUNT(*) FROM purchases) AS purchase_event_rows,
  (
    SELECT COUNTIF(transaction_id IS NULL)
    FROM purchases
  ) AS missing_transaction_id_rows,
  ROUND(
    (
      SELECT SUM(IF(transaction_id IS NULL, purchase_revenue_in_usd, 0))
      FROM purchases
    ),
    2
  ) AS missing_transaction_id_revenue_usd,
  (SELECT COUNT(*) FROM valid_purchases) AS valid_purchase_rows,
  COUNT(*) AS distinct_transaction_ids,
  COUNTIF(purchase_event_rows > 1) AS duplicated_transaction_ids,
  SUM(IF(purchase_event_rows > 1, purchase_event_rows, 0))
    AS rows_in_duplicated_transactions,
  SUM(purchase_event_rows - 1) AS excess_duplicate_rows,
  MAX(purchase_event_rows) AS max_rows_per_transaction,
  COUNTIF(users > 1) AS transactions_spanning_multiple_users,
  COUNTIF(distinct_revenue_values > 1)
    AS transactions_with_inconsistent_revenue,
  ROUND(
    (SELECT SUM(purchase_revenue_in_usd) FROM valid_purchases),
    2
  ) AS raw_valid_purchase_revenue_usd,
  ROUND(SUM(canonical_revenue_usd), 2) AS canonical_order_revenue_usd,
  ROUND(
    (SELECT SUM(purchase_revenue_in_usd) FROM valid_purchases)
      - SUM(canonical_revenue_usd),
    2
  ) AS excess_duplicate_revenue_usd
FROM transaction_rollup;


-- ============================================================================
-- 00.13 EVENT-LEVEL VERSUS ITEM-LEVEL REVENUE
-- Uses only canonical clean orders. The values need not match exactly because
-- event revenue can include elements not represented as item revenue. The
-- comparison is a diagnostic, not an enforced equality test.
-- ============================================================================

WITH purchase_events AS (
  SELECT
    event_timestamp,
    user_pseudo_id,
    NULLIF(TRIM(ecommerce.transaction_id), '') AS transaction_id,
    ecommerce.purchase_revenue_in_usd AS event_revenue_usd,
    items
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND event_name = 'purchase'
),
clean_transactions AS (
  SELECT transaction_id
  FROM purchase_events
  WHERE transaction_id IS NOT NULL
  GROUP BY transaction_id
  HAVING COUNT(DISTINCT user_pseudo_id) = 1
    AND COUNT(DISTINCT event_revenue_usd) = 1
),
canonical_clean_purchase_events AS (
  SELECT purchase_events.*
  FROM purchase_events
  JOIN clean_transactions USING (transaction_id)
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY transaction_id
    ORDER BY event_timestamp, ARRAY_LENGTH(items) DESC
  ) = 1
),
revenue_comparison AS (
  SELECT
    transaction_id,
    event_revenue_usd,
    (
      SELECT SUM(
        COALESCE(
          item.item_revenue_in_usd,
          item.price_in_usd * COALESCE(item.quantity, 1)
        )
      )
      FROM UNNEST(items) AS item
    ) AS summed_item_revenue_usd
  FROM canonical_clean_purchase_events
)
SELECT
  COUNT(*) AS clean_orders,
  COUNTIF(event_revenue_usd IS NULL) AS orders_missing_event_revenue,
  COUNTIF(summed_item_revenue_usd IS NULL) AS orders_missing_item_revenue,
  COUNTIF(ABS(event_revenue_usd - summed_item_revenue_usd) < 0.01)
    AS orders_with_matching_revenue,
  COUNTIF(event_revenue_usd > summed_item_revenue_usd)
    AS orders_with_event_revenue_above_items,
  COUNTIF(event_revenue_usd < summed_item_revenue_usd)
    AS orders_with_item_revenue_above_event,
  ROUND(SUM(event_revenue_usd), 2) AS event_revenue_usd,
  ROUND(SUM(summed_item_revenue_usd), 2) AS summed_item_revenue_usd,
  ROUND(SUM(event_revenue_usd) - SUM(summed_item_revenue_usd), 2) AS difference_usd
FROM revenue_comparison;


-- ============================================================================
-- 00.14 ITEM FIELD QUALITY
-- Supports the decision whether product-level analysis should use item_id,
-- item_name, or a documented fallback key. It also profiles item-array size so
-- multi-item payloads are not mistaken for independent actions.
-- ============================================================================

WITH ecommerce_events AS (
  SELECT
    event_name,
    items
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND event_name IN ('view_item', 'add_to_cart', 'begin_checkout', 'purchase')
),
item_array_profile AS (
  SELECT
    event_name,
    COUNT(*) AS item_bearing_event_rows,
    ROUND(AVG(ARRAY_LENGTH(items)), 2) AS avg_items_per_item_event,
    APPROX_QUANTILES(ARRAY_LENGTH(items), 100)[OFFSET(50)]
      AS median_items_per_item_event,
    APPROX_QUANTILES(ARRAY_LENGTH(items), 100)[OFFSET(95)]
      AS p95_items_per_item_event,
    MAX(ARRAY_LENGTH(items)) AS max_items_per_item_event
  FROM ecommerce_events
  WHERE ARRAY_LENGTH(items) > 0
  GROUP BY event_name
),
item_field_profile AS (
  SELECT
    event_name,
    COUNT(*) AS item_rows,
    COUNTIF(item.item_id IS NULL OR item.item_id = '') AS rows_missing_item_id,
    COUNTIF(item.item_name IS NULL OR item.item_name = '') AS rows_missing_item_name,
    COUNTIF(item.item_category IS NULL OR item.item_category = '')
      AS rows_missing_item_category,
    COUNTIF(item.price_in_usd IS NULL) AS rows_missing_price_usd,
    COUNTIF(item.quantity IS NULL) AS rows_missing_quantity,
    COUNT(DISTINCT NULLIF(item.item_id, '')) AS distinct_item_ids,
    COUNT(DISTINCT NULLIF(item.item_name, '')) AS distinct_item_names
  FROM ecommerce_events,
  UNNEST(items) AS item
  GROUP BY event_name
)
SELECT
  item_field_profile.event_name,
  item_array_profile.item_bearing_event_rows,
  item_field_profile.item_rows,
  item_array_profile.avg_items_per_item_event,
  item_array_profile.median_items_per_item_event,
  item_array_profile.p95_items_per_item_event,
  item_array_profile.max_items_per_item_event,
  item_field_profile.rows_missing_item_id,
  item_field_profile.rows_missing_item_name,
  item_field_profile.rows_missing_item_category,
  item_field_profile.rows_missing_price_usd,
  item_field_profile.rows_missing_quantity,
  item_field_profile.distinct_item_ids,
  item_field_profile.distinct_item_names
FROM item_field_profile
JOIN item_array_profile USING (event_name)
ORDER BY
  CASE event_name
    WHEN 'view_item' THEN 1
    WHEN 'add_to_cart' THEN 2
    WHEN 'begin_checkout' THEN 3
    WHEN 'purchase' THEN 4
    ELSE 5
  END;


-- ============================================================================
-- 00.15 PAGE METADATA FEASIBILITY
-- A specific-page recommendation is valid only when page_location or another
-- page identifier has adequate coverage. Otherwise recommendations must remain
-- at the journey-stage or product level.
-- ============================================================================

WITH page_events AS (
  SELECT
    event_name,
    (
      SELECT ANY_VALUE(value.string_value)
      FROM UNNEST(event_params)
      WHERE key = 'page_location'
    ) AS page_location,
    (
      SELECT ANY_VALUE(value.string_value)
      FROM UNNEST(event_params)
      WHERE key = 'page_title'
    ) AS page_title
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
)
SELECT
  event_name,
  COUNT(*) AS event_rows,
  COUNTIF(page_location IS NOT NULL AND page_location != '') AS rows_with_page_location,
  COUNTIF(page_title IS NOT NULL AND page_title != '') AS rows_with_page_title,
  COUNT(DISTINCT NULLIF(page_location, '')) AS distinct_page_locations,
  COUNT(DISTINCT NULLIF(page_title, '')) AS distinct_page_titles,
  ROUND(
    100 * SAFE_DIVIDE(
      COUNTIF(page_location IS NOT NULL AND page_location != ''),
      COUNT(*)
    ),
    2
  ) AS page_location_coverage_pct
FROM page_events
GROUP BY event_name
ORDER BY event_rows DESC, event_name;


-- ============================================================================
-- 00.16 DEVICE DISTRIBUTION AND PLACEHOLDERS
-- The placeholder bucket is retained explicitly so missingness is not confused
-- with a real device category.
-- ============================================================================

SELECT
  CASE
    WHEN device.category IS NULL OR device.category = '' THEN '[missing]'
    WHEN device.category IN ('<Other>', '(not set)') THEN '[placeholder]'
    ELSE device.category
  END AS device_category,
  COUNT(*) AS event_rows,
  COUNT(DISTINCT user_pseudo_id) AS users,
  ROUND(100 * SAFE_DIVIDE(COUNT(*), SUM(COUNT(*)) OVER ()), 2) AS event_row_share_pct
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
GROUP BY device_category
ORDER BY event_rows DESC, device_category;


-- ============================================================================
-- 00.17 COUNTRY DISTRIBUTION AND PLACEHOLDERS
-- Assigns the first observed country within each valid session, checks
-- within-session consistency, and returns the top 15 countries plus Other.
-- ============================================================================

WITH event_base AS (
  SELECT
    event_timestamp,
    user_pseudo_id,
    CONCAT(
      user_pseudo_id,
      '#',
      CAST(
        (
          SELECT ANY_VALUE(value.int_value)
          FROM UNNEST(event_params)
          WHERE key = 'ga_session_id'
        ) AS STRING
      )
    ) AS session_key,
    CASE
      WHEN geo.country IS NULL OR geo.country = '' THEN '[missing]'
      WHEN geo.country IN ('<Other>', '(not set)') THEN '[placeholder]'
      ELSE geo.country
    END AS country
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND user_pseudo_id IS NOT NULL
),
session_geo AS (
  SELECT
    session_key,
    user_pseudo_id,
    ARRAY_AGG(country ORDER BY event_timestamp LIMIT 1)[OFFSET(0)]
      AS country_name,
    COUNT(DISTINCT country) AS countries_in_session
  FROM event_base
  GROUP BY session_key, user_pseudo_id
),
country_counts AS (
  SELECT
    country_name,
    COUNT(*) AS sessions
  FROM session_geo
  GROUP BY country_name
),
ranked_countries AS (
  SELECT
    country_name,
    ROW_NUMBER() OVER (
      ORDER BY sessions DESC, country_name
    ) AS country_rank
  FROM country_counts
),
labeled_sessions AS (
  SELECT
    session_geo_rows.*,
    IF(
      ranked_countries.country_rank <= 15
        OR session_geo_rows.country_name IN ('[missing]', '[placeholder]'),
      session_geo_rows.country_name,
      'Other'
    ) AS country_group
  FROM session_geo AS session_geo_rows
  JOIN ranked_countries USING (country_name)
)
SELECT
  country_group,
  COUNT(*) AS sessions,
  COUNT(DISTINCT user_pseudo_id) AS users,
  COUNTIF(countries_in_session > 1) AS sessions_with_multiple_countries,
  ROUND(100 * SAFE_DIVIDE(COUNT(*), SUM(COUNT(*)) OVER ()), 2)
    AS session_share_pct
FROM labeled_sessions
GROUP BY country_group
ORDER BY sessions DESC, country_group;


-- ============================================================================
-- 00.18 FIRST-USER ACQUISITION SOURCE COVERAGE
-- traffic_source describes first-user acquisition, not necessarily the source
-- of the current session. Returns the top 15 acquisition combinations plus
-- Other at user grain and checks within-user consistency.
-- ============================================================================

WITH event_base AS (
  SELECT
    event_timestamp,
    user_pseudo_id,
    CONCAT(
      user_pseudo_id,
      '#',
      CAST(
        (
          SELECT ANY_VALUE(value.int_value)
          FROM UNNEST(event_params)
          WHERE key = 'ga_session_id'
        ) AS STRING
      )
    ) AS session_key,
    COALESCE(NULLIF(traffic_source.source, ''), '[missing]')
      AS first_user_source,
    COALESCE(NULLIF(traffic_source.medium, ''), '[missing]')
      AS first_user_medium,
    COALESCE(NULLIF(traffic_source.name, ''), '[missing]')
      AS first_user_campaign
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND user_pseudo_id IS NOT NULL
),
user_acquisition AS (
  SELECT
    user_pseudo_id,
    ARRAY_AGG(
      STRUCT(
        first_user_source AS source,
        first_user_medium AS medium,
        first_user_campaign AS campaign
      )
      ORDER BY event_timestamp
      LIMIT 1
    )[OFFSET(0)] AS acquisition,
    COUNT(
      DISTINCT TO_JSON_STRING(
        STRUCT(
          first_user_source AS source,
          first_user_medium AS medium,
          first_user_campaign AS campaign
        )
      )
    ) AS acquisition_combinations,
    COUNT(DISTINCT session_key) AS sessions
  FROM event_base
  GROUP BY user_pseudo_id
),
combination_counts AS (
  SELECT
    acquisition.source AS source,
    acquisition.medium AS medium,
    acquisition.campaign AS campaign,
    COUNT(*) AS users
  FROM user_acquisition
  GROUP BY source, medium, campaign
),
ranked_combinations AS (
  SELECT
    source,
    medium,
    campaign,
    ROW_NUMBER() OVER (
      ORDER BY users DESC, source, medium, campaign
    ) AS combination_rank
  FROM combination_counts
),
labeled_users AS (
  SELECT
    user_acquisition.*,
    ranked_combinations.combination_rank
  FROM user_acquisition
  JOIN ranked_combinations
    ON user_acquisition.acquisition.source = ranked_combinations.source
   AND user_acquisition.acquisition.medium = ranked_combinations.medium
   AND user_acquisition.acquisition.campaign = ranked_combinations.campaign
)
SELECT
  IF(combination_rank <= 15, acquisition.source, 'Other')
    AS first_user_source,
  IF(combination_rank <= 15, acquisition.medium, 'Other')
    AS first_user_medium,
  IF(combination_rank <= 15, acquisition.campaign, 'Other')
    AS first_user_campaign,
  COUNT(*) AS users,
  SUM(sessions) AS sessions,
  COUNTIF(acquisition_combinations > 1)
    AS users_with_inconsistent_acquisition,
  ROUND(100 * SAFE_DIVIDE(COUNT(*), SUM(COUNT(*)) OVER ()), 2)
    AS user_share_pct
FROM labeled_users
GROUP BY first_user_source, first_user_medium, first_user_campaign
ORDER BY users DESC, first_user_source, first_user_medium, first_user_campaign;


-- ============================================================================
-- 00.19 RETENTION WINDOW FEASIBILITY
-- Users whose first-touch timestamp predates the sample are left-censored and
-- should not be labeled as newly acquired in the primary retention cohort.
-- ============================================================================

WITH user_rollup AS (
  SELECT
    user_pseudo_id,
    MIN(PARSE_DATE('%Y%m%d', event_date)) AS first_observed_event_date,
    DATE(TIMESTAMP_MICROS(MIN(user_first_touch_timestamp))) AS first_touch_date
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND user_pseudo_id IS NOT NULL
  GROUP BY user_pseudo_id
)
SELECT
  CASE
    WHEN first_touch_date IS NULL THEN 'missing_first_touch'
    WHEN first_touch_date < DATE '2020-11-01' THEN 'first_touch_before_sample'
    WHEN first_touch_date BETWEEN DATE '2020-11-01' AND DATE '2021-01-31'
      THEN 'first_touch_inside_sample'
    ELSE 'first_touch_after_sample_check_data'
  END AS first_touch_window,
  COUNT(*) AS users,
  MIN(first_observed_event_date) AS earliest_first_observed_date,
  MAX(first_observed_event_date) AS latest_first_observed_date,
  ROUND(100 * SAFE_DIVIDE(COUNT(*), SUM(COUNT(*)) OVER ()), 2) AS user_share_pct
FROM user_rollup
GROUP BY first_touch_window
ORDER BY users DESC;


-- ============================================================================
-- PROFILE COMPLETION GATE
-- ============================================================================
-- Before downstream modeling, record:
-- [ ] exact observed date coverage and missing days
-- [ ] ga_session_id coverage and composite-session policy
-- [ ] ga_session_number / first_visit coverage
-- [ ] transaction-ID duplicates and missing IDs
-- [ ] event-level and item-level revenue behavior
-- [ ] item_id / item_name fallback policy
-- [ ] page_location coverage and permitted page-level claims
-- [ ] placeholder handling for device, geography, and acquisition
-- [ ] left-censoring and right-censoring rules for retention
-- [ ] any deviation from docs/metric_dictionary.md
