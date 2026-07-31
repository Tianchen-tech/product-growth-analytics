-- Grain: one item-array line in one clean canonical order.

CREATE OR REPLACE VIEW
  `{{ project_id }}.{{ dataset_id }}.fct_order_items`
OPTIONS (
  description = 'Purchase item lines from clean canonical orders'
)
AS
SELECT
  CONCAT(
    order_key,
    '#',
    LPAD(CAST(item_offset + 1 AS STRING), 3, '0')
  ) AS order_item_key,
  order_key,
  user_key,
  session_key,
  order_date,
  order_event_timestamp,
  order_ts,
  item_offset + 1 AS item_line_number,
  NULLIF(TRIM(item.item_id), '') AS purchase_product_key,
  NULLIF(TRIM(item.item_name), '') AS item_name,
  NULLIF(TRIM(item.item_category), '') AS item_category,
  item.price_in_usd AS item_price_usd,
  COALESCE(item.quantity, 1) AS item_quantity,
  item.quantity IS NULL AS quantity_was_defaulted,
  item.item_revenue_in_usd AS reported_item_revenue_usd,
  COALESCE(
    item.item_revenue_in_usd,
    item.price_in_usd * COALESCE(item.quantity, 1)
  ) AS calculated_item_revenue_usd,
  item.price_in_usd IS NULL AS price_was_missing
FROM `{{ project_id }}.{{ dataset_id }}.int_clean_purchase_events`
CROSS JOIN UNNEST(canonical_event_items) AS item WITH OFFSET AS item_offset;
