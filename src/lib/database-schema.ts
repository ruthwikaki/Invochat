-- =====================================================
-- INVOCHAT DATABASE SCHEMA - FIXED VERSION
-- Run this script in your Supabase SQL Editor
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
            date_trunc('day', s.created_at)::date as sale_day,
            SUM(s.total_amount) as daily_revenue,
            SUM(si.quantity * (si.unit_price - COALESCE(i.cost, 0))) as daily_profit,
            COUNT(DISTINCT s.id) as daily_orders
        FROM sales s
        JOIN sale_items si ON s.id = si.sale_id
        LEFT JOIN inventory i ON si.sku = i.sku AND s.company_id = i.company_id
        WHERE s.company_id = p_company_id AND s.created_at >= start_date
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
            WHERE company_id = p_company_id AND deleted_at IS NULL
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
                SELECT c.customer_name, SUM(s.total_amount) as customer_total
                FROM sales s
                JOIN customers c ON s.customer_email = c.email AND s.company_id = c.company_id
                WHERE s.company_id = p_company_id 
                    AND s.created_at >= start_date 
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
            COALESCE(SUM(si.quantity * i.cost), 0) as total_cogs
        FROM sales s
        JOIN sale_items si ON s.id = si.sale_id
        JOIN inventory i ON si.sku = i.sku AND s.company_id = i.company_id
        WHERE s.company_id = p_company_id 
        AND s.created_at >= CURRENT_DATE - (p_days || ' days')::interval
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
            si.sku,
            DATE_TRUNC('month', s.created_at) as month,
            SUM(si.quantity) as monthly_quantity
        FROM sales s
        JOIN sale_items si ON s.id = si.sale_id
        WHERE s.company_id = p_company_id 
        AND s.created_at >= CURRENT_DATE - INTERVAL '12 months'
        GROUP BY si.sku, DATE_TRUNC('month', s.created_at)
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
            COALESCE(SUM(si.quantity * si.unit_price), 0) as revenue
        FROM inventory i
        LEFT JOIN sale_items si ON i.sku = si.sku
        LEFT JOIN sales s ON si.sale_id = s.id AND s.company_id = p_company_id
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
        COALESCE(s.payment_method, 'Unknown') as sales_channel,
        COUNT(si.id) as units_sold,
        SUM(si.quantity * si.unit_price) as revenue,
        SUM(si.quantity * COALESCE(i.cost, 0)) as cost,
        SUM(si.quantity * si.unit_price) - SUM(si.quantity * COALESCE(i.cost, 0)) as gross_profit,
        CASE 
            WHEN SUM(si.quantity * si.unit_price) > 0 
            THEN ((SUM(si.quantity * si.unit_price) - SUM(si.quantity * COALESCE(i.cost, 0))) / SUM(si.quantity * si.unit_price)) * 100
            ELSE 0
        END as gross_margin_percentage
    FROM inventory i
    JOIN sale_items si ON i.sku = si.sku
    JOIN sales s ON si.sale_id = s.id
    WHERE s.company_id = p_company_id 
    AND s.created_at >= CURRENT_DATE - INTERVAL '90 days'
    AND i.deleted_at IS NULL
    GROUP BY i.sku, i.name, s.payment_method
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
            s.payment_method as sales_channel,
            SUM(si.quantity * si.unit_price) as revenue,
            SUM(si.quantity * COALESCE(i.cost, 0)) as cost
        FROM sales s
        JOIN sale_items si ON s.id = si.sale_id
        JOIN inventory i ON si.sku = i.sku AND s.company_id = i.company_id
        WHERE s.company_id = p_company_id 
        AND s.payment_method = p_channel_name
        AND s.created_at >= CURRENT_DATE - INTERVAL '90 days'
        GROUP BY s.payment_method
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
        (cd.revenue * (f.pct_fee) + f.fix_fee) as channel_fees,
        cd.revenue - cd.cost - (cd.revenue * (f.pct_fee) + f.fix_fee) as net_profit,
        CASE 
            WHEN cd.revenue > 0 
            THEN ((cd.revenue - cd.cost - (cd.revenue * (f.pct_fee) + f.fix_fee)) / cd.revenue) * 100
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
        TO_CHAR(DATE_TRUNC('month', s.created_at), 'YYYY-MM') as month,
        SUM(si.quantity * si.unit_price) as revenue,
        SUM(si.quantity * COALESCE(i.cost, 0)) as cost,
        SUM(si.quantity * si.unit_price) - SUM(si.quantity * COALESCE(i.cost, 0)) as gross_profit,
        CASE 
            WHEN SUM(si.quantity * si.unit_price) > 0 
            THEN ((SUM(si.quantity * si.unit_price) - SUM(si.quantity * COALESCE(i.cost, 0))) / SUM(si.quantity * si.unit_price)) * 100
            ELSE 0
        END as gross_margin_percentage
    FROM sales s
    JOIN sale_items si ON s.id = si.sale_id
    JOIN inventory i ON si.sku = i.sku AND s.company_id = i.company_id
    WHERE s.company_id = p_company_id 
    AND s.created_at >= CURRENT_DATE - INTERVAL '12 months'
    GROUP BY DATE_TRUNC('month', s.created_at)
    ORDER BY DATE_TRUNC('month', s.created_at);
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
            SELECT 1 FROM sale_items si 
            JOIN sales s ON si.sale_id = s.id 
            WHERE si.sku = i.sku AND s.company_id = p_company_id
        )
        OR EXISTS (
            SELECT 1 FROM purchase_order_items poi 
            JOIN purchase_orders po ON poi.po_id = po.id 
            WHERE poi.sku = i.sku AND po.company_id = p_company_id
        )
    );
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
GRANT EXECUTE ON FUNCTION public.cleanup_old_sync_logs TO service_role;

-- 14. Add Customer Analytics Function
CREATE OR REPLACE FUNCTION public.get_customer_analytics(p_company_id uuid)
RETURNS json
LANGUAGE plpgsql
AS $$
DECLARE
    result_json json;
BEGIN
    WITH customer_stats AS (
        SELECT
            COUNT(*) as total_customers,
            COUNT(*) FILTER (WHERE c.first_order_date >= NOW() - INTERVAL '30 days') as new_customers_last_30_days,
            COALESCE(AVG(c.total_spent), 0) as average_lifetime_value,
            CASE WHEN COUNT(*) > 0 THEN
                (COUNT(*) FILTER (WHERE c.total_orders > 1))::numeric * 100 / COUNT(*)::numeric
            ELSE 0 END as repeat_customer_rate
        FROM customers c
        WHERE c.company_id = p_company_id AND c.deleted_at IS NULL
    )
    SELECT json_build_object(
        'total_customers', (SELECT total_customers FROM customer_stats),
        'new_customers_last_30_days', (SELECT new_customers_last_30_days FROM customer_stats),
        'average_lifetime_value', (SELECT average_lifetime_value FROM customer_stats),
        'repeat_customer_rate', (SELECT repeat_customer_rate / 100.0 FROM customer_stats),
        'top_customers_by_spend', COALESCE((
            SELECT json_agg(json_build_object('name', customer_name, 'value', total_spent))
            FROM (
                SELECT customer_name, total_spent
                FROM customers
                WHERE company_id = p_company_id AND deleted_at IS NULL
                ORDER BY total_spent DESC
                LIMIT 5
            ) top_spend
        ), '[]'::json),
        'top_customers_by_orders', COALESCE((
            SELECT json_agg(json_build_object('name', customer_name, 'value', total_orders))
            FROM (
                SELECT customer_name, total_orders
                FROM customers
                WHERE company_id = p_company_id AND deleted_at IS NULL
                ORDER BY total_orders DESC
                LIMIT 5
            ) top_orders
        ), '[]'::json)
    ) INTO result_json;

    RETURN result_json;
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_customer_analytics TO anon, authenticated;


-- New Function for Reorder Tool
DROP FUNCTION IF EXISTS public.get_historical_sales(uuid,text[]);
CREATE OR REPLACE FUNCTION public.get_historical_sales(p_company_id uuid, p_skus text[])
RETURNS TABLE(sku text, monthly_sales jsonb)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH monthly_sales_data AS (
        SELECT 
            si.sku,
            to_char(date_trunc('month', s.created_at), 'YYYY-MM') as month,
            SUM(si.quantity)::integer as total_quantity
        FROM sale_items si
        JOIN sales s ON si.sale_id = s.id
        WHERE s.company_id = p_company_id
          AND si.sku = ANY(p_skus)
          AND s.created_at >= now() - interval '24 months'
        GROUP BY si.sku, to_char(date_trunc('month', s.created_at), 'YYYY-MM')
    )
    SELECT 
        s.sku,
        jsonb_agg(jsonb_build_object('month', s.month, 'total_quantity', s.total_quantity)) as monthly_sales
    FROM monthly_sales_data s
    GROUP BY s.sku;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_historical_sales TO anon, authenticated;

-- =====================================================
-- FIX: Handle dependent objects before dropping tables
-- =====================================================
DO $$ 
BEGIN
    IF EXISTS (
        SELECT 1 
        FROM information_schema.table_constraints 
        WHERE constraint_name = 'return_items_order_item_id_fkey'
        AND table_name = 'return_items'
    ) THEN
        ALTER TABLE public.return_items DROP CONSTRAINT return_items_order_item_id_fkey;
    END IF;
    
    DROP TABLE IF EXISTS public.order_items CASCADE;
    DROP TABLE IF EXISTS public.orders CASCADE;
END $$;

-- =====================================================
-- Create Sales Tables (if they don't already exist)
-- =====================================================
CREATE TABLE IF NOT EXISTS public.sales (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id UUID NOT NULL REFERENCES companies(id),
  sale_number TEXT NOT NULL,
  customer_name TEXT,
  customer_email TEXT,
  total_amount NUMERIC(10,2) NOT NULL,
  payment_method TEXT NOT NULL DEFAULT 'card',
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID REFERENCES auth.users(id),
  external_id TEXT,
  CONSTRAINT unique_sale_number_per_company UNIQUE (company_id, sale_number)
);
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage sales for their own company"
    ON public.sales FOR ALL
    USING (company_id = (SELECT company_id FROM users WHERE id = auth.uid()));


CREATE TABLE IF NOT EXISTS public.sale_items (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  sale_id UUID NOT NULL REFERENCES sales(id) ON DELETE CASCADE,
  sku TEXT NOT NULL,
  product_name TEXT NOT NULL,
  quantity INTEGER NOT NULL,
  unit_price NUMERIC(10,2) NOT NULL,
  cost_at_time NUMERIC(10,2),
  created_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.sale_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage sale items for sales in their own company"
    ON public.sale_items FOR ALL
    USING (sale_id IN (SELECT id FROM sales WHERE company_id = (SELECT company_id FROM users WHERE id = auth.uid())));

-- Indexes for Sales
CREATE INDEX IF NOT EXISTS idx_sales_company_date ON public.sales(company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sales_customer ON public.sales(customer_name);
CREATE INDEX IF NOT EXISTS idx_sale_items_sku ON public.sale_items(sku);
CREATE INDEX IF NOT EXISTS idx_sale_items_sale_id ON public.sale_items(sale_id);


-- Function to record a sale atomically
CREATE OR REPLACE FUNCTION public.record_sale_transaction(
    p_company_id uuid,
    p_user_id uuid,
    p_sale_items jsonb, -- [{sku, product_name, quantity, unit_price, cost_at_time}]
    p_customer_name text,
    p_customer_email text,
    p_payment_method text,
    p_notes text,
    p_external_id text DEFAULT NULL
) RETURNS public.sales
LANGUAGE plpgsql
AS $$
DECLARE
    new_sale public.sales;
    item record;
    total_sale_amount numeric := 0;
    new_sale_number text;
BEGIN
    FOR item IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(sku text, quantity int, unit_price numeric)
    LOOP
        total_sale_amount := total_sale_amount + (item.quantity * item.unit_price);
    END LOOP;

    IF p_external_id IS NULL THEN
        new_sale_number := 'SALE-' || to_char(NOW(), 'YYYYMMDD') || '-' || (
            SELECT COALESCE(MAX(SUBSTRING(sale_number, -3)::int), 0) + 1 FROM sales WHERE company_id = p_company_id AND sale_number LIKE 'SALE-' || to_char(NOW(), 'YYYYMMDD') || '%'
        )::text;
    ELSE
        new_sale_number := 'EXT-' || p_external_id;
    END IF;

    INSERT INTO public.sales (company_id, created_by, sale_number, customer_name, customer_email, total_amount, payment_method, notes, external_id)
    VALUES (p_company_id, p_user_id, new_sale_number, p_customer_name, p_customer_email, total_sale_amount, p_payment_method, p_notes, p_external_id)
    ON CONFLICT (company_id, external_id) WHERE p_external_id IS NOT NULL
    DO UPDATE SET
        customer_name = EXCLUDED.customer_name,
        total_amount = EXCLUDED.total_amount,
        notes = EXCLUDED.notes,
        created_at = EXCLUDED.created_at
    RETURNING * INTO new_sale;


    FOR item IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(sku text, product_name text, quantity int, unit_price numeric, cost_at_time numeric)
    LOOP
        INSERT INTO public.sale_items (sale_id, sku, product_name, quantity, unit_price, cost_at_time)
        VALUES (new_sale.id, item.sku, item.product_name, item.quantity, item.unit_price, item.cost_at_time);

        UPDATE inventory 
        SET quantity = quantity - item.quantity,
            last_sold_date = NOW(),
            updated_at = NOW()
        WHERE company_id = p_company_id AND sku = item.sku;

        INSERT INTO inventory_ledger (company_id, sku, change_type, quantity_change, new_quantity, related_id, notes)
        SELECT p_company_id, item.sku, 'sale', -item.quantity, i.quantity, new_sale.id, 'Sale #' || new_sale.sale_number
        FROM inventory i WHERE i.company_id = p_company_id AND i.sku = item.sku;
    END LOOP;

    IF p_customer_email IS NOT NULL THEN
        PERFORM public.update_customer_stats_from_sale(p_company_id, p_customer_email, total_sale_amount);
    END IF;

    RETURN new_sale;
END;
$$;
GRANT EXECUTE ON FUNCTION public.record_sale_transaction TO authenticated;

-- Grant permissions for new tables
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sales TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sale_items TO authenticated;

-- =====================================================
-- FIXES FOR FINAL SET OF ERRORS
-- =====================================================

-- Anomaly Insights RPC using `sales` table
DROP FUNCTION IF EXISTS public.get_anomaly_insights(uuid);
CREATE OR REPLACE FUNCTION public.get_anomaly_insights(p_company_id uuid)
RETURNS TABLE (
    date date,
    daily_revenue numeric,
    daily_customers bigint,
    avg_revenue numeric,
    avg_customers numeric,
    anomaly_type text,
    deviation_percentage numeric
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH daily_stats AS (
        SELECT
            s.created_at::date as date,
            SUM(s.total_amount) as revenue,
            COUNT(DISTINCT s.customer_email) as customers
        FROM public.sales s
        WHERE s.company_id = p_company_id
        GROUP BY s.created_at::date
    ),
    avg_stats AS (
        SELECT
            AVG(revenue) as avg_revenue,
            AVG(customers) as avg_customers,
            STDDEV(revenue) as stddev_revenue,
            STDDEV(customers) as stddev_customers
        FROM daily_stats
        WHERE date >= now() - interval '30 days'
    )
    SELECT
        ds.date,
        ds.revenue as daily_revenue,
        ds.customers as daily_customers,
        a.avg_revenue,
        a.avg_customers,
        CASE
            WHEN ds.revenue > a.avg_revenue + (2 * a.stddev_revenue) THEN 'Revenue Anomaly'
            WHEN ds.customers > a.avg_customers + (2 * a.stddev_customers) THEN 'Customer Anomaly'
            ELSE 'No Anomaly'
        END::text as anomaly_type,
        CASE
            WHEN ds.revenue > a.avg_revenue + (2 * a.stddev_revenue) THEN (ds.revenue - a.avg_revenue) / a.avg_revenue * 100
            WHEN ds.customers > a.avg_customers + (2 * a.stddev_customers) THEN (ds.customers - a.avg_customers) / a.avg_customers * 100
            ELSE 0
        END::numeric as deviation_percentage
    FROM daily_stats ds, avg_stats a
    WHERE
        ds.date >= now() - interval '7 days' AND
        (ds.revenue > a.avg_revenue + (2 * a.stddev_revenue) OR ds.customers > a.avg_customers + (2 * a.stddev_customers));
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_anomaly_insights(uuid) TO authenticated;

-- Alerts RPC using `sales` table
DROP FUNCTION IF EXISTS public.get_alerts(uuid, integer, integer, integer);
CREATE OR REPLACE FUNCTION public.get_alerts(
    p_company_id uuid,
    p_dead_stock_days integer,
    p_fast_moving_days integer,
    p_predictive_stock_days integer
) RETURNS TABLE (
    type text,
    sku text,
    product_name text,
    current_stock integer,
    reorder_point integer,
    last_sold_date date,
    value numeric,
    days_of_stock_remaining numeric
)
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
      AND i.quantity > 0
      AND i.reorder_point IS NOT NULL
      AND i.quantity < i.reorder_point

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
      AND (i.quantity / sv.daily_sales) <= p_predictive_stock_days;
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_alerts(uuid, integer, integer, integer) TO authenticated;

-- Dead Stock Alerts Data Function (to fix type mismatch)
DROP FUNCTION IF EXISTS public.get_dead_stock_alerts_data(uuid, integer);
CREATE OR REPLACE FUNCTION public.get_dead_stock_alerts_data(p_company_id uuid, p_dead_stock_days integer)
RETURNS TABLE (
    sku text,
    product_name text,
    quantity numeric,
    cost numeric,
    total_value numeric,
    last_sale_date date
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        i.sku::text,
        i.name::text,
        i.quantity::numeric,
        i.cost::numeric,
        (i.quantity * i.cost)::numeric,
        i.last_sold_date::date
    FROM inventory i
    WHERE i.company_id = p_company_id
    AND i.last_sold_date < (now() - (p_dead_stock_days || ' day')::interval)
    AND i.deleted_at IS NULL;
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_dead_stock_alerts_data(uuid, integer) TO authenticated;

-- =====================================================
-- Script completed successfully!
-- =====================================================
    