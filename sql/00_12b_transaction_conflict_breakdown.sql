-- Product Growth Analytics
-- File: sql/00_12b_transaction_conflict_breakdown.sql
-- Dialect: BigQuery Standard SQL
-- Source window: 2020-11-01 through 2021-01-31
--
-- PURPOSE
-- -------
-- Resolve the ambiguity found by profile query 00.12 without exposing raw
-- transaction IDs. The output contains at most four quality classes.
--
-- PRIMARY POLICY
-- --------------
-- A clean transaction has:
--   1. a non-empty transaction ID,
--   2. exactly one pseudonymous user, and
--   3. exactly one non-null revenue value.
-- Repeated clean rows are canonicalized to the earliest purchase event.
-- Cross-user or inconsistent-revenue IDs are excluded from primary order and
-- revenue metrics and retained only in data-quality reporting.

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
transaction_rollup AS (
  SELECT
    transaction_id,
    COUNT(*) AS purchase_event_rows,
    COUNT(DISTINCT user_pseudo_id) AS users,
    COUNT(DISTINCT purchase_revenue_in_usd) AS distinct_revenue_values,
    SUM(purchase_revenue_in_usd) AS raw_revenue_usd,
    ARRAY_AGG(
      purchase_revenue_in_usd IGNORE NULLS
      ORDER BY event_timestamp
      LIMIT 1
    )[SAFE_OFFSET(0)] AS canonical_revenue_usd,
    LOWER(transaction_id) IN (
      '(not set)',
      'not set',
      '<other>',
      'unknown',
      'undefined',
      'null',
      'none',
      'n/a',
      'na',
      '0'
    ) AS is_placeholder_like
  FROM purchases
  WHERE transaction_id IS NOT NULL
  GROUP BY transaction_id
),
classified AS (
  SELECT
    *,
    CASE
      WHEN users = 1 AND distinct_revenue_values = 1
        THEN 'clean'
      WHEN users > 1 AND distinct_revenue_values > 1
        THEN 'cross_user_and_inconsistent_revenue'
      WHEN users > 1
        THEN 'cross_user_only'
      ELSE 'inconsistent_revenue_only'
    END AS transaction_quality_class
  FROM transaction_rollup
)
SELECT
  transaction_quality_class,
  COUNT(*) AS transaction_ids,
  SUM(purchase_event_rows) AS purchase_event_rows,
  SUM(purchase_event_rows - 1) AS excess_duplicate_rows,
  MAX(purchase_event_rows) AS max_rows_per_transaction,
  MAX(users) AS max_users_per_transaction,
  COUNTIF(is_placeholder_like) AS placeholder_like_transaction_ids,
  ROUND(SUM(raw_revenue_usd), 2) AS raw_revenue_usd,
  ROUND(SUM(canonical_revenue_usd), 2) AS canonical_revenue_usd,
  ROUND(
    SUM(raw_revenue_usd) - SUM(canonical_revenue_usd),
    2
  ) AS duplicate_revenue_difference_usd
FROM classified
GROUP BY transaction_quality_class
ORDER BY
  CASE transaction_quality_class
    WHEN 'clean' THEN 1
    WHEN 'cross_user_only' THEN 2
    WHEN 'inconsistent_revenue_only' THEN 3
    WHEN 'cross_user_and_inconsistent_revenue' THEN 4
    ELSE 5
  END;
