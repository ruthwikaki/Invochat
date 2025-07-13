-- =====================================================
-- ADVANCED SCHEMA FOR E-COMMERCE ANALYTICS
-- Version: 4
-- =====================================================

-- =====================================================
-- 1. SETUP: FUNCTIONS & EXTENSIONS
-- =====================================================

-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Enable modern crypto functions
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Function to get the current user's company_id from their JWT claims
CREATE OR REPLACE FUNCTION public.get_current_company_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT (auth.jwt()->>'app_metadata')::jsonb->>'company_id'::text
$$;

-- Function to automatically update 'updated_at' columns
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- =====================================================
-- 2. CLEANUP: DROP OLD OBJECTS
-- =====================================================
-- Drop the old user creation function and its trigger if they exist
DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;
-- Drop old tables if they exist to prevent conflicts
DROP TABLE IF EXISTS public.inventory_ledger;
DROP TABLE IF EXISTS public.sale_items;
DROP TABLE IF EXISTS public.sales;
-- Rename inventory to products to better reflect its new role as a parent table
ALTER TABLE IF EXISTS public.inventory RENAME TO products;


-- =====================================================
-- 3. CORE TABLES: DEFINE THE MAIN DATA STRUCTURE
-- =====================================================

-- Companies Table: The root of the multi-tenant structure
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);

-- Users Table: Stores app-specific user data and links to a company
CREATE TABLE IF NOT EXISTS public.users (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email text,
    role text NOT NULL DEFAULT 'Member', -- e.g., 'Owner', 'Admin', 'Member'
    created_at timestamp with time zone DEFAULT now()
);

-- Customers Table: Stores customer data from e-commerce platforms
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name text,
    email text,
    total_orders integer DEFAULT 0,
    total_spent numeric(10,2) DEFAULT 0,
    first_order_date date,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now()
);

-- Products Table: The parent for all product variants
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
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

-- Product Variants Table
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
    inventory_quantity integer NOT NULL DEFAULT 0,
    external_variant_id text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;

-- Orders Table
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
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone
);
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

-- Order Line Items Table
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
    total_discount integer, -- in cents
    tax_amount integer, -- in cents
    cost_at_time integer, -- in cents
    external_line_item_id text
);
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;

-- Customer Addresses Table
CREATE TABLE IF NOT EXISTS public.customer_addresses (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id uuid NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    address_type text DEFAULT 'shipping',
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
ALTER TABLE public.customer_addresses ENABLE ROW LEVEL SECURITY;

-- Refunds Table
CREATE TABLE IF NOT EXISTS public.refunds (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    refund_number text,
    reason text,
    note text,
    total_amount integer, -- in cents
    external_refund_id text,
    created_at timestamp with time zone DEFAULT now()
);
ALTER TABLE public.refunds ENABLE ROW LEVEL SECURITY;

-- Refund Line Items Table
CREATE TABLE IF NOT EXISTS public.refund_line_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    refund_id uuid NOT NULL REFERENCES public.refunds(id) ON DELETE CASCADE,
    order_line_item_id uuid NOT NULL REFERENCES public.order_line_items(id) ON DELETE CASCADE,
    quantity integer NOT NULL,
    amount integer, -- in cents
    restock boolean DEFAULT true
);
ALTER TABLE public.refund_line_items ENABLE ROW LEVEL SECURITY;


-- Discounts Table
CREATE TABLE IF NOT EXISTS public.discounts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    code text NOT NULL,
    type text NOT NULL,
    value numeric(10,2) NOT NULL,
    minimum_purchase numeric(10,2),
    usage_limit integer,
    usage_count integer DEFAULT 0,
    applies_to text DEFAULT 'all',
    starts_at timestamp with time zone,
    ends_at timestamp with time zone,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now()
);
ALTER TABLE public.discounts ENABLE ROW LEVEL SECURITY;


-- =====================================================
-- 4. CONSTRAINTS & INDEXES
-- =====================================================

-- Drop constraints before creating them to ensure the script is re-runnable
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS unique_order_number_per_company;
ALTER TABLE public.refunds DROP CONSTRAINT IF EXISTS unique_refund_number_per_company;
ALTER TABLE public.discounts DROP CONSTRAINT IF EXISTS unique_discount_code_per_company;
ALTER TABLE public.product_variants DROP CONSTRAINT IF EXISTS unique_sku_per_company;
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS unique_handle_per_company;

-- Add unique constraints
ALTER TABLE public.orders ADD CONSTRAINT unique_order_number_per_company UNIQUE (company_id, order_number);
ALTER TABLE public.refunds ADD CONSTRAINT unique_refund_number_per_company UNIQUE (company_id, refund_number);
ALTER TABLE public.discounts ADD CONSTRAINT unique_discount_code_per_company UNIQUE (company_id, code);
ALTER TABLE public.product_variants ADD CONSTRAINT unique_sku_per_company UNIQUE (company_id, sku);
ALTER TABLE public.products ADD CONSTRAINT unique_handle_per_company UNIQUE (company_id, handle);


-- Create indexes for foreign keys and frequently queried columns
CREATE INDEX IF NOT EXISTS idx_users_company_id ON public.users(company_id);
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_company_id ON public.product_variants(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_sku ON public.product_variants(sku);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON public.orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON public.orders(created_at);
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON public.order_line_items(variant_id);
CREATE INDEX IF NOT EXISTS idx_customer_addresses_customer_id ON public.customer_addresses(customer_id);
CREATE INDEX IF NOT EXISTS idx_refunds_company_id ON public.refunds(company_id);
CREATE INDEX IF NOT EXISTS idx_refunds_order_id ON public.refunds(order_id);
CREATE INDEX IF NOT EXISTS idx_refund_line_items_refund_id ON public.refund_line_items(refund_id);
CREATE INDEX IF NOT EXISTS idx_discounts_company_id ON public.discounts(company_id);


-- =====================================================
-- 5. ROW-LEVEL SECURITY (RLS)
-- =====================================================

-- Function to apply RLS policy to a table
CREATE OR REPLACE FUNCTION create_rls_policy(table_name_param text)
RETURNS void AS $$
BEGIN
    EXECUTE format('
        DROP POLICY IF EXISTS "Users can only see their own company''s data." ON public.%I;
        CREATE POLICY "Users can only see their own company''s data."
        ON public.%I FOR ALL
        USING (company_id = public.get_current_company_id());
    ', table_name_param, table_name_param);
END;
$$ LANGUAGE plpgsql;

-- Apply RLS to all company-specific tables
SELECT create_rls_policy(table_name)
FROM information_schema.tables
WHERE table_schema = 'public' AND table_name IN (
    'products', 'product_variants', 'orders', 'order_line_items',
    'customers', 'customer_addresses', 'refunds', 'discounts'
);

-- Policies for tables without a direct company_id but linked through another table
DROP POLICY IF EXISTS "Users can see refund line items for their company" ON public.refund_line_items;
CREATE POLICY "Users can see refund line items for their company"
ON public.refund_line_items FOR ALL
USING (
    EXISTS (
        SELECT 1 FROM public.refunds
        WHERE refunds.id = refund_line_items.refund_id
        AND refunds.company_id = public.get_current_company_id()
    )
);
ALTER TABLE public.refund_line_items ENABLE ROW LEVEL SECURITY;


-- =====================================================
-- 6. TRIGGERS
-- =====================================================

-- Auto-handle new user creation
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  new_company_id uuid;
BEGIN
  -- Create a new company for the user
  INSERT INTO public.companies (name)
  VALUES (new.raw_user_meta_data->>'company_name')
  RETURNING id INTO new_company_id;

  -- Create a corresponding user entry
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (new.id, new_company_id, new.email, 'Owner');
  
  -- Update the user's claims in auth.users
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'role', 'Owner')
  WHERE id = new.id;
  
  RETURN new;
END;
$$;

-- Drop and recreate the trigger to ensure it's up-to-date
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();


-- Drop and recreate updated_at triggers
DROP TRIGGER IF EXISTS update_products_updated_at ON public.products;
CREATE TRIGGER update_products_updated_at BEFORE UPDATE ON public.products
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_product_variants_updated_at ON public.product_variants;
CREATE TRIGGER update_product_variants_updated_at BEFORE UPDATE ON public.product_variants
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_orders_updated_at ON public.orders;
CREATE TRIGGER update_orders_updated_at BEFORE UPDATE ON public.orders
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();


-- =====================================================
-- 7. GRANT PERMISSIONS
-- =====================================================

-- Grant all permissions to the authenticated role on our public tables
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO authenticated;

-- Grant usage to the anon role, so they can sign up
GRANT USAGE ON SCHEMA public TO anon;
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO anon;
