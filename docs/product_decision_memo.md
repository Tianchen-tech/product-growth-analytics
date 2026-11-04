# Product Decision Memo: Simplified Checkout Experiment

**To:** Ecommerce Product Manager  
**From:** Product Analytics  
**Date:** 31 July 2026  
**Decision status:** Provisional go to experiment; not launch-ready

## Decision

Advance a simplified checkout experience into a user-randomized A/B test.
Do not claim that the current checkout causes abandonment. Launch only after
sticky exposure logging, the 24-hour outcome window, guardrails, current
unique-user throughput, the planning MDE, and the payment-error margin are
approved.

## Executive summary

The historical GA4 sample contains 360,129 valid sessions, 4,436 clean orders,
and $306,678 in canonical gross revenue. The ordered product funnel narrows from
77,020 product-view sessions to 14,380 cart sessions, 5,187 checkout sessions,
and 2,491 clean purchases after checkout. The largest absolute loss occurs from
product view to cart, but a checkout intervention is more directly measurable
and has a broader historical-window opportunity than the top governed
single-page scenario.

A +0.50 percentage-point checkout-completion scenario produces 25.9
incremental orders and $1,793 in gross revenue across the historical checkout
population. The top governed PDP, Super G Unisex Joggers, produces a
non-additive scenario of 21.46 orders and $1,483.56 at the P75 page benchmark.
Neither value is a forecast or a causal estimate.

The original 941-purchase strict-path gap is not evidence of 941 abandonments.
All 941 purchases have shipping at or before the governed checkout start and
payment before purchase; none lacks shipping everywhere in the session.
Because 92.75% of checkout sessions contain repeated `begin_checkout` events,
the gap is classified as a sequence or re-entry artifact. A real experiment
must therefore use a dedicated sticky exposure event.

## Evidence supporting the decision

| Signal | Historical evidence | Decision implication |
|---|---:|---|
| Purchase-session conversion | 1.12% | Establishes the business baseline |
| Checkout completion proxy | 2,491 / 5,187 = 48.02% | Large, measurable eligible population |
| Product view to cart | 18.67%; 62,640 sessions lost | Largest behavioral loss, but page scenarios are non-additive |
| Mobile vs Desktop purchase conversion | 1.15% vs 1.10%; difference CI includes zero | Do not prioritize a mobile-only redesign |
| Returning vs New purchase conversion | 2.55% vs 0.57% | Strong descriptive split; secondary experiment interaction |
| Channel-quality limitations | 70.13% of sessions in weak-quality buckets | Do not use channel ranking for the product decision |

All 43 core and analysis-layer reconciliations passed. Segment comparisons are
descriptive because users can contribute repeated sessions and traffic mix is
not adjusted.

## Alternatives considered

1. **Optimize the top PDP:** retain Super G Unisex Joggers as the secondary
   opportunity. Its identity is robust, but scenario magnitude is highly
   benchmark-sensitive and page opportunities cannot be summed.
2. **Prioritize mobile:** reject as the primary direction because the observed
   mobile purchase rate is not lower than Desktop.
3. **Target acquisition channels:** defer because source and medium quality is
   not decision-grade.
4. **Simplify checkout:** advance to a controlled test because it is
   actionable, measurable, and produces a larger historical-window scenario
   than the top governed single PDP at only +0.50 pp.

## Experiment contract

| Element | Locked planning rule |
|---|---|
| Control | Current checkout |
| Treatment | One streamlined page combining shipping and payment, removing nonessential optional fields while preserving price, tax, shipping, and order-summary disclosure |
| Randomization | Sticky 50/50 assignment by pseudonymous user at first eligible checkout |
| Analysis | Intention to treat |
| Primary outcome | Clean purchase within 24 hours of first eligible exposure |
| Primary estimand | Treatment minus Control conversion, in percentage points |
| Secondary outcome | Gross purchase revenue per eligible assigned user |
| Guardrails | Payment-error rate, refund or cancellation rate, and checkout completion time |

Shipping and payment events remain diagnostics; they are not required in the
primary conversion definition.

## Sample size and feasibility

The 48.02% historical checkout-session completion rate is a planning proxy, not
the exact user-level 24-hour experiment metric. With two-sided alpha of 5%,
equal allocation, and a provisional +5.00 pp absolute MDE, the primary metric
alone needs 1,569 users per arm (3,296 with a 5% buffer, about 8.4 proxy weeks).

That first plan failed its own audit. Its rule also required the point estimate
to reach +5.00 pp and the payment-error bound to clear a +1.50 pp margin, which
the sample size never covered. Simulated end to end, it shipped a change that
met the target only **28.6%** of the time. The plan of record fixes both
problems and is sized by simulating the full decision rule:

| Planning quantity | Value |
|---|---:|
| Users per arm (5% buffer included) | 3,108 |
| Maximum total | 6,216 |
| Historical checkout-session throughput proxy | 56.4 per day |
| Maximum duration proxy | 15.8 weeks |
| Expected duration if the lift is real / absent | 13.4 / 11.7 weeks |
| Ships a true +5.00 pp lift | 80.1% |
| Ships a no-effect / harmful change | 2.0% / 2.4% |

The payment-error guardrail, not the primary metric, sets the duration: a
+2.00 pp margin would cut the maximum to 4,410 users and 11.2 weeks. Durations
are optimistic because historical sessions can repeat within users. A +0.50 pp
MDE would require approximately 313,580 units and 795 proxy weeks, so
commercial opportunity and statistical detectability must remain separate
decisions.

## Decision rules

1. Run the 50/50 sample-ratio-mismatch check at every look before reading
   outcomes. Stop and investigate if the SRM p-value is below 0.001.
2. Read the test at 25%, 50%, 75%, and 100% of enrollment against
   O'Brien-Fleming boundaries (z = 4.05, 2.86, 2.34, 2.02). Unadjusted daily
   reads would raise the false-positive rate from 5% to 38%.
3. Ship when the primary z-statistic reaches the look's boundary and the
   payment-error upper bound, at the same confidence, is below the margin. The
   point estimate is not compared with the MDE.
4. Stop for harm if the payment-error lower bound is above zero; stop for
   futility at the halfway look if the observed lift is not positive.
5. Do not change the MDE, margin, look schedule, or subgroup hierarchy after
   reading outcomes.

## Launch gates and owners

- **Analytics:** validate sticky exposure, the 24-hour clean-purchase window,
  current unique eligible users per day, SRM monitoring, and the user-level
  baseline.
- **Engineering:** prevent re-randomization on repeated checkout starts and
  validate payment-error, refund or cancellation, and timing telemetry.
- **Payments and Product:** measure the payment-error base rate, approve the
  margin that sets the duration, and confirm that +5.00 pp is the smallest
  effect worth detecting.
- **Product and Design:** freeze the treatment specification and preserve
  pricing, shipping, tax, order-summary, accessibility, and trust disclosures.

## Simulation disclosure

The seeded notebook example assumes a true +5.00 pp lift. At the final look it
estimates +5.08 pp (z = 4.01 against a 2.02 boundary), but the payment-error
upper bound of +1.54 pp misses the +1.50 pp margin, so the rule does not ship.
It is demonstration-only synthetic output and provides no evidence about a
real checkout treatment.

## Final recommendation

Proceed to instrumentation validation and stakeholder sign-off, then run the
user-randomized test. Do not ship the treatment from historical analysis or
from the seeded simulation. Revisit the top PDP opportunity if checkout
instrumentation fails, the approved MDE becomes infeasible, or current
unique-user throughput cannot support the test.

**Evidence base:** Google GA4 public ecommerce sample, 2020-11-01 through
2021-01-31; aggregate analysis run `20260731T052813Z`; 43 of 43 hard checks
passed.  
**Interactive dashboard:** https://ga4-product-growth-decision-dashboard.world8866.chatgpt.site
