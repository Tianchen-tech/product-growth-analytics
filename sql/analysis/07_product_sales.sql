SELECT *
FROM `{{ project_id }}.{{ dataset_id }}.mart_product_sales`
WHERE is_reportable
ORDER BY revenue_rank, purchase_product_key;
