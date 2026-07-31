# Analysis Layer Build Results

**Execution date:** 2026-07-31  
**Engine:** BigQuery Standard SQL  
**Source window:** 2020-11-01 through 2021-01-31  
**Status:** Pass — 43 of 43 core and analysis-layer checks passed

## Built objects

The governed core remains eight reusable BigQuery views. The analysis layer is
refreshed as tables so dashboard queries do not repeatedly expand the nested
view graph.

| Object | Grain | Purpose |
|---|---|---|
| `int_checkout_sessions` | One ordered checkout session | Narrow execution bridge for checkout sequencing |
| `mart_metric_tree_daily` | One event date | Daily traffic, funnel, order, and revenue metrics |
| `mart_metric_tree_summary` | One full-window row | Executive KPI summary |
| `mart_funnel_overall` | One ordered funnel stage | Stage conversion and loss |
| `mart_funnel_by_segment` | One segment value × metric | Device, tenure, country, and channel comparisons |
| `mart_page_funnel` | One canonical PDP | Last-view attribution and page opportunity scenarios |
| `mart_checkout_funnel` | One checkout telemetry stage | Shipping, payment, and clean-purchase sequence |
| `mart_retention_weekly` | One complete cohort-week cell | W0–W8 observed weekly activity retention |
| `mart_product_sales` | One clean purchase SKU | Orders, units, and item revenue |

The local runner detects a derived object whose existing type blocks a refresh,
migrates that object from view to table when required, builds in dependency
order, runs the hard checks, and exports only aggregate CSV results.

## Preselected reporting rules

- Segment rows require at least 500 sessions and the relevant funnel metric
  requires at least 200 denominator sessions.
- PDP comparisons require at least 200 view sessions. This retains 191 pages
  and 92.61% of session-page exposures.
- The PDP benchmark is the unweighted 75th percentile view-to-add rate among
  eligible pages: 4.44%.
- PDP scenario orders apply the governed downstream ordered
  add-to-purchase rate of 17.32% and the clean AOV of $69.13.
- SKU rankings require at least 20 clean orders; 214 of 789 SKUs qualify.
- Retention requires a first-touch date inside the sample and a New session in
  the same Monday-starting cohort week. This excludes 80 of 255,356 initial
  candidates, or 0.031%, whose first-touch metadata and New-session timing do
  not align to the same week.
- Proportion intervals use the 95% Wilson method and are numerically clipped to
  the valid `[0, 1]` range at exact 0% or 100% boundaries.

## Observed evidence

These are descriptive results. Scenario values are not causal estimates.

### Metric tree

| Metric | Observed value |
|---|---:|
| Pseudonymous users | 270,154 |
| Valid sessions | 360,129 |
| Clean orders | 4,436 |
| Gross purchase revenue | $306,678.00 |
| Purchase-session conversion | 1.12% |
| Average order value | $69.13 |
| Revenue per session | $0.85 |

### Primary ordered funnel

| Stage | Sessions | Step conversion | Lost from prior stage |
|---|---:|---:|---:|
| `view_item` | 77,020 | 100.00% | — |
| `add_to_cart` | 14,380 | 18.67% | 62,640 |
| `begin_checkout` | 5,187 | 36.07% | 9,193 |
| `purchase` | 2,491 | 48.02% | 2,696 |

The largest observed absolute loss is product view to add-to-cart. Only 2,491
of 4,021 clean purchasing sessions contain the complete strict same-session
path, so the ordered funnel is a diagnostic path rather than a universal
journey model.

### Segment evidence

- Mobile purchase-session conversion is 1.15% versus 1.10% on desktop. The
  initial hypothesis that mobile is the obvious underperformer is not supported
  by the raw rates.
- Returning sessions convert to a clean purchase at 2.55% versus 0.57% for New
  sessions. Their ordered view-to-purchase rates are 6.03% and 1.90%,
  respectively. This is the largest stable descriptive split found so far.
- Session-channel results remain dominated by Missing, Conflicting,
  Obfuscated, and Self-referral quality groups. Channel differences are not
  treated as clean acquisition performance.
- Country estimates retain denominators and uncertainty. They are exploratory,
  and overlapping intervals do not support a market-priority decision by
  themselves.

### Page opportunity scenario

The highest-ranked eligible PDP is **Super G Unisex Joggers**:

- 3,830 session-page views;
- 46 attributed add sessions;
- 1.20% observed view-to-add rate, with a 95% Wilson interval of 0.90%–1.60%;
- 4.44% high-traffic-page P75 benchmark; and
- a non-additive scenario of 21.46 incremental orders and $1,483.56 revenue.

The value is a benchmark scenario, not a forecast. One session may appear on
multiple page rows, and page URLs are not joined to purchase SKUs merely because
their labels look similar.

### Checkout telemetry

| Stage | Sessions | Step conversion | Lost from prior stage |
|---|---:|---:|---:|
| `begin_checkout` | 5,187 | 100.00% | — |
| `add_shipping_info` | 2,978 | 57.41% | 2,209 |
| `add_payment_info` | 2,360 | 79.25% | 618 |
| clean purchase after payment | 1,550 | 65.68% | 810 |

There are 2,491 clean purchases after ordered checkout regardless of
intermediate telemetry, but only 1,550 contain the full strict shipping and
payment sequence. The initial 941-session difference was not labeled checkout
friction without further evidence.

Follow-up query
[`11_checkout_telemetry_diagnostic.sql`](../sql/analysis/11_checkout_telemetry_diagnostic.sql)
resolved the ambiguity: all 941 gap purchases contain `add_shipping_info` at or
before the governed checkout start and `add_payment_info` after checkout but
before purchase. None lacks shipping everywhere in the session. Because 4,811
of 5,187 eligible sessions contain multiple `begin_checkout` events, the strict
gap is primarily an event-order/re-entry artifact relative to the governed
start—not evidence that 941 users skipped a required interface step.

### Retention and product sales

Weighted across complete available cohort cells, observed activity retention is
3.75% in W1, 1.52% in W2, and 0.30% in W8. Later-week figures use fewer mature
cohorts and are not directly comparable without retaining those denominators.

The top clean purchase SKU by item revenue is **Google Canteen Bottle Black**
at $4,892.00, or 1.60% of clean item revenue. The top ten SKUs contribute
11.28%, indicating a relatively dispersed sales mix. SKU sales are not used as
a substitute for the page behavioral funnel.

## Notebook sensitivity results

The executed
[`01_funnel_and_sensitivity.ipynb`](../notebooks/01_funnel_and_sensitivity.ipynb)
uses only aggregate extracts and produced the following decision checks.

### Segment uncertainty

The preselected independent-proportion comparisons use 95% Newcombe intervals:

| Comparison | Metric | Difference | 95% CI | Interpretation |
|---|---|---:|---:|---|
| Mobile − Desktop | Purchase-session conversion | +0.06 pp | −0.01 to +0.13 pp | No observed mobile deficit; interval includes zero |
| Mobile − Desktop | Ordered view-to-purchase | +0.22 pp | −0.03 to +0.48 pp | Interval includes zero |
| Returning − New | Purchase-session conversion | +1.98 pp | +1.87 to +2.08 pp | Large descriptive tenure split |
| Returning − New | Checkout completion | +18.34 pp | +15.65 to +21.00 pp | Large descriptive tenure split |
| Returning − New | Ordered view-to-purchase | +4.13 pp | +3.81 to +4.45 pp | Large descriptive tenure split |

Sessions are treated as independent in these intervals. Repeated users across
sessions and unadjusted traffic mix remain limitations.

### Robustness and benchmark sensitivity

- Removing the four low-volume dates and one high-volume date changes
  purchase-session conversion by only **+0.92 basis points**. The principal
  funnel and value findings are stable to this exclusion.
- Missing, Conflicting, Obfuscated, and Self-referral channel-quality buckets
  contain **70.13% of sessions**. Their purchase conversion is 1.38%, versus
  0.50% among stable named channels. Channel rankings are therefore not
  decision-grade.
- PDP thresholds of 50, 100, 200, 500, and 1,000 views combined with exact P50,
  P75, and P90 peer benchmarks produce top-page scenarios ranging from
  **4.1 to 151.3 incremental orders**. The governed P75 top page remains
  **Super G Unisex Joggers** across every tested threshold, but the magnitude is
  highly benchmark-sensitive.
- The governed page rule remains 200 views and P75, producing **21.46 scenario
  orders** and **$1,483.56 scenario revenue** for the top single PDP.

### Checkout sensitivity

The strict recorded checkout path contains 5,187 starts and 1,550 purchases
after payment, while the primary any-intermediate ordered definition contains
2,491 purchases. The follow-up diagnostic classifies 940 of the 941 gap
purchases as payment-before-purchase with shipping already recorded at or
before the governed checkout start; the remaining session contains both event
types in a non-strict order.

| Assumed absolute checkout lift | Scenario incremental orders | Scenario revenue |
|---:|---:|---:|
| +0.25 pp | 13.0 | $896 |
| +0.50 pp | 25.9 | $1,793 |
| +1.00 pp | 51.9 | $3,586 |
| +2.00 pp | 103.7 | $7,172 |
| +3.00 pp | 155.6 | $10,758 |
| +5.00 pp | 259.4 | $17,930 |

Even the +0.50 percentage-point checkout scenario exceeds the governed top
single-PDP scenario. This comparison supports prioritization; it does not prove
that the lift is achievable.

## Provisional decision and next analysis

**Advance a simplified checkout intervention into experiment design,
conditional on experiment-specific telemetry and MDE approval.**

The historical sequence artifact is now characterized, but it does not prove
that the existing interface causes abandonment. Before launch, the project
will:

1. implement a dedicated sticky experiment-exposure event rather than using
   repeated `begin_checkout` events as assignment evidence;
2. keep clean purchase within 24 hours of first eligible checkout as the
   primary outcome;
3. use sticky 50/50 pseudonymous-user randomization;
4. preregister the business MDE and required sample size;
5. validate payment-error, refund/cancellation, and checkout-time guardrails;
6. treat tenure interaction analysis as secondary and exploratory; and
7. retain the top PDP as a secondary opportunity rather than summing page
   scenarios.

The statistical planning and visibly simulated analysis are now implemented in
[`02_ab_test_design_and_simulation.ipynb`](../notebooks/02_ab_test_design_and_simulation.ipynb).
The locked planning values, feasibility constraint, and remaining launch gates
are recorded in [`experiment_design.md`](experiment_design.md).
The detailed historical sequence evidence is recorded in
[`checkout_telemetry_diagnostic.md`](checkout_telemetry_diagnostic.md).

Aggregate extracts are written to the Git-ignored
`data/interim/query_results/` directory. The successful QA run is timestamped
`20260731T052745Z`; the complete twelve-result analysis export is timestamped
`20260731T052813Z`.
