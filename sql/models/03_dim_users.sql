-- Grain: one pseudonymous user_key.
-- Acquisition fields are explicitly first-observed proxies.

CREATE OR REPLACE VIEW
  `{{ project_id }}.{{ dataset_id }}.dim_users`
OPTIONS (
  description = 'Pseudonymous users with observation and acquisition-quality fields'
)
AS
WITH user_rollup AS (
  SELECT
    user_key,
    MIN(event_date) AS first_observed_date,
    MAX(event_date) AS last_observed_date,
    MIN(event_ts) AS first_observed_ts,
    MAX(event_ts) AS last_observed_ts,
    MIN(user_first_touch_ts) AS user_first_touch_ts,
    COUNT(*) AS event_rows,
    COUNT(DISTINCT session_key) AS valid_sessions,
    COUNTIF(event_name = 'first_visit') AS first_visit_event_rows,
    ARRAY_AGG(
      STRUCT(
        COALESCE(first_user_source, '[missing]') AS source,
        COALESCE(first_user_medium, '[missing]') AS medium,
        COALESCE(first_user_campaign, '[missing]') AS campaign
      )
      ORDER BY event_timestamp
      LIMIT 1
    )[OFFSET(0)] AS first_observed_acquisition,
    COUNT(
      DISTINCT TO_JSON_STRING(
        STRUCT(
          COALESCE(first_user_source, '[missing]') AS source,
          COALESCE(first_user_medium, '[missing]') AS medium,
          COALESCE(first_user_campaign, '[missing]') AS campaign
        )
      )
    ) AS acquisition_combinations
  FROM `{{ project_id }}.{{ dataset_id }}.stg_events`
  WHERE user_key IS NOT NULL
  GROUP BY user_key
),
labeled AS (
  SELECT
    *,
    DATE(user_first_touch_ts) AS user_first_touch_date
  FROM user_rollup
)
SELECT
  user_key,
  first_observed_date,
  last_observed_date,
  first_observed_ts,
  last_observed_ts,
  user_first_touch_ts,
  user_first_touch_date,
  CASE
    WHEN user_first_touch_date IS NULL THEN 'missing_first_touch'
    WHEN user_first_touch_date < DATE '2020-11-01' THEN 'first_touch_before_sample'
    WHEN user_first_touch_date <= DATE '2021-01-31' THEN 'first_touch_inside_sample'
    ELSE 'first_touch_after_sample'
  END AS first_touch_window,
  event_rows,
  valid_sessions,
  first_visit_event_rows,
  first_observed_acquisition.source AS first_user_source_proxy,
  first_observed_acquisition.medium AS first_user_medium_proxy,
  first_observed_acquisition.campaign AS first_user_campaign_proxy,
  acquisition_combinations,
  acquisition_combinations > 1 AS has_inconsistent_acquisition
FROM labeled;
