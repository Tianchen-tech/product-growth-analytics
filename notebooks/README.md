# Notebooks

## Completed

### `01_funnel_and_sensitivity.ipynb`

This executed notebook consumes the newest complete aggregate export under
`data/interim/query_results/` and covers:

- the governed metric tree and ordered funnel;
- preselected device and tenure differences with 95% Newcombe intervals;
- channel-quality exclusion sensitivity;
- exclusion of the five source-volume anomaly dates;
- PDP denominator thresholds of 50, 100, 200, 500, and 1,000 views;
- exact P50, P75, and P90 PDP benchmark scenarios;
- strict versus any-intermediate checkout telemetry;
- checkout absolute-lift scenarios; and
- complete-cell W1–W8 activity retention.

The notebook provisionally advances simplified checkout into experiment design.
The later checkout diagnostic classifies the strict-path difference as a
sequence/re-entry artifact; experiment-specific telemetry and MDE approval
remain gates. Historical data do not establish causal impact.

Five generated charts are saved under `notebooks/figures/`. SQL remains the
source of truth; the notebook never loads user-, session-, event-, or
order-level identifiers.

### `02_ab_test_design_and_simulation.ipynb`

This executed notebook converts the provisional simplified-checkout priority
into a reproducible experiment plan:

- 48.02% historical same-session completion as a planning proxy, not a promised
  user-level 24-hour baseline;
- sticky 50/50 pseudonymous-user assignment and intention-to-treat analysis;
- a provisional +5.00 percentage-point planning MDE, which needs 1,569 users
  per arm for the primary metric alone, with sample-size, baseline, and
  fixed-duration MDE sensitivity;
- a decision-rule audit: simulated end to end, the original ship rule ships a
  true +5.00 pp lift only 28.6% of the time, because it also required the point
  estimate to reach the MDE and never sized the payment-error guardrail;
- guardrail sizing and the payment-error margin trade-off;
- a four-look O'Brien-Fleming plan with harm and futility stops, sized by
  simulation at 6,216 users, that ships a true +5.00 pp lift 80% of the time
  and a no-effect change 2% of the time;
- the false-positive cost of unadjusted peeking (22% weekly, 38% daily);
- one seeded synthetic experiment read look by look with SRM checks, repeated
  confidence intervals, revenue per eligible user, and the payment-error
  guardrail; and
- design-contract checks that gate the build, plus
  `outputs/experiment_design_summary.json`, which the dashboard and memo read.

Every synthetic row includes `is_simulated = True`. The build asserts properties
of the design, not the outcome of the single seeded draw, which happens to end
with a significant lift blocked by the guardrail. Five additional charts are
saved under `notebooks/figures/`.

## Run it

Create the isolated environment once, using Python 3.10 or newer:

```bash
make notebook-setup NOTEBOOK_PYTHON=/path/to/python3
```

Then choose one of the following:

```bash
make notebook       # rebuild the funnel and sensitivity notebook
make ab-notebook    # rebuild the A/B design and simulation notebook
make notebooks      # rebuild both from the latest complete local export
make analysis       # refresh BigQuery, run QA, export, then rebuild both
make notebook-html  # execute both and create local HTML previews
```

The generators are `scripts/build_analysis_notebook.py` and
`scripts/build_ab_test_notebook.py`. They execute the notebooks top to bottom
and fail if an input contract, statistical calibration, or decision check
fails.

The aggregate dashboard and the final decision memo are complete. The
remaining work is experiment exposure and guardrail validation and current
unique-user throughput measurement. Historical sequence telemetry has been
diagnosed by
`sql/analysis/11_checkout_telemetry_diagnostic.sql`; experiment exposure and
guardrail instrumentation remain launch gates.
