-- InvoChat Database Schema
-- Version: 2.0.0
-- Description: This script sets up all necessary tables, views, functions, 
-- and security policies for the InvoChat application. It is designed to be
-- idempotent and can be run safely on new or existing databases.

-- Drop old, conflicting objects first to ensure a clean setup.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS handle_new_user();

-- Helper function to get the company_id from the current session's JWT claims.
-- This is a cornerstone of the Row-Level Security (RLS) policy.
CREATE OR REPLACE FUNCTION public.get_company_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT (NULLIF(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid);
$$;

-- Helper function to get the currently authenticated user's ID.
CREATE OR REPLACE FUNCTION public.get_user_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT (NULLIF(current_setting('request.jwt.claims', true)::jsonb ->> 'sub', '')::uuid);
$$;


-- =============================================
-- SECTION 1: TABLES
-- All tables are created with "IF NOT EXISTS" to prevent errors on re-runs.
-- =============================================

CREATE TABLE IF NOT EXISTS public.companies (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.users (
    id uuid PRIMARY KEY, -- This is the same as auth.users.id
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email text,
    role text DEFAULT 'Member'::text, -- Roles: 'Owner', 'Admin', 'Member'
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    fast_moving_days integer NOT NULL DEFAULT 30,
    overstock_multiplier integer NOT NULL DEFAULT 3,
    high_value_threshold integer NOT NULL DEFAULT 100000, -- in cents
    predictive_stock_days integer NOT NULL DEFAULT 7,
    currency text DEFAULT 'USD',
    timezone text DEFAULT 'UTC',
    tax_rate numeric DEFAULT 0,
    promo_sales_lift_multiplier real NOT NULL DEFAULT 2.5,
    custom_rules jsonb,
    subscription_status text DEFAULT 'trial',
    subscription_plan text DEFAULT 'starter',
    subscription_expires_at timestamptz,
    stripe_customer_id text,
    stripe_subscription_id text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.integrations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform text NOT NULL,
    shop_domain text,
    shop_name text,
    is_active boolean DEFAULT false,
    last_sync_at timestamptz,
    sync_status text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, platform)
);

CREATE TABLE IF NOT EXISTS public.products (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    description text,
    handle text,
    product_type text,
    tags text[],
    status text,
    image_url text,
    external_product_id text,
    fts_document tsvector,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, external_product_id)
);

CREATE TABLE IF NOT EXISTS public.product_variants (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku text NOT NULL,
    title text,
    option1_name text,
    option1_value text,
    option2_name text,
    option2_value text,
    option3_name text,
    option3_value text,
    barcode text,
    price integer, -- in cents
    compare_at_price integer, -- in cents
    cost integer, -- in cents
    inventory_quantity integer NOT NULL DEFAULT 0,
    external_variant_id text,
    location text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    UNIQUE(company_id, sku),
    UNIQUE(company_id, external_variant_id)
);

CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid, -- e.g., order_id, po_id, etc.
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.customers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name text,
    email text,
    total_orders integer DEFAULT 0,
    total_spent integer DEFAULT 0, -- in cents
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now(),
    UNIQUE(company_id, email)
);

CREATE TABLE IF NOT EXISTS public.orders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number text NOT NULL,
    external_order_id text,
    customer_id uuid REFERENCES public.customers(id),
    status text NOT NULL DEFAULT 'pending',
    financial_status text DEFAULT 'pending',
    fulfillment_status text DEFAULT 'unfulfilled',
    currency text DEFAULT 'USD',
    subtotal integer NOT NULL DEFAULT 0,
    total_tax integer DEFAULT 0,
    total_shipping integer DEFAULT 0,
    total_discounts integer DEFAULT 0,
    total_amount integer NOT NULL,
    source_platform text,
    source_name text,
    tags text[],
    notes text,
    cancelled_at timestamptz,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    UNIQUE(company_id, external_order_id)
);

CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    product_id uuid REFERENCES public.products(id),
    variant_id uuid REFERENCES public.product_variants(id),
    product_name text NOT NULL,
    variant_title text,
    sku text,
    quantity integer NOT NULL,
    price integer NOT NULL, -- in cents
    cost_at_time integer, -- in cents
    total_discount integer DEFAULT 0,
    tax_amount integer DEFAULT 0,
    fulfillment_status text DEFAULT 'unfulfilled',
    requires_shipping boolean DEFAULT true,
    external_line_item_id text
);

CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.suppliers(id),
    status text NOT NULL DEFAULT 'Draft',
    po_number text NOT NULL,
    total_cost integer NOT NULL,
    expected_arrival_date date,
    idempotency_key uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(company_id, po_number)
);

CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    purchase_order_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id),
    quantity integer NOT NULL,
    cost integer NOT NULL
);

-- AI & App Feature Tables
CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid REFERENCES public.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    created_at timestamptz DEFAULT now(),
    last_accessed_at timestamptz DEFAULT now(),
    is_starred boolean DEFAULT false
);

CREATE TABLE IF NOT EXISTS public.messages (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role text NOT NULL, -- 'user' or 'assistant'
    content text,
    component text,
    component_props jsonb,
    visualization jsonb,
    confidence numeric,
    assumptions text[],
    is_error boolean DEFAULT false,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.audit_log (
    id bigserial PRIMARY KEY,
    company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id uuid REFERENCES public.users(id),
    action text NOT NULL,
    details jsonb,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.webhook_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id text NOT NULL,
    processed_at timestamptz DEFAULT now(),
    created_at timestamptz DEFAULT now(),
    UNIQUE(integration_id, webhook_id)
);


-- =============================================
-- SECTION 2: INDEXES
-- Indexes are added to improve query performance on frequently filtered columns.
-- =============================================
CREATE INDEX IF NOT EXISTS idx_users_company_id ON public.users(company_id);
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_variants_company_id_sku ON public.product_variants(company_id, sku);
CREATE INDEX IF NOT EXISTS idx_orders_company_id_created_at ON public.orders(company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ledger_variant_id ON public.inventory_ledger(variant_id);
CREATE INDEX IF NOT EXISTS idx_ledger_company_id_created_at ON public.inventory_ledger(company_id, created_at DESC);

-- =============================================
-- SECTION 3: DATABASE FUNCTIONS
-- =============================================

-- This function is called by the application's signup action.
-- It creates a company, a user profile, and default settings in a single transaction.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id uuid := public.get_user_id();
    v_company_id uuid;
    v_user_email text;
    v_company_name text;
BEGIN
    -- Get user email and company name from auth.users metadata
    SELECT email, raw_app_meta_data->>'company_name'
    INTO v_user_email, v_company_name
    FROM auth.users
    WHERE id = v_user_id;

    -- Create a new company
    INSERT INTO public.companies (name)
    VALUES (v_company_name)
    RETURNING id INTO v_company_id;

    -- Update the user's app_metadata in auth.users to link them to the new company
    UPDATE auth.users
    SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', v_company_id, 'role', 'Owner')
    WHERE id = v_user_id;

    -- Create a corresponding entry in the public.users table
    INSERT INTO public.users (id, company_id, email, role)
    VALUES (v_user_id, v_company_id, v_user_email, 'Owner');
    
    -- Create default settings for the new company
    INSERT INTO public.company_settings (company_id)
    VALUES (v_company_id);
END;
$$;


-- =============================================
-- SECTION 4: ROW-LEVEL SECURITY (RLS)
-- =============================================

-- Master procedure to enable RLS on all tables and apply policies.
-- This makes the script idempotent and easier to manage.
CREATE OR REPLACE PROCEDURE apply_rls_policies(table_name text)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Enable RLS on the table if not already enabled
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', table_name);
    
    -- Drop existing policy to ensure it's always up-to-date
    EXECUTE format('DROP POLICY IF EXISTS "Allow all access to own company data" ON %I', table_name);

    -- Create the new policy
    IF table_name = 'public.companies' THEN
      EXECUTE format('CREATE POLICY "Allow all access to own company data" ON %I FOR ALL USING (id = public.get_company_id()) WITH CHECK (id = public.get_company_id())', table_name);
    ELSE
      EXECUTE format('CREATE POLICY "Allow all access to own company data" ON %I FOR ALL USING (company_id = public.get_company_id()) WITH CHECK (company_id = public.get_company_id())', table_name);
    END IF;
END;
$$;

-- Run the RLS procedure on all tables that require it.
DO $$
DECLARE
    t text;
BEGIN
    FOR t IN 
        SELECT table_name FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name NOT IN ('webhook_events') -- List any tables to exclude from RLS
    LOOP
        CALL apply_rls_policies(t);
    END LOOP;
END;
$$;


-- Special case for purchase_order_line_items which doesn't have a direct company_id
-- We secure it by checking the company_id of the parent purchase order.
DROP POLICY IF EXISTS "Allow all access to own company data" ON public.purchase_order_line_items;
CREATE POLICY "Allow all access to own company data" ON public.purchase_order_line_items
FOR ALL
USING (
  (SELECT po.company_id FROM public.purchase_orders po WHERE po.id = purchase_order_id) = public.get_company_id()
);


-- The public.users table needs special handling so users can see other members of their company
DROP POLICY IF EXISTS "Allow all access to own company data" ON public.users;
CREATE POLICY "Allow users to see members of their own company" ON public.users
FOR SELECT
USING (company_id = public.get_company_id());

CREATE POLICY "Allow users to update their own record" ON public.users
FOR UPDATE
USING (id = public.get_user_id());


-- =============================================
-- SECTION 5: VIEWS
-- =============================================

-- A unified view for inventory that joins products and variants.
-- This simplifies many queries in the application.
DROP VIEW IF EXISTS public.product_variants_with_details;
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT 
    v.id,
    v.product_id,
    v.company_id,
    p.title as product_title,
    v.title as variant_title,
    v.sku,
    v.price,
    v.cost,
    v.inventory_quantity,
    p.product_type,
    p.status as product_status,
    p.image_url,
    v.location
FROM public.product_variants v
JOIN public.products p ON v.product_id = p.id;
