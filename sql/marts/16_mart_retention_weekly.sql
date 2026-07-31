-- Grain: one complete cohort-week by retention-week cell.
-- Cohorts require first touch inside the sample plus at least one New session.
-- The partial cohort week beginning 2020-10-26 is excluded, and incomplete
-- right-censored cells are omitted.

CREATE OR REPLACE TABLE
  `{{ project_id }}.{{ dataset_id }}.mart_retention_weekly`
OPTIONS (
  description = 'Complete W0-W8 observed weekly activity retention cohorts'
)
AS
WITH new_user_weeks AS (
  SELECT DISTINCT
    user_key,
    DATE_TRUNC(session_date, WEEK(MONDAY)) AS new_signal_week
  FROM `{{ project_id }}.{{ dataset_id }}.fct_sessions`
  WHERE user_tenure = 'New'
),
inside_sample_users AS (
  SELECT
    users.user_key,
    users.user_first_touch_date,
    DATE_TRUNC(users.user_first_touch_date, WEEK(MONDAY)) AS cohort_week
  FROM `{{ project_id }}.{{ dataset_id }}.dim_users` AS users
  WHERE users.first_touch_window = 'first_touch_inside_sample'
    AND DATE_TRUNC(users.user_first_touch_date, WEEK(MONDAY))
      > DATE '2020-10-26'
),
qualified_users AS (
  SELECT
    inside_sample_users.user_key,
    inside_sample_users.user_first_touch_date,
    inside_sample_users.cohort_week
  FROM inside_sample_users
  JOIN new_user_weeks
    ON new_user_weeks.user_key = inside_sample_users.user_key
   AND new_user_weeks.new_signal_week = inside_sample_users.cohort_week
),
cohort_sizes AS (
  SELECT
    cohort_week,
    COUNT(DISTINCT user_key) AS cohort_users
  FROM qualified_users
  GROUP BY cohort_week
),
weekly_activity AS (
  SELECT
    qualified_users.cohort_week,
    DIV(
      DATE_DIFF(
        DATE_TRUNC(sessions.session_date, WEEK(MONDAY)),
        qualified_users.cohort_week,
        DAY
      ),
      7
    ) AS retention_week,
    COUNT(DISTINCT sessions.user_key) AS active_users
  FROM qualified_users
  JOIN `{{ project_id }}.{{ dataset_id }}.fct_sessions` AS sessions
    USING (user_key)
  WHERE sessions.session_date >= qualified_users.user_first_touch_date
  GROUP BY qualified_users.cohort_week, retention_week
),
complete_grid AS (
  SELECT
    cohort_sizes.cohort_week,
    retention_week,
    cohort_sizes.cohort_users
  FROM cohort_sizes
  CROSS JOIN UNNEST(GENERATE_ARRAY(0, 8)) AS retention_week
  WHERE DATE_ADD(
    DATE_ADD(
      cohort_sizes.cohort_week,
      INTERVAL retention_week WEEK
    ),
    INTERVAL 6 DAY
  ) <= DATE '2021-01-31'
),
rates AS (
  SELECT
    complete_grid.cohort_week,
    DATE_ADD(complete_grid.cohort_week, INTERVAL 6 DAY)
      AS cohort_week_end,
    complete_grid.retention_week,
    DATE_ADD(
      complete_grid.cohort_week,
      INTERVAL complete_grid.retention_week WEEK
    ) AS activity_week,
    complete_grid.cohort_users,
    COALESCE(weekly_activity.active_users, 0) AS active_users,
    SAFE_DIVIDE(
      COALESCE(weekly_activity.active_users, 0),
      complete_grid.cohort_users
    ) AS retention_rate
  FROM complete_grid
  LEFT JOIN weekly_activity
    USING (cohort_week, retention_week)
)
SELECT
  cohort_week,
  cohort_week_end,
  retention_week,
  activity_week,
  DATE_ADD(activity_week, INTERVAL 6 DAY) AS activity_week_end,
  cohort_users,
  active_users,
  retention_rate,
  GREATEST(
    0.0,
    (
      retention_rate
      + 3.841458820694124 / (2 * cohort_users)
      - 1.959963984540054 * SQRT(
        retention_rate * (1 - retention_rate) / cohort_users
        + 3.841458820694124 / (4 * POW(cohort_users, 2))
      )
    ) / (1 + 3.841458820694124 / cohort_users)
  )
    AS retention_rate_ci95_lower,
  LEAST(
    1.0,
    (
      retention_rate
      + 3.841458820694124 / (2 * cohort_users)
      + 1.959963984540054 * SQRT(
        retention_rate * (1 - retention_rate) / cohort_users
        + 3.841458820694124 / (4 * POW(cohort_users, 2))
      )
    ) / (1 + 3.841458820694124 / cohort_users)
  )
    AS retention_rate_ci95_upper,
  TRUE AS is_complete_followup_cell,
  'Observed weekly activity retention within the sample'
    AS retention_scope
FROM rates;
