-- Complete Fixed Dashboard Metrics Function - Schema Compatible
-- This version matches your DashboardMetricsSchema exactly

BEGIN;

-- Drop the existing function
DROP FUNCTION IF EXISTS get_dashboard_metrics(UUID, INTEGER);

-- Create the schema-compatible function
CREATE OR REPLACE FUNCTION get_dashboard_metrics(p_company_id UUID, p_days INTEGER)
RETURNS JSON AS $$
DECLARE
    result JSON;
    current_revenue NUMERIC := 0;
    prev_revenue NUMERIC := 0;
    current_orders INTEGER := 0;
    prev_orders INTEGER := 0;
    current_customers INTEGER := 0;
    prev_customers INTEGER := 0;
    dead_stock_val NUMERIC := 0;
    inventory_total NUMERIC := 0;
    inventory_in_stock NUMERIC := 0;
    inventory_low_stock NUMERIC := 0;
    start_date DATE;
    prev_start_date DATE;
    prev_end_date DATE;
BEGIN
    -- Calculate date ranges
    start_date := CURRENT_DATE - (p_days || ' days')::INTERVAL;
    prev_end_date := start_date - INTERVAL '1 day';
    prev_start_date := prev_end_date - (p_days || ' days')::INTERVAL;

    -- Current period metrics
    SELECT 
        COALESCE(SUM(total_amount), 0),
        COUNT(*),
        COUNT(DISTINCT customer_id)
    INTO current_revenue, current_orders, current_customers
    FROM orders 
    WHERE company_id = p_company_id 
      AND created_at >= start_date
      AND financial_status = 'paid';

    -- Previous period metrics
    SELECT 
        COALESCE(SUM(total_amount), 0),
        COUNT(*),
        COUNT(DISTINCT customer_id)
    INTO prev_revenue, prev_orders, prev_customers
    FROM orders 
    WHERE company_id = p_company_id 
      AND created_at >= prev_start_date 
      AND created_at <= prev_end_date
      AND financial_status = 'paid';

    -- Calculate inventory values
    SELECT 
        COALESCE(SUM(inventory_quantity * COALESCE(cost, 0)), 0),
        COALESCE(SUM(CASE WHEN inventory_quantity > 0 THEN inventory_quantity * COALESCE(cost, 0) ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN inventory_quantity <= COALESCE(reorder_point, 0) AND reorder_point > 0 THEN inventory_quantity * COALESCE(cost, 0) ELSE 0 END), 0)
    INTO inventory_total, inventory_in_stock, inventory_low_stock
    FROM product_variants 
    WHERE company_id = p_company_id;

    -- Calculate dead stock value (simplified - items not sold in the period)
    SELECT COALESCE(SUM(pv.inventory_quantity * COALESCE(pv.cost, 0)), 0)
    INTO dead_stock_val
    FROM product_variants pv
    WHERE pv.company_id = p_company_id
      AND pv.inventory_quantity > 0
      AND NOT EXISTS (
          SELECT 1 FROM order_line_items oli
          JOIN orders o ON oli.order_id = o.id
          WHERE oli.variant_id = pv.id
            AND o.created_at >= start_date
            AND o.financial_status = 'paid'
      );

    -- Build result matching DashboardMetricsSchema
    result := json_build_object(
        'total_revenue', current_revenue,
        'revenue_change', CASE 
            WHEN prev_revenue > 0 THEN ((current_revenue - prev_revenue) / prev_revenue * 100)
            WHEN current_revenue > 0 THEN 100
            ELSE 0
        END,
        'total_orders', current_orders,
        'orders_change', CASE 
            WHEN prev_orders > 0 THEN ((current_orders - prev_orders)::numeric / prev_orders * 100)
            WHEN current_orders > 0 THEN 100
            ELSE 0
        END,
        'new_customers', current_customers,
        'customers_change', CASE 
            WHEN prev_customers > 0 THEN ((current_customers - prev_customers)::numeric / prev_customers * 100)
            WHEN current_customers > 0 THEN 100
            ELSE 0
        END,
        'dead_stock_value', dead_stock_val,
        'sales_over_time', COALESCE(
            (SELECT json_agg(
                json_build_object(
                    'date', sale_date::text,
                    'revenue', daily_revenue,
                    'orders', daily_orders
                )
            ) FROM (
                SELECT 
                    DATE(o.created_at) as sale_date,
                    SUM(o.total_amount) as daily_revenue,
                    COUNT(*) as daily_orders
                FROM orders o
                WHERE o.company_id = p_company_id 
                  AND o.created_at >= start_date
                  AND o.financial_status = 'paid'
                GROUP BY DATE(o.created_at)
                ORDER BY sale_date
            ) daily_sales),
            '[]'::json
        ),
        'top_selling_products', COALESCE(
            (SELECT json_agg(
                json_build_object(
                    'product_name', product_name,
                    'total_revenue', total_revenue,
                    'image_url', image_url
                )
            ) FROM (
                SELECT 
                    p.title as product_name,
                    SUM(oli.price * oli.quantity) as total_revenue,
                    p.image_url
                FROM order_line_items oli
                JOIN orders o ON oli.order_id = o.id
                JOIN product_variants pv ON oli.variant_id = pv.id
                JOIN products p ON pv.product_id = p.id
                WHERE oli.company_id = p_company_id
                  AND o.created_at >= start_date
                  AND o.financial_status = 'paid'
                GROUP BY p.id, p.title, p.image_url
                ORDER BY total_revenue DESC
                LIMIT 5
            ) top_products),
            '[]'::json
        ),
        'inventory_summary', json_build_object(
            'total_value', inventory_total,
            'in_stock_value', inventory_in_stock,
            'low_stock_value', inventory_low_stock,
            'dead_stock_value', dead_stock_val
        )
    );

    RETURN result;

EXCEPTION WHEN OTHERS THEN
    -- Return error response matching schema
    RAISE NOTICE 'Error in get_dashboard_metrics: %', SQLERRM;
    RETURN json_build_object(
        'total_revenue', 0,
        'revenue_change', 0,
        'total_orders', 0,
        'orders_change', 0,
        'new_customers', 0,
        'customers_change', 0,
        'dead_stock_value', 0,
        'sales_over_time', '[]'::json,
        'top_selling_products', '[]'::json,
        'inventory_summary', json_build_object(
            'total_value', 0,
            'in_stock_value', 0,
            'low_stock_value', 0,
            'dead_stock_value', 0
        ),
        'error', SQLERRM
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant permissions
GRANT EXECUTE ON FUNCTION get_dashboard_metrics(UUID, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION get_dashboard_metrics(UUID, INTEGER) TO service_role;

COMMENT ON FUNCTION get_dashboard_metrics(UUID, INTEGER) IS 
'Returns dashboard metrics matching DashboardMetricsSchema. Fixed to avoid nested aggregates and schema validation errors.';

COMMIT;
