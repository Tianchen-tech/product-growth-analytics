# Product Growth Analytics Dashboard

Interactive React/vinext dashboard for the ecommerce product-growth case study.

## Local commands

Run from the repository root:

```bash
make dashboard-setup
make dashboard-data
make dashboard-test
make dashboard-dev
```

The site imports `app/dashboard-data.json`, generated from the same
aggregate-only inputs published under `../aggregated_data/`. Download copies
are placed under `public/data/` by the data builder.

The production build emits a Cloudflare-compatible worker under `dist/`.
