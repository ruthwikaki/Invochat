-- =================================================================
-- InvoChat - Full Database Schema
--
-- This script is idempotent and can be run safely on a new or
-- existing database. It will drop old objects before creating
-- new ones to ensure a clean state.
-- =================================================================


-- =================================================================
-- 1. EXTENSIONS & SETTINGS
-- =================================================================
-- Enable the pgcrypto extension for gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS "pgcrypto";


-- =================================================================
-- 2. HELPER FUNCTIONS & TYPES
-- =================================================================

-- Function to get the current user's company_id from their auth token
DROP FUNCTION IF EXISTS public.get_current_company_id();
CREATE OR REPLACE FUNCTION public.get_current_company_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT
    CASE
      WHEN auth.jwt()->>'app_metadata' IS NOT NULL THEN
        (auth.jwt()->'app_metadata'->>'company_id')::uuid
      ELSE
        NULL::uuid
    END;
$$;


-- =================================================================
-- 3. CLEANUP: Drop old objects if they exist
-- =================================================================
-- Drop old, simplified tables
DROP TABLE IF EXISTS public.inventory CASCADE;
DROP TABLE IF EXISTS public.sales CASCADE;
DROP TABLE IF EXISTS public.sale_items CASCADE;

-- Drop dependent functions/policies from previous versions if they exist
DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;
DROP POLICY IF EXISTS "Enable read access for all users" ON public.inventory;


-- =================================================================
-- 4. CORE TABLES
-- =================================================================

-- Companies table (one company per user group)
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
-- Enable RLS
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;

-- Products table (parent for variants)
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
    updated_at timestamp with time zone DEFAULT now()
);
-- Enable RLS
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

-- Product Variants table (the actual sellable items)
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
    compare_at_price integer, -- in cents
    cost integer, -- in cents
    inventory_quantity integer DEFAULT 0,
    external_variant_id text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);
-- Enable RLS
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;

-- Customers table
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name text,
    email text,
    total_orders integer DEFAULT 0,
    total_spent integer DEFAULT 0, -- in cents
    first_order_date date,
    created_at timestamp with time zone DEFAULT now(),
    deleted_at timestamp with time zone
);
-- Enable RLS
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;

-- Customer Addresses table
CREATE TABLE IF NOT EXISTS public.customer_addresses (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id uuid NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    address_type text NOT NULL DEFAULT 'shipping', -- billing/shipping
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
    is_default boolean DEFAULT false
);
-- Enable RLS
ALTER TABLE public.customer_addresses ENABLE ROW LEVEL SECURITY;

-- Orders table
CREATE TABLE IF NOT EXISTS public.orders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number text NOT NULL,
    external_order_id text,
    customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
    financial_status text,
    fulfillment_status text,
    currency text,
    subtotal integer NOT NULL DEFAULT 0, -- in cents
    total_tax integer,
    total_shipping integer,
    total_discounts integer,
    total_amount integer NOT NULL,
    source_platform text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);
-- Enable RLS
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

-- Order Line Items table
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id uuid REFERENCES public.product_variants(id) ON DELETE SET NULL,
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
-- Enable RLS
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;

-- Refunds Table
CREATE TABLE IF NOT EXISTS public.refunds (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    refund_number text NOT NULL,
    reason text,
    note text,
    total_amount integer NOT NULL, -- in cents
    created_by_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    external_refund_id text,
    created_at timestamp with time zone DEFAULT now()
);
-- Enable RLS
ALTER TABLE public.refunds ENABLE ROW LEVEL SECURITY;

-- Refund Line Items Table
CREATE TABLE IF NOT EXISTS public.refund_line_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    refund_id uuid NOT NULL REFERENCES public.refunds(id) ON DELETE CASCADE,
    order_line_item_id uuid NOT NULL REFERENCES public.order_line_items(id) ON DELETE CASCADE,
    quantity integer NOT NULL,
    restock boolean DEFAULT true
);
-- Enable RLS
ALTER TABLE public.refund_line_items ENABLE ROW LEVEL SECURITY;


-- Discounts Table
CREATE TABLE IF NOT EXISTS public.discounts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    code text NOT NULL,
    type text NOT NULL, -- percentage/fixed_amount/free_shipping
    value numeric(10,2) NOT NULL,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now()
);
-- Enable RLS
ALTER TABLE public.discounts ENABLE ROW LEVEL SECURITY;


-- =================================================================
-- 5. INDEXES & CONSTRAINTS
-- =================================================================

-- Drop constraints if they exist before creating
ALTER TABLE IF EXISTS public.products DROP CONSTRAINT IF EXISTS unique_external_product_id_per_company;
ALTER TABLE public.products ADD CONSTRAINT unique_external_product_id_per_company UNIQUE (company_id, external_product_id);

ALTER TABLE IF EXISTS public.product_variants DROP CONSTRAINT IF EXISTS unique_sku_per_company;
ALTER TABLE public.product_variants ADD CONSTRAINT unique_sku_per_company UNIQUE (company_id, sku);

ALTER TABLE IF EXISTS public.orders DROP CONSTRAINT IF EXISTS unique_external_order_id_per_company;
ALTER TABLE public.orders ADD CONSTRAINT unique_external_order_id_per_company UNIQUE (company_id, external_order_id);

ALTER TABLE IF EXISTS public.discounts DROP CONSTRAINT IF EXISTS unique_discount_code_per_company;
ALTER TABLE public.discounts ADD CONSTRAINT unique_discount_code_per_company UNIQUE (company_id, code);

-- Create Indexes
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_company_id ON public.product_variants(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_sku ON public.product_variants(sku);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON public.orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON public.order_line_items(variant_id);
CREATE INDEX IF NOT EXISTS idx_customer_addresses_customer_id ON public.customer_addresses(customer_id);
CREATE INDEX IF NOT EXISTS idx_refunds_company_id ON public.refunds(company_id);
CREATE INDEX IF NOT EXISTS idx_refunds_order_id ON public.refunds(order_id);
CREATE INDEX IF NOT EXISTS idx_discounts_company_id ON public.discounts(company_id);


-- =================================================================
-- 6. TRIGGERS & AUTOMATION
-- =================================================================

-- Create a function to update the updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Add update triggers for tables with updated_at columns
DROP TRIGGER IF EXISTS update_products_updated_at ON public.products;
CREATE TRIGGER update_products_updated_at BEFORE UPDATE ON public.products
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_product_variants_updated_at ON public.product_variants;
CREATE TRIGGER update_product_variants_updated_at BEFORE UPDATE ON public.product_variants
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_orders_updated_at ON public.orders;
CREATE TRIGGER update_orders_updated_at BEFORE UPDATE ON public.orders
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();


-- Trigger function to handle new user sign-ups
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_company_id uuid;
  user_email text;
  company_name text;
BEGIN
  -- Create a new company for the new user
  company_name := COALESCE(new.raw_app_meta_data->>'company_name', new.email);
  INSERT INTO public.companies (name)
  VALUES (company_name)
  RETURNING id INTO new_company_id;

  -- Update the user's app_metadata with the new company_id
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'role', 'Owner')
  WHERE id = new.id;
  
  -- Create default settings for the new company
  INSERT INTO public.company_settings(company_id)
  VALUES(new_company_id);

  RETURN new;
END;
$$;

-- Create the trigger on the auth.users table
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- =================================================================
-- 7. ROW-LEVEL SECURITY (RLS)
-- =================================================================

-- Create a generic policy creation function to avoid repetition
CREATE OR REPLACE FUNCTION create_rls_policy(table_name TEXT)
RETURNS void AS $$
BEGIN
  EXECUTE format('DROP POLICY IF EXISTS "Users can only see their own company''s data." ON public.%I', table_name);
  EXECUTE format(
    'CREATE POLICY "Users can only see their own company''s data." ' ||
    'ON public.%I FOR ALL ' ||
    'USING (company_id = public.get_current_company_id());',
    table_name
  );
END;
$$ LANGUAGE plpgsql;

-- Apply the policy to all relevant tables
SELECT create_rls_policy(table_name)
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN (
    'products', 'product_variants', 'orders', 'order_line_items', 'customers', 'customer_addresses',
    'refunds', 'refund_line_items', 'discounts'
  );

-- Special policy for the companies table itself
DROP POLICY IF EXISTS "Users can only see their own company." ON public.companies;
CREATE POLICY "Users can only see their own company." ON public.companies
FOR ALL USING (id = public.get_current_company_id());


-- =================================================================
-- 8. GRANT PERMISSIONS
-- =================================================================

-- Grant permissions to authenticated users for the public schema
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO authenticated;

-- Grant permissions to the service_role for all operations
GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO service_role;

-- Grant access to the auth schema for our security definer functions
GRANT USAGE ON SCHEMA auth TO postgres, service_role;

-- Note: Supabase handles permissions for its own internal schemas (auth, storage, etc.)
