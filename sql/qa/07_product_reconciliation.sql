-- Clean SKU sales reconciliation and interpretation safeguards.

WITH product_metrics AS (
  SELECT
    COUNT(*) AS product_rows,
    COUNT(DISTINCT purchase_product_key) AS distinct_products,
    SUM(item_revenue_usd) AS item_revenue_usd,
    COUNTIF(behavioral_funnel_available) AS behavioral_funnel_claim_rows,
    COUNTIF(is_reportable AND orders < minimum_orders_for_ranking)
      AS invalid_reportable_rows
  FROM `{{ project_id }}.{{ dataset_id }}.mart_product_sales`
)
SELECT check_result.*
FROM product_metrics
CROSS JOIN UNNEST([
  STRUCT(
    'product_key_reconciliation' AS check_name,
    IF(
      product_metrics.product_rows = 789
      AND product_metrics.distinct_products = product_metrics.product_rows,
      'PASS',
      'FAIL'
    ) AS status,
    FORMAT(
      '%d / %d',
      product_metrics.distinct_products,
      product_metrics.product_rows
    ) AS actual_value,
    '789 / 789' AS expected_value,
    'Sales mart preserves one row per clean SKU' AS details
  ),
  STRUCT(
    'product_revenue_reconciliation',
    IF(ABS(product_metrics.item_revenue_usd - 306599.0) < 0.01, 'PASS', 'FAIL'),
    FORMAT('%.2f', product_metrics.item_revenue_usd),
    '306599.00',
    'SKU revenue sums to clean purchase-item revenue'
  ),
  STRUCT(
    'product_reporting_safeguards',
    IF(
      product_metrics.behavioral_funnel_claim_rows = 0
      AND product_metrics.invalid_reportable_rows = 0,
      'PASS',
      'FAIL'
    ),
    FORMAT(
      '%d funnel claims / %d threshold',
      product_metrics.behavioral_funnel_claim_rows,
      product_metrics.invalid_reportable_rows
    ),
    '0 funnel claims / 0 threshold',
    'Sales mart does not imply unsupported product behavior'
  )
]) AS check_result
ORDER BY check_name;
