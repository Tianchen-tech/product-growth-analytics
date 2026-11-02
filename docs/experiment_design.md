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

## Primary-metric sample size

The planning assumptions are two-sided 5% significance, 80% power, equal
allocation, and a provisional +5.00 percentage-point absolute MDE. That MDE is
a 10.4% relative lift over the proxy baseline. For the primary metric alone:

| Quantity | Planning value |
|---|---:|
| Core sample per arm | 1,569 |
| Buffered target per arm (5% operational buffer) | 1,648 |
| Buffered total target | 3,296 |
| Historical checkout-session volume proxy | 56.4 per day |
| Proxy duration for buffered target | 8.35 weeks |

This was the original enrollment plan. The decision-rule audit below shows that
it is not enough once the full ship rule and the payment-error guardrail are
taken into account.

### MDE trade-off for the primary metric

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

## Decision-rule audit

The original rule shipped only if (1) the primary 95% interval was above zero,
(2) the point estimate was at least +5.00 pp, and (3) the payment-error upper
bound was below a +1.50 pp non-inferiority margin. The sample size covered
condition 1 only. Simulating the whole rule with 40,000 seeded replications at
the 1,569-user core, with a true +5.00 pp lift and no change in payment errors
(4% assumed base rate):

| Condition at a true +5.00 pp lift | Probability |
|---|---:|
| Primary interval above zero | 80.5% |
| Point estimate at least +5.00 pp | 50.1% |
| Payment-error upper bound below +1.50 pp | 56.7% |
| **All three: the original ship rule** | **28.6%** |

A change that met the target exactly would have shipped less than one time in
three. Requiring the point estimate to reach the MDE costs half the power by
construction, because an unbiased estimate falls below its true value about
half the time. The guardrail, never included in the sizing, costs most of the
rest.

The corrected rule ships on evidence, not on the point estimate: the MDE sets
the sample size and is not a second hurdle for the estimate. The test is then
sized so that both the primary test and the guardrail pass with 80% joint
probability when the lift equals the MDE.

## Guardrail sizing

The payment-error guardrail is a non-inferiority test. Its power depends on the
margin and on the base rate, assumed to be 4% until real telemetry exists.

| Payment-error margin | Guardrail power at 1,569 per arm | Fixed-design users per arm | Fixed-design enrollment total | Proxy weeks |
|---:|---:|---:|---:|---:|
| +1.0 pp | 30% | 6,040 | 12,684 | 32.1 |
| +1.5 pp | 57% | 2,880 | 6,048 | 15.3 |
| +2.0 pp | 82% | 2,020 | 4,242 | 10.7 |
| +2.5 pp | 95% | 1,710 | 3,592 | 9.1 |
| +3.0 pp | 99% | 1,600 | 3,360 | 8.5 |

At the provisional +1.50 pp margin the guardrail, not the primary metric, sets
the sample size. The base rate matters as much as the margin: at a 2%, 4%, or 6%
payment-error rate the fixed design needs 1,930, 2,880, or 3,990 users per arm.

## Sequential monitoring plan

Reading results repeatedly with an unadjusted 5% test inflates false positives.
Over the planned test duration:

| Monitoring | Looks | False-positive rate |
|---|---:|---:|
| One read at the end | 1 | 5.0% |
| Weekly reads, unadjusted | 15 | 22.5% |
| Daily reads, unadjusted | 111 | 38.4% |
| Four planned reads, O'Brien-Fleming | 4 | 5.0% |

The plan of record reads the test four times, at 25%, 50%, 75%, and 100% of
enrollment, with O'Brien-Fleming boundaries. Every decision at a look uses the
same boundary, both for the primary z-statistic and for the confidence level of
the payment-error interval:

| Look | Users enrolled | Proxy week | z needed to ship | Nominal two-sided p |
|---:|---:|---:|---:|---:|
| 1 | 1,554 | 3.9 | 4.049 | 0.00005 |
| 2 | 3,108 | 7.9 | 2.863 | 0.0042 |
| 3 | 4,662 | 11.8 | 2.337 | 0.0194 |
| 4 | 6,216 | 15.8 | 2.024 | 0.0429 |

## Decision rules

1. Run the 50/50 sample-ratio-mismatch check at every look before reading
   outcomes. If the SRM p-value is below 0.001, stop interpretation and
   investigate.
2. **Stop for harm** if the payment-error lower bound is above zero.
3. **Ship** if the primary z-statistic reaches the look's boundary and the
   payment-error upper bound is below the +1.50 pp margin.
4. **Stop for futility** at the halfway look if the observed lift is zero or
   negative. The rule is non-binding, so ignoring it cannot raise the
   false-positive rate.
5. At the final look, apply rule 3; otherwise do not ship.
6. Report the lift with the repeated confidence interval at the stopping
   boundary; estimates from an early stop tend to overstate the true lift.
7. Treat revenue as secondary and gross, not profit.
8. Do not change the MDE, margin, look schedule, or subgroup hierarchy after
   observing treatment outcomes.

## Operating characteristics

The maximum sample started from the closed-form fixed design (2,880 per arm)
times the O'Brien-Fleming inflation factor for four looks (1.024) and was then
raised in steps of 10 until the simulated full procedure shipped a true +5.00 pp
lift at least 80% of the time: **2,960 users per arm, 3,108 with the 5%
operational buffer, 6,216 in total, at most 15.8 proxy weeks.**

| Scenario | Ships | Expected proxy weeks |
|---|---:|---:|
| No true effect | 2.0% | 11.7 |
| True lift +2.50 pp | 38.6% | 14.4 |
| True lift +5.00 pp | 80.1% | 13.4 |
| True lift +5.00 pp with payment errors +1.50 pp | 2.4% | 13.1 |

With no true effect, half of all runs stop for futility at the halfway look.
When the change raises payment errors by the full margin, 76% of runs stop for
harm. When a true +5.00 pp winner fails to ship, the guardrail is the usual
reason: 14.2% of runs end with a significant lift but a payment-error bound
above the margin, 3.0% without a significant lift, and 2.5% on a false harm
stop. Above the MDE, the probability of shipping levels off near 83% because a
larger lift does not narrow the payment-error interval.

The margin decision belongs to Payments and engineering:

| Payment-error margin | Maximum users | Maximum proxy weeks | Expected weeks if the lift is real |
|---:|---:|---:|---:|
| +1.0 pp | 13,104 | 33.2 | 27.2 |
| +1.5 pp (plan of record) | 6,216 | 15.8 | 13.4 |
| +2.0 pp | 4,410 | 11.2 | 9.5 |
| +2.5 pp | 3,760 | 9.5 | 8.0 |
| +3.0 pp | 3,612 | 9.2 | 7.5 |

## Seeded simulation

The executed
[`02_ab_test_design_and_simulation.ipynb`](../notebooks/02_ab_test_design_and_simulation.ipynb)
generates 6,216 synthetic assigned units with seed `20260731` and an assumed
true treatment effect of +5.00 pp with no change in payment errors. Every row
carries `is_simulated = True`. Read at the four planned looks:

| Look | Lift | z / boundary | Payment-error upper bound | Decision |
|---:|---:|---:|---:|---|
| 1 | +7.59 pp | 2.99 / 4.05 | +5.82 pp | Continue |
| 2 | +4.83 pp | 2.70 / 2.86 | +2.55 pp | Continue |
| 3 | +6.03 pp | 4.12 / 2.34 | +1.90 pp | Continue |
| 4 | +5.08 pp | 4.01 / 2.02 | +1.54 pp | Do not ship: guardrail not cleared |

The lift is clearly significant, but the payment-error interval cannot rule out
a rise of more than +1.50 pp, so the pre-registered rule does not ship. The
same draw shows control and treatment conversion of 48.65% and 53.73%, a
repeated confidence interval of +2.52 to +7.64 pp, and +$4.26 revenue per
eligible user. Under this plan a true winner is blocked this way about one time
in seven; the remedy is a margin decision, not a re-read of the data.

These values demonstrate the analysis and have no evidentiary value about the
real checkout change. The notebook gates its build on design properties, not on
this draw: the original rule ships a true +5 pp lift less than 40% of the time,
the final plan ships it at least 80% of the time, a no-effect change at most
2.5%, and a harmful change at most 3%.

## Remaining launch gates

- Implement and validate sticky assignment/exposure logging.
- Validate the 24-hour purchase window, payment-error, refund/cancellation, and
  checkout-duration guardrails, and measure the real payment-error rate.
- Measure current unique eligible users and the user-level 24-hour baseline.
- Confirm that +5.00 pp is the smallest effect worth detecting.
- Approve the payment-error margin; it sets the test duration.
- Freeze the analysis plan, look dates, and boundaries before treatment
  outcomes are available.

Until these are complete, the experiment design is reproducible but not
launch-ready.
