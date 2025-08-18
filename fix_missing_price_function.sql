-- Additional missing function for AI Price Optimization Flow

-- Function to get historical sales for multiple SKUs (plural version)
CREATE OR REPLACE FUNCTION public.get_historical_sales_for_skus(p_company_id uuid, p_skus text[])
RETURNS JSON
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN (
        SELECT COALESCE(json_agg(t), '[]'::json)
        FROM (
            SELECT
                oli.sku,
                pv.product_name,
                DATE_TRUNC('week', o.created_at) as week,
                SUM(oli.quantity) as quantity_sold,
                SUM(oli.price * oli.quantity) as revenue,
                AVG(oli.price) as avg_price
            FROM public.orders o
            JOIN public.order_line_items oli ON o.id = oli.order_id
            LEFT JOIN public.product_variants pv ON pv.sku = oli.sku AND pv.company_id = o.company_id
            WHERE o.company_id = p_company_id
                AND o.created_at >= NOW() - INTERVAL '90 days'
                AND oli.sku = ANY(p_skus)
            GROUP BY oli.sku, pv.product_name, DATE_TRUNC('week', o.created_at)
            ORDER BY week DESC, oli.sku
        ) t
    );
END;
$$;
