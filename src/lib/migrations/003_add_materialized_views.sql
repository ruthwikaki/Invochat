-- This migration introduces materialized views for performance-critical queries.
-- Materialized views pre-calculate and store the results of complex joins,
-- which makes reading this data much faster for analytics and dashboard pages.

-- Drop the old standard views if they exist to replace them with materialized views
DROP VIEW IF EXISTS public.product_variants_with_details;
DROP VIEW IF EXISTS public.customers_view;

-- Create a materialized view for product variants with their parent product details.
-- This is heavily used on the main inventory page and several AI tools.
CREATE MATERIALIZED VIEW public.product_variants_with_details_mat AS
SELECT 
    pv.id,
    pv.product_id,
    pv.company_id,
    p.title AS product_title,
    p.status AS product_status,
    p.image_url,
    p.product_type,
    pv.sku,
    pv.title,
    pv.option1_name,
    pv.option1_value,
    pv.option2_name,
    pv.option2_value,
    pv.option3_name,
    pv.option3_value,
    pv.barcode,
    pv.price,
    pv.compare_at_price,
    pv.cost,
    pv.inventory_quantity,
    pv.location,
    pv.reorder_point,
    pv.reorder_quantity,
    pv.supplier_id,
    pv.external_variant_id,
    pv.created_at,
    pv.updated_at
FROM 
    public.product_variants pv
JOIN 
    public.products p ON pv.product_id = p.id;

-- Create an index for faster lookups by company_id
CREATE INDEX ON public.product_variants_with_details_mat (company_id);
CREATE INDEX ON public.product_variants_with_details_mat (sku, company_id);

-- Create a materialized view for customer analytics.
-- This pre-computes total orders and total spend for each customer.
CREATE MATERIALIZED VIEW public.customers_view AS
SELECT
    c.id,
    c.company_id,
    c.name as customer_name,
    c.email,
    count(o.id) as total_orders,
    sum(o.total_amount) as total_spent,
    min(o.created_at) as first_order_date,
    c.created_at
FROM
    public.customers c
LEFT JOIN
    public.orders o ON c.id = o.customer_id
GROUP BY
    c.id;
    
-- Create an index for faster lookups by company_id
CREATE INDEX ON public.customers_view (company_id);

-- Create a function to refresh all materialized views for a given company.
-- This should be called after significant data changes (e.g., after an integration sync).
CREATE OR REPLACE FUNCTION public.refresh_all_matviews(p_company_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Refreshing concurrently does not lock the view, allowing reads while it updates.
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.product_variants_with_details_mat;
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.customers_view;
    
    RAISE LOG 'Materialized views refreshed for company %', p_company_id;
END;
$$;
