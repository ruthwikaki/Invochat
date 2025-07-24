
-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create custom types if they don't exist
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


-- #################################################################
-- ### Tables
-- #################################################################

-- Companies Table
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Users Table (public schema)
CREATE TABLE IF NOT EXISTS public.users (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email text,
    role text DEFAULT 'member'::text,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now()
);

-- Suppliers Table
CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Products Table
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
    fts_document tsvector,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    deleted_at timestamptz
);
CREATE INDEX IF NOT EXISTS products_company_id_idx ON public.products(company_id);
CREATE UNIQUE INDEX IF NOT EXISTS products_external_id_company_id_unique ON public.products(external_product_id, company_id);

-- Product Variants Table
CREATE TABLE IF NOT EXISTS public.product_variants (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid null,
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
    inventory_quantity integer NOT NULL DEFAULT 0 CHECK (inventory_quantity >= 0),
    location text,
    external_variant_id text,
    version integer NOT NULL DEFAULT 1,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    deleted_at timestamptz,
    CONSTRAINT product_variants_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS variants_product_id_idx ON public.product_variants(product_id);
CREATE UNIQUE INDEX IF NOT EXISTS variants_sku_company_id_unique ON public.product_variants(sku, company_id);
CREATE UNIQUE INDEX IF NOT EXISTS variants_ext_id_company_id_unique ON public.product_variants(external_variant_id, company_id);

-- Customers Table
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name text NOT NULL,
    email text,
    total_orders integer DEFAULT 0,
    total_spent integer DEFAULT 0,
    first_order_date date,
    created_at timestamptz DEFAULT now(),
    deleted_at timestamptz
);

-- Orders Table
CREATE TABLE IF NOT EXISTS public.orders (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number text NOT NULL,
    external_order_id text,
    customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
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

-- Order Line Items Table
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE RESTRICT,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_name text NOT NULL,
    variant_title text,
    sku text NOT NULL,
    quantity integer NOT NULL,
    price integer NOT NULL,
    total_discount integer DEFAULT 0,
    tax_amount integer DEFAULT 0,
    cost_at_time integer,
    external_line_item_id text
);

-- Purchase Orders Table
CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL,
    status text NOT NULL DEFAULT 'Draft',
    po_number text NOT NULL,
    total_cost integer NOT NULL,
    expected_arrival_date date,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    idempotency_key uuid
);
CREATE UNIQUE INDEX IF NOT EXISTS po_number_company_id_unique ON public.purchase_orders(po_number, company_id);

-- Purchase Order Line Items Table
CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    purchase_order_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    quantity integer NOT NULL,
    cost integer NOT NULL
);

-- Integrations Table
CREATE TABLE IF NOT EXISTS public.integrations (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
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
CREATE UNIQUE INDEX IF NOT EXISTS integrations_platform_company_id_unique ON public.integrations(platform, company_id);

-- Webhook Events Table
CREATE TABLE IF NOT EXISTS public.webhook_events (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id text NOT NULL,
    created_at timestamptz DEFAULT now(),
    processed_at timestamptz DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS webhook_events_unique_id ON public.webhook_events(integration_id, webhook_id);

-- Inventory Ledger Table
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS inventory_ledger_variant_id_idx ON public.inventory_ledger(variant_id);

-- Conversations Table
CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    created_at timestamptz DEFAULT now(),
    last_accessed_at timestamptz DEFAULT now(),
    is_starred boolean DEFAULT false
);

-- Messages Table
CREATE TABLE IF NOT EXISTS public.messages (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role text NOT NULL,
    content text,
    component text,
    component_props jsonb,
    visualization jsonb,
    confidence numeric,
    assumptions text[],
    is_error boolean DEFAULT false,
    created_at timestamptz DEFAULT now()
);

-- Company Settings Table
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
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);

-- Audit Log Table
CREATE TABLE IF NOT EXISTS public.audit_log (
  id bigserial PRIMARY KEY,
  company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE,
  user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  action text NOT NULL,
  details jsonb,
  created_at timestamptz DEFAULT now()
);

-- #################################################################
-- ### Row-Level Security (RLS)
-- #################################################################

-- Drop existing policies first to ensure idempotency, in correct dependency order
DROP POLICY IF EXISTS "User can access their own company data" ON public.products;
DROP POLICY IF EXISTS "User can access their own company data" ON public.product_variants;
DROP POLICY IF EXISTS "User can access their own company data" ON public.orders;
DROP POLICY IF EXISTS "User can access their own company data" ON public.order_line_items;
DROP POLICY IF EXISTS "User can access their own company data" ON public.customers;
DROP POLICY IF EXISTS "User can access their own company data" ON public.suppliers;
DROP POLICY IF EXISTS "User can access their own company data" ON public.purchase_orders;
DROP POLICY IF EXISTS "User can access their own company data" ON public.purchase_order_line_items;
DROP POLICY IF EXISTS "User can access their own company data" ON public.integrations;
DROP POLICY IF EXISTS "User can access their own company data" ON public.webhook_events;
DROP POLICY IF EXISTS "User can access their own company data" ON public.inventory_ledger;
DROP POLICY IF EXISTS "User can access their own company data" ON public.conversations;
DROP POLICY IF EXISTS "User can access their own company data" ON public.messages;
DROP POLICY IF EXISTS "User can access their own company data" ON public.audit_log;
DROP POLICY IF EXISTS "User can access their own company settings" ON public.company_settings;
DROP POLICY IF EXISTS "User can see other users in their company" ON public.users;

-- #################################################################
-- ### Functions & Triggers
-- #################################################################

-- Drop the trigger first to avoid dependency errors
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Drop functions in reverse order of dependency
DROP FUNCTION IF EXISTS public.check_user_permission(p_user_id uuid, p_required_role text);
DROP FUNCTION IF EXISTS public.lock_user_account(p_user_id uuid, p_lockout_duration text);
DROP FUNCTION IF EXISTS public.get_company_id_for_user(p_user_id uuid);
DROP FUNCTION IF EXISTS public.handle_new_user();


-- Function to get company ID for a user
CREATE OR REPLACE FUNCTION public.get_company_id_for_user(p_user_id uuid)
RETURNS uuid AS $$
BEGIN
  RETURN (
    SELECT company_id
    FROM public.users
    WHERE id = p_user_id
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Function to create a new company for a new user and link them.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  -- Create a new company for the new user, using the company_name from metadata
  INSERT INTO public.companies (name)
  VALUES (new.raw_user_meta_data->>'company_name');

  -- Add the new user to the public users table, linking them to the newly created company
  INSERT INTO public.users (id, company_id, email, role)
  SELECT new.id, c.id, new.email, 'Owner'
  FROM public.companies c
  WHERE c.name = new.raw_user_meta_data->>'company_name'
  ORDER BY c.created_at DESC
  LIMIT 1;
  
  -- Update the user's app_metadata with the company_id for easy access in RLS policies
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', (
      SELECT company_id
      FROM public.users
      WHERE id = new.id
  ))
  WHERE id = new.id;
  
  RETURN new;
END;
$$;

-- Trigger to call the function when a new user signs up.
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();


-- Function to check user permissions
CREATE OR REPLACE FUNCTION public.check_user_permission(p_user_id uuid, p_required_role text)
RETURNS boolean AS $$
DECLARE
    user_role text;
BEGIN
    SELECT role INTO user_role FROM public.users WHERE id = p_user_id;

    IF user_role IS NULL THEN
        RETURN FALSE;
    END IF;

    IF p_required_role = 'Owner' AND user_role = 'Owner' THEN
        RETURN TRUE;
    ELSIF p_required_role = 'Admin' AND (user_role = 'Owner' OR user_role = 'Admin') THEN
        RETURN TRUE;
    END IF;

    RETURN FALSE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Function to lock a user account
CREATE OR REPLACE FUNCTION public.lock_user_account(p_user_id uuid, p_lockout_duration text)
RETURNS void AS $$
BEGIN
  UPDATE auth.users
  SET banned_until = now() + p_lockout_duration::interval
  WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- #################################################################
-- ### Recreate RLS Policies
-- #################################################################

-- Enable RLS on all relevant tables
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "User can access their own company data" ON public.products FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "User can access their own company data" ON public.product_variants FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "User can access their own company data" ON public.orders FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "User can access their own company data" ON public.order_line_items FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "User can access their own company data" ON public.customers FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "User can access their own company data" ON public.suppliers FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "User can access their own company data" ON public.purchase_orders FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "User can access their own company data" ON public.purchase_order_line_items FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "User can access their own company data" ON public.integrations FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "User can access their own company data" ON public.webhook_events FOR ALL USING (integration_id IN (SELECT id FROM public.integrations WHERE company_id = public.get_company_id_for_user(auth.uid())));
CREATE POLICY "User can access their own company data" ON public.inventory_ledger FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "User can access their own company data" ON public.conversations FOR ALL USING (user_id = auth.uid());
CREATE POLICY "User can access their own company data" ON public.messages FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "User can access their own company data" ON public.audit_log FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "User can access their own company settings" ON public.company_settings FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "User can see other users in their company" ON public.users FOR SELECT USING (company_id = public.get_company_id_for_user(auth.uid()));
