
-- =================================================================
-- MIGRATION SCRIPT: MATERIALIZED VIEWS
-- =================================================================
-- This script creates materialized views to significantly improve
-- the performance of analytical queries and the dashboard.
-- It should be run once after the initial database setup.
-- =================================================================

-- Step 1: Create a materialized view for daily sales data
-- This pre-aggregates sales data by day, which is expensive to calculate on the fly.
CREATE MATERIALIZED VIEW IF NOT EXISTS public.daily_sales_stats AS
SELECT
    o.company_id,
    DATE(o.created_at) AS sale_date,
    COUNT(DISTINCT o.id) AS total_orders,
    SUM(oli.quantity) AS total_items_sold,
    SUM(oli.price * oli.quantity) AS gross_revenue,
    SUM(oli.total_discount) AS total_discounts,
    SUM((oli.price * oli.quantity) - oli.total_discount) AS net_revenue,
    SUM(oli.cost_at_time * oli.quantity) AS total_cogs,
    SUM((oli.price * oli.quantity) - oli.total_discount - (oli.cost_at_time * oli.quantity)) AS total_profit
FROM
    public.orders o
JOIN
    public.order_line_items oli ON o.id = oli.order_id
GROUP BY
    o.company_id,
    DATE(o.created_at)
WITH DATA;

-- Create an index for faster lookups by company and date
CREATE UNIQUE INDEX IF NOT EXISTS idx_daily_sales_stats_company_date ON public.daily_sales_stats(company_id, sale_date);


-- Step 2: Create a materialized view for product-level sales statistics
-- This pre-calculates key metrics for each product variant.
CREATE MATERIALIZED VIEW IF NOT EXISTS public.product_sales_stats AS
SELECT
    pv.company_id,
    pv.id as variant_id,
    p.id as product_id,
    p.title as product_name,
    pv.sku,
    SUM(oli.quantity) AS total_quantity_sold,
    SUM(oli.price * oli.quantity) AS total_revenue,
    SUM((oli.price * oli.quantity) - (oli.cost_at_time * oli.quantity)) AS total_profit,
    MIN(o.created_at) as first_sale_date,
    MAX(o.created_at) as last_sale_date,
    COUNT(DISTINCT o.id) as total_orders
FROM
    public.product_variants pv
JOIN
    public.products p ON pv.product_id = p.id
LEFT JOIN
    public.order_line_items oli ON pv.id = oli.variant_id
LEFT JOIN
    public.orders o ON oli.order_id = o.id
GROUP BY
    pv.company_id,
    pv.id,
    p.id
WITH DATA;

-- Create indexes for faster lookups
CREATE UNIQUE INDEX IF NOT EXISTS idx_product_sales_stats_company_variant ON public.product_sales_stats(company_id, variant_id);
CREATE INDEX IF NOT EXISTS idx_product_sales_stats_company_product ON public.product_sales_stats(company_id, product_id);
CREATE INDEX IF NOT EXISTS idx_product_sales_stats_company_sku ON public.product_sales_stats(company_id, sku);


-- Step 3: Create a materialized view for customer-level statistics
-- This pre-calculates lifetime value and other metrics for each customer.
CREATE MATERIALIZED VIEW IF NOT EXISTS public.customer_stats AS
SELECT
    c.company_id,
    c.id as customer_id,
    c.customer_name,
    c.email,
    COUNT(DISTINCT o.id) AS total_orders,
    SUM(o.total_amount) AS total_spent,
    MIN(o.created_at) AS first_order_date,
    MAX(o.created_at) as last_order_date
FROM
    public.customers c
JOIN
    public.orders o ON c.id = o.customer_id
GROUP BY
    c.company_id,
    c.id
WITH DATA;

-- Create an index for faster lookups
CREATE UNIQUE INDEX IF NOT EXISTS idx_customer_stats_company_customer ON public.customer_stats(company_id, customer_id);


-- Step 4: Create a function to refresh all materialized views
-- This can be called after data imports or syncs to keep the views up-to-date.
CREATE OR REPLACE FUNCTION public.refresh_all_materialized_views()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.daily_sales_stats;
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.product_sales_stats;
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.customer_stats;
END;
$$;
