-- InvoChat Logical Upgrades
-- This script updates existing database functions and settings to be more robust and intelligent.
-- It is designed to be run on an existing database.

-- Add a new configurable setting for the promotional sales lift multiplier
ALTER TABLE public.company_settings
ADD COLUMN IF NOT EXISTS promo_sales_lift_multiplier numeric NOT NULL DEFAULT 2.5;


--
-- 1. UPGRADE: get_financial_impact_of_promotion
-- Replaces the simplistic linear sales lift model with a more realistic one that models
-- diminishing returns for very high discounts. Also uses the new configurable multiplier.
--
CREATE OR REPLACE FUNCTION public.get_financial_impact_of_promotion(
    p_company_id uuid,
    p_skus text[],
    p_discount_percentage numeric,
    p_duration_days integer
)
RETURNS TABLE(
    estimated_sales_lift_units integer,
    estimated_incremental_revenue numeric,
    estimated_incremental_profit numeric,
    original_profit numeric,
    promo_profit numeric
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_sales_lift_multiplier numeric;
BEGIN
    -- Get the configurable sales lift multiplier from settings
    SELECT cs.promo_sales_lift_multiplier INTO v_sales_lift_multiplier
    FROM public.company_settings cs
    WHERE cs.company_id = p_company_id;

    -- If no setting is found, default to 2.5
    v_sales_lift_multiplier := COALESCE(v_sales_lift_multiplier, 2.5);

    RETURN QUERY
    WITH promo_items AS (
        SELECT
            i.id,
            i.sku,
            i.name,
            i.cost,
            i.price,
            -- Calculate average daily sales over the last 90 days
            COALESCE((
                SELECT SUM(si.quantity) / 90.0
                FROM public.sale_items si
                JOIN public.sales s ON si.sale_id = s.id
                WHERE si.sku = i.sku
                  AND s.company_id = p_company_id
                  AND s.created_at >= (NOW() - INTERVAL '90 days')
            ), 0) AS avg_daily_sales
        FROM public.inventory i
        WHERE i.company_id = p_company_id
          AND i.sku = ANY(p_skus)
          AND i.deleted_at IS NULL
    ),
    promo_analysis AS (
        SELECT
            -- A more realistic sales lift model using a sigmoid-like curve (via tanh)
            -- This models diminishing returns for very high discounts.
            pi.avg_daily_sales * (1 + (p_discount_percentage * v_sales_lift_multiplier) * (1 - tanh(p_discount_percentage * 2))) * p_duration_days AS projected_units,
            pi.avg_daily_sales * p_duration_days AS baseline_units,
            pi.price,
            pi.cost
        FROM promo_items pi
    )
    SELECT
        (SUM(pa.projected_units) - SUM(pa.baseline_units))::integer AS estimated_sales_lift_units,
        SUM((pa.projected_units - pa.baseline_units) * (pa.price * (1 - p_discount_percentage)))::numeric AS estimated_incremental_revenue,
        SUM((pa.projected_units - pa.baseline_units) * (pa.price * (1 - p_discount_percentage) - pa.cost))::numeric AS estimated_incremental_profit,
        SUM(pa.baseline_units * (pa.price - pa.cost))::numeric AS original_profit,
        SUM(pa.projected_units * (pa.price * (1 - p_discount_percentage) - pa.cost))::numeric AS promo_profit
    FROM promo_analysis pa;
END;
$$;


--
-- 2. UPGRADE: get_demand_forecast
-- Replaces the simple moving average forecast with an exponentially weighted moving average (EWMA).
-- This gives more weight to recent sales, making forecasts more responsive to current trends.
--
CREATE OR REPLACE FUNCTION public.get_demand_forecast(p_company_id uuid)
RETURNS TABLE(
    sku text,
    product_name text,
    forecast_30_days numeric
)
LANGUAGE sql STABLE
AS $$
WITH monthly_sales AS (
    SELECT
        si.sku,
        date_trunc('month', s.created_at) AS sale_month,
        SUM(si.quantity) AS total_quantity
    FROM public.sales s
    JOIN public.sale_items si ON s.id = si.sale_id
    WHERE s.company_id = p_company_id
      AND s.created_at >= NOW() - INTERVAL '12 months'
    GROUP BY si.sku, sale_month
),
product_months AS (
    SELECT DISTINCT
        i.sku,
        m.month_start::date
    FROM public.inventory i
    CROSS JOIN generate_series(
        date_trunc('month', NOW() - INTERVAL '11 months'),
        date_trunc('month', NOW()),
        '1 month'
    ) AS m(month_start)
    WHERE i.company_id = p_company_id
),
full_sales_data AS (
    SELECT
        pm.sku,
        pm.month_start,
        COALESCE(ms.total_quantity, 0) AS monthly_quantity
    FROM product_months pm
    LEFT JOIN monthly_sales ms ON pm.sku = ms.sku AND pm.month_start = ms.sale_month
    ORDER BY pm.sku, pm.month_start
),
ewma_forecast AS (
    SELECT
        sku,
        -- Calculate EWMA (alpha = 0.7 gives high weight to recent months)
        (
            SELECT SUM(s.monthly_quantity * (0.7 * pow(1 - 0.7, r.rn - 1)))
            FROM (
                SELECT monthly_quantity, ROW_NUMBER() OVER (ORDER BY month_start DESC) as rn
                FROM full_sales_data s_inner
                WHERE s_inner.sku = s_outer.sku
            ) r
        ) / (
            SELECT SUM(0.7 * pow(1 - 0.7, r.rn - 1))
            FROM (
                SELECT ROW_NUMBER() OVER (ORDER BY month_start DESC) as rn
                FROM full_sales_data s_inner
                WHERE s_inner.sku = s_outer.sku
            ) r
        ) AS forecast
    FROM full_sales_data s_outer
    GROUP BY sku
)
SELECT
    i.sku,
    i.name as product_name,
    -- Round forecast to nearest whole number, ensure non-negative
    GREATEST(0, ROUND(ef.forecast)) as forecast_30_days
FROM ewma_forecast ef
JOIN public.inventory i ON ef.sku = i.sku
WHERE i.company_id = p_company_id
ORDER BY forecast_30_days DESC
LIMIT 10;
$$;


--
-- 3. UPGRADE: get_customer_analytics
-- Makes the "Top Spenders" calculation more robust for small customer bases.
-- Instead of a simple top 10%, it now takes the GREATER of 10% or at least 1 customer.
-- This prevents the query from failing or returning empty results for new companies.
--
CREATE OR REPLACE FUNCTION public.get_customer_analytics(p_company_id uuid)
RETURNS json
LANGUAGE sql STABLE
AS $$
WITH customer_stats AS (
    SELECT
        COUNT(*) as total_customers,
        COUNT(*) FILTER (WHERE c.created_at >= NOW() - INTERVAL '30 days') as new_customers_last_30_days,
        COALESCE(SUM(s.total_amount), 0) as total_lifetime_value
    FROM public.customers c
    LEFT JOIN public.sales s ON c.email = s.customer_email AND c.company_id = s.company_id
    WHERE c.company_id = p_company_id AND c.deleted_at IS NULL
),
repeat_customers AS (
    SELECT
        COUNT(DISTINCT customer_email) as repeat_customer_count
    FROM public.sales
    WHERE company_id = p_company_id AND customer_email IS NOT NULL
    GROUP BY customer_email
    HAVING COUNT(id) > 1
),
top_by_spend AS (
    SELECT
        c.customer_name as name,
        c.total_spent as value
    FROM public.customers c
    WHERE c.company_id = p_company_id AND c.deleted_at IS NULL
    ORDER BY c.total_spent DESC
    LIMIT GREATEST(1, (SELECT (COUNT(*)*0.1)::integer FROM public.customers WHERE company_id = p_company_id))
),
top_by_sales AS (
     SELECT
        c.customer_name as name,
        c.total_orders as value
    FROM public.customers c
    WHERE c.company_id = p_company_id AND c.deleted_at IS NULL
    ORDER BY c.total_orders DESC
    LIMIT GREATEST(1, (SELECT (COUNT(*)*0.1)::integer FROM public.customers WHERE company_id = p_company_id))
)
SELECT json_build_object(
    'total_customers', cs.total_customers,
    'new_customers_last_30_days', cs.new_customers_last_30_days,
    'repeat_customer_rate', CASE WHEN cs.total_customers > 0 THEN (SELECT COUNT(*) FROM repeat_customers)::numeric / cs.total_customers ELSE 0 END,
    'average_lifetime_value', CASE WHEN cs.total_customers > 0 THEN cs.total_lifetime_value / cs.total_customers ELSE 0 END,
    'top_customers_by_spend', (SELECT json_agg(t) FROM top_by_spend t),
    'top_customers_by_sales', (SELECT json_agg(t) FROM top_by_sales t)
)
FROM customer_stats cs;
$$;
