-- Grain: one clean purchase SKU/variant.
-- This is a sales mart. It deliberately makes no view/add behavioral-funnel
-- claim because pre-purchase item arrays do not identify the focal product.

CREATE OR REPLACE TABLE
  `{{ project_id }}.{{ dataset_id }}.mart_product_sales`
OPTIONS (
  description = 'Clean SKU sales, units, revenue share, and reporting flags'
)
AS
WITH product_rollup AS (
  SELECT
    purchase_product_key,
    COUNT(*) AS order_item_lines,
    COUNT(DISTINCT order_key) AS orders,
    COUNT(DISTINCT session_key) AS purchasing_sessions,
    COUNT(DISTINCT user_key) AS purchasing_users,
    SUM(item_quantity) AS units,
    SUM(calculated_item_revenue_usd) AS item_revenue_usd,
    ROUND(AVG(item_price_usd), 2) AS average_observed_item_price_usd,
    COUNTIF(quantity_was_defaulted) AS quantity_defaulted_lines,
    COUNTIF(price_was_missing) AS price_missing_lines
  FROM `{{ project_id }}.{{ dataset_id }}.fct_order_items`
  GROUP BY purchase_product_key
),
scored AS (
  SELECT
    product_rollup.*,
    SAFE_DIVIDE(
      item_revenue_usd,
      SUM(item_revenue_usd) OVER ()
    ) AS item_revenue_share,
    SAFE_DIVIDE(units, SUM(units) OVER ()) AS unit_share,
    DENSE_RANK() OVER (
      ORDER BY item_revenue_usd DESC
    ) AS revenue_rank,
    SUM(item_revenue_usd) OVER (
      ORDER BY item_revenue_usd DESC, purchase_product_key
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) / SUM(item_revenue_usd) OVER () AS cumulative_item_revenue_share
  FROM product_rollup
)
SELECT
  scored.purchase_product_key,
  products.canonical_item_name,
  products.canonical_item_category,
  scored.order_item_lines,
  scored.orders,
  scored.purchasing_sessions,
  scored.purchasing_users,
  scored.units,
  scored.item_revenue_usd,
  scored.average_observed_item_price_usd,
  scored.item_revenue_share,
  scored.unit_share,
  scored.revenue_rank,
  scored.cumulative_item_revenue_share,
  scored.quantity_defaulted_lines,
  scored.price_missing_lines,
  20 AS minimum_orders_for_ranking,
  scored.orders >= 20 AS is_reportable,
  FALSE AS behavioral_funnel_available
FROM scored
JOIN `{{ project_id }}.{{ dataset_id }}.dim_products` AS products
  USING (purchase_product_key);
