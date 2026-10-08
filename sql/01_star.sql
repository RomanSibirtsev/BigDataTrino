-- Read both source catalogs and materialize the dimensional model in ClickHouse.
CREATE SCHEMA IF NOT EXISTS clickhouse.sales;

DROP TABLE IF EXISTS clickhouse.sales.mart_quality;
DROP TABLE IF EXISTS clickhouse.sales.mart_suppliers;
DROP TABLE IF EXISTS clickhouse.sales.mart_stores;
DROP TABLE IF EXISTS clickhouse.sales.mart_time;
DROP TABLE IF EXISTS clickhouse.sales.mart_customers;
DROP TABLE IF EXISTS clickhouse.sales.mart_products;
DROP TABLE IF EXISTS clickhouse.sales.fact_sales;
DROP TABLE IF EXISTS clickhouse.sales.dim_date;
DROP TABLE IF EXISTS clickhouse.sales.dim_product;
DROP TABLE IF EXISTS clickhouse.sales.dim_customer;
DROP TABLE IF EXISTS clickhouse.sales.dim_seller;
DROP TABLE IF EXISTS clickhouse.sales.dim_store;
DROP TABLE IF EXISTS clickhouse.sales.dim_supplier;
DROP TABLE IF EXISTS clickhouse.sales.staging_sales;

CREATE TABLE clickhouse.sales.staging_sales WITH (engine = 'MergeTree') AS
WITH sources AS (
    SELECT *, 'clickhouse' AS source_system
    FROM clickhouse.raw.mock_data
    UNION ALL
    SELECT *, 'postgres' AS source_system
    FROM postgres.public.mock_data
)
SELECT
    id,
    customer_first_name,
    customer_last_name,
    CAST(NULLIF(customer_age, '') AS INTEGER) AS customer_age,
    customer_email,
    customer_country,
    customer_postal_code,
    customer_pet_type,
    customer_pet_name,
    customer_pet_breed,
    seller_first_name,
    seller_last_name,
    seller_email,
    seller_country,
    seller_postal_code,
    product_name,
    product_category,
    CAST(NULLIF(product_price, '') AS DECIMAL(18, 2)) AS product_price,
    CAST(NULLIF(product_quantity, '') AS BIGINT) AS product_quantity,
    CAST(date_parse(NULLIF(sale_date, ''), '%c/%e/%Y') AS DATE) AS sale_date,
    sale_customer_id,
    sale_seller_id,
    sale_product_id,
    CAST(NULLIF(sale_quantity, '') AS BIGINT) AS sale_quantity,
    CAST(NULLIF(sale_total_price, '') AS DECIMAL(18, 2)) AS sale_total_price,
    store_name,
    store_location,
    store_city,
    store_state,
    store_country,
    store_phone,
    store_email,
    pet_category,
    CAST(NULLIF(product_weight, '') AS DECIMAL(18, 2)) AS product_weight,
    product_color,
    product_size,
    product_brand,
    product_material,
    product_description,
    CAST(NULLIF(product_rating, '') AS DECIMAL(18, 6)) AS product_rating,
    CAST(NULLIF(product_reviews, '') AS BIGINT) AS product_reviews,
    CAST(date_parse(NULLIF(product_release_date, ''), '%c/%e/%Y') AS DATE) AS product_release_date,
    CAST(date_parse(NULLIF(product_expiry_date, ''), '%c/%e/%Y') AS DATE) AS product_expiry_date,
    supplier_name,
    supplier_contact,
    supplier_email,
    supplier_phone,
    supplier_address,
    supplier_city,
    supplier_country,
    source_file,
    source_row,
    source_row_id,
    source_system
FROM sources;

CREATE TABLE clickhouse.sales.dim_customer WITH (engine = 'MergeTree') AS
SELECT DISTINCT
    customer_email AS customer_key,
    customer_first_name,
    customer_last_name,
    customer_age,
    customer_email,
    customer_country,
    customer_postal_code,
    customer_pet_type,
    customer_pet_name,
    customer_pet_breed
FROM clickhouse.sales.staging_sales;

CREATE TABLE clickhouse.sales.dim_seller WITH (engine = 'MergeTree') AS
SELECT DISTINCT
    seller_email AS seller_key,
    seller_first_name,
    seller_last_name,
    seller_email,
    seller_country,
    seller_postal_code
FROM clickhouse.sales.staging_sales;

CREATE TABLE clickhouse.sales.dim_store WITH (engine = 'MergeTree') AS
SELECT DISTINCT
    store_email AS store_key,
    store_name,
    store_location,
    store_city,
    store_state,
    store_country,
    store_phone,
    store_email
FROM clickhouse.sales.staging_sales;

CREATE TABLE clickhouse.sales.dim_supplier WITH (engine = 'MergeTree') AS
SELECT DISTINCT
    supplier_email AS supplier_key,
    supplier_name,
    supplier_contact,
    supplier_email,
    supplier_phone,
    supplier_address,
    supplier_city,
    supplier_country
FROM clickhouse.sales.staging_sales;

CREATE TABLE clickhouse.sales.dim_product WITH (engine = 'MergeTree') AS
SELECT DISTINCT
    source_row_id AS product_key,
    product_name,
    product_category,
    product_price,
    product_quantity,
    product_weight,
    product_color,
    product_size,
    product_brand,
    product_material,
    product_description,
    product_rating,
    product_reviews,
    product_release_date,
    product_expiry_date,
    pet_category
FROM clickhouse.sales.staging_sales;

CREATE TABLE clickhouse.sales.dim_date WITH (engine = 'MergeTree') AS
SELECT DISTINCT
    sale_date AS date_key,
    day(sale_date) AS day,
    month(sale_date) AS month,
    quarter(sale_date) AS quarter,
    year(sale_date) AS year
FROM clickhouse.sales.staging_sales;

CREATE TABLE clickhouse.sales.fact_sales WITH (engine = 'MergeTree') AS
SELECT
    source_row_id,
    source_file,
    source_row,
    source_system,
    id,
    sale_customer_id,
    sale_seller_id,
    sale_product_id,
    customer_email AS customer_key,
    seller_email AS seller_key,
    source_row_id AS product_key,
    store_email AS store_key,
    supplier_email AS supplier_key,
    sale_date AS date_key,
    sale_quantity,
    sale_total_price
FROM clickhouse.sales.staging_sales;