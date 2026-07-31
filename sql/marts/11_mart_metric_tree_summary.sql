-- Grain: one row for the complete governed source window.

CREATE OR REPLACE TABLE
  `{{ project_id }}.{{ dataset_id }}.mart_metric_tree_summary`
OPTIONS (
  description = 'Full-window traffic, funnel, order, revenue, and value summary'
)
AS
SELECT
  MIN(session_date) AS analysis_start_date,
  MAX(session_date) AS analysis_end_date,
  COUNT(DISTINCT session_date) AS observed_calendar_days,
  COUNT(DISTINCT user_key) AS pseudonymous_users,
  COUNT(*) AS sessions,
  COUNTIF(session_engaged = 1) AS engaged_sessions,
  COUNTIF(reached_view_item) AS product_view_sessions,
  COUNTIF(reached_add_to_cart_after_view) AS ordered_add_to_cart_sessions,
  COUNTIF(reached_checkout_after_add_to_cart) AS ordered_checkout_sessions,
  COUNTIF(reached_purchase_after_checkout) AS ordered_purchase_sessions,
  COUNTIF(has_clean_purchase) AS purchasing_sessions,
  SUM(clean_orders) AS orders,
  SUM(clean_order_revenue_usd) AS revenue_usd,
  SAFE_DIVIDE(COUNT(*), COUNT(DISTINCT user_key)) AS sessions_per_user,
  SAFE_DIVIDE(COUNTIF(session_engaged = 1), COUNT(*))
    AS session_engagement_rate,
  SAFE_DIVIDE(COUNTIF(reached_view_item), COUNT(*))
    AS product_view_reach_rate,
  SAFE_DIVIDE(
    COUNTIF(reached_add_to_cart_after_view),
    COUNTIF(reached_view_item)
  ) AS view_to_cart_conversion_rate,
  SAFE_DIVIDE(
    COUNTIF(reached_checkout_after_add_to_cart),
    COUNTIF(reached_add_to_cart_after_view)
  ) AS cart_to_checkout_conversion_rate,
  SAFE_DIVIDE(
    COUNTIF(reached_purchase_after_checkout),
    COUNTIF(reached_checkout_after_add_to_cart)
  ) AS checkout_completion_rate,
  SAFE_DIVIDE(
    COUNTIF(reached_purchase_after_checkout),
    COUNTIF(reached_view_item)
  ) AS ordered_view_to_purchase_rate,
  SAFE_DIVIDE(COUNTIF(has_clean_purchase), COUNT(*))
    AS purchase_session_conversion_rate,
  SAFE_DIVIDE(SUM(clean_orders), COUNT(*)) AS orders_per_session,
  SAFE_DIVIDE(SUM(clean_order_revenue_usd), SUM(clean_orders))
    AS average_order_value_usd,
  SAFE_DIVIDE(SUM(clean_order_revenue_usd), COUNT(*))
    AS revenue_per_session_usd,
  SAFE_DIVIDE(
    SUM(clean_order_revenue_usd),
    COUNT(DISTINCT user_key)
  ) AS revenue_per_user_usd
FROM `{{ project_id }}.{{ dataset_id }}.fct_sessions`;
