-- =================================================================
-- DATABASE SETUP SCRIPT FOR InvoChat (SaaS Version)
--
-- This script is designed to be IDEMPOTENT, meaning it can be
-- run multiple times without causing errors. It will reset the
-- public schema to the correct state for the application.
--
-- THIS SCRIPT WILL DELETE EXISTING DATA in the application tables.
-- Run this only on a development database or after backing up data.
-- =================================================================

-- =================================================================
-- 1. CLEANUP & RESET
-- Drop existing objects in reverse order of dependency.
-- =================================================================

-- Remove RLS policies from all tables in the public schema
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public') LOOP
        EXECUTE 'ALTER TABLE public.' || quote_ident(r.tablename) || ' DISABLE ROW LEVEL SECURITY';
    END LOOP;
END $$;
DROP POLICY IF EXISTS "Users can only see their own company's data." ON public.audit_log;
DROP POLICY IF EXISTS "Users can only see their own company's data." ON public.companies;
-- ... and so on for all tables that will have RLS

-- Drop functions
DROP FUNCTION IF EXISTS public.handle_new_user CASCADE;
DROP FUNCTION IF EXISTS public.get_current_company_id CASCADE;
DROP FUNCTION IF EXISTS public.create_rls_policy CASCADE;
DROP FUNCTION IF EXISTS public.update_updated_at_column CASCADE;
DROP FUNCTION IF EXISTS public.get_sales_analytics CASCADE;
DROP FUNCTION IF EXISTS public.get_customer_analytics CASCADE;
DROP FUNCTION IF EXISTS public.record_order_from_platform CASCADE;

-- Drop tables
DROP TABLE IF EXISTS public.refund_line_items CASCADE;
DROP TABLE IF EXISTS public.refunds CASCADE;
DROP TABLE IF EXISTS public.order_line_items CASCADE;
DROP TABLE IF EXISTS public.orders CASCADE;
DROP TABLE IF EXISTS public.discounts CASCADE;
DROP TABLE IF EXISTS public.customer_addresses CASCADE;
DROP TABLE IF EXISTS public.customers CASCADE;
DROP TABLE IF EXISTS public.product_variants CASCADE;
DROP TABLE IF EXISTS public.products CASCADE; -- Replaces 'inventory'
DROP TABLE IF EXISTS public.inventory CASCADE; -- Old table
DROP TABLE IF EXISTS public.sales CASCADE; -- Old table
DROP TABLE IF EXISTS public.sale_items CASCADE; -- Old table
DROP TABLE IF EXISTS public.suppliers CASCADE;
DROP TABLE IF EXISTS public.integrations CASCADE;
DROP TABLE IF EXISTS public.sync_logs CASCADE;
DROP TABLE IF EXISTS public.sync_state CASCADE;
DROP TABLE IF EXISTS public.channel_fees CASCADE;
DROP TABLE IF EXISTS public.company_settings CASCADE;
DROP TABLE IF EXISTS public.messages CASCADE;
DROP TABLE IF EXISTS public.conversations CASCADE;
DROP TABLE IF EXISTS public.export_jobs CASCADE;
DROP TABLE IF EXISTS public.audit_log CASCADE;
DROP TABLE IF EXISTS public.users CASCADE;
DROP TABLE IF EXISTS public.companies CASCADE;

-- Drop custom types
DROP TYPE IF EXISTS public.user_role;

-- =================================================================
-- 2. CREATE CORE TABLES
-- =================================================================

-- User role type
CREATE TYPE public.user_role AS ENUM ('Owner', 'Admin', 'Member');

-- Companies table
CREATE TABLE public.companies (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Users table (stores app-specific user data)
CREATE TABLE public.users (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email text,
    role user_role NOT NULL DEFAULT 'Member'
);

-- Products table (parent for variants)
CREATE TABLE public.products (
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
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

-- Product Variants table (the actual sellable items/SKUs)
CREATE TABLE public.product_variants (
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
    price integer, -- Price in cents
    compare_at_price integer, -- In cents
    cost integer, -- Cost in cents
    inventory_quantity integer DEFAULT 0,
    external_variant_id text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

-- Customers table
CREATE TABLE public.customers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name text,
    email text,
    total_orders integer DEFAULT 0,
    total_spent integer DEFAULT 0, -- In cents
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now()
);

-- Orders table
CREATE TABLE public.orders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number text NOT NULL,
    external_order_id text,
    customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
    financial_status text,
    fulfillment_status text,
    currency text,
    subtotal integer NOT NULL, -- In cents
    total_tax integer,
    total_shipping integer,
    total_discounts integer,
    total_amount integer NOT NULL,
    source_platform text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

-- Order Line Items table
CREATE TABLE public.order_line_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id uuid REFERENCES public.product_variants(id) ON DELETE SET NULL,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_name text,
    variant_title text,
    sku text,
    quantity integer NOT NULL,
    price integer NOT NULL, -- In cents
    total_discount integer,
    tax_amount integer,
    cost_at_time integer, -- In cents
    external_line_item_id text
);

-- Suppliers table
CREATE TABLE public.suppliers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Company Settings table
CREATE TABLE public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    fast_moving_days integer NOT NULL DEFAULT 30,
    timezone text DEFAULT 'UTC',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);

-- Integrations table
CREATE TABLE public.integrations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform text NOT NULL,
    shop_domain text,
    shop_name text,
    is_active boolean DEFAULT false,
    sync_status text,
    last_sync_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);

-- Webhook event log for replay protection
CREATE TABLE public.webhook_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    platform text NOT NULL,
    webhook_id text NOT NULL,
    received_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(integration_id, webhook_id)
);


-- =================================================================
-- 3. INDEXES & CONSTRAINTS
-- =================================================================

-- Add unique constraints
ALTER TABLE public.users ADD CONSTRAINT unique_user_per_company UNIQUE (id, company_id);
ALTER TABLE public.products ADD CONSTRAINT unique_external_product_id_per_company UNIQUE (company_id, external_product_id);
ALTER TABLE public.product_variants ADD CONSTRAINT unique_sku_per_company UNIQUE (company_id, sku);
ALTER TABLE public.orders ADD CONSTRAINT unique_order_number_per_company UNIQUE (company_id, order_number);

-- Add indexes
CREATE INDEX idx_products_company_id ON public.products(company_id);
CREATE INDEX idx_product_variants_product_id ON public.product_variants(product_id);
CREATE INDEX idx_product_variants_company_id_sku ON public.product_variants(company_id, sku);
CREATE INDEX idx_orders_company_id ON public.orders(company_id);
CREATE INDEX idx_order_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX idx_order_line_items_variant_id ON public.order_line_items(variant_id);
CREATE INDEX idx_customers_company_id ON public.customers(company_id);
CREATE INDEX idx_suppliers_company_id ON public.suppliers(company_id);


-- =================================================================
-- 4. FUNCTIONS & TRIGGERS
-- =================================================================

-- Function to update 'updated_at' columns
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Attach update trigger to relevant tables
CREATE TRIGGER update_products_updated_at BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_product_variants_updated_at BEFORE UPDATE ON public.product_variants FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_orders_updated_at BEFORE UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_company_settings_updated_at BEFORE UPDATE ON public.company_settings FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_integrations_updated_at BEFORE UPDATE ON public.integrations FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Function to create a company for a new user
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  new_company_id uuid;
BEGIN
  -- Create a new company for the user
  INSERT INTO public.companies (name)
  VALUES (new.raw_app_meta_data->>'company_name')
  RETURNING id INTO new_company_id;

  -- Create a corresponding user entry in our public users table
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (new.id, new_company_id, new.email, 'Owner');

  -- Create default settings for the new company
  INSERT INTO public.company_settings (company_id)
  VALUES (new_company_id);

  -- Update the user's app_metadata with the new company_id
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id)
  WHERE id = new.id;

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to call handle_new_user on new user signup
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();


-- =================================================================
-- 5. ROW-LEVEL SECURITY (RLS)
-- =================================================================

-- Function to get the current user's company_id
CREATE OR REPLACE FUNCTION public.get_current_company_id()
RETURNS uuid AS $$
DECLARE
    company_id_val uuid;
BEGIN
    -- Using coalesce to handle potential nulls gracefully, though auth.uid() should exist for authenticated users.
    SELECT COALESCE(
        (SELECT raw_app_meta_data->>'company_id' FROM auth.users WHERE id = auth.uid()),
        (SELECT raw_user_meta_data->>'company_id' FROM auth.users WHERE id = auth.uid())
    )::uuid INTO company_id_val;
    RETURN company_id_val;
EXCEPTION
    WHEN OTHERS THEN
        RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to dynamically create RLS policies
CREATE OR REPLACE FUNCTION public.create_rls_policy(table_name_param text)
RETURNS void AS $$
BEGIN
    EXECUTE format(
        'CREATE POLICY "Users can only see their own company''s data." ' ||
        'ON public.%I FOR ALL ' ||
        'USING (company_id = public.get_current_company_id());',
        table_name_param
    );
END;
$$ LANGUAGE plpgsql;

-- Apply RLS to all relevant tables
SELECT public.create_rls_policy('companies');
SELECT public.create_rls_policy('products');
SELECT public.create_rls_policy('product_variants');
SELECT public.create_rls_policy('customers');
SELECT public.create_rls_policy('orders');
SELECT public.create_rls_policy('order_line_items');
SELECT public.create_rls_policy('suppliers');
SELECT public.create_rls_policy('company_settings');
SELECT public.create_rls_policy('integrations');
-- Add other tables as needed

-- Enable RLS on all relevant tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;

-- Grant usage on schema and select on tables to authenticated role
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT INSERT ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT UPDATE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public to authenticated;

-- Grant execute on functions to authenticated role
GRANT EXECUTE ON FUNCTION public.get_current_company_id() TO authenticated;

-- Grant permissions for service_role for server-side operations
GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO service_role;

-- Grant permissions for anon role on specific functions if needed for signup
GRANT EXECUTE ON FUNCTION public.handle_new_user() TO anon;

