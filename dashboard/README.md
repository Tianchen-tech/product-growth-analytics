# Dashboard

**Status:** The aggregate-only interactive dashboard is implemented, tested,
and privately deployed.

**Live dashboard:** [Product Growth Analytics Decision Dashboard](https://ga4-product-growth-decision-dashboard.world8866.chatgpt.site)

The dashboard is the portfolio-facing decision surface for this case study. It
uses the same governed aggregates as the SQL and notebooks and keeps observed
behavior, scenario estimates, and simulated experiment output visually
separate.

## What the dashboard answers

1. What is the traffic, conversion, order-value, and revenue baseline?
2. Where does the ordered product funnel lose the most sessions?
3. Do Device or New / Returning segments materially change the diagnosis?
4. Which high-traffic product-detail pages have the largest governed
   view-to-add opportunity scenarios?
5. Is the historical checkout sequence gap real abandonment or a telemetry
   artifact?
6. What checkout lift scenarios are commercially meaningful?
7. What sample, MDE, and instrumentation gates apply to the proposed A/B test?
8. How quickly does observed weekly activity retention decay?

## Views and interactions

- **Executive decision and metric tree:** sessions, product-view reach,
  purchase-session conversion, orders, revenue, and AOV.
- **Ordered funnel:** toggle between step and cumulative conversion.
- **Segment diagnosis:** switch between Device and New / Returning, then
  compare purchase/session, view-to-cart, or checkout-to-purchase rates.
- **Product opportunity:** top reportable PDP scenario rows, with non-additive
  opportunity warnings.
- **Checkout telemetry:** strict-sequence versus sequence-gap composition and
  segment comparisons.
- **Experiment design:** adjustable checkout-lift scenario calculator, planned
  MDE/sample contract, detectability trade-off, and a visibly labeled
  simulation-only example.
- **Retention:** pooled weekly activity retention among complete follow-up
  cohorts.
- **Downloads:** governed CSV extracts for Tableau, Power BI, or independent
  review.

## Reproduce locally

The data builder automatically selects the newest query-result folder that
contains every required aggregate input.

```bash
make dashboard-setup   # one-time Node dependency install
make dashboard-data    # refresh public aggregate CSVs and site JSON
make dashboard-test    # data refresh, production build, tests, and lint
make dashboard-dev     # local interactive preview
```

Run `make extract` first whenever the BigQuery marts or analysis queries have
changed. The current committed dashboard data comes from aggregate run
`20260731T052813Z`.

## Published aggregate files

`aggregated_data/` contains twelve dashboard-ready CSVs plus a manifest:

- KPI summary and monthly performance;
- ordered funnel and reportable Device / New / Returning comparisons;
- top-ten governed PDP opportunity scenarios;
- pooled retention curve;
- checkout telemetry summary and segment comparison;
- checkout lift scenarios;
- MDE sensitivity, experiment plan, and simulation-only result.

The [field dictionary](field_dictionary.md) documents grains, evidence labels,
and usage cautions. `data_manifest.csv` records row counts, source run, privacy
level, and SHA-256 hashes.

## Privacy and interpretation

- No user-, session-, event-, order-, or transaction-level row is published.
- Product opportunity values are scenarios and cannot be summed across pages.
- Historical segment differences are descriptive, not causal.
- The checkout sequence gap is treated as a re-entry/order artifact, not as
  abandonment.
- Experiment output is synthetic and explicitly marked `is_simulated = true`.
- The sample covers 2020-11-01 through 2021-01-31 and must not be presented as
  current Google Merchandise Store performance.

## Implementation

The web dashboard lives in `site/` and uses vinext/React with a
Cloudflare-compatible production build. `scripts/build_dashboard_data.py`
creates both the reusable CSVs and the typed site data payload from the same
source run.
