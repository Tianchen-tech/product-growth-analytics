SELECT *
FROM `{{ project_id }}.{{ dataset_id }}.mart_retention_weekly`
ORDER BY cohort_week, retention_week;
