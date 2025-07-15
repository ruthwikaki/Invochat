-- InvoChat Database Schema Setup
-- Version: 1.5.0
-- Description: This script sets up the entire database, including tables,
-- functions, RLS policies, and initial data structures. It is designed to be
-- idempotent and can be run safely on an existing database to apply updates.

-- === I. EXTENSIONS & SETTINGS ===
-- Enable the UUID extension for generating unique identifiers.
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
-- Enable the pgroonga extension if available (for full-text search).
-- CREATE EXTENSION IF NOT EXISTS "pgroonga";


-- === II. DROP DEPENDENT OBJECTS (in reverse order of creation) ===
-- This section is crucial for idempotency. We drop objects that depend on tables
-- or functions we need to alter.

-- Drop Materialized Views first as they depend on the underlying tables.
DROP MATERIALIZED VIEW IF EXISTS public.company_dashboard_metrics;

-- Drop Policies before altering tables they depend on.
DO $$ BEGIN DROP POLICY "Allow company members to read" ON public.products; EXCEPTION WHEN undefined_object THEN null; END $$;
DO $$ BEGIN DROP POLICY "Allow company members to read" ON public.product_variants; EXCEPTION WHEN undefined_object THEN null; END $$;
DO $$ BEGIN DROP POLICY "Allow company members to read" ON public.orders; EXCEPTION WHEN undefined_object THEN null; END $$;
DO $$ BEGIN DROP POLICY "Allow company members to read" ON public.order_line_items; EXCEPTION WHEN undefined_object THEN null; END $$;
DO $$ BEGIN DROP POLICY "Allow company members to manage" ON public.customers; EXCEPTION WHEN undefined_object THEN null; END $$;
DO $$ BEGIN DROP POLICY "Allow company members to read" ON public.refunds; EXCEPTION WHEN undefined_object THEN null; END $$;
DO $$ BEGIN DROP POLICY "Allow company members to manage" ON public.suppliers; EXCEPTION WHEN undefined_object THEN null; END $$;
DO $$ BEGIN DROP POLICY "Allow company members to manage" ON public.purchase_orders; EXCEPTION WHEN undefined_object THEN null; END $$;
DO $$ BEGIN DROP POLICY "Allow company members to read" ON public.inventory_ledger; EXCEPTION WHEN undefined_object THEN null; END $$;
DO $$ BEGIN DROP POLICY "Allow company members to manage" ON public.integrations; EXCEPTION WHEN undefined_object THEN null; END $$;
DO $$ BEGIN DROP POLICY "Allow company members to manage" ON public.company_settings; EXCEPTION WHEN undefined_object THEN null; END $$;
DO $$ BEGIN DROP POLICY "Allow admins to read audit logs for their company" ON public.audit_log; EXCEPTION WHEN undefined_object THEN null; END $$;
DO $$ BEGIN DROP POLICY "Allow user to manage messages in their conversations" ON public.messages; EXCEPTION WHEN undefined_object THEN null; END $$;

-- Drop the old, insecure function.
DROP FUNCTION IF EXISTS public.get_my_company_id();
DROP FUNCTION IF EXISTS public.get_my_user_role();

-- Drop views that depend on table structures.
DROP VIEW IF EXISTS public.product_variants_with_details;


-- === III. TABLE CREATION & ALTERATIONS ===
-- Create core tables if they don't exist.

CREATE TABLE IF NOT EXISTS public.companies (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.users (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email text,
    role text DEFAULT 'member',
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now()
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
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
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
    price integer,
    compare_at_price integer,
    cost integer,
    inventory_quantity integer NOT NULL DEFAULT 0,
    location text,
    external_variant_id text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.orders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number text NOT NULL,
    external_order_id text,
    customer_id uuid,
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
    updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid REFERENCES public.products(id) ON DELETE SET NULL,
    variant_id uuid REFERENCES public.product_variants(id) ON DELETE SET NULL,
    product_name text NOT NULL,
    variant_title text,
    sku text,
    quantity integer NOT NULL,
    price integer NOT NULL,
    total_discount integer DEFAULT 0,
    tax_amount integer DEFAULT 0,
    cost_at_time integer,
    fulfillment_status text DEFAULT 'unfulfilled',
    requires_shipping boolean DEFAULT true,
    external_line_item_id text
);

CREATE TABLE IF NOT EXISTS public.customers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name text NOT NULL,
    email text,
    total_orders integer DEFAULT 0,
    total_spent integer DEFAULT 0,
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now()
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
    supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL,
    status text NOT NULL DEFAULT 'Draft',
    po_number text NOT NULL,
    total_cost integer NOT NULL,
    expected_arrival_date date,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    purchase_order_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE RESTRICT,
    quantity integer NOT NULL,
    cost integer NOT NULL
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
    updated_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    fast_moving_days integer NOT NULL DEFAULT 30,
    overstock_multiplier integer NOT NULL DEFAULT 3,
    high_value_threshold integer NOT NULL DEFAULT 1000,
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

CREATE TABLE IF NOT EXISTS public.audit_log (
    id bigserial PRIMARY KEY,
    company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    action text NOT NULL,
    details jsonb,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
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
    role text NOT NULL,
    content text,
    component text,
    component_props jsonb,
    visualization jsonb,
    confidence numeric,
    assumptions text[],
    is_error boolean default false,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.webhook_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  integration_id UUID NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
  webhook_id TEXT NOT NULL,
  processed_at TIMESTAMPTZ DEFAULT now(),
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Add idempotency key to purchase orders
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='purchase_orders' AND column_name='idempotency_key') THEN
    ALTER TABLE public.purchase_orders ADD COLUMN idempotency_key uuid;
  END IF;
END;
$$;

-- Fix financial data types (numeric -> integer for cents)
ALTER TABLE public.customers ALTER COLUMN total_spent TYPE integer;
ALTER TABLE public.refunds ALTER COLUMN total_amount TYPE integer;

-- Add FTS column to products table
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='products' AND column_name='fts_document') THEN
    ALTER TABLE public.products ADD COLUMN fts_document tsvector;
  END IF;
END;
$$;

-- Ensure SKU and title are not nullable on product_variants
ALTER TABLE public.product_variants ALTER COLUMN sku SET NOT NULL;
ALTER TABLE public.product_variants ALTER COLUMN title SET NOT NULL;


-- === IV. INDEXES ===
-- Create indexes for performance. Use IF NOT EXISTS to prevent errors on re-runs.

-- Indexes for foreign keys
CREATE INDEX IF NOT EXISTS idx_users_company_id ON public.users(company_id);
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_variants_company_id ON public.product_variants(company_id);
CREATE INDEX IF NOT EXISTS idx_variants_sku ON public.product_variants(sku);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON public.orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_line_items_variant_id ON public.order_line_items(variant_id);
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers(company_id);
CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON public.suppliers(company_id);
CREATE INDEX IF NOT EXISTS idx_po_company_id ON public.purchase_orders(company_id);
CREATE INDEX IF NOT EXISTS idx_po_supplier_id ON public.purchase_orders(supplier_id);
CREATE INDEX IF NOT EXISTS idx_po_line_items_po_id ON public.purchase_order_line_items(purchase_order_id);
CREATE INDEX IF NOT EXISTS idx_po_line_items_variant_id ON public.purchase_order_line_items(variant_id);
CREATE INDEX IF NOT EXISTS idx_ledger_variant_id ON public.inventory_ledger(variant_id);
CREATE INDEX IF NOT EXISTS idx_integrations_company_id ON public.integrations(company_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_company_user ON public.audit_log(company_id, user_id);
CREATE INDEX IF NOT EXISTS idx_conversations_user_id ON public.conversations(user_id);
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id ON public.messages(conversation_id);

-- Unique constraint for idempotency on purchase orders
CREATE UNIQUE INDEX IF NOT EXISTS po_company_idempotency_idx ON public.purchase_orders (company_id, idempotency_key) WHERE idempotency_key IS NOT NULL;

-- Unique constraint for webhook events to prevent replay attacks
CREATE UNIQUE INDEX IF NOT EXISTS webhook_events_integration_id_webhook_id_key ON public.webhook_events (integration_id, webhook_id);

-- Full-text search index
CREATE INDEX IF NOT EXISTS products_fts_document_idx ON public.products USING GIN (fts_document);


-- === V. FUNCTIONS & TRIGGERS ===
-- Core business logic and automation.

-- Function to securely get the company_id of the currently authenticated user
CREATE OR REPLACE FUNCTION public.get_my_company_id()
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid;
$$;

-- Function to get the role of the currently authenticated user
CREATE OR REPLACE FUNCTION public.get_my_user_role()
RETURNS text
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'user_role', '');
$$;

-- Trigger function to create a company and link the user upon sign-up
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_company_id uuid;
  v_company_name text := new.raw_app_meta_data ->> 'company_name';
BEGIN
  -- Create a new company for the user
  INSERT INTO public.companies (name)
  VALUES (v_company_name)
  RETURNING id INTO v_company_id;

  -- Insert a corresponding entry in the public.users table
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (new.id, v_company_id, new.email, 'Owner');

  -- Update the user's app_metadata with the new company_id and role
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', v_company_id, 'user_role', 'Owner')
  WHERE id = new.id;

  RETURN new;
END;
$$;

-- Trigger to execute the function after a new user is created
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- Trigger function to update the fts_document column on product changes
CREATE OR REPLACE FUNCTION public.update_fts_document()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.fts_document := to_tsvector('english', coalesce(NEW.title, '') || ' ' || coalesce(NEW.product_type, '') || ' ' || coalesce(array_to_string(NEW.tags, ' '), ''));
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_update_fts_document ON public.products;
CREATE TRIGGER trg_update_fts_document
BEFORE INSERT OR UPDATE ON public.products
FOR EACH ROW
EXECUTE FUNCTION public.update_fts_document();


-- === VI. ROW-LEVEL SECURITY (RLS) ===
-- Enforce data isolation between companies.

-- Enable RLS on all relevant tables
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refunds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;


-- Define Policies
CREATE POLICY "Allow company members to read" ON public.products FOR SELECT USING (company_id = public.get_my_company_id());
CREATE POLICY "Allow company members to read" ON public.product_variants FOR SELECT USING (company_id = public.get_my_company_id());
CREATE POLICY "Allow company members to read" ON public.orders FOR SELECT USING (company_id = public.get_my_company_id());
CREATE POLICY "Allow company members to read" ON public.order_line_items FOR SELECT USING (company_id = public.get_my_company_id());
CREATE POLICY "Allow company members to manage" ON public.customers FOR ALL USING (company_id = public.get_my_company_id());
CREATE POLICY "Allow company members to read" ON public.refunds FOR SELECT USING (company_id = public.get_my_company_id());
CREATE POLICY "Allow company members to manage" ON public.suppliers FOR ALL USING (company_id = public.get_my_company_id());
CREATE POLICY "Allow company members to manage" ON public.purchase_orders FOR ALL USING (company_id = public.get_my_company_id());
CREATE POLICY "Allow company members to read" ON public.inventory_ledger FOR SELECT USING (company_id = public.get_my_company_id());
CREATE POLICY "Allow company members to manage" ON public.integrations FOR ALL USING (company_id = public.get_my_company_id());
CREATE POLICY "Allow company members to manage" ON public.company_settings FOR ALL USING (company_id = public.get_my_company_id());
CREATE POLICY "Allow admins to read audit logs for their company" ON public.audit_log FOR SELECT USING (company_id = public.get_my_company_id() AND public.get_my_user_role() IN ('Owner', 'Admin'));
CREATE POLICY "Allow user to manage their conversations" ON public.conversations FOR ALL USING (user_id = auth.uid());
CREATE POLICY "Allow user to manage messages in their conversations" ON public.messages FOR ALL USING (company_id = public.get_my_company_id() AND conversation_id IN (SELECT id FROM public.conversations WHERE user_id = auth.uid()));


-- === VII. VIEWS & MATERIALIZED VIEWS ===

-- Recreate the view for product variants with details
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.id,
    pv.product_id,
    pv.company_id,
    pv.sku,
    pv.title,
    pv.inventory_quantity,
    pv.price,
    pv.cost,
    pv.location,
    p.title as product_title,
    p.status as product_status,
    p.product_type,
    p.image_url
FROM
    public.product_variants pv
JOIN
    public.products p ON pv.product_id = p.id;

-- Recreate Materialized View for Dashboard Metrics
CREATE MATERIALIZED VIEW IF NOT EXISTS public.company_dashboard_metrics AS
SELECT
    c.id AS company_id,
    CURRENT_DATE AS calculation_date,
    SUM(oli.price * oli.quantity) AS total_revenue,
    COUNT(DISTINCT o.id) AS total_orders,
    COUNT(DISTINCT o.customer_id) AS total_customers
FROM
    public.companies c
LEFT JOIN
    public.orders o ON c.id = o.company_id
LEFT JOIN
    public.order_line_items oli ON o.id = oli.order_id
GROUP BY
    c.id;

CREATE UNIQUE INDEX IF NOT EXISTS idx_company_dashboard_metrics_company_date ON public.company_dashboard_metrics(company_id, calculation_date);

-- Function to refresh the materialized view
CREATE OR REPLACE FUNCTION public.refresh_dashboard_metrics()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    REFRESH MATERIALIZED VIEW public.company_dashboard_metrics;
    RETURN NULL;
END;
$$;

-- Trigger to refresh the view on new orders
DROP TRIGGER IF EXISTS on_new_order_refresh_metrics ON public.orders;
CREATE TRIGGER on_new_order_refresh_metrics
AFTER INSERT ON public.orders
FOR EACH STATEMENT
EXECUTE FUNCTION public.refresh_dashboard_metrics();

-- Initial data population for the materialized view
REFRESH MATERIALIZED VIEW public.company_dashboard_metrics;

-- Final success message
SELECT 'Database schema setup complete.' as status;
