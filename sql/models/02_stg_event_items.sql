-- Grain: one item-array row attached to one GA4 event row.
-- This is a payload bridge, not a focal-product behavioral funnel.

CREATE OR REPLACE VIEW
  `{{ project_id }}.{{ dataset_id }}.stg_event_items`
OPTIONS (
  description = 'One row per item payload attached to a staged GA4 event'
)
AS
SELECT
  event_date,
  event_timestamp,
  event_ts,
  event_name,
  user_key,
  session_key,
  transaction_id,
  canonical_page_url,
  item_offset,
  ARRAY_LENGTH(event_items) AS event_item_count,
  NULLIF(TRIM(item.item_id), '') AS item_id,
  NULLIF(TRIM(item.item_name), '') AS item_name,
  NULLIF(TRIM(item.item_category), '') AS item_category,
  item.price_in_usd AS item_price_usd,
  item.quantity AS item_quantity,
  item.item_revenue_in_usd AS reported_item_revenue_usd,
  COALESCE(
    item.item_revenue_in_usd,
    item.price_in_usd * COALESCE(item.quantity, 1)
  ) AS calculated_item_revenue_usd,
  item.quantity IS NULL AS quantity_was_missing,
  item.price_in_usd IS NULL AS price_was_missing
FROM `{{ project_id }}.{{ dataset_id }}.stg_events`
CROSS JOIN UNNEST(event_items) AS item WITH OFFSET AS item_offset;
