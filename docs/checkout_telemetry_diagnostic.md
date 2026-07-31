# Checkout Telemetry Diagnostic

**Execution date:** 2026-07-31  
**Query:** `sql/analysis/11_checkout_telemetry_diagnostic.sql`  
**Aggregate export:** `20260731T052813Z`  
**Status:** Pass — all rows reconcile to the governed checkout mart

## Question

The strict checkout mart contains 1,550 purchases after recorded shipping and
payment, while the any-intermediate ordered definition contains 2,491
purchases. This diagnostic asks whether the 941-session difference represents
missing telemetry, skipped product steps, or event ordering around repeated
checkout entry.

The query uses session-scoped temporary tables to avoid BigQuery's nested-view
planning limit. Session keys are used only inside the query; the final 184-row
output is aggregate.

## Reconciliation

| Population | Diagnostic | Governed mart | Status |
|---|---:|---:|---|
| Ordered checkout sessions | 5,187 | 5,187 | Pass |
| Purchases after checkout | 2,491 | 2,491 | Pass |
| Strict shipping → payment → purchase | 1,550 | 1,550 | Pass |

Every exported row carries `reconciliation_status = PASS`.

## Exclusive path results

| Path after governed checkout start | Sessions | Share of checkout sessions |
|---|---:|---:|
| Purchase with full shipping → payment sequence | 1,550 | 29.88% |
| Purchase with payment in-window but shipping outside the strict window | 940 | 18.12% |
| Purchase with both intermediates in a non-strict order | 1 | 0.02% |
| No purchase with full shipping → payment sequence | 774 | 14.92% |
| No purchase with shipping only | 586 | 11.30% |
| No purchase with payment only | 420 | 8.10% |
| No purchase with neither intermediate in-window | 887 | 17.10% |
| No purchase with both intermediates in a non-strict order | 29 | 0.56% |

No purchasing session falls into a genuinely shipping-only or
no-intermediate-event path.

## What explains the 941 purchase gaps?

Within the 941 purchases missing the full strict sequence:

| Context check | Sessions | Rate |
|---|---:|---:|
| Shipping at or before governed checkout start | 941 | 100.00% |
| Payment after checkout and before purchase | 941 | 100.00% |
| No shipping event anywhere in the session | 0 | 0.00% |
| Shipping at or after purchase | 38 | 4.04% |

The gap is therefore not broad absence of shipping or payment telemetry. It is
created by event order relative to the selected checkout start.

Supporting quality signals:

- 4,811 of 5,187 checkout sessions, or 92.75%, contain multiple
  `begin_checkout` events;
- 4,038 sessions, or 77.85%, contain shipping at or before the governed
  checkout start;
- 24.48% contain multiple in-window shipping events;
- 34.24% contain multiple in-window payment events; and
- only 0.58% contain both intermediate event types without any valid
  shipping-to-payment ordering.

The data cannot distinguish deliberate user re-entry from duplicate firing in
the source implementation, so the result is labeled a
**sequence/re-entry artifact**, not a confirmed instrumentation bug.

## Segment concentration

The purchase telemetry-gap rate is similar across the two major device groups:

| Comparison | Gap rate |
|---|---:|
| Desktop | 37.40% |
| Mobile | 38.07% |
| Tablet | 41.82% |

Mobile minus Desktop is +0.67 pp with a descriptive 95% Newcombe interval of
−3.21 to +4.58 pp. The gap is not concentrated on mobile.

New sessions have a 38.17% gap rate and Returning sessions 37.52%.
Returning minus New is −0.65 pp with a descriptive 95% interval of −4.55 to
+3.22 pp. The gap is not concentrated by tenure.

Across reportable calendar weeks, the gap remains present and ranges from
21.69% to 46.31%. The low-volume flagged-date purchase denominator is only 45
and remains below the preselected reporting threshold, so it is not used for a
decision.

## Metric and experiment implications

1. Keep clean purchase after ordered checkout as the historical completion
   metric; do not require the strict intermediate sequence.
2. Do not label the 941-session strict-path difference as checkout abandonment.
3. Use a dedicated, sticky experiment-exposure event at first eligibility.
   Repeated `begin_checkout` events must not re-randomize users or restart the
   24-hour outcome window.
4. Use shipping and payment events for diagnostic monitoring only.
5. Real launch readiness still requires payment-error, refund/cancellation,
   checkout-duration, assignment, and current unique-user throughput telemetry.

This closes the historical path-ambiguity question without claiming that the
simplified checkout has a causal effect.
