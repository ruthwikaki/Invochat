-- This script updates existing database functions with smarter business logic.
-- It is safe to run on an existing database that has been set up previously.

-- Grant usage on the auth schema to the postgres role
-- This is necessary for the SECURITY DEFINER functions below to work correctly.
GRANT USAGE ON SCHEMA auth TO postgres;

-- Drop the old functions if they exist to avoid signature conflicts
DROP FUNCTION IF EXISTS get_financial_impact_of_promotion(uuid,text[],numeric,integer);
DROP FUNCTION IF EXISTS get_demand_forecast(uuid);
DROP FUNCTION IF EXISTS get_customer_segment_analysis(uuid);

--
-- Function: get_financial_impact_of_promotion
--
CREATE OR REPLACE FUNCTION public.get_financial_impact_of_promotion(
    p_company_id uuid,
    p_skus text[],
    p_discount_percentage numeric,
    p_duration_days integer
)
RETURNS TABLE(
    sku text,
    product_name text,
    current_price numeric,
    promotional_price numeric,
    estimated_sales_lift numeric,
    estimated_promo_units_sold bigint,
    estimated_promo_revenue numeric,
    estimated_promo_profit numeric,
    profit_change numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    sales_lift_multiplier REAL;
    promo_sales_lift_factor NUMERIC;
BEGIN
    -- Get the configurable sales lift multiplier from settings
    SELECT cs.promo_sales_lift_multiplier
    INTO sales_lift_multiplier
    FROM public.company_settings cs
    WHERE cs.company_id = p_company_id;

    -- A more realistic, non-linear model for promotional lift
    -- The lift is significant for small discounts but has diminishing returns
    promo_sales_lift_factor := 1 + (p_discount_percentage * sales_lift_multiplier * (1 - p_discount_percentage));

    RETURN QUERY
    WITH product_sales_velocity AS (
        SELECT
            i.sku,
            i.name,
            i.price,
            i.cost,
            COALESCE(SUM(si.quantity) / 90.0, 0.01) AS daily_sales_velocity -- Use a small default if no sales
        FROM public.inventory i
        LEFT JOIN public.sale_items si ON i.sku = si.sku AND i.company_id = si.company_id
        LEFT JOIN public.sales s ON si.sale_id = s.id
        WHERE i.company_id = p_company_id
          AND i.sku = ANY(p_skus)
          AND (s.created_at >= (NOW() - INTERVAL '90 days') OR s.created_at IS NULL)
        GROUP BY i.id, i.name
    )
    SELECT
        v.sku,
        v.name AS product_name,
        v.price AS current_price,
        (v.price * (1 - p_discount_percentage)) AS promotional_price,
        promo_sales_lift_factor AS estimated_sales_lift,
        ceil(v.daily_sales_velocity * p_duration_days * promo_sales_lift_factor)::bigint AS estimated_promo_units_sold,
        (ceil(v.daily_sales_velocity * p_duration_days * promo_sales_lift_factor) * (v.price * (1 - p_discount_percentage))) AS estimated_promo_revenue,
        (ceil(v.daily_sales_velocity * p_duration_days * promo_sales_lift_factor) * ((v.price * (1 - p_discount_percentage)) - v.cost)) AS estimated_promo_profit,
        (ceil(v.daily_sales_velocity * p_duration_days * promo_sales_lift_factor) * ((v.price * (1 - p_discount_percentage)) - v.cost)) -
        (v.daily_sales_velocity * p_duration_days * (v.price - v.cost)) AS profit_change
    FROM product_sales_velocity v;
END;
$$;


--
-- Function: get_demand_forecast
--
CREATE OR REPLACE FUNCTION public.get_demand_forecast(
    p_company_id uuid
)
RETURNS TABLE (
    sku text,
    product_name text,
    forecasted_demand_next_30_days numeric
)
LANGUAGE sql
SECURITY DEFINER
AS $$
WITH monthly_sales AS (
    SELECT
        si.sku,
        DATE_TRUNC('month', s.created_at) as sale_month,
        SUM(si.quantity) as total_quantity
    FROM public.sales s
    JOIN public.sale_items si ON s.id = si.sale_id
    WHERE s.company_id = p_company_id
    AND s.created_at >= NOW() - INTERVAL '12 months'
    GROUP BY si.sku, DATE_TRUNC('month', s.created_at)
),
-- Use EWMA to give more weight to recent months
weighted_sales AS (
    SELECT
        sku,
        -- Exponentially Weighted Moving Average with alpha = 0.7
        -- This gives much more weight to recent sales data
        SUM(total_quantity * POW(0.7, (EXTRACT(YEAR FROM NOW()) - EXTRACT(YEAR FROM sale_month)) * 12 + (EXTRACT(MONTH FROM NOW()) - EXTRACT(MONTH FROM sale_month)))) /
        SUM(POW(0.7, (EXTRACT(YEAR FROM NOW()) - EXTRACT(YEAR FROM sale_month)) * 12 + (EXTRACT(MONTH FROM NOW()) - EXTRACT(MONTH FROM sale_month)))) as ewma_monthly_sales
    FROM monthly_sales
    GROUP BY sku
),
ranked_sales AS (
    SELECT
      ws.sku,
      i.name as product_name,
      ws.ewma_monthly_sales,
      ROW_NUMBER() OVER(ORDER BY ws.ewma_monthly_sales DESC) as rank
    FROM weighted_sales ws
    JOIN public.inventory i ON ws.sku = i.sku AND i.company_id = p_company_id
)
SELECT
    rs.sku,
    rs.product_name,
    -- Project for next 30 days
    ROUND(rs.ewma_monthly_sales, 2) AS forecasted_demand_next_30_days
FROM ranked_sales rs
WHERE rs.rank <= 10;
$$;


--
-- Function: get_customer_segment_analysis
--
CREATE OR REPLACE FUNCTION public.get_customer_segment_analysis(
    p_company_id uuid
)
RETURNS TABLE (
    segment text,
    sku text,
    product_name text,
    total_quantity bigint,
    total_revenue numeric
)
LANGUAGE sql
SECURITY DEFINER
AS $$
WITH customer_stats AS (
    SELECT
        c.id as customer_id,
        c.email,
        COUNT(s.id) as total_orders
    FROM public.customers c
    JOIN public.sales s ON c.email = s.customer_email AND c.company_id = s.company_id
    WHERE c.company_id = p_company_id
    GROUP BY c.id
),
customer_segments AS (
  SELECT
    c.email,
    CASE
      WHEN cs.total_orders = 1 THEN 'New Customers'
      WHEN cs.total_orders > 1 THEN 'Repeat Customers'
    END as segment
  FROM public.customers c
  JOIN customer_stats cs ON c.email = cs.email
  WHERE c.company_id = p_company_id
),
top_spenders AS (
    SELECT email
    FROM public.customers
    WHERE company_id = p_company_id
    ORDER BY total_spent DESC
    -- Robust calculation for top 10% or at least 1 customer
    LIMIT GREATEST(1, (SELECT CEIL(COUNT(*) * 0.1) FROM public.customers WHERE company_id = p_company_id)::integer)
)
SELECT
    'New Customers' as segment,
    si.sku,
    si.product_name,
    SUM(si.quantity)::bigint as total_quantity,
    SUM(si.unit_price * si.quantity) as total_revenue
FROM public.sales s
JOIN public.sale_items si ON s.id = si.sale_id AND s.company_id = si.company_id
JOIN customer_segments c_seg ON s.customer_email = c_seg.email AND c_seg.segment = 'New Customers'
WHERE s.company_id = p_company_id
GROUP BY si.sku, si.product_name
ORDER BY total_revenue DESC
LIMIT 5

UNION ALL

SELECT
    'Repeat Customers' as segment,
    si.sku,
    si.product_name,
    SUM(si.quantity)::bigint as total_quantity,
    SUM(si.unit_price * si.quantity) as total_revenue
FROM public.sales s
JOIN public.sale_items si ON s.id = si.sale_id AND s.company_id = si.company_id
JOIN customer_segments c_seg ON s.customer_email = c_seg.email AND c_seg.segment = 'Repeat Customers'
WHERE s.company_id = p_company_id
GROUP BY si.sku, si.product_name
ORDER BY total_revenue DESC
LIMIT 5

UNION ALL

SELECT
    'Top Spenders' as segment,
    si.sku,
    si.product_name,
    SUM(si.quantity)::bigint as total_quantity,
    SUM(si.unit_price * si.quantity) as total_revenue
FROM public.sales s
JOIN public.sale_items si ON s.id = si.sale_id AND s.company_id = si.company_id
JOIN top_spenders ts ON s.customer_email = ts.email
WHERE s.company_id = p_company_id
GROUP BY si.sku, si.product_name
ORDER BY total_revenue DESC
LIMIT 5;
$$;
