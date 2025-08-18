-- Add missing function for Price Optimizer
-- This function gets historical sales data for multiple SKUs for AI price optimization

CREATE OR REPLACE FUNCTION get_historical_sales_for_skus(p_company_id uuid, p_skus text[])
RETURNS TABLE (
    sku text,
    product_name text,
    current_price integer,
    cost integer,
    total_quantity_sold bigint,
    total_revenue bigint,
    avg_order_value numeric,
    sales_frequency numeric,
    last_sale_date timestamp with time zone,
    price_elasticity_indicator numeric
) 
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        pv.sku,
        p.title as product_name,
        pv.price as current_price,
        pv.cost,
        COALESCE(SUM(oli.quantity), 0)::bigint as total_quantity_sold,
        COALESCE(SUM(oli.price * oli.quantity), 0)::bigint as total_revenue,
        COALESCE(AVG(oli.price * oli.quantity), 0) as avg_order_value,
        COALESCE(COUNT(DISTINCT o.id)::numeric / NULLIF(EXTRACT(days FROM (NOW() - MIN(o.created_at))), 0), 0) as sales_frequency,
        MAX(o.created_at) as last_sale_date,
        -- Simple price elasticity indicator: higher values suggest more price-sensitive
        CASE 
            WHEN COALESCE(SUM(oli.quantity), 0) > 0 AND pv.price > 0 
            THEN (COALESCE(SUM(oli.quantity), 0)::numeric / pv.price) * 100
            ELSE 0 
        END as price_elasticity_indicator
    FROM 
        product_variants pv
        JOIN products p ON p.id = pv.product_id
        LEFT JOIN order_line_items oli ON oli.variant_id = pv.id
        LEFT JOIN orders o ON o.id = oli.order_id 
            AND o.financial_status = 'paid' 
            AND o.cancelled_at IS NULL
            AND o.created_at >= NOW() - INTERVAL '12 months'
    WHERE 
        pv.company_id = p_company_id
        AND pv.sku = ANY(p_skus)
        AND pv.deleted_at IS NULL
        AND p.deleted_at IS NULL
    GROUP BY 
        pv.sku, 
        p.title, 
        pv.price, 
        pv.cost
    ORDER BY 
        total_revenue DESC;
END;
$$;
