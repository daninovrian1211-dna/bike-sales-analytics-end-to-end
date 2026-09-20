/*
===============================================================================
Report Layer: Customer Report & Product Report
===============================================================================
Script Purpose:
    Creates two consumption views in the 'report' schema. They sit on top of the
    Gold star schema and pre-aggregate the data for analysts and BI tools.

        - report.customers : one row per customer (segments, KPIs)
        - report.products  : one row per product  (segments, KPIs)

    Views are used here on purpose: they hold no data of their own, so they are
    always consistent with gold.* and never need to be reloaded.

Design notes:
    - "Recency" and "age" are measured against the LAST ORDER DATE IN THE DATA
      (not GETDATE()). The dataset is historical, so measuring against today's
      date would inflate the numbers and change them every month.
    - Age is a real completed-years age (DATEDIFF(YEAR) alone over-counts when the
      birthday has not yet occurred in the reference year).
    - Averages are calculated with decimals (integer division truncates).

Usage:
    SELECT * FROM report.customers;
    SELECT * FROM report.products;
===============================================================================
*/
USE DataWarehouse;
GO

IF SCHEMA_ID('report') IS NULL
    EXEC ('CREATE SCHEMA report');
GO

-- =============================================================================
-- Customer Report
-- =============================================================================
-- Segments customers into VIP / Regular / New and into age groups.
--   VIP     : lifespan >= 12 months and total sales >  5,000
--   Regular : lifespan >= 12 months and total sales <= 5,000
--   New     : lifespan <  12 months
-- =============================================================================
CREATE OR ALTER VIEW report.customers AS
WITH ref AS (
    -- Reference date = most recent order in the data
    SELECT MAX(order_date) AS ref_date FROM gold.fact_sales
),
base_query AS (
    /*-----------------------------------------------------------------------
    1) Base query: core columns from fact_sales and dim_customers
    -----------------------------------------------------------------------*/
    SELECT
        f.order_number,
        f.product_key,
        f.order_date,
        f.sales_amount,
        f.quantity,
        c.customer_key,
        c.customer_number,
        CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
        CASE
            WHEN c.birthdate IS NULL THEN NULL
            ELSE DATEDIFF(YEAR, c.birthdate, r.ref_date)
                 - CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, c.birthdate, r.ref_date), c.birthdate) > r.ref_date
                        THEN 1 ELSE 0 END
        END AS age
    FROM gold.fact_sales f
    INNER JOIN gold.dim_customers c ON c.customer_key = f.customer_key
    CROSS JOIN ref r
    WHERE f.order_date IS NOT NULL            -- only valid sales dates
),
customer_aggregation AS (
    /*-----------------------------------------------------------------------
    2) Customer aggregations: key metrics at the customer level
    -----------------------------------------------------------------------*/
    SELECT
        customer_key,
        customer_number,
        customer_name,
        age,
        COUNT(DISTINCT order_number)                     AS total_orders,
        SUM(sales_amount)                                AS total_sales,
        SUM(quantity)                                    AS total_quantity,
        COUNT(DISTINCT product_key)                      AS total_products,
        MAX(order_date)                                  AS last_order_date,
        DATEDIFF(MONTH, MIN(order_date), MAX(order_date)) AS lifespan
    FROM base_query
    GROUP BY customer_key, customer_number, customer_name, age
)
/*---------------------------------------------------------------------------
3) Final query: segments and KPIs
---------------------------------------------------------------------------*/
SELECT
    ca.customer_key,
    ca.customer_number,
    ca.customer_name,
    ca.age,
    CASE
        WHEN ca.age IS NULL           THEN 'n/a'
        WHEN ca.age < 20              THEN 'Under 20'
        WHEN ca.age BETWEEN 20 AND 29 THEN '20-29'
        WHEN ca.age BETWEEN 30 AND 39 THEN '30-39'
        WHEN ca.age BETWEEN 40 AND 49 THEN '40-49'
        ELSE '50 and above'
    END AS age_group,
    CASE
        WHEN ca.lifespan >= 12 AND ca.total_sales >  5000 THEN 'VIP'
        WHEN ca.lifespan >= 12 AND ca.total_sales <= 5000 THEN 'Regular'
        ELSE 'New'
    END AS customer_segment,
    ca.last_order_date,
    DATEDIFF(MONTH, ca.last_order_date, r.ref_date) AS recency_in_months,
    ca.total_orders,
    ca.total_sales,
    ca.total_quantity,
    ca.total_products,
    ca.lifespan,
    -- Average order value
    CAST(1.0 * ca.total_sales / NULLIF(ca.total_orders, 0) AS DECIMAL(18, 2)) AS avg_order_value,
    -- Average monthly spend
    CASE
        WHEN ca.lifespan = 0 THEN CAST(ca.total_sales AS DECIMAL(18, 2))
        ELSE CAST(1.0 * ca.total_sales / ca.lifespan AS DECIMAL(18, 2))
    END AS avg_monthly_spend
FROM customer_aggregation ca
CROSS JOIN ref r;
GO

-- =============================================================================
-- Product Report
-- =============================================================================
-- Segments products by revenue:
--   High-Performer : total sales >  50,000
--   Mid-Range      : total sales >= 10,000
--   Low-Performer  : otherwise
-- =============================================================================
CREATE OR ALTER VIEW report.products AS
WITH ref AS (
    SELECT MAX(order_date) AS ref_date FROM gold.fact_sales
),
base_query AS (
    /*-----------------------------------------------------------------------
    1) Base query: core columns from fact_sales and dim_products
    -----------------------------------------------------------------------*/
    SELECT
        f.order_number,
        f.order_date,
        f.customer_key,
        f.sales_amount,
        f.quantity,
        p.product_key,
        p.product_name,
        p.category,
        p.subcategory,
        p.cost
    FROM gold.fact_sales f
    INNER JOIN gold.dim_products p ON f.product_key = p.product_key
    WHERE f.order_date IS NOT NULL            -- only valid sales dates
),
product_aggregations AS (
    /*-----------------------------------------------------------------------
    2) Product aggregations: key metrics at the product level
    -----------------------------------------------------------------------*/
    SELECT
        product_key,
        product_name,
        category,
        subcategory,
        cost,
        DATEDIFF(MONTH, MIN(order_date), MAX(order_date)) AS lifespan,
        MAX(order_date)                                   AS last_sale_date,
        COUNT(DISTINCT order_number)                      AS total_orders,
        COUNT(DISTINCT customer_key)                      AS total_customers,
        SUM(sales_amount)                                 AS total_sales,
        SUM(quantity)                                     AS total_quantity,
        ROUND(AVG(CAST(sales_amount AS FLOAT) / NULLIF(quantity, 0)), 1) AS avg_selling_price
    FROM base_query
    GROUP BY product_key, product_name, category, subcategory, cost
)
/*---------------------------------------------------------------------------
3) Final query: segments and KPIs
---------------------------------------------------------------------------*/
SELECT
    pa.product_key,
    pa.product_name,
    pa.category,
    pa.subcategory,
    pa.cost,
    pa.last_sale_date,
    DATEDIFF(MONTH, pa.last_sale_date, r.ref_date) AS recency_in_months,
    CASE
        WHEN pa.total_sales >  50000 THEN 'High-Performer'
        WHEN pa.total_sales >= 10000 THEN 'Mid-Range'
        ELSE 'Low-Performer'
    END AS product_segment,
    pa.lifespan,
    pa.total_orders,
    pa.total_sales,
    pa.total_quantity,
    pa.total_customers,
    pa.avg_selling_price,
    -- Average order revenue
    CAST(1.0 * pa.total_sales / NULLIF(pa.total_orders, 0) AS DECIMAL(18, 2)) AS avg_order_revenue,
    -- Average monthly revenue
    CASE
        WHEN pa.lifespan = 0 THEN CAST(pa.total_sales AS DECIMAL(18, 2))
        ELSE CAST(1.0 * pa.total_sales / pa.lifespan AS DECIMAL(18, 2))
    END AS avg_monthly_revenue
FROM product_aggregations pa
CROSS JOIN ref r;
GO
