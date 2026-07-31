-- Every row is a hard reconciliation. The local runner fails if any status is
-- not PASS and saves this aggregate output as CSV.

WITH event_metrics AS (
  SELECT
    COUNT(*) AS event_rows,
    COUNTIF(user_key IS NULL) AS missing_users,
    COUNTIF(session_key IS NULL) AS missing_sessions,
    COUNT(DISTINCT event_date) AS event_dates
  FROM `{{ project_id }}.{{ dataset_id }}.stg_events`
),
user_metrics AS (
  SELECT
    COUNT(*) AS users,
    COUNT(DISTINCT user_key) AS distinct_users
  FROM `{{ project_id }}.{{ dataset_id }}.dim_users`
),
session_metrics AS (
  SELECT
    COUNT(*) AS sessions,
    COUNT(DISTINCT session_key) AS distinct_sessions,
    SUM(event_rows) AS session_event_rows,
    COUNTIF(user_tenure = 'New') AS new_sessions,
    COUNTIF(user_tenure = 'Returning') AS returning_sessions,
    COUNTIF(reached_view_item) AS viewed_sessions,
    COUNTIF(reached_add_to_cart_after_view) AS added_sessions,
    COUNTIF(reached_checkout_after_add_to_cart) AS checkout_sessions,
    COUNTIF(reached_purchase_after_checkout) AS ordered_purchase_sessions,
    COUNTIF(has_clean_purchase) AS all_clean_purchase_sessions,
    SUM(clean_order_revenue_usd) AS session_order_revenue_usd
  FROM `{{ project_id }}.{{ dataset_id }}.fct_sessions`
),
order_metrics AS (
  SELECT
    COUNT(*) AS orders,
    COUNT(DISTINCT order_key) AS distinct_orders,
    SUM(order_revenue_usd) AS order_revenue_usd,
    SUM(summed_item_revenue_usd) AS order_summed_item_revenue_usd
  FROM `{{ project_id }}.{{ dataset_id }}.fct_orders`
),
order_item_metrics AS (
  SELECT
    COUNT(*) AS order_item_rows,
    COUNT(DISTINCT order_item_key) AS distinct_order_item_rows,
    COUNTIF(purchase_product_key IS NULL) AS missing_product_keys,
    SUM(calculated_item_revenue_usd) AS item_revenue_usd
  FROM `{{ project_id }}.{{ dataset_id }}.fct_order_items`
),
product_metrics AS (
  SELECT
    COUNT(*) AS products,
    COUNT(DISTINCT purchase_product_key) AS distinct_products
  FROM `{{ project_id }}.{{ dataset_id }}.dim_products`
),
all_metrics AS (
  SELECT *
  FROM event_metrics
  CROSS JOIN user_metrics
  CROSS JOIN session_metrics
  CROSS JOIN order_metrics
  CROSS JOIN order_item_metrics
  CROSS JOIN product_metrics
)
SELECT check_result.*
FROM all_metrics
CROSS JOIN UNNEST([
  STRUCT(
    'stg_event_rows' AS check_name,
    IF(event_rows = 4295584, 'PASS', 'FAIL') AS status,
    CAST(event_rows AS STRING) AS actual_value,
    '4295584' AS expected_value,
    'Exact source-row reconciliation' AS details
  ),
  STRUCT(
    'stg_missing_user_keys',
    IF(missing_users = 0, 'PASS', 'FAIL'),
    CAST(missing_users AS STRING),
    '0',
    'No source event is missing user_pseudo_id'
  ),
  STRUCT(
    'stg_missing_session_keys',
    IF(missing_sessions = 0, 'PASS', 'FAIL'),
    CAST(missing_sessions AS STRING),
    '0',
    'Composite session coverage'
  ),
  STRUCT(
    'stg_observed_event_dates',
    IF(event_dates = 92, 'PASS', 'FAIL'),
    CAST(event_dates AS STRING),
    '92',
    'Complete source window'
  ),
  STRUCT(
    'dim_user_rows',
    IF(users = 270154 AND distinct_users = users, 'PASS', 'FAIL'),
    CAST(users AS STRING),
    '270154',
    'One row per pseudonymous user'
  ),
  STRUCT(
    'fct_session_rows',
    IF(sessions = 360129 AND distinct_sessions = sessions, 'PASS', 'FAIL'),
    CAST(sessions AS STRING),
    '360129',
    'One row per composite session'
  ),
  STRUCT(
    'fct_session_event_rows',
    IF(session_event_rows = 4295584, 'PASS', 'FAIL'),
    CAST(session_event_rows AS STRING),
    '4295584',
    'All source events roll into valid sessions'
  ),
  STRUCT(
    'new_sessions',
    IF(new_sessions = 261238, 'PASS', 'FAIL'),
    CAST(new_sessions AS STRING),
    '261238',
    'ga_session_number equals one'
  ),
  STRUCT(
    'returning_sessions',
    IF(returning_sessions = 98891, 'PASS', 'FAIL'),
    CAST(returning_sessions AS STRING),
    '98891',
    'ga_session_number is greater than one'
  ),
  STRUCT(
    'ordered_view_item_sessions',
    IF(viewed_sessions = 77020, 'PASS', 'FAIL'),
    CAST(viewed_sessions AS STRING),
    '77020',
    'First ordered funnel stage'
  ),
  STRUCT(
    'ordered_add_to_cart_sessions',
    IF(added_sessions = 14380, 'PASS', 'FAIL'),
    CAST(added_sessions AS STRING),
    '14380',
    'Add-to-cart strictly after view'
  ),
  STRUCT(
    'ordered_checkout_sessions',
    IF(checkout_sessions = 5187, 'PASS', 'FAIL'),
    CAST(checkout_sessions AS STRING),
    '5187',
    'Checkout strictly after add-to-cart'
  ),
  STRUCT(
    'ordered_purchase_sessions',
    IF(ordered_purchase_sessions = 2491, 'PASS', 'FAIL'),
    CAST(ordered_purchase_sessions AS STRING),
    '2491',
    'Clean purchase strictly after checkout'
  ),
  STRUCT(
    'all_clean_purchase_sessions',
    IF(all_clean_purchase_sessions = 4021, 'PASS', 'FAIL'),
    CAST(all_clean_purchase_sessions AS STRING),
    '4021',
    'Clean purchase regardless of observed path'
  ),
  STRUCT(
    'fct_order_rows',
    IF(orders = 4436 AND distinct_orders = orders, 'PASS', 'FAIL'),
    CAST(orders AS STRING),
    '4436',
    'One row per clean transaction ID'
  ),
  STRUCT(
    'fct_order_revenue_usd',
    IF(ABS(order_revenue_usd - 306678.0) < 0.01, 'PASS', 'FAIL'),
    FORMAT('%.2f', order_revenue_usd),
    '306678.00',
    'Authoritative event-level order revenue'
  ),
  STRUCT(
    'session_order_revenue_usd',
    IF(ABS(session_order_revenue_usd - 306678.0) < 0.01, 'PASS', 'FAIL'),
    FORMAT('%.2f', session_order_revenue_usd),
    '306678.00',
    'Session rollup reconciles to order fact'
  ),
  STRUCT(
    'fct_order_item_key_uniqueness',
    IF(order_item_rows = distinct_order_item_rows, 'PASS', 'FAIL'),
    CAST(distinct_order_item_rows AS STRING),
    CAST(order_item_rows AS STRING),
    'One deterministic line key per canonical order item'
  ),
  STRUCT(
    'fct_order_items_missing_product_key',
    IF(missing_product_keys = 0, 'PASS', 'FAIL'),
    CAST(missing_product_keys AS STRING),
    '0',
    'Purchase SKU key completeness'
  ),
  STRUCT(
    'fct_order_item_revenue_usd',
    IF(ABS(item_revenue_usd - 306599.0) < 0.01, 'PASS', 'FAIL'),
    FORMAT('%.2f', item_revenue_usd),
    '306599.00',
    'Canonical purchase-item revenue'
  ),
  STRUCT(
    'order_to_item_revenue_rollup',
    IF(
      ABS(order_summed_item_revenue_usd - item_revenue_usd) < 0.01,
      'PASS',
      'FAIL'
    ),
    FORMAT('%.2f', item_revenue_usd),
    FORMAT('%.2f', order_summed_item_revenue_usd),
    'Order fact and order-item fact agree'
  ),
  STRUCT(
    'dim_product_key_uniqueness',
    IF(products > 0 AND distinct_products = products, 'PASS', 'FAIL'),
    CAST(distinct_products AS STRING),
    CAST(products AS STRING),
    'One row per clean purchase SKU'
  )
]) AS check_result
ORDER BY check_name;
