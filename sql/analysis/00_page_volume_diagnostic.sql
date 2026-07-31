-- Aggregate-only diagnostic used to preselect a stable PDP reporting threshold.
-- Add-to-cart is attributed to the most recent earlier product-page view in
-- the same session. No user, session, event, or order identifiers are exported.

WITH product_views AS (
  SELECT
    session_key,
    event_timestamp,
    canonical_page_url AS product_page_key
  FROM `{{ project_id }}.{{ dataset_id }}.stg_events`
  WHERE event_name = 'view_item'
    AND session_key IS NOT NULL
    AND canonical_page_url IS NOT NULL
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
    cart_events.event_timestamp,
    ARRAY_AGG(
      product_views.product_page_key
      ORDER BY product_views.event_timestamp DESC
      LIMIT 1
    )[OFFSET(0)] AS product_page_key
  FROM cart_events
  JOIN product_views
    ON product_views.session_key = cart_events.session_key
   AND product_views.event_timestamp < cart_events.event_timestamp
  GROUP BY cart_events.session_key, cart_events.event_timestamp
),
page_exposures AS (
  SELECT DISTINCT
    session_key,
    product_page_key
  FROM product_views
),
page_adds AS (
  SELECT DISTINCT
    session_key,
    product_page_key
  FROM attributed_cart_events
),
page_metrics AS (
  SELECT
    page_exposures.product_page_key,
    COUNT(*) AS view_sessions,
    COUNTIF(page_adds.session_key IS NOT NULL) AS add_sessions
  FROM page_exposures
  LEFT JOIN page_adds
    USING (session_key, product_page_key)
  GROUP BY page_exposures.product_page_key
),
thresholds AS (
  SELECT threshold
  FROM UNNEST([50, 100, 200, 500, 1000]) AS threshold
)
SELECT
  threshold AS minimum_view_sessions,
  COUNTIF(view_sessions >= threshold) AS eligible_pages,
  SUM(IF(view_sessions >= threshold, view_sessions, 0))
    AS eligible_page_exposure_sessions,
  SUM(IF(view_sessions >= threshold, add_sessions, 0))
    AS eligible_page_add_sessions,
  SAFE_DIVIDE(
    SUM(IF(view_sessions >= threshold, add_sessions, 0)),
    SUM(IF(view_sessions >= threshold, view_sessions, 0))
  ) AS pooled_view_to_add_rate,
  SUM(IF(view_sessions >= threshold, view_sessions, 0))
    / SUM(view_sessions) AS eligible_exposure_share,
  MIN(IF(view_sessions >= threshold, view_sessions, NULL))
    AS smallest_eligible_page,
  MAX(IF(view_sessions >= threshold, view_sessions, NULL))
    AS largest_eligible_page
FROM page_metrics
CROSS JOIN thresholds
GROUP BY threshold
ORDER BY threshold;
