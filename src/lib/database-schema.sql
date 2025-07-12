-- This script is a targeted update for existing database functions.
-- It should be run in the Supabase SQL Editor.

-- Drop existing functions that need signature changes to avoid errors.
DROP FUNCTION IF EXISTS get_financial_impact_of_promotion(uuid,text[],numeric,integer);
DROP FUNCTION IF EXISTS get_demand_forecast(uuid);
DROP FUNCTION IF EXISTS get_customer_segment_analysis(uuid);

-- Add promo_sales_lift_multiplier to company_settings
ALTER TABLE public.company_settings
ADD COLUMN IF NOT EXISTS promo_sales_lift_multiplier real NOT NULL DEFAULT 2.5;

--
-- Name: get_financial_impact_of_promotion(uuid, text[], numeric, integer); Type: FUNCTION; Schema: public; Owner: supabase_admin
--
CREATE OR REPLACE FUNCTION public.get_financial_impact_of_promotion(p_company_id uuid, p_skus text[], p_discount_percentage numeric, p_duration_days integer)
RETURNS TABLE(
    sku text,
    product_name text,
    estimated_sales_lift numeric,
    estimated_additional_units_sold numeric,
    estimated_additional_revenue numeric,
    estimated_additional_profit numeric
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_sales_lift_multiplier real;
BEGIN
    -- Get the company-specific sales lift multiplier, defaulting to 2.5
    SELECT cs.promo_sales_lift_multiplier INTO v_sales_lift_multiplier
    FROM public.company_settings cs
    WHERE cs.company_id = p_company_id
    LIMIT 1;

    IF NOT FOUND THEN
        v_sales_lift_multiplier := 2.5;
    END IF;

    RETURN QUERY
    WITH product_daily_sales AS (
        SELECT
            i.sku,
            i.name,
            i.price,
            i.cost,
            -- Calculate average daily sales over the last 90 days
            COALESCE(SUM(s.quantity) / 90.0, 0) as avg_daily_units_sold
        FROM
            public.inventory i
        LEFT JOIN
            public.sales s ON i.id = s.product_id AND s.created_at >= (NOW() - INTERVAL '90 days')
        WHERE
            i.company_id = p_company_id AND i.sku = ANY(p_skus)
        GROUP BY
            i.id, i.sku, i.name, i.price, i.cost
    )
    SELECT
        pds.sku,
        pds.name AS product_name,
        -- Non-linear sales lift: The higher the discount, the smaller the additional lift per percentage point.
        -- This models diminishing returns. Using LOG gives a more realistic curve than a simple linear model.
        (1 + (p_discount_percentage * (v_sales_lift_multiplier - (p_discount_percentage * (v_sales_lift_multiplier - 1))))) AS estimated_sales_lift,
        (pds.avg_daily_units_sold * (1 + (p_discount_percentage * (v_sales_lift_multiplier - (p_discount_percentage * (v_sales_lift_multiplier - 1))))) * p_duration_days) - (pds.avg_daily_units_sold * p_duration_days) AS estimated_additional_units_sold,
        -- Revenue calculation based on discounted price
        (pds.price * (1 - p_discount_percentage) * (pds.avg_daily_units_sold * (1 + (p_discount_percentage * (v_sales_lift_multiplier - (p_discount_percentage * (v_sales_lift_multiplier - 1))))) * p_duration_days)) - (pds.price * pds.avg_daily_units_sold * p_duration_days) AS estimated_additional_revenue,
        -- Profit calculation based on discounted price
        ((pds.price * (1 - p_discount_percentage) - pds.cost) * (pds.avg_daily_units_sold * (1 + (p_discount_percentage * (v_sales_lift_multiplier - (p_discount_percentage * (v_sales_lift_multiplier - 1))))) * p_duration_days)) - ((pds.price - pds.cost) * pds.avg_daily_units_sold * p_duration_days) AS estimated_additional_profit
    FROM
        product_daily_sales pds;
END;
$$;

--
-- Name: get_demand_forecast(uuid); Type: FUNCTION; Schema: public; Owner: supabase_admin
--
CREATE OR REPLACE FUNCTION public.get_demand_forecast(p_company_id uuid)
RETURNS TABLE(
    sku text,
    product_name text,
    forecasted_demand_next_30_days numeric
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH monthly_sales AS (
        SELECT
            date_trunc('month', s.created_at) as sale_month,
            i.sku,
            i.name,
            SUM(s.quantity) as total_quantity
        FROM
            public.sales s
        JOIN
            public.inventory i ON s.product_id = i.id
        WHERE
            i.company_id = p_company_id
            AND s.created_at >= NOW() - INTERVAL '12 months'
        GROUP BY
            sale_month, i.sku, i.name
    ),
    ewma_sales AS (
        -- Calculate Exponentially Weighted Moving Average (EWMA) for sales
        -- This gives more weight to recent data. Alpha = 0.3 is a common value.
        SELECT
            sku,
            name,
            sale_month,
            total_quantity,
            AVG(total_quantity) OVER (PARTITION BY sku ORDER BY sale_month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) as ewma
        FROM
            monthly_sales
    ),
    latest_trend AS (
        SELECT
            sku,
            name,
            ewma as monthly_forecast
        FROM
           ewma_sales
        -- Get the latest calculated EWMA for each product
        QUALIFY ROW_NUMBER() OVER (PARTITION BY sku ORDER BY sale_month DESC) = 1
    )
    SELECT
        lt.sku,
        lt.name as product_name,
        -- Forecast for the next 30 days based on the latest trended monthly average
        ROUND(lt.monthly_forecast, 0) as forecasted_demand_next_30_days
    FROM
        latest_trend lt
    ORDER BY
        forecasted_demand_next_30_days DESC
    LIMIT 10;
END;
$$;

--
-- Name: get_customer_segment_analysis(uuid); Type: FUNCTION; Schema: public; Owner: supabase_admin
--
CREATE OR REPLACE FUNCTION public.get_customer_segment_analysis(p_company_id uuid)
RETURNS TABLE(
    segment text,
    sku text,
    product_name text,
    total_quantity bigint,
    total_revenue bigint
)
LANGUAGE sql
AS $$
WITH customer_stats AS (
    SELECT
        c.id as customer_id,
        c.email,
        COUNT(s.id) as total_orders,
        SUM(s.total_amount) as total_spend
    FROM
        public.customers c
    JOIN
        public.sales s ON c.id = s.customer_id
    WHERE
        c.company_id = p_company_id
    GROUP BY
        c.id, c.email
),
top_spenders AS (
    SELECT
        cs.email
    FROM
        customer_stats cs
    ORDER BY
        cs.total_spend DESC
    -- Edge case handled: select at least 1 customer or top 10%
    LIMIT GREATEST(1, (SELECT CEIL(COUNT(*) * 0.1) FROM customer_stats))
),
segmented_sales AS (
    SELECT
        s.id as sale_id,
        s.customer_email,
        CASE
            WHEN cs.total_orders = 1 THEN 'New Customers'
            WHEN cs.total_orders > 1 THEN 'Repeat Customers'
            ELSE 'Unknown'
        END as lifecycle_segment,
        CASE
            WHEN ts.email IS NOT NULL THEN 'Top Spenders'
            ELSE NULL
        END as value_segment
    FROM
        public.sales s
    LEFT JOIN
        customer_stats cs ON s.customer_email = cs.email
    LEFT JOIN
        top_spenders ts ON s.customer_email = ts.email
    WHERE
        s.company_id = p_company_id AND s.customer_email IS NOT NULL
),
unioned_segments AS (
    SELECT sale_id, lifecycle_segment as segment FROM segmented_sales WHERE lifecycle_segment IS NOT NULL
    UNION ALL
    SELECT sale_id, value_segment as segment FROM segmented_sales WHERE value_segment IS NOT NULL
),
product_sales_by_segment AS (
    SELECT
        us.segment,
        i.sku,
        i.name as product_name,
        SUM(si.quantity) as total_quantity,
        SUM(si.quantity * si.unit_price) as total_revenue
    FROM
        unioned_segments us
    JOIN
        public.sale_items si ON us.sale_id = si.sale_id
    JOIN
        public.inventory i ON si.product_id = i.id
    WHERE
        si.company_id = p_company_id
    GROUP BY
        us.segment, i.sku, i.name
),
ranked_products AS (
    SELECT
        *,
        ROW_NUMBER() OVER(PARTITION BY segment ORDER BY total_revenue DESC) as rn
    FROM
        product_sales_by_segment
)
SELECT
    rp.segment,
    rp.sku,
    rp.product_name,
    rp.total_quantity,
    rp.total_revenue
FROM
    ranked_products rp
WHERE
    rp.rn <= 5
ORDER BY
    rp.segment, rp.total_revenue DESC;
$$;
