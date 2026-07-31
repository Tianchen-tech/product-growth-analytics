# Metric Dictionary

**Project:** Product Growth Analytics  
**Version:** 0.26 — checkout sequence diagnostic and experiment exposure rule locked  
**Source window:** 2020-11-01 through 2021-01-31  
**Currency:** USD unless explicitly stated otherwise

## Purpose

This document defines the analytical grains, identifiers, metrics, segment
dimensions, and decision rules used throughout SQL, notebooks, the dashboard,
and the product decision memo.

Definitions are written before results are examined to reduce the risk of
changing a denominator or comparison after seeing an attractive result. Any
necessary deviation must be documented here with the reason and impact.

## Source and analytical grains

The raw GA4 export is event-grain data with two important repeated records:
`event_params` and `items`. The project separates the following grains:

| Model | One row represents | Primary purpose |
|---|---|---|
| Staged event | One GA4 event | Event sequencing, page context, event revenue |
| Event-item bridge | One item attached to one event | Product and item funnel analysis |
| User dimension | One `user_pseudo_id` | First observed activity and acquisition attributes |
| Session fact | One composite session | Traffic, segment, and session funnel metrics |
| Product dimension | One validated product key | Product labels and categories |
| Order fact | One valid transaction | Orders, revenue, and average order value |
| Order-item fact | One item in one valid transaction | Product sales and basket analysis |

Event-level revenue must never be summed after an uncontrolled `UNNEST(items)`.

## Identifiers

| Name | Definition | Caveat |
|---|---|---|
| `user_key` | `user_pseudo_id` | Pseudonymous browser/device identifier; not necessarily one human or logged-in customer |
| `session_key` | `CONCAT(user_pseudo_id, '#', CAST(ga_session_id AS STRING))` | Rows missing either component are excluded from primary session metrics and reported separately |
| `transaction_key` | Trimmed, non-empty `ecommerce.transaction_id` | Primary use additionally requires one user and one consistent revenue value |
| `purchase_product_key` | Valid non-empty purchase `item_id` | SKU/variant grain; `item_name` is the display and product-family label |
| `product_page_key` | Canonicalized `page_location` on `view_item` | Page exposure key; not assumed to map one-to-one to a purchase SKU |
| `event_key` | Deterministic surrogate constructed from available event fields | GA4 does not provide a guaranteed universal event ID; candidate key must pass a uniqueness audit before use |

The provisional event surrogate will combine `user_pseudo_id`,
`event_timestamp`, `event_name`, and available bundle/order fields. Duplicate
purchase events are resolved at the transaction grain, not by assuming every
event surrogate represents a new order.

Profiling query `00.6` empirically validated the composite-session rule:
`ga_session_id` was complete, but 349,545 distinct raw IDs mapped to 360,129
distinct user-session pairs. All session metrics therefore use `session_key`.

## Date and time rules

| Rule | Definition |
|---|---|
| Analysis window | Event tables from `20201101` through `20210131`, inclusive |
| Event date | `PARSE_DATE('%Y%m%d', event_date)` |
| Event timestamp | `TIMESTAMP_MICROS(event_timestamp)` |
| Cohort week | Monday-starting week containing the qualified user's first-touch date |
| Retention week | Integer week difference between activity week and cohort week |
| A/B conversion window | Purchase within 24 hours after first eligible checkout exposure |

The export's registered property time zone is not inferred from UTC timestamps.
Daily reporting uses `event_date`; within-session ordering uses
`event_timestamp`.

Query `00.2` confirmed events on all 92 expected dates and exact reconciliation
to 4,295,584 source rows. Four dates below 50% of the daily event-row median and
one date above 200% are retained in primary analysis as diagnostic flags, not
automatic exclusions. If they materially change a decision, an explicitly
labeled sensitivity result is reported alongside the full-window result.

## Event-parameter extraction rules

Parameter-key presence is not treated as proof of a populated value. Query
`00.4` found null-payload keys and parameters stored under multiple primitive
types, so staged-event SQL uses parameter-specific extraction:

- Integer session identifiers are read from `int_value`.
- String page and channel fields are read from `string_value` and remain null
  when that field is not populated.
- Mixed numeric fields explicitly coalesce supported numeric types.
- Mixed string/integer identifiers require documented casting before use.
- Presence-only keys may become boolean flags, but not readable identifiers.

The canonical order fields come from the `ecommerce` record, not the
mixed-type event parameters named `transaction_id` and `value`.

## Core traffic metrics

| Metric | Definition | Grain / denominator | Notes |
|---|---|---|---|
| Pseudonymous users | Distinct non-empty `user_key` | Selected period | A device/browser proxy, not known unique people |
| Valid sessions | Distinct non-empty `session_key` | Selected period | Primary traffic denominator |
| Sessions per user | Valid sessions ÷ pseudonymous users with a valid session | Selected period | Descriptive, not a retention metric |
| Product-view sessions | Valid sessions containing `view_item` | Valid sessions | Measures product-detail reach |
| Checkout-start sessions | Valid sessions containing `begin_checkout` | Valid sessions | Unordered reach metric; ordered funnel uses a stricter definition |
| Purchasing sessions | Valid sessions containing at least one valid purchase transaction | Valid sessions | One session can contain more than one order |

Rows without a valid session key remain in source-quality reporting but do not
enter session conversion denominators.

Profiling query `00.7` found that 5,272 valid composite sessions had no
`session_start` and 105 had more than one. Session counts therefore use distinct
`session_key`, while observed session start and end use the minimum and maximum
event timestamps within that key. A `session_start` event is not required for a
session to enter the primary denominator.

## User-tenure metrics

| Segment | Definition |
|---|---|
| New | Session has `ga_session_number = 1` |
| Returning | Session has `ga_session_number > 1` |
| Unknown | `ga_session_number` is missing or unusable |

The `first_visit` event is used to validate the classification. If
`ga_session_number` fails profiling, a separate `first_observed` label may be
used, but it must not be renamed `new`: users can have activity before the
sample window.

Profile query `00.5` found `ga_session_number` on 100% of event rows, so this is
the primary tenure definition. `first_visit` remains a consistency check rather
than a replacement.

Profile query `00.8` classified 261,238 sessions as New and 98,891 as
Returning, with no Unknown sessions. `first_visit` corroborated 98.53% of New
sessions and appeared on no Returning session. The 3,838 New sessions without
`first_visit` remain New under the primary session-number rule.

## Ordered funnel definitions

The primary funnel uses the session as its unit. Event presence alone is not
sufficient; each subsequent step must occur later in the same session.

| Funnel stage | Qualification |
|---|---|
| Viewed item | At least one `view_item` event |
| Added to cart | At least one `add_to_cart` after a qualifying `view_item` |
| Began checkout | At least one `begin_checkout` after a qualifying `add_to_cart` |
| Purchased | At least one valid purchase after a qualifying `begin_checkout` |

If multiple events exist, use the earliest event that occurs after the
qualifying timestamp of the previous step. This preserves a valid path even
when an earlier out-of-order event also exists.

Profiling query `00.3` confirmed that all four required event types are present.
Its event-level session counts are treated only as independent reach inventory;
they are not used as stage-to-stage conversion rates until query `00.10`
validates same-session ordering.

| Metric | Formula |
|---|---|
| View-to-cart conversion | Ordered add-to-cart sessions ÷ product-view sessions |
| Cart-to-checkout conversion | Ordered checkout sessions ÷ ordered add-to-cart sessions |
| Checkout completion | Ordered purchase sessions ÷ ordered checkout sessions |
| End-to-end funnel conversion | Ordered purchase sessions ÷ product-view sessions |
| Step drop-off rate | `1 − step conversion rate` |
| Step lost sessions | Prior-stage sessions − next-stage ordered sessions |

`Purchase session conversion` is reported separately as all purchasing sessions
divided by all valid sessions. It can differ from ordered funnel conversion
because instrumentation gaps or alternative paths may bypass a recorded step.

### Checkout intermediate telemetry

The strict checkout diagnostic requires `add_shipping_info` after the governed
ordered checkout start, followed by `add_payment_info`, followed by clean
purchase. It is retained as a telemetry sequence—not as the experiment primary
metric or a direct friction measure.

Aggregate diagnostic `11_checkout_telemetry_diagnostic.sql` reconciles 5,187
checkout sessions, 2,491 purchases, and 1,550 strict-sequence purchases. All
941 purchases outside the strict sequence contain shipping at or before the
governed checkout start and payment after checkout but before purchase. None
lacks shipping everywhere in the session. In addition, 92.75% of eligible
sessions contain multiple `begin_checkout` events.

The 941-session difference is therefore classified as a sequence/re-entry
artifact relative to the governed start. A real experiment requires a
dedicated, sticky `experiment_exposure` signal; repeated `begin_checkout`
events must not create multiple assignments or reset the outcome window.

Profile query `00.10` established the initial same-session baselines:

- view-to-cart conversion: 18.67%;
- cart-to-checkout conversion: 36.07%;
- checkout completion: 48.02%;
- ordered view-to-purchase conversion: 3.23%; and
- all-session clean purchase conversion: 1.12%.

Only 61.95% of clean purchasing sessions contain the full ordered path within
one session. These rates therefore diagnose same-session behavior and do not
replace a later cross-session journey sensitivity analysis.

### Product-level funnel

Profiling query `00.9` found incomplete item arrays on 37.35% of `view_item`
events and 17.46% of `begin_checkout` events. Item-bearing `view_item` and
`add_to_cart` events also averaged more than 11 item rows each. Product metrics
therefore remain secondary to the session-stage funnel; raw unnested item-row
counts are never reported as independent user actions.

Query `00.14` further showed that both view and add arrays have a median, 95th
percentile, and maximum of 12 items, with price missing on every row. These
arrays are not used to identify the focal viewed or added product.

The page-level PDP funnel instead uses `product_page_key`. An add action is
attributed to the most recent qualifying product-page view in the same session.
This last-view rule is disclosed and tested for sensitivity. Purchase-product
sales use `purchase_product_key` from canonical clean purchase events.

The primary PDP comparison requires at least 200 session-page views. The
preselected threshold retains 191 pages and 92.61% of observed session-page
exposures. Its benchmark is the unweighted 75th percentile view-to-add rate
among those eligible pages. Opportunity values then apply the governed
same-session add-to-purchase rate and clean AOV. Because one session can view
multiple pages, page opportunity values are explicitly non-additive.

## Order and value metrics

| Metric | Definition | Caveat |
|---|---|---|
| Valid orders | Distinct clean `transaction_key`, canonicalized to its earliest purchase event | Clean means one user and one consistent revenue value; ambiguous IDs are excluded |
| Gross purchase revenue | Sum of `ecommerce.purchase_revenue_in_usd` across canonical valid orders | Does not imply profit or net revenue |
| Average order value | Gross purchase revenue ÷ valid orders | Report only when denominator is non-zero |
| Orders per session | Valid orders ÷ valid sessions | Can exceed purchase-session conversion if a session has multiple orders |
| Revenue per session | Gross purchase revenue ÷ valid sessions | Primary value metric for traffic comparisons |
| Revenue per user | Gross purchase revenue ÷ pseudonymous users | Limited to the observation window |
| Units per order | Sum of `COALESCE(purchase item quantity, 1)` ÷ valid orders | 2.80% of purchase item rows require the default and are disclosed |

Primary order revenue uses the event-level ecommerce field. Item revenue is
used for product attribution and reconciliation, not as a silent replacement.
Shipping, tax, refunds, and duplicate-transaction behavior are documented after
profiling. Profit and margin are out of scope.

Profiling query `00.11` found complete, non-negative revenue on all 5,692
purchase events, but 23 events lacked a transaction ID and 5,669 valid-ID rows
mapped to only 4,452 distinct IDs. The raw event revenue of `$362,165.00` is not
used as final revenue until duplicate transactions are canonicalized by query
`00.12`.

Query `00.12` found 327 duplicated IDs, 1,217 excess event rows, a maximum of
883 rows on one ID, 16 cross-user IDs, and 16 IDs with inconsistent revenue.
The provisional earliest-event total is `$307,707.00`; conflicted IDs must be
excluded before this becomes the primary gross purchase revenue.

The targeted `00.12b` follow-up confirmed that the same 16 IDs fail both the
cross-user and inconsistent-revenue checks. The locked primary population is
4,436 clean canonical orders with `$306,678.00` gross purchase revenue and a
data-quality-adjusted AOV of `$69.13`.

Query `00.13` reconciled `$306,678.00` authoritative event revenue to
`$306,599.00` summed purchase-item revenue, a `$79.00` or 0.026% aggregate
difference. Item revenue is approved for product attribution, while event
revenue remains authoritative for total revenue and AOV.

The first live core-model build reproduced all locked order and revenue totals.
It contains 13,176 canonical clean order-item lines and 789 unique clean
purchase SKU/variant keys. These counts describe the governed purchase model,
not raw item-array reach.

## Segment dimensions

| Dimension | Primary field / rule | Labeling rule |
|---|---|---|
| Device | `device.category` | Missing and placeholder values remain explicit |
| Country | `geo.country` | Use top countries plus `Other` only after inspecting denominators |
| First-user source | Earliest observed `traffic_source.source` | Label as first-observed acquisition proxy, not session source |
| First-user medium | Earliest observed `traffic_source.medium` | Label as first-observed acquisition proxy, not session medium |
| Session source / medium | First-observed non-empty event parameters plus quality flags | Missing, conflicting, obfuscated, and self-referral sessions remain explicit |
| User tenure | `ga_session_number` rule above | New, Returning, Unknown |
| Product category | Validated `item_category` | Missing values remain Unknown |
| Page | Canonicalized host and path from `page_location` | Query strings, fragments, and trailing-slash variants require normalization |

Raw conversion rankings are not shown without denominators. Small groups are
suppressed or flagged, and the chosen minimum denominator is recorded after the
source distribution is profiled.

The analysis mart requires at least 500 sessions for a segment and at least 200
eligible sessions for the relevant ordered stage metric. Rows below either
threshold remain available for reconciliation but are flagged non-reportable.

Profile query `00.16` found Desktop, Mobile, and Tablet with no missing or
placeholder device values. Device is assigned at session grain; device-specific
user counts are not additive because pseudonymous users can appear on multiple
device categories.

Profile query `00.17` assigned all 360,129 valid sessions to a stable
first-observed country with no within-session conflicts. The United States
represents 43.92% of sessions. `Other` represents 19.66% and is retained for
reconciliation, not treated as a single actionable market; missing and
placeholder categories remain explicit outside `Other` in maintained SQL.

Profile query `00.15` found 100% `page_location` coverage on every event type,
including 386,068 `view_item` rows across 553 raw locations. Because those
locations map to only 429 page titles, page aggregation uses a canonicalized URL
path; `page_title` is a display label rather than a primary key.

Profile query `00.5` found event-parameter source and medium on 33.25% and
33.50% of event rows. Targeted query `00.18b` found that 26.47% of sessions are
missing at least one of source or medium, 17.64% contain multiple non-empty
sources, and 14.99% contain multiple non-empty mediums. Session channel is
therefore a **first-observed session attribution proxy**, not clean last-click
attribution.

Each session retains the first non-empty observed source and medium together
with separate missing, source-conflict, medium-conflict, obfuscated, and
self-referral flags. The reconciled reporting group assigns problematic
sessions to explicit quality buckets; only stable, known, non-self-referral
combinations receive named-channel treatment in the primary comparison.
Overall metrics retain every session, and first-user acquisition fields are
never used to fill missing session-channel parameters.

Profile query `00.18` found that 42,263 users, or 15.64%, carry multiple
first-user acquisition combinations in the obfuscated source. `traffic_source`
is therefore labeled a **first-observed acquisition proxy**. Obfuscated
`<Other>`, `(data deleted)`, and self-referral values remain explicit and are
not interpreted as known external channels.

## Retention metrics

Primary retention cohorts include users whose first-touch date is inside the
sample window and is supported by a New session in the same Monday-starting
cohort week.

| Metric | Definition |
|---|---|
| Cohort size | Qualified new users in cohort week |
| Week-N active users | Cohort users with at least one valid session in week N |
| Week-N activity retention | Week-N active users ÷ cohort size |
| Repeat-purchase users | Cohort users with a valid order after their first order |
| Repeat-purchase rate | Repeat-purchase users ÷ cohort purchasers |

Incomplete follow-up weeks are excluded rather than treated as zero retention.
Users first seen before the sample are left-censored; late cohorts are
right-censored. The result is labeled **observed weekly retention within the
sample**, not lifetime retention.

Profile query `00.19` found 257,304 users with first touch inside the sample,
8,417 first touched before it, and 4,433 with missing first touch. The latter
12,850 users are excluded from acquisition cohorts but remain in applicable
overall and Returning-user metrics. The partial Monday-based week containing
2020-11-01 is excluded, and the primary heatmap is limited to complete observed
Week 0 through Week 8 cells.

The live analysis initially found 255,356 candidates after removing the partial
opening week. Requiring the New-session signal in the same cohort week excludes
80 users, or 0.031%, whose first-touch metadata and observable New-session
timing do not align. The governed W0 population is therefore 255,276 users and
every retained W0 cell reconciles to 100% activity.

## Uncertainty and comparison rules

- Proportion metrics display a 95% Wilson confidence interval.
- Wilson bounds are clipped to `[0, 1]` to prevent floating-point artifacts at
  exact 0% and 100% observations.
- Differences between two independent proportions use a 95% interval suitable
  for a difference in proportions. The preselected device and tenure
  comparisons use Newcombe's Wilson-score method.
- The descriptive difference intervals treat sessions as independent.
  Repeated pseudonymous users across sessions remain a disclosed limitation.
- Every segment visualization includes its denominator.
- Exploratory multiple comparisons are labeled exploratory; isolated
  p-values are not used to declare a product decision.
- An adjusted logistic-regression analysis may supplement raw segment rates,
  but coefficients will be presented as associations rather than causal
  effects.

## Opportunity metrics

| Metric | Definition |
|---|---|
| Benchmark conversion | Conversion rate for a defensible peer group, such as same category and comparable device mix |
| Conversion gap | `benchmark conversion − observed conversion` |
| Potential incremental orders | `eligible sessions × max(0, conversion gap)` |
| Scenario revenue opportunity | `potential incremental orders × relevant average order value` |

Opportunity values are prioritization scenarios. They assume the benchmark is
reachable and do not account for engineering cost, general-equilibrium effects,
or causal uncertainty. The final recommendation considers confidence and
actionability in addition to the point estimate.

PDP sensitivity varies the minimum exposure threshold across 50, 100, 200, 500,
and 1,000 session-page views and recomputes exact unweighted P50, P75, and P90
peer benchmarks. These are labeled sensitivity results; the governed primary
rule remains at least 200 views and P75.

Checkout lift scenarios multiply the 5,187 eligible ordered checkout sessions
by an assumed absolute conversion lift. They do not use the historical
strict-intermediate telemetry path as the experiment outcome and do not claim
the assumed lift is achievable.

## A/B test metrics

The experiment is designed only after the selected intervention is specified.
For the planned simplified-checkout example:

| Item | Definition |
|---|---|
| Randomization unit | Pseudonymous user, assigned 50/50 with sticky allocation |
| Eligibility | First qualifying `begin_checkout` exposure during the test |
| Primary metric | Users completing a valid purchase within 24 hours ÷ assigned eligible users |
| Secondary metric | Gross purchase revenue ÷ assigned eligible users |
| Guardrails | Payment-error rate, refund/cancellation rate, and checkout completion time, if instrumented |
| Analysis population | Intention to treat |
| Significance level | Two-sided 5% |
| Target power | 80% |
| Historical planning proxy | 2,491 purchases after 5,187 ordered checkout sessions, or 48.02% |
| Planning MDE | Provisional +5.00 percentage points absolute, or 10.4% relative to the proxy baseline |
| Core sample | 1,569 randomized eligible users per arm; 3,138 total |
| Buffered enrollment target | 1,648 per arm; 3,296 total after a 5% operational buffer |
| Fixed-N MDE | Smallest absolute conversion lift detectable at planned N, 5% alpha, and 80% power |
| Assignment check | 50/50 sample-ratio-mismatch test before outcomes; p-value below 0.001 blocks interpretation |
| Primary interval | 95% Newcombe Wilson-score interval for treatment minus control |
| Primary test | Pooled two-proportion z-test; confidence interval remains the main uncertainty statement |
| Stopping | Fixed target sample, evaluated at the end of a full week without outcome peeking |

Simulated experiment rows use a fixed random seed and a visible
`is_simulated = TRUE` field. Simulation output demonstrates the method; it is
never merged with observed GA4 outcomes or described as a real test.

The historical baseline and traffic values are session-grain proxies. A real
launch must replace them with current unique eligible users and a user-level
24-hour baseline. At the historical checkout-session volume, the buffered
sample requires about 8.35 weeks; actual duration can only be established after
shadow assignment.

The primary simulation uses seed `20260731` and assumes a true +5.00 pp lift.
The calibration uses seed `20260801` and 20,000 A/A plus 20,000 A/B repetitions.
The simulated payment-error non-inferiority margin is +1.50 pp and remains
provisional until payments and engineering approve it.

## Data-quality gates

Downstream analysis does not begin until the following are recorded:

- Complete observed date coverage or documented missing days.
- Coverage of `user_pseudo_id`, `ga_session_id`, and `ga_session_number`.
- Valid composite-session behavior and session-start anomalies.
- Funnel event and item-array coverage.
- Missing and duplicate transaction IDs.
- Event-level versus item-level revenue reconciliation.
- Stable product key and fallback policy.
- Page-location coverage sufficient for the specificity of page claims.
- Placeholder and long-tail treatment for device, geography, and acquisition.
- Parameter value types and null-payload behavior.
- Retention left-censoring and right-censoring policy.

The executable checks are in
[`../sql/00_data_profile.sql`](../sql/00_data_profile.sql).

## Change log

| Version | Change |
|---|---|
| 0.1 | Initial pre-analysis definitions and decision rules |
| 0.2 | Confirmed complete session-ID coverage and mandatory composite session key |
| 0.3 | Confirmed session-start exceptions and timestamp-based session boundaries |
| 0.4 | Confirmed funnel event availability and preserved ordered-funnel requirement |
| 0.5 | Restricted product metrics after observing incomplete, multi-item event arrays |
| 0.6 | Required canonical transaction deduplication before revenue reporting |
| 0.7 | Excluded cross-user and inconsistent-revenue transaction IDs from primary orders |
| 0.8 | Locked 4,436 clean orders, $306,678 revenue, and $69.13 AOV |
| 0.9 | Established ordered session-funnel baselines and cross-session limitation |
| 0.10 | Confirmed full page-location coverage and required URL canonicalization |
| 0.11 | Separated page-based PDP behavior from purchase-item product reporting |
| 0.12 | Reconciled clean event revenue to item revenue within a $79 aggregate difference |
| 0.13 | Confirmed complete tenure parameters and deferred channel labels to session-grain validation |
| 0.14 | Locked New and Returning session definitions with first-visit exceptions disclosed |
| 0.15 | Locked retention eligibility, left-censoring, right-censoring, and partial-week rules |
| 0.16 | Confirmed complete device categories and session-grain comparison policy |
| 0.17 | Confirmed stable session country and non-actionable residual geography policy |
| 0.18 | Downgraded first-user acquisition to a proxy after 15.64% user inconsistency |
| 0.19 | Labeled session-channel attribution as a quality-flagged descriptive proxy |
| 0.20 | Required parameter-specific typed extraction after the full key inventory |
| 0.21 | Closed daily completeness with all dates retained and five diagnostic flags |
| 0.22 | Validated the live core model graph with all 22 hard reconciliations passing |
| 0.23 | Locked segment and PDP thresholds, page scenario rules, same-week retention validation, and analysis-layer QA |
| 0.24 | Added Newcombe difference intervals, anomaly-date and PDP benchmark sensitivity, checkout lift scenarios, and the telemetry-gated checkout experiment priority |
| 0.25 | Locked the provisional +5 pp planning MDE, buffered sample target, SRM gate, fixed-horizon analysis, and visibly seeded simulation workflow |
| 0.26 | Reconciled checkout path telemetry, reclassified the 941 strict-path gaps as sequence/re-entry artifacts, and required dedicated sticky exposure logging |
