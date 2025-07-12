-- =================================================================
-- InvoChat - Database Update Script
-- Version: 1.1
-- Description: Adds new functions and views for advanced analytics features.
-- This script is designed to be run on an existing database.
-- =================================================================

-- Drop existing functions if they exist to ensure they are replaced with the new versions.
DROP FUNCTION IF EXISTS public.get_inventory_aging_report(uuid);
DROP FUNCTION IF EXISTS public.get_product_lifecycle_analysis(uuid);
DROP FUNCTION IF EXISTS public.get_inventory_risk_report(uuid);
DROP FUNCTION IF EXISTS public.get_customer_segment_analysis(uuid);
DROP FUNCTION IF EXISTS public.get_cash_flow_insights(uuid);
DROP FUNCTION IF EXISTS public.get_financial_impact_of_promotion(uuid, text[], numeric, integer);
DROP FUNCTION IF EXISTS public.get_profit_warning_alerts(uuid);
DROP FUNCTION IF EXISTS public.get_alerts(uuid,integer,integer,integer);


-- =================================================================
-- Function: get_inventory_aging_report
-- Description: Calculates how long inventory has been sitting on shelves.
-- =================================================================
CREATE OR REPLACE FUNCTION public.get_inventory_aging_report(p_company_id uuid)
RETURNS TABLE(sku text, product_name text, quantity integer, total_value integer, days_since_last_sale integer)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        i.sku,
        i.name as product_name,
        i.quantity,
        (i.quantity * i.cost)::integer AS total_value,
        COALESCE(EXTRACT(DAY FROM (NOW() - i.last_sold_date))::integer, 9999) AS days_since_last_sale
    FROM
        public.inventory i
    WHERE
        i.company_id = p_company_id
        AND i.deleted_at IS NULL
        AND i.quantity > 0
    ORDER BY
        days_since_last_sale DESC;
END;
$$;


-- =================================================================
-- Function: get_product_lifecycle_analysis
-- Description: Categorizes products into lifecycle stages (Launch, Growth, Maturity, Decline).
-- =================================================================
CREATE OR REPLACE FUNCTION public.get_product_lifecycle_analysis(p_company_id uuid)
RETURNS json
LANGUAGE plpgsql
AS $$
DECLARE
    result json;
BEGIN
    WITH sales_history AS (
        SELECT
            si.sku,
            s.created_at
        FROM public.sale_items si
        JOIN public.sales s ON si.sale_id = s.id
        WHERE s.company_id = p_company_id
    ),
    product_sales_windows AS (
        SELECT
            i.sku,
            i.name as product_name,
            i.created_at as product_created_at,
            COALESCE(SUM(CASE WHEN sh.created_at >= NOW() - INTERVAL '90 days' THEN 1 ELSE 0 END), 0) as sales_last_90_days,
            COALESCE(SUM(CASE WHEN sh.created_at >= NOW() - INTERVAL '180 days' AND sh.created_at < NOW() - INTERVAL '90 days' THEN 1 ELSE 0 END), 0) as sales_prev_90_days,
            (SELECT MAX(created_at) FROM sales_history WHERE sku = i.sku) as last_sale_date
        FROM public.inventory i
        LEFT JOIN sales_history sh ON i.sku = sh.sku
        WHERE i.company_id = p_company_id
          AND i.deleted_at IS NULL
        GROUP BY i.id, i.sku, i.name
    ),
    categorized_products AS (
        SELECT
            psw.sku,
            psw.product_name,
            psw.sales_last_90_days,
            psw.sales_prev_90_days,
            psw.last_sale_date,
            CASE
                WHEN psw.product_created_at >= NOW() - INTERVAL '60 days' AND psw.last_sale_date IS NOT NULL THEN 'Launch'
                WHEN psw.sales_last_90_days > psw.sales_prev_90_days * 1.2 AND psw.sales_last_90_days > 5 THEN 'Growth'
                WHEN psw.sales_last_90_days > 0 AND psw.sales_prev_90_days > 0 AND ABS(psw.sales_last_90_days - psw.sales_prev_90_days)::decimal / psw.sales_prev_90_days <= 0.2 THEN 'Maturity'
                ELSE 'Decline'
            END as stage,
            (SELECT i.price * i.quantity FROM public.inventory i WHERE i.sku = psw.sku and i.company_id = p_company_id) as total_revenue
        FROM product_sales_windows psw
    )
    SELECT json_build_object(
        'summary', (
            SELECT json_build_object(
                'launch_count', COUNT(*) FILTER (WHERE stage = 'Launch'),
                'growth_count', COUNT(*) FILTER (WHERE stage = 'Growth'),
                'maturity_count', COUNT(*) FILTER (WHERE stage = 'Maturity'),
                'decline_count', COUNT(*) FILTER (WHERE stage = 'Decline')
            ) FROM categorized_products
        ),
        'products', (SELECT json_agg(cp) FROM categorized_products cp)
    ) INTO result;

    RETURN result;
END;
$$;


-- =================================================================
-- Function: get_inventory_risk_report
-- Description: Assigns a risk score to each product.
-- =================================================================
CREATE OR REPLACE FUNCTION public.get_inventory_risk_report(p_company_id uuid)
RETURNS TABLE(sku text, product_name text, risk_score integer, risk_level text, total_value integer, reason text)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH risk_factors AS (
        SELECT
            i.sku,
            i.name as product_name,
            i.quantity * i.cost as total_value,
            (CASE WHEN i.last_sold_date IS NULL THEN 999 ELSE EXTRACT(DAY FROM NOW() - i.last_sold_date) END) as days_since_last_sale,
            COALESCE((i.price - i.cost) / NULLIF(i.price, 0), 0) as margin
        FROM public.inventory i
        WHERE i.company_id = p_company_id AND i.deleted_at IS NULL and i.quantity > 0
    )
    SELECT
        rf.sku,
        rf.product_name,
        LEAST(100, (
            (rf.days_since_last_sale / 3) + -- 30 points for 90 days old
            ((1 - rf.margin) * 50) + -- 50 points for 0% margin
            (rf.total_value / 10000) -- 10 points for $1000 value
        ))::integer AS risk_score,
        CASE
            WHEN LEAST(100, ((rf.days_since_last_sale / 3) + ((1 - rf.margin) * 50) + (rf.total_value / 10000))) > 75 THEN 'High'
            WHEN LEAST(100, ((rf.days_since_last_sale / 3) + ((1 - rf.margin) * 50) + (rf.total_value / 10000))) > 50 THEN 'Medium'
            ELSE 'Low'
        END AS risk_level,
        rf.total_value::integer,
        'Days since last sale: ' || rf.days_since_last_sale || ', Margin: ' || (rf.margin * 100)::integer || '%' as reason
    FROM risk_factors rf
    ORDER BY risk_score DESC;
END;
$$;


-- =================================================================
-- Function: get_customer_segment_analysis
-- Description: Shows which products are popular with different customer segments.
-- =================================================================
CREATE OR REPLACE FUNCTION public.get_customer_segment_analysis(p_company_id uuid)
RETURNS TABLE(segment text, sku text, product_name text, total_quantity bigint, total_revenue integer)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH customer_segments AS (
        SELECT
            c.id as customer_id,
            CASE
                WHEN c.total_orders = 1 THEN 'New Customers'
                WHEN c.total_orders > 1 THEN 'Repeat Customers'
            END as segment
        FROM public.customers c
        WHERE c.company_id = p_company_id
    ),
    top_spenders AS (
        SELECT c.id as customer_id, 'Top Spenders' as segment
        FROM public.customers c
        WHERE c.company_id = p_company_id
        ORDER BY c.total_spent DESC
        LIMIT (SELECT CEIL(COUNT(*) * 0.1) FROM public.customers WHERE company_id = p_company_id) -- Top 10%
    ),
    all_segments AS (
        SELECT customer_id, segment FROM customer_segments
        UNION ALL
        SELECT customer_id, segment FROM top_spenders
    )
    SELECT
        s.segment,
        si.sku,
        si.product_name,
        SUM(si.quantity)::bigint as total_quantity,
        SUM(si.quantity * si.unit_price)::integer as total_revenue
    FROM public.sales sa
    JOIN public.sale_items si ON sa.id = si.sale_id
    JOIN public.customers c ON sa.customer_email = c.email AND sa.company_id = c.company_id
    JOIN all_segments s ON c.id = s.customer_id
    WHERE sa.company_id = p_company_id
    GROUP BY s.segment, si.sku, si.product_name
    ORDER BY s.segment, total_revenue DESC;
END;
$$;


-- =================================================================
-- Function: get_cash_flow_insights
-- Description: Calculates value tied up in dead and slow-moving stock.
-- =================================================================
CREATE OR REPLACE FUNCTION public.get_cash_flow_insights(p_company_id uuid)
RETURNS TABLE(dead_stock_value integer, slow_mover_value integer, dead_stock_threshold_days integer)
LANGUAGE plpgsql
AS $$
DECLARE
    v_dead_stock_days int;
BEGIN
    SELECT cs.dead_stock_days INTO v_dead_stock_days
    FROM public.company_settings cs
    WHERE cs.company_id = p_company_id;

    RETURN QUERY
    SELECT
        COALESCE(SUM(CASE WHEN (NOW()::date - i.last_sold_date) > v_dead_stock_days THEN i.quantity * i.cost ELSE 0 END), 0)::integer as dead_stock_value,
        COALESCE(SUM(CASE WHEN (NOW()::date - i.last_sold_date) BETWEEN 30 AND v_dead_stock_days THEN i.quantity * i.cost ELSE 0 END), 0)::integer as slow_mover_value,
        v_dead_stock_days as dead_stock_threshold_days
    FROM public.inventory i
    WHERE i.company_id = p_company_id
      AND i.last_sold_date IS NOT NULL
      AND i.deleted_at IS NULL;
END;
$$;

-- =================================================================
-- Function: get_financial_impact_of_promotion
-- Description: Analyzes financial impact of a potential promotion.
-- =================================================================
CREATE OR REPLACE FUNCTION public.get_financial_impact_of_promotion(
    p_company_id uuid,
    p_skus text[],
    p_discount_percentage numeric,
    p_duration_days integer
)
RETURNS TABLE(
    estimated_sales_increase_percentage numeric,
    estimated_additional_units_sold integer,
    estimated_gross_revenue numeric,
    estimated_revenue_from_promo numeric,
    estimated_profit numeric
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_sales_velocity numeric;
    v_total_cost numeric;
BEGIN
    -- Simplified logic: get average daily sales for these SKUs
    SELECT COALESCE(SUM(si.quantity), 0) / 90.0 INTO v_sales_velocity
    FROM public.sale_items si
    JOIN public.sales s ON si.sale_id = s.id
    WHERE s.company_id = p_company_id
      AND si.sku = ANY(p_skus)
      AND s.created_at >= NOW() - INTERVAL '90 days';

    -- Estimate increased sales (simplified model)
    estimated_sales_increase_percentage := p_discount_percentage * 2.5;
    estimated_additional_units_sold := (v_sales_velocity * p_duration_days * estimated_sales_increase_percentage)::integer;
    
    -- Calculate estimated revenue and profit
    SELECT
        (estimated_additional_units_sold * i.price * (1 - p_discount_percentage)) as revenue,
        (estimated_additional_units_sold * (i.price * (1 - p_discount_percentage) - i.cost)) as profit,
        (estimated_additional_units_sold * i.price) as gross_revenue
    INTO
        estimated_revenue_from_promo,
        estimated_profit,
        estimated_gross_revenue
    FROM public.inventory i
    WHERE i.company_id = p_company_id AND i.sku = p_skus[1]
    LIMIT 1;
    
    RETURN NEXT;
END;
$$;

-- =================================================================
-- Function: get_profit_warning_alerts
-- Description: Identifies products with declining profit margins.
-- =================================================================
CREATE OR REPLACE FUNCTION public.get_profit_warning_alerts(p_company_id uuid)
RETURNS TABLE(
    product_id uuid,
    sku text,
    product_name text,
    recent_margin numeric,
    previous_margin numeric
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH sales_with_margin AS (
        SELECT
            si.sku,
            s.created_at,
            (si.unit_price - si.cost_at_time)::numeric / NULLIF(si.unit_price, 0) as margin
        FROM public.sale_items si
        JOIN public.sales s ON si.sale_id = s.id
        WHERE s.company_id = p_company_id
          AND si.unit_price > 0 AND si.cost_at_time IS NOT NULL
    ),
    margin_periods AS (
        SELECT
            sku,
            AVG(margin) FILTER (WHERE created_at >= NOW() - INTERVAL '90 days') as recent_margin,
            AVG(margin) FILTER (WHERE created_at < NOW() - INTERVAL '90 days' AND created_at >= NOW() - INTERVAL '180 days') as previous_margin
        FROM sales_with_margin
        GROUP BY sku
    )
    SELECT
        i.id,
        mp.sku,
        i.name,
        mp.recent_margin,
        mp.previous_margin
    FROM margin_periods mp
    JOIN public.inventory i ON mp.sku = i.sku AND i.company_id = p_company_id
    WHERE mp.recent_margin IS NOT NULL
      AND mp.previous_margin IS NOT NULL
      AND mp.recent_margin < mp.previous_margin * 0.9; -- 10% drop in margin
END;
$$;


-- =================================================================
-- Function: get_alerts (MODIFIED)
-- Description: Consolidates all alert types into a single query.
-- =================================================================
CREATE OR REPLACE FUNCTION public.get_alerts(
    p_company_id uuid,
    p_dead_stock_days integer,
    p_fast_moving_days integer,
    p_predictive_stock_days integer
)
RETURNS TABLE(
    id text,
    type text,
    title text,
    message text,
    severity text,
    "timestamp" timestamptz,
    metadata jsonb
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    -- Low Stock Alerts
    SELECT
        'low_stock_' || i.id::text as id,
        'low_stock' as type,
        'Low Stock Warning' as title,
        i.name || ' is running low on stock.' as message,
        'warning' as severity,
        NOW() as "timestamp",
        jsonb_build_object(
            'productId', i.id,
            'productName', i.name,
            'currentStock', i.quantity,
            'reorderPoint', i.reorder_point
        ) as metadata
    FROM public.inventory i
    WHERE i.company_id = p_company_id
      AND i.quantity > 0
      AND i.reorder_point IS NOT NULL
      AND i.quantity < i.reorder_point
      AND i.deleted_at IS NULL

    UNION ALL

    -- Predictive Out of Stock Alerts
    WITH sales_velocity AS (
        SELECT
            si.sku,
            SUM(si.quantity)::numeric / p_fast_moving_days as daily_velocity
        FROM public.sale_items si
        JOIN public.sales s ON si.sale_id = s.id
        WHERE s.company_id = p_company_id
          AND s.created_at >= NOW() - (p_fast_moving_days || ' days')::interval
        GROUP BY si.sku
    )
    SELECT
        'predictive_' || i.id::text as id,
        'predictive' as type,
        'Predictive Stock Alert' as title,
        'Based on current sales velocity, ' || i.name || ' is predicted to run out of stock soon.' as message,
        'info' as severity,
        NOW() as "timestamp",
        jsonb_build_object(
            'productId', i.id,
            'productName', i.name,
            'currentStock', i.quantity,
            'daysOfStockRemaining', i.quantity / sv.daily_velocity
        ) as metadata
    FROM public.inventory i
    JOIN sales_velocity sv ON i.sku = sv.sku
    WHERE i.company_id = p_company_id
      AND i.deleted_at IS NULL
      AND sv.daily_velocity > 0
      AND (i.quantity / sv.daily_velocity) <= p_predictive_stock_days

    UNION ALL
    
    -- Profit Warning Alerts
    SELECT
        'profit_warning_' || pwa.product_id::text,
        'profit_warning',
        'Profitability Warning',
        'The profit margin for ' || pwa.product_name || ' has decreased significantly.',
        'warning',
        NOW(),
        jsonb_build_object(
            'productId', pwa.product_id,
            'productName', pwa.product_name,
            'recent_margin', pwa.recent_margin,
            'previous_margin', pwa.previous_margin
        )
    FROM public.get_profit_warning_alerts(p_company_id) pwa;

END;
$$;


-- Add the company_id column to audit_log if it doesn't exist.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
        AND table_name = 'audit_log'
        AND column_name = 'company_id'
    ) THEN
        ALTER TABLE public.audit_log ADD COLUMN company_id uuid;
        ALTER TABLE public.audit_log ADD CONSTRAINT audit_log_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id);
    END IF;
END;
$$;

-- Grant usage on schema to supabase_auth_admin
GRANT USAGE ON SCHEMA public TO supabase_auth_admin;

-- Grant all privileges on tables to supabase_auth_admin
GRANT ALL ON ALL TABLES IN SCHEMA public TO supabase_auth_admin;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO supabase_auth_admin;

-- This is a placeholder for a real security review. In a production environment,
-- you would want to grant more granular permissions.
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO supabase_auth_admin;


ALTER TABLE public.sale_items
ADD COLUMN IF NOT EXISTS company_id uuid;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_sale_items_company'
          AND conrelid = 'public.sale_items'::regclass
    ) THEN
        ALTER TABLE public.sale_items
        ADD CONSTRAINT fk_sale_items_company
        FOREIGN KEY (company_id) REFERENCES public.companies(id);
    END IF;
END;
$$;
