/*
===============================================================================
DDL Script: Create Gold Tables (Star Schema)
===============================================================================
Script Purpose:
    Creates the physical tables of the Gold layer:
        - gold.dim_customers
        - gold.dim_products
        - gold.dim_date
        - gold.fact_sales

    The tables are populated by the stored procedure gold.load_gold
    (see 07_proc_load_gold.sql).

    Why tables instead of views?
        - Surrogate keys (customer_key, product_key) are generated once per
          load and stay stable between queries. When they were generated with
          ROW_NUMBER() inside a view, they were recomputed on every query.
        - Joins and window functions are not re-executed on every read, which
          makes Power BI refresh and ad-hoc analysis faster.
        - Primary / foreign keys document and enforce the star schema.

WARNING:
    Running this script drops and recreates the Gold tables (and removes the
    old Gold views if they still exist). Run gold.load_gold afterwards.
===============================================================================
*/

USE DataWarehouse;
GO

-- -----------------------------------------------------------------------------
-- Clean up: remove legacy views and existing tables (fact first because of FKs)
-- -----------------------------------------------------------------------------
IF OBJECT_ID('gold.fact_sales',     'V') IS NOT NULL DROP VIEW gold.fact_sales;
IF OBJECT_ID('gold.dim_products',   'V') IS NOT NULL DROP VIEW gold.dim_products;
IF OBJECT_ID('gold.dim_customers',  'V') IS NOT NULL DROP VIEW gold.dim_customers;
IF OBJECT_ID('gold.report_products',  'V') IS NOT NULL DROP VIEW gold.report_products;
IF OBJECT_ID('gold.report_customers', 'V') IS NOT NULL DROP VIEW gold.report_customers;
GO

DROP TABLE IF EXISTS gold.fact_sales;
DROP TABLE IF EXISTS gold.dim_date;
DROP TABLE IF EXISTS gold.dim_products;
DROP TABLE IF EXISTS gold.dim_customers;
GO

-- =============================================================================
-- Dimension: gold.dim_customers
-- =============================================================================
CREATE TABLE gold.dim_customers (
    customer_key    INT           NOT NULL,   -- Surrogate key
    customer_id     INT           NULL,
    customer_number NVARCHAR(50)  NULL,
    first_name      NVARCHAR(50)  NULL,
    last_name       NVARCHAR(50)  NULL,
    country         NVARCHAR(50)  NULL,
    marital_status  NVARCHAR(50)  NULL,
    gender          NVARCHAR(50)  NULL,
    birthdate       DATE          NULL,
    create_date     DATE          NULL,
    CONSTRAINT PK_dim_customers PRIMARY KEY (customer_key)
);
GO

-- =============================================================================
-- Dimension: gold.dim_products
-- =============================================================================
CREATE TABLE gold.dim_products (
    product_key     INT           NOT NULL,   -- Surrogate key
    product_id      INT           NULL,
    product_number  NVARCHAR(50)  NULL,
    product_name    NVARCHAR(50)  NULL,
    category_id     NVARCHAR(50)  NULL,
    category        NVARCHAR(50)  NULL,
    subcategory     NVARCHAR(50)  NULL,
    maintenance     NVARCHAR(50)  NULL,
    cost            INT           NULL,
    product_line    NVARCHAR(50)  NULL,
    start_date      DATE          NULL,
    CONSTRAINT PK_dim_products PRIMARY KEY (product_key)
);
GO

-- =============================================================================
-- Dimension: gold.dim_date  (calendar table, used for time intelligence in BI)
-- =============================================================================
CREATE TABLE gold.dim_date (
    date_key        INT           NOT NULL,   -- yyyymmdd, e.g. 20130131
    full_date       DATE          NOT NULL,
    calendar_year   SMALLINT      NOT NULL,
    calendar_quarter TINYINT      NOT NULL,
    month_number    TINYINT       NOT NULL,
    month_name      NVARCHAR(20)  NOT NULL,
    month_short     NVARCHAR(3)   NOT NULL,
    year_month      CHAR(7)       NOT NULL,   -- yyyy-MM (sortable label)
    day_of_month    TINYINT       NOT NULL,
    weekday_number  TINYINT       NOT NULL,   -- 1 = Monday ... 7 = Sunday
    weekday_name    NVARCHAR(20)  NOT NULL,
    is_weekend      BIT           NOT NULL,
    CONSTRAINT PK_dim_date PRIMARY KEY (date_key),
    CONSTRAINT UQ_dim_date_full_date UNIQUE (full_date)
);
GO

-- =============================================================================
-- Fact: gold.fact_sales
-- =============================================================================
CREATE TABLE gold.fact_sales (
    order_number    NVARCHAR(50)  NULL,
    product_key     INT           NULL,
    customer_key    INT           NULL,
    order_date      DATE          NULL,
    shipping_date   DATE          NULL,
    due_date        DATE          NULL,
    sales_amount    INT           NULL,
    quantity        INT           NULL,
    price           INT           NULL,
    CONSTRAINT FK_fact_sales_customers FOREIGN KEY (customer_key) REFERENCES gold.dim_customers (customer_key),
    CONSTRAINT FK_fact_sales_products  FOREIGN KEY (product_key)  REFERENCES gold.dim_products  (product_key)
);
GO

CREATE INDEX IX_fact_sales_customer_key ON gold.fact_sales (customer_key);
CREATE INDEX IX_fact_sales_product_key  ON gold.fact_sales (product_key);
CREATE INDEX IX_fact_sales_order_date   ON gold.fact_sales (order_date);
GO
