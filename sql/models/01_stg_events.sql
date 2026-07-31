-- Grain: one source GA4 event row.
-- This view flattens only governed parameters and preserves the item array for
-- the separate event-item bridge. It does not invent a unique event ID.

CREATE OR REPLACE VIEW
  `{{ project_id }}.{{ dataset_id }}.stg_events`
OPTIONS (
  description = 'One row per GA4 event with governed parameters flattened'
)
AS
WITH extracted AS (
  SELECT
    _TABLE_SUFFIX AS source_table_suffix,
    PARSE_DATE('%Y%m%d', event_date) AS event_date,
    event_timestamp,
    TIMESTAMP_MICROS(event_timestamp) AS event_ts,
    event_name,
    user_pseudo_id AS user_key,
    TIMESTAMP_MICROS(user_first_touch_timestamp) AS user_first_touch_ts,
    (
      SELECT parameter.value.int_value
      FROM UNNEST(event_params) AS parameter
      WHERE parameter.key = 'ga_session_id'
        AND parameter.value.int_value IS NOT NULL
      LIMIT 1
    ) AS ga_session_id,
    (
      SELECT parameter.value.int_value
      FROM UNNEST(event_params) AS parameter
      WHERE parameter.key = 'ga_session_number'
        AND parameter.value.int_value IS NOT NULL
      LIMIT 1
    ) AS ga_session_number,
    (
      SELECT parameter.value.string_value
      FROM UNNEST(event_params) AS parameter
      WHERE parameter.key = 'page_location'
        AND parameter.value.string_value IS NOT NULL
      LIMIT 1
    ) AS page_location,
    (
      SELECT parameter.value.string_value
      FROM UNNEST(event_params) AS parameter
      WHERE parameter.key = 'page_title'
        AND parameter.value.string_value IS NOT NULL
      LIMIT 1
    ) AS page_title,
    (
      SELECT parameter.value.string_value
      FROM UNNEST(event_params) AS parameter
      WHERE parameter.key = 'page_referrer'
        AND parameter.value.string_value IS NOT NULL
      LIMIT 1
    ) AS page_referrer,
    (
      SELECT parameter.value.string_value
      FROM UNNEST(event_params) AS parameter
      WHERE parameter.key = 'source'
        AND parameter.value.string_value IS NOT NULL
      LIMIT 1
    ) AS event_source,
    (
      SELECT parameter.value.string_value
      FROM UNNEST(event_params) AS parameter
      WHERE parameter.key = 'medium'
        AND parameter.value.string_value IS NOT NULL
      LIMIT 1
    ) AS event_medium,
    (
      SELECT parameter.value.string_value
      FROM UNNEST(event_params) AS parameter
      WHERE parameter.key = 'campaign'
        AND parameter.value.string_value IS NOT NULL
      LIMIT 1
    ) AS event_campaign,
    (
      SELECT parameter.value.int_value
      FROM UNNEST(event_params) AS parameter
      WHERE parameter.key = 'engagement_time_msec'
        AND parameter.value.int_value IS NOT NULL
      LIMIT 1
    ) AS engagement_time_msec,
    (
      SELECT parameter.value.int_value
      FROM UNNEST(event_params) AS parameter
      WHERE parameter.key = 'engaged_session_event'
        AND parameter.value.int_value IS NOT NULL
      LIMIT 1
    ) AS engaged_session_event,
    (
      SELECT parameter.value.int_value
      FROM UNNEST(event_params) AS parameter
      WHERE parameter.key = 'session_engaged'
        AND parameter.value.int_value IS NOT NULL
      LIMIT 1
    ) AS session_engaged_int,
    (
      SELECT parameter.value.string_value
      FROM UNNEST(event_params) AS parameter
      WHERE parameter.key = 'session_engaged'
        AND parameter.value.string_value IS NOT NULL
      LIMIT 1
    ) AS session_engaged_string,
    NULLIF(TRIM(traffic_source.source), '') AS first_user_source,
    NULLIF(TRIM(traffic_source.medium), '') AS first_user_medium,
    NULLIF(TRIM(traffic_source.name), '') AS first_user_campaign,
    NULLIF(TRIM(device.category), '') AS device_category,
    NULLIF(TRIM(geo.country), '') AS country,
    NULLIF(TRIM(ecommerce.transaction_id), '') AS transaction_id,
    ecommerce.purchase_revenue_in_usd AS purchase_revenue_usd,
    items AS event_items
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
)
SELECT
  source_table_suffix,
  event_date,
  event_timestamp,
  event_ts,
  event_name,
  user_key,
  user_first_touch_ts,
  ga_session_id,
  IF(
    user_key IS NOT NULL AND ga_session_id IS NOT NULL,
    CONCAT(user_key, '#', CAST(ga_session_id AS STRING)),
    NULL
  ) AS session_key,
  ga_session_number,
  NULLIF(TRIM(page_location), '') AS page_location,
  CASE
    WHEN NULLIF(TRIM(page_location), '') IS NULL THEN NULL
    ELSE REGEXP_REPLACE(
      REGEXP_REPLACE(TRIM(page_location), r'[?#].*$', ''),
      r'/$',
      ''
    )
  END AS canonical_page_url,
  NULLIF(TRIM(page_title), '') AS page_title,
  NULLIF(TRIM(page_referrer), '') AS page_referrer,
  NULLIF(TRIM(event_source), '') AS event_source,
  NULLIF(TRIM(event_medium), '') AS event_medium,
  NULLIF(TRIM(event_campaign), '') AS event_campaign,
  engagement_time_msec,
  engaged_session_event,
  COALESCE(
    session_engaged_int,
    SAFE_CAST(session_engaged_string AS INT64)
  ) AS session_engaged,
  first_user_source,
  first_user_medium,
  first_user_campaign,
  device_category,
  country,
  transaction_id,
  purchase_revenue_usd,
  event_items
FROM extracted;
