
-- ===============================================================================================
-- !! DANGER ZONE: DATA RESET SCRIPT !!
-- ===============================================================================================
-- This script will permanently delete all data from your application tables, including users,
-- companies, products, orders, and all related information.
--
-- RUN THIS SCRIPT ONLY IF YOU WANT TO START WITH A COMPLETELY EMPTY DATABASE.
--
-- To use:
-- 1. Copy the entire section from here down to the "END OF DATA RESET SCRIPT" line.
-- 2. Paste it into the Supabase SQL Editor.
-- 3. Click "Run".
--
-- AFTER RUNNING THIS, you will need to run the main setup script below to re-create
-- essential database functions and triggers. Then, you can sign up with a new user.
-- ===============================================================================================

-- Disable all triggers
SET session_replication_role = 'replica';

-- Truncate all application tables to remove their data
TRUNCATE TABLE
  public.companies,
  public.company_settings,
  public.company_users,
  public.products,
  public.product_variants,
  public.suppliers,
  public.orders,
  public.order_line_items,
  public.customers,
  public.purchase_orders,
  public.purchase_order_line_items,
  public.inventory_ledger,
  public.integrations,
  public.conversations,
  public.messages,
  public.feedback,
  public.audit_log,
  public.channel_fees,
  public.imports,
  public.export_jobs,
  public.webhook_events
RESTART IDENTITY CASCADE;

-- Delete all users from the auth schema except for the super admin
DELETE FROM auth.users WHERE email <> 'supabase_admin@supabase.io';

-- Re-enable all triggers
SET session_replication_role = 'origin';

-- ===============================================================================================
-- END OF DATA RESET SCRIPT
-- ===============================================================================================



-- ===============================================================================================
-- ARVO: CORE DATABASE SCHEMA
-- ===============================================================================================
-- This script should be run once in your Supabase SQL Editor to set up the database.
-- ===============================================================================================

-- 1. EXTENSIONS
-- -----------------------------------------------------------------------------------------------
-- Enable necessary extensions
create extension if not exists "uuid-ossp" with schema extensions;


-- 2. ENUMS
-- -----------------------------------------------------------------------------------------------
-- Define custom types used throughout the database for consistency.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'company_role') THEN
    CREATE TYPE public.company_role AS ENUM ('Owner', 'Admin', 'Member');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'integration_platform') THEN
    CREATE TYPE public.integration_platform AS ENUM ('shopify', 'woocommerce', 'amazon_fba');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'message_role') THEN
    CREATE TYPE public.message_role AS ENUM ('user', 'assistant', 'tool');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'feedback_type') THEN
    CREATE TYPE public.feedback_type AS ENUM ('helpful', 'unhelpful');
  END IF;
END$$;


-- 3. TABLES
-- -----------------------------------------------------------------------------------------------
-- Core tables for storing application data.

-- Companies table
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    name text NOT NULL,
    owner_id uuid REFERENCES auth.users(id),
    created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;

-- Company Users junction table (for multi-tenancy)
CREATE TABLE IF NOT EXISTS public.company_users (
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role public.company_role NOT NULL DEFAULT 'Member',
    PRIMARY KEY (company_id, user_id)
);
ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;

-- Company-specific settings table
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days int NOT NULL DEFAULT 90,
    fast_moving_days int NOT NULL DEFAULT 30,
    overstock_multiplier real NOT NULL DEFAULT 3,
    high_value_threshold int NOT NULL DEFAULT 100000,
    predictive_stock_days int NOT NULL DEFAULT 7,
    currency text DEFAULT 'USD',
    timezone text DEFAULT 'UTC',
    tax_rate numeric DEFAULT 0,
    alert_settings jsonb DEFAULT '{"low_stock_threshold": 10, "critical_stock_threshold": 5, "email_notifications": true, "morning_briefing_enabled": true, "morning_briefing_time": "09:00"}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;

-- Products table
CREATE TABLE IF NOT EXISTS public.products (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    description text,
    handle text,
    product_type text,
    tags text[],
    status text,
    image_url text,
    external_product_id text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    CONSTRAINT unique_product_external_id UNIQUE (company_id, external_product_id)
);
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

-- Suppliers table
CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days int,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;

-- Product Variants table (the core of inventory)
CREATE TABLE IF NOT EXISTS public.product_variants (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL,
    sku text NOT NULL,
    title text,
    option1_name text,
    option1_value text,
    option2_name text,
    option2_value text,
    option3_name text,
    option3_value text,
    barcode text,
    price int, -- in cents
    compare_at_price int, -- in cents
    cost int, -- in cents
    inventory_quantity int NOT NULL DEFAULT 0,
    reorder_point int,
    reorder_quantity int,
    location text,
    external_variant_id text,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz,
    CONSTRAINT unique_variant_sku UNIQUE (company_id, sku)
);
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_product_variants_company_sku ON public.product_variants(company_id, sku);

-- Customers table
CREATE TABLE IF NOT EXISTS public.customers (
  id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  name text,
  email text,
  phone text,
  external_customer_id text,
  deleted_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz
);
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;

-- Orders table
CREATE TABLE IF NOT EXISTS public.orders (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
    order_number text NOT NULL,
    external_order_id text,
    financial_status text,
    fulfillment_status text,
    currency text,
    subtotal int NOT NULL,
    total_tax int,
    total_shipping int,
    total_discounts int,
    total_amount int NOT NULL,
    source_platform text,
    created_at timestamptz NOT NULL,
    updated_at timestamptz
);
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);

-- Order Line Items table
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id uuid REFERENCES public.product_variants(id) ON DELETE SET NULL,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_name text,
    variant_title text,
    sku text,
    quantity int NOT NULL,
    price int NOT NULL, -- in cents
    total_discount int, -- in cents
    tax_amount int, -- in cents
    cost_at_time int, -- in cents
    external_line_item_id text
);
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;

-- Purchase Orders table
CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL,
    status text NOT NULL DEFAULT 'Draft',
    po_number text NOT NULL,
    total_cost int NOT NULL,
    expected_arrival_date date,
    notes text,
    idempotency_key uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;

-- Purchase Order Line Items table
CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    purchase_order_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    quantity int NOT NULL,
    cost int NOT NULL -- in cents
);
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;

-- Inventory Ledger table for tracking stock movements
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type text NOT NULL,
    quantity_change int NOT NULL,
    new_quantity int NOT NULL,
    related_id uuid, -- e.g., order_id or po_id
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id ON public.inventory_ledger(variant_id);

-- Integrations table
CREATE TABLE IF NOT EXISTS public.integrations (
  id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  platform public.integration_platform NOT NULL,
  shop_domain text,
  shop_name text,
  is_active boolean DEFAULT false,
  last_sync_at timestamptz,
  sync_status text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz,
  UNIQUE (company_id, platform)
);
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;

-- Audit log table
CREATE TABLE IF NOT EXISTS public.audit_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  action text NOT NULL,
  details jsonb,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

-- Feedback table
CREATE TABLE IF NOT EXISTS public.feedback (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  subject_id text NOT NULL, -- Can be message_id, report_id, etc.
  subject_type text NOT NULL, -- 'message', 'report', etc.
  feedback public.feedback_type NOT NULL,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE public.feedback ENABLE ROW LEVEL SECURITY;

-- Tables for AI Chat functionality
CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    is_starred boolean DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    last_accessed_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.messages (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role public.message_role NOT NULL,
    content text,
    component text,
    componentProps jsonb,
    visualization jsonb,
    confidence numeric,
    assumptions text[],
    isError boolean DEFAULT false,
    created_at timestamptz DEFAULT now()
);
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- Table for channel-specific fees
CREATE TABLE IF NOT EXISTS public.channel_fees (
  id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  channel_name text NOT NULL,
  percentage_fee numeric,
  fixed_fee numeric, -- in cents
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz,
  UNIQUE(company_id, channel_name)
);
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;

-- Table for handling data exports
CREATE TABLE IF NOT EXISTS public.export_jobs (
  id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  requested_by_user_id uuid NOT NULL REFERENCES auth.users(id),
  status text NOT NULL DEFAULT 'pending',
  download_url text,
  expires_at timestamptz,
  error_message text,
  created_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz
);
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;

-- Table for handling data imports
CREATE TABLE IF NOT EXISTS public.imports (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    import_type text NOT NULL,
    file_name text NOT NULL,
    total_rows integer,
    processed_rows integer,
    failed_rows integer,
    status text NOT NULL DEFAULT 'pending', -- e.g., pending, processing, completed, completed_with_errors, failed
    errors jsonb,
    summary jsonb,
    created_at timestamptz DEFAULT now(),
    completed_at timestamptz
);
ALTER TABLE public.imports ENABLE ROW LEVEL SECURITY;

-- Table for preventing webhook replay attacks
CREATE TABLE IF NOT EXISTS public.webhook_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id text NOT NULL,
    created_at timestamptz DEFAULT now(),
    UNIQUE (integration_id, webhook_id)
);
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;

-- 4. DATABASE FUNCTIONS
-- -----------------------------------------------------------------------------------------------
-- Server-side functions to encapsulate business logic.

-- Function to get the company_id for a given user_id
CREATE OR REPLACE FUNCTION public.get_company_id_for_user(p_user_id uuid)
RETURNS uuid AS $$
DECLARE
    company_id uuid;
BEGIN
    SELECT c.company_id INTO company_id
    FROM public.company_users c
    WHERE c.user_id = p_user_id;
    RETURN company_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to handle new user setup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
  company_id uuid;
  user_email text;
BEGIN
  -- Create a new company for the user
  INSERT INTO public.companies (name, owner_id)
  VALUES (new.raw_app_meta_data->>'company_name', new.id)
  RETURNING id INTO company_id;

  -- Link the user to the new company as 'Owner'
  INSERT INTO public.company_users (user_id, company_id, role)
  VALUES (new.id, company_id, 'Owner');
  
  -- Create default settings for the new company
  INSERT INTO public.company_settings (company_id)
  VALUES (company_id);
  
  -- Update the user's app_metadata with the new company_id
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id)
  WHERE id = new.id;
  
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 5. TRIGGERS
-- -----------------------------------------------------------------------------------------------
-- Automations that fire on database events.

-- Trigger to call handle_new_user on new user signup
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();


-- 6. ROW LEVEL SECURITY (RLS)
-- -----------------------------------------------------------------------------------------------
-- Policies to enforce data isolation and multi-tenancy.

-- Generic RLS policies for tables with a `company_id`
DO $$
DECLARE
    t_name text;
BEGIN
    FOR t_name IN
        SELECT table_name FROM information_schema.columns WHERE column_name = 'company_id' AND table_schema = 'public'
    LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', t_name);
        EXECUTE format('DROP POLICY IF EXISTS "User can access their own company data" ON public.%I;', t_name);
        EXECUTE format(
            'CREATE POLICY "User can access their own company data" ON public.%I ' ||
            'FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid())) ' ||
            'WITH CHECK (company_id = public.get_company_id_for_user(auth.uid()));',
            t_name
        );
    END LOOP;
END;
$$;

-- Specific RLS policy for the `companies` table
DROP POLICY IF EXISTS "Users can only see their own company" ON public.companies;
CREATE POLICY "Users can only see their own company"
ON public.companies FOR SELECT
USING (id = public.get_company_id_for_user(auth.uid()));

-- Specific RLS policy for the `company_users` table
DROP POLICY IF EXISTS "Users can see other members of their own company" ON public.company_users;
CREATE POLICY "Users can see other members of their own company"
ON public.company_users FOR SELECT
USING (company_id = public.get_company_id_for_user(auth.uid()));

DROP POLICY IF EXISTS "Owners/Admins can manage their company users" ON public.company_users;
CREATE POLICY "Owners/Admins can manage their company users"
ON public.company_users FOR ALL
USING (company_id = public.get_company_id_for_user(auth.uid()) AND (
    SELECT role FROM public.company_users WHERE user_id = auth.uid() AND company_id = public.get_company_id_for_user(auth.uid())
) IN ('Owner', 'Admin'));


-- 7. VIEWS
-- -----------------------------------------------------------------------------------------------
-- Denormalized views for easier and more performant querying.

-- View for product variants with essential product details
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.*,
    p.title as product_title,
    p.status as product_status,
    p.image_url,
    p.product_type
FROM
    public.product_variants pv
JOIN
    public.products p ON pv.product_id = p.id;

-- View for customers with aggregated order data
CREATE OR REPLACE VIEW public.customers_view AS
SELECT
    c.id,
    c.company_id,
    c.name as customer_name,
    c.email,
    c.created_at,
    count(o.id) as total_orders,
    sum(o.total_amount) as total_spent
FROM
    public.customers c
LEFT JOIN
    public.orders o ON c.id = o.customer_id
WHERE c.deleted_at IS NULL
GROUP BY
    c.id, c.company_id;

-- View for orders with customer email
CREATE OR REPLACE VIEW public.orders_view AS
SELECT
    o.*,
    c.email as customer_email
FROM
    public.orders o
LEFT JOIN
    public.customers c ON o.customer_id = c.id;

-- View for purchase orders with supplier name
CREATE OR REPLACE VIEW public.purchase_orders_view AS
SELECT 
    po.*,
    s.name as supplier_name
FROM 
    public.purchase_orders po
LEFT JOIN 
    public.suppliers s ON po.supplier_id = s.id;


-- 8. MATERIALIZED VIEWS
-- -----------------------------------------------------------------------------------------------
-- Materialized views for expensive, frequently accessed analytical queries.

-- Materialized view for daily sales summaries
DROP MATERIALIZED VIEW IF EXISTS public.daily_sales_matview;
CREATE MATERIALIZED VIEW public.daily_sales_matview AS
SELECT
    company_id,
    date_trunc('day', created_at) AS sale_date,
    sum(total_amount) AS total_revenue,
    count(id) AS total_orders
FROM public.orders
GROUP BY company_id, date_trunc('day', created_at);
CREATE UNIQUE INDEX IF NOT EXISTS daily_sales_matview_idx ON public.daily_sales_matview(company_id, sale_date);

-- Function to refresh all materialized views for a company
CREATE OR REPLACE FUNCTION public.refresh_all_matviews(p_company_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.daily_sales_matview;
    -- Add other materialized views here in the future
END;
$$;


-- 9. ADVANCED DATABASE FUNCTIONS
-- -----------------------------------------------------------------------------------------------
-- More complex functions for analytics and operations.

-- Function to get dashboard metrics
CREATE OR REPLACE FUNCTION public.get_dashboard_metrics(p_company_id uuid, p_days int)
RETURNS json
LANGUAGE plpgsql
AS $$
DECLARE
    result json;
BEGIN
    SELECT json_build_object(
        'total_revenue', (SELECT COALESCE(SUM(total_amount), 0) FROM public.orders WHERE company_id = p_company_id AND created_at >= now() - (p_days || ' days')::interval),
        'revenue_change', 0, -- Placeholder
        'total_sales', (SELECT COALESCE(COUNT(id), 0) FROM public.orders WHERE company_id = p_company_id AND created_at >= now() - (p_days || ' days')::interval),
        'sales_change', 0, -- Placeholder
        'new_customers', (SELECT COALESCE(COUNT(id), 0) FROM public.customers WHERE company_id = p_company_id AND created_at >= now() - (p_days || ' days')::interval),
        'customers_change', 0, -- Placeholder
        'dead_stock_value', (SELECT COALESCE(SUM(total_value), 0) FROM public.get_dead_stock_report(p_company_id)),
        'sales_over_time', (SELECT json_agg(json_build_object('date', sale_date, 'total_sales', total_revenue)) FROM public.daily_sales_matview WHERE company_id = p_company_id AND sale_date >= now() - (p_days || ' days')::interval),
        'top_selling_products', (
            SELECT json_agg(t)
            FROM (
                SELECT p.title AS product_name, p.image_url, SUM(oli.price * oli.quantity) AS total_revenue
                FROM public.order_line_items oli
                JOIN public.product_variants pv ON oli.variant_id = pv.id
                JOIN public.products p ON pv.product_id = p.id
                WHERE oli.company_id = p_company_id AND oli.created_at >= now() - (p_days || ' days')::interval
                GROUP BY p.id, p.title, p.image_url
                ORDER BY total_revenue DESC
                LIMIT 5
            ) t
        ),
        'inventory_summary', (SELECT json_build_object(
            'total_value', COALESCE(SUM(cost * inventory_quantity), 0),
            'in_stock_value', COALESCE(SUM(CASE WHEN inventory_quantity > reorder_point THEN cost * inventory_quantity ELSE 0 END), 0),
            'low_stock_value', COALESCE(SUM(CASE WHEN inventory_quantity <= reorder_point AND inventory_quantity > 0 THEN cost * inventory_quantity ELSE 0 END), 0),
            'dead_stock_value', (SELECT COALESCE(SUM(total_value), 0) FROM public.get_dead_stock_report(p_company_id))
        ) FROM public.product_variants_with_details WHERE company_id = p_company_id)
    ) INTO result;
    RETURN result;
END;
$$;

-- Function to get dead stock report
CREATE OR REPLACE FUNCTION public.get_dead_stock_report(p_company_id uuid)
RETURNS TABLE(sku text, product_name text, quantity int, total_value int, last_sale_date timestamptz)
LANGUAGE plpgsql
AS $$
DECLARE
    v_dead_stock_days int;
BEGIN
    SELECT dead_stock_days INTO v_dead_stock_days FROM public.company_settings WHERE company_id = p_company_id;
    RETURN QUERY
    WITH last_sale AS (
        SELECT
            oli.variant_id,
            MAX(o.created_at) as last_sale_date
        FROM public.order_line_items oli
        JOIN public.orders o ON oli.order_id = o.id
        WHERE oli.company_id = p_company_id
        GROUP BY oli.variant_id
    )
    SELECT
        pv.sku,
        p.title AS product_name,
        pv.inventory_quantity AS quantity,
        (pv.cost * pv.inventory_quantity)::int AS total_value,
        ls.last_sale_date
    FROM public.product_variants pv
    JOIN public.products p ON pv.product_id = p.id
    LEFT JOIN last_sale ls ON pv.id = ls.variant_id
    WHERE pv.company_id = p_company_id
      AND pv.inventory_quantity > 0
      AND (ls.last_sale_date IS NULL OR ls.last_sale_date < now() - (v_dead_stock_days || ' days')::interval);
END;
$$;

-- Function to create a full purchase order with line items
CREATE OR REPLACE FUNCTION public.create_full_purchase_order(
    p_company_id uuid,
    p_user_id uuid,
    p_supplier_id uuid,
    p_status text,
    p_notes text,
    p_expected_arrival date,
    p_line_items jsonb
) RETURNS uuid AS $$
DECLARE
    new_po_id uuid;
    total_cost_calc int := 0;
    item jsonb;
    item_cost int;
    item_quantity int;
BEGIN
    -- Calculate total cost from line items
    FOR item IN SELECT * FROM jsonb_array_elements(p_line_items)
    LOOP
        item_cost := (item->>'cost')::int;
        item_quantity := (item->>'quantity')::int;
        total_cost_calc := total_cost_calc + (item_cost * item_quantity);
    END LOOP;

    -- Insert the main purchase order
    INSERT INTO public.purchase_orders (company_id, supplier_id, status, notes, expected_arrival_date, total_cost, po_number)
    VALUES (
        p_company_id,
        p_supplier_id,
        p_status,
        p_notes,
        p_expected_arrival,
        total_cost_calc,
        'PO-' || (SELECT COUNT(*) + 1001 FROM public.purchase_orders WHERE company_id = p_company_id)::text
    ) RETURNING id INTO new_po_id;

    -- Insert line items
    FOR item IN SELECT * FROM jsonb_array_elements(p_line_items)
    LOOP
        INSERT INTO public.purchase_order_line_items (purchase_order_id, variant_id, quantity, cost, company_id)
        VALUES (
            new_po_id,
            (item->>'variant_id')::uuid,
            (item->>'quantity')::int,
            (item->>'cost')::int,
            p_company_id
        );
    END LOOP;

    -- Create audit log
    INSERT INTO public.audit_log (company_id, user_id, action, details)
    VALUES (p_company_id, p_user_id, 'purchase_order_created', jsonb_build_object('po_id', new_po_id, 'supplier_id', p_supplier_id, 'total_cost', total_cost_calc));

    RETURN new_po_id;
END;
$$ LANGUAGE plpgsql;


-- Finalization
-- -----------------------------------------------------------------------------------------------
-- Any final commands to run after setting up the schema.

-- Grant usage on the public schema to the authenticated role
GRANT USAGE ON SCHEMA public TO authenticated;
-- Grant select permissions on all current and future tables in the public schema to the authenticated role
GRANT SELECT ON ALL TABLES IN SCHEMA public TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO authenticated;
-- Grant execute permissions on all functions to the authenticated role
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;


-- Grant access to Supabase's managed roles
grant usage on schema public to anon, authenticated, service_role;
grant all privileges on all tables in schema public to anon, authenticated, service_role;
grant all privileges on all functions in schema public to anon, authenticated, service_role;
grant all privileges on all sequences in schema public to anon, authenticated, service_role;

-- Grant access to PGMemento roles if the extension is used
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'pgmemento_roles_writer') THEN
    GRANT USAGE ON SCHEMA public TO pgmemento_roles_writer;
    GRANT ALL ON ALL TABLES IN SCHEMA public TO pgmemento_roles_writer;
  END IF;
END
$$;

-- Refresh the materialized views for the first time
SELECT public.refresh_all_matviews(c.id) FROM public.companies c;
