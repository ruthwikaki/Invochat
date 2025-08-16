-- Fix missing get_dead_stock_report function
-- This function is referenced by get_dashboard_metrics but was never defined.

-- Create the missing get_dead_stock_report function
CREATE OR REPLACE FUNCTION public.get_dead_stock_report(p_company_id uuid)
RETURNS TABLE (
    sku text,
    product_name text,
    quantity integer,
    total_value numeric,
    last_sale_date timestamp with time zone
)
LANGUAGE sql
STABLE
AS $$
    WITH company_settings AS (
        SELECT dead_stock_days
        FROM public.company_settings 
        WHERE company_id = p_company_id
    ),
    dead_stock_cutoff AS (
        SELECT CURRENT_DATE - INTERVAL '1 day' * COALESCE((SELECT dead_stock_days FROM company_settings), 90) AS cutoff_date
    ),
    last_sales AS (
        SELECT 
            oli.sku,
            MAX(o.created_at) AS last_sale_date
        FROM public.order_line_items oli
        JOIN public.orders o ON oli.order_id = o.id
        WHERE o.company_id = p_company_id
            AND o.financial_status = 'paid'
        GROUP BY oli.sku
    ),
    dead_stock_variants AS (
        SELECT 
            pv.sku,
            pv.title AS variant_title,
            p.title AS product_title,
            pv.inventory_quantity,
            COALESCE(pv.cost, 0) AS cost,
            ls.last_sale_date
        FROM public.product_variants pv
        JOIN public.products p ON pv.product_id = p.id
        LEFT JOIN last_sales ls ON pv.sku = ls.sku
        CROSS JOIN dead_stock_cutoff dsc
        WHERE pv.company_id = p_company_id
            AND pv.inventory_quantity > 0
            AND (ls.last_sale_date IS NULL OR ls.last_sale_date < dsc.cutoff_date)
    )
    SELECT 
        dsv.sku,
        COALESCE(dsv.variant_title, dsv.product_title) AS product_name,
        dsv.inventory_quantity AS quantity,
        (dsv.inventory_quantity * dsv.cost) AS total_value,
        dsv.last_sale_date
    FROM dead_stock_variants dsv
    ORDER BY total_value DESC;
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION public.get_dead_stock_report(uuid) TO authenticated;

-- Add comment for documentation
COMMENT ON FUNCTION public.get_dead_stock_report(uuid) IS 'Returns dead stock items for a company based on dead_stock_days setting and sales history';