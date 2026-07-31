# Data Model

**Status:** Core views and refreshed analysis tables live; 43 of 43 BigQuery
reconciliations passed.

```text
GA4 events
├── staged events
│   ├── stg_events
│   └── stg_event_items
├── dimensions
│   ├── dim_users
│   └── dim_products
├── governed transaction layer
│   └── int_clean_purchase_events
├── facts
│   ├── fct_sessions
│   ├── fct_orders
│   └── fct_order_items
└── refreshed analysis layer
    ├── int_checkout_sessions
    ├── mart_metric_tree_daily
    ├── mart_metric_tree_summary
    ├── mart_funnel_overall
    ├── mart_funnel_by_segment
    ├── mart_page_funnel
    ├── mart_checkout_funnel
    ├── mart_retention_weekly
    └── mart_product_sales
```

Core models are BigQuery views. The execution bridge and analysis marts are
refreshed BigQuery tables so dashboard and QA queries do not repeatedly expand
the complete nested view graph. They are built in lexical filename order by
`scripts/bq_runner.py`.

| Model | Grain | Primary key / rule |
|---|---|---|
| `stg_events` | One source GA4 event row | No invented event ID; source duplicates remain |
| `stg_event_items` | One item-array payload row | Event context plus item offset; behavioral attribution is not implied |
| `dim_users` | One pseudonymous user | `user_key` |
| `int_clean_purchase_events` | One canonical clean purchase event | Clean `transaction_id` |
| `fct_orders` | One clean canonical order | `order_key` |
| `fct_order_items` | One canonical order item line | `order_item_key` |
| `fct_sessions` | One valid composite session | `session_key` |
| `dim_products` | One purchased SKU/variant | `purchase_product_key` |
| `int_checkout_sessions` | One ordered checkout session | Narrow materialized execution bridge |
| `mart_metric_tree_daily` | One observed event date | Additive daily KPI layer |
| `mart_metric_tree_summary` | One complete-window row | Executive metric tree |
| `mart_funnel_overall` | One ordered funnel stage | Strict stage loss and conversion |
| `mart_funnel_by_segment` | One segment value × metric | Wilson intervals and reporting flags |
| `mart_page_funnel` | One canonical PDP | Last-view attribution and non-additive scenario |
| `mart_checkout_funnel` | One strict checkout stage | Ordered shipping/payment diagnostics |
| `mart_retention_weekly` | One complete cohort-week cell | W0–W8 observed activity |
| `mart_product_sales` | One clean purchase SKU | Sales only; no behavioral funnel claim |

The authoritative definitions and caveats remain in
`docs/metric_dictionary.md`. Hard expected-value checks are in
`sql/qa/01_core_model_reconciliation.sql`.

The source profile established two separate product concepts:

- product-page behavior uses a canonicalized `page_location`; and
- purchased-product reporting uses purchase `item_id` at SKU/variant grain.

View/add item arrays are not used as focal-product actions because their
cardinality behaves like a fixed 12-item payload.

## Required reconciliations

The successful 2026-07-31 core build reproduced:

- 4,295,584 staged events;
- 270,154 pseudonymous users;
- 360,129 valid sessions;
- 4,436 clean orders and `$306,678.00` event revenue;
- `$306,599.00` clean purchase-item revenue; and
- the ordered funnel counts 77,020 → 14,380 → 5,187 → 2,491.

The runner exits with failure if any hard check does not pass. Full recorded
output is in `docs/model_build_results.md`.

The analysis layer adds 21 hard checks covering:

- daily and summary reconciliation to all core totals;
- exhaustive session partitions for device, tenure, country, and channel;
- valid Wilson intervals and reporting thresholds;
- 553 unique PDP keys and the preselected 191-page reporting population;
- strict checkout-stage monotonicity and the 2,491 any-intermediate purchases;
- retention eligibility, complete W0–W8 cells, and censoring; and
- 789 unique SKU rows summing to `$306,599.00` item revenue.

Definitions and validated descriptive evidence are in
`docs/analysis_layer_results.md`.
