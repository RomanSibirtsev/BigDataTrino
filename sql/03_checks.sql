SELECT 'clickhouse' AS source, COUNT(*) AS rows FROM clickhouse.raw.mock_data
UNION ALL
SELECT 'postgres', COUNT(*) FROM postgres.public.mock_data;

SELECT
    COUNT(*) AS rows,
    COUNT(DISTINCT source_row_id) AS unique_rows,
    SUM(sale_quantity) AS quantity,
    SUM(sale_total_price) AS revenue
FROM clickhouse.sales.fact_sales;

SELECT * FROM clickhouse.sales.mart_products ORDER BY sales_rank;
SELECT * FROM clickhouse.sales.mart_customers ORDER BY spending_rank;
SELECT * FROM clickhouse.sales.mart_time ORDER BY period_type, period_start;
SELECT * FROM clickhouse.sales.mart_stores ORDER BY revenue_rank;
SELECT * FROM clickhouse.sales.mart_suppliers ORDER BY revenue_rank;
SELECT * FROM clickhouse.sales.mart_quality ORDER BY rating_rank_desc;