SELECT *
FROM `{{ project_id }}.{{ dataset_id }}.mart_page_funnel`
WHERE is_reportable
ORDER BY page_opportunity_rank, product_page_key;
