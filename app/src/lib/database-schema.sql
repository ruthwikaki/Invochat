-- ============================================================================
-- FIX: Replace get_dashboard_metrics function to resolve nested aggregate error
-- and align with the application's Zod schema.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_dashboard_metrics(p_company_id uuid, p_days int DEFAULT 90)
RETURNS json
LANGUAGE plpgsql
AS $$
DECLARE
    result JSON;
    v_total_revenue NUMERIC := 0;
    v_total_orders INTEGER := 0;
    v_new_customers INTEGER := 0;
    v_dead_stock_value NUMERIC := 0;
    
    v_revenue_change NUMERIC := 0;
    v_orders_change NUMERIC := 0;
    v_customers_change NUMERIC := 0;
    
    v_period_start timestamptz;
    v_previous_period_start timestamptz;
    v_previous_period_end timestamptz;
    
    v_sales_data json;
    v_top_products json;
    v_inventory_summary json;
BEGIN
    -- Calculate date ranges
    v_period_start := now() - (p_days || ' days')::interval;
    v_previous_period_start := now() - (p_days * 2 || ' days')::interval;
    v_previous_period_end := v_period_start;

    -- Current period metrics
    SELECT 
        COALESCE(SUM(total_amount), 0),
        COUNT(*),
        COUNT(DISTINCT customer_id)
    INTO v_total_revenue, v_total_orders, v_new_customers
    FROM public.orders 
    WHERE company_id = p_company_id 
      AND created_at >= v_period_start;

    -- Previous period metrics for comparison
    DECLARE
        v_previous_revenue numeric := 0;
        v_previous_orders integer := 0;
        v_previous_customers integer := 0;
    BEGIN
        SELECT 
            COALESCE(SUM(total_amount), 0),
            COUNT(*),
            COUNT(DISTINCT customer_id)
        INTO 
            v_previous_revenue,
            v_previous_orders,
            v_previous_customers
        FROM public.orders 
        WHERE company_id = p_company_id 
          AND created_at >= v_previous_period_start 
          AND created_at < v_previous_period_end;

        -- Calculate percentage changes, avoiding division by zero
        IF v_previous_revenue > 0 THEN
            v_revenue_change := ((v_total_revenue - v_previous_revenue) / v_previous_revenue) * 100;
        ELSIF v_total_revenue > 0 THEN
            v_revenue_change := 100;
        END IF;

        IF v_previous_orders > 0 THEN
            v_orders_change := ((v_total_orders - v_previous_orders)::numeric / v_previous_orders) * 100;
        ELSIF v_total_orders > 0 THEN
            v_orders_change := 100;
        END IF;
        
        IF v_previous_customers > 0 THEN
            v_customers_change := ((v_new_customers - v_previous_customers)::numeric / v_previous_customers) * 100;
        ELSIF v_new_customers > 0 THEN
            v_customers_change := 100;
        END IF;
    END;

    -- Dead stock value
    SELECT COALESCE(SUM(v.cost * v.inventory_quantity), 0)
    INTO v_dead_stock_value
    FROM product_variants v
    WHERE v.company_id = p_company_id AND v.inventory_quantity > 0 AND NOT EXISTS (
        SELECT 1
        FROM order_line_items oli
        JOIN orders o ON oli.order_id = o.id
        WHERE o.created_at >= v_period_start AND oli.variant_id = v.id
    );

    -- Sales over time (daily aggregation)
    WITH daily_sales AS (
      SELECT
        date_trunc('day', o.created_at)::date AS sale_date,
        SUM(o.total_amount) AS revenue,
        COUNT(o.id) AS orders
      FROM public.orders o
      WHERE o.company_id = p_company_id AND o.created_at >= v_period_start
      GROUP BY 1
    )
    SELECT json_agg(json_build_object(
        'date', ds.sale_date,
        'revenue', ds.revenue,
        'orders', ds.orders
      ) ORDER BY ds.sale_date)
    INTO v_sales_data
    FROM daily_sales ds;

    -- Top selling products
    WITH top_products_cte AS (
        SELECT
            oli.variant_id,
            p.title as product_name,
            p.image_url,
            SUM(oli.quantity * oli.price) as total_revenue
        FROM public.order_line_items oli
        JOIN public.orders o ON oli.order_id = o.id
        JOIN public.product_variants pv ON oli.variant_id = pv.id
        JOIN public.products p ON pv.product_id = p.id
        WHERE o.company_id = p_company_id AND o.created_at >= v_period_start
        GROUP BY 1, 2, 3
        ORDER BY total_revenue DESC
        LIMIT 5
    )
    SELECT json_agg(json_build_object(
      'product_name', tpc.product_name,
      'image_url', tpc.image_url,
      'total_revenue', tpc.total_revenue
    ))
    INTO v_top_products
    FROM top_products_cte tpc;

    -- Inventory summary
    SELECT json_build_object(
        'total_value', COALESCE(SUM(pv.cost * pv.inventory_quantity), 0),
        'in_stock_value', COALESCE(SUM(CASE WHEN pv.inventory_quantity > 10 THEN pv.cost * pv.inventory_quantity ELSE 0 END), 0),
        'low_stock_value', COALESCE(SUM(CASE WHEN pv.inventory_quantity BETWEEN 1 AND 10 THEN pv.cost * pv.inventory_quantity ELSE 0 END), 0),
        'dead_stock_value', v_dead_stock_value
    )
    INTO v_inventory_summary
    FROM public.product_variants pv
    WHERE pv.company_id = p_company_id;

    -- Return comprehensive metrics
    RETURN json_build_object(
        'total_revenue', v_total_revenue,
        'revenue_change', v_revenue_change,
        'total_orders', v_total_orders,
        'orders_change', v_orders_change,
        'new_customers', v_new_customers,
        'customers_change', v_customers_change,
        'dead_stock_value', v_dead_stock_value,
        'sales_over_time', COALESCE(v_sales_data, '[]'::json),
        'top_selling_products', COALESCE(v_top_products, '[]'::json),
        'inventory_summary', COALESCE(v_inventory_summary, '{}'::json)
    );
END;
$$;
