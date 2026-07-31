-- Grain: one stage in the primary strict same-session ordered funnel.

CREATE OR REPLACE TABLE
  `{{ project_id }}.{{ dataset_id }}.mart_funnel_overall`
OPTIONS (
  description = 'Strict ordered session funnel with losses and conversion rates'
)
AS
WITH counts AS (
  SELECT
    COUNT(*) AS all_sessions,
    COUNTIF(reached_view_item) AS viewed_sessions,
    COUNTIF(reached_add_to_cart_after_view) AS added_sessions,
    COUNTIF(reached_checkout_after_add_to_cart) AS checkout_sessions,
    COUNTIF(reached_purchase_after_checkout) AS purchased_sessions
  FROM `{{ project_id }}.{{ dataset_id }}.fct_sessions`
),
stages AS (
  SELECT 1 AS stage_index, 'view_item' AS stage_name,
    viewed_sessions AS sessions
  FROM counts
  UNION ALL
  SELECT 2, 'add_to_cart', added_sessions
  FROM counts
  UNION ALL
  SELECT 3, 'begin_checkout', checkout_sessions
  FROM counts
  UNION ALL
  SELECT 4, 'purchase', purchased_sessions
  FROM counts
),
sequenced AS (
  SELECT
    stage_index,
    stage_name,
    sessions,
    LAG(sessions) OVER (ORDER BY stage_index) AS prior_stage_sessions,
    FIRST_VALUE(sessions) OVER (ORDER BY stage_index) AS first_stage_sessions
  FROM stages
)
SELECT
  stage_index,
  stage_name,
  sessions,
  prior_stage_sessions,
  IF(
    stage_index = 1,
    1.0,
    SAFE_DIVIDE(sessions, prior_stage_sessions)
  ) AS step_conversion_rate,
  SAFE_DIVIDE(sessions, first_stage_sessions) AS cumulative_conversion_rate,
  IF(stage_index = 1, 0, prior_stage_sessions - sessions)
    AS lost_sessions_from_prior_stage,
  IF(
    stage_index = 1,
    0.0,
    1 - SAFE_DIVIDE(sessions, prior_stage_sessions)
  ) AS step_dropoff_rate,
  SAFE_DIVIDE(sessions, (SELECT all_sessions FROM counts))
    AS share_of_all_valid_sessions
FROM sequenced;
