
-- ### InvoChat Database Schema ###
-- This script is designed to be idempotent and can be run multiple times safely.

-- === Extensions ===
-- Enable necessary extensions if they don't exist.
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- === Drop existing objects (in reverse order of creation) ===
-- Drop dependent views first.
DROP VIEW IF EXISTS public.product_variants_with_details;
DROP VIEW IF EXISTS public.sales_with_profit;
DROP VIEW IF EXISTS public.inventory_value_by_product;

-- Safely drop policies on tables if they exist.
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to read" ON public.products; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to manage" ON public.products; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to read variants" ON public.product_variants; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to manage variants" ON public.product_variants; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to read settings" ON public.company_settings; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to manage settings" ON public.company_settings; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to manage suppliers" ON public.suppliers; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to manage orders" ON public.orders; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to manage purchase orders" ON public.purchase_orders; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to manage customers" ON public.customers; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to manage integrations" ON public.integrations; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to read their conversations" ON public.conversations; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to manage their messages" ON public.messages; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to manage audit logs" ON public.audit_log; EXCEPTION WHEN undefined_object THEN END; $$;

-- Drop functions
DROP FUNCTION IF EXISTS public.get_company_id();
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.create_new_company_for_user();
DROP FUNCTION IF EXISTS public.record_sale_transaction(uuid,uuid,text,text,text,text,jsonb,text);
DROP FUNCTION IF EXISTS public.get_dashboard_metrics(uuid,integer);
DROP FUNCTION IF EXISTS public.get_reorder_suggestions(uuid);
DROP FUNCTION IF EXISTS public.get_dead_stock_report(uuid);
DROP FUNCTION IF EXISTS public.get_supplier_performance_report(uuid);
DROP FUNCTION IF EXISTS public.detect_anomalies(uuid);
DROP FUNCTION IF EXISTS public.get_alerts(uuid);
DROP FUNCTION IF EXISTS public.record_order_from_platform(uuid,jsonb,text);
DROP FUNCTION IF EXISTS public.get_inventory_analytics(uuid);
DROP FUNCTION IF EXISTS public.get_sales_analytics(uuid);
DROP FUNCTION IF EXISTS public.get_customer_analytics(uuid);
DROP FUNCTION IF EXISTS public.reconcile_inventory_from_integration(uuid,uuid,uuid);
DROP FUNCTION IF EXISTS public.create_purchase_orders_from_suggestions(uuid,uuid,jsonb,uuid);
DROP FUNCTION IF EXISTS public.get_historical_sales_for_sku(uuid,text);


-- Drop tables if they exist
DROP TABLE IF EXISTS public.purchase_order_line_items;
DROP TABLE IF EXISTS public.purchase_orders;
DROP TABLE IF EXISTS public.order_line_items;
DROP TABLE IF EXISTS public.orders;
DROP TABLE IF EXISTS public.inventory_ledger;
DROP TABLE IF EXISTS public.product_variants;
DROP TABLE IF EXISTS public.products;
DROP TABLE IF EXISTS public.customers;
DROP TABLE IF EXISTS public.suppliers;
DROP TABLE IF EXISTS public.integrations;
DROP TABLE IF EXISTS public.company_settings;
DROP TABLE IF EXISTS public.users;
DROP TABLE IF EXISTS public.companies;
DROP TABLE IF EXISTS public.messages;
DROP TABLE IF EXISTS public.conversations;
DROP TABLE IF EXISTS public.audit_log;
DROP TABLE IF EXISTS public.webhook_events;
DROP TABLE IF EXISTS public.channel_fees;


-- === Create Tables ===

CREATE TABLE public.companies (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.users (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email text,
    role text DEFAULT 'Member'::text,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    fast_moving_days integer NOT NULL DEFAULT 30,
    overstock_multiplier integer NOT NULL DEFAULT 3,
    high_value_threshold integer NOT NULL DEFAULT 1000, -- in cents
    predictive_stock_days integer NOT NULL DEFAULT 7,
    promo_sales_lift_multiplier real NOT NULL DEFAULT 2.5,
    currency text DEFAULT 'USD'::text,
    timezone text DEFAULT 'UTC'::text,
    tax_rate numeric DEFAULT 0,
    custom_rules jsonb,
    subscription_status text DEFAULT 'trial'::text,
    subscription_plan text DEFAULT 'starter'::text,
    subscription_expires_at timestamptz,
    stripe_customer_id text,
    stripe_subscription_id text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);

CREATE TABLE public.products (
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
    updated_at timestamptz,
    fts_document tsvector GENERATED ALWAYS AS (to_tsvector('english', title || ' ' || COALESCE(description, ''))) STORED,
    UNIQUE(company_id, external_product_id)
);
CREATE INDEX products_fts_document_idx ON public.products USING GIN (fts_document);
CREATE INDEX products_company_id_idx ON public.products (company_id);

CREATE TABLE public.product_variants (
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
    compare_at_price integer,
    cost integer,
    inventory_quantity integer NOT NULL DEFAULT 0,
    location text,
    external_variant_id text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    UNIQUE(company_id, sku)
);
CREATE INDEX product_variants_product_id_idx ON public.product_variants (product_id);
CREATE INDEX product_variants_company_id_sku_idx ON public.product_variants (company_id, sku);

CREATE TABLE public.inventory_ledger (
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
CREATE INDEX inventory_ledger_variant_id_idx ON public.inventory_ledger (variant_id);

CREATE TABLE public.suppliers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.customers (
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

CREATE TABLE public.orders (
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

CREATE TABLE public.order_line_items (
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
    total_discount integer DEFAULT 0,
    tax_amount integer DEFAULT 0,
    cost_at_time integer, -- in cents
    fulfillment_status text DEFAULT 'unfulfilled',
    requires_shipping boolean DEFAULT true,
    external_line_item_id text
);

CREATE TABLE public.purchase_orders (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.suppliers(id),
    status text NOT NULL DEFAULT 'Draft',
    po_number text NOT NULL,
    total_cost integer NOT NULL,
    expected_arrival_date date,
    idempotency_key uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(company_id, po_number),
    UNIQUE(idempotency_key)
);

CREATE TABLE public.purchase_order_line_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    purchase_order_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id),
    quantity integer NOT NULL,
    cost integer NOT NULL -- in cents
);

CREATE TABLE public.integrations (
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

CREATE TABLE public.conversations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL REFERENCES auth.users(id),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    title text NOT NULL,
    created_at timestamptz DEFAULT now(),
    last_accessed_at timestamptz DEFAULT now(),
    is_starred boolean DEFAULT false
);

CREATE TABLE public.messages (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id),
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

CREATE TABLE public.audit_log (
    id bigserial PRIMARY KEY,
    company_id uuid REFERENCES public.companies(id),
    user_id uuid REFERENCES auth.users(id),
    action text NOT NULL,
    details jsonb,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE public.webhook_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id text NOT NULL,
    processed_at timestamptz DEFAULT now(),
    created_at timestamptz DEFAULT now(),
    UNIQUE (integration_id, webhook_id)
);

CREATE TABLE public.channel_fees (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    channel_name text NOT NULL,
    percentage_fee numeric NOT NULL,
    fixed_fee numeric NOT NULL,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, channel_name)
);

-- === Views ===
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.*,
    p.title as product_title,
    p.status as product_status,
    p.image_url
FROM
    public.product_variants pv
JOIN
    public.products p ON pv.product_id = p.id;

CREATE OR REPLACE VIEW public.sales_with_profit AS
SELECT
    oli.id as line_item_id,
    o.id as order_id,
    o.company_id,
    o.order_number,
    o.created_at as sale_date,
    p.id as product_id,
    p.title as product_name,
    v.id as variant_id,
    v.sku,
    v.title as variant_title,
    oli.quantity,
    oli.price as sale_price_per_unit,
    (oli.price * oli.quantity) as total_revenue,
    COALESCE(oli.cost_at_time, v.cost, 0) as cost_per_unit,
    (COALESCE(oli.cost_at_time, v.cost, 0) * oli.quantity) as total_cogs,
    ((oli.price * oli.quantity) - (COALESCE(oli.cost_at_time, v.cost, 0) * oli.quantity)) as total_profit
FROM public.order_line_items oli
JOIN public.orders o ON oli.order_id = o.id
LEFT JOIN public.product_variants v ON oli.variant_id = v.id
LEFT JOIN public.products p ON v.product_id = p.id;

-- === Functions ===
CREATE OR REPLACE FUNCTION public.get_company_id()
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
AS $$
    SELECT nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid;
$$;

CREATE OR REPLACE FUNCTION public.create_new_company_for_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  new_company_id uuid;
  user_email text;
  company_name text;
BEGIN
  -- 1. Create a new company
  company_name := NEW.raw_user_meta_data->>'company_name';
  user_email := NEW.email;
  
  IF company_name IS NULL OR company_name = '' THEN
    company_name := user_email;
  END IF;

  INSERT INTO public.companies (name)
  VALUES (company_name)
  RETURNING id INTO new_company_id;

  -- 2. Update the user's app_metadata with the new company_id and role
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'role', 'Owner')
  WHERE id = NEW.id;

  -- 3. Create a corresponding entry in public.users
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (NEW.id, new_company_id, user_email, 'Owner');
  
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_historical_sales_for_sku(p_company_id uuid, p_sku text)
RETURNS TABLE(sale_date date, total_quantity bigint)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        o.created_at::date as sale_date,
        SUM(oli.quantity) as total_quantity
    FROM public.order_line_items oli
    JOIN public.orders o ON oli.order_id = o.id
    WHERE
        oli.company_id = p_company_id
        AND oli.sku = p_sku
    GROUP BY o.created_at::date
    ORDER BY sale_date ASC;
END;
$$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.create_new_company_for_user();

-- === Row-Level Security (RLS) ===
-- Enable RLS for all relevant tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;

-- Define policies
CREATE POLICY "Allow company members to read" ON public.products FOR SELECT USING (company_id = public.get_company_id());
CREATE POLICY "Allow company members to manage" ON public.products FOR ALL USING (company_id = public.get_company_id());

CREATE POLICY "Allow company members to read variants" ON public.product_variants FOR SELECT USING (company_id = public.get_company_id());
CREATE POLICY "Allow company members to manage variants" ON public.product_variants FOR ALL USING (company_id = public.get_company_id());

CREATE POLICY "Allow company members to read settings" ON public.company_settings FOR SELECT USING (company_id = public.get_company_id());
CREATE POLICY "Allow company members to manage settings" ON public.company_settings FOR ALL USING (company_id = public.get_company_id());

CREATE POLICY "Allow company members to manage suppliers" ON public.suppliers FOR ALL USING (company_id = public.get_company_id());
CREATE POLICY "Allow company members to manage customers" ON public.customers FOR ALL USING (company_id = public.get_company_id());
CREATE POLICY "Allow company members to manage orders" ON public.orders FOR ALL USING (company_id = public.get_company_id());
CREATE POLICY "Allow company members to manage order line items" ON public.order_line_items FOR ALL USING (company_id = public.get_company_id());
CREATE POLICY "Allow company members to manage purchase orders" ON public.purchase_orders FOR ALL USING (company_id = public.get_company_id());
CREATE POLICY "Allow company members to manage PO line items" ON public.purchase_order_line_items FOR ALL USING (
    purchase_order_id IN (SELECT id FROM public.purchase_orders WHERE company_id = public.get_company_id())
);
CREATE POLICY "Allow company members to manage integrations" ON public.integrations FOR ALL USING (company_id = public.get_company_id());
CREATE POLICY "Allow company members to manage ledger" ON public.inventory_ledger FOR ALL USING (company_id = public.get_company_id());

CREATE POLICY "Allow company members to read their conversations" ON public.conversations FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "Allow user to manage their own messages" ON public.messages FOR ALL USING (
    conversation_id IN (SELECT id FROM public.conversations WHERE user_id = auth.uid())
);
CREATE POLICY "Allow company members to read audit log" ON public.audit_log FOR SELECT USING (company_id = public.get_company_id());
CREATE POLICY "Allow company members to read webhook events" ON public.webhook_events FOR SELECT USING (
    integration_id IN (SELECT id FROM public.integrations WHERE company_id = public.get_company_id())
);

-- Grant usage on schema to authenticated users
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;

GRANT USAGE ON SCHEMA public TO service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO service_role;


    