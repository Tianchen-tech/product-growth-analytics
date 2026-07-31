-- Grain: one purchase item_id (SKU/variant).
-- Labels are selected by most frequent clean purchase-item occurrence.

CREATE OR REPLACE VIEW
  `{{ project_id }}.{{ dataset_id }}.dim_products`
OPTIONS (
  description = 'Purchase-SKU dimension with canonical observed labels'
)
AS
WITH product_lines AS (
  SELECT *
  FROM `{{ project_id }}.{{ dataset_id }}.fct_order_items`
  WHERE purchase_product_key IS NOT NULL
),
product_rollup AS (
  SELECT
    purchase_product_key,
    COUNT(DISTINCT item_name) AS item_names_observed,
    COUNT(DISTINCT item_category) AS item_categories_observed,
    MIN(order_date) AS first_purchase_date,
    MAX(order_date) AS last_purchase_date
  FROM product_lines
  GROUP BY purchase_product_key
),
name_counts AS (
  SELECT
    purchase_product_key,
    COALESCE(item_name, '[missing]') AS item_name,
    COUNT(*) AS item_rows
  FROM product_lines
  GROUP BY purchase_product_key, item_name
),
canonical_names AS (
  SELECT
    purchase_product_key,
    item_name AS canonical_item_name
  FROM name_counts
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY purchase_product_key
    ORDER BY item_rows DESC, item_name
  ) = 1
),
category_counts AS (
  SELECT
    purchase_product_key,
    COALESCE(item_category, '[missing]') AS item_category,
    COUNT(*) AS item_rows
  FROM product_lines
  GROUP BY purchase_product_key, item_category
),
canonical_categories AS (
  SELECT
    purchase_product_key,
    item_category AS canonical_item_category
  FROM category_counts
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY purchase_product_key
    ORDER BY item_rows DESC, item_category
  ) = 1
)
SELECT
  product_rollup.purchase_product_key,
  canonical_names.canonical_item_name,
  canonical_categories.canonical_item_category,
  product_rollup.item_names_observed,
  product_rollup.item_categories_observed,
  product_rollup.item_names_observed > 1 AS has_multiple_item_names,
  product_rollup.item_categories_observed > 1
    AS has_multiple_item_categories,
  product_rollup.first_purchase_date,
  product_rollup.last_purchase_date
FROM product_rollup
JOIN canonical_names USING (purchase_product_key)
JOIN canonical_categories USING (purchase_product_key);
