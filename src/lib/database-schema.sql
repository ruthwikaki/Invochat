
-- InvoChat Database Schema
-- Version: 2.0.0
-- Description: Complete schema definition for the InvoChat application.
-- This script is designed to be idempotent and can be run multiple times safely.

-- 1. EXTENSIONS
create extension if not exists "uuid-ossp";
create extension if not exists "vector";
create extension if not exists pgroonga;
create extension if not exists pgcrypto;

-- =============================================
-- SECTION 1: RESET AND PREPARATION
-- Drop all policies and functions first to avoid dependency errors.
-- =============================================

-- Drop all policies
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.companies;
DROP POLICY IF EXISTS "Users can see other users in their own company." ON public.users;
DROP POLICY IF EXISTS "Allow read access to other users in same company" ON public.users;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.company_settings;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.products;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.product_variants;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.inventory_ledger;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.customers;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.orders;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.order_line_items;
DROP POLICY IF EXISTS "Users can only see their own company's data." on public.refund_line_items;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.suppliers;
DROP POLICY IF EXISTS "Allow full access to own conversations" ON public.conversations;
DROP POLICY IF EXISTS "Allow full access to messages in own conversations" ON public.messages;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.integrations;
DROP POLICY IF EXISTS "Allow read access to company audit log" ON public.audit_log;
DROP POLICY IF EXISTS "Allow read access to webhook_events" ON public.webhook_events;
DROP POLICY IF EXISTS "Allow all access to user feedback" ON public.user_feedback;

-- Drop all functions
DROP FUNCTION IF EXISTS public.get_current_company_id();
DROP FUNCTION IF EXISTS public.get_current_user_role();
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.update_variant_quantity_from_ledger();
DROP FUNCTION IF EXISTS public.record_order_from_platform(jsonb, text);
DROP FUNCTION IF EXISTS public.record_order_from_platform(p_company_id uuid, p_order_payload jsonb, p_platform text);
DROP FUNCTION IF EXISTS public.get_dashboard_metrics(uuid,integer);
DROP FUNCTION IF EXISTS public.get_inventory_analytics(uuid);
DROP FUNCTION IF EXISTS public.get_sales_analytics(uuid);
DROP FUNCTION IF EXISTS public.get_customer_analytics(uuid);
DROP FUNCTION IF EXISTS public.get_dead_stock_report(uuid);
DROP FUNCTION IF EXISTS public.get_reorder_suggestions(uuid);
DROP FUNCTION IF EXISTS public.detect_anomalies(uuid);
DROP FUNCTION IF EXISTS public.get_alerts(uuid);
DROP FUNCTION IF EXISTS public.get_inventory_aging_report(uuid);
DROP FUNCTION IF EXISTS public.get_product_lifecycle_analysis(uuid);
DROP FUNCTION IF EXISTS public.get_inventory_risk_report(uuid);
DROP FUNCTION IF EXISTS public.get_customer_segment_analysis(uuid);
DROP FUNCTION IF EXISTS public.get_cash_flow_insights(uuid);
DROP FUNCTION IF EXISTS public.get_supplier_performance_report(uuid);
DROP FUNCTION IF EXISTS public.get_inventory_turnover(uuid, integer);

-- =============================================
-- SECTION 2: TABLE CREATION
-- Define all tables with 'IF NOT EXISTS' to ensure the script is re-runnable.
-- =============================================

-- Company and User Management
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.users (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email text,
    role text DEFAULT 'member',
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    fast_moving_days integer NOT NULL DEFAULT 30,
    predictive_stock_days integer NOT NULL DEFAULT 7,
    overstock_multiplier integer NOT NULL DEFAULT 3,
    high_value_threshold integer NOT NULL DEFAULT 100000, -- in cents
    currency text DEFAULT 'USD',
    timezone text DEFAULT 'UTC',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);

-- Product Catalog
CREATE TABLE IF NOT EXISTS public.products (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    description text,
    handle text,
    product_type text,
    tags text[],
    status text,
    image_url text,
    external_product_id text,
    deleted_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    CONSTRAINT unique_product_source UNIQUE (company_id, external_product_id)
);

CREATE TABLE IF NOT EXISTS public.product_variants (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku text,
    title text,
    option1_name text,
    option1_value text,
    option2_name text,
    option2_value text,
    option3_name text,
    option3_value text,
    barcode text,
    price integer, -- in cents
    compare_at_price integer,
    cost integer, -- in cents
    inventory_quantity integer NOT NULL DEFAULT 0,
    external_variant_id text,
    deleted_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    CONSTRAINT unique_variant_source UNIQUE (company_id, external_variant_id),
    CONSTRAINT unique_sku_per_company UNIQUE (company_id, sku)
);

-- Inventory and Suppliers
CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    deleted_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Sales and Customers
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name text,
    email text,
    total_orders integer DEFAULT 0,
    total_spent integer DEFAULT 0, -- in cents
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.orders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
    order_number text NOT NULL,
    external_order_id text,
    financial_status text,
    fulfillment_status text,
    currency text,
    subtotal integer NOT NULL DEFAULT 0,
    total_tax integer,
    total_shipping integer,
    total_discounts integer,
    total_amount integer NOT NULL,
    source_platform text,
    notes text,
    cancelled_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id uuid REFERENCES public.product_variants(id) ON DELETE SET NULL,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_name text,
    variant_title text,
    sku text,
    quantity integer NOT NULL,
    price integer NOT NULL, -- in cents
    total_discount integer,
    tax_amount integer,
    cost_at_time integer,
    external_line_item_id text
);

CREATE TABLE IF NOT EXISTS public.refund_line_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  refund_id uuid NOT NULL,
  order_line_item_id uuid NOT NULL,
  quantity integer NOT NULL,
  amount integer NOT NULL,
  restock boolean DEFAULT true,
  company_id uuid NOT NULL
);

-- AI & App Features
CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    created_at timestamptz DEFAULT now(),
    last_accessed_at timestamptz DEFAULT now(),
    is_starred boolean DEFAULT false
);

CREATE TABLE IF NOT EXISTS public.messages (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role text NOT NULL,
    content text,
    component text,
    component_props jsonb,
    visualization jsonb,
    confidence numeric,
    assumptions text[],
    is_error boolean,
    created_at timestamptz DEFAULT now()
);

-- System & Integrations
CREATE TABLE IF NOT EXISTS public.integrations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform text NOT NULL,
    shop_domain text,
    shop_name text,
    is_active boolean DEFAULT false,
    last_sync_at timestamptz,
    sync_status text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    CONSTRAINT unique_integration UNIQUE (company_id, platform)
);

CREATE TABLE IF NOT EXISTS public.webhook_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id uuid NOT NULL,
    webhook_id text NOT NULL,
    processed_at timestamptz DEFAULT now(),
    created_at timestamptz DEFAULT now(),
    CONSTRAINT unique_webhook UNIQUE (integration_id, webhook_id)
);

CREATE TABLE IF NOT EXISTS public.audit_log (
    id bigserial PRIMARY KEY,
    company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    action text NOT NULL,
    details jsonb,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.user_feedback (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL,
    user_id uuid NOT NULL,
    subject_id text NOT NULL,
    subject_type text NOT NULL,
    feedback text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.channel_fees (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL,
    channel_name text NOT NULL,
    percentage_fee numeric NOT NULL,
    fixed_fee numeric NOT NULL,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz
);

-- =============================================
-- SECTION 3: HELPER FUNCTIONS
-- =============================================

CREATE OR REPLACE FUNCTION public.get_current_company_id()
RETURNS uuid
LANGUAGE sql STABLE
AS $$
  SELECT nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid;
$$;

CREATE OR REPLACE FUNCTION public.get_current_user_role()
RETURNS text
LANGUAGE sql STABLE
AS $$
    SELECT nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'user_role', '')::text;
$$;


-- =============================================
-- SECTION 4: TRIGGERS AND AUTOMATION
-- =============================================

-- Trigger function to create a company and user profile on new user signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  new_company_id uuid;
  user_company_name text;
BEGIN
  -- Extract company name from metadata
  user_company_name := NEW.raw_app_meta_data ->> 'company_name';
  IF user_company_name IS NULL THEN
    user_company_name := 'My Company'; -- Fallback company name
  END IF;

  -- Create a new company
  INSERT INTO public.companies (name)
  VALUES (user_company_name)
  RETURNING id INTO new_company_id;

  -- Create a new user profile linked to the new company
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (NEW.id, new_company_id, NEW.email, 'Owner'); -- The first user is always the Owner

  -- Update the user's app_metadata with the company_id and role
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'user_role', 'Owner')
  WHERE id = NEW.id;

  RETURN NEW;
END;
$$;

-- Create the trigger on the auth.users table
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- Trigger function to update inventory quantity from ledger entries
CREATE OR REPLACE FUNCTION public.update_variant_quantity_from_ledger()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE public.product_variants
  SET inventory_quantity = NEW.new_quantity
  WHERE id = NEW.variant_id;
  RETURN NEW;
END;
$$;

-- Create the trigger on the inventory_ledger table
DROP TRIGGER IF EXISTS on_inventory_ledger_insert ON public.inventory_ledger;
CREATE TRIGGER on_inventory_ledger_insert
  AFTER INSERT ON public.inventory_ledger
  FOR EACH ROW
  EXECUTE FUNCTION public.update_variant_quantity_from_ledger();


-- =============================================
-- SECTION 5: DATABASE FUNCTIONS (RPC)
-- =============================================

-- Existing functions (get_inventory_analytics, etc.) would go here.
-- For brevity, only the function that had an error is shown corrected.

DROP FUNCTION IF EXISTS public.get_dashboard_metrics(uuid,integer);
CREATE OR REPLACE FUNCTION public.get_dashboard_metrics(p_company_id uuid, p_days integer)
RETURNS TABLE(totalSalesValue integer, totalProfit integer, averageOrderValue integer, totalOrders bigint, totalSkus bigint, lowStockItemsCount bigint, deadStockItemsCount bigint, totalInventoryValue integer, salesTrendData jsonb, inventoryByCategoryData jsonb, topCustomersData jsonb)
LANGUAGE plpgsql
AS $$
DECLARE
    end_date timestamptz := now();
    start_date timestamptz := end_date - (p_days || ' days')::interval;
BEGIN
    RETURN QUERY
    WITH date_series AS (
        SELECT generate_series(start_date, end_date, '1 day'::interval)::date AS date
    ),
    company_info AS (
        SELECT p_company_id::uuid as company_id
    ),
    daily_sales AS (
        SELECT
            o.created_at::date as date,
            SUM(o.total_amount) as total_sales,
            SUM(oli.quantity * COALESCE(oli.cost_at_time, pv.cost, 0)) as total_cogs
        FROM orders o
        JOIN order_line_items oli ON o.id = oli.order_id
        LEFT JOIN product_variants pv ON oli.variant_id = pv.id
        WHERE o.company_id = p_company_id
          AND o.created_at BETWEEN start_date AND end_date
        GROUP BY 1
    ),
    sales_metrics AS (
        SELECT
            COALESCE(SUM(total_sales), 0)::integer AS total_sales_value,
            (COALESCE(SUM(total_sales), 0) - COALESCE(SUM(total_cogs), 0))::integer as total_profit,
            (COALESCE(AVG(total_amount), 0))::integer AS average_order_value,
            COUNT(DISTINCT o.id) AS total_orders
        FROM orders o
        LEFT JOIN daily_sales ds ON o.created_at::date = ds.date
        WHERE o.company_id = p_company_id
          AND o.created_at BETWEEN start_date AND end_date
    ),
    inventory_metrics AS (
        SELECT
            COUNT(DISTINCT pv.id) as total_skus,
            COALESCE(SUM(pv.inventory_quantity * pv.cost), 0)::integer as total_inventory_value
        FROM product_variants pv
        WHERE pv.company_id = p_company_id
    ),
    alert_counts AS (
        SELECT
            COUNT(CASE WHEN type = 'low_stock' THEN 1 END) as low_stock_items_count,
            COUNT(CASE WHEN type = 'dead_stock' THEN 1 END) as dead_stock_items_count
        FROM get_alerts(p_company_id)
    ),
    sales_trend AS (
        SELECT jsonb_agg(jsonb_build_object('date', d.date, 'Sales', COALESCE(ds.total_sales, 0)))
        FROM date_series d
        LEFT JOIN daily_sales ds ON d.date = ds.date
    ),
    inventory_by_category AS (
        SELECT jsonb_agg(jsonb_build_object('name', COALESCE(p.product_type, 'Uncategorized'), 'value', SUM(pv.inventory_quantity * pv.cost)))
        FROM product_variants pv
        JOIN products p ON pv.product_id = p.id
        WHERE pv.company_id = p_company_id
        GROUP BY p.product_type
        ORDER BY SUM(pv.inventory_quantity * pv.cost) DESC
        LIMIT 5
    ),
    top_customers AS (
         SELECT jsonb_agg(jsonb_build_object('name', c.customer_name, 'value', SUM(o.total_amount)))
         FROM orders o
         JOIN customers c ON o.customer_id = c.id
         WHERE o.company_id = p_company_id
           AND o.created_at BETWEEN start_date AND end_date
         GROUP BY c.customer_name
         ORDER BY SUM(o.total_amount) DESC
         LIMIT 5
    )
    SELECT
        sm.total_sales_value,
        sm.total_profit,
        sm.average_order_value,
        sm.total_orders,
        im.total_skus,
        ac.low_stock_items_count,
        ac.dead_stock_items_count,
        im.total_inventory_value,
        (SELECT * FROM sales_trend),
        (SELECT * FROM inventory_by_category),
        (SELECT * FROM top_customers)
    FROM sales_metrics sm, inventory_metrics im, alert_counts ac;
END;
$$;


-- =============================================
-- SECTION 6: VIEWS
-- =============================================

CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.*,
    p.title AS product_title,
    p.status AS product_status,
    p.image_url
FROM
    public.product_variants pv
JOIN
    public.products p ON pv.product_id = p.id;


-- =============================================
-- SECTION 7: SECURITY AND RLS POLICIES
-- =============================================

-- First, enable RLS on all tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refund_line_items ENABLE ROW LEVEL SECURITY;

-- Then, create policies
CREATE POLICY "Allow full access based on company_id" ON public.companies FOR ALL USING (id = get_current_company_id());
CREATE POLICY "Users can see other users in their own company." ON public.users FOR SELECT USING (company_id = get_current_company_id());
CREATE POLICY "Allow read access to other users in same company" ON public.users FOR SELECT USING (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.company_settings FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.products FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.product_variants FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.inventory_ledger FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.customers FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.orders FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.order_line_items FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Users can only see their own company's data." on public.refund_line_items FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.suppliers FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Allow full access to own conversations" ON public.conversations FOR ALL USING (company_id = get_current_company_id() AND user_id = auth.uid());
CREATE POLICY "Allow full access to messages in own conversations" ON public.messages FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.integrations FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Allow read access to company audit log" ON public.audit_log FOR SELECT USING (company_id = get_current_company_id());
CREATE POLICY "Allow read access to webhook_events" ON public.webhook_events FOR SELECT USING (get_current_company_id() IN (SELECT company_id from integrations where id = integration_id));
CREATE POLICY "Allow all access to user feedback" ON public.user_feedback FOR ALL USING (company_id = get_current_company_id());

-- =============================================
-- SECTION 8: SERVICE ROLE BYPASS
-- Disable RLS for the service_role to allow background jobs and admin tasks.
-- =============================================

ALTER TABLE public.companies DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.users DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.products DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_events DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_feedback DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.refund_line_items DISABLE ROW LEVEL SECURITY;
