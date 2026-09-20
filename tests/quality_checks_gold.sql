/*
===============================================================================
Quality Checks: Gold Layer
===============================================================================
Script Purpose:
    Validates the integrity, consistency and accuracy of the Gold layer:
        - Uniqueness of surrogate keys and business keys in the dimensions
        - Referential integrity between the fact table and the dimensions
        - Reconciliation between Silver and Gold (no rows lost or duplicated)
        - Coverage of the calendar dimension
        - Text encoding sanity check

Usage:
    Run after EXEC gold.load_gold. Every check states its expected result.
    Investigate and resolve any discrepancy.
===============================================================================
*/
USE DataWarehouse;
GO

-- ====================================================================
-- 1) Uniqueness of surrogate keys
-- Expectation: no rows
-- ====================================================================
SELECT 'dim_customers.customer_key' AS check_name, customer_key AS key_value, COUNT(*) AS duplicate_count
FROM gold.dim_customers GROUP BY customer_key HAVING COUNT(*) > 1
UNION ALL
SELECT 'dim_products.product_key', product_key, COUNT(*)
FROM gold.dim_products GROUP BY product_key HAVING COUNT(*) > 1;

-- ====================================================================
-- 2) Uniqueness of business keys (a duplicate here would multiply fact rows)
-- Expectation: no rows
-- ====================================================================
SELECT 'dim_customers.customer_id' AS check_name, customer_id AS key_value, COUNT(*) AS duplicate_count
FROM gold.dim_customers GROUP BY customer_id HAVING COUNT(*) > 1;

SELECT 'dim_products.product_number' AS check_name, product_number AS key_value, COUNT(*) AS duplicate_count
FROM gold.dim_products GROUP BY product_number HAVING COUNT(*) > 1;

-- ====================================================================
-- 3) Referential integrity: fact rows without a matching dimension row
-- Expectation: 0 and 0
-- ====================================================================
SELECT COUNT(*) AS fact_rows_without_customer
FROM gold.fact_sales f
LEFT JOIN gold.dim_customers c ON c.customer_key = f.customer_key
WHERE c.customer_key IS NULL;

SELECT COUNT(*) AS fact_rows_without_product
FROM gold.fact_sales f
LEFT JOIN gold.dim_products p ON p.product_key = f.product_key
WHERE p.product_key IS NULL;

-- ====================================================================
-- 4) Silver -> Gold reconciliation
-- Expectation: row_diff = 0 and sales_diff = 0
-- ====================================================================
SELECT
    (SELECT COUNT(*)          FROM silver.crm_sales_details) AS silver_rows,
    (SELECT COUNT(*)          FROM gold.fact_sales)          AS gold_rows,
    (SELECT COUNT(*)          FROM gold.fact_sales)
      - (SELECT COUNT(*)      FROM silver.crm_sales_details) AS row_diff,
    (SELECT SUM(CAST(sls_sales   AS BIGINT)) FROM silver.crm_sales_details) AS silver_sales,
    (SELECT SUM(CAST(sales_amount AS BIGINT)) FROM gold.fact_sales)         AS gold_sales,
    (SELECT SUM(CAST(sales_amount AS BIGINT)) FROM gold.fact_sales)
      - (SELECT SUM(CAST(sls_sales AS BIGINT)) FROM silver.crm_sales_details) AS sales_diff;

-- ====================================================================
-- 5) Row counts per Gold table
-- Expected for the course dataset: 18484 / 295 / 60398 (dim_date depends on the date range)
-- ====================================================================
SELECT 'dim_customers' AS table_name, COUNT(*) AS row_count FROM gold.dim_customers
UNION ALL SELECT 'dim_products', COUNT(*) FROM gold.dim_products
UNION ALL SELECT 'fact_sales',   COUNT(*) FROM gold.fact_sales
UNION ALL SELECT 'dim_date',     COUNT(*) FROM gold.dim_date;

-- Total sales. Expected for the course dataset: 29356250
SELECT SUM(sales_amount) AS total_sales FROM gold.fact_sales;

-- ====================================================================
-- 6) Calendar coverage: fact dates that are missing in dim_date
-- Expectation: 0
-- ====================================================================
SELECT COUNT(*) AS order_dates_without_calendar_row
FROM gold.fact_sales f
LEFT JOIN gold.dim_date d ON d.full_date = f.order_date
WHERE f.order_date IS NOT NULL AND d.full_date IS NULL;

-- ====================================================================
-- 7) Encoding check
-- NCHAR(9500) is the box-drawing character that shows up when UTF-8 text was
-- loaded with the wrong code page (e.g. 'Jimenez' with an accent).
-- Expectation: no rows
-- ====================================================================
SELECT customer_id, first_name, last_name
FROM gold.dim_customers
WHERE first_name LIKE N'%' + NCHAR(9500) + N'%'
   OR last_name  LIKE N'%' + NCHAR(9500) + N'%';

-- Spot check of an accented name. Expected last_name: Jiménez
SELECT customer_id, first_name, last_name
FROM gold.dim_customers
WHERE customer_id = 11120;
GO
