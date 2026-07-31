-- Grain: one clean canonical transaction.
-- The view retains the canonical purchase item array for downstream order facts.

CREATE OR REPLACE VIEW
  `{{ project_id }}.{{ dataset_id }}.int_clean_purchase_events`
OPTIONS (
  description = 'Canonical purchase event for clean transaction IDs only'
)
AS
WITH purchase_events AS (
  SELECT
    transaction_id,
    user_key,
    session_key,
    event_date,
    event_timestamp,
    event_ts,
    purchase_revenue_usd,
    event_items
  FROM `{{ project_id }}.{{ dataset_id }}.stg_events`
  WHERE event_name = 'purchase'
),
transaction_quality AS (
  SELECT
    transaction_id,
    COUNT(*) AS purchase_event_rows,
    COUNT(DISTINCT user_key) AS users,
    COUNT(DISTINCT purchase_revenue_usd) AS distinct_revenue_values,
    COUNTIF(purchase_revenue_usd IS NULL) AS rows_missing_revenue
  FROM purchase_events
  WHERE transaction_id IS NOT NULL
  GROUP BY transaction_id
),
clean_transaction_ids AS (
  SELECT *
  FROM transaction_quality
  WHERE users = 1
    AND distinct_revenue_values = 1
    AND rows_missing_revenue = 0
),
canonical_events AS (
  SELECT
    purchase_events.*,
    clean_transaction_ids.purchase_event_rows
  FROM purchase_events
  JOIN clean_transaction_ids USING (transaction_id)
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY transaction_id
    ORDER BY
      event_timestamp,
      ARRAY_LENGTH(event_items) DESC,
      TO_JSON_STRING(event_items)
  ) = 1
)
SELECT
  transaction_id AS order_key,
  user_key,
  session_key,
  event_date AS order_date,
  event_timestamp AS order_event_timestamp,
  event_ts AS order_ts,
  purchase_revenue_usd AS order_revenue_usd,
  purchase_event_rows,
  event_items AS canonical_event_items
FROM canonical_events;
