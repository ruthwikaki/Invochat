-- Fix AI Functions to work with existing database schema
-- This script creates the missing R                SUM(oli.quanti                SUM(oli.quantity * COALESCE(oli.cost_at_time, pv.cost, 0)) as cost,
                ROUND(((SUM(oli.quantity * oli.price) - SUM(oli.quantity * COALESCE(oli.cost_at_time, pv.cost, 0))) / NULLIF(SUM(oli.quantity * oli.price), 0) * 100)::numeric, 2) as margin_percentage * COALESCE(oli.cost_at_time, pv.cost, 0)) as total_cost,
                ROUND(((SUM(oli.quantity * oli.price) - SUM(oli.quantity * COALESCE(oli.cost_at_time, pv.cost, 0))) / NULLIF(SUM(oli.quantity * oli.price), 0) * 100)::numeric, 2) as margin_percentage,
                SUM(oli.quantity * oli.price) - SUM(oli.quantity * COALESCE(oli.cost_at_time, pv.cost, 0)) as gross_profitfunctions that AI features expect
-- Uses the actual table structure (orders, order_line_items, etc.)

-- Drop and recreate the missing functions to use correct table names

-- Function: get_sales_velocity
CREATE OR REPLACE FUNCTION public.get_sales_velocity(p_company_id uuid, p_days integer DEFAULT 30, p_limit integer DEFAULT 50)
RETURNS JSON
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN (
        SELECT COALESCE(json_agg(t), '[]'::json)
        FROM (
            SELECT
                oli.sku,
                oli.product_name,
                SUM(oli.quantity) as total_sold,
                COUNT(DISTINCT o.id) as num_transactions,
                AVG(oli.price) as avg_price,
                SUM(oli.quantity * oli.price) as total_revenue,
                ROUND(SUM(oli.quantity)::numeric / NULLIF(p_days, 0), 2) as velocity_per_day
            FROM order_line_items oli
            JOIN orders o ON oli.order_id = o.id
            WHERE oli.company_id = p_company_id
            AND o.created_at >= NOW() - INTERVAL '1 day' * p_days
            AND o.financial_status = 'paid'
            GROUP BY oli.sku, oli.product_name
            ORDER BY total_sold DESC
            LIMIT p_limit
        ) t
    );
END;
$$;

-- Function: get_abc_analysis
CREATE OR REPLACE FUNCTION public.get_abc_analysis(p_company_id uuid)
RETURNS JSON
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN (
        SELECT COALESCE(json_agg(t), '[]'::json)
        FROM (
            WITH revenue_data AS (
                SELECT
                    oli.sku,
                    oli.product_name,
                    SUM(oli.quantity * oli.price) as revenue
                FROM order_line_items oli
                JOIN orders o ON oli.order_id = o.id
                WHERE oli.company_id = p_company_id
                AND o.created_at >= NOW() - INTERVAL '90 days'
                AND o.financial_status = 'paid'
                GROUP BY oli.sku, oli.product_name
            ),
            ranked_data AS (
                SELECT *,
                    SUM(revenue) OVER () as total_revenue,
                    SUM(revenue) OVER (ORDER BY revenue DESC) as cumulative_revenue
                FROM revenue_data
            )
            SELECT
                sku,
                product_name,
                revenue,
                ROUND((revenue / NULLIF(total_revenue, 0) * 100)::numeric, 2) as revenue_percentage,
                ROUND((cumulative_revenue / NULLIF(total_revenue, 0) * 100)::numeric, 2) as cumulative_percentage,
                CASE
                    WHEN cumulative_revenue / NULLIF(total_revenue, 0) <= 0.8 THEN 'A'
                    WHEN cumulative_revenue / NULLIF(total_revenue, 0) <= 0.95 THEN 'B'
                    ELSE 'C'
                END as category
            FROM ranked_data
            ORDER BY revenue DESC
        ) t
    );
END;
$$;

-- Function: get_gross_margin_analysis
CREATE OR REPLACE FUNCTION public.get_gross_margin_analysis(p_company_id uuid)
RETURNS JSON
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN (
        SELECT COALESCE(json_agg(t), '[]'::json)
        FROM (
            SELECT
                oli.sku,
                oli.product_name,
                SUM(oli.quantity) as total_sold,
                SUM(oli.quantity * oli.price) as total_revenue,
                SUM(oli.quantity * COALESCE(oli.cost_at_time, inv.cost, 0)) as total_cost,
                ROUND(((SUM(oli.quantity * oli.price) - SUM(oli.quantity * COALESCE(oli.cost_at_time, inv.cost, 0))) / NULLIF(SUM(oli.quantity * oli.price), 0) * 100)::numeric, 2) as margin_percentage,
                SUM(oli.quantity * oli.price) - SUM(oli.quantity * COALESCE(oli.cost_at_time, inv.cost, 0)) as gross_profit
            FROM order_line_items oli
            JOIN orders o ON oli.order_id = o.id
            LEFT JOIN product_variants pv ON pv.sku = oli.sku AND pv.company_id = oli.company_id
            WHERE oli.company_id = p_company_id
            AND o.created_at >= NOW() - INTERVAL '90 days'
            AND o.financial_status = 'paid'
            GROUP BY oli.sku, oli.product_name
            ORDER BY gross_profit DESC
        ) t
    );
END;
$$;

-- Function: get_margin_trends
CREATE OR REPLACE FUNCTION public.get_margin_trends(p_company_id uuid)
RETURNS JSON
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN (
        SELECT COALESCE(json_agg(t), '[]'::json)
        FROM (
            SELECT
                DATE_TRUNC('week', o.created_at) as week,
                SUM(oli.quantity * oli.price) as revenue,
                SUM(oli.quantity * COALESCE(oli.cost_at_time, inv.cost, 0)) as cost,
                ROUND(((SUM(oli.quantity * oli.price) - SUM(oli.quantity * COALESCE(oli.cost_at_time, inv.cost, 0))) / NULLIF(SUM(oli.quantity * oli.price), 0) * 100)::numeric, 2) as margin_percentage
            FROM order_line_items oli
            JOIN orders o ON oli.order_id = o.id
            LEFT JOIN product_variants pv ON pv.sku = oli.sku AND pv.company_id = oli.company_id
            WHERE oli.company_id = p_company_id
            AND o.created_at >= NOW() - INTERVAL '12 weeks'
            AND o.financial_status = 'paid'
            GROUP BY DATE_TRUNC('week', o.created_at)
            ORDER BY week
        ) t
    );
END;
$$;

-- Function: forecast_demand (simplified version)
CREATE OR REPLACE FUNCTION public.forecast_demand(p_company_id uuid)
RETURNS JSON
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN (
        SELECT COALESCE(json_agg(t), '[]'::json)
        FROM (
            SELECT
                oli.sku,
                oli.product_name,
                AVG(weekly_qty) as avg_weekly_demand,
                ROUND(AVG(weekly_qty) * 4, 0) as forecasted_monthly_demand,
                CASE
                    WHEN AVG(weekly_qty) * 4 > pv.inventory_quantity THEN 'REORDER_SOON'
                    WHEN AVG(weekly_qty) * 2 > pv.inventory_quantity THEN 'MONITOR'
                    ELSE 'ADEQUATE'
                END as stock_status
            FROM (
                SELECT
                    oli.sku,
                    oli.product_name,
                    DATE_TRUNC('week', o.created_at) as week,
                    SUM(oli.quantity) as weekly_qty
                FROM order_line_items oli
                JOIN orders o ON oli.order_id = o.id
                WHERE oli.company_id = p_company_id
                AND o.created_at >= NOW() - INTERVAL '12 weeks'
                AND o.financial_status = 'paid'
                GROUP BY oli.sku, oli.product_name, DATE_TRUNC('week', o.created_at)
            ) weekly_data
            LEFT JOIN product_variants pv ON pv.sku = weekly_data.sku AND pv.company_id = p_company_id
            GROUP BY weekly_data.sku, weekly_data.product_name, pv.inventory_quantity
            ORDER BY avg_weekly_demand DESC
        ) t
    );
END;
$$;

-- Function: get_financial_impact_of_promotion
CREATE OR REPLACE FUNCTION public.get_financial_impact_of_promotion(p_company_id uuid, p_skus text[], p_discount_percentage numeric, p_duration_days integer)
RETURNS JSON
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN (
        SELECT COALESCE(json_agg(t), '[]'::json)
        FROM (
            SELECT
                oli.sku,
                oli.product_name,
                AVG(oli.price) as current_price,
                AVG(oli.price) * (1 - p_discount_percentage / 100) as discounted_price,
                AVG(daily_qty) as avg_daily_sales,
                ROUND(AVG(daily_qty) * p_duration_days, 0) as estimated_units_sold,
                ROUND(AVG(daily_qty) * p_duration_days * AVG(oli.price) * (1 - p_discount_percentage / 100), 2) as estimated_revenue,
                ROUND(AVG(daily_qty) * p_duration_days * (AVG(oli.price) * (1 - p_discount_percentage / 100) - AVG(COALESCE(oli.cost_at_time, pv.cost, 0))), 2) as estimated_profit
            FROM (
                SELECT
                    oli.sku,
                    oli.product_name,
                    oli.price,
                    oli.cost_at_time,
                    DATE_TRUNC('day', o.created_at) as day,
                    SUM(oli.quantity) as daily_qty
                FROM order_line_items oli
                JOIN orders o ON oli.order_id = o.id
                WHERE oli.company_id = p_company_id
                AND oli.sku = ANY(p_skus)
                AND o.created_at >= NOW() - INTERVAL '30 days'
                AND o.financial_status = 'paid'
                GROUP BY oli.sku, oli.product_name, oli.price, oli.cost_at_time, DATE_TRUNC('day', o.created_at)
            ) daily_data
            LEFT JOIN product_variants pv ON pv.sku = daily_data.sku AND pv.company_id = p_company_id
            GROUP BY daily_data.sku, daily_data.product_name
        ) t
    );
END;
$$;
