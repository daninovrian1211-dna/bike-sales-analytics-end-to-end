# Power BI Report

Final output of the project: an interactive report built on the Gold star schema.

> Save the report as `bike_sales_dashboard.pbix` in this folder and put page screenshots in `screenshots/`
> (they are linked from the main README).

## 1. Connect to the data

1. Power BI Desktop → **Get data → SQL Server**
2. Server: your instance (e.g. `localhost\SQLEXPRESS`), Database: `DataWarehouse`
3. Data connectivity mode: **Import** (about 60k fact rows and static data, so DirectQuery is not needed)
4. Select these tables:
   - `gold.fact_sales`
   - `gold.dim_customers`
   - `gold.dim_products`
   - `gold.dim_date`
   - `report.customers` *(optional, for customer segment / age group visuals)*
   - `report.products` *(optional, for product segment visuals)*

Refresh the report after every ETL run (`EXEC gold.load_gold`) with **Home → Refresh**.

## 2. Data model

```
dim_customers (1) ───< fact_sales >─── (1) dim_products
                           ^
                           |
                    dim_date (1)
```

| From (many) | To (one) | Active |
|---|---|---|
| `fact_sales[customer_key]` | `dim_customers[customer_key]` | Yes |
| `fact_sales[product_key]` | `dim_products[product_key]` | Yes |
| `fact_sales[order_date]` | `dim_date[full_date]` | Yes |
| `fact_sales[shipping_date]` | `dim_date[full_date]` | No (role-playing, use `USERELATIONSHIP`) |
| `fact_sales[due_date]` | `dim_date[full_date]` | No (role-playing, use `USERELATIONSHIP`) |
| `report.customers[customer_key]` | `dim_customers[customer_key]` | Yes (one-to-one, single direction) |
| `report.products[product_key]` | `dim_products[product_key]` | Yes (one-to-one, single direction) |

Model settings:
- Mark `dim_date` as a **date table** using `full_date`.
- Sort `month_name` by `month_number` and `weekday_name` by `weekday_number`.
- Hide the key columns (`*_key`, `customer_id`, `product_id`) from the report view.
- Set `sales_amount`, `price`, `cost` to *Don't summarize*, and use the measures below instead.

## 3. DAX measures

Create a table called `_Measures` (Home → Enter data, empty) and add:

```DAX
-- Core
Total Sales      = SUM ( fact_sales[sales_amount] )
Total Quantity   = SUM ( fact_sales[quantity] )
Total Orders     = DISTINCTCOUNT ( fact_sales[order_number] )
Total Customers  = DISTINCTCOUNT ( fact_sales[customer_key] )
Avg Order Value  = DIVIDE ( [Total Sales], [Total Orders] )
Avg Selling Price = DIVIDE ( [Total Sales], [Total Quantity] )

-- Profitability (uses the CURRENT unit cost of each product, so treat it as an estimate)
Total Cost       = SUMX ( fact_sales, fact_sales[quantity] * RELATED ( dim_products[cost] ) )
Gross Profit     = [Total Sales] - [Total Cost]
Profit Margin %  = DIVIDE ( [Gross Profit], [Total Sales] )

-- Time intelligence (relationship on order_date)
Sales YTD        = TOTALYTD ( [Total Sales], dim_date[full_date] )
Sales LY         = CALCULATE ( [Total Sales], SAMEPERIODLASTYEAR ( dim_date[full_date] ) )
Sales YoY %      = DIVIDE ( [Total Sales] - [Sales LY], [Sales LY] )
Sales Prev Month = CALCULATE ( [Total Sales], DATEADD ( dim_date[full_date], -1, MONTH ) )
Sales MoM %      = DIVIDE ( [Total Sales] - [Sales Prev Month], [Sales Prev Month] )
Cumulative Sales =
    CALCULATE (
        [Total Sales],
        FILTER ( ALL ( dim_date ), dim_date[full_date] <= MAX ( dim_date[full_date] ) )
    )

-- Share of total
Sales % of Total = DIVIDE ( [Total Sales], CALCULATE ( [Total Sales], ALLSELECTED () ) )

-- Role-playing date (shipping date instead of order date)
Sales by Ship Date =
    CALCULATE ( [Total Sales], USERELATIONSHIP ( fact_sales[shipping_date], dim_date[full_date] ) )

-- Customer / product segmentation (from the report views)
VIP Customers =
    CALCULATE ( DISTINCTCOUNT ( report_customers[customer_key] ), report_customers[customer_segment] = "VIP" )
High-Performer Products =
    CALCULATE ( DISTINCTCOUNT ( report_products[product_key] ), report_products[product_segment] = "High-Performer" )
```

> If Power BI names the imported views `customers` / `products`, adjust the table names above,
> or rename them in Power Query to `report_customers` / `report_products`.

## 4. Report pages

**Page 1 – Executive Overview**
- KPI cards: Total Sales, Total Orders, Total Customers, Avg Order Value, Sales YoY %
- Line chart: Total Sales by `year_month` (+ Cumulative Sales as a second line)
- Column chart: Total Sales by `category`
- Map / bar: Total Sales by `country`
- Slicers: `calendar_year`, `category`, `country`

**Page 2 – Product Performance**
- Matrix: `category` → `subcategory` → `product_name` with Total Sales, Total Quantity, Sales % of Total
- Donut / bar: number of products by `product_segment` (High-Performer / Mid-Range / Low-Performer)
- Scatter: Avg Selling Price vs Total Quantity, size = Total Sales
- Slicers: `category`, `product_line`, `maintenance`

**Page 3 – Customer Insights**
- KPI cards: Total Customers, VIP Customers, Avg Monthly Spend
- Column chart: Total Customers by `customer_segment`
- Column chart: Total Sales by `age_group`
- Bar chart: Total Sales by `gender` and `marital_status`
- Table: Top 10 customers by Total Sales (`customer_name`, `total_orders`, `total_sales`, `recency_in_months`)

## 5. Things to know about the data

- Orders span **29 Dec 2010 to 28 Jan 2014**. **2010 and 2014 are partial years** (14 and about 1,970 order lines).
  Volume also jumps sharply in 2013, which holds about 87% of all order lines, so year-over-year growth for 2012 and 2013
  looks extreme. Add a short note on the page instead of presenting it as organic growth.
- A few order lines have no valid order date and are excluded from time-based visuals by the date relationship.
- Use `bike_sales_theme.json` (View → Themes → Browse for themes) for consistent colours.
