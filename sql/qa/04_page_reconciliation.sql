-- PDP attribution and opportunity-scenario safeguards.

WITH page_metrics AS (
  SELECT
    COUNT(*) AS page_rows,
    COUNT(DISTINCT product_page_key) AS distinct_pages,
    COUNTIF(is_reportable) AS reportable_pages,
    COUNT(DISTINCT IF(is_reportable, benchmark_view_to_add_rate, NULL))
      AS reportable_benchmarks,
    COUNTIF(
      attributed_add_sessions > view_sessions
      OR attributed_checkout_sessions > attributed_add_sessions
      OR attributed_ordered_purchase_sessions > attributed_checkout_sessions
    ) AS non_monotonic_rows,
    COUNTIF(
      view_to_add_rate < 0 OR view_to_add_rate > 1
      OR view_to_add_rate_ci95_lower < 0
      OR view_to_add_rate_ci95_upper > 1
      OR view_to_add_rate_ci95_lower > view_to_add_rate
      OR view_to_add_rate_ci95_upper < view_to_add_rate
    ) AS invalid_rate_rows,
    COUNTIF(
      scenario_incremental_add_sessions < 0
      OR scenario_incremental_orders < 0
      OR scenario_revenue_opportunity_usd < 0
    ) AS negative_opportunity_rows,
    COUNTIF(opportunity_values_are_additive) AS additive_claim_rows,
    COUNTIF(
      NOT is_reportable
      AND (
        view_to_add_gap IS NOT NULL
        OR scenario_incremental_orders IS NOT NULL
      )
    ) AS unsuppressed_small_page_rows
  FROM `{{ project_id }}.{{ dataset_id }}.mart_page_funnel`
)
SELECT check_result.*
FROM page_metrics
CROSS JOIN UNNEST([
  STRUCT(
    'page_key_uniqueness' AS check_name,
    IF(
      page_metrics.page_rows > 0
      AND page_metrics.page_rows = page_metrics.distinct_pages,
      'PASS',
      'FAIL'
    ) AS status,
    FORMAT(
      '%d / %d',
      page_metrics.distinct_pages,
      page_metrics.page_rows
    ) AS actual_value,
    'unique and nonempty' AS expected_value,
    'One row per canonical PDP key' AS details
  ),
  STRUCT(
    'page_reporting_population',
    IF(
      page_metrics.reportable_pages = 191
      AND page_metrics.reportable_benchmarks = 1,
      'PASS',
      'FAIL'
    ),
    FORMAT(
      '%d pages / %d benchmark',
      page_metrics.reportable_pages,
      page_metrics.reportable_benchmarks
    ),
    '191 pages / 1 benchmark',
    'Preselected 200-view-session threshold and common P75 benchmark'
  ),
  STRUCT(
    'page_metric_validity',
    IF(
      page_metrics.non_monotonic_rows = 0
      AND page_metrics.invalid_rate_rows = 0
      AND page_metrics.negative_opportunity_rows = 0
      AND page_metrics.additive_claim_rows = 0
      AND page_metrics.unsuppressed_small_page_rows = 0,
      'PASS',
      'FAIL'
    ),
    FORMAT(
      '%d monotonic / %d rate / %d negative / %d additive / %d unsuppressed',
      page_metrics.non_monotonic_rows,
      page_metrics.invalid_rate_rows,
      page_metrics.negative_opportunity_rows,
      page_metrics.additive_claim_rows,
      page_metrics.unsuppressed_small_page_rows
    ),
    '0 monotonic / 0 rate / 0 negative / 0 additive / 0 unsuppressed',
    'Attribution and scenario values obey all defined safeguards'
  )
]) AS check_result
ORDER BY check_name;
