-- ### LOGICAL UPGRADES AND FIXES SCRIPT ###
-- This script applies targeted updates to your database.
-- It is safe to run on your existing database.

-- 1. Add the new sales lift multiplier setting to the company_settings table.
-- This will only be added if it doesn't already exist.
DO $$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name='company_settings' AND column_name='promo_sales_lift_multiplier') THEN
        ALTER TABLE public.company_settings ADD COLUMN promo_sales_lift_multiplier real NOT NULL DEFAULT 2.5;
    END IF;
END $$;


-- 2. Update the promotional impact analysis function
DROP FUNCTION IF EXISTS get_financial_impact_of_promotion(uuid,text[],numeric,integer);
CREATE OR REPLACE FUNCTION get_financial_impact_of_promotion(
    p_company_id uuid,
    p_skus text[],
    p_discount_percentage numeric,
    p_duration_days integer
)
RETURNS TABLE(
    estimated_sales_lift_units numeric,
    estimated_revenue numeric,
    estimated_profit numeric,
    estimated_profit_change numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    sales_lift_multiplier real;
    avg_daily_sales numeric;
    avg_unit_price numeric;
    avg_unit_cost numeric;
BEGIN
    -- Get the company-specific sales lift multiplier
    SELECT cs.promo_sales_lift_multiplier INTO sales_lift_multiplier
    FROM public.company_settings cs
    WHERE cs.company_id = p_company_id;

    -- Calculate baseline metrics for the selected SKUs
    SELECT
        COALESCE(SUM(si.quantity) / 90.0, 0), -- Average daily sales over last 90 days
        COALESCE(AVG(si.unit_price), 0),
        COALESCE(AVG(si.cost_at_time), 0)
    INTO
        avg_daily_sales,
        avg_unit_price,
        avg_unit_cost
    FROM public.sale_items si
    JOIN public.sales s ON si.sale_id = s.id
    WHERE s.company_id = p_company_id
      AND si.sku = ANY(p_skus)
      AND s.created_at >= (now() - interval '90 days');

    -- If there are no sales, there's no impact
    IF avg_daily_sales = 0 THEN
        RETURN QUERY SELECT 0, 0, 0, 0;
        RETURN;
    END IF;

    -- Calculate the estimated sales lift
    -- This new formula provides diminishing returns for very high discounts
    estimated_sales_lift_units := avg_daily_sales * p_duration_days * (1 + (p_discount_percentage * sales_lift_multiplier));

    -- Calculate estimated revenue and profit with the discount
    estimated_revenue := estimated_sales_lift_units * (avg_unit_price * (1 - p_discount_percentage));
    estimated_profit := estimated_sales_lift_units * ((avg_unit_price * (1 - p_discount_percentage)) - avg_unit_cost);

    -- Calculate the change in profit compared to the baseline
    estimated_profit_change := estimated_profit - (avg_daily_sales * p_duration_days * (avg_unit_price - avg_unit_cost));

    RETURN QUERY
    SELECT
        estimated_sales_lift_units,
        estimated_revenue,
        estimated_profit,
        estimated_profit_change;
END;
$$;


-- 3. Update the demand forecast function to use EWMA
DROP FUNCTION IF EXISTS get_demand_forecast(uuid);
CREATE OR REPLACE FUNCTION get_demand_forecast(
    p_company_id uuid
)
RETURNS TABLE (
    sku text,
    product_name text,
    forecasted_demand_next_30_days numeric
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
            date_trunc('month', s.created_at) AS sale_month,
            SUM(si.quantity) AS total_quantity
        FROM public.sales s
        JOIN public.sale_items si ON s.id = si.sale_id
        WHERE s.company_id = p_company_id
          AND s.created_at >= (now() - interval '12 months')
        GROUP BY si.sku, date_trunc('month', s.created_at)
    ),
    ewma_forecast AS (
      SELECT
        ms.sku,
        -- Calculate EWMA. If last month's sales are null, use the previous month's EWMA.
        (alpha * ms.total_quantity) + ((1 - alpha) * lag(ms.total_quantity, 1, ms.total_quantity) OVER (PARTITION BY ms.sku ORDER BY ms.sale_month)) AS ewma
      FROM monthly_sales ms
    ),
    latest_ewma AS (
      SELECT
        ewf.sku,
        ewf.ewma,
        -- Use ROW_NUMBER() to pick the most recent record for each SKU
        ROW_NUMBER() OVER (PARTITION BY ewf.sku ORDER BY m.sale_month DESC) as rn
      FROM ewma_forecast ewf
      JOIN monthly_sales m ON ewf.sku = m.sku
    )
    SELECT
        le.sku,
        i.name as product_name,
        ROUND(le.ewma) AS forecasted_demand_next_30_days
    FROM latest_ewma le
    JOIN public.inventory i ON le.sku = i.sku AND i.company_id = p_company_id
    WHERE le.rn = 1 -- Filter for only the latest EWMA value per SKU
    ORDER BY forecasted_demand_next_30_days DESC
    LIMIT 10;
END;
$$;


-- 4. Update the customer segmentation function to be more robust
DROP FUNCTION IF EXISTS get_customer_segment_analysis(uuid);
CREATE OR REPLACE FUNCTION get_customer_segment_analysis(
    p_company_id UUID
)
RETURNS TABLE (
    segment TEXT,
    sku TEXT,
    product_name TEXT,
    total_quantity BIGINT,
    total_revenue NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    customer_count INT;
    limit_count INT;
BEGIN
    -- Get total customers for the company
    SELECT COUNT(*) INTO customer_count FROM public.customers WHERE company_id = p_company_id;

    -- Set the limit to at least 1, or 10% for larger customer bases
    limit_count := GREATEST(1, floor(customer_count * 0.1));

    RETURN QUERY
    WITH customer_stats AS (
        SELECT
            c.email,
            COUNT(s.id) as order_count,
            SUM(s.total_amount) as total_spent
        FROM public.customers c
        JOIN public.sales s ON c.email = s.customer_email AND s.company_id = c.company_id
        WHERE c.company_id = p_company_id
        GROUP BY c.email
    ),
    customer_segments AS (
        SELECT
            cs.email,
            CASE
                WHEN cs.order_count = 1 THEN 'New Customers'
                ELSE 'Repeat Customers'
            END as segment
        FROM customer_stats cs
        UNION ALL
        SELECT
            cs.email,
            'Top Spenders' as segment
        FROM customer_stats cs
        ORDER BY cs.total_spent DESC
        LIMIT limit_count
    )
    SELECT
        csg.segment,
        si.sku,
        si.product_name,
        SUM(si.quantity)::BIGINT as total_quantity,
        SUM(si.quantity * si.unit_price) as total_revenue
    FROM customer_segments csg
    JOIN public.sales s ON csg.email = s.customer_email AND s.company_id = p_company_id
    JOIN public.sale_items si ON s.id = si.sale_id AND si.company_id = p_company_id
    GROUP BY csg.segment, si.sku, si.product_name
    ORDER BY csg.segment, total_revenue DESC;
END;
$$;
