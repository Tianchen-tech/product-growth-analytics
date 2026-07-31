-- Grain: one canonical product-detail page.
-- An add_to_cart is attributed to the most recent earlier view_item page in
-- the same session. Page opportunity values are scenarios and are not additive
-- because one session can view more than one product page.

CREATE OR REPLACE TABLE
  `{{ project_id }}.{{ dataset_id }}.mart_page_funnel`
OPTIONS (
  description = 'PDP last-view attribution, Wilson intervals, and opportunity scenarios'
)
AS
WITH product_views AS (
  SELECT
    session_key,
    event_timestamp,
    canonical_page_url AS product_page_key,
    page_title
  FROM `{{ project_id }}.{{ dataset_id }}.stg_events`
  WHERE event_name = 'view_item'
    AND session_key IS NOT NULL
    AND canonical_page_url IS NOT NULL
),
page_title_counts AS (
  SELECT
    product_page_key,
    COALESCE(page_title, '[missing]') AS page_title,
    COUNT(*) AS title_event_rows
  FROM product_views
  GROUP BY product_page_key, page_title
),
canonical_page_titles AS (
  SELECT
    product_page_key,
    page_title AS canonical_page_title
  FROM page_title_counts
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY product_page_key
    ORDER BY title_event_rows DESC, page_title
  ) = 1
),
cart_events AS (
  SELECT
    session_key,
    event_timestamp
  FROM `{{ project_id }}.{{ dataset_id }}.stg_events`
  WHERE event_name = 'add_to_cart'
    AND session_key IS NOT NULL
),
attributed_cart_events AS (
  SELECT
    cart_events.session_key,
    cart_events.event_timestamp AS add_event_timestamp,
    ARRAY_AGG(
      STRUCT(
        product_views.product_page_key AS product_page_key,
        product_views.event_timestamp AS view_event_timestamp
      )
      ORDER BY product_views.event_timestamp DESC
      LIMIT 1
    )[OFFSET(0)] AS attributed_view
  FROM cart_events
  JOIN product_views
    ON product_views.session_key = cart_events.session_key
   AND product_views.event_timestamp < cart_events.event_timestamp
  GROUP BY cart_events.session_key, cart_events.event_timestamp
),
page_exposures AS (
  SELECT
    session_key,
    product_page_key,
    MIN(event_timestamp) AS first_view_event_timestamp,
    MAX(event_timestamp) AS last_view_event_timestamp
  FROM product_views
  GROUP BY session_key, product_page_key
),
page_adds AS (
  SELECT
    session_key,
    attributed_view.product_page_key AS product_page_key,
    MIN(add_event_timestamp) AS first_attributed_add_timestamp,
    MAX(add_event_timestamp) AS last_attributed_add_timestamp
  FROM attributed_cart_events
  GROUP BY session_key, product_page_key
),
focal_checkout_pages AS (
  SELECT
    attributed_cart_events.session_key,
    attributed_cart_events.attributed_view.product_page_key
      AS product_page_key,
    sessions.reached_purchase_after_checkout
  FROM attributed_cart_events
  JOIN `{{ project_id }}.{{ dataset_id }}.fct_sessions` AS sessions
    ON sessions.session_key = attributed_cart_events.session_key
   AND sessions.reached_checkout_after_add_to_cart
   AND attributed_cart_events.add_event_timestamp
     < sessions.begin_checkout_event_timestamp
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY attributed_cart_events.session_key
    ORDER BY attributed_cart_events.add_event_timestamp DESC
  ) = 1
),
page_rollup AS (
  SELECT
    page_exposures.product_page_key,
    COUNT(*) AS view_sessions,
    COUNTIF(page_adds.session_key IS NOT NULL) AS attributed_add_sessions,
    COUNTIF(focal_checkout_pages.session_key IS NOT NULL)
      AS attributed_checkout_sessions,
    COUNTIF(
      focal_checkout_pages.session_key IS NOT NULL
      AND focal_checkout_pages.reached_purchase_after_checkout
    ) AS attributed_ordered_purchase_sessions
  FROM page_exposures
  LEFT JOIN page_adds
    USING (session_key, product_page_key)
  LEFT JOIN focal_checkout_pages
    USING (session_key, product_page_key)
  GROUP BY page_exposures.product_page_key
),
page_rates AS (
  SELECT
    *,
    SAFE_DIVIDE(attributed_add_sessions, view_sessions)
      AS view_to_add_rate,
    SAFE_DIVIDE(attributed_checkout_sessions, attributed_add_sessions)
      AS attributed_add_to_checkout_rate,
    SAFE_DIVIDE(
      attributed_ordered_purchase_sessions,
      attributed_checkout_sessions
    ) AS attributed_checkout_to_purchase_rate,
    view_sessions >= 200 AS is_benchmark_eligible
  FROM page_rollup
),
benchmark AS (
  SELECT
    APPROX_QUANTILES(view_to_add_rate, 100)[OFFSET(75)]
      AS benchmark_view_to_add_rate
  FROM page_rates
  WHERE is_benchmark_eligible
),
global_scenario_inputs AS (
  SELECT
    SAFE_DIVIDE(
      COUNTIF(reached_purchase_after_checkout),
      COUNTIF(reached_add_to_cart_after_view)
    ) AS ordered_add_to_purchase_rate,
    SAFE_DIVIDE(SUM(clean_order_revenue_usd), SUM(clean_orders))
      AS average_order_value_usd
  FROM `{{ project_id }}.{{ dataset_id }}.fct_sessions`
),
opportunity AS (
  SELECT
    page_rates.*,
    benchmark.benchmark_view_to_add_rate,
    global_scenario_inputs.ordered_add_to_purchase_rate,
    global_scenario_inputs.average_order_value_usd,
    IF(
      is_benchmark_eligible,
      GREATEST(benchmark_view_to_add_rate - view_to_add_rate, 0),
      NULL
    ) AS view_to_add_gap,
    IF(
      is_benchmark_eligible,
      view_sessions
        * GREATEST(benchmark_view_to_add_rate - view_to_add_rate, 0),
      NULL
    ) AS scenario_incremental_add_sessions
  FROM page_rates
  CROSS JOIN benchmark
  CROSS JOIN global_scenario_inputs
),
scored AS (
  SELECT
    *,
    scenario_incremental_add_sessions * ordered_add_to_purchase_rate
      AS scenario_incremental_orders,
    scenario_incremental_add_sessions
      * ordered_add_to_purchase_rate
      * average_order_value_usd AS scenario_revenue_opportunity_usd
  FROM opportunity
)
SELECT
  scored.product_page_key,
  canonical_page_titles.canonical_page_title,
  scored.view_sessions,
  scored.attributed_add_sessions,
  scored.attributed_checkout_sessions,
  scored.attributed_ordered_purchase_sessions,
  scored.view_to_add_rate,
  GREATEST(
    0.0,
    (
      scored.view_to_add_rate
      + 3.841458820694124 / (2 * scored.view_sessions)
      - 1.959963984540054 * SQRT(
        scored.view_to_add_rate * (1 - scored.view_to_add_rate)
          / scored.view_sessions
        + 3.841458820694124 / (4 * POW(scored.view_sessions, 2))
      )
    ) / (1 + 3.841458820694124 / scored.view_sessions)
  )
    AS view_to_add_rate_ci95_lower,
  LEAST(
    1.0,
    (
      scored.view_to_add_rate
      + 3.841458820694124 / (2 * scored.view_sessions)
      + 1.959963984540054 * SQRT(
        scored.view_to_add_rate * (1 - scored.view_to_add_rate)
          / scored.view_sessions
        + 3.841458820694124 / (4 * POW(scored.view_sessions, 2))
      )
    ) / (1 + 3.841458820694124 / scored.view_sessions)
  )
    AS view_to_add_rate_ci95_upper,
  scored.attributed_add_to_checkout_rate,
  scored.attributed_checkout_to_purchase_rate,
  200 AS minimum_view_sessions,
  scored.is_benchmark_eligible AS is_reportable,
  'Unweighted P75 view-to-add rate among PDPs with at least 200 view sessions'
    AS benchmark_method,
  scored.benchmark_view_to_add_rate,
  scored.view_to_add_gap,
  scored.ordered_add_to_purchase_rate AS scenario_downstream_rate,
  scored.average_order_value_usd AS scenario_average_order_value_usd,
  scored.scenario_incremental_add_sessions,
  scored.scenario_incremental_orders,
  scored.scenario_revenue_opportunity_usd,
  FALSE AS opportunity_values_are_additive,
  CASE
    WHEN scored.is_benchmark_eligible THEN DENSE_RANK() OVER (
      ORDER BY scored.scenario_incremental_orders DESC
    )
    ELSE NULL
  END AS page_opportunity_rank
FROM scored
JOIN canonical_page_titles
  USING (product_page_key);
