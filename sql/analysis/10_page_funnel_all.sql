-- Aggregate PDP input for threshold and benchmark sensitivity analysis.
-- Page keys are public product URLs; no user or session identifiers are
-- exported.

SELECT
  product_page_key,
  canonical_page_title,
  view_sessions,
  attributed_add_sessions,
  attributed_checkout_sessions,
  attributed_ordered_purchase_sessions,
  view_to_add_rate,
  view_to_add_rate_ci95_lower,
  view_to_add_rate_ci95_upper
FROM `{{ project_id }}.{{ dataset_id }}.mart_page_funnel`
ORDER BY view_sessions DESC, product_page_key;
