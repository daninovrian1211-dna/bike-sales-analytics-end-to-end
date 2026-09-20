/*
===============================================================================
Stored Procedure: Load Gold Layer (Silver -> Gold)
===============================================================================
Script Purpose:
    Populates the Gold star schema from the Silver layer:
        1. gold.dim_customers  (CRM customers enriched with ERP data)
        2. gold.dim_products   (current CRM products enriched with ERP categories)
        3. gold.fact_sales     (CRM sales lines linked to the dimensions)
        4. gold.dim_date       (calendar covering all dates found in the fact table)

    Behaviour:
        - Full reload: all Gold tables are emptied and refilled on every run.
        - Everything runs in ONE transaction, so surrogate keys always come from
          the same snapshot and a failed run leaves the previous data untouched.

Parameters:
    None.

Usage Example:
    EXEC gold.load_gold;

Prerequisite:
    06_ddl_gold.sql has been executed and silver.load_silver has been run.
===============================================================================
*/
USE DataWarehouse;
GO

CREATE OR ALTER PROCEDURE gold.load_gold AS
BEGIN
    DECLARE @start_time DATETIME, @batch_start_time DATETIME, @batch_end_time DATETIME;
    DECLARE @min_date DATE, @max_date DATE;

    BEGIN TRY
        SET @batch_start_time = GETDATE();
        PRINT '================================================';
        PRINT 'Loading Gold Layer';
        PRINT '================================================';

        BEGIN TRAN;

        -- ---------------------------------------------------------------------
        -- Empty the tables (child table first because of the foreign keys)
        -- ---------------------------------------------------------------------
        DELETE FROM gold.fact_sales;
        DELETE FROM gold.dim_date;
        DELETE FROM gold.dim_products;
        DELETE FROM gold.dim_customers;

        -- ---------------------------------------------------------------------
        -- 1) gold.dim_customers
        -- ---------------------------------------------------------------------
        SET @start_time = GETDATE();
        PRINT '>> Inserting Data Into: gold.dim_customers';

        INSERT INTO gold.dim_customers (
            customer_key, customer_id, customer_number, first_name, last_name,
            country, marital_status, gender, birthdate, create_date
        )
        SELECT
            ROW_NUMBER() OVER (ORDER BY ci.cst_id) AS customer_key,   -- Surrogate key
            ci.cst_id                              AS customer_id,
            ci.cst_key                             AS customer_number,
            ci.cst_firstname                       AS first_name,
            ci.cst_lastname                        AS last_name,
            la.cntry                               AS country,
            ci.cst_marital_status                  AS marital_status,
            CASE
                WHEN ci.cst_gndr != 'n/a' THEN ci.cst_gndr            -- CRM is the primary source for gender
                ELSE COALESCE(ca.gen, 'n/a')                          -- Fallback to ERP data
            END                                    AS gender,
            ca.bdate                               AS birthdate,
            ci.cst_create_date                     AS create_date
        FROM silver.crm_cust_info ci
        LEFT JOIN silver.erp_cust_az12 ca ON ci.cst_key = ca.cid
        LEFT JOIN silver.erp_loc_a101  la ON ci.cst_key = la.cid;

        PRINT '>> Rows loaded: ' + CAST(@@ROWCOUNT AS NVARCHAR(20));
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, GETDATE()) AS NVARCHAR(20)) + ' seconds';
        PRINT '>> -------------';

        -- ---------------------------------------------------------------------
        -- 2) gold.dim_products
        -- ---------------------------------------------------------------------
        SET @start_time = GETDATE();
        PRINT '>> Inserting Data Into: gold.dim_products';

        INSERT INTO gold.dim_products (
            product_key, product_id, product_number, product_name, category_id,
            category, subcategory, maintenance, cost, product_line, start_date
        )
        SELECT
            ROW_NUMBER() OVER (ORDER BY pn.prd_start_dt, pn.prd_key) AS product_key,  -- Surrogate key
            pn.prd_id       AS product_id,
            pn.prd_key      AS product_number,
            pn.prd_nm       AS product_name,
            pn.cat_id       AS category_id,
            pc.cat          AS category,
            pc.subcat       AS subcategory,
            pc.maintenance  AS maintenance,
            pn.prd_cost     AS cost,
            pn.prd_line     AS product_line,
            pn.prd_start_dt AS start_date
        FROM silver.crm_prd_info pn
        LEFT JOIN silver.erp_px_cat_g1v2 pc ON pn.cat_id = pc.id
        WHERE pn.prd_end_dt IS NULL;                                  -- Keep current products only

        PRINT '>> Rows loaded: ' + CAST(@@ROWCOUNT AS NVARCHAR(20));
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, GETDATE()) AS NVARCHAR(20)) + ' seconds';
        PRINT '>> -------------';

        -- ---------------------------------------------------------------------
        -- 3) gold.fact_sales (looks up the surrogate keys generated above)
        -- ---------------------------------------------------------------------
        SET @start_time = GETDATE();
        PRINT '>> Inserting Data Into: gold.fact_sales';

        INSERT INTO gold.fact_sales (
            order_number, product_key, customer_key, order_date, shipping_date,
            due_date, sales_amount, quantity, price
        )
        SELECT
            sd.sls_ord_num  AS order_number,
            pr.product_key  AS product_key,
            cu.customer_key AS customer_key,
            sd.sls_order_dt AS order_date,
            sd.sls_ship_dt  AS shipping_date,
            sd.sls_due_dt   AS due_date,
            sd.sls_sales    AS sales_amount,
            sd.sls_quantity AS quantity,
            sd.sls_price    AS price
        FROM silver.crm_sales_details sd
        LEFT JOIN gold.dim_products  pr ON sd.sls_prd_key = pr.product_number
        LEFT JOIN gold.dim_customers cu ON sd.sls_cust_id = cu.customer_id;

        PRINT '>> Rows loaded: ' + CAST(@@ROWCOUNT AS NVARCHAR(20));
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, GETDATE()) AS NVARCHAR(20)) + ' seconds';
        PRINT '>> -------------';

        -- ---------------------------------------------------------------------
        -- 4) gold.dim_date (full calendar years covering every fact date)
        -- ---------------------------------------------------------------------
        SET @start_time = GETDATE();
        PRINT '>> Inserting Data Into: gold.dim_date';

        SELECT
            @min_date = DATEFROMPARTS(YEAR(MIN(v.d)), 1, 1),
            @max_date = DATEFROMPARTS(YEAR(MAX(v.d)), 12, 31)
        FROM gold.fact_sales f
        CROSS APPLY (VALUES (f.order_date), (f.shipping_date), (f.due_date)) AS v(d);

        IF @min_date IS NOT NULL
        BEGIN
            WITH dates AS (
                SELECT @min_date AS d
                UNION ALL
                SELECT DATEADD(DAY, 1, d) FROM dates WHERE d < @max_date
            )
            INSERT INTO gold.dim_date (
                date_key, full_date, calendar_year, calendar_quarter, month_number,
                month_name, month_short, year_month, day_of_month,
                weekday_number, weekday_name, is_weekend
            )
            SELECT
                CONVERT(INT, FORMAT(d.d, 'yyyyMMdd'))        AS date_key,
                d.d                                          AS full_date,
                YEAR(d.d)                                    AS calendar_year,
                DATEPART(QUARTER, d.d)                       AS calendar_quarter,
                MONTH(d.d)                                   AS month_number,
                FORMAT(d.d, 'MMMM', 'en-US')                 AS month_name,
                FORMAT(d.d, 'MMM',  'en-US')                 AS month_short,
                FORMAT(d.d, 'yyyy-MM')                       AS year_month,
                DAY(d.d)                                     AS day_of_month,
                w.wd                                         AS weekday_number,
                FORMAT(d.d, 'dddd', 'en-US')                 AS weekday_name,
                CASE WHEN w.wd >= 6 THEN 1 ELSE 0 END        AS is_weekend
            FROM dates d
            CROSS APPLY (VALUES (((DATEPART(WEEKDAY, d.d) + @@DATEFIRST - 2) % 7) + 1)) AS w(wd)  -- 1 = Monday, independent of DATEFIRST
            OPTION (MAXRECURSION 0);
        END;

        DECLARE @rows_loaded INT;
        SELECT @rows_loaded = COUNT(*)
        FROM gold.dim_date;
        PRINT '>> Rows loaded: ' + CAST(@rows_loaded AS NVARCHAR(20));
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, GETDATE()) AS NVARCHAR(20)) + ' seconds';
        PRINT '>> -------------';

        COMMIT TRAN;

        SET @batch_end_time = GETDATE();
        PRINT '==========================================';
        PRINT 'Loading Gold Layer is Completed';
        PRINT '   - Total Load Duration: ' + CAST(DATEDIFF(SECOND, @batch_start_time, @batch_end_time) AS NVARCHAR(20)) + ' seconds';
        PRINT '==========================================';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        PRINT '==========================================';
        PRINT 'ERROR OCCURED DURING LOADING GOLD LAYER';
        PRINT 'Error Message: ' + ERROR_MESSAGE();
        PRINT 'Error Number: '  + CAST(ERROR_NUMBER() AS NVARCHAR(20));
        PRINT 'Error State: '   + CAST(ERROR_STATE()  AS NVARCHAR(20));
        PRINT '==========================================';
        THROW;
    END CATCH
END;
GO
