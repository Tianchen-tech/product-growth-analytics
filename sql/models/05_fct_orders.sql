-- Grain: one clean canonical order.

CREATE OR REPLACE VIEW
  `{{ project_id }}.{{ dataset_id }}.fct_orders`
OPTIONS (
  description = 'Clean canonical orders with authoritative event revenue'
)
AS
WITH order_values AS (
  SELECT
    order_key,
    user_key,
    session_key,
    order_date,
    order_event_timestamp,
    order_ts,
    order_revenue_usd,
    purchase_event_rows,
    ARRAY_LENGTH(canonical_event_items) AS order_item_rows,
    (
      SELECT SUM(COALESCE(item.quantity, 1))
      FROM UNNEST(canonical_event_items) AS item
    ) AS order_units,
    (
      SELECT SUM(
        COALESCE(
          item.item_revenue_in_usd,
          item.price_in_usd * COALESCE(item.quantity, 1)
        )
      )
      FROM UNNEST(canonical_event_items) AS item
    ) AS summed_item_revenue_usd
  FROM `{{ project_id }}.{{ dataset_id }}.int_clean_purchase_events`
)
SELECT
  order_key,
  user_key,
  session_key,
  order_date,
  order_event_timestamp,
  order_ts,
  order_revenue_usd,
  purchase_event_rows,
  purchase_event_rows > 1 AS had_duplicate_purchase_events,
  order_item_rows,
  order_units,
  summed_item_revenue_usd,
  order_revenue_usd - summed_item_revenue_usd
    AS event_minus_item_revenue_usd
FROM order_values;
