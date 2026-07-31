-- Execution bridge for the checkout mart.
-- Grain: one session that reached begin_checkout after an ordered add.
-- Materializing this narrow subset keeps the downstream sequencing query below
-- BigQuery's query-planning complexity limit.

CREATE OR REPLACE TABLE
  `{{ project_id }}.{{ dataset_id }}.int_checkout_sessions`
OPTIONS (
  description = 'Narrow materialized bridge for strict checkout sequencing'
)
AS
SELECT
  session_key,
  begin_checkout_event_timestamp,
  reached_purchase_after_checkout,
  purchase_event_timestamp
FROM `{{ project_id }}.{{ dataset_id }}.fct_sessions`
WHERE reached_checkout_after_add_to_cart;
