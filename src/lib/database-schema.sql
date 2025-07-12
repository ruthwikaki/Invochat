-- InvoChat Database Schema
-- Version: 1.5
-- Last Updated: 2024-05-23
-- This script is designed to be idempotent and can be run multiple times.

-- =============================================
-- Setup Extensions
-- =============================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "vector"; -- For PGVector embeddings

-- =============================================
-- Schema & Role Management
-- =============================================
-- The RLS (Row-Level Security) policies below depend on the authenticated user's
-- company_id being available. This is set up via a trigger on user creation.
-- Ensure that your Supabase JWT includes the company_id in the app_metadata.

-- =============================================
-- Tables
-- =============================================

CREATE TABLE IF NOT EXISTS "companies" (
  "id" uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  "name" TEXT NOT NULL,
  "created_at" timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS "users" (
  "id" uuid PRIMARY KEY REFERENCES auth.users(id),
  "company_id" uuid REFERENCES companies(id),
  "role" TEXT NOT NULL DEFAULT 'Member', -- e.g., 'Owner', 'Admin', 'Member'
  "deleted_at" timestamptz
);

CREATE TABLE IF NOT EXISTS "company_settings" (
  "company_id" uuid PRIMARY KEY REFERENCES companies(id) ON DELETE CASCADE,
  "dead_stock_days" INT NOT NULL DEFAULT 90,
  "fast_moving_days" INT NOT NULL DEFAULT 30,
  "predictive_stock_days" INT NOT NULL DEFAULT 7,
  "overstock_multiplier" INT NOT NULL DEFAULT 3,
  "high_value_threshold" INT NOT NULL DEFAULT 100000, -- in cents
  "promo_sales_lift_multiplier" NUMERIC(5, 2) NOT NULL DEFAULT 2.5,
  "currency" TEXT DEFAULT 'USD',
  "timezone" TEXT DEFAULT 'UTC',
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "updated_at" timestamptz
);

CREATE TABLE IF NOT EXISTS "suppliers" (
  "id" uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  "company_id" uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  "name" TEXT NOT NULL,
  "email" TEXT,
  "phone" TEXT,
  "default_lead_time_days" INT,
  "notes" TEXT,
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "updated_at" timestamptz,
  UNIQUE("company_id", "name")
);

CREATE TABLE IF NOT EXISTS "inventory" (
  "id" uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  "company_id" uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  "sku" TEXT NOT NULL,
  "name" TEXT NOT NULL,
  "category" TEXT,
  "price" INT, -- in cents
  "cost" INT NOT NULL, -- in cents
  "quantity" INT NOT NULL DEFAULT 0,
  "reorder_point" INT,
  "supplier_id" uuid REFERENCES suppliers(id),
  "barcode" TEXT,
  "source_platform" TEXT, -- e.g., 'shopify', 'woocommerce', 'manual'
  "external_product_id" TEXT,
  "external_variant_id" TEXT,
  "external_quantity" INT,
  "last_sync_at" timestamptz,
  "deleted_at" timestamptz,
  "deleted_by" uuid REFERENCES users(id),
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "updated_at" timestamptz,
   UNIQUE("company_id", "sku")
);

CREATE TABLE IF NOT EXISTS "customers" (
  "id" uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  "company_id" uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  "customer_name" TEXT NOT NULL,
  "email" TEXT,
  "deleted_at" timestamptz,
  "created_at" timestamptz NOT NULL DEFAULT now(),
  UNIQUE("company_id", "email")
);

CREATE TABLE IF NOT EXISTS "sales" (
  "id" uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  "company_id" uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  "sale_number" TEXT NOT NULL,
  "customer_email" TEXT,
  "total_amount" INT NOT NULL, -- in cents
  "payment_method" TEXT NOT NULL,
  "notes" TEXT,
  "external_id" TEXT, -- ID from source system like Shopify
  "created_at" timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS "sale_items" (
  "id" uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  "sale_id" uuid NOT NULL REFERENCES sales(id) ON DELETE CASCADE,
  "company_id" uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  "product_id" uuid NOT NULL REFERENCES inventory(id),
  "quantity" INT NOT NULL,
  "unit_price" INT NOT NULL, -- in cents
  "cost_at_time" INT, -- in cents
  "created_at" timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS "inventory_ledger" (
  "id" uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  "company_id" uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  "product_id" uuid NOT NULL REFERENCES inventory(id),
  "change_type" TEXT NOT NULL, -- e.g., 'sale', 'restock', 'return', 'adjustment'
  "quantity_change" INT NOT NULL,
  "new_quantity" INT NOT NULL,
  "related_id" uuid, -- e.g., sale_id, purchase_order_id
  "notes" TEXT,
  "created_at" timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS "audit_log" (
  "id" BIGSERIAL PRIMARY KEY,
  "company_id" uuid NOT NULL REFERENCES companies(id),
  "user_id" uuid REFERENCES users(id),
  "action" TEXT NOT NULL,
  "details" JSONB,
  "created_at" timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS "imports" (
  "id" uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  "company_id" uuid NOT NULL REFERENCES companies(id),
  "created_by" uuid REFERENCES users(id),
  "import_type" TEXT NOT NULL,
  "file_name" TEXT NOT NULL,
  "status" TEXT NOT NULL,
  "total_rows" INT NOT NULL,
  "processed_rows" INT,
  "failed_rows" INT,
  "errors" JSONB,
  "summary" JSONB,
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "completed_at" timestamptz
);

CREATE TABLE IF NOT EXISTS "export_jobs" (
    "id" uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    "company_id" uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    "requested_by_user_id" uuid NOT NULL REFERENCES users(id),
    "status" TEXT NOT NULL DEFAULT 'pending',
    "download_url" TEXT,
    "expires_at" timestamptz,
    "created_at" timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS "channel_fees" (
    "id" uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    "company_id" uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    "channel_name" TEXT NOT NULL,
    "percentage_fee" NUMERIC(5, 4) NOT NULL, -- e.g., 0.029 for 2.9%
    "fixed_fee" INT NOT NULL, -- in cents, e.g., 30 for $0.30
    "created_at" timestamptz NOT NULL DEFAULT now(),
    "updated_at" timestamptz,
    UNIQUE("company_id", "channel_name")
);


CREATE TABLE IF NOT EXISTS "integrations" (
  "id" uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  "company_id" uuid NOT NULL REFERENCES companies(id),
  "platform" TEXT NOT NULL,
  "shop_domain" TEXT,
  "shop_name" TEXT,
  "is_active" BOOLEAN NOT NULL DEFAULT true,
  "last_sync_at" timestamptz,
  "sync_status" TEXT,
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "updated_at" timestamptz,
  UNIQUE("company_id", "platform")
);


CREATE TABLE IF NOT EXISTS "sync_state" (
  "id" BIGSERIAL PRIMARY KEY,
  "integration_id" uuid NOT NULL REFERENCES integrations(id) ON DELETE CASCADE,
  "sync_type" TEXT NOT NULL,
  "last_processed_cursor" TEXT,
  "last_update" timestamptz NOT NULL DEFAULT now(),
  UNIQUE("integration_id", "sync_type")
);

-- =============================================
-- Triggers and Functions
-- =============================================

-- Function to create a company and associate it with a new user
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  new_company_id uuid;
BEGIN
  -- Create a new company
  INSERT INTO public.companies (name)
  VALUES (NEW.raw_user_meta_data->>'company_name')
  RETURNING id INTO new_company_id;

  -- Create a user entry
  INSERT INTO public.users (id, company_id, role)
  VALUES (NEW.id, new_company_id, 'Owner');
  
  -- Create a default settings entry
  INSERT INTO public.company_settings (company_id)
  VALUES (new_company_id);

  -- Update the user's app_metadata with the new company_id
  UPDATE auth.users
  SET app_metadata = jsonb_set(
    COALESCE(app_metadata, '{}'::jsonb),
    '{company_id}',
    to_jsonb(new_company_id)
  )
  WHERE id = NEW.id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Trigger to call the function when a new user signs up
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- =============================================
-- Row Level Security (RLS)
-- =============================================
ALTER TABLE companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE sale_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE imports ENABLE ROW LEVEL SECURITY;
ALTER TABLE export_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE sync_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE channel_fees ENABLE ROW LEVEL SECURITY;


-- Function to get the current user's company_id
CREATE OR REPLACE FUNCTION auth.get_company_id()
RETURNS uuid AS $$
BEGIN
  RETURN (current_setting('request.jwt.claims', true)::jsonb -> 'app_metadata' ->> 'company_id')::uuid;
EXCEPTION
  WHEN others THEN
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Policies
DROP POLICY IF EXISTS "Allow read access based on company" ON companies;
CREATE POLICY "Allow read access based on company" ON companies FOR SELECT USING (id = auth.get_company_id());

DROP POLICY IF EXISTS "Allow read access based on company" ON users;
CREATE POLICY "Allow read access based on company" ON users FOR SELECT USING (company_id = auth.get_company_id());

DROP POLICY IF EXISTS "Allow full access based on company" ON company_settings;
CREATE POLICY "Allow full access based on company" ON company_settings FOR ALL USING (company_id = auth.get_company_id());

DROP POLICY IF EXISTS "Allow full access based on company" ON suppliers;
CREATE POLICY "Allow full access based on company" ON suppliers FOR ALL USING (company_id = auth.get_company_id());

DROP POLICY IF EXISTS "Allow full access based on company" ON inventory;
CREATE POLICY "Allow full access based on company" ON inventory FOR ALL USING (company_id = auth.get_company_id());

DROP POLICY IF EXISTS "Allow full access based on company" ON customers;
CREATE POLICY "Allow full access based on company" ON customers FOR ALL USING (company_id = auth.get_company_id());

DROP POLICY IF EXISTS "Allow full access based on company" ON sales;
CREATE POLICY "Allow full access based on company" ON sales FOR ALL USING (company_id = auth.get_company_id());

DROP POLICY IF EXISTS "Allow full access based on company" ON sale_items;
CREATE POLICY "Allow full access based on company" ON sale_items FOR ALL USING (company_id = auth.get_company_id());

DROP POLICY IF EXISTS "Allow read access based on company" ON inventory_ledger;
CREATE POLICY "Allow read access based on company" ON inventory_ledger FOR SELECT USING (company_id = auth.get_company_id());

DROP POLICY IF EXISTS "Allow read access based on company" ON audit_log;
CREATE POLICY "Allow read access based on company" ON audit_log FOR SELECT USING (company_id = auth.get_company_id());

DROP POLICY IF EXISTS "Allow full access based on company" ON imports;
CREATE POLICY "Allow full access based on company" ON imports FOR ALL USING (company_id = auth.get_company_id());

DROP POLICY IF EXISTS "Allow full access based on company" ON export_jobs;
CREATE POLICY "Allow full access based on company" ON export_jobs FOR ALL USING (company_id = auth.get_company_id());

DROP POLICY IF EXISTS "Allow full access based on company" ON integrations;
CREATE POLICY "Allow full access based on company" ON integrations FOR ALL USING (company_id = auth.get_company_id());

DROP POLICY IF EXISTS "Allow full access based on company" ON sync_state;
CREATE POLICY "Allow full access based on company" ON sync_state FOR ALL USING (company_id = auth.get_company_id());

DROP POLICY IF EXISTS "Allow full access based on company" ON channel_fees;
CREATE POLICY "Allow full access based on company" ON channel_fees FOR ALL USING (company_id = auth.get_company_id());


-- =============================================
-- Performance Indexes
-- =============================================
CREATE INDEX IF NOT EXISTS idx_inventory_company_id ON inventory(company_id);
CREATE INDEX IF NOT EXISTS idx_sales_company_id ON sales(company_id);
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON customers(company_id);
CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON suppliers(company_id);
CREATE INDEX IF NOT EXISTS idx_sale_items_sale_id ON sale_items(sale_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_product_id ON inventory_ledger(product_id);

-- =============================================
-- Functions for Reports and Analytics
-- =============================================

DROP FUNCTION IF EXISTS public.get_financial_impact_of_promotion(uuid,text[],numeric,integer);
CREATE OR REPLACE FUNCTION public.get_financial_impact_of_promotion(
    p_company_id uuid,
    p_skus text[],
    p_discount_percentage numeric,
    p_duration_days integer
)
RETURNS TABLE (
    estimated_sales_lift_units numeric,
    estimated_additional_revenue numeric,
    estimated_additional_profit numeric,
    estimated_new_avg_margin numeric
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

    -- If no setting is found, default to 2.5
    sales_lift_multiplier := COALESCE(sales_lift_multiplier, 2.5);

    RETURN QUERY
    WITH avg_daily_sales AS (
        SELECT
            si.product_id,
            SUM(si.quantity)::numeric / 90.0 AS avg_daily_units
        FROM
            public.sale_items si
        JOIN
            public.sales s ON si.sale_id = s.id
        WHERE
            si.company_id = p_company_id
            AND s.created_at >= (now() - interval '90 days')
            AND si.product_id IN (SELECT id FROM public.inventory WHERE sku = ANY(p_skus) AND company_id = p_company_id)
        GROUP BY
            si.product_id
    )
    SELECT
        -- A non-linear model: effect of discount diminishes.
        -- A 20% discount might give a 2x lift, but a 40% discount gives a ~2.7x lift, not 4x.
        SUM(ads.avg_daily_units * p_duration_days * (1 + sales_lift_multiplier * sqrt(p_discount_percentage))) - SUM(ads.avg_daily_units * p_duration_days) AS estimated_sales_lift_units,
        SUM(ads.avg_daily_units * p_duration_days * (1 + sales_lift_multiplier * sqrt(p_discount_percentage)) * (i.price * (1 - p_discount_percentage))) AS estimated_additional_revenue,
        SUM(ads.avg_daily_units * p_duration_days * (1 + sales_lift_multiplier * sqrt(p_discount_percentage)) * (i.price * (1 - p_discount_percentage) - i.cost)) AS estimated_additional_profit,
        AVG((i.price * (1 - p_discount_percentage) - i.cost) / (i.price * (1 - p_discount_percentage))) AS estimated_new_avg_margin
    FROM
        avg_daily_sales ads
    JOIN
        public.inventory i ON ads.product_id = i.id;
END;
$$;


DROP FUNCTION IF EXISTS public.get_demand_forecast(uuid);
CREATE OR REPLACE FUNCTION public.get_demand_forecast(
    p_company_id uuid
)
RETURNS TABLE (
    sku text,
    product_name text,
    forecasted_demand numeric
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH monthly_sales AS (
        SELECT
            i.sku,
            i.name,
            date_trunc('month', s.created_at) AS sale_month,
            SUM(si.quantity) AS total_quantity
        FROM
            public.sale_items si
        JOIN
            public.sales s ON si.sale_id = s.id
        JOIN
            public.inventory i ON si.product_id = i.id
        WHERE
            s.company_id = p_company_id
            AND s.created_at >= now() - interval '12 months'
        GROUP BY
            i.sku, i.name, sale_month
    ),
    ewma_sales AS (
      -- Using EWMA (Exponentially Weighted Moving Average) with alpha=0.3
      -- This gives more weight to recent data.
      SELECT
        sku,
        product_name,
        SUM(total_quantity * power(0.7, (date_part('year', now()) - date_part('year', sale_month)) * 12 + (date_part('month', now()) - date_part('month', sale_month))))
        /
        SUM(power(0.7, (date_part('year', now()) - date_part('year', sale_month)) * 12 + (date_part('month', now()) - date_part('month', sale_month)))) AS ewma_monthly_sales
      FROM monthly_sales
      GROUP BY sku, product_name
    )
    SELECT
        ewma.sku,
        ewma.product_name,
        -- Simple forecast: project the EWMA for the next 30 days
        round(ewma.ewma_monthly_sales) as forecasted_demand
    FROM ewma_sales ewma
    ORDER BY forecasted_demand DESC
    LIMIT 10;
END;
$$;

DROP FUNCTION IF EXISTS public.get_customer_segment_analysis(uuid);
CREATE OR REPLACE FUNCTION public.get_customer_segment_analysis(p_company_id uuid)
RETURNS TABLE (
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
        c.email,
        COUNT(s.id) AS total_orders,
        SUM(s.total_amount) AS total_spend
    FROM
        public.customers c
    JOIN
        public.sales s ON c.email = s.customer_email AND s.company_id = c.company_id
    WHERE
        c.company_id = p_company_id
    GROUP BY
        c.email
),
ranked_customers AS (
    SELECT
        email,
        total_orders,
        total_spend,
        NTILE(10) OVER (ORDER BY total_spend DESC) as decile
    FROM
        customer_stats
),
-- New Customers: First-time buyers in the last 90 days
new_customers AS (
    SELECT
        s.customer_email
    FROM
        public.sales s
    WHERE s.company_id = p_company_id AND s.created_at > (now() - interval '90 days')
    GROUP BY s.customer_email
    HAVING COUNT(s.id) = 1
),
-- Repeat Customers: More than one order
repeat_customers AS (
    SELECT email FROM customer_stats WHERE total_orders > 1
),
-- Top Spenders: Top 10% by lifetime spend
top_spenders AS (
    SELECT email FROM ranked_customers WHERE decile = 1
)
-- Combine sales data for each segment
SELECT
    'New Customers' as segment,
    i.sku,
    i.name as product_name,
    SUM(si.quantity)::bigint as total_quantity,
    SUM(si.quantity * si.unit_price)::bigint as total_revenue
FROM public.sale_items si
JOIN public.sales s ON si.sale_id = s.id
JOIN public.inventory i ON si.product_id = i.id
WHERE s.customer_email IN (SELECT customer_email FROM new_customers) AND s.company_id = p_company_id
GROUP BY i.sku, i.name
HAVING SUM(si.quantity) > 0
ORDER BY total_revenue DESC
LIMIT 5

UNION ALL

SELECT
    'Repeat Customers' as segment,
    i.sku,
    i.name as product_name,
    SUM(si.quantity)::bigint as total_quantity,
    SUM(si.quantity * si.unit_price)::bigint as total_revenue
FROM public.sale_items si
JOIN public.sales s ON si.sale_id = s.id
JOIN public.inventory i ON si.product_id = i.id
WHERE s.customer_email IN (SELECT email FROM repeat_customers) AND s.company_id = p_company_id
GROUP BY i.sku, i.name
HAVING SUM(si.quantity) > 0
ORDER BY total_revenue DESC
LIMIT 5

UNION ALL

SELECT
    'Top Spenders' as segment,
    i.sku,
    i.name as product_name,
    SUM(si.quantity)::bigint as total_quantity,
    SUM(si.quantity * si.unit_price)::bigint as total_revenue
FROM public.sale_items si
JOIN public.sales s ON si.sale_id = s.id
JOIN public.inventory i ON si.product_id = i.id
WHERE s.customer_email IN (SELECT email FROM top_spenders) AND s.company_id = p_company_id
GROUP BY i.sku, i.name
HAVING SUM(si.quantity) > 0
ORDER BY total_revenue DESC
LIMIT 5;
$$;


DROP FUNCTION IF EXISTS public.get_product_lifecycle_analysis(uuid);
CREATE OR REPLACE FUNCTION public.get_product_lifecycle_analysis(p_company_id uuid)
RETURNS json
LANGUAGE plpgsql
AS $$
DECLARE
    v_results json;
BEGIN
    WITH sales_data AS (
        SELECT
            i.id as product_id,
            i.sku,
            i.name as product_name,
            i.created_at as product_created_at,
            date_trunc('month', s.created_at) as sale_month,
            SUM(si.quantity) as monthly_sales,
            SUM(si.quantity * si.unit_price) as monthly_revenue
        FROM
            public.inventory i
        JOIN public.sale_items si ON i.id = si.product_id
        JOIN public.sales s ON si.sale_id = s.id
        WHERE i.company_id = p_company_id
        GROUP BY i.id, i.sku, i.name, i.created_at, sale_month
    ),
    sales_trends AS (
        SELECT
            product_id,
            sku,
            product_name,
            product_created_at,
            sale_month,
            monthly_sales,
            monthly_revenue,
            LAG(monthly_sales, 1, 0) OVER (PARTITION BY sku ORDER BY sale_month) as prev_month_sales,
            LAG(monthly_sales, 2, 0) OVER (PARTITION BY sku ORDER BY sale_month) as prev_2_month_sales
        FROM
            sales_data
    ),
    latest_trends_cte AS (
        SELECT
            *,
            ROW_NUMBER() OVER (PARTITION BY sku ORDER BY sale_month DESC) as rn
        FROM
            sales_trends
    ),
    latest_trends AS (
      SELECT * FROM latest_trends_cte WHERE rn = 1
    ),
    product_stages AS (
        SELECT
            lt.sku,
            lt.product_name,
            lt.monthly_revenue,
            CASE
                WHEN lt.product_created_at > (now() - interval '60 days') AND lt.prev_month_sales = 0 THEN 'Launch'
                WHEN lt.monthly_sales > lt.prev_month_sales AND lt.prev_month_sales > lt.prev_2_month_sales THEN 'Growth'
                WHEN lt.monthly_sales > 0 AND abs(lt.monthly_sales - lt.prev_month_sales) / (lt.prev_month_sales + 1.0) < 0.25 THEN 'Maturity'
                ELSE 'Decline'
            END as stage,
            lt.monthly_sales - lt.prev_month_sales as sales_trend
        FROM
            latest_trends lt
    )
    SELECT json_build_object(
        'summary', (
            SELECT json_build_object(
                'launch_count', COUNT(*) FILTER (WHERE stage = 'Launch'),
                'growth_count', COUNT(*) FILTER (WHERE stage = 'Growth'),
                'maturity_count', COUNT(*) FILTER (WHERE stage = 'Maturity'),
                'decline_count', COUNT(*) FILTER (WHERE stage = 'Decline')
            )
            FROM product_stages
        ),
        'products', (
            SELECT json_agg(
                json_build_object(
                    'sku', sku,
                    'product_name', product_name,
                    'stage', stage,
                    'total_revenue', monthly_revenue,
                    'sales_trend', sales_trend
                )
            )
            FROM product_stages
        )
    ) INTO v_results;

    RETURN v_results;
END;
$$;
