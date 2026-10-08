CREATE TABLE clickhouse.sales.mart_products WITH (engine = 'MergeTree') AS
WITH products AS (
    SELECT
        p.product_name,
        p.product_category,
        SUM(f.sale_quantity) AS units_sold,
        CAST(SUM(f.sale_total_price) AS DECIMAL(18, 2)) AS revenue,
        CAST(AVG(CAST(p.product_rating AS DOUBLE)) AS DECIMAL(18, 6)) AS avg_rating,
        SUM(p.product_reviews) AS review_count
    FROM clickhouse.sales.fact_sales f
    JOIN clickhouse.sales.dim_product p ON p.product_key = f.product_key
    GROUP BY p.product_name, p.product_category
)
SELECT
    *,
    ROW_NUMBER() OVER (ORDER BY units_sold DESC, product_name, product_category) AS sales_rank,
    CAST(SUM(revenue) OVER (PARTITION BY product_category) AS DECIMAL(18, 2)) AS category_revenue
FROM products;

CREATE TABLE clickhouse.sales.mart_customers WITH (engine = 'MergeTree') AS
WITH customers AS (
    SELECT
        c.customer_email AS email,
        MAX(concat(c.customer_first_name, ' ', c.customer_last_name)) AS full_name,
        MAX(c.customer_country) AS country,
        COUNT(*) AS orders_count,
        CAST(SUM(f.sale_total_price) AS DECIMAL(18, 2)) AS revenue,
        CAST(AVG(CAST(f.sale_total_price AS DECIMAL(18, 6))) AS DECIMAL(18, 6)) AS avg_order_value
    FROM clickhouse.sales.fact_sales f
    JOIN clickhouse.sales.dim_customer c ON c.customer_key = f.customer_key
    GROUP BY c.customer_email
)
SELECT
    *,
    ROW_NUMBER() OVER (ORDER BY revenue DESC, email) AS spending_rank,
    COUNT(*) OVER (PARTITION BY country) AS country_customer_count
FROM customers;

CREATE TABLE clickhouse.sales.mart_time WITH (engine = 'MergeTree') AS
WITH periods AS (
    SELECT
        'month' AS period_type,
        CAST(date_trunc('month', date_key) AS DATE) AS period_start,
        sale_quantity,
        sale_total_price
    FROM clickhouse.sales.fact_sales
    UNION ALL
    SELECT
        'year',
        CAST(date_trunc('year', date_key) AS DATE),
        sale_quantity,
        sale_total_price
    FROM clickhouse.sales.fact_sales
), totals AS (
    SELECT
        period_type,
        period_start,
        COUNT(*) AS orders_count,
        SUM(sale_quantity) AS units_sold,
        CAST(SUM(sale_total_price) AS DECIMAL(18, 2)) AS revenue,
        CAST(AVG(CAST(sale_total_price AS DECIMAL(18, 6))) AS DECIMAL(18, 6)) AS avg_order_value,
        CAST(AVG(CAST(sale_quantity AS DECIMAL(18, 6))) AS DECIMAL(18, 6)) AS avg_order_quantity
    FROM periods
    GROUP BY period_type, period_start
), comparisons AS (
    SELECT
        *,
        LAG(revenue) OVER (PARTITION BY period_type ORDER BY period_start) AS previous_revenue
    FROM totals
)
SELECT
    *,
    CAST(revenue - previous_revenue AS DECIMAL(18, 2)) AS revenue_change,
    CAST(
        (CAST(revenue AS DOUBLE) - CAST(previous_revenue AS DOUBLE)) * 100.0
        / NULLIF(CAST(previous_revenue AS DOUBLE), 0.0)
        AS DECIMAL(18, 6)
    ) AS revenue_change_percent
FROM comparisons;

CREATE TABLE clickhouse.sales.mart_stores WITH (engine = 'MergeTree') AS
WITH stores AS (
    SELECT
        s.store_name,
        s.store_city AS city,
        s.store_country AS country,
        COUNT(*) AS orders_count,
        CAST(SUM(f.sale_total_price) AS DECIMAL(18, 2)) AS revenue,
        CAST(AVG(CAST(f.sale_total_price AS DECIMAL(18, 6))) AS DECIMAL(18, 6)) AS avg_order_value
    FROM clickhouse.sales.fact_sales f
    JOIN clickhouse.sales.dim_store s ON s.store_key = f.store_key
    GROUP BY s.store_name, s.store_city, s.store_country
)
SELECT
    *,
    ROW_NUMBER() OVER (ORDER BY revenue DESC, store_name, city, country) AS revenue_rank,
    CAST(SUM(revenue) OVER (PARTITION BY city, country) AS DECIMAL(18, 2)) AS city_revenue,
    CAST(SUM(revenue) OVER (PARTITION BY country) AS DECIMAL(18, 2)) AS country_revenue
FROM stores;

CREATE TABLE clickhouse.sales.mart_suppliers WITH (engine = 'MergeTree') AS
WITH suppliers AS (
    SELECT
        s.supplier_name,
        s.supplier_country AS country,
        COUNT(*) AS orders_count,
        CAST(SUM(f.sale_total_price) AS DECIMAL(18, 2)) AS revenue,
        CAST(AVG(CAST(p.product_price AS DECIMAL(18, 6))) AS DECIMAL(18, 6)) AS avg_product_price
    FROM clickhouse.sales.fact_sales f
    JOIN clickhouse.sales.dim_supplier s ON s.supplier_key = f.supplier_key
    JOIN clickhouse.sales.dim_product p ON p.product_key = f.product_key
    GROUP BY s.supplier_name, s.supplier_country
)
SELECT
    *,
    ROW_NUMBER() OVER (ORDER BY revenue DESC, supplier_name, country) AS revenue_rank,
    CAST(SUM(revenue) OVER (PARTITION BY country) AS DECIMAL(18, 2)) AS country_revenue
FROM suppliers;

CREATE TABLE clickhouse.sales.mart_quality WITH (engine = 'MergeTree') AS
WITH products AS (
    SELECT
        p.product_name,
        p.product_category,
        AVG(CAST(p.product_rating AS DOUBLE)) AS exact_avg_rating,
        SUM(p.product_reviews) AS review_count,
        SUM(f.sale_quantity) AS units_sold
    FROM clickhouse.sales.fact_sales f
    JOIN clickhouse.sales.dim_product p ON p.product_key = f.product_key
    GROUP BY p.product_name, p.product_category
)
SELECT
    product_name,
    product_category,
    CAST(exact_avg_rating AS DECIMAL(18, 6)) AS avg_rating,
    review_count,
    units_sold,
    ROW_NUMBER() OVER (ORDER BY exact_avg_rating DESC, product_name, product_category) AS rating_rank_desc,
    ROW_NUMBER() OVER (ORDER BY exact_avg_rating ASC, product_name, product_category) AS rating_rank_asc,
    ROW_NUMBER() OVER (ORDER BY review_count DESC, product_name, product_category) AS review_rank,
    CORR(exact_avg_rating, CAST(units_sold AS DOUBLE)) OVER () AS rating_sales_correlation
FROM products;