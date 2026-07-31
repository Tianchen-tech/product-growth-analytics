# Simplified Checkout Experiment Design

**Status:** Planning and historical sequence QA complete; real launch blocked
on experiment-specific telemetry, current user-level throughput measurement,
and stakeholder approval  
**Observed source window:** 2020-11-01 through 2021-01-31  
**Simulation status:** Demonstration only; no experiment was run

## Decision and intervention

The experiment asks whether a simplified checkout should replace the current
experience for eligible users.

- **Control:** current checkout.
- **Treatment:** one streamlined page combining shipping and payment while
  removing nonessential optional fields and preserving price, shipping, tax,
  and order-summary disclosure.
- **Randomization:** sticky 50/50 assignment by pseudonymous user at first
  eligible checkout.
- **Analysis:** intention to treat.
- **Primary outcome:** clean purchase within 24 hours of first eligible
  exposure.
- **Primary estimand:** treatment minus control conversion in percentage
  points.
- **Secondary outcome:** gross purchase revenue per eligible assigned user.
- **Guardrails:** payment-error rate, refund/cancellation rate, and checkout
  completion time after telemetry validation.

New-versus-Returning interaction analysis is secondary and exploratory. The
experiment is not powered for a primary subgroup claim.

## Planning inputs

The ordered historical funnel contains 5,187 checkout sessions and 2,491 clean
purchases after checkout, producing a 48.02% completion proxy with a 95% Wilson
interval of 46.67%–49.38%.

This is not the exact planned experiment metric:

- the historical denominator is sessions, while randomization is by user;
- the historical outcome is same-session, while the test uses 24 hours; and
- the source is an obfuscated 2020–2021 sample rather than current traffic.

The proxy is used only for statistical planning.

## Historical sequence diagnostic

Follow-up query
[`11_checkout_telemetry_diagnostic.sql`](../sql/analysis/11_checkout_telemetry_diagnostic.sql)
reconciles all 5,187 checkout sessions, 2,491 purchases, and 1,550 strict-path
purchases to the governed mart.

The 941 purchases outside the strict intermediate sequence are not missing all
intermediate telemetry:

- all 941 contain shipping at or before the governed checkout start;
- all 941 contain payment after checkout and before purchase;
- none lacks a shipping event everywhere in the session; and
- 4,811 of 5,187 checkout sessions contain multiple `begin_checkout` events.

The historical gap is therefore treated as a sequence/re-entry artifact. The
experiment must use a dedicated sticky exposure signal and must not use strict
shipping/payment order as its primary outcome.

## Sample size and feasibility

The planning assumptions are two-sided 5% significance, 80% power, equal
allocation, and a provisional +5.00 percentage-point absolute MDE. That MDE is
a 10.4% relative lift over the proxy baseline.

| Quantity | Planning value |
|---|---:|
| Core sample per arm | 1,569 |
| Core total sample | 3,138 |
| Operational buffer | 5% |
| Buffered target per arm | 1,648 |
| Buffered total target | 3,296 |
| Historical checkout-session volume proxy | 56.4 per day |
| Proxy duration for buffered target | 8.35 weeks |

The real stopping rule is to reach the buffered sample and stop only at the end
of a full week, without outcome peeking. Because checkout sessions can repeat
within users, the 8.35-week duration is optimistic until shadow assignment
measures current unique eligible users per day.

### MDE trade-off

| Absolute MDE | Required total sample | Historical-volume proxy |
|---:|---:|---:|
| +0.50 pp | 313,580 | 794.6 weeks |
| +1.00 pp | 78,420 | 198.7 weeks |
| +2.00 pp | 19,614 | 49.7 weeks |
| +3.00 pp | 8,718 | 22.1 weeks |
| +4.00 pp | 4,904 | 12.4 weeks |
| +5.00 pp | 3,138 | 8.0 weeks |

The +0.50 pp scenario used for opportunity prioritization is therefore not a
feasible experimental MDE at this traffic level. Opportunity sizing and
detectability are separate decisions.

## Analysis gates

1. Run the 50/50 sample-ratio-mismatch check before reading outcomes.
2. If the SRM p-value is below 0.001, stop interpretation and investigate.
3. Estimate the primary effect with a 95% Newcombe interval and report the
   pooled two-proportion z-test p-value.
4. Do not automatically ship unless the primary interval is positive, the
   point estimate meets the approved minimum-worthwhile threshold, and every
   guardrail passes.
5. Treat revenue as secondary and gross, not profit.
6. Do not change the MDE, sample, or subgroup hierarchy after observing
   treatment outcomes.

The simulated payment-error example uses a provisional +1.50 pp
non-inferiority margin. A real margin requires payments and engineering
approval.

## Seeded simulation

The executed
[`02_ab_test_design_and_simulation.ipynb`](../notebooks/02_ab_test_design_and_simulation.ipynb)
generates 3,296 synthetic assigned units with seed `20260731`. Every row carries
`is_simulated = True`. The assumed true treatment effect is +5.00 pp.

One seeded draw produces:

| Simulation-only result | Value |
|---|---:|
| Control conversion | 48.18% |
| Treatment conversion | 54.97% |
| Estimated difference | +6.80 pp |
| 95% Newcombe interval | +3.39 to +10.19 pp |
| Two-sided p-value | 0.00009 |
| SRM p-value | 0.2802 |
| Revenue-per-eligible-user difference | +$4.80 |
| Payment-error difference | −0.03 pp |

These values demonstrate the analysis and have no evidentiary value about the
real checkout change.

A separate seed, `20260801`, runs 20,000 A/A and 20,000 A/B repetitions. The
observed rejection rates are 4.98% under no effect and 80.46% when the true
effect equals +5.00 pp, matching the design targets.

## Remaining launch gates

- Implement and validate sticky assignment/exposure logging.
- Validate the 24-hour purchase window, payment-error, refund/cancellation, and
  checkout-duration guardrails.
- Measure current unique eligible users and the user-level 24-hour baseline.
- Confirm that +5.00 pp is genuinely the smallest effect worth shipping.
- Approve guardrail non-inferiority margins.
- Freeze the analysis plan before treatment outcomes are available.

Until these are complete, the experiment design is reproducible but not
launch-ready.
