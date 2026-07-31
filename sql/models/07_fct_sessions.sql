-- Grain: one valid composite session_key.
-- Ordered funnel timestamps use strict event ordering within the same session.

CREATE OR REPLACE VIEW
  `{{ project_id }}.{{ dataset_id }}.fct_sessions`
OPTIONS (
  description = 'Composite sessions with quality flags and ordered funnel stages'
)
AS
WITH valid_events AS (
  SELECT *
  FROM `{{ project_id }}.{{ dataset_id }}.stg_events`
  WHERE user_key IS NOT NULL
    AND session_key IS NOT NULL
),
session_rollup AS (
  SELECT
    session_key,
    ARRAY_AGG(user_key ORDER BY event_timestamp LIMIT 1)[OFFSET(0)] AS user_key,
    ARRAY_AGG(
      ga_session_id IGNORE NULLS
      ORDER BY event_timestamp
      LIMIT 1
    )[SAFE_OFFSET(0)] AS ga_session_id,
    ARRAY_AGG(
      ga_session_number IGNORE NULLS
      ORDER BY event_timestamp
      LIMIT 1
    )[SAFE_OFFSET(0)] AS ga_session_number,
    COUNT(DISTINCT ga_session_number) AS session_numbers_observed,
    MIN(event_date) AS session_date,
    COUNT(DISTINCT event_date) AS observed_event_dates,
    MIN(event_timestamp) AS session_start_event_timestamp,
    MAX(event_timestamp) AS session_end_event_timestamp,
    MIN(event_ts) AS session_start_ts,
    MAX(event_ts) AS session_end_ts,
    COUNT(*) AS event_rows,
    COUNTIF(event_name = 'session_start') AS session_start_event_rows,
    COUNTIF(event_name = 'first_visit') AS first_visit_event_rows,
    COUNTIF(event_name = 'view_item') AS view_item_event_rows,
    COUNTIF(event_name = 'add_to_cart') AS add_to_cart_event_rows,
    COUNTIF(event_name = 'begin_checkout') AS begin_checkout_event_rows,
    COUNTIF(event_name = 'purchase') AS raw_purchase_event_rows,
    COUNT(DISTINCT canonical_page_url) AS distinct_pages,
    ARRAY_AGG(
      page_location IGNORE NULLS
      ORDER BY event_timestamp
      LIMIT 1
    )[SAFE_OFFSET(0)] AS first_page_location,
    ARRAY_AGG(
      canonical_page_url IGNORE NULLS
      ORDER BY event_timestamp
      LIMIT 1
    )[SAFE_OFFSET(0)] AS landing_page_key,
    SUM(COALESCE(engagement_time_msec, 0)) AS engagement_time_msec,
    MAX(session_engaged) AS session_engaged,
    ARRAY_AGG(
      device_category IGNORE NULLS
      ORDER BY event_timestamp
      LIMIT 1
    )[SAFE_OFFSET(0)] AS first_device_category,
    COUNT(DISTINCT device_category) AS device_categories_observed,
    ARRAY_AGG(
      country IGNORE NULLS
      ORDER BY event_timestamp
      LIMIT 1
    )[SAFE_OFFSET(0)] AS first_country,
    COUNT(DISTINCT country) AS countries_observed,
    ARRAY_AGG(
      event_source IGNORE NULLS
      ORDER BY event_timestamp
      LIMIT 1
    )[SAFE_OFFSET(0)] AS session_source_proxy,
    ARRAY_AGG(
      event_medium IGNORE NULLS
      ORDER BY event_timestamp
      LIMIT 1
    )[SAFE_OFFSET(0)] AS session_medium_proxy,
    ARRAY_AGG(
      event_campaign IGNORE NULLS
      ORDER BY event_timestamp
      LIMIT 1
    )[SAFE_OFFSET(0)] AS session_campaign_proxy,
    COUNT(DISTINCT event_source) AS sources_observed,
    COUNT(DISTINCT event_medium) AS mediums_observed,
    COUNT(DISTINCT event_campaign) AS campaigns_observed
  FROM valid_events
  GROUP BY session_key
),
viewed AS (
  SELECT
    session_key,
    MIN(event_timestamp) AS view_item_event_timestamp
  FROM valid_events
  WHERE event_name = 'view_item'
  GROUP BY session_key
),
added AS (
  SELECT
    viewed.session_key,
    viewed.view_item_event_timestamp,
    MIN(valid_events.event_timestamp) AS add_to_cart_event_timestamp
  FROM viewed
  JOIN valid_events
    ON valid_events.session_key = viewed.session_key
   AND valid_events.event_name = 'add_to_cart'
   AND valid_events.event_timestamp > viewed.view_item_event_timestamp
  GROUP BY viewed.session_key, viewed.view_item_event_timestamp
),
checkout_started AS (
  SELECT
    added.session_key,
    added.view_item_event_timestamp,
    added.add_to_cart_event_timestamp,
    MIN(valid_events.event_timestamp) AS begin_checkout_event_timestamp
  FROM added
  JOIN valid_events
    ON valid_events.session_key = added.session_key
   AND valid_events.event_name = 'begin_checkout'
   AND valid_events.event_timestamp > added.add_to_cart_event_timestamp
  GROUP BY
    added.session_key,
    added.view_item_event_timestamp,
    added.add_to_cart_event_timestamp
),
ordered_purchased AS (
  SELECT
    checkout_started.session_key,
    MIN(fct_orders.order_event_timestamp) AS purchase_event_timestamp
  FROM checkout_started
  JOIN `{{ project_id }}.{{ dataset_id }}.fct_orders` AS fct_orders
    ON fct_orders.session_key = checkout_started.session_key
   AND fct_orders.order_event_timestamp
     > checkout_started.begin_checkout_event_timestamp
  GROUP BY checkout_started.session_key
),
orders_by_session AS (
  SELECT
    session_key,
    COUNT(*) AS clean_orders,
    SUM(order_revenue_usd) AS clean_order_revenue_usd
  FROM `{{ project_id }}.{{ dataset_id }}.fct_orders`
  GROUP BY session_key
)
SELECT
  session_rollup.session_key,
  session_rollup.user_key,
  session_rollup.ga_session_id,
  session_rollup.ga_session_number,
  CASE
    WHEN session_rollup.ga_session_number = 1 THEN 'New'
    WHEN session_rollup.ga_session_number > 1 THEN 'Returning'
    ELSE 'Unknown'
  END AS user_tenure,
  session_rollup.session_numbers_observed > 1
    AS has_inconsistent_session_number,
  session_rollup.session_date,
  session_rollup.observed_event_dates,
  session_rollup.session_start_event_timestamp,
  session_rollup.session_end_event_timestamp,
  session_rollup.session_start_ts,
  session_rollup.session_end_ts,
  SAFE_DIVIDE(
    session_rollup.session_end_event_timestamp
      - session_rollup.session_start_event_timestamp,
    60000000.0
  ) AS observed_session_minutes,
  session_rollup.event_rows,
  session_rollup.session_start_event_rows,
  session_rollup.first_visit_event_rows,
  session_rollup.view_item_event_rows,
  session_rollup.add_to_cart_event_rows,
  session_rollup.begin_checkout_event_rows,
  session_rollup.raw_purchase_event_rows,
  session_rollup.distinct_pages,
  session_rollup.first_page_location,
  session_rollup.landing_page_key,
  session_rollup.engagement_time_msec,
  session_rollup.session_engaged,
  CASE
    WHEN session_rollup.first_device_category IS NULL THEN '[missing]'
    WHEN session_rollup.first_device_category IN ('<Other>', '(not set)')
      THEN '[placeholder]'
    ELSE session_rollup.first_device_category
  END AS device_category,
  session_rollup.device_categories_observed > 1
    AS has_multiple_device_categories,
  CASE
    WHEN session_rollup.first_country IS NULL THEN '[missing]'
    WHEN session_rollup.first_country IN ('<Other>', '(not set)')
      THEN '[placeholder]'
    ELSE session_rollup.first_country
  END AS country,
  session_rollup.countries_observed > 1 AS has_multiple_countries,
  session_rollup.session_source_proxy,
  session_rollup.session_medium_proxy,
  session_rollup.session_campaign_proxy,
  session_rollup.sources_observed,
  session_rollup.mediums_observed,
  session_rollup.campaigns_observed,
  session_rollup.sources_observed > 1 AS has_source_conflict,
  session_rollup.mediums_observed > 1 AS has_medium_conflict,
  session_rollup.session_source_proxy IS NULL
    OR session_rollup.session_medium_proxy IS NULL AS has_missing_channel,
  session_rollup.session_source_proxy IN ('<Other>', '(data deleted)')
    OR session_rollup.session_medium_proxy IN ('<Other>', '(data deleted)')
    AS has_obfuscated_channel,
  session_rollup.session_source_proxy IN (
    'shop.googlemerchandisestore.com',
    'googlemerchandisestore.com'
  ) AS is_self_referral,
  CASE
    WHEN session_rollup.session_source_proxy IS NULL
      OR session_rollup.session_medium_proxy IS NULL
      THEN 'Missing'
    WHEN session_rollup.sources_observed > 1
      OR session_rollup.mediums_observed > 1
      THEN 'Conflicting'
    WHEN session_rollup.session_source_proxy IN ('<Other>', '(data deleted)')
      OR session_rollup.session_medium_proxy IN ('<Other>', '(data deleted)')
      THEN 'Obfuscated'
    WHEN session_rollup.session_source_proxy IN (
      'shop.googlemerchandisestore.com',
      'googlemerchandisestore.com'
    )
      THEN 'Self-referral'
    ELSE CONCAT(
      session_rollup.session_source_proxy,
      ' / ',
      session_rollup.session_medium_proxy
    )
  END AS channel_reporting_group,
  viewed.view_item_event_timestamp,
  added.add_to_cart_event_timestamp,
  checkout_started.begin_checkout_event_timestamp,
  ordered_purchased.purchase_event_timestamp,
  viewed.session_key IS NOT NULL AS reached_view_item,
  added.session_key IS NOT NULL AS reached_add_to_cart_after_view,
  checkout_started.session_key IS NOT NULL
    AS reached_checkout_after_add_to_cart,
  ordered_purchased.session_key IS NOT NULL
    AS reached_purchase_after_checkout,
  COALESCE(orders_by_session.clean_orders, 0) AS clean_orders,
  COALESCE(orders_by_session.clean_order_revenue_usd, 0)
    AS clean_order_revenue_usd,
  COALESCE(orders_by_session.clean_orders, 0) > 0
    AS has_clean_purchase,
  CASE
    WHEN ordered_purchased.session_key IS NOT NULL THEN 'purchase'
    WHEN checkout_started.session_key IS NOT NULL THEN 'begin_checkout'
    WHEN added.session_key IS NOT NULL THEN 'add_to_cart'
    WHEN viewed.session_key IS NOT NULL THEN 'view_item'
    ELSE 'no_view_item'
  END AS deepest_ordered_funnel_stage,
  session_rollup.session_date IN (
    DATE '2020-12-25',
    DATE '2020-12-26',
    DATE '2020-12-27',
    DATE '2021-01-01'
  ) AS is_low_volume_date,
  session_rollup.session_date = DATE '2020-12-08' AS is_high_volume_date
FROM session_rollup
LEFT JOIN viewed USING (session_key)
LEFT JOIN added USING (session_key)
LEFT JOIN checkout_started USING (session_key)
LEFT JOIN ordered_purchased USING (session_key)
LEFT JOIN orders_by_session USING (session_key);
