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
- a provisional +5.00 percentage-point planning MDE;
- 1,569 users per arm, or 1,648 per arm after a 5% operational buffer;
- sample-size, baseline, and fixed-duration MDE sensitivity;
- an SRM gate at `p < 0.001`;
- a 95% Newcombe interval and pooled two-proportion z-test;
- revenue per eligible user and a simulated payment-error guardrail; and
- 20,000 seeded A/A and A/B repetitions validating approximately 5% false
  positives and 80% power.

Every synthetic row includes `is_simulated = True`, and the notebook repeatedly
labels the favorable seeded draw as a demonstration rather than a real
experiment. Four additional charts are saved under `notebooks/figures/`.

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
