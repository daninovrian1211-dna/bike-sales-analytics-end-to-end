/*
===============================================================================
Run All: rebuild the whole data warehouse
===============================================================================
Run the scripts in this order (each file is a separate script, open and execute it):

    -- ONE-TIME SETUP (creates the database and all tables / procedures)
    01_init_database/01_init_database.sql      -- WARNING: drops and recreates the DataWarehouse database
    02_bronze_layer/02_ddl_bronze.sql
    02_bronze_layer/03_proc_load_bronze.sql    -- remember to set your CSV path (see README)
    03_silver_layer/04_ddl_silver.sql
    03_silver_layer/05_proc_load_silver.sql
    04_gold_layer/06_ddl_gold.sql
    04_gold_layer/07_proc_load_gold.sql
    05_report_layer/08_report_views.sql

    -- DATA LOAD (this file): can be re-run at any time to refresh the warehouse
===============================================================================
*/
USE DataWarehouse;
GO

EXEC bronze.load_bronze;   -- CSV files  -> bronze
EXEC silver.load_silver;   -- bronze     -> silver (clean & standardize)
EXEC gold.load_gold;       -- silver     -> gold   (star schema)
GO

-- Sanity check: quick look at the report layer
SELECT TOP 10 * FROM report.customers ORDER BY total_sales DESC;
SELECT TOP 10 * FROM report.products  ORDER BY total_sales DESC;
GO

-- Then run tests/quality_checks_silver.sql and tests/quality_checks_gold.sql
