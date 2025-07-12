-- ### Smart Promotional Impact Model ###

-- Add a new column to company_settings for the configurable promo multiplier
-- This is designed to be run on an existing table.
ALTER TABLE public.company_settings
ADD COLUMN IF NOT EXISTS promo_sales_lift_multiplier real NOT NULL DEFAULT 2.5;

-- Drop the old function if it exists
DROP FUNCTION IF EXISTS public.get_financial_impact_of_promotion(uuid, text[], numeric, integer);

-- Create the new function with updated logic
CREATE OR REPLACE FUNCTION public.get_financial_impact_of_promotion(p_company_id uuid, p_skus text[], p_discount_percentage numeric, p_duration_days integer)
RETURNS TABLE(
    sku text,
    product_name text,
    current_price integer,
    discounted_price integer,
    projected_units_sold_increase integer,
    projected_revenue_change integer,
    projected_profit_change integer
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_sales_lift_multiplier REAL;
BEGIN
    -- Get the configurable sales lift multiplier from settings
    SELECT cs.promo_sales_lift_multiplier INTO v_sales_lift_multiplier
    FROM public.company_settings cs
    WHERE cs.company_id = p_company_id;

    RETURN QUERY
    WITH product_sales_velocity AS (
        SELECT
            inv.sku,
            inv.name AS product_name,
            inv.price,
            COALESCE(SUM(si.quantity), 0) AS units_sold_last_30_days
        FROM public.inventory inv
        LEFT JOIN public.sales_items si ON inv.id = si.product_id
        LEFT JOIN public.sales s ON si.sale_id = s.id
        WHERE inv.company_id = p_company_id
          AND inv.sku = ANY(p_skus)
          AND s.created_at >= NOW() - INTERVAL '30 days'
        GROUP BY inv.id, inv.sku, inv.name, inv.price
    )
    SELECT
        psv.sku,
        psv.product_name,
        psv.price AS current_price,
        (psv.price * (1 - p_discount_percentage))::integer AS discounted_price,
        -- Non-linear sales lift model: Diminishing returns for higher discounts.
        (psv.units_sold_last_30_days * (p_discount_percentage * v_sales_lift_multiplier) * (p_duration_days / 30.0))::integer AS projected_units_sold_increase,
        (psv.price * (1 - p_discount_percentage) * (psv.units_sold_last_30_days * (p_discount_percentage * v_sales_lift_multiplier) * (p_duration_days / 30.0)) - (psv.price * psv.units_sold_last_30_days * (p_duration_days / 30.0)))::integer AS projected_revenue_change,
        -- Assuming profit change is directly related to revenue change for simplicity here
        (psv.price * (1 - p_discount_percentage) * (psv.units_sold_last_30_days * (p_discount_percentage * v_sales_lift_multiplier) * (p_duration_days / 30.0)) - (psv.price * psv.units_sold_last_30_days * (p_duration_days / 30.0)))::integer AS projected_profit_change
    FROM product_sales_velocity psv;
END;
$$;


-- ### More Accurate Demand Forecasting ###

-- Drop the old function if it exists
DROP FUNCTION IF EXISTS public.get_demand_forecast(uuid);

-- Create the new function with EWMA logic
CREATE OR REPLACE FUNCTION public.get_demand_forecast(p_company_id uuid)
RETURNS TABLE(
    sku text,
    product_name text,
    current_inventory integer,
    "30_day_ewma_forecast" numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    alpha numeric := 0.3; -- Smoothing factor for EWMA, giving more weight to recent data.
BEGIN
    RETURN QUERY
    WITH monthly_sales AS (
        SELECT
            p.sku,
            date_trunc('month', s.created_at) AS month,
            SUM(si.quantity) AS total_quantity
        FROM public.inventory p
        JOIN public.sales_items si ON p.id = si.product_id
        JOIN public.sales s ON si.sale_id = s.id
        WHERE p.company_id = p_company_id
        GROUP BY p.sku, date_trunc('month', s.created_at)
    ),
    ewma_forecast AS (
      SELECT
          sku,
          (
              SELECT SUM(total_quantity * power(1 - alpha, (extract(year from age(month)) * 12 + extract(month from age(month)))::integer))
              FROM monthly_sales sub
              WHERE sub.sku = ms.sku
          ) / (
              SELECT SUM(power(1 - alpha, (extract(year from age(month)) * 12 + extract(month from age(month)))::integer))
              FROM monthly_sales sub
              WHERE sub.sku = ms.sku
          ) AS forecast
      FROM monthly_sales ms
      GROUP BY sku
    )
    SELECT
        i.sku,
        i.name as product_name,
        i.quantity as current_inventory,
        ROUND(f.forecast, 0) AS "30_day_ewma_forecast"
    FROM ewma_forecast f
    JOIN public.inventory i ON f.sku = i.sku AND i.company_id = p_company_id
    ORDER BY f.forecast DESC
    LIMIT 10;
END;
$$;


-- ### Robust Customer Segmentation ###

-- Drop the old function if it exists
DROP FUNCTION IF EXISTS public.get_customer_segment_analysis(uuid);

-- Create the new function with robust top 10% logic
CREATE OR REPLACE FUNCTION public.get_customer_segment_analysis(p_company_id uuid)
RETURNS TABLE (
    segment text,
    sku text,
    product_name text,
    total_quantity bigint,
    total_revenue bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    WITH customer_segments AS (
        SELECT
            c.id AS customer_id,
            CASE
                WHEN (SELECT COUNT(*) FROM public.sales s WHERE s.customer_email = c.email) = 1 THEN 'New Customers'
                ELSE 'Repeat Customers'
            END AS segment,
            c.email
        FROM public.customers c
        WHERE c.company_id = p_company_id
    ),
    top_spenders AS (
        -- Select top 10% of customers by spend, but always at least 1
        SELECT c.email
        FROM public.customers c
        WHERE c.company_id = p_company_id
        ORDER BY c.total_spent DESC
        LIMIT GREATEST(1, (SELECT (COUNT(*) * 0.1)::integer FROM public.customers WHERE company_id = p_company_id))
    )
    SELECT
        cs.segment,
        p.sku,
        p.name AS product_name,
        SUM(si.quantity)::bigint AS total_quantity,
        SUM(si.quantity * si.unit_price)::bigint AS total_revenue
    FROM customer_segments cs
    JOIN public.sales s ON cs.email = s.customer_email AND s.company_id = p_company_id
    JOIN public.sales_items si ON s.id = si.sale_id
    JOIN public.inventory p ON si.product_id = p.id
    GROUP BY cs.segment, p.sku, p.name

    UNION ALL

    SELECT
        'Top Spenders' AS segment,
        p.sku,
        p.name AS product_name,
        SUM(si.quantity)::bigint AS total_quantity,
        SUM(si.quantity * si.unit_price)::bigint AS total_revenue
    FROM top_spenders ts
    JOIN public.sales s ON ts.email = s.customer_email AND s.company_id = p_company_id
    JOIN public.sales_items si ON s.id = si.sale_id
    JOIN public.inventory p ON si.product_id = p.id
    GROUP BY p.sku, p.name
    ORDER BY segment, total_revenue DESC;
END;
$$;
