
-- Migration: Create Materialized Views for Performance
-- Date: 2024-07-26
-- This script creates materialized views to significantly improve the performance
-- of analytics queries for the dashboard and AI features.
-- It is safe to run on existing databases.

-- Drop existing views if they exist to ensure a clean slate
DROP VIEW IF EXISTS public.product_variants_with_details;
DROP VIEW IF EXISTS public.orders_view;
DROP VIEW IF EXISTS public.customers_view;

-- Create the product_variants_with_details view
-- This combines variant information with key details from the parent product.
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT 
    pv.id,
    pv.product_id,
    pv.company_id,
    p.title AS product_title,
    p.status AS product_status,
    p.image_url,
    pv.sku,
    pv.title,
    pv.price,
    pv.cost,
    pv.inventory_quantity,
    pv.location,
    pv.created_at,
    pv.updated_at
FROM 
    public.product_variants pv
JOIN 
    public.products p ON pv.product_id = p.id;

-- Create the orders_view
-- This denormalizes order information for easier querying.
CREATE OR REPLACE VIEW public.orders_view AS
SELECT
    o.id,
    o.company_id,
    o.order_number,
    o.external_order_id,
    o.customer_id,
    c.email AS customer_email,
    o.financial_status,
    o.fulfillment_status,
    o.total_amount,
    o.source_platform,
    o.created_at
FROM 
    public.orders o
LEFT JOIN 
    public.customers c ON o.customer_id = c.id;

-- Create the customers_view
-- This calculates key metrics for each customer.
CREATE OR REPLACE VIEW public.customers_view AS
SELECT 
    c.id,
    c.company_id,
    c.customer_name,
    c.email,
    c.first_order_date,
    c.created_at,
    COALESCE(o.total_orders, 0) as total_orders,
    COALESCE(o.total_spent, 0) as total_spent
FROM 
    public.customers c
LEFT JOIN (
    SELECT
        customer_id,
        COUNT(id) as total_orders,
        SUM(total_amount) as total_spent
    FROM 
        public.orders
    GROUP BY 
        customer_id
) o ON c.id = o.customer_id
WHERE c.deleted_at IS NULL;


-- Materialized View for Daily Sales
-- This view pre-calculates total sales per day, which is essential for the dashboard sales chart.
CREATE MATERIALIZED VIEW IF NOT EXISTS public.daily_sales_stats AS
SELECT
    o.company_id,
    date_trunc('day', o.created_at) AS sale_date,
    SUM(ol.quantity * ol.price) AS total_revenue,
    SUM(ol.quantity) AS total_units_sold,
    COUNT(DISTINCT o.id) AS total_orders
FROM
    public.orders o
JOIN
    public.order_line_items ol ON o.id = ol.order_id
GROUP BY
    o.company_id,
    date_trunc('day', o.created_at)
WITH DATA;

-- Create a unique index for concurrent refreshing
CREATE UNIQUE INDEX IF NOT EXISTS idx_daily_sales_stats_company_date ON public.daily_sales_stats(company_id, sale_date);

-- Materialized View for Product Sales Summary
-- This view aggregates sales data per product variant, crucial for many AI analytics.
CREATE MATERIALIZED VIEW IF NOT EXISTS public.product_sales_summary AS
SELECT
    ol.variant_id,
    p.company_id,
    SUM(ol.quantity) AS total_quantity_sold,
    SUM(ol.price * ol.quantity) AS total_revenue,
    SUM(ol.cost_at_time * ol.quantity) AS total_cogs,
    (SUM(ol.price * ol.quantity) - SUM(ol.cost_at_time * ol.quantity)) AS total_profit,
    MAX(o.created_at) AS last_sale_date,
    COUNT(DISTINCT o.id) AS distinct_orders
FROM
    public.order_line_items ol
JOIN
    public.orders o ON ol.order_id = o.id
JOIN
    public.products p ON ol.product_id = p.id
GROUP BY
    ol.variant_id,
    p.company_id
WITH DATA;

-- Create a unique index for concurrent refreshing
CREATE UNIQUE INDEX IF NOT EXISTS idx_product_sales_summary_variant_company ON public.product_sales_summary(variant_id, company_id);

-- Function to refresh all materialized views
CREATE OR REPLACE FUNCTION public.refresh_all_materialized_views(p_company_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    -- Refresh concurrently to avoid locking tables during the refresh.
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.daily_sales_stats;
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.product_sales_summary;

    RAISE LOG 'Materialized views refreshed for company: %', p_company_id;
END;
$$;

-- Grant execution rights to the authenticated role
GRANT EXECUTE ON FUNCTION public.refresh_all_materialized_views(uuid) TO authenticated;

-- Grant select rights on the new materialized views to the authenticated role
GRANT SELECT ON public.daily_sales_stats TO authenticated;
GRANT SELECT ON public.product_sales_summary TO authenticated;
GRANT SELECT ON public.product_variants_with_details TO authenticated;
GRANT SELECT ON public.orders_view TO authenticated;
GRANT SELECT ON public.customers_view TO authenticated;


-- Add policies to the new materialized views
ALTER TABLE public.daily_sales_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_sales_summary ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow all access to own company data" ON public.daily_sales_stats;
CREATE POLICY "Allow all access to own company data"
    ON public.daily_sales_stats FOR ALL
    USING (company_id = public.get_company_id());

DROP POLICY IF EXISTS "Allow all access to own company data" ON public.product_sales_summary;
CREATE POLICY "Allow all access to own company data"
    ON public.product_sales_summary FOR ALL
    USING (company_id = public.get_company_id());

    
RAISE NOTICE 'Migration for materialized views applied successfully.';
