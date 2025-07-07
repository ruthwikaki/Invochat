-- =====================================================
-- INVOCHAT DATABASE SCHEMA - V3 (FINAL)
-- This script fixes all remaining references to the old 'orders' table.
-- Run this script in your Supabase SQL Editor.
-- =====================================================

-- =====================================================
-- SECTION 1: FIX ALL FUNCTIONS REFERENCING 'orders'
-- =====================================================

-- 1. Fix get_unified_inventory
CREATE OR REPLACE FUNCTION public.get_unified_inventory(
    p_company_id uuid,
    p_query text DEFAULT NULL,
    p_category text DEFAULT NULL,
    p_location_id uuid DEFAULT NULL,
    p_supplier_id uuid DEFAULT NULL,
    p_sku_filter text DEFAULT NULL,
    p_limit integer DEFAULT 50,
    p_offset integer DEFAULT 0
)
RETURNS TABLE(items json, total_count bigint)
LANGUAGE plpgsql
AS $$
DECLARE
    result_items json;
    total_count bigint;
BEGIN
    WITH filtered_inventory AS (
        SELECT 
            i.sku,
            i.name as product_name,
            i.category,
            i.quantity,
            i.cost,
            i.price,
            (i.quantity * i.cost) as total_value,
            i.reorder_point,
            i.on_order_quantity,
            i.landed_cost,
            i.barcode,
            i.location_id,
            l.name as location_name,
            COALESCE(
                (SELECT SUM(si.quantity) 
                 FROM public.sales s 
                 JOIN public.sale_items si ON s.id = si.sale_id 
                 WHERE si.sku = i.sku 
                   AND s.company_id = i.company_id 
                   AND s.created_at >= (NOW() - interval '30 days')
                ), 0
            ) as monthly_units_sold,
            COALESCE(
                (SELECT SUM(si.quantity * (si.unit_price - i.cost))
                 FROM public.sales s 
                 JOIN public.sale_items si ON s.id = si.sale_id 
                 WHERE si.sku = i.sku 
                   AND s.company_id = i.company_id 
                   AND s.created_at >= (NOW() - interval '30 days')
                ), 0
            ) as monthly_profit,
            i.version
        FROM inventory i
        LEFT JOIN locations l ON i.location_id = l.id
        WHERE i.company_id = p_company_id
            AND i.deleted_at IS NULL
            AND (p_query IS NULL OR (
                i.sku ILIKE '%' || p_query || '%' OR
                i.name ILIKE '%' || p_query || '%' OR
                i.barcode ILIKE '%' || p_query || '%'
            ))
            AND (p_category IS NULL OR i.category = p_category)
            AND (p_location_id IS NULL OR i.location_id = p_location_id)
            AND (p_supplier_id IS NULL OR EXISTS (
                SELECT 1 FROM supplier_catalogs sc 
                WHERE sc.sku = i.sku AND sc.supplier_id = p_supplier_id
            ))
            AND (p_sku_filter IS NULL OR i.sku = p_sku_filter)
    ),
    count_query AS (
        SELECT count(*) as total FROM filtered_inventory
    )
    SELECT 
        (SELECT COALESCE(json_agg(fi.*), '[]'::json) FROM (SELECT * FROM filtered_inventory ORDER BY product_name LIMIT p_limit OFFSET p_offset) fi) as items,
        (SELECT total FROM count_query) as total_count
    INTO result_items, total_count;

    RETURN QUERY SELECT result_items, total_count;
END;
$$;


-- 2. Fix get_customers_with_stats
DROP FUNCTION IF EXISTS public.get_customers_with_stats(uuid, text, integer, integer);
CREATE OR REPLACE FUNCTION public.get_customers_with_stats(
    p_company_id uuid,
    p_query text DEFAULT NULL,
    p_limit integer DEFAULT 50,
    p_offset integer DEFAULT 0
)
RETURNS json
LANGUAGE plpgsql
AS $$
DECLARE
    result_json json;
BEGIN
    WITH customer_stats AS (
        SELECT
            c.id,
            c.company_id,
            c.platform,
            c.external_id,
            c.customer_name,
            c.email,
            c.status,
            c.deleted_at,
            c.created_at,
            COUNT(s.id) as total_orders,
            COALESCE(SUM(s.total_amount), 0) as total_spend
        FROM public.customers c
        LEFT JOIN public.sales s ON c.email = s.customer_email AND c.company_id = s.company_id
        WHERE c.company_id = p_company_id
          AND c.deleted_at IS NULL
          AND (
            p_query IS NULL OR
            c.customer_name ILIKE '%' || p_query || '%' OR
            c.email ILIKE '%' || p_query || '%'
          )
        GROUP BY c.id
    ),
    count_query AS (
        SELECT count(*) as total FROM customer_stats
    )
    SELECT json_build_object(
        'items', COALESCE((SELECT json_agg(cs) FROM (
            SELECT * FROM customer_stats ORDER BY total_spend DESC LIMIT p_limit OFFSET p_offset
        ) cs), '[]'::json),
        'totalCount', (SELECT total FROM count_query)
    ) INTO result_json;
    
    RETURN result_json;
END;
$$;


-- 3. Fix get_distinct_categories
CREATE OR REPLACE FUNCTION public.get_distinct_categories(p_company_id uuid)
RETURNS TABLE(category text)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT i.category::text
    FROM inventory i
    WHERE i.company_id = p_company_id
    AND i.category IS NOT NULL
    AND i.category <> ''
    ORDER BY i.category;
END;
$$;


-- 4. Fix get_alerts to use the `sales` table
CREATE OR REPLACE FUNCTION public.get_alerts(
    p_company_id uuid,
    p_dead_stock_days integer,
    p_fast_moving_days integer,
    p_predictive_stock_days integer
)
RETURNS TABLE(type text, sku text, product_name text, current_stock integer, reorder_point integer, last_sold_date date, value numeric, days_of_stock_remaining numeric)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    -- Low Stock Alerts
    SELECT
        'low_stock'::text as type,
        i.sku,
        i.name::text as product_name,
        i.quantity::integer as current_stock,
        i.reorder_point::integer,
        i.last_sold_date::date,
        (i.quantity * i.cost)::numeric as value,
        NULL::numeric as days_of_stock_remaining
    FROM inventory i
    WHERE i.company_id = p_company_id
      AND i.reorder_point IS NOT NULL
      AND i.quantity <= i.reorder_point
      AND i.quantity > 0

    UNION ALL

    -- Dead Stock Alerts
    SELECT
        'dead_stock'::text as type,
        i.sku,
        i.name::text as product_name,
        i.quantity::integer as current_stock,
        i.reorder_point::integer,
        i.last_sold_date::date,
        (i.quantity * i.cost)::numeric as value,
        NULL::numeric as days_of_stock_remaining
    FROM inventory i
    WHERE i.company_id = p_company_id
      AND i.last_sold_date < (NOW() - (p_dead_stock_days || ' day')::interval)

    UNION ALL

    -- Predictive Stockout Alerts
    (
        WITH sales_velocity AS (
          SELECT
            si.sku,
            SUM(si.quantity)::numeric / p_fast_moving_days as daily_sales
          FROM sale_items si
          JOIN sales s ON si.sale_id = s.id
          WHERE s.company_id = p_company_id
            AND s.created_at >= (NOW() - (p_fast_moving_days || ' day')::interval)
          GROUP BY si.sku
        )
        SELECT
            'predictive'::text as type,
            i.sku,
            i.name::text as product_name,
            i.quantity::integer as current_stock,
            i.reorder_point::integer,
            i.last_sold_date::date,
            (i.quantity * i.cost)::numeric as value,
            (i.quantity / sv.daily_sales)::numeric as days_of_stock_remaining
        FROM inventory i
        JOIN sales_velocity sv ON i.sku = sv.sku
        WHERE i.company_id = p_company_id
          AND sv.daily_sales > 0
          AND (i.quantity / sv.daily_sales) <= p_predictive_stock_days
    );
END;
$$;


-- 5. Fix `get_anomaly_insights` to use sales table
CREATE OR REPLACE FUNCTION public.get_anomaly_insights(p_company_id uuid)
RETURNS TABLE(date text, daily_revenue numeric, daily_customers bigint, avg_revenue numeric, avg_customers numeric, anomaly_type text, deviation_percentage numeric)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH daily_stats AS (
        SELECT
            s.created_at::date AS stat_date,
            SUM(s.total_amount) AS revenue,
            COUNT(DISTINCT s.customer_email) AS customers
        FROM public.sales s
        WHERE s.company_id = p_company_id AND s.created_at >= NOW() - INTERVAL '30 days'
        GROUP BY s.created_at::date
    ),
    avg_stats AS (
        SELECT
            AVG(revenue) AS avg_revenue,
            AVG(customers) AS avg_customers
        FROM daily_stats
    ),
    anomalies AS (
        SELECT
            ds.stat_date,
            ds.revenue,
            ds.customers,
            a.avg_revenue,
            a.avg_customers,
            (ds.revenue - a.avg_revenue) / a.avg_revenue AS revenue_deviation,
            (ds.customers::numeric - a.avg_customers) / a.avg_customers AS customers_deviation
        FROM daily_stats ds, avg_stats a
        WHERE a.avg_revenue > 0 AND a.avg_customers > 0
    )
    SELECT
        a.stat_date::text,
        a.revenue,
        a.customers,
        ROUND(a.avg_revenue, 2),
        ROUND(a.avg_customers, 2),
        CASE
            WHEN ABS(a.revenue_deviation) > 2 THEN 'Revenue Anomaly'
            WHEN ABS(a.customers_deviation) > 2 THEN 'Customer Anomaly'
            ELSE 'No Anomaly'
        END::text AS anomaly_type,
        CASE
            WHEN ABS(a.revenue_deviation) > 2 THEN ROUND(a.revenue_deviation * 100, 2)
            WHEN ABS(a.customers_deviation) > 2 THEN ROUND(a.customers_deviation * 100, 2)
            ELSE 0
        END::numeric AS deviation_percentage
    FROM anomalies a
    WHERE ABS(a.revenue_deviation) > 2 OR ABS(a.customers_deviation) > 2;
END;
$$;

-- 6. Grant Permissions to fixed functions
GRANT EXECUTE ON FUNCTION public.get_unified_inventory(uuid, text, text, uuid, uuid, text, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_customers_with_stats(uuid, text, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_distinct_categories(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_alerts(uuid, integer, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_anomaly_insights(uuid) TO authenticated;

-- =====================================================
-- SECTION 2: ENSURE IDEMPOTENCY OF THE REST OF THE SCRIPT
-- =====================================================

-- Drop policy if it exists, then recreate it
DROP POLICY IF EXISTS "Users can manage sales for their own company" ON public.sales;
CREATE POLICY "Users can manage sales for their own company"
    ON public.sales FOR ALL
    USING (company_id = (SELECT company_id FROM users WHERE id = auth.uid()));
    
DROP POLICY IF EXISTS "Users can manage sale items for sales in their own company" ON public.sale_items;
CREATE POLICY "Users can manage sale items for sales in their own company"
    ON public.sale_items FOR ALL
    USING (sale_id IN (SELECT id FROM sales WHERE company_id = (SELECT company_id FROM users WHERE id = auth.uid())));
    
-- =====================================================
-- SCRIPT FULLY CORRECTED
-- =====================================================
