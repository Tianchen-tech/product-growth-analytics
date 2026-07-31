# Data Profile Results

**Source:** `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`  
**Expected window:** 2020-11-01 through 2021-01-31  
**Status:** Complete — all 19 core profiling queries and both targeted
follow-ups recorded

This document separates observed query output from interpretation. A check is
marked complete only when its result has been run in BigQuery and recorded
here.

## 00.1 Table coverage and top-line volume

**Status:** Pass  
**Execution:** User-run in BigQuery Studio

| min_event_date | max_event_date | observed_calendar_days | source_tables | event_rows | pseudonymous_users | rows_missing_user_pseudo_id |
|---|---|---:|---:|---:|---:|---:|
| 2020-11-01 | 2021-01-31 | 92 | 92 | 4,295,584 | 270,154 | 0 |

### Interpretation

- The observed minimum and maximum dates match the planned analytical window.
- The inclusive window contains 92 calendar days, matching both 92 distinct
  event dates and 92 source tables. Source date coverage is complete.
- The sample contains 4,295,584 event rows and 270,154 distinct
  `user_pseudo_id` values.
- No event row is missing `user_pseudo_id`, so the event-level pseudonymous-user
  key passes its initial completeness check.

### What this does not prove

- It does not test daily event-volume anomalies; query `00.2` does that.
- It does not validate `ga_session_id`, composite sessions, or session starts.
- It does not validate funnel events, transaction IDs, revenue, item fields, or
  page metadata.
- It does not imply that 270,154 pseudonymous identifiers represent 270,154
  unique people.

## 00.2 Daily completeness

**Status:** Pass with five diagnostic volume flags retained  
**Execution:** User-run in BigQuery Studio

| Expected days | Observed event days | Missing or empty days | Total event rows | Average daily event rows |
|---:|---:|---:|---:|---:|
| 92 | 92 | 0 | 4,295,584 | 46,691.13 |

| Minimum | Minimum day | P05 | Median | P95 | Maximum | Maximum day |
|---:|---|---:|---:|---:|---:|---|
| 21,355 | 2020-12-25 | 24,114.90 | 45,148.50 | 72,240.50 | 92,199 | 2020-12-08 |

| Diagnostic flag | Days | Dates and event rows |
|---|---:|---|
| Below 50% of median | 4 | 2020-12-25 (21,355); 2020-12-26 (22,121); 2020-12-27 (22,496); 2021-01-01 (22,096) |
| Above 200% of median | 1 | 2020-12-08 (92,199) |

### Reconciliation

- All 92 expected calendar days contain events; there are no missing or empty
  days.
- Daily event rows sum exactly to the 4,295,584 source rows recorded by query
  `00.1`.
- The average, minimum, percentile, median, and maximum statistics are
  calculated across the 92 observed days.

### Interpretation

- The source window is complete at the daily-event level.
- Four dates fall below the diagnostic threshold of half the daily median.
  Their proximity to Christmas and New Year's Day is consistent with a
  possible holiday pattern, but the event data alone does not establish the
  cause.
- One date, 2020-12-08, exceeds twice the daily median. It is retained as
  observed traffic rather than automatically treated as an error.

### Modeling consequence

- All dates remain in primary traffic, funnel, conversion, and revenue
  calculations.
- Time-series outputs annotate the five diagnostic dates. If a product
  recommendation changes when they are excluded, both the full-window result
  and that sensitivity result are reported.
- No event row is removed solely because its date has unusually high or low
  volume.

### What this does not prove

- Daily row presence does not rule out intraday collection gaps.
- The profile does not identify whether unusual traffic reflects campaigns,
  seasonality, bots, outages, or real demand.
- Complete telemetry does not imply that every day represents
  business-as-usual behavior.

## 00.3 Event inventory

**Status:** Pass  
**Execution:** User-run in BigQuery Studio

| event_name | event_rows | users | sessions | event_row_share_pct |
|---|---:|---:|---:|---:|
| page_view | 1,350,428 | 269,792 | 333,683 | 31.44% |
| user_engagement | 1,058,721 | 213,004 | 275,517 | 24.65% |
| scroll | 493,072 | 138,098 | 174,140 | 11.48% |
| view_item | 386,068 | 61,252 | 77,020 | 8.99% |
| session_start | 354,970 | 267,116 | 354,857 | 8.26% |
| first_visit | 257,462 | 257,314 | 257,400 | 5.99% |
| view_promotion | 190,104 | 102,443 | 128,447 | 4.43% |
| add_to_cart | 58,543 | 12,545 | 15,188 | 1.36% |
| begin_checkout | 38,757 | 9,715 | 11,106 | 0.90% |
| select_item | 31,007 | 13,180 | 15,828 | 0.72% |
| view_search_results | 26,172 | 14,449 | 15,719 | 0.61% |
| add_shipping_info | 19,722 | 9,714 | 11,105 | 0.46% |
| add_payment_info | 13,899 | 5,751 | 6,815 | 0.32% |
| select_promotion | 9,450 | 8,164 | 8,499 | 0.22% |
| purchase | 5,692 | 4,419 | 4,848 | 0.13% |
| click | 1,446 | 1,010 | 1,239 | 0.03% |
| view_item_list | 71 | 44 | 59 | 0.00% |

### Interpretation

- The 17 event types reconcile exactly to the 4,295,584 source event rows
  recorded in query `00.1`.
- All four required funnel events are present at usable raw volume:
  `view_item`, `add_to_cart`, `begin_checkout`, and `purchase`.
- Raw event-reach sessions decline from 77,020 product-view sessions to 15,188
  add-to-cart sessions, 11,106 checkout-start sessions, and 4,848 purchase
  sessions. This makes product-view-to-cart loss an investigation candidate,
  not yet a diagnosed ordered-funnel problem.
- `begin_checkout` reaches 11,106 sessions and `add_shipping_info` reaches
  11,105, while `add_payment_info` reaches 6,815. These additional checkout
  events can support a secondary checkout diagnostic after the primary funnel
  is validated.
- Only 59 sessions contain `view_item_list`, so list-impression-to-product-view
  analysis is not sufficiently instrumented for a primary claim.
- Multiple event rows per session, especially 386,068 `view_item` rows across
  77,020 sessions, reinforce the decision to calculate funnel reach at session
  grain rather than treating event rows as users or opportunities.

### What this does not prove

- The event-level session counts are independent reach counts. They do not
  prove that a later event followed the prior stage in the same session.
- Purchase events are not yet validated against transaction IDs.
- The inventory does not show whether item arrays or page metadata are complete.
- The raw gaps do not identify causal friction or justify a product change.

## 00.4 Event parameter inventory

**Status:** Pass with mixed-type and presence-only caveats  
**Execution:** User-run in BigQuery Studio

| Parameter key | Occurrences | Event types | String values | Integer values | Double values | Float values |
|---|---:|---:|---:|---:|---:|---:|
| `ga_session_id` | 4,295,584 | 17 | 0 | 4,295,584 | 0 | 0 |
| `ga_session_number` | 4,295,584 | 17 | 0 | 4,295,584 | 0 | 0 |
| `page_location` | 4,295,584 | 17 | 4,295,584 | 0 | 0 | 0 |
| `page_title` | 4,276,104 | 17 | 4,274,636 | 0 | 0 | 0 |
| `engaged_session_event` | 4,116,237 | 17 | 0 | 4,116,237 | 0 | 0 |
| `session_engaged` | 3,996,312 | 17 | 3,682,921 | 313,391 | 0 | 0 |
| `debug_mode` | 3,682,991 | 15 | 0 | 3,682,991 | 0 | 0 |
| `page_referrer` | 3,206,512 | 17 | 1,127,778 | 0 | 0 | 0 |
| `all_data` | 2,828,174 | 15 | 0 | 0 | 0 | 0 |
| `clean_event` | 2,828,040 | 14 | 2,828,040 | 0 | 0 | 0 |
| `engagement_time_msec` | 2,431,818 | 14 | 0 | 2,431,818 | 0 | 0 |
| `medium` | 1,439,214 | 15 | 1,439,214 | 0 | 0 | 0 |
| `campaign` | 1,439,167 | 15 | 1,439,167 | 0 | 0 | 0 |
| `source` | 1,428,080 | 15 | 1,428,080 | 0 | 0 | 0 |
| `percent_scrolled` | 493,072 | 1 | 0 | 493,072 | 0 | 0 |
| `term` | 338,704 | 12 | 338,704 | 0 | 0 | 0 |
| `entrances` | 332,179 | 1 | 0 | 332,179 | 0 | 0 |
| `gclid` | 118,481 | 10 | 0 | 0 | 0 | 0 |
| `gclsrc` | 116,846 | 10 | 0 | 0 | 0 | 0 |
| `currency` | 39,313 | 3 | 39,313 | 0 | 0 | 0 |
| `search_term` | 26,172 | 1 | 26,172 | 0 | 0 | 0 |
| `unique_search_term` | 20,967 | 1 | 0 | 20,967 | 0 | 0 |
| `dclid` | 15,701 | 8 | 0 | 0 | 0 | 0 |
| `payment_type` | 5,242 | 1 | 5,242 | 0 | 0 | 0 |
| `tax` | 5,242 | 1 | 0 | 455 | 4,787 | 0 |
| `transaction_id` | 5,242 | 1 | 4,786 | 456 | 0 | 0 |
| `value` | 5,242 | 1 | 0 | 1,832 | 3,410 | 0 |
| `shipping_tier` | 4,159 | 1 | 4,159 | 0 | 0 | 0 |
| `coupon` | 3,075 | 1 | 3,075 | 0 | 0 | 0 |
| `promotion_name` | 2,270 | 1 | 2,270 | 0 | 0 | 0 |
| `link_domain` | 1,446 | 1 | 1,446 | 0 | 0 | 0 |
| `link_url` | 1,446 | 1 | 1,446 | 0 | 0 | 0 |
| `outbound` | 1,446 | 1 | 1,446 | 0 | 0 | 0 |
| `link_classes` | 6 | 1 | 6 | 0 | 0 | 0 |

### Reconciliation

- The inventory contains 34 distinct parameter keys.
- `ga_session_id`, `ga_session_number`, and `page_location` each contain a
  usable typed value on all 4,295,584 event rows.
- `page_title` occurs 4,276,104 times but contains only 4,274,636 string
  values. Thus 1,468 occurrences have no populated primitive value, and usable
  title coverage is 99.51% rather than the 99.55% key-occurrence rate.
- `page_referrer` occurs on 3,206,512 rows but contains only 1,127,778 string
  values: 74.65% key presence versus 26.25% usable-string coverage.

### Interpretation

- Parameter-key presence is not equivalent to a usable value. `all_data`,
  `gclid`, `gclsrc`, and `dclid` have occurrences but no populated primitive
  value field in this sample.
- `session_engaged` changes storage type: 3,682,921 string values and 313,391
  integer values. It cannot be extracted from one typed field without
  normalization.
- The event-parameter versions of `tax` and `value` mix integer and double
  storage. Event-parameter `transaction_id` mixes string and integer storage
  and occurs only 5,242 times, while the canonical purchase audit found 5,669
  purchase rows with a valid `ecommerce.transaction_id`.
- Source, medium, and campaign are consistently string-typed where present,
  although their session-level missingness and conflicts remain material.

### Modeling consequence

- Event staging uses parameter-specific typed extraction rather than one
  generic extractor. Numeric fields coalesce explicitly supported numeric
  types; mixed string/integer fields require a documented normalization rule.
- `ecommerce.transaction_id` and `ecommerce.purchase_revenue_in_usd` remain the
  canonical order fields. The mixed event-parameter `transaction_id` and
  `value` fields do not replace them.
- Presence-only parameters can be retained as boolean key-presence flags if
  needed, but their missing payloads are never presented as readable campaign
  identifiers.
- `page_location` remains the page key. `page_title` is a nullable display
  label, and `page_referrer` is not required for primary funnel analysis.

### What this does not prove

- It does not show the distribution or business meaning of parameter values.
- It does not test whether the same key can occur multiple times on one event.
- It does not establish engagement, ad-attribution, or campaign-performance
  metrics from key presence alone.

## 00.5 Critical parameter coverage

**Status:** Pass with value-type and channel-grain caveats  
**Execution:** User-run in BigQuery Studio

| Parameter | Occurrences | Event types | Occurrences per 100 event rows |
|---|---:|---:|---:|
| `ga_session_id` | 4,295,584 | 17 | 100.00 |
| `ga_session_number` | 4,295,584 | 17 | 100.00 |
| `medium` | 1,439,214 | 15 | 33.50 |
| `page_location` | 4,295,584 | 17 | 100.00 |
| `page_title` | 4,276,104 | 17 | 99.55 |
| `session_engaged` | 3,996,312 | 17 | 93.03 |
| `source` | 1,428,080 | 15 | 33.25 |

### Interpretation

- Both session parameters occur on every event row across all 17 event types.
  Session construction and `ga_session_number`-based tenure classification have
  complete parameter coverage.
- `page_location` contains a string value on every event row. `page_title` has
  99.55% key presence and 99.51% usable-string coverage, confirming that it is
  suitable as a nullable display label rather than a key.
- `session_engaged` occurs on 93.03% of event rows and mixes string and integer
  storage. Engagement must be normalized and rolled up to session grain before
  it becomes a metric.
- Event-parameter `source` and `medium` occur on only 33.25% and 33.50% of event
  rows. Event-row missingness cannot be interpreted as session-channel
  missingness because a valid value on one event may describe the whole
  session.

### Modeling consequence

- New versus returning uses `ga_session_number`; no first-observed fallback is
  currently required.
- `page_location` remains the page key and `page_title` remains a display label.
- Session source and medium use a quality-flagged first-observed proxy under
  the policy established by targeted query `00.18b`.
- First-user acquisition fields remain distinct from session source and are
  profiled separately by query `00.18`.
- Missing engagement, source, or medium values remain explicit until their
  session-grain coverage is known.

### What this does not prove

- On its own, it does not show the values or data types stored in these
  parameters; query `00.4` provides that inventory.
- On its own, it does not establish source/medium coverage or consistency at
  session grain; targeted query `00.18b` provides those checks.
- It does not validate agreement between `ga_session_number = 1` and
  `first_visit`; query `00.8` tests that next.

## 00.6 Session identifier coverage and collision risk

**Status:** Pass  
**Execution:** User-run in BigQuery Studio

| event_rows | rows_missing_ga_session_id | rows_missing_ga_session_id_pct | raw_ga_session_ids | composite_sessions |
|---:|---:|---:|---:|---:|
| 4,295,584 | 0 | 0.0% | 349,545 | 360,129 |

### Interpretation

- No event row is missing `ga_session_id`, so every event has both components
  required by the primary session key.
- The composite `user_pseudo_id + ga_session_id` definition produces 360,129
  sessions, compared with only 349,545 distinct raw `ga_session_id` values.
- The 10,584 excess composite user-session pairs represent a 3.03% increase
  over the raw-ID count. This proves that `ga_session_id` alone is not a safe
  globally unique session key for this dataset.
- All downstream session metrics will therefore use the composite
  `session_key`.

### What this does not prove

- It does not identify the exact number of raw session IDs shared by multiple
  users; that requires a separate collision-detail query if needed.
- It does not prove that every composite session has exactly one
  `session_start` event; query `00.7` tests that assumption.
- It does not validate event ordering or funnel completion.

## 00.7 Session-start consistency

**Status:** Pass with documented telemetry exceptions  
**Execution:** User-run in BigQuery Studio

| valid_sessions | without session_start | with one session_start | with multiple session_starts | min events | median events | p95 events | max events | avg observed minutes |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 360,129 | 5,272 | 354,752 | 105 | 1 | 5 | 39 | 1,007 | 3.39 |

### Interpretation

- The valid-session total reconciles exactly to the 360,129 composite sessions
  reported by query `00.6`.
- 354,752 sessions, or 98.51%, contain exactly one `session_start`.
- 5,272 sessions, or 1.46%, contain no `session_start`; counting only
  `session_start` would therefore undercount valid composite sessions.
- 105 sessions, or 0.03%, contain multiple `session_start` events; counting
  event rows would also introduce a smaller overcount risk.
- The median session contains 5 events and the 95th percentile contains 39.
  The maximum of 1,007 events is an extreme long-tail observation that requires
  inspection before any outlier policy is adopted.
- Session start and end timestamps will use the minimum and maximum observed
  event timestamps within the validated composite key, not the presence of a
  `session_start` event.

### What this does not prove

- It does not establish that the 1,007-event session is invalid, automated, or
  a tracking error.
- The 3.39-minute value is observed event-span duration, not GA4 engaged time
  and not a complete measure of time spent on the final page.
- It does not validate the availability of funnel events or their order.

## 00.8 New-versus-returning feasibility

**Status:** Pass  
**Execution:** User-run in BigQuery Studio

| User-tenure segment | Has `first_visit` | Sessions | Session share |
|---|---|---:|---:|
| New | true | 257,400 | 71.47% |
| New | false | 3,838 | 1.07% |
| Returning | false | 98,891 | 27.46% |

### Reconciliation

- New sessions total 261,238, or 72.54% of all valid sessions.
- Returning sessions total 98,891, or 27.46%.
- The three returned groups sum exactly to 360,129 valid sessions.
- No Unknown group and no Returning-with-`first_visit` group was returned.

### Interpretation

- `ga_session_number` provides a complete and internally coherent primary
  New/Returning segmentation.
- Among New sessions, 257,400, or 98.53%, contain `first_visit`.
- The remaining 3,838 New sessions, or 1.47%, lack `first_visit`. They remain
  New under the complete `ga_session_number = 1` definition and are disclosed
  as a telemetry exception.
- `first_visit` is a strong consistency signal but would undercount New
  sessions if used as the only definition.

### Modeling consequence

- Session comparisons use `ga_session_number = 1` for New and values greater
  than one for Returning.
- No Unknown tenure bucket is required for this source window.
- Retention cohorts additionally require a first-touch date inside the sample
  window so left-censored users are not treated as newly acquired.

### What this does not prove

- It does not validate whether each pseudonymous user has only one
  `ga_session_number = 1` session.
- It does not establish retention eligibility or available follow-up duration;
  query `00.19` tests the first-touch window next.
- It does not explain why 3,838 New sessions lack `first_visit`.

## 00.9 Ecommerce event and item coverage

**Status:** Pass for session funnel; limited for product-level funnel  
**Execution:** User-run in BigQuery Studio

| event_name | event_rows | users | sessions | events_with_items | events_without_items | item_rows_if_unnested |
|---|---:|---:|---:|---:|---:|---:|
| view_item | 386,068 | 61,252 | 77,020 | 241,876 | 144,192 | 2,748,246 |
| add_to_cart | 58,543 | 12,545 | 15,188 | 58,543 | 0 | 667,426 |
| begin_checkout | 38,757 | 9,715 | 11,106 | 31,991 | 6,766 | 77,980 |
| purchase | 5,692 | 4,419 | 4,848 | 5,690 | 2 | 16,003 |

### Interpretation

- Session-level funnel analysis remains viable because the four required event
  names and composite session keys are available independently of item arrays.
- Only 62.65% of `view_item` events contain items; 144,192 product-view events,
  or 37.35%, do not. A product-level view denominator based only on unnested
  items would have substantial missing coverage.
- `add_to_cart` has 100% item-array coverage, `begin_checkout` has 82.54%, and
  `purchase` has 99.96% coverage.
- Among events with an item array, `view_item` averages 11.36 item rows and
  `add_to_cart` averages 11.40. An unnested item row therefore cannot be
  interpreted automatically as one independent view or add action.
- The two purchase events without items are retained in order-level metrics but
  cannot support product-level attribution.
- No `refund` row was returned, consistent with the event inventory. Net
  revenue and refund-rate analysis are unavailable in this source window.

### Modeling consequence

- The primary funnel remains session-stage based.
- Product analysis is secondary and must report item-array coverage.
- Product reach will use deduplicated session-product or event-product pairs,
  never raw unnested row counts.
- Purchase revenue remains event/order grain; item rows are used only for
  documented product attribution.
- Query `00.14` will test identifier completeness and item-array cardinality
  before the final product-key policy is selected.

### What this does not prove

- It does not show whether the repeated items represent all products involved
  in an action, a broader page payload, or another implementation behavior.
- It does not validate `item_id`, `item_name`, category, price, or quantity.
- It does not establish an ordered funnel or a page-level recommendation.

## 00.11 Purchase and transaction-ID quality

**Status:** Pass for field completeness; duplicate resolution required  
**Execution:** User-run in BigQuery Studio

| purchase_event_rows | missing transaction_id | distinct valid transaction_ids | missing revenue | negative revenue | raw event revenue |
|---:|---:|---:|---:|---:|---:|
| 5,692 | 23 | 4,452 | 0 | 0 | $362,165.00 |

### Interpretation

- All 5,692 purchase events contain revenue and none has negative revenue.
- 23 purchase rows, or 0.40%, have no valid `transaction_id`. They are invalid
  for the primary order count and cannot be deduplicated reliably.
- The remaining 5,669 purchase rows map to only 4,452 distinct valid
  transaction IDs. There are 1,217 event rows above the unique-order count, so
  duplicate transaction behavior is material.
- The raw `$362,165.00` is an event-row sum. It can contain both duplicate
  transaction revenue and revenue attached to the 23 unidentified purchases;
  it is not the final gross purchase revenue.

### Modeling consequence

- Primary orders require a non-empty transaction ID.
- `fct_orders` will contain one canonical row per valid transaction ID.
- Query `00.12` must determine duplicate concentration, cross-user conflicts,
  inconsistent revenue values, and the canonical revenue total before AOV or
  revenue metrics are calculated.
- Unidentified purchases remain a separately reported telemetry-quality bucket
  and are excluded from primary order and revenue metrics.

### What this does not prove

- It does not show how many transaction IDs are duplicated or how many times.
- It does not establish whether duplicate rows have consistent users or revenue.
- It does not provide a deduplicated revenue value.

## 00.12 Duplicate transactions

**Status:** Needs targeted conflict resolution  
**Execution:** User-run in BigQuery Studio

| purchase events | missing-ID rows | missing-ID revenue | valid-ID rows | distinct transaction IDs | duplicated IDs | rows in duplicated IDs | excess rows | max rows per ID |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 5,692 | 23 | $1,328.00 | 5,669 | 4,452 | 327 | 1,544 | 1,217 | 883 |

| cross-user IDs | inconsistent-revenue IDs | raw valid-ID revenue | provisional canonical revenue | excess duplicate revenue |
|---:|---:|---:|---:|---:|
| 16 | 16 | $360,837.00 | $307,707.00 | $53,130.00 |

### Reconciliation

- `$360,837.00` valid-ID revenue plus `$1,328.00` missing-ID revenue equals
  the `$362,165.00` raw purchase-event revenue from query `00.11`.
- The 1,544 rows belonging to duplicated IDs contain 1,217 rows beyond one row
  per transaction, exactly reconciling 5,669 valid-ID rows to 4,452 distinct
  IDs.
- Deduplicating each valid ID to its earliest event removes `$53,130.00`, or
  14.72% of raw valid-ID revenue.

### Interpretation

- Most transaction IDs occur once, but 327 IDs are duplicated.
- A maximum of 883 purchase rows on one ID is an extreme conflict and rules out
  treating every non-empty ID as automatically valid.
- Sixteen transaction IDs span multiple users and sixteen contain inconsistent
  revenue values. The current output does not show how those sets overlap.
- The `$307,707.00` canonical total is provisional because it still retains one
  arbitrary earliest observation for conflicted IDs.

### Modeling consequence

- Consistent repeats for one user and one revenue value can be canonicalized to
  the earliest purchase event.
- Transaction IDs spanning multiple users or multiple revenue values are
  classified as ambiguous and excluded from primary orders and revenue.
- The final clean order count and clean revenue require the targeted
  `00_12b_transaction_conflict_breakdown.sql` result.
- The ordered funnel will use only the canonical event for a clean transaction,
  preventing one duplicated order from appearing in multiple purchase sessions.

### What this does not prove

- It does not identify whether the 883-row transaction is a placeholder,
  implementation error, or another obfuscation artifact.
- It does not provide the final clean revenue after ambiguous IDs are excluded.
- It does not validate item-level versus event-level revenue.

## 00.12b Transaction conflict breakdown

**Status:** Pass — primary order population locked  
**Execution:** User-run in BigQuery Studio

| transaction quality class | transaction IDs | purchase rows | excess rows | max rows per ID | max users per ID | placeholder-like IDs | raw revenue | canonical revenue | duplicate difference |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| clean | 4,436 | 4,753 | 317 | 4 | 1 | 0 | $327,984.00 | $306,678.00 | $21,306.00 |
| cross-user and inconsistent revenue | 16 | 916 | 900 | 883 | 767 | 1 | $32,853.00 | $1,029.00 | $31,824.00 |

No `cross_user_only` or `inconsistent_revenue_only` row was returned. All 16
conflicted IDs fail both checks simultaneously.

### Final primary order policy

- **Primary valid orders:** 4,436 clean transaction IDs.
- **Primary gross purchase revenue:** `$306,678.00`.
- **Data-quality-adjusted AOV:** `$69.13`.
- Repeated clean transactions have at most four event rows and are
  canonicalized to their earliest purchase event.
- The 16 cross-user, inconsistent-revenue IDs are excluded entirely, including
  their provisional `$1,029.00` canonical value.
- The 23 missing-ID purchase rows and their `$1,328.00` revenue are excluded
  from primary order and revenue metrics.

### Complete event reconciliation

```text
5,692 raw purchase events
= 4,436 canonical clean orders
+   317 excess clean duplicate rows
+   916 conflicted-ID rows
+    23 missing-ID rows
```

### Complete revenue reconciliation

```text
$362,165 raw purchase-event revenue
= $306,678 canonical clean-order revenue
+  $21,306 excess clean-duplicate revenue
+  $32,853 conflicted-ID revenue
+   $1,328 missing-ID revenue
```

The excluded or duplicate revenue totals `$55,487.00`. This is a
data-quality adjustment, not a refund, cost, or business loss.

### Interpretation

- The extreme duplicate behavior is isolated within the ambiguous transaction
  class rather than the clean class.
- At least one conflict ID is placeholder-like. The aggregate output does not
  prove that it is specifically the 883-row or 767-user ID.
- Clean-order metrics can now be used in the ordered funnel, AOV, and revenue
  calculations under the documented policy.

### What this does not prove

- It does not establish why the source generated the conflicting IDs.
- It does not validate item-level revenue attribution.
- It does not establish that clean purchases followed the required funnel
  sequence; query `00.10` tests that next.

## 00.10 Preliminary ordered session funnel

**Status:** Pass with cross-session journey limitation  
**Execution:** User-run in BigQuery Studio

| Stage | Sessions | Step conversion | Step drop-off | Lost sessions |
|---|---:|---:|---:|---:|
| All valid sessions | 360,129 | — | — | — |
| `view_item` | 77,020 | 21.39% of all sessions | — | — |
| `add_to_cart` after `view_item` | 14,380 | 18.67% | 81.33% | 62,640 |
| `begin_checkout` after `add_to_cart` | 5,187 | 36.07% | 63.93% | 9,193 |
| Clean purchase after `begin_checkout` | 2,491 | 48.02% | 51.98% | 2,696 |

Additional clean purchase reach:

| Metric | Value |
|---|---:|
| Clean purchase sessions regardless of path | 4,021 |
| All-session clean purchase rate | 1.12% |
| Ordered view-to-purchase conversion | 3.23% |
| Full same-session path share of clean purchase sessions | 61.95% |
| Clean purchase sessions without the full same-session path | 1,530 |
| Clean orders per clean purchasing session | 1.103 |

### Interpretation

- The largest absolute same-session loss occurs between product view and add to
  cart: 62,640 sessions do not reach an ordered add event.
- The observed view-to-cart conversion is 18.67%, making the product-detail
  stage the leading investigation candidate.
- Checkout completion is 48.02%, so checkout remains a material friction
  candidate, but its observed absolute loss is smaller at 2,696 sessions.
- Only 2,491 of 4,021 clean purchasing sessions contain the full required
  same-session sequence. The 1,530-session difference may reflect cross-session
  shopping, a persisted cart, an alternative path, or missing/out-of-order
  telemetry; this query cannot distinguish those explanations.
- The 4,436 clean orders occur in 4,021 purchasing sessions, confirming that
  some sessions contain more than one canonical order.

### Decision consequence

- Product detail/add-to-cart is promoted to the leading candidate for deeper
  page, product, and segment analysis.
- A simplified-checkout experiment remains a valid secondary design exercise,
  not yet the evidence-backed primary recommendation.
- Page metadata, item identifiers, segment mix, and a cross-session sensitivity
  analysis are required before the final product decision.

### What this does not prove

- It does not prove that page design caused the view-to-cart loss.
- It does not treat every prior-stage session as recoverable.
- It does not capture valid journeys whose steps occur across multiple sessions.
- It does not establish a specific product page URL or product category to
  prioritize.

## 00.13 Event-level versus item-level revenue

**Status:** Pass — aggregate revenue reconciled  
**Execution:** User-run in BigQuery Studio

| clean orders | missing event revenue | missing item revenue | matching orders | event above items | items above event | event revenue | item revenue | difference |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 4,436 | 0 | 0 | 3,606 | 446 | 384 | $306,678.00 | $306,599.00 | $79.00 |

### Interpretation

- The query returns exactly the locked 4,436 clean canonical orders.
- Event revenue and summed item revenue are complete for every clean order.
- Aggregate item revenue is only `$79.00` below event revenue, a 0.026%
  difference relative to event revenue.
- Revenue matches within one cent for 3,606 orders, or 81.29%.
- The remaining 830 orders, or 18.71%, contain order-level differences: event
  revenue is higher for 446 and item revenue is higher for 384.
- The positive and negative order-level differences mostly offset in aggregate;
  close totals do not imply that the two fields are interchangeable per order.

### Modeling consequence

- `ecommerce.purchase_revenue_in_usd` on canonical clean orders is the
  authoritative total-revenue field.
- Summed purchase item revenue is sufficiently reconciled for product and
  category revenue attribution.
- Order-level item revenue will not silently overwrite event revenue.
- The `$79.00` aggregate difference is disclosed in the data-quality notes and
  not treated as business loss, refund, or profit adjustment.

### What this does not prove

- It does not explain individual-order differences.
- It does not restore price fields missing from pre-purchase events.
- It does not establish product profitability or net revenue.

## 00.14 Item field quality

**Status:** Pass for purchase-item analysis; fail for behavioral item funnel  
**Execution:** User-run in BigQuery Studio

| event | item-bearing events | item rows | avg items | median | p95 | max | missing item ID | missing name | missing category | missing price | missing quantity | distinct IDs | distinct names |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| view_item | 241,876 | 2,748,246 | 11.36 | 12 | 12 | 12 | 0 | 0 | 8,594 | 2,748,246 | 2,729,121 | 427 | 422 |
| add_to_cart | 58,543 | 667,426 | 11.40 | 12 | 12 | 12 | 0 | 0 | 1,825 | 667,426 | 630,166 | 806 | 414 |
| begin_checkout | 31,991 | 77,980 | 2.44 | 1 | 7 | 31 | 0 | 0 | 3,297 | 77,980 | 1,933 | 797 | 392 |
| purchase | 5,690 | 16,003 | 2.81 | 2 | 8 | 30 | 0 | 0 | 230 | 448 | 448 | 810 | 396 |

### Interpretation

- Item IDs and names are complete on every unnested item row.
- `view_item` and `add_to_cart` arrays behave like systematic fixed-length
  payloads: both have a median, 95th percentile, and maximum of 12 items.
  Those rows cannot be interpreted as the single focal product the user viewed
  or added.
- Price is missing on 100% of view, add, and checkout item rows. Quantity is
  missing on 99.30% of view rows and 94.42% of add rows. Pre-purchase price or
  quantity analysis is therefore unsupported.
- Purchase arrays have plausible basket-shaped cardinality: median 2, 95th
  percentile 8, and maximum 30. Purchase item price and quantity are each
  missing on 2.80% of rows, and category is missing on 1.44%.
- Purchase contains 810 item IDs but 396 item names, indicating that IDs are
  closer to SKU or variant grain while names are closer to product-family
  labels.

### Modeling consequence

- Raw item arrays will not be used to connect `view_item` to `add_to_cart`.
- The PDP funnel will use canonical page URL as the exposure key and attribute
  an add action to the most recent qualifying product-page view in the same
  session. This is a documented last-view attribution rule, not exact product
  identity.
- Purchase-product reporting uses `item_id` as the SKU-level key and
  `item_name` as the display/product-family label.
- Product sales and basket analysis use only canonical clean purchase events.
- Missing purchase quantity is provisionally treated as one and disclosed;
  item-revenue reconciliation is tested by query `00.13`.
- Price sensitivity, price elasticity, and pre-purchase product-price
  comparisons are out of scope.

### What this does not prove

- It does not reveal why a view or add event carries a 12-item payload.
- It does not establish a one-to-one mapping among URL, item ID, and item name.
- It does not yet reconcile canonical event revenue to item revenue.

## 00.15 Page metadata feasibility

**Status:** Pass — page-level analysis is feasible  
**Execution:** User-run in BigQuery Studio

| event_name | event_rows | rows with location | rows with title | distinct locations | distinct titles | location coverage |
|---|---:|---:|---:|---:|---:|---:|
| page_view | 1,350,428 | 1,350,428 | 1,343,567 | 2,515 | 500 | 100.00% |
| user_engagement | 1,058,721 | 1,058,721 | 1,054,755 | 2,242 | 500 | 100.00% |
| scroll | 493,072 | 493,072 | 490,818 | 1,822 | 488 | 100.00% |
| view_item | 386,068 | 386,068 | 384,487 | 553 | 429 | 100.00% |
| session_start | 354,970 | 354,970 | 351,637 | 1,243 | 468 | 100.00% |
| first_visit | 257,462 | 257,462 | 254,568 | 979 | 422 | 100.00% |
| view_promotion | 190,104 | 190,104 | 190,046 | 23 | 10 | 100.00% |
| add_to_cart | 58,543 | 58,543 | 58,543 | 39 | 39 | 100.00% |
| begin_checkout | 38,757 | 38,757 | 38,757 | 4 | 3 | 100.00% |
| select_item | 31,007 | 31,007 | 31,007 | 44 | 44 | 100.00% |
| view_search_results | 26,172 | 26,172 | 26,172 | 3 | 3 | 100.00% |
| add_shipping_info | 19,722 | 19,722 | 19,722 | 3 | 2 | 100.00% |
| add_payment_info | 13,899 | 13,899 | 13,899 | 1 | 1 | 100.00% |
| select_promotion | 9,450 | 9,450 | 9,449 | 8 | 4 | 100.00% |
| purchase | 5,692 | 5,692 | 5,692 | 3 | 3 | 100.00% |
| click | 1,446 | 1,446 | 1,446 | 63 | 59 | 100.00% |
| view_item_list | 71 | 71 | 71 | 10 | 10 | 100.00% |

### Interpretation

- Every event row contains `page_location`, including every `view_item`,
  `add_to_cart`, `begin_checkout`, and `purchase` event.
- Page-level and page-template analysis are therefore technically feasible.
- `page_location` is the primary page identifier; `page_title` is incomplete
  on some high-volume events and is used only as a display label.
- The 553 raw `view_item` locations map to 429 titles. This indicates URL
  fragmentation or many-to-one page labeling that must be canonicalized before
  pages are ranked.
- `add_to_cart` appears on 39 locations, `begin_checkout` on four, and purchase
  on three. These counts support stage-specific path inspection but do not by
  themselves establish distinct product experiences.

### Modeling consequence

- Page URLs will be parsed into host and path and normalized for query strings,
  fragments, and trailing-slash variants before aggregation.
- Raw URL counts will not be labeled as counts of distinct products.
- Product-page opportunity analysis will require minimum session denominators
  and, where possible, validated item identifiers.
- Only aggregated page metrics will be published; user-level browsing paths
  remain out of the public repository and dashboard.

### What this does not prove

- It does not show how much of the 553-location count is caused by query
  parameters, localization, product variants, or genuinely different pages.
- It does not identify which product page has the lowest reliable conversion.
- It does not establish that `add_to_cart` occurred for the product represented
  by an earlier page without item-key validation.

## 00.16 Device distribution and placeholders

**Status:** Pass  
**Execution:** User-run in BigQuery Studio

| Device category | Event rows | Users | Event-row share |
|---|---:|---:|---:|
| Desktop | 2,498,330 | 158,917 | 58.16% |
| Mobile | 1,704,069 | 109,195 | 39.67% |
| Tablet | 93,185 | 6,250 | 2.17% |

### Interpretation

- Device category has no missing or placeholder bucket.
- All three device groups have non-trivial observed volume; Tablet is smaller
  but is not automatically merged before its session and purchase denominators
  are known.
- The device-specific user counts sum to 274,362, exceeding the 270,154 total
  pseudonymous users by 4,208 memberships. Users can appear in more than one
  device category, so device user groups are not mutually exclusive.
- The current shares are event-row shares, not session shares or conversion
  denominators.

### Modeling consequence

- Device conversion comparisons use a session-level device assignment.
- A user's activity is not forced into a single lifetime device category.
- Tablet remains a separate exploratory segment and is combined only if the
  downstream eligible-session denominator is too small for a stable interval.
- Every device comparison displays session denominators and confidence
  intervals.

### What this does not prove

- It does not show whether device category is perfectly stable within a
  session; the session model must test that consistency.
- It does not show device-specific funnel conversion or revenue.
- It does not establish that device causes any observed conversion difference.

## 00.17 Country distribution and placeholders

**Status:** Pass with residual-bucket caveat  
**Execution:** User-run in BigQuery Studio

| Country group | Sessions | Users | Multi-country sessions | Session share |
|---|---:|---:|---:|---:|
| United States | 158,155 | 118,493 | 0 | 43.92% |
| Other | 70,804 | 52,927 | 0 | 19.66% |
| India | 33,769 | 25,367 | 0 | 9.38% |
| Canada | 26,824 | 20,268 | 0 | 7.45% |
| United Kingdom | 11,327 | 8,527 | 0 | 3.15% |
| France | 7,162 | 5,381 | 0 | 1.99% |
| Spain | 6,667 | 5,044 | 0 | 1.85% |
| Germany | 6,393 | 4,866 | 0 | 1.78% |
| China | 6,258 | 4,620 | 0 | 1.74% |
| Taiwan | 6,057 | 4,568 | 0 | 1.68% |
| Italy | 4,998 | 3,750 | 0 | 1.39% |
| Singapore | 4,741 | 3,597 | 0 | 1.32% |
| Japan | 4,732 | 3,547 | 0 | 1.31% |
| South Korea | 4,523 | 3,424 | 0 | 1.26% |
| Netherlands | 4,073 | 3,042 | 0 | 1.13% |
| Turkey | 3,646 | 2,733 | 0 | 1.01% |

### Reconciliation

- Country groups sum exactly to all 360,129 valid sessions.
- Reported user memberships sum exactly to all 270,154 pseudonymous users.
- Rounded session shares sum to 100.02%; the 0.02-point difference is rounding.

### Interpretation

- No valid session contains multiple country values, so first-observed country
  is a stable session assignment in this sample.
- The United States represents 43.92% of sessions. India and Canada are the next
  largest named markets at 9.38% and 7.45%.
- `Other` contains 19.66% of sessions and is heterogeneous. It is useful for
  reconciliation and display but not a single actionable market.
- Every named country shown has at least 3,646 sessions, providing adequate
  traffic for initial conversion estimates; purchase denominators and
  confidence intervals still determine final inclusion.

### Modeling consequence

- Country conversion uses session country and keeps the Top-N countries plus a
  reconciliation `Other` bucket.
- Product recommendations are not made for `Other` as though it were one
  geography.
- The maintained SQL now preserves `[missing]` and `[placeholder]` separately
  even when either falls below the Top-15 rank.
- Country comparisons report denominators and confidence intervals and remain
  observational.

### What this does not prove

- The executed Top-15 result may have placed a small missing or placeholder
  category inside `Other`; the downstream session mart must expose those
  buckets explicitly.
- Zero within-session country conflicts does not rule out country changes
  across different sessions that both fall within the aggregated `Other`
  bucket.
- It does not show country-specific conversion or revenue.

## 00.18 First-user acquisition source coverage

**Status:** Pass for descriptive proxy; fail as an immutable user attribute  
**Execution:** User-run in BigQuery Studio

| First-user source | Medium | Campaign | Users | Sessions | Users with inconsistent acquisition | User share |
|---|---|---|---:|---:|---:|---:|
| google | organic | (organic) | 93,041 | 122,625 | 13,451 | 34.44% |
| (direct) | (none) | (direct) | 64,109 | 85,643 | 9,619 | 23.73% |
| `<Other>` | `<Other>` | `<Other>` | 47,100 | 61,005 | 7,459 | 17.43% |
| `<Other>` | referral | (referral) | 25,255 | 33,878 | 4,147 | 9.35% |
| shop.googlemerchandisestore.com | referral | (referral) | 14,763 | 20,567 | 2,602 | 5.46% |
| google | cpc | `<Other>` | 14,282 | 18,722 | 2,407 | 5.29% |
| `<Other>` | organic | (organic) | 8,701 | 11,494 | 1,453 | 3.22% |
| (data deleted) | (data deleted) | (data deleted) | 2,782 | 5,982 | 1,090 | 1.03% |
| (data deleted) | (data deleted) | `<Other>` | 66 | 127 | 20 | 0.02% |
| `<Other>` | (data deleted) | (data deleted) | 52 | 83 | 15 | 0.02% |
| (data deleted) | referral | (referral) | 1 | 1 | 0 | 0.00% |
| `<Other>` | referral | `<Other>` | 1 | 1 | 0 | 0.00% |
| google | `<Other>` | `<Other>` | 1 | 1 | 0 | 0.00% |

### Reconciliation

- The rows sum exactly to all 270,154 pseudonymous users and all 360,129 valid
  sessions.
- A total of 42,263 users, or 15.64%, have more than one first-user acquisition
  combination across their events.

### Interpretation

- Google organic is the largest first-observed acquisition proxy at 34.44% of
  users, followed by Direct at 23.73%.
- Obfuscated `<Other>` combinations represent a large share and cannot be
  interpreted as a specific marketing source.
- `shop.googlemerchandisestore.com / referral` is a self-referral pattern. It is
  retained as observed telemetry but is not interpreted automatically as an
  external acquisition channel.
- First-user acquisition fields are not immutable within this obfuscated sample
  for 15.64% of users, despite their intended semantics.

### Modeling consequence

- First-user acquisition is labeled **first-observed acquisition proxy** and
  uses the earliest observed combination per user.
- `<Other>`, `(data deleted)`, and self-referral remain explicit quality
  categories and are not relabeled as known marketing channels.
- Primary channel conversion requires a separate session-level source/medium
  profile from event parameters.
- Acquisition comparisons remain observational and include denominators and
  confidence intervals.

### What this does not prove

- It does not establish the true historical acquisition channel for users with
  inconsistent or obfuscated values.
- It does not provide session-channel attribution.
- It does not establish marketing incrementality or return on ad spend.

## 00.18b Session source/medium quality

**Status:** Pass for a quality-flagged descriptive proxy; fail as clean
last-click attribution  
**Execution:** User-run in BigQuery Studio

| Session source | Session medium | Sessions | Users | Sessions with multiple sources | Sessions with multiple mediums | Session share |
|---|---|---:|---:|---:|---:|---:|
| google | organic | 95,244 | 84,904 | 27,922 | 27,991 | 26.45% |
| `[missing]` | `[missing]` | 94,553 | 82,026 | 0 | 0 | 26.26% |
| shop.googlemerchandisestore.com | referral | 52,397 | 39,164 | 1,927 | 874 | 14.55% |
| (direct) | (none) | 37,786 | 36,230 | 9,495 | 9,612 | 10.49% |
| `<Other>` | `<Other>` | 25,327 | 25,095 | 6,473 | 6,572 | 7.03% |
| `<Other>` | referral | 20,381 | 18,217 | 8,061 | 1,405 | 5.66% |
| google | cpc | 7,672 | 7,647 | 1,931 | 1,968 | 2.13% |
| (data deleted) | (data deleted) | 6,343 | 5,705 | 1,241 | 1,259 | 1.76% |
| `<Other>` | organic | 4,845 | 4,831 | 1,231 | 1,276 | 1.35% |
| googlemerchandisestore.com | referral | 4,095 | 3,556 | 2,171 | 435 | 1.14% |
| Other | Other | 3,855 | 3,381 | 1,700 | 758 | 1.07% |
| analytics.google.com | referral | 3,412 | 2,616 | 598 | 223 | 0.95% |
| Partners | affiliate | 1,329 | 1,037 | 410 | 410 | 0.37% |
| shop.googlemerchandisestore.com | organic | 1,086 | 1,050 | 108 | 1,086 | 0.30% |
| creatoracademy.youtube.com | referral | 886 | 828 | 210 | 45 | 0.25% |
| `[missing]` | organic | 756 | 691 | 0 | 0 | 0.21% |
| `<Other>` | (data deleted) | 100 | 100 | 28 | 29 | 0.03% |
| (data deleted) | organic | 50 | 48 | 34 | 50 | 0.01% |
| `[missing]` | referral | 9 | 9 | 0 | 0 | 0.00% |
| (data deleted) | referral | 1 | 1 | 0 | 0 | 0.00% |
| Partners | `[missing]` | 1 | 1 | 0 | 0 | 0.00% |
| google | `<Other>` | 1 | 1 | 0 | 0 | 0.00% |

### Reconciliation

- The rows sum exactly to all 360,129 valid sessions.
- The grouped user counts sum to 317,138, exceeding 270,154 distinct users
  because users can visit through multiple session-channel groups. Channel user
  counts are therefore not additive.
- A total of 95,319 sessions, or 26.47%, are missing at least one of source or
  medium. Of these, 94,553 are missing both.
- A total of 63,540 sessions, or 17.64%, contain multiple non-empty sources.
  Separately, 53,993 sessions, or 14.99%, contain multiple non-empty mediums.
  This aggregated output does not identify their overlap, so the number of
  sessions with either type of conflict is not inferred by adding them.
- The two observed store-domain referral rows total 56,492 sessions, or 15.69%
  of all sessions.

### Interpretation

- Google Organic is the largest first-observed session combination at 26.45%,
  but 29.32% of sessions assigned to that row contain multiple source values.
  The label is therefore not clean attribution.
- Direct represents 10.49% of sessions, and 25.13% of those sessions contain
  multiple source values.
- Missing attribution is nearly as large as Google Organic, while obfuscated
  values and self-referrals account for additional material volume.
- The event parameters support descriptive session-channel diagnostics, but not
  trustworthy last-click attribution or marketing-incrementality claims.

### Modeling consequence

- Each session keeps the first-observed non-empty source and medium as an
  attribution proxy plus separate `source_conflict`, `medium_conflict`,
  `missing_channel`, `obfuscated_channel`, and `self_referral` flags.
- The reconciled channel reporting layer uses explicit Missing, Conflicting,
  Obfuscated, and Self-referral quality groups. Only stable, known,
  non-self-referral combinations receive a named channel in the primary
  channel comparison.
- Overall traffic and conversion metrics retain every valid session. A
  sensitivity view may show first-observed labels for all sessions, but must
  expose the quality flags and cannot be interpreted causally.
- First-user acquisition fields are not used to fill missing session-channel
  parameters.

### What this does not prove

- It does not identify which observed source or medium is the true acquisition
  or last-click value in a conflicting session.
- It does not measure the overlap between source-conflict and medium-conflict
  sessions; that union is computed directly in the session model.
- It does not show channel-specific funnel conversion, revenue, or causal lift.

## 00.19 Retention window feasibility

**Status:** Pass — cohort population is sufficient  
**Execution:** User-run in BigQuery Studio

| First-touch window | Users | Earliest first-observed date | Latest first-observed date | User share |
|---|---:|---|---|---:|
| Inside sample | 257,304 | 2020-11-01 | 2021-01-31 | 95.24% |
| Before sample | 8,417 | 2020-11-01 | 2021-01-31 | 3.12% |
| Missing first touch | 4,433 | 2020-11-01 | 2021-01-31 | 1.64% |

### Reconciliation

- The three groups sum exactly to all 270,154 pseudonymous users from query
  `00.1`.
- The 8,417 pre-sample and 4,433 missing-first-touch users total 12,850, or
  4.76% of users.

### Interpretation

- The 257,304 users whose first touch falls inside the source window provide a
  sufficiently large acquisition-cohort population.
- Users first touched before 2020-11-01 are left-censored and cannot be treated
  as newly acquired in the sample.
- Users without first-touch timestamps cannot be assigned a defensible
  acquisition week.
- Every group includes users first observed across the full sample window, so
  first-observed event date cannot replace first-touch date.

### Modeling consequence

- Primary retention cohorts require a first-touch date inside the sample and a
  consistent New-user signal.
- The 12,850 pre-sample or missing-first-touch users are excluded from cohort
  retention but remain eligible for overall traffic and Returning-user
  analyses.
- The partial week containing Sunday 2020-11-01 is excluded from primary
  Monday-based weekly cohort comparisons.
- Late cohorts and incomplete Week-N cells are right-censored rather than
  recorded as zero retention.
- The primary cohort heatmap will report complete observed weeks only, with a
  planned Week 0 through Week 8 horizon.

### What this does not prove

- It does not calculate retention rates.
- It does not validate the exact intersection between inside-sample first touch
  and `ga_session_number = 1`; the cohort mart must test that reconciliation.
- It does not measure customer lifetime beyond 2021-01-31.

## Profiling checklist

- [x] `00.1` Table coverage and top-line volume
- [x] `00.2` Daily completeness
- [x] `00.3` Event inventory
- [x] `00.4` Event parameter inventory
- [x] `00.5` Critical parameter coverage
- [x] `00.6` Session identifier coverage and collision risk
- [x] `00.7` Session-start consistency
- [x] `00.8` New-versus-returning feasibility
- [x] `00.9` Ecommerce event and item coverage
- [x] `00.10` Preliminary ordered session funnel
- [x] `00.11` Purchase and transaction-ID quality
- [x] `00.12` Duplicate transactions
- [x] Targeted follow-up: `00_12b_transaction_conflict_breakdown.sql`
- [x] `00.13` Event-level versus item-level revenue
- [x] `00.14` Item field quality
- [x] `00.15` Page metadata feasibility
- [x] `00.16` Device distribution and placeholders
- [x] `00.17` Country distribution and placeholders
- [x] `00.18` First-user acquisition source coverage
- [x] Targeted follow-up: `00_18b_session_channel_profile.sql`
- [x] `00.19` Retention window feasibility

## Profiling closeout

All planned source-profile queries have been executed and reconciled. The
results define explicit downstream policies for composite sessions, ordered
funnels, canonical clean orders, page and item grains, parameter typing,
channel-quality flags, cohort censoring, and daily volume anomalies.

This closeout authorizes construction of the staging, fact, dimension, and
analytical mart SQL. It does not authorize a product recommendation before
those models and their reconciliations are complete.
