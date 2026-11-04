# Documentation

- `metric_dictionary.md`: locked metric and denominator definitions.
- `data_profile_results.md`: observed outputs and pass/fail interpretations for
  each source profiling query.
- `data_model.md`: implemented model grains, lineage, and reconciliation rules.
- `model_build_results.md`: live BigQuery build and hard-QA evidence.
- `analysis_layer_results.md`: implemented marts, reporting thresholds, QA
  results, sensitivity checks, and the provisional telemetry-gated experiment
  priority.
- `experiment_design.md`: simplified-checkout test contract, the
  decision-rule audit, guardrail sizing, the four-look sequential monitoring
  plan, operating characteristics, simulated analysis, and launch gates.
- `checkout_telemetry_diagnostic.md`: historical checkout path classification,
  repeated-event findings, segment checks, and metric implications.
- `../dashboard/field_dictionary.md`: grains, evidence labels, and usage
  cautions for every published dashboard CSV.
- `product_decision_memo.md`: human-readable source for the final two-page
  English memo.
- `product_decision_memo.pdf`: final rendered two-page decision memo, with
  historical evidence, opportunity scenarios, and simulation output labeled
  separately.

Rebuild and validate the PDF from the repository root with:

```bash
make memo
```
