# Dashboard Field Dictionary

**Version:** 1.0  
**Source run:** `20260731T052813Z`  
**Privacy class:** Aggregate-only

All rates are stored as decimal proportions unless the field name ends in
`_pp`, which denotes percentage points.

## Files

| File | Grain | Main use | Important caution |
|---|---|---|---|
| `kpi_summary.csv` | One analysis window | Metric tree and executive KPIs | Historical sample, not current performance |
| `monthly_performance.csv` | Calendar month | Traffic, orders, revenue, conversion, AOV | Three months do not establish seasonality |
| `funnel_overall.csv` | Ordered funnel stage | Step and cumulative funnel | Same-session event ordering |
| `segment_funnel.csv` | Segment × metric | Device and New / Returning comparisons | Descriptive, not causal |
| `page_opportunities.csv` | Reportable PDP | Product opportunity ranking | Scenarios are non-additive |
| `retention_curve.csv` | Retention week | Pooled observed activity retention | Complete follow-up cells only |
| `checkout_telemetry_summary.csv` | Diagnostic metric | Sequence/re-entry diagnosis | A telemetry gap is not abandonment |
| `checkout_telemetry_by_segment.csv` | Segment value | Gap-rate comparison | Denominator is purchases after checkout |
| `checkout_lift_scenarios.csv` | Absolute lift assumption | Orders/revenue scenario calculator | Scenario, not forecast or MDE |
| `mde_sensitivity.csv` | Candidate absolute MDE | Sample-size trade-off | Historical session volume is only a proxy |
| `experiment_plan.csv` | One planning contract | A/B design summary | Instrumentation and stakeholder gates remain |
| `simulation_only_result.csv` | One seeded simulation | Demonstrate analysis workflow | No evidentiary value about a real treatment |
| `data_manifest.csv` | Published CSV | Lineage, row count, privacy, hash | Hash covers the corresponding committed CSV |

## Core metrics

| Field | Definition |
|---|---|
| `sessions` | Count of valid composite sessions in the analysis population |
| `product_view_sessions` | Sessions with a governed `view_item` event |
| `purchasing_sessions` | Sessions with at least one clean canonical order |
| `orders` | Distinct clean canonical transaction IDs |
| `revenue_usd` | Canonical clean order revenue in USD |
| `purchase_session_conversion_rate` | Purchasing sessions ÷ valid sessions |
| `average_order_value_usd` | Canonical revenue ÷ clean orders |
| `revenue_per_session_usd` | Canonical revenue ÷ valid sessions |

## Ordered funnel

| Field | Definition |
|---|---|
| `sessions` | Sessions reaching the stage after all required prior stages |
| `step_conversion_rate` | Stage sessions ÷ immediately prior-stage sessions |
| `cumulative_conversion_rate` | Stage sessions ÷ ordered `view_item` sessions |
| `lost_sessions_from_prior_stage` | Prior-stage sessions − stage sessions |
| `step_dropoff_rate` | 1 − step conversion rate |

## Segment inference fields

| Field | Definition |
|---|---|
| `numerator_sessions` | Sessions satisfying the selected conversion outcome |
| `denominator_sessions` | Eligible sessions for the selected metric |
| `conversion_rate` | Numerator sessions ÷ denominator sessions |
| `conversion_rate_ci95_lower` | Wilson 95% interval lower bound |
| `conversion_rate_ci95_upper` | Wilson 95% interval upper bound |
| `minimum_denominator` | Governed reporting threshold |
| `is_reportable` | Whether the denominator meets the threshold |

## Product opportunity fields

| Field | Definition |
|---|---|
| `view_to_add_rate` | PDP view sessions with an attributed later add ÷ PDP view sessions |
| `benchmark_view_to_add_rate` | Unweighted P75 among PDPs with at least 200 view sessions |
| `scenario_incremental_orders` | Incremental adds at benchmark × observed downstream rate |
| `scenario_revenue_opportunity_usd` | Scenario incremental orders × governed AOV |
| `opportunity_values_are_additive` | Always `false`; sessions may view multiple PDPs |

## Experiment fields

| Field | Definition |
|---|---|
| `planned_absolute_mde_pp` | Provisional smallest detectable absolute lift, in percentage points |
| `buffered_target_per_arm` | Core per-arm sample plus 5% operational buffer |
| `historical_volume_proxy_weeks` | Sample ÷ historical checkout-session throughput ÷ seven |
| `randomization_unit` | Planned assignment unit; `user` |
| `exposure_rule` | Sticky exposure event; repeated checkout cannot re-randomize |
| `is_simulated` | `true` only for synthetic experiment output |

For complete business definitions and exclusions, use the repository-level
[metric dictionary](../docs/metric_dictionary.md).
