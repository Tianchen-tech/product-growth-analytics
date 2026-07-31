# Data

## Source

This project uses Google's public GA4 ecommerce sample:

```text
bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*
```

- Documentation:
  [BigQuery sample dataset for Google Analytics ecommerce](https://developers.google.com/analytics/bigquery/web-ecommerce-demo-dataset)
- Schema:
  [GA4 BigQuery Export schema](https://support.google.com/analytics/answer/7029846)
- Observation window: 2020-11-01 through 2021-01-31

Google describes the source as obfuscated sample data that emulates a
real-world implementation. Nulls, placeholders, and limited internal
consistency are expected and are profiled before analysis.

## Repository data policy

Raw events and user-level exports are not committed. In particular, files
containing `user_pseudo_id`, session keys, or event-level browsing paths must
remain local.

Only small, aggregated, non-user-level tables needed to reproduce the public
dashboard may be committed under `dashboard/aggregated_data/`. Every committed
extract must document:

- generating SQL file and query version;
- extraction date;
- row grain;
- source date window;
- filters and suppression rules;
- whether any value is simulated.

Synthetic A/B test data must include `is_simulated = TRUE` and must not be
presented as observed GA4 data.

The experiment notebook generates its synthetic rows in memory with a fixed
seed and does not persist them as observed-data extracts. Every generated row
still carries the explicit simulation flag.

## Reproduction

1. Copy `.env.example` to `.env` and set `BQ_PROJECT_ID`.
2. Run `make auth` once to complete Google user authorization.
3. Run `make all` to build core views, refresh analysis tables, require every
   reconciliation to pass, and export aggregate analysis results.
4. Read aggregate QA and analysis output under
   `data/interim/query_results/`.
5. Run `make notebooks` to regenerate both executed notebooks from the newest
   complete aggregate export, or use `make analysis` to combine steps 3 and 5.
6. Run `make dashboard-data` to publish only documented aggregate dashboard
   tables, or `make dashboard-test` to regenerate and validate the complete
   interactive dashboard.

No service-account key or local credential file should be committed.

`data/interim/` is ignored by Git. The automated runner does not download
event-, user-, session-, or order-level model rows; it saves only aggregate QA
and dashboard-safe analysis results.
