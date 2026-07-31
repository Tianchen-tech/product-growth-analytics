# SQL execution order

All SQL uses BigQuery Standard SQL and the public source:

```text
bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*
```

Run the numbered sections in `00_data_profile.sql` individually before building
downstream models. Record failed assumptions or unavailable fields in
`docs/metric_dictionary.md`; do not silently replace a planned definition.

Targeted quality follow-ups are maintained as separate files:

- `00_12b_transaction_conflict_breakdown.sql`
- `00_18b_session_channel_profile.sql`

Implemented model order:

1. Source profiling and data-quality gates.
2. `models/01_stg_events.sql`
3. `models/02_stg_event_items.sql`
4. `models/03_dim_users.sql`
5. `models/04_int_clean_purchase_events.sql`
6. `models/05_fct_orders.sql`
7. `models/06_fct_order_items.sql`
8. `models/07_fct_sessions.sql`
9. `models/08_dim_products.sql`
10. `marts/09_int_checkout_sessions.sql`
11. `marts/10_mart_metric_tree_daily.sql`
12. `marts/11_mart_metric_tree_summary.sql`
13. `marts/12_mart_funnel_overall.sql`
14. `marts/13_mart_funnel_by_segment.sql`
15. `marts/14_mart_page_funnel.sql`
16. `marts/15_mart_checkout_funnel.sql`
17. `marts/16_mart_retention_weekly.sql`
18. `marts/17_mart_product_sales.sql`
19. `qa/01_core_model_reconciliation.sql` through
    `qa/07_product_reconciliation.sql`
20. Aggregate-only result queries under `analysis/`

The twelve aggregate result queries include the governed dashboard outputs,
daily anomaly diagnostics, retention-alignment diagnostics, and the full
553-row PDP aggregate used for notebook threshold and benchmark sensitivity.
The checkout telemetry diagnostic is a multi-statement query that uses
session-scoped temporary tables to avoid repeatedly expanding the governed view
graph; only its final aggregate result set is exported.

Core models are reusable views. The execution bridge and analysis marts are
refreshed tables: this prevents BigQuery's planner from repeatedly expanding
the complete nested view graph and gives the dashboard stable aggregate
sources.

Every source query must include a `_TABLE_SUFFIX` date filter. Event-level
revenue must be aggregated before any `UNNEST(items)` operation.

The local runner substitutes `{{ project_id }}` and `{{ dataset_id }}` from
`.env`; SQL committed to Git never contains a personal project ID.

`make all` performs the full sequence. `make build`, `make qa`, and
`make extract` run the individual phases. The runner also supports selected
paths, for example:

```bash
python3 scripts/bq_runner.py build sql/marts/16_mart_retention_weekly.sql
python3 scripts/bq_runner.py extract sql/analysis/06_retention_weekly.sql
```
