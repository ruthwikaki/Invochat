-- This is a targeted UPDATE script. It only modifies database functions.
-- It assumes all tables and columns from the initial setup already exist.

-- Drop existing functions to be replaced
DROP FUNCTION IF EXISTS get_financial_impact_of_promotion(uuid,text[],numeric,integer);
DROP FUNCTION IF EXISTS get_demand_forecast(uuid);
DROP FUNCTION IF EXISTS get_customer_segment_analysis(uuid);

-- Grant usage on the auth schema to postgres role, which runs SECURITY DEFINER functions
GRANT USAGE ON SCHEMA auth TO postgres;

-- Function to get financial impact of a promotion with a non-linear sales lift
CREATE OR REPLACE FUNCTION get_financial_impact_of_promotion(p_company_id uuid, p_skus text[], p_discount_percentage numeric, p_duration_days integer)
RETURNS TABLE(
    sku text,
    product_name text,
    current_price numeric,
    promotional_price numeric,
    estimated_base_sales integer,
    estimated_promo_sales integer,
    estimated_additional_sales integer,
    estimated_base_revenue numeric,
    estimated_promo_revenue numeric,
    estimated_base_profit numeric,
    estimated_promo_profit numeric,
    estimated_profit_change numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    sales_lift_multiplier real;
BEGIN
    -- Get the company-specific sales lift multiplier
    SELECT cs.promo_sales_lift_multiplier INTO sales_lift_multiplier
    FROM public.company_settings cs
    WHERE cs.company_id = p_company_id;

    RETURN QUERY
    WITH product_costs AS (
        SELECT i.sku, i.name, i.price, i.cost
        FROM public.inventory i
        WHERE i.company_id = p_company_id AND i.sku = ANY(p_skus)
    ),
    sales_velocity AS (
        SELECT
            si.sku,
            (COUNT(si.id)::numeric / 90) AS daily_sales_velocity
        FROM public.sale_items si
        JOIN public.sales s ON si.sale_id = s.id
        WHERE s.company_id = p_company_id
          AND si.sku = ANY(p_skus)
          AND s.created_at >= (now() - interval '90 days')
        GROUP BY si.sku
    )
    SELECT
        pc.sku,
        pc.name AS product_name,
        pc.price AS current_price,
        (pc.price * (1 - p_discount_percentage)) AS promotional_price,
        (COALESCE(sv.daily_sales_velocity, 0.1) * p_duration_days)::integer AS estimated_base_sales,
        -- Non-linear sales lift: sales lift decreases as discount gets very high
        (COALESCE(sv.daily_sales_velocity, 0.1) * p_duration_days * (1 + (p_discount_percentage * sales_lift_multiplier * (1 - p_discount_percentage))))::integer AS estimated_promo_sales,
        ((COALESCE(sv.daily_sales_velocity, 0.1) * p_duration_days * (1 + (p_discount_percentage * sales_lift_multiplier * (1 - p_discount_percentage)))) - (COALESCE(sv.daily_sales_velocity, 0.1) * p_duration_days))::integer AS estimated_additional_sales,
        (COALESCE(sv.daily_sales_velocity, 0.1) * p_duration_days * pc.price) AS estimated_base_revenue,
        (COALESCE(sv.daily_sales_velocity, 0.1) * p_duration_days * (1 + (p_discount_percentage * sales_lift_multiplier * (1 - p_discount_percentage))) * (pc.price * (1 - p_discount_percentage))) AS estimated_promo_revenue,
        (COALESCE(sv.daily_sales_velocity, 0.1) * p_duration_days * (pc.price - pc.cost)) AS estimated_base_profit,
        (COALESCE(sv.daily_sales_velocity, 0.1) * p_duration_days * (1 + (p_discount_percentage * sales_lift_multiplier * (1 - p_discount_percentage))) * ((pc.price * (1 - p_discount_percentage)) - pc.cost)) AS estimated_promo_profit,
        ((COALESCE(sv.daily_sales_velocity, 0.1) * p_duration_days * (1 + (p_discount_percentage * sales_lift_multiplier * (1 - p_discount_percentage))) * ((pc.price * (1 - p_discount_percentage)) - pc.cost)) - (COALESCE(sv.daily_sales_velocity, 0.1) * p_duration_days * (pc.price - pc.cost))) as estimated_profit_change
    FROM product_costs pc
    LEFT JOIN sales_velocity sv ON pc.sku = sv.sku;
END;
$$;


-- Function to forecast demand using EWMA
CREATE OR REPLACE FUNCTION get_demand_forecast(p_company_id uuid)
RETURNS TABLE (
    sku text,
    product_name text,
    last_30_day_sales bigint,
    forecasted_30_day_demand bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    alpha numeric := 0.3; -- Smoothing factor for EWMA
BEGIN
    RETURN QUERY
    WITH monthly_sales AS (
        SELECT
            si.sku,
            date_trunc('month', s.created_at)::date as sale_month,
            sum(si.quantity) as total_quantity
        FROM public.sales s
        JOIN public.sale_items si ON s.id = si.sale_id
        WHERE s.company_id = p_company_id
          AND s.created_at >= now() - interval '12 months'
        GROUP BY si.sku, sale_month
    ),
    ranked_sales AS (
      SELECT
        sku,
        sale_month,
        total_quantity,
        ROW_NUMBER() OVER(PARTITION BY sku ORDER BY sale_month) as rn
      FROM monthly_sales
    ),
    ewma_calc AS (
        SELECT
            sku,
            sale_month,
            total_quantity,
            rn,
            CASE
                WHEN rn = 1 THEN total_quantity::numeric
                ELSE (alpha * total_quantity) + ((1 - alpha) * LAG(total_quantity::numeric) OVER (PARTITION BY sku ORDER BY sale_month))
            END as ewma
        FROM ranked_sales
    ),
    latest_ewma AS (
      SELECT
        sku,
        ewma
      FROM (
        SELECT
            sku,
            ewma,
            ROW_NUMBER() OVER (PARTITION BY sku ORDER BY sale_month DESC) as rn_latest
        FROM ewma_calc
      ) as sub
      WHERE rn_latest = 1
    ),
    last_30_days AS (
        SELECT
            si.sku,
            sum(si.quantity) as last_30_sales
        FROM public.sales s
        JOIN public.sale_items si ON s.id = si.sale_id
        WHERE s.company_id = p_company_id
          AND s.created_at >= now() - interval '30 days'
        GROUP BY si.sku
    )
    SELECT
        i.sku,
        i.name as product_name,
        COALESCE(l30.last_30_sales, 0)::bigint as last_30_day_sales,
        ceil(COALESCE(le.ewma, l30.last_30_sales, 5))::bigint as forecasted_30_day_demand
    FROM public.inventory i
    LEFT JOIN latest_ewma le ON i.sku = le.sku
    LEFT JOIN last_30_days l30 ON i.sku = l30.sku
    WHERE i.company_id = p_company_id
    ORDER BY forecasted_30_day_demand DESC
    LIMIT 10;
END;
$$;


-- Function for customer segmentation analysis
CREATE OR REPLACE FUNCTION get_customer_segment_analysis(p_company_id uuid)
RETURNS TABLE(
    segment text,
    sku text,
    product_name text,
    total_quantity bigint,
    total_revenue numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    WITH customer_stats AS (
        SELECT
            c.id as customer_id,
            c.email,
            MIN(s.created_at) as first_order_date,
            COUNT(s.id) as total_orders,
            SUM(s.total_amount) as total_spent
        FROM public.customers c
        JOIN public.sales s ON c.email = s.customer_email AND c.company_id = s.company_id
        WHERE c.company_id = p_company_id
        GROUP BY c.id, c.email
    ),
    ranked_customers AS (
      SELECT
        customer_id,
        email,
        total_spent,
        NTILE(10) OVER (ORDER BY total_spent DESC) as decile
      FROM customer_stats
    ),
    segments AS (
        SELECT
            s.id as sale_id,
            s.customer_email,
            CASE
                WHEN cs.total_orders = 1 THEN 'New Customers'
                ELSE 'Repeat Customers'
            END as repeat_segment,
            CASE
                WHEN rc.decile = 1 THEN 'Top Spenders'
                ELSE NULL
            END as spend_segment
        FROM public.sales s
        JOIN customer_stats cs ON s.customer_email = cs.email AND s.company_id = cs.company_id
        LEFT JOIN ranked_customers rc ON s.customer_email = rc.email
        WHERE s.company_id = p_company_id
    ),
    unioned_segments AS (
      SELECT sale_id, customer_email, repeat_segment as segment FROM segments WHERE repeat_segment IS NOT NULL
      UNION ALL
      SELECT sale_id, customer_email, spend_segment as segment FROM segments WHERE spend_segment IS NOT NULL
    )
    SELECT
        us.segment,
        si.sku,
        i.name as product_name,
        sum(si.quantity)::bigint as total_quantity,
        sum(si.quantity * si.unit_price) as total_revenue
    FROM public.sale_items si
    JOIN unioned_segments us ON si.sale_id = us.sale_id
    JOIN public.inventory i ON si.sku = i.sku AND si.company_id = i.company_id
    WHERE si.company_id = p_company_id
    GROUP BY us.segment, si.sku, i.name
    ORDER BY us.segment, total_revenue DESC;
END;
$$;
