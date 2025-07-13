-- InvoChat - Database Schema
-- Version: 2.0
-- Description: This script sets up the full database schema for the application,
-- including tables for products, variants, orders, customers, and more. It is designed
-- to be idempotent, meaning it can be run multiple times without causing errors.

-- =====================================================
-- PRE-CONFIGURATION
-- =====================================================

-- Enable the pgcrypto extension for UUID generation if not already enabled.
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- =====================================================
-- AUTH & USER MANAGEMENT
-- =====================================================

-- 1. Create a table for companies/organizations.
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);

-- 2. Define a custom user role type.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE public.user_role AS ENUM ('Owner', 'Admin', 'Member');
    END IF;
END$$;

-- 3. Create a table to link Supabase auth users to companies.
CREATE TABLE IF NOT EXISTS public.users (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email text,
    role user_role NOT NULL DEFAULT 'Member'::user_role,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now()
);

-- 4. Function to create a new user profile and company on signup.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  company_id uuid;
BEGIN
  -- Create a new company for the new user.
  INSERT INTO public.companies (name)
  VALUES (new.raw_app_meta_data->>'company_name')
  RETURNING id INTO company_id;

  -- Create a new user profile, linking them to the new company as 'Owner'.
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (new.id, company_id, new.email, 'Owner');

  -- Update the user's app_metadata in Supabase auth to include their new company_id and role.
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id, 'role', 'Owner')
  WHERE id = new.id;
  
  RETURN new;
END;
$$;

-- 5. Trigger to execute the function when a new user signs up.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- =====================================================
-- CORE E-COMMERCE TABLES
-- =====================================================

-- Products (Parent Table)
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
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone
);

-- Product Variants
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
    inventory_quantity integer DEFAULT 0,
    external_variant_id text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone
);

-- Customers
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name text,
    email text,
    total_orders integer DEFAULT 0,
    total_spent integer DEFAULT 0,
    first_order_date date,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    external_customer_id text
);

-- Orders
CREATE TABLE IF NOT EXISTS public.orders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number text NOT NULL,
    external_order_id text,
    customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
    financial_status text,
    fulfillment_status text,
    currency text,
    subtotal integer,
    total_tax integer,
    total_shipping integer,
    total_discounts integer,
    total_amount integer NOT NULL,
    source_platform text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone
);

-- Order Line Items
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid REFERENCES public.product_variants(id) ON DELETE SET NULL,
    product_name text,
    variant_title text,
    sku text,
    quantity integer NOT NULL,
    price integer NOT NULL,
    total_discount integer,
    tax_amount integer,
    cost_at_time integer,
    external_line_item_id text
);

-- Refunds
CREATE TABLE IF NOT EXISTS public.refunds (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    refund_number text,
    reason text,
    note text,
    total_amount integer NOT NULL,
    created_by_user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
    external_refund_id text,
    created_at timestamp with time zone DEFAULT now()
);

-- Refund Line Items
CREATE TABLE IF NOT EXISTS public.refund_line_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    refund_id uuid NOT NULL REFERENCES public.refunds(id) ON DELETE CASCADE,
    order_line_item_id uuid NOT NULL REFERENCES public.order_line_items(id) ON DELETE CASCADE,
    quantity integer NOT NULL,
    amount integer NOT NULL,
    restock boolean DEFAULT true
);

-- Customer Addresses
CREATE TABLE IF NOT EXISTS public.customer_addresses (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id uuid NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    address_type text,
    first_name text,
    last_name text,
    company text,
    address1 text,
    address2 text,
    city text,
    province_code text,
    country_code text,
    zip text,
    phone text,
    is_default boolean
);

-- Discounts
CREATE TABLE IF NOT EXISTS public.discounts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    code text NOT NULL,
    type text,
    value integer NOT NULL,
    starts_at timestamp with time zone,
    ends_at timestamp with time zone,
    is_active boolean
);


-- =====================================================
-- APP-SPECIFIC & OPERATIONAL TABLES
-- =====================================================

-- Suppliers
CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);

-- Inventory Adjustments (Audit Log for Stock)
CREATE TABLE IF NOT EXISTS public.inventory_adjustments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    change_type text,
    reason text,
    related_id uuid,
    adjusted_by_user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
    created_at timestamp with time zone DEFAULT now()
);

-- Integrations
CREATE TABLE IF NOT EXISTS public.integrations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform text NOT NULL,
    shop_domain text,
    shop_name text,
    is_active boolean DEFAULT false,
    last_sync_at timestamp with time zone,
    sync_status text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone
);

-- =====================================================
-- INDEXES & CONSTRAINTS
-- =====================================================

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_company_id ON public.product_variants(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_sku ON public.product_variants(sku);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON public.orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON public.order_line_items(variant_id);
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers(company_id);
CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON public.suppliers(company_id);

-- Unique constraints to prevent duplicate data
ALTER TABLE public.product_variants DROP CONSTRAINT IF EXISTS unique_sku_per_company;
ALTER TABLE public.product_variants ADD CONSTRAINT unique_sku_per_company UNIQUE (company_id, sku);

ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS unique_external_order_id_per_company;
ALTER TABLE public.orders ADD CONSTRAINT unique_external_order_id_per_company UNIQUE (company_id, external_order_id);

ALTER TABLE public.refunds DROP CONSTRAINT IF EXISTS unique_external_refund_id_per_company;
ALTER TABLE public.refunds ADD CONSTRAINT unique_external_refund_id_per_company UNIQUE (company_id, external_refund_id);

ALTER TABLE public.discounts DROP CONSTRAINT IF EXISTS unique_discount_code_per_company;
ALTER TABLE public.discounts ADD CONSTRAINT unique_discount_code_per_company UNIQUE (company_id, code);

-- =====================================================
-- TRIGGERS & AUTOMATION
-- =====================================================

-- Trigger to update 'updated_at' timestamps automatically
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ language 'plpgsql';

DROP TRIGGER IF EXISTS trigger_products_updated_at ON public.products;
CREATE TRIGGER trigger_products_updated_at BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS trigger_product_variants_updated_at ON public.product_variants;
CREATE TRIGGER trigger_product_variants_updated_at BEFORE UPDATE ON public.product_variants FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS trigger_orders_updated_at ON public.orders;
CREATE TRIGGER trigger_orders_updated_at BEFORE UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS trigger_integrations_updated_at ON public.integrations;
CREATE TRIGGER trigger_integrations_updated_at BEFORE UPDATE ON public.integrations FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- =====================================================
-- ROW-LEVEL SECURITY (RLS)
-- =====================================================

-- Helper function to get the current user's company_id
CREATE OR REPLACE FUNCTION public.get_current_company_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    (SELECT company_id FROM public.users WHERE id = auth.uid()),
    (SELECT raw_app_meta_data->>'company_id' FROM auth.users WHERE id = auth.uid())::uuid
  )
$$;

-- Function to create RLS policies on a table
CREATE OR REPLACE FUNCTION create_rls_policy(table_name text)
RETURNS void AS $$
BEGIN
  EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', table_name);
  EXECUTE format('DROP POLICY IF EXISTS "Users can only see their own company''s data." ON public.%I;', table_name);
  EXECUTE format('CREATE POLICY "Users can only see their own company''s data." ON public.%I FOR ALL USING (company_id = public.get_current_company_id());', table_name);
END;
$$ LANGUAGE plpgsql;

-- Apply RLS policies to all company-specific tables
SELECT create_rls_policy(table_name)
FROM information_schema.tables
WHERE table_schema = 'public'
AND table_name NOT IN ('users', 'companies') -- 'users' and 'companies' have their own specific access rules
AND table_name IN (
    'products', 'product_variants', 'orders', 'order_line_items',
    'customers', 'customer_addresses', 'refunds', 'refund_line_items',
    'discounts', 'suppliers', 'inventory_adjustments', 'integrations'
);

-- Grant permissions
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO service_role;

-- Log successful completion
RAISE NOTICE 'InvoChat schema setup complete.';
