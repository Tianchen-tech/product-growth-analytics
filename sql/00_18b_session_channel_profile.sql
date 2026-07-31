-- Product Growth Analytics
-- File: sql/00_18b_session_channel_profile.sql
-- Dialect: BigQuery Standard SQL
-- Source window: 2020-11-01 through 2021-01-31
--
-- PURPOSE
-- -------
-- Build and validate a session-level source/medium proxy from event_params.
-- This is distinct from traffic_source.*, which represents first-user
-- acquisition and was found to be inconsistent for 15.64% of users.
--
-- POLICY
-- ------
-- Select the first non-empty source and first non-empty medium observed within
-- each validated composite session. Preserve missing and obfuscated values,
-- and report sessions containing multiple non-empty values.

WITH raw_events AS (
  SELECT
    event_timestamp,
    user_pseudo_id,
    (
      SELECT ANY_VALUE(value.int_value)
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id,
    (
      SELECT ANY_VALUE(value.string_value)
      FROM UNNEST(event_params)
      WHERE key = 'source'
    ) AS event_source,
    (
      SELECT ANY_VALUE(value.string_value)
      FROM UNNEST(event_params)
      WHERE key = 'medium'
    ) AS event_medium
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
),
event_base AS (
  SELECT
    event_timestamp,
    user_pseudo_id,
    CONCAT(
      user_pseudo_id,
      '#',
      CAST(ga_session_id AS STRING)
    ) AS session_key,
    NULLIF(event_source, '') AS event_source,
    NULLIF(event_medium, '') AS event_medium
  FROM raw_events
  WHERE user_pseudo_id IS NOT NULL
    AND ga_session_id IS NOT NULL
),
session_channel AS (
  SELECT
    session_key,
    user_pseudo_id,
    ARRAY_AGG(
      event_source IGNORE NULLS
      ORDER BY event_timestamp
      LIMIT 1
    )[SAFE_OFFSET(0)] AS session_source,
    ARRAY_AGG(
      event_medium IGNORE NULLS
      ORDER BY event_timestamp
      LIMIT 1
    )[SAFE_OFFSET(0)] AS session_medium,
    COUNT(DISTINCT event_source) AS sources_in_session,
    COUNT(DISTINCT event_medium) AS mediums_in_session
  FROM event_base
  GROUP BY session_key, user_pseudo_id
),
normalized_sessions AS (
  SELECT
    session_key,
    user_pseudo_id,
    COALESCE(session_source, '[missing]') AS session_source,
    COALESCE(session_medium, '[missing]') AS session_medium,
    sources_in_session,
    mediums_in_session
  FROM session_channel
),
combination_counts AS (
  SELECT
    session_source,
    session_medium,
    COUNT(*) AS sessions
  FROM normalized_sessions
  GROUP BY session_source, session_medium
),
ranked_combinations AS (
  SELECT
    session_source,
    session_medium,
    ROW_NUMBER() OVER (
      ORDER BY sessions DESC, session_source, session_medium
    ) AS combination_rank
  FROM combination_counts
),
labeled_sessions AS (
  SELECT
    normalized_sessions.*,
    ranked_combinations.combination_rank
  FROM normalized_sessions
  JOIN ranked_combinations USING (session_source, session_medium)
),
grouped_sessions AS (
  SELECT
    * EXCEPT (session_source, session_medium),
    IF(
      combination_rank <= 15
        OR session_source IN ('[missing]', '<Other>', '(data deleted)')
        OR session_medium IN ('[missing]', '<Other>', '(data deleted)'),
      session_source,
      'Other'
    ) AS channel_source_group,
    IF(
      combination_rank <= 15
        OR session_source IN ('[missing]', '<Other>', '(data deleted)')
        OR session_medium IN ('[missing]', '<Other>', '(data deleted)'),
      session_medium,
      'Other'
    ) AS channel_medium_group
  FROM labeled_sessions
)
SELECT
  channel_source_group AS session_source,
  channel_medium_group AS session_medium,
  COUNT(*) AS sessions,
  COUNT(DISTINCT user_pseudo_id) AS users,
  COUNTIF(sources_in_session > 1) AS sessions_with_multiple_sources,
  COUNTIF(mediums_in_session > 1) AS sessions_with_multiple_mediums,
  ROUND(100 * SAFE_DIVIDE(COUNT(*), SUM(COUNT(*)) OVER ()), 2)
    AS session_share_pct
FROM grouped_sessions
GROUP BY channel_source_group, channel_medium_group
ORDER BY sessions DESC, session_source, session_medium;
