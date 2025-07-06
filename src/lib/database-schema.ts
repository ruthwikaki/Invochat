
-- =====================================================
-- INVOCHAT DATABASE FIXES
-- Run this script in your Supabase SQL Editor
-- This fixes all missing columns, functions, and constraints
-- =====================================================

-- 1. Fix Messages Table - Add missing columns and update role constraint
ALTER TABLE public.messages 
ADD COLUMN IF NOT EXISTS component TEXT,
ADD COLUMN IF NOT EXISTS component_props JSONB;

-- Drop the old constraint and create a new one that includes 'tool' role
ALTER TABLE public.messages 
DROP CONSTRAINT IF EXISTS messages_role_check;

ALTER TABLE public.messages 
ADD CONSTRAINT messages_role_check 
CHECK (role = ANY (ARRAY['user'::text, 'assistant'::text, 'tool'::text]));

-- 2. Create Missing Indexes
CREATE INDEX IF NOT EXISTS idx_messages_company_id ON public.messages(company_id);
CREATE INDEX IF NOT EXISTS idx_inventory_deleted_by ON public.inventory(deleted_by);
CREATE INDEX IF NOT EXISTS idx_audit_log_company_id ON public.audit_log(company_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_created_at ON public.audit_log(created_at);

-- 3. Fix the get_dashboard_metrics function (remove nested aggregates)
CREATE OR REPLACE FUNCTION public.get_dashboard_metrics(p_company_id uuid, p_days integer)
RETURNS json
LANGUAGE plpgsql
AS $$
DECLARE
    result_json json;
    start_date timestamptz := now() - (p_days || ' days')::interval;
    dead_stock_days integer;
BEGIN
    -- Get company settings
    SELECT COALESCE(cs.dead_stock_days, 90) INTO dead_stock_days
    FROM company_settings cs
    WHERE cs.company_id = p_company_id;

    WITH date_series AS (
        SELECT generate_series(start_date::date, now()::date, '1 day'::interval) as date
    ),
    sales_data AS (
        SELECT
            date_trunc('day', o.sale_date)::date as sale_day,
            SUM(oi.quantity * oi.unit_price) as daily_revenue,
            SUM(oi.quantity * (oi.unit_price - COALESCE(i.cost, 0))) as daily_profit,
            COUNT(DISTINCT o.id) as daily_orders
        FROM orders o
        JOIN order_items oi ON o.id = oi.sale_id
        LEFT JOIN inventory i ON oi.sku = i.sku AND o.company_id = i.company_id
        WHERE o.company_id = p_company_id AND o.sale_date >= start_date
        GROUP BY 1
    ),
    totals AS (
        SELECT 
            COALESCE(SUM(daily_revenue), 0) as total_revenue,
            COALESCE(SUM(daily_profit), 0) as total_profit,
            COALESCE(SUM(daily_orders), 0) as total_orders
        FROM sales_data
    )
    SELECT json_build_object(
        'totalSalesValue', (SELECT total_revenue FROM totals),
        'totalProfit', (SELECT total_profit FROM totals),
        'totalOrders', (SELECT total_orders FROM totals),
        'averageOrderValue', (SELECT CASE WHEN total_orders > 0 THEN total_revenue / total_orders ELSE 0 END FROM totals),
        'deadStockItemsCount', (
            SELECT COUNT(*) 
            FROM inventory 
            WHERE company_id = p_company_id 
            AND last_sold_date < now() - (dead_stock_days || ' days')::interval
        ),
        'salesTrendData', (
            SELECT json_agg(json_build_object('date', ds.date, 'Sales', COALESCE(sd.daily_revenue, 0)))
            FROM date_series ds
            LEFT JOIN sales_data sd ON ds.date = sd.sale_day
        ),
        'inventoryByCategoryData', (
            SELECT json_agg(json_build_object('name', COALESCE(category, 'Uncategorized'), 'value', category_value))
            FROM (
                SELECT category, SUM(quantity * cost) as category_value
                FROM inventory
                WHERE company_id = p_company_id AND deleted_at IS NULL
                GROUP BY category
                ORDER BY category_value DESC
                LIMIT 5
            ) cat_data
        ),
        'topCustomersData', (
            SELECT json_agg(json_build_object('name', customer_name, 'value', customer_total))
            FROM (
                SELECT c.customer_name, SUM(o.total_amount) as customer_total
                FROM orders o
                JOIN customers c ON o.customer_id = c.id
                WHERE o.company_id = p_company_id 
                    AND o.sale_date >= start_date 
                    AND c.deleted_at IS NULL
                GROUP BY c.customer_name
                ORDER BY customer_total DESC
                LIMIT 5
            ) cust_data
        )
    ) INTO result_json;

    RETURN result_json;
END;
$$;

-- 4. Create Missing RPC Functions

-- Inventory Turnover Report
CREATE OR REPLACE FUNCTION public.get_inventory_turnover_report(p_company_id uuid, p_days integer DEFAULT 90)
RETURNS TABLE(turnover_rate numeric, total_cogs numeric, average_inventory_value numeric, period_days integer)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH cogs_calc AS (
        SELECT 
            COALESCE(SUM(oi.quantity * i.cost), 0) as total_cogs
        FROM orders o
        JOIN order_items oi ON o.id = oi.sale_id
        JOIN inventory i ON oi.sku = i.sku AND o.company_id = i.company_id
        WHERE o.company_id = p_company_id 
        AND o.sale_date >= CURRENT_DATE - (p_days || ' days')::interval
    ),
    inventory_value AS (
        SELECT COALESCE(SUM(quantity * cost), 0) as current_value
        FROM inventory
        WHERE company_id = p_company_id AND deleted_at IS NULL
    )
    SELECT 
        CASE 
            WHEN iv.current_value > 0 THEN (cc.total_cogs / iv.current_value) * (365.0 / p_days)
            ELSE 0
        END as turnover_rate,
        cc.total_cogs,
        iv.current_value as average_inventory_value,
        p_days as period_days
    FROM cogs_calc cc, inventory_value iv;
END;
$$;

-- Demand Forecast
CREATE OR REPLACE FUNCTION public.get_demand_forecast(p_company_id uuid)
RETURNS TABLE(sku text, product_name text, forecasted_demand integer, current_stock integer, days_until_stockout integer)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH monthly_sales AS (
        SELECT 
            oi.sku,
            DATE_TRUNC('month', o.sale_date) as month,
            SUM(oi.quantity) as monthly_quantity
        FROM orders o
        JOIN order_items oi ON o.id = oi.sale_id
        WHERE o.company_id = p_company_id 
        AND o.sale_date >= CURRENT_DATE - INTERVAL '12 months'
        GROUP BY oi.sku, DATE_TRUNC('month', o.sale_date)
    ),
    avg_sales AS (
        SELECT 
            sku,
            AVG(monthly_quantity) as avg_monthly_sales,
            COUNT(DISTINCT month) as months_with_sales
        FROM monthly_sales
        GROUP BY sku
    )
    SELECT 
        i.sku,
        i.name as product_name,
        CEIL(COALESCE(a.avg_monthly_sales, 0))::integer as forecasted_demand,
        i.quantity as current_stock,
        CASE 
            WHEN COALESCE(a.avg_monthly_sales, 0) > 0 
            THEN FLOOR(i.quantity / (a.avg_monthly_sales / 30))::integer
            ELSE 999
        END as days_until_stockout
    FROM inventory i
    LEFT JOIN avg_sales a ON i.sku = a.sku
    WHERE i.company_id = p_company_id AND i.deleted_at IS NULL
    ORDER BY days_until_stockout ASC;
END;
$$;

-- ABC Analysis
CREATE OR REPLACE FUNCTION public.get_abc_analysis(p_company_id uuid)
RETURNS TABLE(sku text, product_name text, revenue numeric, revenue_percentage numeric, cumulative_percentage numeric, category character)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH revenue_data AS (
        SELECT 
            i.sku,
            i.name as product_name,
            COALESCE(SUM(oi.quantity * oi.unit_price), 0) as revenue
        FROM inventory i
        LEFT JOIN order_items oi ON i.sku = oi.sku
        LEFT JOIN orders o ON oi.sale_id = o.id AND o.company_id = p_company_id
        WHERE i.company_id = p_company_id 
        AND i.deleted_at IS NULL
        GROUP BY i.sku, i.name
    ),
    total_revenue AS (
        SELECT SUM(revenue) as total FROM revenue_data
    ),
    ranked_data AS (
        SELECT 
            sku,
            product_name,
            revenue,
            CASE WHEN t.total > 0 THEN (revenue / t.total) * 100 ELSE 0 END as revenue_percentage,
            SUM(CASE WHEN t.total > 0 THEN (revenue / t.total) * 100 ELSE 0 END) 
                OVER (ORDER BY revenue DESC) as cumulative_percentage
        FROM revenue_data, total_revenue t
    )
    SELECT 
        sku,
        product_name,
        revenue,
        revenue_percentage,
        cumulative_percentage,
        CASE 
            WHEN cumulative_percentage <= 80 THEN 'A'
            WHEN cumulative_percentage <= 95 THEN 'B'
            ELSE 'C'
        END::character as category
    FROM ranked_data
    ORDER BY revenue DESC;
END;
$$;

-- Gross Margin Analysis
CREATE OR REPLACE FUNCTION public.get_gross_margin_analysis(p_company_id uuid)
RETURNS TABLE(sku text, product_name text, sales_channel text, units_sold bigint, revenue numeric, cost numeric, gross_profit numeric, gross_margin_percentage numeric)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        i.sku,
        i.name as product_name,
        COALESCE(o.sales_channel, 'Unknown') as sales_channel,
        COUNT(oi.id) as units_sold,
        SUM(oi.quantity * oi.unit_price) as revenue,
        SUM(oi.quantity * COALESCE(i.cost, 0)) as cost,
        SUM(oi.quantity * oi.unit_price) - SUM(oi.quantity * COALESCE(i.cost, 0)) as gross_profit,
        CASE 
            WHEN SUM(oi.quantity * oi.unit_price) > 0 
            THEN ((SUM(oi.quantity * oi.unit_price) - SUM(oi.quantity * COALESCE(i.cost, 0))) / SUM(oi.quantity * oi.unit_price)) * 100
            ELSE 0
        END as gross_margin_percentage
    FROM inventory i
    JOIN order_items oi ON i.sku = oi.sku
    JOIN orders o ON oi.sale_id = o.id
    WHERE o.company_id = p_company_id 
    AND o.sale_date >= CURRENT_DATE - INTERVAL '90 days'
    AND i.deleted_at IS NULL
    GROUP BY i.sku, i.name, o.sales_channel
    ORDER BY revenue DESC;
END;
$$;

-- Net Margin by Channel
CREATE OR REPLACE FUNCTION public.get_net_margin_by_channel(p_company_id uuid, p_channel_name text)
RETURNS TABLE(channel text, total_revenue numeric, total_cost numeric, channel_fees numeric, net_profit numeric, net_margin_percentage numeric)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH channel_data AS (
        SELECT 
            o.sales_channel,
            SUM(oi.quantity * oi.unit_price) as revenue,
            SUM(oi.quantity * COALESCE(i.cost, 0)) as cost
        FROM orders o
        JOIN order_items oi ON o.id = oi.sale_id
        JOIN inventory i ON oi.sku = i.sku AND o.company_id = i.company_id
        WHERE o.company_id = p_company_id 
        AND o.sales_channel = p_channel_name
        AND o.sale_date >= CURRENT_DATE - INTERVAL '90 days'
        GROUP BY o.sales_channel
    ),
    fees AS (
        SELECT 
            COALESCE(percentage_fee, 0) as pct_fee,
            COALESCE(fixed_fee, 0) as fix_fee
        FROM channel_fees
        WHERE company_id = p_company_id AND channel_name = p_channel_name
        LIMIT 1
    )
    SELECT 
        cd.sales_channel as channel,
        cd.revenue as total_revenue,
        cd.cost as total_cost,
        (cd.revenue * (f.pct_fee / 100) + f.fix_fee) as channel_fees,
        cd.revenue - cd.cost - (cd.revenue * (f.pct_fee / 100) + f.fix_fee) as net_profit,
        CASE 
            WHEN cd.revenue > 0 
            THEN ((cd.revenue - cd.cost - (cd.revenue * (f.pct_fee / 100) + f.fix_fee)) / cd.revenue) * 100
            ELSE 0
        END as net_margin_percentage
    FROM channel_data cd, fees f;
END;
$$;

-- Margin Trends
CREATE OR REPLACE FUNCTION public.get_margin_trends(p_company_id uuid)
RETURNS TABLE(month text, revenue numeric, cost numeric, gross_profit numeric, gross_margin_percentage numeric)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        TO_CHAR(DATE_TRUNC('month', o.sale_date), 'YYYY-MM') as month,
        SUM(oi.quantity * oi.unit_price) as revenue,
        SUM(oi.quantity * COALESCE(i.cost, 0)) as cost,
        SUM(oi.quantity * oi.unit_price) - SUM(oi.quantity * COALESCE(i.cost, 0)) as gross_profit,
        CASE 
            WHEN SUM(oi.quantity * oi.unit_price) > 0 
            THEN ((SUM(oi.quantity * oi.unit_price) - SUM(oi.quantity * COALESCE(i.cost, 0))) / SUM(oi.quantity * oi.unit_price)) * 100
            ELSE 0
        END as gross_margin_percentage
    FROM orders o
    JOIN order_items oi ON o.id = oi.sale_id
    JOIN inventory i ON oi.sku = i.sku AND o.company_id = i.company_id
    WHERE o.company_id = p_company_id 
    AND o.sale_date >= CURRENT_DATE - INTERVAL '12 months'
    GROUP BY DATE_TRUNC('month', o.sale_date)
    ORDER BY DATE_TRUNC('month', o.sale_date);
END;
$$;

-- Check Inventory References
CREATE OR REPLACE FUNCTION public.check_inventory_references(p_company_id uuid, p_skus text[])
RETURNS TABLE(sku text)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT i.sku
    FROM inventory i
    WHERE i.company_id = p_company_id 
    AND i.sku = ANY(p_skus)
    AND (
        EXISTS (
            SELECT 1 FROM order_items oi 
            JOIN orders o ON oi.sale_id = o.id 
            WHERE oi.sku = i.sku AND o.company_id = p_company_id
        )
        OR EXISTS (
            SELECT 1 FROM purchase_order_items poi 
            JOIN purchase_orders po ON poi.po_id = po.id 
            WHERE poi.sku = i.sku AND po.company_id = p_company_id
        )
    );
END;
$$;

-- Process Sales Order Inventory
CREATE OR REPLACE FUNCTION public.process_sales_order_inventory(p_order_id uuid, p_company_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    -- Update inventory quantities based on order items
    UPDATE inventory i
    SET quantity = i.quantity - oi.quantity,
        last_sold_date = CURRENT_DATE,
        updated_at = NOW()
    FROM order_items oi
    JOIN orders o ON oi.sale_id = o.id
    WHERE o.id = p_order_id
    AND o.company_id = p_company_id
    AND i.sku = oi.sku
    AND i.company_id = p_company_id;

    -- Create inventory ledger entries
    INSERT INTO inventory_ledger (company_id, sku, created_at, change_type, quantity_change, new_quantity, related_id, notes)
    SELECT 
        p_company_id,
        oi.sku,
        NOW(),
        'sale',
        -oi.quantity,
        i.quantity,
        p_order_id,
        'Order fulfillment'
    FROM order_items oi
    JOIN orders o ON oi.sale_id = o.id
    JOIN inventory i ON oi.sku = i.sku AND i.company_id = p_company_id
    WHERE o.id = p_order_id
    AND o.company_id = p_company_id;
END;
$$;

-- 5. Fix the handle_new_user trigger to handle invited users properly
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    new_company_id UUID;
    user_role TEXT := 'Owner';
    new_company_name TEXT;
BEGIN
    RAISE NOTICE '[handle_new_user] Trigger started for user %', new.email;

    -- Check for Supabase environment
    IF NOT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'auth') THEN
        RAISE WARNING '[handle_new_user] Auth schema not found. Skipping trigger logic.';
        RETURN new;
    END IF;

    -- Handle invited users vs. new sign-ups
    IF new.invited_at IS NOT NULL THEN
        RAISE NOTICE '[handle_new_user] Processing invited user.';
        user_role := 'Member';
        -- Check both raw_app_meta_data and raw_user_meta_data for company_id
        new_company_id := COALESCE(
            (new.raw_app_meta_data->>'company_id')::uuid,
            (new.raw_user_meta_data->>'company_id')::uuid
        );
        IF new_company_id IS NULL THEN
            RAISE EXCEPTION 'Invited user sign-up failed: company_id was missing from user metadata.';
        END IF;
    ELSE
        RAISE NOTICE '[handle_new_user] Processing new direct sign-up.';
        user_role := 'Owner';
        new_company_name := COALESCE(new.raw_user_meta_data->>'company_name', new.email || '''s Company');
        
        BEGIN
            INSERT INTO public.companies (name) VALUES (new_company_name) RETURNING id INTO new_company_id;
        EXCEPTION
            WHEN OTHERS THEN
                RAISE EXCEPTION 'Failed to insert into public.companies: %', SQLERRM;
        END;
    END IF;

    BEGIN
        INSERT INTO public.users (id, company_id, email, role)
        VALUES (new.id, new_company_id, new.email, user_role);
    EXCEPTION
        WHEN OTHERS THEN
            RAISE EXCEPTION 'Failed to insert into public.users: %', SQLERRM;
    END;

    IF user_role = 'Owner' THEN
        BEGIN
            INSERT INTO public.company_settings (company_id) VALUES (new_company_id) ON CONFLICT (company_id) DO NOTHING;
        EXCEPTION
            WHEN OTHERS THEN
                RAISE EXCEPTION 'Failed to insert into public.company_settings: %', SQLERRM;
        END;
    END IF;
    
    BEGIN
        UPDATE auth.users
        SET raw_app_meta_data = COALESCE(raw_app_meta_data, '{}'::jsonb) || jsonb_build_object('role', user_role, 'company_id', new_company_id)
        WHERE id = new.id;
    EXCEPTION
        WHEN OTHERS THEN
            RAISE EXCEPTION 'Failed to update auth.users metadata: %', SQLERRM;
    END;

    RAISE NOTICE '[handle_new_user] Trigger finished successfully.';
    RETURN new;
END;
$$;

-- 6. Secure the execute_dynamic_query function
-- First revoke all permissions
REVOKE ALL ON FUNCTION public.execute_dynamic_query FROM PUBLIC;
REVOKE ALL ON FUNCTION public.execute_dynamic_query FROM anon;
REVOKE ALL ON FUNCTION public.execute_dynamic_query FROM authenticated;

-- Only grant to service_role
GRANT EXECUTE ON FUNCTION public.execute_dynamic_query TO service_role;

-- Add a comment warning about its use
COMMENT ON FUNCTION public.execute_dynamic_query IS 'SECURITY WARNING: This function executes arbitrary SQL. Only use through secure server-side code with proper input validation.';

-- 7. Create the company_dashboard_metrics table properly (not as materialized view)
-- It already exists as a table, so we just need to ensure it has the right structure
CREATE TABLE IF NOT EXISTS public.company_dashboard_metrics (
    company_id UUID PRIMARY KEY,
    total_skus BIGINT,
    inventory_value NUMERIC,
    low_stock_count BIGINT,
    last_refreshed TIMESTAMPTZ
);

-- Create unique index if it doesn't exist
CREATE UNIQUE INDEX IF NOT EXISTS idx_company_dashboard_metrics_company_id 
ON public.company_dashboard_metrics(company_id);

-- 8. Add cleanup function for old sync logs
CREATE OR REPLACE FUNCTION public.cleanup_old_sync_logs()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    -- Delete sync logs older than 30 days
    DELETE FROM sync_logs 
    WHERE completed_at < NOW() - INTERVAL '30 days';
    
    -- Delete failed sync logs older than 7 days
    DELETE FROM sync_logs 
    WHERE status = 'failed' 
    AND completed_at < NOW() - INTERVAL '7 days';
    
    -- Delete orphaned sync states
    DELETE FROM sync_state 
    WHERE integration_id NOT IN (SELECT id FROM integrations);
END;
$$;

-- 9. Add RLS policies for new columns
-- Already handled by existing policies

-- 10. Create index for performance on order_items
CREATE INDEX IF NOT EXISTS idx_order_items_sale_id ON public.order_items(sale_id);

-- 11. Add missing constraint for inventory quantity check
ALTER TABLE inventory 
DROP CONSTRAINT IF EXISTS inventory_quantity_check;

ALTER TABLE inventory 
ADD CONSTRAINT inventory_quantity_check 
CHECK (quantity >= 0);

-- 12. Grant necessary permissions
GRANT EXECUTE ON FUNCTION public.get_inventory_turnover_report TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_demand_forecast TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_abc_analysis TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_gross_margin_analysis TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_net_margin_by_channel TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_margin_trends TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_inventory_references TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.process_sales_order_inventory TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cleanup_old_sync_logs TO service_role;

-- 13. Schedule cleanup job (requires pg_cron extension)
-- Uncomment these lines if you have pg_cron enabled:
-- SELECT cron.schedule('cleanup-sync-logs', '0 2 * * *', 'SELECT public.cleanup_old_sync_logs()');
-- SELECT cron.schedule('refresh-dashboard-metrics', '*/5 * * * *', 'REFRESH MATERIALIZED VIEW CONCURRENTLY public.company_dashboard_metrics');

-- =====================================================
-- Script completed successfully!
-- Your database is now fixed and ready to use.
-- ====================================================="
