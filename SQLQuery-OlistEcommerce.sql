Use BrazilianEcommerce

;WITH DataAudit AS (
    -- 1. Customers Table
    SELECT 
        'Customers' AS TableName,
        COUNT(*) AS TotalRows,
        SUM(CASE WHEN ["customer_id"] IS NULL THEN 1 ELSE 0 END) AS MissingPrimaryKeys,
        (COUNT(*) - COUNT(DISTINCT ["customer_id"] )) AS DuplicateRows
    FROM olist_customers_dataset 

    UNION ALL

    -- 2. Geolocation Table
    SELECT 
        'Geolocation' AS TableName,
        COUNT(*) AS TotalRows,
        SUM(CASE WHEN ["geolocation_zip_code_prefix"] IS NULL THEN 1 ELSE 0 END) AS MissingPrimaryKeys,
        -- Geolocation maps many coordinates to a zip code, checking composite duplicate rows
        (COUNT(*) - COUNT(DISTINCT CONCAT(["geolocation_zip_code_prefix"], '_', ["geolocation_lat"], '_', ["geolocation_lng"]))) AS DuplicateRows
    FROM olist_geolocation_dataset 

    UNION ALL

    -- 3. Order Items Table
    SELECT 
        'Order Items' AS TableName,
        COUNT(*) AS TotalRows,
        SUM(CASE WHEN ["order_id"] IS NULL OR ["order_item_id"] IS NULL THEN 1 ELSE 0 END) AS MissingPrimaryKeys,
        (COUNT(*) - COUNT(DISTINCT CONCAT(["order_id"], '_', ["order_item_id"]))) AS DuplicateRows
    FROM olist_order_items_dataset 

    UNION ALL

    -- 4. Order Payments Table
    SELECT 
        'Order Payments' AS TableName,
        COUNT(*) AS TotalRows,
        SUM(CASE WHEN ["order_id"] IS NULL OR ["payment_sequential"] IS NULL THEN 1 ELSE 0 END) AS MissingPrimaryKeys,
        (COUNT(*) - COUNT(DISTINCT CONCAT(["order_id"], '_', ["payment_sequential"]))) AS DuplicateRows
    FROM olist_order_payments_dataset 
    UNION ALL

    -- 5. Order Reviews Table
    SELECT 
        'Order Reviews' AS TableName,
        COUNT(*) AS TotalRows,
        SUM(CASE WHEN review_id IS NULL THEN 1 ELSE 0 END) AS MissingPrimaryKeys,
        (COUNT(*) - COUNT(DISTINCT review_id)) AS DuplicateRows
    FROM olist_order_reviews_dataset 

    UNION ALL

    -- 6. Orders Table
    SELECT 
        'Orders' AS TableName,
        COUNT(*) AS TotalRows,
        SUM(CASE WHEN ["order_id"] IS NULL THEN 1 ELSE 0 END) AS MissingPrimaryKeys,
        (COUNT(*) - COUNT(DISTINCT ["order_id"])) AS DuplicateRows
    FROM olist_orders_dataset 

    UNION ALL

    -- 7. Products Table
    SELECT 
        'Products' AS TableName,
        COUNT(*) AS TotalRows,
        SUM(CASE WHEN ["product_id"] IS NULL THEN 1 ELSE 0 END) AS MissingPrimaryKeys,
        (COUNT(*) - COUNT(DISTINCT ["product_id"])) AS DuplicateRows
    FROM olist_products_dataset 

    UNION ALL

    -- 8. Sellers Table
    SELECT 
        'Sellers' AS TableName,
        COUNT(*) AS TotalRows,
        SUM(CASE WHEN ["seller_id"] IS NULL THEN 1 ELSE 0 END) AS MissingPrimaryKeys,
        (COUNT(*) - COUNT(DISTINCT ["seller_id"])) AS DuplicateRows
    FROM olist_sellers_dataset 

    UNION ALL

    -- 9. Product Category Name Translation Table
    SELECT 
        'Category Translation' AS TableName,
        COUNT(*) AS TotalRows,
        SUM(CASE WHEN product_category_name IS NULL THEN 1 ELSE 0 END) AS MissingPrimaryKeys,
        (COUNT(*) - COUNT(DISTINCT product_category_name)) AS DuplicateRows
    FROM product_category_name_translation 
)
SELECT 
    TableName AS [Table Name],
    TotalRows AS [Total Records],
    MissingPrimaryKeys AS [Missing Key Values (NULLs)],
    DuplicateRows AS [Duplicate Records Found]
FROM DataAudit
ORDER BY [Total Records] DESC;

 -- Multiple customers can share a geographic location, but the olist_geolocation_dataset is a standalone coordinate lookup map rather than a user registry. The raw table contained rows where the exact same zip code, latitude, and longitude were repeated multiple times. Removing these absolute identical rows eliminates data redundancy, protects system performance, and downsizes the table without deleting any actual customers

-- A. View the exact duplicate entries:
 select 
    ["geolocation_zip_code_prefix"], 
    ["geolocation_lat"], 
    ["geolocation_lng"],
    COUNT(*) AS occurrence_count
FROM olist_geolocation_dataset 
GROUP BY ["geolocation_zip_code_prefix"], ["geolocation_lat"], ["geolocation_lng"]
HAVING COUNT(*) > 1
ORDER BY occurrence_count DESC;

--B. Remove the duplicates permanently (Keeps only 1 original row):
;WITH CTE_GeoDuplicates AS (
    SELECT 
        ["geolocation_zip_code_prefix"],
        ROW_NUMBER() OVER (
            PARTITION BY ["geolocation_zip_code_prefix"], ["geolocation_lat"], ["geolocation_lng"]
            ORDER BY (SELECT NULL)
        ) AS row_num
    FROM olist_geolocation_dataset
)
DELETE FROM CTE_GeoDuplicates
WHERE row_num > 1

--Unlike the coordinate map, duplicate IDs in the olist_order_reviews_dataset should not be deleted. Multiple records sharing an identical review_id occur naturally when a customer reviews an order containing multiple distinct products. Performing a blind deduplication here would accidentally drop valid transaction data. We must preserve these rows as-is and instead apply conditional aggregates like DISTINCT or MAX() during metric calculations to avoid double-counting review scores.

 -- A. View the exact duplicate entries:
SELECT 
    review_id, 
    COUNT(*) AS [Occurrence Count]
FROM olist_order_reviews_dataset 
GROUP BY review_id
HAVING COUNT(*) > 1
ORDER BY [Occurrence Count] DESC;

--B. Remove the duplicates permanently (Keeps only 1 original row):

;WITH DeduplicatedReviews AS (
    SELECT 
        review_id,
        order_id,
        review_score,
        -- Tag the first occurrence of each review_id to prevent double-counting
        ROW_NUMBER() OVER (
            PARTITION BY review_id 
            ORDER BY review_creation_date DESC
        ) AS RowNum
    FROM olist_order_reviews_dataset
	)
SELECT 
    -- 1. Count all rows vs only unique review IDs
    COUNT(*) AS [Total Rows Preserved],
    COUNT(DISTINCT review_id) AS [Total Unique Reviews],
    
    -- 2. Calculate the average score safely by skipping duplicates
    AVG(CASE WHEN RowNum = 1 THEN CAST(review_score AS DECIMAL(10,2)) END) AS [Safe Average Review Score]

FROM DeduplicatedReviews;

-- Checking Missing Values (nulls) in non primary Columns

;WITH NullAudit AS (
    -- 1. Orders Table: Check for missing delivery or approval timestamps
    SELECT 
        'Orders' AS TableName,
        'order_approved_at' AS ColumnName,
        SUM(CASE WHEN ["order_approved_at"] IS NULL THEN 1 ELSE 0 END) AS MissingCount
    FROM olist_orders_dataset 
    UNION ALL
    SELECT 'Orders', 'order_delivered_carrier_date', SUM(CASE WHEN ["order_delivered_carrier_date"] IS NULL THEN 1 ELSE 0 END) FROM olist_orders_dataset 
    UNION ALL
    SELECT 'Orders', 'order_delivered_customer_date', SUM(CASE WHEN ["order_delivered_customer_date"] IS NULL THEN 1 ELSE 0 END) FROM olist_orders_dataset 

    UNION ALL

    -- 2. Products Table: Check for missing physical dimensions or category names
    SELECT 
        'Products' AS TableName,
        'product_category_name' AS ColumnName,
        SUM(CASE WHEN ["product_category_name"] IS NULL THEN 1 ELSE 0 END) AS MissingCount
    FROM olist_products_dataset 
    UNION ALL
    SELECT 'Products', 'product_weight_g', SUM(CASE WHEN ["product_weight_g"] IS NULL THEN 1 ELSE 0 END) FROM olist_products_dataset 

    UNION ALL

    -- 3. Order Reviews Table: Check how many reviews left scores but skipped text comments
    SELECT 
        'Order Reviews' AS TableName,
        'review_comment_title' AS ColumnName,
        SUM(CASE WHEN review_comment_title IS NULL THEN 1 ELSE 0 END) AS MissingCount
    FROM olist_order_reviews_dataset 
    UNION ALL
    SELECT 'Order Reviews', 'review_comment_message', SUM(CASE WHEN review_comment_message IS NULL THEN 1 ELSE 0 END) FROM olist_order_reviews_dataset
)
SELECT 
    TableName AS [Table Name],
    ColumnName AS [Column Name],
    MissingCount AS [Count of NULL Values]
FROM NullAudit
WHERE MissingCount > 0
ORDER BY [Count of NULL Values] DESC;

SELECT 
    review_id,
    review_score,
    -- If title is NULL, replace it with 'No Title'
    ISNULL(review_comment_title, 'No Title') AS CleanTitle,
    
    -- If message is NULL, replace it with 'Rating Only'
    ISNULL(review_comment_message, 'Rating Only') AS CleanMessage
FROM olist_order_reviews_dataset;







If OBJECT_ID('vw_order_commercial','v') is not null
drop View vw_order_commercial;
go
Create view vw_order_commercial AS

WITH item_summary AS (
    SELECT 
        ["order_id"],
        COUNT(["order_item_id"]) AS total_items,
        SUM(CAST(["price"] AS DECIMAL(10,2))) AS total_price,
        SUM(CAST(["freight_value"] AS DECIMAL(10,2))) AS total_freight,
        SUM(CAST(["price"] AS DECIMAL(10,2)) + CAST(["freight_value"] AS DECIMAL(10,2))) AS total_Sales
    FROM olist_order_items_dataset
    GROUP BY ["order_id"]
),
payment_summary AS (
    SELECT 
        ["order_id"],
        SUM(CAST(["payment_value"] AS DECIMAL(10,2))) AS total_payment_value,
        STRING_AGG(["payment_type"], ', ') AS payment_types
    FROM olist_order_payments_dataset
    GROUP BY ["order_id"]
)
SELECT 
    o.["order_id"],
    o.["customer_id"],
    c.["customer_unique_id"],
    o.["order_status"],
    o.["order_purchase_timestamp"],
    o.["order_approved_at"],
    o.["order_delivered_carrier_date"],
    o.["order_delivered_customer_date"],
    o.["order_estimated_delivery_date"],
    i.total_items,
    i.total_price,
    i.total_freight,
    i.total_Sales,
    p.total_payment_value,
    p.payment_types,
    c.["customer_city"],
    c.["customer_state"]
FROM olist_orders_dataset o
LEFT JOIN olist_customers_dataset c 
    ON o.["customer_id"] = c.["customer_id"]
LEFT JOIN item_summary i 
    ON o.["order_id"] = i.["order_id"]
LEFT JOIN payment_summary p 
    ON o.["order_id"] = p.["order_id"];

	select * from vw_order_commercial


	IF OBJECT_ID('vw_category_performance', 'V') IS NOT NULL
    DROP VIEW vw_category_performance;
GO

CREATE VIEW vw_category_performance AS
WITH category_metrics AS (
    SELECT 
        p.["product_category_name"] AS category_name,
		COUNT(DISTINCT oi.["order_id"]) AS total_orders,
        COUNT(oi.["order_item_id"]) AS total_items_sold,
        
        -- Cleaned: casting handles the 2-decimal precision implicitly
        SUM(CAST(oi.["price"] AS DECIMAL(10,2)) + (Cast(oi.["freight_value"] as decimal(10,2)))) AS total_sales_value,
        CAST(SUM(CAST(oi.["price"] AS DECIMAL(10,2))) / COUNT(DISTINCT oi.["order_id"]) AS DECIMAL(10,2)) AS average_order_value
    FROM 
        olist_order_items_dataset oi
    JOIN 
        olist_products_dataset p ON oi.["product_id"] = p.["product_id"]
    JOIN 
        olist_orders_dataset o ON oi.["order_id"] = o.["order_id"]
	
    WHERE 
        o.["order_status"] = 'delivered'
        AND p.["product_category_name"] IS NOT NULL
    GROUP BY 
        p.["product_category_name"]
		
),
performance_calculations AS (
    SELECT
        category_name,
        total_orders,
        total_sales_value,
        average_order_value,
        
        RANK() OVER (ORDER BY total_sales_value DESC) AS rank_by_sales_value,
        RANK() OVER (ORDER BY total_orders DESC) AS rank_by_order_volume,
        
        -- Cleaned: Using direct CAST for the percentage output formatting
        CAST((total_sales_value / SUM(total_sales_value) OVER ()) * 100 AS DECIMAL(5,2)) AS pct_contribution_to_total_sales
    FROM
        category_metrics
)

SELECT
    COALESCE(t.[product_category_name_english], pc.category_name) AS product_category_name_english,
    total_orders,
    total_sales_value,
    average_order_value,
    rank_by_sales_value,
    rank_by_order_volume,
    pct_contribution_to_total_sales
FROM
    performance_calculations pc
	LEFT JOIN product_category_name_translation t
    ON pc.category_name = t.[product_category_name];


	IF OBJECT_ID('vw_delivery_and_satisfaction', 'V') IS NOT NULL
    DROP VIEW vw_delivery_and_satisfaction;
go

CREATE VIEW vw_delivery_and_satisfaction AS
SELECT 
    o.["order_id"],
    o.["customer_id"],
    oi.["seller_id"],
    p.["product_category_name"],
    o.["order_purchase_timestamp"],
    o.["order_delivered_customer_date"],
    o.["order_estimated_delivery_date"],
    DATEDIFF(day, o.["order_purchase_timestamp"], o.["order_delivered_customer_date"]) AS actual_delivery_days,
    DATEDIFF(day, o.["order_purchase_timestamp"], o.["order_estimated_delivery_date"]) AS estimated_delivery_days,
    DATEDIFF(day, o.["order_estimated_delivery_date"], o.["order_delivered_customer_date"]) AS days_delayed,

    -- Delivery Performance Rates (Task 1)
    CASE WHEN o.["order_delivered_customer_date"] <= o.["order_estimated_delivery_date"] THEN 'On-Time' ELSE 'Late' END AS delivery_status,
    r.review_score
    

FROM olist_orders_dataset o
INNER JOIN olist_order_items_dataset oi 
    ON o.["order_id"] = oi.["order_id"]
INNER JOIN olist_products_dataset p 
    ON oi.["product_id"] = p.["product_id"]
LEFT JOIN olist_order_reviews_dataset r 
    ON o.["order_id"] = r.order_id
WHERE o.["order_status"] = 'delivered'; -- Focus analysis on completed deliveries
go

select * from vw_delivery_and_satisfaction;




	
GO

select * from vw_category_performance;
