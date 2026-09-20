# Data Catalog for Gold Layer

## Overview
The Gold Layer is the business-level data representation, structured to support analytical and reporting use cases. It consists of **dimension tables** and **fact tables** (physical tables loaded by `gold.load_gold`) for specific business metrics. The `report` schema on top of it exposes two pre-aggregated views: `report.customers` and `report.products`.

---

### 1. **gold.dim_customers**
- **Purpose:** Stores customer details enriched with demographic and geographic data.
- **Columns:**

| Column Name      | Data Type     | Description                                                                                   |
|------------------|---------------|-----------------------------------------------------------------------------------------------|
| customer_key     | INT           | Surrogate key uniquely identifying each customer record in the dimension table.               |
| customer_id      | INT           | Unique numerical identifier assigned to each customer.                                        |
| customer_number  | NVARCHAR(50)  | Alphanumeric identifier representing the customer, used for tracking and referencing.         |
| first_name       | NVARCHAR(50)  | The customer's first name, as recorded in the system.                                         |
| last_name        | NVARCHAR(50)  | The customer's last name or family name.                                                     |
| country          | NVARCHAR(50)  | The country of residence for the customer (e.g., 'Australia').                               |
| marital_status   | NVARCHAR(50)  | The marital status of the customer (e.g., 'Married', 'Single').                              |
| gender           | NVARCHAR(50)  | The gender of the customer (e.g., 'Male', 'Female', 'n/a').                                  |
| birthdate        | DATE          | The date of birth of the customer, formatted as YYYY-MM-DD (e.g., 1971-10-06).               |
| create_date      | DATE          | The date and time when the customer record was created in the system|

---

### 2. **gold.dim_products**
- **Purpose:** Provides information about the products and their attributes.
- **Columns:**

| Column Name         | Data Type     | Description                                                                                   |
|---------------------|---------------|-----------------------------------------------------------------------------------------------|
| product_key         | INT           | Surrogate key uniquely identifying each product record in the product dimension table.         |
| product_id          | INT           | A unique identifier assigned to the product for internal tracking and referencing.            |
| product_number      | NVARCHAR(50)  | A structured alphanumeric code representing the product, often used for categorization or inventory. |
| product_name        | NVARCHAR(50)  | Descriptive name of the product, including key details such as type, color, and size.         |
| category_id         | NVARCHAR(50)  | A unique identifier for the product's category, linking to its high-level classification.     |
| category            | NVARCHAR(50)  | The broader classification of the product (e.g., Bikes, Components) to group related items.  |
| subcategory         | NVARCHAR(50)  | A more detailed classification of the product within the category, such as product type.      |
| maintenance         | NVARCHAR(50)  | Indicates whether the product requires maintenance (e.g., 'Yes', 'No').                       |
| cost                | INT           | The cost or base price of the product, measured in monetary units.                            |
| product_line        | NVARCHAR(50)  | The specific product line or series to which the product belongs (e.g., Road, Mountain).      |
| start_date          | DATE          | The date when the product became available for sale or use, stored in|

---

### 3. **gold.fact_sales**
- **Purpose:** Stores transactional sales data for analytical purposes.
- **Columns:**

| Column Name     | Data Type     | Description                                                                                   |
|-----------------|---------------|-----------------------------------------------------------------------------------------------|
| order_number    | NVARCHAR(50)  | A unique alphanumeric identifier for each sales order (e.g., 'SO54496').                      |
| product_key     | INT           | Surrogate key linking the order to the product dimension table.                               |
| customer_key    | INT           | Surrogate key linking the order to the customer dimension table.                              |
| order_date      | DATE          | The date when the order was placed.                                                           |
| shipping_date   | DATE          | The date when the order was shipped to the customer.                                          |
| due_date        | DATE          | The date when the order payment was due.                                                      |
| sales_amount    | INT           | The total monetary value of the sale for the line item, in whole currency units (e.g., 25).   |
| quantity        | INT           | The number of units of the product ordered for the line item (e.g., 1).                       |
| price           | INT           | The price per unit of the product for the line item, in whole currency units (e.g., 25).      |

---

### 4. **gold.dim_date**
- **Purpose:** Calendar dimension used for time analysis and time-intelligence measures in Power BI. Covers every full calendar year found in the sales data.
- **Columns:**

| Column Name      | Data Type     | Description                                                          |
|------------------|---------------|----------------------------------------------------------------------|
| date_key         | INT           | Surrogate key in `yyyymmdd` format (e.g., 20130131).                 |
| full_date        | DATE          | The calendar date. Joins to `fact_sales.order_date`.                 |
| calendar_year    | SMALLINT      | Calendar year (e.g., 2013).                                          |
| calendar_quarter | TINYINT       | Quarter of the year (1-4).                                           |
| month_number     | TINYINT       | Month of the year (1-12).                                            |
| month_name       | NVARCHAR(20)  | Full month name (e.g., 'January').                                   |
| month_short      | NVARCHAR(3)   | Abbreviated month name (e.g., 'Jan').                                |
| year_month       | CHAR(7)       | Sortable year-month label (e.g., '2013-01').                         |
| day_of_month     | TINYINT       | Day of the month (1-31).                                             |
| weekday_number   | TINYINT       | Day of the week, 1 = Monday ... 7 = Sunday.                          |
| weekday_name     | NVARCHAR(20)  | Full weekday name (e.g., 'Monday').                                  |
| is_weekend       | BIT           | 1 for Saturday and Sunday, otherwise 0.                              |

---

## Report Layer (views)

Reference date for all "recency" and "age" calculations is the most recent order date in the data.

### 5. **report.customers** (one row per customer)
| Column Name        | Description                                                                                  |
|--------------------|----------------------------------------------------------------------------------------------|
| customer_key       | Surrogate key from `gold.dim_customers`.                                                     |
| customer_number    | Business identifier of the customer.                                                         |
| customer_name      | First and last name.                                                                         |
| age / age_group    | Age in completed years and its bucket (Under 20, 20-29, 30-39, 40-49, 50 and above, n/a).    |
| customer_segment   | VIP (lifespan >= 12 months and sales > 5,000), Regular (lifespan >= 12 months), New (other). |
| last_order_date    | Date of the customer's most recent order.                                                    |
| recency_in_months  | Months between the last order and the reference date.                                        |
| total_orders, total_sales, total_quantity, total_products | Aggregated purchase metrics.                  |
| lifespan           | Months between the first and last order.                                                     |
| avg_order_value    | total_sales / total_orders.                                                                  |
| avg_monthly_spend  | total_sales / lifespan (total_sales when lifespan is 0).                                     |

### 6. **report.products** (one row per product)
| Column Name         | Description                                                                              |
|---------------------|------------------------------------------------------------------------------------------|
| product_key, product_name, category, subcategory, cost | Product attributes from `gold.dim_products`.       |
| last_sale_date      | Date of the most recent sale.                                                            |
| recency_in_months   | Months between the last sale and the reference date.                                     |
| product_segment     | High-Performer (sales > 50,000), Mid-Range (>= 10,000), Low-Performer (other).            |
| lifespan            | Months between the first and last sale.                                                  |
| total_orders, total_sales, total_quantity, total_customers | Aggregated sales metrics.                     |
| avg_selling_price   | Average of sales_amount / quantity per order line.                                       |
| avg_order_revenue   | total_sales / total_orders.                                                              |
| avg_monthly_revenue | total_sales / lifespan (total_sales when lifespan is 0).                                 |
