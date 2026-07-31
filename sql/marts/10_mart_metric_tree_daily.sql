-- Grain: one observed event_date.
-- Daily users are not additive across dates; session, order, and revenue
-- measures are additive and reconcile to the full-window summary.

CREATE OR REPLACE TABLE
  `{{ project_id }}.{{ dataset_id }}.mart_metric_tree_daily`
OPTIONS (
  description = 'Daily traffic, funnel, order, and revenue metric tree'
)
AS
SELECT
  session_date AS metric_date,
  COUNT(DISTINCT user_key) AS active_users,
  COUNT(*) AS sessions,
  COUNTIF(session_engaged = 1) AS engaged_sessions,
  COUNTIF(reached_view_item) AS product_view_sessions,
  COUNTIF(reached_add_to_cart_after_view) AS ordered_add_to_cart_sessions,
  COUNTIF(reached_checkout_after_add_to_cart) AS ordered_checkout_sessions,
  COUNTIF(reached_purchase_after_checkout) AS ordered_purchase_sessions,
  COUNTIF(has_clean_purchase) AS purchasing_sessions,
  SUM(clean_orders) AS orders,
  SUM(clean_order_revenue_usd) AS revenue_usd,
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
  ROUND(AVG(observed_session_minutes), 4)
    AS average_observed_session_minutes,
  LOGICAL_OR(is_low_volume_date) AS is_low_volume_date,
  LOGICAL_OR(is_high_volume_date) AS is_high_volume_date
FROM `{{ project_id }}.{{ dataset_id }}.fct_sessions`
GROUP BY session_date;
