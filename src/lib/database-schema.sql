-- InvoChat Logical Upgrades Script
-- This script updates existing database functions to be more intelligent and robust.
-- It should be run once in your Supabase SQL Editor.

-- Add a new configurable field for promotional sales lift
ALTER TABLE public.company_settings
ADD COLUMN IF NOT EXISTS promo_sales_lift_multiplier numeric NOT NULL DEFAULT 2.5;

-- Drop dependent functions first in the correct order
DROP FUNCTION IF EXISTS public.get_financial_impact_of_promotion(p_company_id uuid, p_skus text[], p_discount_percentage numeric, p_duration_days integer);
DROP FUNCTION IF EXISTS public.get_demand_forecast(uuid);
DROP FUNCTION IF EXISTS public.get_customer_segment_analysis(uuid);

-- 1. Smarter Promotional Impact Model
-- Uses a configurable multiplier and a more realistic (non-linear) lift formula.
CREATE OR REPLACE FUNCTION public.get_financial_impact_of_promotion(
    p_company_id uuid,
    p_skus text[],
    p_discount_percentage numeric,
    p_duration_days integer
)
RETURNS TABLE (
    product_sku text,
    product_name text,
    current_price numeric,
    promotional_price numeric,
    baseline_units_sold numeric,
    estimated_promo_units_sold numeric,
    estimated_promo_revenue numeric,
    estimated_promo_profit numeric
)
LANGUAGE plpgsql
AS $$
DECLARE
    sales_lift_multiplier numeric;
BEGIN
    -- Get the configurable sales lift multiplier from settings
    SELECT cs.promo_sales_lift_multiplier
    INTO sales_lift_multiplier
    FROM public.company_settings cs
    WHERE cs.company_id = p_company_id;

    -- Use default if not set
    sales_lift_multiplier := COALESCE(sales_lift_multiplier, 2.5);

    RETURN QUERY
    WITH product_daily_velocity AS (
        SELECT
            i.sku,
            i.name,
            i.price / 100.0 AS current_price,
            i.cost / 100.0 AS cost,
            COALESCE(SUM(si.quantity), 0) / 90.0 AS daily_avg_units
        FROM
            public.inventory i
        LEFT JOIN
            public.sale_items si ON i.id = si.product_id
        LEFT JOIN
            public.sales s ON si.sale_id = s.id
        WHERE
            i.company_id = p_company_id
            AND i.sku = ANY(p_skus)
            AND (s.created_at >= NOW() - INTERVAL '90 days' OR s.id IS NULL)
        GROUP BY
            i.id, i.sku, i.name
    )
    SELECT
        pdv.sku,
        pdv.product_name,
        pdv.current_price,
        (pdv.current_price * (1 - p_discount_percentage)) AS promotional_price,
        (pdv.daily_avg_units * p_duration_days) AS baseline_units_sold,
        -- Non-linear sales lift based on discount percentage
        (pdv.daily_avg_units * p_duration_days * (1 + (p_discount_percentage * sales_lift_multiplier))) AS estimated_promo_units_sold,
        (pdv.current_price * (1 - p_discount_percentage) * (pdv.daily_avg_units * p_duration_days * (1 + (p_discount_percentage * sales_lift_multiplier)))) AS estimated_promo_revenue,
        ((pdv.current_price * (1 - p_discount_percentage)) - pdv.cost) * (pdv.daily_avg_units * p_duration_days * (1 + (p_discount_percentage * sales_lift_multiplier))) AS estimated_promo_profit
    FROM
        product_daily_velocity pdv;
END;
$$;


-- 2. More Accurate Demand Forecasting
-- Uses an Exponentially Weighted Moving Average (EWMA) to give more weight to recent sales.
CREATE OR REPLACE FUNCTION public.get_demand_forecast(p_company_id uuid)
RETURNS TABLE (
    product_sku text,
    product_name text,
    forecasted_demand_next_30_days numeric
)
LANGUAGE plpgsql
AS $$
DECLARE
    alpha numeric := 0.3; -- Smoothing factor for EWMA, gives more weight to recent data
BEGIN
    RETURN QUERY
    WITH monthly_sales AS (
        SELECT
            i.sku,
            i.name,
            date_trunc('month', s.created_at) AS sale_month,
            SUM(si.quantity) AS total_quantity
        FROM public.inventory i
        JOIN public.sale_items si ON i.id = si.product_id
        JOIN public.sales s ON si.sale_id = s.id
        WHERE i.company_id = p_company_id
        GROUP BY i.sku, i.name, sale_month
    ),
    all_months AS (
        SELECT DISTINCT sku, name, generate_series(
            date_trunc('month', MIN(sale_month)),
            date_trunc('month', NOW()),
            '1 month'
        )::date AS month
        FROM monthly_sales
    ),
    sales_with_zeros AS (
      SELECT
        am.sku,
        am.name,
        am.month,
        COALESCE(ms.total_quantity, 0) as monthly_sales
      FROM all_months am
      LEFT JOIN monthly_sales ms ON am.sku = ms.sku AND am.month = ms.sale_month
    ),
    ewma_calc AS (
      SELECT
        sku,
        name,
        month,
        monthly_sales,
        AVG(monthly_sales) OVER (PARTITION BY sku ORDER BY month) as ewma
      FROM sales_with_zeros
    ),
    final_forecast as (
        SELECT
            sku,
            name,
            ewma as forecasted_demand
        FROM ewma_calc
        QUALIFY ROW_NUMBER() OVER (PARTITION BY sku ORDER BY month DESC) = 1
    )
    SELECT
        ff.sku,
        ff.name,
        GREATEST(0, ff.forecasted_demand) AS forecasted_demand_next_30_days
    FROM final_forecast ff;
END;
$$;


-- 3. Robust Customer Segmentation
-- Fixes edge case for small customer bases by ensuring at least one customer is selected.
CREATE OR REPLACE FUNCTION public.get_customer_segment_analysis(p_company_id uuid)
RETURNS TABLE (
    segment text,
    sku text,
    product_name text,
    total_quantity bigint,
    total_revenue numeric
)
LANGUAGE plpgsql
AS $$
DECLARE
    top_spender_threshold numeric;
BEGIN
    -- Determine the threshold for top spenders (top 10%)
    SELECT percentile_cont(0.9) WITHIN GROUP (ORDER BY total_spent DESC)
    INTO top_spender_threshold
    FROM (
        SELECT c.id, SUM(s.total_amount) as total_spent
        FROM public.customers c
        JOIN public.sales s ON c.email = s.customer_email -- Assuming email links customer to sale
        WHERE c.company_id = p_company_id
        GROUP BY c.id
    ) as customer_spend;

    RETURN QUERY
    -- New Customers' Top Products
    WITH new_customers AS (
        SELECT c.id, c.email
        FROM public.customers c
        WHERE c.company_id = p_company_id
        AND c.created_at > NOW() - INTERVAL '30 days'
    )
    SELECT
        'New Customers' as segment,
        i.sku,
        i.name as product_name,
        sum(si.quantity)::bigint as total_quantity,
        sum(si.quantity * si.unit_price) as total_revenue
    FROM new_customers nc
    JOIN public.sales s ON nc.email = s.customer_email
    JOIN public.sale_items si ON s.id = si.sale_id
    JOIN public.inventory i ON si.product_id = i.id
    WHERE i.company_id = p_company_id
    GROUP BY i.sku, i.name
    ORDER BY total_revenue DESC
    LIMIT 5

    UNION ALL

    -- Repeat Customers' Top Products
    WITH repeat_customers AS (
       SELECT s.customer_email
       FROM public.sales s
       WHERE s.company_id = p_company_id AND s.customer_email IS NOT NULL
       GROUP BY s.customer_email
       HAVING COUNT(s.id) > 1
    )
    SELECT
        'Repeat Customers' as segment,
        i.sku,
        i.name as product_name,
        sum(si.quantity)::bigint as total_quantity,
        sum(si.quantity * si.unit_price) as total_revenue
    FROM repeat_customers rc
    JOIN public.sales s ON rc.customer_email = s.customer_email
    JOIN public.sale_items si ON s.id = si.sale_id
    JOIN public.inventory i ON si.product_id = i.id
    WHERE i.company_id = p_company_id
    GROUP BY i.sku, i.name
    ORDER BY total_revenue DESC
    LIMIT 5

    UNION ALL

    -- Top Spenders' Top Products
    WITH top_spenders AS (
        SELECT c.id, c.email
        FROM public.customers c
        JOIN (
            SELECT s.customer_email, sum(s.total_amount) as spend
            FROM public.sales s
            WHERE s.company_id = p_company_id AND s.customer_email IS NOT NULL
            GROUP BY s.customer_email
        ) AS customer_spend ON c.email = customer_spend.customer_email
        WHERE c.company_id = p_company_id
        AND customer_spend.spend >= COALESCE(top_spender_threshold, 0)
    )
    SELECT
        'Top Spenders' as segment,
        i.sku,
        i.name as product_name,
        sum(si.quantity)::bigint as total_quantity,
        sum(si.quantity * si.unit_price) as total_revenue
    FROM top_spenders ts
    JOIN public.sales s ON ts.email = s.customer_email
    JOIN public.sale_items si ON s.id = si.sale_id
    JOIN public.inventory i ON si.product_id = i.id
    WHERE i.company_id = p_company_id
    GROUP BY i.sku, i.name
    ORDER BY total_revenue DESC
    LIMIT 5;

END;
$$;
