# Model Build Results

**Execution date:** 2026-07-31  
**Engine:** BigQuery Standard SQL  
**Location:** US  
**Status:** Pass — eight governed core views, one execution bridge, and eight
analysis tables built; 43 of 43 hard checks passed

## Built models

| Execution order | Model | Grain |
|---:|---|---|
| 1 | `stg_events` | One source GA4 event row |
| 2 | `stg_event_items` | One item-array payload row |
| 3 | `dim_users` | One pseudonymous user |
| 4 | `int_clean_purchase_events` | One canonical clean purchase event |
| 5 | `fct_orders` | One clean canonical order |
| 6 | `fct_order_items` | One canonical order item line |
| 7 | `fct_sessions` | One valid composite session |
| 8 | `dim_products` | One clean purchased SKU/variant |

All models passed a BigQuery dry run immediately before creation.

## Reconciliation results

| Check | Actual | Expected | Status |
|---|---:|---:|---|
| Staged event rows | 4,295,584 | 4,295,584 | Pass |
| Missing staged user keys | 0 | 0 | Pass |
| Missing staged session keys | 0 | 0 | Pass |
| Observed event dates | 92 | 92 | Pass |
| User dimension rows | 270,154 | 270,154 | Pass |
| Session fact rows | 360,129 | 360,129 | Pass |
| Event rows rolled into sessions | 4,295,584 | 4,295,584 | Pass |
| New sessions | 261,238 | 261,238 | Pass |
| Returning sessions | 98,891 | 98,891 | Pass |
| Ordered view-item sessions | 77,020 | 77,020 | Pass |
| Ordered add-to-cart sessions | 14,380 | 14,380 | Pass |
| Ordered checkout sessions | 5,187 | 5,187 | Pass |
| Ordered purchase sessions | 2,491 | 2,491 | Pass |
| Clean purchase sessions, any path | 4,021 | 4,021 | Pass |
| Clean order rows | 4,436 | 4,436 | Pass |
| Clean order revenue | $306,678.00 | $306,678.00 | Pass |
| Session-attributed clean revenue | $306,678.00 | $306,678.00 | Pass |
| Clean order-item revenue | $306,599.00 | $306,599.00 | Pass |
| Order-to-item revenue rollup | $306,599.00 | $306,599.00 | Pass |
| Missing purchase product keys | 0 | 0 | Pass |
| Order-item key uniqueness | 13,176 / 13,176 | Equal | Pass |
| Product key uniqueness | 789 / 789 | Equal | Pass |

## Additional observed baselines

- Canonical clean orders contain 13,176 order-item lines.
- The clean purchase product dimension contains 789 SKU/variant keys.
- The raw purchase profile contained 16,003 item payload rows and 810 distinct
  item IDs. The lower clean-model counts reflect transaction exclusions,
  canonical duplicate selection, or both; the difference is not labeled
product loss.

## Analysis-layer build

| Execution order | Object | Storage | Grain |
|---:|---|---|---|
| 9 | `int_checkout_sessions` | Refreshed table | One ordered checkout session |
| 10 | `mart_metric_tree_daily` | Refreshed table | One event date |
| 11 | `mart_metric_tree_summary` | Refreshed table | One full-window row |
| 12 | `mart_funnel_overall` | Refreshed table | One ordered funnel stage |
| 13 | `mart_funnel_by_segment` | Refreshed table | One segment value × metric |
| 14 | `mart_page_funnel` | Refreshed table | One canonical PDP |
| 15 | `mart_checkout_funnel` | Refreshed table | One checkout stage |
| 16 | `mart_retention_weekly` | Refreshed table | One complete cohort-week cell |
| 17 | `mart_product_sales` | Refreshed table | One clean purchase SKU |

The 21 additional hard checks cover metric-tree totals, exhaustive segment
partitions, Wilson interval bounds, page attribution and thresholds, checkout
monotonicity, retention censoring, and SKU revenue. All passed on 2026-07-31.
Detailed results and initial evidence are recorded in
`docs/analysis_layer_results.md`.

## Automation evidence

The local runner:

1. verified the official Google Cloud CLI and local authentication;
2. created the destination dataset;
3. dry-ran and built models in dependency order;
4. executed all hard reconciliation queries;
5. exported the aggregate analysis results; and
6. saved every local CSV under the Git-ignored
   `data/interim/query_results/` directory.

No event-, user-, session-, order-, or item-level rows were downloaded.
