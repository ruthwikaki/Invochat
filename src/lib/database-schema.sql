--
-- Base Schema
--
-- This file contains the foundational tables, types, and functions for the application.
-- It is designed to be idempotent and can be run safely on a new or existing database.
--

-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

--
-- Types
--
CREATE TYPE public.user_role AS ENUM ('Owner', 'Admin', 'Member');

--
-- Tables
--

-- Companies Table: Stores basic information about each company using the app.
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    name text NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT companies_pkey PRIMARY KEY (id)
);

-- Users Table: Stores user information, linking them to a company and their auth identity.
CREATE TABLE IF NOT EXISTS public.users (
    id uuid NOT NULL,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email text,
    role user_role NOT NULL DEFAULT 'Member'::user_role,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT users_pkey PRIMARY KEY (id),
    CONSTRAINT users_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_users_company_id ON public.users(company_id);

-- Company Settings Table: Configurable business logic and thresholds for each company.
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid NOT NULL PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    fast_moving_days integer NOT NULL DEFAULT 30,
    predictive_stock_days integer NOT NULL DEFAULT 7,
    overstock_multiplier numeric NOT NULL DEFAULT 3,
    high_value_threshold numeric NOT NULL DEFAULT 100000,
    promo_sales_lift_multiplier numeric NOT NULL DEFAULT 2.5,
    currency text DEFAULT 'USD',
    timezone text DEFAULT 'UTC',
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone
);

-- Suppliers Table
CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT suppliers_pkey PRIMARY KEY (id),
    CONSTRAINT suppliers_company_id_name_key UNIQUE (company_id, name)
);
CREATE INDEX IF NOT EXISTS idx_suppliers_name_company ON public.suppliers(company_id, name);

-- Inventory Table: The core table for all product and stock information.
CREATE TABLE IF NOT EXISTS public.inventory (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku text NOT NULL,
    name text NOT NULL,
    category text,
    quantity integer NOT NULL DEFAULT 0,
    cost integer NOT NULL DEFAULT 0, -- Stored in cents
    price integer, -- Stored in cents
    reorder_point integer,
    supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL,
    barcode text,
    last_sync_at timestamp with time zone,
    source_platform text,
    external_product_id text,
    external_variant_id text,
    external_quantity integer,
    deleted_at timestamp with time zone,
    deleted_by uuid REFERENCES public.users(id),
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone,
    CONSTRAINT inventory_pkey PRIMARY KEY (id),
    CONSTRAINT inventory_company_id_sku_key UNIQUE (company_id, sku)
);
CREATE INDEX IF NOT EXISTS idx_inventory_company_sku ON public.inventory(company_id, sku);
CREATE INDEX IF NOT EXISTS idx_inventory_category ON public.inventory(company_id, category);
CREATE INDEX IF NOT EXISTS idx_inventory_deleted_at ON public.inventory(deleted_at);

-- Customers Table
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name text NOT NULL,
    email text,
    created_at timestamp with time zone DEFAULT now(),
    deleted_at timestamp with time zone,
    CONSTRAINT customers_pkey PRIMARY KEY (id),
    CONSTRAINT customers_company_id_email_key UNIQUE (company_id, email)
);
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers(company_id);

-- Sales Table
CREATE TABLE IF NOT EXISTS public.sales (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
    sale_number text NOT NULL,
    total_amount integer NOT NULL, -- Stored in cents
    payment_method text,
    notes text,
    created_at timestamp with time zone DEFAULT now(),
    external_id text,
    CONSTRAINT sales_pkey PRIMARY KEY (id),
    CONSTRAINT sales_company_id_sale_number_key UNIQUE (company_id, sale_number)
);
CREATE INDEX IF NOT EXISTS idx_sales_company_id ON public.sales(company_id);
CREATE INDEX IF NOT EXISTS idx_sales_created_at ON public.sales(created_at);

-- Sale Items Table
CREATE TABLE IF NOT EXISTS public.sale_items (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    sale_id uuid NOT NULL REFERENCES public.sales(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.inventory(id),
    quantity integer NOT NULL,
    unit_price integer NOT NULL, -- Stored in cents
    cost_at_time integer, -- Stored in cents
    CONSTRAINT sale_items_pkey PRIMARY KEY (id)
);
CREATE INDEX IF NOT EXISTS idx_sale_items_sale_id ON public.sale_items(sale_id);
CREATE INDEX IF NOT EXISTS idx_sale_items_product_id ON public.sale_items(product_id);

-- Inventory Ledger Table: Audit trail for all stock movements.
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.inventory(id),
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid,
    notes text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT inventory_ledger_pkey PRIMARY KEY (id)
);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_product_id ON public.inventory_ledger(product_id, created_at);

-- Integrations Table
CREATE TABLE IF NOT EXISTS public.integrations (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform text NOT NULL,
    shop_domain text,
    shop_name text,
    is_active boolean DEFAULT false,
    last_sync_at timestamp with time zone,
    sync_status text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone,
    CONSTRAINT integrations_pkey PRIMARY KEY (id),
    CONSTRAINT integrations_company_id_platform_key UNIQUE (company_id, platform)
);

-- Conversations and Messages for AI Chat
CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL REFERENCES auth.users(id),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    title text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    last_accessed_at timestamp with time zone DEFAULT now(),
    is_starred boolean DEFAULT false,
    CONSTRAINT conversations_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.messages (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id),
    role text NOT NULL,
    content text,
    component text,
    component_props jsonb,
    visualization jsonb,
    confidence numeric,
    assumptions text[],
    is_error boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT messages_pkey PRIMARY KEY (id)
);
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id_created_at ON public.messages(conversation_id, created_at);

-- Other utility tables
CREATE TABLE IF NOT EXISTS public.audit_log (
    id bigserial PRIMARY KEY,
    user_id uuid REFERENCES auth.users(id),
    company_id uuid REFERENCES public.companies(id),
    action text NOT NULL,
    details jsonb,
    created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.channel_fees (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    channel_name text NOT NULL,
    percentage_fee numeric NOT NULL,
    fixed_fee integer NOT NULL, -- in cents
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone,
    UNIQUE(company_id, channel_name)
);

CREATE TABLE IF NOT EXISTS public.sync_state (
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    sync_type text NOT NULL,
    last_processed_cursor text,
    last_update timestamp with time zone,
    PRIMARY KEY (integration_id, sync_type)
);

CREATE TABLE IF NOT EXISTS public.sync_logs (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    sync_type text,
    status text,
    records_synced integer,
    error_message text,
    started_at timestamp with time zone DEFAULT now(),
    completed_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.export_jobs (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    requested_by_user_id uuid NOT NULL REFERENCES auth.users(id),
    status text NOT NULL DEFAULT 'pending',
    download_url text,
    expires_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);

--
-- Functions and Triggers
--

-- Function to handle new user sign-up
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_company_id uuid;
  v_company_name text;
BEGIN
  -- Extract company name from metadata, defaulting if not present
  v_company_name := NEW.raw_user_meta_data->>'company_name';
  IF v_company_name IS NULL OR v_company_name = '' THEN
    v_company_name := NEW.email || '''s Company';
  END IF;

  -- Create a new company for the new user
  INSERT INTO public.companies (name)
  VALUES (v_company_name)
  RETURNING id INTO v_company_id;

  -- Insert a corresponding row into the public.users table
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (NEW.id, v_company_id, NEW.email, 'Owner');
  
  -- Create default settings for the new company
  INSERT INTO public.company_settings (company_id)
  VALUES (v_company_id);

  -- Update the user's app_metadata with the new company_id and role
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', v_company_id, 'role', 'Owner')
  WHERE id = NEW.id;
  
  RETURN NEW;
END;
$$;

-- Trigger to call handle_new_user on new user creation
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();


-- Function to get ABC analysis
CREATE OR REPLACE FUNCTION public.get_abc_analysis(p_company_id uuid)
RETURNS TABLE(sku text, product_name text, total_revenue numeric, percentage_of_total_revenue numeric, abc_category text)
LANGUAGE sql
AS $$
  WITH product_revenue AS (
    SELECT
      i.sku,
      i.name as product_name,
      SUM(si.quantity * si.unit_price) AS revenue
    FROM public.inventory i
    JOIN public.sale_items si ON i.id = si.product_id
    WHERE i.company_id = p_company_id
    GROUP BY i.id
  ),
  total_revenue AS (
    SELECT SUM(revenue) as total FROM product_revenue
  ),
  ranked_products AS (
    SELECT
      pr.sku,
      pr.product_name,
      pr.revenue / 100.0 as total_revenue,
      (pr.revenue / tr.total) * 100 as percentage_of_total_revenue,
      SUM((pr.revenue / tr.total) * 100) OVER (ORDER BY pr.revenue DESC) as cumulative_percentage
    FROM product_revenue pr, total_revenue tr
  )
  SELECT
    sku,
    product_name,
    total_revenue,
    percentage_of_total_revenue,
    CASE
      WHEN cumulative_percentage <= 80 THEN 'A'
      WHEN cumulative_percentage <= 95 THEN 'B'
      ELSE 'C'
    END as abc_category
  FROM ranked_products;
$$;

-- Upgraded Demand Forecasting Function with EWMA
CREATE OR REPLACE FUNCTION public.get_demand_forecast(p_company_id uuid)
RETURNS TABLE(sku text, product_name text, forecast_30_days numeric)
LANGUAGE plpgsql
AS $$
DECLARE
    alpha numeric := 0.3; -- Smoothing factor for EWMA. Higher values give more weight to recent data.
BEGIN
    RETURN QUERY
    WITH monthly_sales AS (
        SELECT
            i.sku,
            i.name as product_name,
            date_trunc('month', s.created_at) as month,
            SUM(si.quantity) as total_quantity
        FROM public.inventory i
        JOIN public.sale_items si ON i.id = si.product_id
        JOIN public.sales s ON si.sale_id = s.id
        WHERE i.company_id = p_company_id
          AND s.created_at >= now() - interval '12 months'
        GROUP BY i.sku, i.name, month
    ),
    ewma_calculation AS (
      SELECT
          sku,
          product_name,
          -- Calculate the EWMA. The formula is applied iteratively.
          -- SUM(series_val * (1-alpha)^(N - i)) / SUM((1-alpha)^(N-i))
          SUM(total_quantity * power(1 - alpha, (date_part('year', now()) * 12 + date_part('month', now())) - (date_part('year', month) * 12 + date_part('month', month))))
          /
          SUM(power(1 - alpha, (date_part('year', now()) * 12 + date_part('month', now())) - (date_part('year', month) * 12 + date_part('month', month)))) AS ewma_monthly_sales
      FROM monthly_sales
      GROUP BY sku, product_name
    )
    SELECT
        ewma.sku,
        ewma.product_name,
        -- Project for next 30 days
        round(ewma.ewma_monthly_sales, 0) as forecast_30_days
    FROM ewma_calculation ewma
    ORDER BY forecast_30_days DESC
    LIMIT 10;
END;
$$;

-- Upgraded Promotional Impact Analysis Function
CREATE OR REPLACE FUNCTION public.get_financial_impact_of_promotion(
    p_company_id uuid,
    p_skus text[],
    p_discount_percentage numeric,
    p_duration_days integer
)
RETURNS TABLE(
    estimated_sales_lift_units integer,
    estimated_additional_revenue numeric,
    estimated_profit_impact numeric,
    original_profit numeric,
    new_profit_per_unit numeric,
    sales_lift_multiplier numeric
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_sales_lift_multiplier numeric;
    v_avg_daily_sales numeric;
    v_total_cost numeric;
    v_original_price numeric;
BEGIN
    -- Fetch the configurable sales lift multiplier from settings
    SELECT cs.promo_sales_lift_multiplier INTO v_sales_lift_multiplier
    FROM public.company_settings cs
    WHERE cs.company_id = p_company_id;

    -- Use default if not set
    v_sales_lift_multiplier := COALESCE(v_sales_lift_multiplier, 2.5);

    -- Calculate a non-linear lift multiplier based on discount.
    -- This models diminishing returns for very high discounts.
    sales_lift_multiplier := 1 + (v_sales_lift_multiplier * (1 - exp(-5 * p_discount_percentage)));

    -- Get average daily sales and costs for the given SKUs
    SELECT
        SUM(si.quantity) / 90.0, -- Avg daily sales over last 90 days
        SUM(i.cost * si.quantity),
        SUM(i.price * si.quantity)
    INTO
        v_avg_daily_sales,
        v_total_cost,
        v_original_price
    FROM public.sale_items si
    JOIN public.sales s ON si.sale_id = s.id
    JOIN public.inventory i ON si.product_id = i.id
    WHERE i.company_id = p_company_id
      AND i.sku = ANY(p_skus)
      AND s.created_at >= now() - interval '90 days';

    v_avg_daily_sales := COALESCE(v_avg_daily_sales, 0);

    -- Calculate metrics
    estimated_sales_lift_units := floor(v_avg_daily_sales * p_duration_days * (sales_lift_multiplier - 1));
    estimated_additional_revenue := (v_avg_daily_sales * p_duration_days * sales_lift_multiplier) * (v_original_price / GREATEST(v_avg_daily_sales * 90, 1)) * (1 - p_discount_percentage) - (v_avg_daily_sales * p_duration_days * (v_original_price / GREATEST(v_avg_daily_sales * 90, 1)));

    original_profit := (v_original_price - v_total_cost);
    new_profit_per_unit := (v_original_price / GREATEST(v_avg_daily_sales * 90, 1)) * (1 - p_discount_percentage) - (v_total_cost / GREATEST(v_avg_daily_sales * 90, 1));
    estimated_profit_impact := (new_profit_per_unit * v_avg_daily_sales * p_duration_days * sales_lift_multiplier) - original_profit;


    RETURN NEXT;
END;
$$;

-- Upgraded Customer Segmentation Function
CREATE OR REPLACE FUNCTION public.get_customer_segment_analysis(p_company_id uuid)
RETURNS TABLE(segment text, sku text, product_name text, total_quantity bigint, total_revenue bigint)
LANGUAGE sql
AS $$
WITH customer_stats AS (
    SELECT
        c.id as customer_id,
        COUNT(s.id) as order_count,
        SUM(s.total_amount) as total_spend
    FROM public.customers c
    JOIN public.sales s ON c.id = s.customer_id
    WHERE c.company_id = p_company_id
    GROUP BY c.id
),
-- Robustly get the top 10% or at least 1 customer
top_spenders AS (
    SELECT customer_id
    FROM customer_stats
    ORDER BY total_spend DESC
    LIMIT GREATEST(1, floor((SELECT COUNT(*) FROM customer_stats) * 0.1))::integer
),
-- All sales items with customer context
sales_with_customer AS (
    SELECT
        si.*,
        s.customer_id
    FROM public.sale_items si
    JOIN public.sales s ON si.sale_id = s.id
    WHERE s.company_id = p_company_id AND s.customer_id IS NOT NULL
),
-- New customers are those with only one order
new_customers AS (
    SELECT customer_id FROM customer_stats WHERE order_count = 1
),
-- Repeat customers are those with more than one order
repeat_customers AS (
    SELECT customer_id FROM customer_stats WHERE order_count > 1
)
-- Combine the segments
SELECT
    'New Customers' as segment,
    i.sku,
    i.name as product_name,
    sum(swc.quantity) as total_quantity,
    sum(swc.quantity * swc.unit_price) as total_revenue
FROM sales_with_customer swc
JOIN public.inventory i ON swc.product_id = i.id
WHERE swc.customer_id IN (SELECT customer_id FROM new_customers)
GROUP BY i.sku, i.name
ORDER BY total_revenue DESC LIMIT 5

UNION ALL

SELECT
    'Repeat Customers' as segment,
    i.sku,
    i.name as product_name,
    sum(swc.quantity) as total_quantity,
    sum(swc.quantity * swc.unit_price) as total_revenue
FROM sales_with_customer swc
JOIN public.inventory i ON swc.product_id = i.id
WHERE swc.customer_id IN (SELECT customer_id FROM repeat_customers)
GROUP BY i.sku, i.name
ORDER BY total_revenue DESC LIMIT 5

UNION ALL

SELECT
    'Top Spenders' as segment,
    i.sku,
    i.name as product_name,
    sum(swc.quantity) as total_quantity,
    sum(swc.quantity * swc.unit_price) as total_revenue
FROM sales_with_customer swc
JOIN public.inventory i ON swc.product_id = i.id
WHERE swc.customer_id IN (SELECT customer_id FROM top_spenders)
GROUP BY i.sku, i.name
ORDER BY total_revenue DESC LIMIT 5;
$$;


-- Add a new function for inventory aging report
CREATE OR REPLACE FUNCTION public.get_inventory_aging_report(p_company_id uuid)
RETURNS TABLE (
    sku text,
    product_name text,
    quantity integer,
    total_value integer,
    days_since_last_sale integer
)
LANGUAGE sql
AS $$
WITH last_sale AS (
    SELECT
        product_id,
        MAX(s.created_at) as last_sale_date
    FROM public.sale_items si
    JOIN public.sales s ON si.sale_id = s.id
    WHERE s.company_id = p_company_id
    GROUP BY product_id
)
SELECT
    i.sku,
    i.name as product_name,
    i.quantity,
    (i.quantity * i.cost) as total_value,
    COALESCE(
        DATE_PART('day', NOW() - ls.last_sale_date)::integer,
        DATE_PART('day', NOW() - i.created_at)::integer
    ) as days_since_last_sale
FROM public.inventory i
LEFT JOIN last_sale ls ON i.id = ls.product_id
WHERE i.company_id = p_company_id
  AND i.deleted_at IS NULL
  AND i.quantity > 0
ORDER BY days_since_last_sale DESC;
$$;


-- Add a new function for product lifecycle analysis
CREATE OR REPLACE FUNCTION public.get_product_lifecycle_analysis(p_company_id uuid)
RETURNS json
LANGUAGE plpgsql
AS $$
DECLARE
    result json;
BEGIN
    -- Use temporary tables to build up the analysis step by step for clarity and performance
    
    -- 1. Get sales data with time periods
    CREATE TEMP TABLE product_sales_periods ON COMMIT DROP AS
    SELECT
        si.product_id,
        i.name,
        i.sku,
        i.created_at as product_created_at,
        SUM(si.quantity) AS total_sales_volume,
        SUM(si.unit_price * si.quantity) AS total_revenue,
        SUM(CASE WHEN s.created_at >= NOW() - INTERVAL '90 days' THEN si.quantity ELSE 0 END) AS sales_last_90_days,
        SUM(CASE WHEN s.created_at < NOW() - INTERVAL '90 days' AND s.created_at >= NOW() - INTERVAL '180 days' THEN si.quantity ELSE 0 END) AS sales_prior_90_days
    FROM public.sale_items si
    JOIN public.sales s ON si.sale_id = s.id
    JOIN public.inventory i ON si.product_id = i.id
    WHERE s.company_id = p_company_id
    GROUP BY si.product_id, i.name, i.sku, i.created_at;

    -- 2. Classify products based on sales patterns
    CREATE TEMP TABLE classified_products ON COMMIT DROP AS
    SELECT
        name,
        sku,
        total_revenue,
        CASE
            -- Launch: First sale was recent
            WHEN product_created_at >= NOW() - INTERVAL '60 days' AND total_sales_volume > 0 THEN 'Launch'
            -- Growth: Sales in last 90 days are > 20% higher than prior 90 days
            WHEN sales_last_90_days > (sales_prior_90_days * 1.2) AND sales_prior_90_days > 0 THEN 'Growth'
            -- Decline: Sales in last 90 days are < 20% lower than prior 90 days
            WHEN sales_last_90_days < (sales_prior_90_days * 0.8) THEN 'Decline'
            -- Maturity: Stable sales
            ELSE 'Maturity'
        END AS stage,
        sales_last_90_days,
        sales_prior_90_days
    FROM product_sales_periods;

    -- 3. Aggregate the results into the final JSON structure
    SELECT json_build_object(
        'summary', (
            SELECT json_build_object(
                'launch_count', COUNT(*) FILTER (WHERE stage = 'Launch'),
                'growth_count', COUNT(*) FILTER (WHERE stage = 'Growth'),
                'maturity_count', COUNT(*) FILTER (WHERE stage = 'Maturity'),
                'decline_count', COUNT(*) FILTER (WHERE stage = 'Decline')
            ) FROM classified_products
        ),
        'products', (
            SELECT json_agg(
                json_build_object(
                    'product_name', name,
                    'sku', sku,
                    'stage', stage,
                    'total_revenue', total_revenue,
                    'sales_last_90_days', sales_last_90_days,
                    'sales_prior_90_days', sales_prior_90_days
                )
            ) FROM classified_products
        )
    ) INTO result;

    RETURN result;
END;
$$;


-- Add a new function for inventory risk report
CREATE OR REPLACE FUNCTION public.get_inventory_risk_report(p_company_id uuid)
RETURNS TABLE(
    sku text,
    product_name text,
    risk_score integer,
    risk_level text,
    total_value integer,
    reason text
)
LANGUAGE sql
AS $$
WITH sales_velocity AS (
    SELECT
        si.product_id,
        SUM(si.quantity) / 90.0 AS avg_daily_sales
    FROM public.sale_items si
    JOIN public.sales s ON si.sale_id = s.id
    WHERE s.company_id = p_company_id AND s.created_at >= NOW() - INTERVAL '90 days'
    GROUP BY si.product_id
),
risk_factors AS (
    SELECT
        i.sku,
        i.name as product_name,
        i.quantity * i.cost as total_value,
        -- Factor 1: Days of stock (higher is riskier)
        CASE
            WHEN COALESCE(sv.avg_daily_sales, 0) > 0 THEN (i.quantity / COALESCE(sv.avg_daily_sales, 1))
            ELSE 999 -- Assign high risk for items that haven't sold in 90 days
        END AS days_of_stock,
        -- Factor 2: High value (higher is riskier)
        i.cost as unit_cost,
        -- Factor 3: Profit Margin (lower is riskier)
        CASE WHEN i.price > 0 THEN (i.price - i.cost)::numeric / i.price ELSE 0 END AS margin
    FROM public.inventory i
    LEFT JOIN sales_velocity sv ON i.id = sv.product_id
    WHERE i.company_id = p_company_id AND i.deleted_at IS NULL AND i.quantity > 0
),
normalized_scores AS (
    SELECT
        *,
        -- Normalize each factor to a 0-1 scale, then weigh and sum
        (NTILE(100) OVER (ORDER BY days_of_stock DESC)) * 0.5 AS stock_duration_risk,
        (NTILE(100) OVER (ORDER BY total_value DESC)) * 0.3 AS value_risk,
        (NTILE(100) OVER (ORDER BY margin ASC)) * 0.2 AS margin_risk
    FROM risk_factors
)
SELECT
    ns.sku,
    ns.product_name,
    (ns.stock_duration_risk + ns.value_risk + ns.margin_risk)::integer AS risk_score,
    CASE
        WHEN (ns.stock_duration_risk + ns.value_risk + ns.margin_risk) > 75 THEN 'High'
        WHEN (ns.stock_duration_risk + ns.value_risk + ns.margin_risk) > 50 THEN 'Medium'
        ELSE 'Low'
    END AS risk_level,
    ns.total_value::integer,
    'Days of Stock: ' || round(ns.days_of_stock) || ', Value: $' || round(ns.total_value/100.0, 2) || ', Margin: ' || round(ns.margin * 100, 1) || '%' as reason
FROM normalized_scores ns
ORDER BY risk_score DESC;
$$;


ALTER TABLE public.company_settings
ADD COLUMN IF NOT EXISTS promo_sales_lift_multiplier numeric NOT NULL DEFAULT 2.5;
