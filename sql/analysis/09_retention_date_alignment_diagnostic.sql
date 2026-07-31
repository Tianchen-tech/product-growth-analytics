-- Aggregate diagnostic for the UTC first-touch date versus GA4 property
-- event_date. It contains no user-level output.

WITH user_dates AS (
  SELECT
    user_key,
    DATE(MIN(user_first_touch_ts)) AS user_first_touch_date,
    MIN(IF(ga_session_number = 1, event_date, NULL))
      AS first_new_event_date,
    COUNTIF(ga_session_number = 1) > 0 AS has_new_signal
  FROM `{{ project_id }}.{{ dataset_id }}.stg_events`
  WHERE user_key IS NOT NULL
  GROUP BY user_key
),
qualified AS (
  SELECT *
  FROM user_dates
  WHERE user_first_touch_date BETWEEN DATE '2020-11-01' AND DATE '2021-01-31'
    AND has_new_signal
    AND DATE_TRUNC(user_first_touch_date, WEEK(MONDAY)) > DATE '2020-10-26'
)
SELECT
  DATE_DIFF(first_new_event_date, user_first_touch_date, DAY)
    AS new_event_minus_first_touch_days,
  COUNT(*) AS users,
  MIN(user_first_touch_date) AS earliest_first_touch_date,
  MAX(user_first_touch_date) AS latest_first_touch_date
FROM qualified
GROUP BY new_event_minus_first_touch_days
ORDER BY new_event_minus_first_touch_days;
