-- InvoChat - Conversational Inventory Intelligence
-- This is a partial schema for adding new features and functions.
-- It is designed to be idempotent and can be run multiple times safely.

-- Add a new column to company_settings for configurable promo lift
ALTER TABLE public.company_settings
ADD COLUMN IF NOT EXISTS promo_sales_lift_multiplier numeric NOT NULL DEFAULT 2.0;


-- Drop the old functions if they exist to avoid signature conflicts
DROP FUNCTION IF EXISTS public.get_financial_impact_of_promotion(uuid, text[], numeric, integer);
DROP FUNCTION IF EXISTS public.get_demand_forecast(uuid);


-- Recreate the get_financial_impact_of_promotion function with a new signature and logic
CREATE OR REPLACE FUNCTION public.get_financial_impact_of_promotion(p_company_id uuid, p_skus text[], p_discount_percentage numeric, p_duration_days integer)
RETURNS TABLE(
    sku text,
    product_name text,
    current_price integer,
    discounted_price integer,
    base_daily_sales numeric,
    estimated_lift_factor numeric,
    estimated_daily_sales_lift numeric,
    total_estimated_sales_units numeric,
    estimated_base_revenue numeric,
    estimated_promo_revenue numeric,
    estimated_revenue_change numeric,
    estimated_base_profit numeric,
    estimated_promo_profit numeric,
    estimated_profit_change numeric
)
LANGUAGE plpgsql
AS $$
DECLARE
    settings_row public.company_settings;
BEGIN
    -- Get the configurable sales lift multiplier
    SELECT * INTO settings_row FROM public.company_settings WHERE company_id = p_company_id;

    RETURN QUERY
    WITH promo_products AS (
        SELECT
            i.sku,
            i.name AS product_name,
            i.price AS current_price_cents,
            i.cost AS cost_cents
        FROM public.inventory i
        WHERE i.company_id = p_company_id AND i.sku = ANY(p_skus)
    ),
    sales_data AS (
        SELECT
            si.sku,
            -- Calculate average daily sales over the last 90 days
            COALESCE(SUM(si.quantity)::numeric / 90.0, 0.01) AS base_daily_sales
        FROM public.sale_items si
        JOIN public.sales s ON si.sale_id = s.id
        WHERE s.company_id = p_company_id
            AND si.sku = ANY(p_skus)
            AND s.created_at >= (NOW() - INTERVAL '90 days')
        GROUP BY si.sku
    )
    SELECT
        pp.sku,
        pp.product_name,
        pp.current_price_cents,
        (pp.current_price_cents * (1 - p_discount_percentage))::integer AS discounted_price,
        COALESCE(sd.base_daily_sales, 0.01) AS base_daily_sales,
        -- Use a non-linear formula for more realistic lift estimation
        (1 + (settings_row.promo_sales_lift_multiplier * (1 - (1 - p_discount_percentage) ^ 2)))::numeric AS estimated_lift_factor,
        (COALESCE(sd.base_daily_sales, 0.01) * (1 + (settings_row.promo_sales_lift_multiplier * (1 - (1 - p_discount_percentage) ^ 2))))::numeric AS estimated_daily_sales_lift,
        (p_duration_days * (COALESCE(sd.base_daily_sales, 0.01) * (1 + (settings_row.promo_sales_lift_multiplier * (1 - (1 - p_discount_percentage) ^ 2)))))::numeric AS total_estimated_sales_units,
        (p_duration_days * COALESCE(sd.base_daily_sales, 0.01) * pp.current_price_cents)::numeric AS estimated_base_revenue,
        (p_duration_days * (COALESCE(sd.base_daily_sales, 0.01) * (1 + (settings_row.promo_sales_lift_multiplier * (1 - (1 - p_discount_percentage) ^ 2)))) * (pp.current_price_cents * (1 - p_discount_percentage)))::numeric AS estimated_promo_revenue,
        ((p_duration_days * (COALESCE(sd.base_daily_sales, 0.01) * (1 + (settings_row.promo_sales_lift_multiplier * (1 - (1 - p_discount_percentage) ^ 2)))) * (pp.current_price_cents * (1 - p_discount_percentage))) - (p_duration_days * COALESCE(sd.base_daily_sales, 0.01) * pp.current_price_cents))::numeric AS estimated_revenue_change,
        (p_duration_days * COALESCE(sd.base_daily_sales, 0.01) * (pp.current_price_cents - pp.cost_cents))::numeric AS estimated_base_profit,
        (p_duration_days * (COALESCE(sd.base_daily_sales, 0.01) * (1 + (settings_row.promo_sales_lift_multiplier * (1 - (1 - p_discount_percentage) ^ 2)))) * ((pp.current_price_cents * (1 - p_discount_percentage)) - pp.cost_cents))::numeric AS estimated_promo_profit,
        ((p_duration_days * (COALESCE(sd.base_daily_sales, 0.01) * (1 + (settings_row.promo_sales_lift_multiplier * (1 - (1 - p_discount_percentage) ^ 2)))) * ((pp.current_price_cents * (1 - p_discount_percentage)) - pp.cost_cents)) - (p_duration_days * COALESCE(sd.base_daily_sales, 0.01) * (pp.current_price_cents - pp.cost_cents)))::numeric AS estimated_profit_change
    FROM promo_products pp
    LEFT JOIN sales_data sd ON pp.sku = sd.sku;
END;
$$;


-- Recreate the get_demand_forecast function with improved logic
CREATE OR REPLACE FUNCTION public.get_demand_forecast(p_company_id uuid)
RETURNS TABLE(sku text, product_name text, forecast_30_days numeric)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH monthly_sales AS (
        SELECT
            si.sku,
            date_trunc('month', s.created_at) AS month,
            SUM(si.quantity) AS total_quantity
        FROM public.sales s
        JOIN public.sale_items si ON s.id = si.sale_id
        WHERE s.company_id = p_company_id
        GROUP BY si.sku, date_trunc('month', s.created_at)
    ),
    ewma_sales AS (
        SELECT
            sku,
            -- Calculate a 3-month exponentially weighted moving average for sales
            AVG(total_quantity) FILTER (WHERE month >= date_trunc('month', NOW()) - INTERVAL '3 months') * 0.5 +
            AVG(total_quantity) FILTER (WHERE month >= date_trunc('month', NOW()) - INTERVAL '6 months' AND month < date_trunc('month', NOW()) - INTERVAL '3 months') * 0.3 +
            AVG(total_quantity) FILTER (WHERE month >= date_trunc('month', NOW()) - INTERVAL '12 months' AND month < date_trunc('month', NOW()) - INTERVAL '6 months') * 0.2
            AS weighted_monthly_avg
        FROM monthly_sales
        GROUP BY sku
    )
    SELECT
        i.sku,
        i.name,
        -- Forecast for the next 30 days based on the weighted average
        round(COALESCE(es.weighted_monthly_avg, 0)) AS forecast_30_days
    FROM public.inventory i
    LEFT JOIN ewma_sales es ON i.sku = es.sku
    WHERE i.company_id = p_company_id
    ORDER BY COALESCE(es.weighted_monthly_avg, 0) DESC
    LIMIT 10;
END;
$$;

-- Recreate the get_customer_analytics function with safer logic for small customer bases
CREATE OR REPLACE FUNCTION public.get_customer_analytics(p_company_id uuid)
RETURNS json
LANGUAGE plpgsql
AS $$
DECLARE
    total_customers_count integer;
    top_customer_limit integer;
BEGIN
    -- Get total number of customers for the company
    SELECT COUNT(*) INTO total_customers_count
    FROM public.customers c
    WHERE c.company_id = p_company_id;

    -- Set limit for top customers: at least 1, or 10% for larger bases
    IF total_customers_count < 10 THEN
        top_customer_limit := 1;
    ELSE
        top_customer_limit := GREATEST(1, (total_customers_count * 0.1)::integer);
    END IF;

    RETURN (
        WITH customer_stats AS (
            SELECT
                c.id,
                c.customer_name,
                c.email,
                COUNT(s.id) AS total_orders,
                SUM(s.total_amount) AS total_spent
            FROM public.customers c
            JOIN public.sales s ON c.id = s.customer_id
            WHERE c.company_id = p_company_id
            GROUP BY c.id
        )
        SELECT json_build_object(
            'total_customers', total_customers_count,
            'new_customers_last_30_days', (
                SELECT COUNT(*)
                FROM public.customers c
                WHERE c.company_id = p_company_id AND c.created_at >= NOW() - INTERVAL '30 days'
            ),
            'repeat_customer_rate', (
                SELECT CASE WHEN COUNT(*) > 0 THEN
                    (COUNT(*) FILTER (WHERE total_orders > 1)::numeric / COUNT(*))
                ELSE 0 END
                FROM customer_stats
            ),
            'average_lifetime_value', (
                SELECT AVG(total_spent) FROM customer_stats
            ),
            'top_customers_by_spend', (
                SELECT json_agg(json_build_object('name', customer_name, 'value', total_spent) ORDER BY total_spent DESC)
                FROM (SELECT customer_name, total_spent FROM customer_stats ORDER BY total_spent DESC LIMIT top_customer_limit) as top_spenders
            ),
            'top_customers_by_sales', (
                SELECT json_agg(json_build_object('name', customer_name, 'value', total_orders) ORDER BY total_orders DESC)
                FROM (SELECT customer_name, total_orders FROM customer_stats ORDER BY total_orders DESC LIMIT top_customer_limit) as top_orderers
            )
        )
    );
END;
$$;


-- These functions are new and do not require DROP statements.
CREATE OR REPLACE FUNCTION public.get_inventory_aging_report(p_company_id uuid)
RETURNS TABLE (
    sku text,
    product_name text,
    quantity integer,
    total_value integer,
    days_since_last_sale integer
)
LANGUAGE sql STABLE
AS $$
    SELECT
        i.sku,
        i.name as product_name,
        i.quantity,
        (i.quantity * i.cost)::integer as total_value,
        (CASE
            WHEN i.last_sold_date IS NOT NULL THEN (CURRENT_DATE - i.last_sold_date)
            ELSE (CURRENT_DATE - i.created_at::date)
        END)::integer as days_since_last_sale
    FROM public.inventory i
    WHERE i.company_id = p_company_id AND i.quantity > 0 AND i.deleted_at IS NULL
    ORDER BY days_since_last_sale DESC;
$$;


CREATE OR REPLACE FUNCTION public.get_product_lifecycle_analysis(p_company_id uuid)
RETURNS json
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    sales_data record;
    product_lifecycles json;
BEGIN
    -- This function now uses temporary tables to avoid complex CTEs that might not be supported.
    CREATE TEMP TABLE sales_summary ON COMMIT DROP AS
    SELECT
        si.sku,
        MIN(s.created_at) as first_sale,
        MAX(s.created_at) as last_sale,
        SUM(si.quantity) as total_units_sold,
        SUM(si.quantity * si.unit_price) as total_revenue,
        SUM(CASE WHEN s.created_at >= NOW() - INTERVAL '90 days' THEN si.quantity ELSE 0 END) as sales_last_90_days,
        SUM(CASE WHEN s.created_at < NOW() - INTERVAL '90 days' AND s.created_at >= NOW() - INTERVAL '180 days' THEN si.quantity ELSE 0 END) as sales_prev_90_days
    FROM public.sales s
    JOIN public.sale_items si ON s.id = si.sale_id
    WHERE s.company_id = p_company_id
    GROUP BY si.sku;

    CREATE TEMP TABLE product_stages ON COMMIT DROP AS
    SELECT
        i.sku,
        i.name as product_name,
        ss.total_units_sold,
        ss.total_revenue::integer,
        CASE
            WHEN ss.first_sale >= NOW() - INTERVAL '60 days' THEN 'Launch'
            WHEN ss.sales_last_90_days > ss.sales_prev_90_days * 1.2 THEN 'Growth'
            WHEN ss.sales_last_90_days <= ss.sales_prev_90_days * 0.8 AND ss.last_sale < NOW() - INTERVAL '90 days' THEN 'Decline'
            ELSE 'Maturity'
        END as stage
    FROM public.inventory i
    JOIN sales_summary ss ON i.sku = ss.sku
    WHERE i.company_id = p_company_id;

    SELECT json_build_object(
        'summary', (
            SELECT json_build_object(
                'launch_count', COUNT(*) FILTER (WHERE stage = 'Launch'),
                'growth_count', COUNT(*) FILTER (WHERE stage = 'Growth'),
                'maturity_count', COUNT(*) FILTER (WHERE stage = 'Maturity'),
                'decline_count', COUNT(*) FILTER (WHERE stage = 'Decline')
            ) FROM product_stages
        ),
        'products', (SELECT json_agg(ps.*) FROM product_stages ps)
    ) INTO product_lifecycles;

    RETURN product_lifecycles;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_inventory_risk_report(p_company_id uuid)
RETURNS TABLE (
    sku text,
    product_name text,
    risk_score integer,
    risk_level text,
    total_value integer,
    reason text
)
LANGUAGE plpgsql STABLE
AS $$
BEGIN
    RETURN QUERY
    WITH stock_data AS (
        SELECT
            i.sku,
            i.name,
            i.quantity,
            i.cost,
            (i.quantity * i.cost)::integer as total_value,
            COALESCE(i.last_sold_date, i.created_at::date) as effective_date,
            (CURRENT_DATE - COALESCE(i.last_sold_date, i.created_at::date)) as days_since_activity,
            COALESCE(i.reorder_point, 0) as reorder_point
        FROM public.inventory i
        WHERE i.company_id = p_company_id AND i.quantity > 0 AND i.deleted_at IS NULL
    ),
    risk_factors AS (
        SELECT
            sku,
            name,
            quantity,
            total_value,
            -- Risk from aging stock (max 50 points)
            (LEAST(days_since_activity / 180.0, 1.0) * 50) as age_risk,
            -- Risk from overstock (max 30 points)
            (CASE WHEN reorder_point > 0 THEN LEAST((quantity::numeric / reorder_point) / 3.0, 1.0) * 30 ELSE 0 END) as overstock_risk,
            -- Risk from high value (max 20 points)
            (LEAST(total_value / 500000.0, 1.0) * 20) as value_risk
        FROM stock_data
    )
    SELECT
        rf.sku,
        rf.name,
        (rf.age_risk + rf.overstock_risk + rf.value_risk)::integer as risk_score,
        CASE
            WHEN (rf.age_risk + rf.overstock_risk + rf.value_risk) > 75 THEN 'High'
            WHEN (rf.age_risk + rf.overstock_risk + rf.value_risk) > 50 THEN 'Medium'
            ELSE 'Low'
        END as risk_level,
        rf.total_value,
        'Age: ' || round(rf.age_risk) || ', Overstock: ' || round(rf.overstock_risk) || ', Value: ' || round(rf.value_risk) as reason
    FROM risk_factors rf
    ORDER BY risk_score DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_customer_segment_analysis(p_company_id uuid)
RETURNS TABLE (
    segment text,
    sku text,
    product_name text,
    total_quantity bigint,
    total_revenue integer
)
LANGUAGE sql STABLE
AS $$
WITH customer_order_stats AS (
    SELECT
        c.id as customer_id,
        c.customer_name,
        MIN(s.created_at) as first_order_date,
        COUNT(s.id) as order_count,
        SUM(s.total_amount) as total_spend
    FROM public.customers c
    JOIN public.sales s ON c.id = s.customer_id
    WHERE c.company_id = p_company_id
    GROUP BY c.id
),
customer_segments AS (
    SELECT
        customer_id,
        CASE
            WHEN first_order_date >= NOW() - INTERVAL '30 days' THEN 'New Customers'
            WHEN order_count > 1 THEN 'Repeat Customers'
            ELSE 'Single Purchase'
        END as segment,
        total_spend
    FROM customer_order_stats
),
top_spenders AS (
    SELECT customer_id FROM customer_order_stats ORDER BY total_spend DESC LIMIT GREATEST(1, (SELECT (COUNT(*)*0.1)::integer FROM customer_order_stats))
),
sales_by_segment AS (
    SELECT
        CASE
            WHEN cs.customer_id IN (SELECT customer_id FROM top_spenders) THEN 'Top Spenders'
            ELSE cs.segment
        END as final_segment,
        si.sku,
        i.name as product_name,
        si.quantity,
        (si.quantity * si.unit_price) as revenue
    FROM public.sales s
    JOIN public.sale_items si ON s.id = si.sale_id
    JOIN public.inventory i ON si.sku = i.sku AND s.company_id = i.company_id
    JOIN customer_segments cs ON s.customer_id = cs.customer_id
    WHERE s.company_id = p_company_id
),
ranked_sales AS (
    SELECT
        final_segment,
        sku,
        product_name,
        SUM(quantity) as total_quantity,
        SUM(revenue)::integer as total_revenue,
        ROW_NUMBER() OVER(PARTITION BY final_segment ORDER BY SUM(revenue) DESC) as rn
    FROM sales_by_segment
    WHERE final_segment != 'Single Purchase'
    GROUP BY final_segment, sku, product_name
)
SELECT
    final_segment,
    sku,
    product_name,
    total_quantity,
    total_revenue
FROM ranked_sales
WHERE rn <= 5;
$$;
