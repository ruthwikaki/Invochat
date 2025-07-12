-- This script is designed to be run on an existing database.
-- It will add new functions required for the latest features.
-- It is idempotent and can be run multiple times without causing errors.

-- ========= Financial & What-If Analysis Functions =========

-- Function to get financial impact of a potential promotion
CREATE OR REPLACE FUNCTION public.get_financial_impact_of_promotion(p_company_id uuid, p_skus text[], p_discount_percentage numeric, p_duration_days integer)
RETURNS TABLE(
    estimated_sales_increase_percentage numeric,
    estimated_additional_units_sold numeric,
    estimated_revenue numeric,
    estimated_profit numeric,
    original_revenue numeric,
    original_profit numeric
) AS $$
BEGIN
    RETURN QUERY
    WITH product_sales_velocity AS (
        SELECT
            si.sku,
            (COUNT(DISTINCT s.id)::numeric / 30) * p_duration_days AS estimated_base_sales
        FROM public.sales s
        JOIN public.sale_items si ON s.id = si.sale_id
        WHERE s.company_id = p_company_id
          AND si.sku = ANY(p_skus)
          AND s.created_at >= NOW() - INTERVAL '30 days'
        GROUP BY si.sku
    ),
    promo_simulation AS (
        SELECT
            i.sku,
            i.price,
            i.cost,
            COALESCE(psv.estimated_base_sales, 1) AS base_units,
            (1 + (p_discount_percentage * 2.5)) AS sales_lift_multiplier -- Simplified sales lift model
        FROM public.inventory i
        LEFT JOIN product_sales_velocity psv ON i.sku = psv.sku
        WHERE i.company_id = p_company_id AND i.sku = ANY(p_skus)
    )
    SELECT
        (AVG(ss.sales_lift_multiplier) - 1) * 100 as estimated_sales_increase_percentage,
        SUM(ss.base_units * ss.sales_lift_multiplier - ss.base_units) as estimated_additional_units_sold,
        SUM(ss.base_units * ss.sales_lift_multiplier * (ss.price * (1 - p_discount_percentage))) as estimated_revenue,
        SUM(ss.base_units * ss.sales_lift_multiplier * ((ss.price * (1 - p_discount_percentage)) - ss.cost)) as estimated_profit,
        SUM(ss.base_units * ss.price) as original_revenue,
        SUM(ss.base_units * (ss.price - ss.cost)) as original_profit
    FROM promo_simulation ss;
END;
$$ LANGUAGE plpgsql;

-- ========= Inventory and Customer Reporting Functions =========

-- Function to get a detailed Inventory Aging Report
CREATE OR REPLACE FUNCTION public.get_inventory_aging_report(p_company_id uuid)
RETURNS TABLE(
    sku text,
    product_name text,
    quantity integer,
    total_value integer,
    days_since_last_sale integer
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        i.sku,
        i.name as product_name,
        i.quantity,
        (i.quantity * i.cost)::integer as total_value,
        (CASE
            WHEN i.last_sold_date IS NULL THEN 9999
            ELSE (NOW()::date - i.last_sold_date::date)
        END) as days_since_last_sale
    FROM public.inventory i
    WHERE i.company_id = p_company_id AND i.deleted_at IS NULL AND i.quantity > 0
    ORDER BY days_since_last_sale DESC;
END;
$$ LANGUAGE plpgsql;

-- Function for Product Lifecycle Analysis
CREATE OR REPLACE FUNCTION public.get_product_lifecycle_analysis(p_company_id uuid)
RETURNS json AS $$
DECLARE
    result_json json;
BEGIN
    -- Temporary table for sales velocity
    CREATE TEMP TABLE temp_sales_velocity AS
    SELECT
        si.sku,
        SUM(CASE WHEN s.created_at >= NOW() - INTERVAL '90 days' THEN si.quantity ELSE 0 END) AS sales_last_90_days,
        SUM(CASE WHEN s.created_at >= NOW() - INTERVAL '180 days' AND s.created_at < NOW() - INTERVAL '90 days' THEN si.quantity ELSE 0 END) AS sales_prev_90_days
    FROM public.sales s
    JOIN public.sale_items si ON s.id = si.sale_id
    WHERE s.company_id = p_company_id AND s.created_at >= NOW() - INTERVAL '180 days'
    GROUP BY si.sku;

    -- Temporary table for product stages
    CREATE TEMP TABLE temp_product_stages AS
    SELECT
        i.sku,
        i.name AS product_name,
        i.created_at,
        i.last_sold_date,
        COALESCE(sv.sales_last_90_days, 0) AS sales_last_90_days,
        (i.price * COALESCE(sv.sales_last_90_days, 0))::integer as total_revenue,
        CASE
            WHEN i.created_at > NOW() - INTERVAL '60 days' AND i.last_sold_date IS NOT NULL THEN 'Launch'
            WHEN COALESCE(sv.sales_last_90_days, 0) > COALESCE(sv.sales_prev_90_days, 0) * 1.2 THEN 'Growth'
            WHEN i.last_sold_date < NOW() - INTERVAL '120 days' THEN 'Decline'
            ELSE 'Maturity'
        END AS stage
    FROM public.inventory i
    LEFT JOIN temp_sales_velocity sv ON i.sku = sv.sku
    WHERE i.company_id = p_company_id AND i.deleted_at IS NULL;

    -- Final result aggregation
    SELECT json_build_object(
        'summary', (SELECT json_build_object(
            'launch_count', COUNT(*) FILTER (WHERE stage = 'Launch'),
            'growth_count', COUNT(*) FILTER (WHERE stage = 'Growth'),
            'maturity_count', COUNT(*) FILTER (WHERE stage = 'Maturity'),
            'decline_count', COUNT(*) FILTER (WHERE stage = 'Decline')
        ) FROM temp_product_stages),
        'products', (SELECT json_agg(tps) FROM temp_product_stages tps)
    ) INTO result_json;

    -- Drop temporary tables
    DROP TABLE temp_sales_velocity;
    DROP TABLE temp_product_stages;

    RETURN result_json;
END;
$$ LANGUAGE plpgsql;


-- Function for Inventory Risk Scoring
CREATE OR REPLACE FUNCTION public.get_inventory_risk_report(p_company_id uuid)
RETURNS TABLE (
    sku text,
    product_name text,
    risk_score integer,
    risk_level text,
    total_value integer,
    reason text
) AS $$
BEGIN
    RETURN QUERY
    WITH risk_factors AS (
        SELECT
            i.sku,
            i.name as product_name,
            (i.quantity * i.cost)::integer as total_value,
            -- Factor 1: Days since last sale (up to 40 points)
            (LEAST(COALESCE(EXTRACT(DAY FROM NOW() - i.last_sold_date), 365), 180)::numeric / 180) * 40 AS age_score,
            -- Factor 2: Overstock level (up to 30 points)
            (CASE
                WHEN i.reorder_point > 0 THEN GREATEST(0, (i.quantity::numeric / i.reorder_point) - 1)
                ELSE 0
            END / 5) * 30 AS overstock_score,
            -- Factor 3: Total value at risk (up to 30 points)
            (i.quantity * i.cost / (SELECT NULLIF(MAX(total_value),0) FROM (SELECT inv.quantity * inv.cost as total_value FROM public.inventory inv WHERE inv.company_id = p_company_id) as inv_values)) * 30 as value_score
        FROM public.inventory i
        WHERE i.company_id = p_company_id AND i.deleted_at IS NULL AND i.quantity > 0
    )
    SELECT
        rf.sku,
        rf.product_name,
        LEAST(100, (COALESCE(rf.age_score, 0) + COALESCE(rf.overstock_score, 0) + COALESCE(rf.value_score, 0)))::integer as risk_score,
        CASE
            WHEN LEAST(100, (COALESCE(rf.age_score, 0) + COALESCE(rf.overstock_score, 0) + COALESCE(rf.value_score, 0))) > 75 THEN 'High'
            WHEN LEAST(100, (COALESCE(rf.age_score, 0) + COALESCE(rf.overstock_score, 0) + COALESCE(rf.value_score, 0))) > 50 THEN 'Medium'
            ELSE 'Low'
        END as risk_level,
        rf.total_value,
        TRIM(BOTH ' | ' FROM
            (CASE WHEN rf.age_score > 10 THEN 'Aging Stock' ELSE '' END) ||
            (CASE WHEN rf.overstock_score > 10 THEN ' | Overstocked' ELSE '' END) ||
            (CASE WHEN rf.value_score > 10 THEN ' | High Value' ELSE '' END)
        ) as reason
    FROM risk_factors rf
    ORDER BY risk_score DESC;
END;
$$ LANGUAGE plpgsql;


-- Function for Customer Segment Analysis
CREATE OR REPLACE FUNCTION public.get_customer_segment_analysis(p_company_id uuid)
RETURNS TABLE (
    segment text,
    sku text,
    product_name text,
    total_quantity bigint,
    total_revenue integer
) AS $$
BEGIN
  RETURN QUERY
  WITH customer_segments AS (
      SELECT
          c.id as customer_id,
          CASE
              WHEN c.first_order_date >= NOW() - INTERVAL '60 days' THEN 'New Customers'
              WHEN c.total_orders > 1 THEN 'Repeat Customers'
              ELSE 'Other'
          END as segment
      FROM public.customers c
      WHERE c.company_id = p_company_id
  ),
  top_spenders AS (
      SELECT c.id as customer_id, 'Top Spenders' as segment
      FROM public.customers c
      WHERE c.company_id = p_company_id
      ORDER BY c.total_spent DESC
      LIMIT (SELECT COUNT(*) * 0.1 FROM public.customers WHERE company_id = p_company_id) -- Top 10%
  ),
  all_segments AS (
      SELECT customer_id, segment FROM customer_segments
      UNION ALL
      SELECT customer_id, segment FROM top_spenders
  ),
  product_sales_by_segment AS (
      SELECT
          seg.segment,
          si.sku,
          SUM(si.quantity) as total_quantity,
          SUM(si.unit_price * si.quantity)::integer as total_revenue,
          ROW_NUMBER() OVER(PARTITION BY seg.segment ORDER BY SUM(si.unit_price * si.quantity) DESC) as rn
      FROM public.sales s
      JOIN public.sale_items si ON s.id = si.sale_id
      JOIN public.customers c ON s.customer_email = c.email AND s.company_id = c.company_id
      JOIN all_segments seg ON c.id = seg.customer_id
      WHERE s.company_id = p_company_id
      GROUP BY seg.segment, si.sku
  )
  SELECT
      ps.segment,
      ps.sku,
      i.name as product_name,
      ps.total_quantity,
      ps.total_revenue
  FROM product_sales_by_segment ps
  JOIN public.inventory i ON ps.sku = i.sku AND i.company_id = p_company_id
  WHERE ps.rn <= 5
  ORDER BY ps.segment, ps.total_revenue DESC;
END;
$$ LANGUAGE plpgsql;


-- Function to get Cash Flow Insights
CREATE OR REPLACE FUNCTION public.get_cash_flow_insights(p_company_id uuid)
RETURNS json AS $$
DECLARE
    v_dead_stock_days integer;
    v_fast_moving_days integer;
BEGIN
    SELECT cs.dead_stock_days, cs.fast_moving_days
    INTO v_dead_stock_days, v_fast_moving_days
    FROM public.company_settings cs
    WHERE cs.company_id = p_company_id;

    RETURN (
        SELECT json_build_object(
            'dead_stock_value', COALESCE(SUM(CASE WHEN (NOW()::date - i.last_sold_date) >= v_dead_stock_days THEN i.quantity * i.cost ELSE 0 END), 0)::integer,
            'slow_mover_value', COALESCE(SUM(CASE WHEN (NOW()::date - i.last_sold_date) BETWEEN v_fast_moving_days AND v_dead_stock_days -1 THEN i.quantity * i.cost ELSE 0 END), 0)::integer,
            'dead_stock_threshold_days', v_dead_stock_days
        )
        FROM public.inventory i
        WHERE i.company_id = p_company_id AND i.deleted_at IS NULL AND i.quantity > 0 AND i.last_sold_date IS NOT NULL
    );
END;
$$ LANGUAGE plpgsql;

-- Add company_id to audit_log if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
        AND table_name = 'audit_log'
        AND column_name = 'company_id'
    ) THEN
        ALTER TABLE public.audit_log ADD COLUMN company_id UUID;
        ALTER TABLE public.audit_log ADD CONSTRAINT audit_log_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id);
    END IF;
END;
$$;
