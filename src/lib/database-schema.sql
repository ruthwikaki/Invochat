-- InvoChat SaaS Database Schema
-- Version: 2.0.0
-- Description: This script sets up the full, production-ready schema for a multi-tenant SaaS application.
-- It is designed to be idempotent and can be run safely multiple times.

-- =================================================================
-- 0. PRE-FLIGHT CHECKS & EXTENSIONS
-- =================================================================
-- Enable the pgcrypto extension for gen_random_uuid() if not already enabled.
CREATE EXTENSION IF NOT EXISTS pgcrypto;


-- =================================================================
-- 1. CLEANUP OLD STRUCTURES (IDEMPOTENT)
-- =================================================================
-- Safely drop old functions and their dependent triggers
DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;

-- Safely drop old, simplistic tables if they exist
DROP TABLE IF EXISTS public.inventory CASCADE;
DROP TABLE IF EXISTS public.sales CASCADE;
DROP TABLE IF EXISTS public.sale_items CASCADE;


-- =================================================================
-- 2. CORE TABLES (Companies, Users, Settings)
-- =================================================================
-- Create a table for Companies
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.companies IS 'Stores information about each tenant company.';

-- Create a table for Users, linking them to a company
-- This table is managed by Supabase Auth but we define it for clarity and relationships.
-- We will add a foreign key to companies.
CREATE TABLE IF NOT EXISTS public.users (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email text,
    role text NOT NULL DEFAULT 'Member', -- e.g., 'Owner', 'Admin', 'Member'
    created_at timestamp with time zone DEFAULT now(),
    deleted_at timestamp with time zone
);
COMMENT ON TABLE public.users IS 'Holds application-specific user data and links to a company.';

-- Create a table for company-specific settings
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    fast_moving_days integer NOT NULL DEFAULT 30,
    overstock_multiplier numeric NOT NULL DEFAULT 3.0,
    high_value_threshold numeric NOT NULL DEFAULT 1000.00,
    promo_sales_lift_multiplier real NOT NULL DEFAULT 2.5,
    timezone text DEFAULT 'UTC',
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone
);
COMMENT ON TABLE public.company_settings IS 'Tenant-specific business rules and settings.';


-- =================================================================
-- 3. AUTH & NEW USER TRIGGERS
-- =================================================================
-- Function to handle new user sign-ups and link them to a company
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  new_company_id uuid;
  user_company_name text;
BEGIN
  -- Extract company name from metadata, falling back to a default if not present
  user_company_name := new.raw_user_meta_data->>'company_name';
  IF user_company_name IS NULL OR user_company_name = '' THEN
    user_company_name := new.email || '''s Company';
  END IF;

  -- Create a new company for the new user
  INSERT INTO public.companies (name)
  VALUES (user_company_name)
  RETURNING id INTO new_company_id;

  -- Insert a row into public.users
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (new.id, new_company_id, new.email, 'Owner');

  -- Insert a settings row for the new company
  INSERT INTO public.company_settings (company_id)
  VALUES (new_company_id);
  
  -- Update the user's app_metadata with the new company_id
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'role', 'Owner')
  WHERE id = new.id;
  
  RETURN new;
END;
$$;

-- Drop the trigger if it exists before creating it
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Create the trigger to fire after a new user is inserted into auth.users
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- =================================================================
-- 4. PRODUCT & INVENTORY TABLES
-- =================================================================
-- This is the parent "Product" concept
CREATE TABLE IF NOT EXISTS public.products (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    description text,
    handle text,
    product_type text,
    tags text[],
    status text, -- e.g., active, archived, draft
    image_url text,
    external_product_id text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);
COMMENT ON TABLE public.products IS 'Parent table for product concepts, containing shared details.';

-- This is the sellable/stockable "Variant"
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
    price integer, -- In cents
    compare_at_price integer, -- In cents
    cost integer, -- In cents
    inventory_quantity integer DEFAULT 0,
    external_variant_id text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);
COMMENT ON TABLE public.product_variants IS 'Specific, stockable versions of a product.';


-- =================================================================
-- 5. CUSTOMER & ORDER TABLES
-- =================================================================
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name text,
    email text,
    phone text,
    external_customer_id text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);
COMMENT ON TABLE public.customers IS 'Stores customer information.';

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

CREATE TABLE IF NOT EXISTS public.orders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number text NOT NULL,
    external_order_id text,
    customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
    financial_status text DEFAULT 'pending', -- pending/paid/refunded
    fulfillment_status text DEFAULT 'unfulfilled', -- unfulfilled/partial/fulfilled
    currency text DEFAULT 'USD',
    subtotal integer NOT NULL DEFAULT 0, -- In cents
    total_tax integer DEFAULT 0,
    total_shipping integer DEFAULT 0,
    total_discounts integer DEFAULT 0,
    total_amount integer NOT NULL,
    source_platform text, -- shopify/woocommerce
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid REFERENCES public.product_variants(id) ON DELETE SET NULL,
    product_name text,
    variant_title text,
    sku text,
    quantity integer NOT NULL,
    price integer NOT NULL, -- Price per unit, in cents
    total_discount integer DEFAULT 0,
    tax_amount integer DEFAULT 0,
    cost_at_time integer, -- Cost per unit at time of sale, in cents
    external_line_item_id text
);

CREATE TABLE IF NOT EXISTS public.discounts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    code text NOT NULL,
    type text NOT NULL, -- percentage/fixed_amount
    value numeric NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


-- =================================================================
-- 6. INDEXES FOR PERFORMANCE
-- =================================================================
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_company_id ON public.product_variants(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_sku ON public.product_variants(sku);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON public.orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON public.order_line_items(variant_id);
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers(company_id);
CREATE INDEX IF NOT EXISTS idx_customer_addresses_customer_id ON public.customer_addresses(customer_id);


-- =================================================================
-- 7. HELPER FUNCTIONS & TRIGGERS
-- =================================================================
-- Function to get the company_id of the currently authenticated user
CREATE OR REPLACE FUNCTION public.get_current_company_id()
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER SET search_path = public
AS $$
  SELECT CASE
    WHEN (auth.jwt()->>'app_metadata')::jsonb ? 'company_id'
    THEN ((auth.jwt()->>'app_metadata')::jsonb->>'company_id')::uuid
    ELSE NULL
  END;
$$;


-- Auto-update `updated_at` columns
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Drop triggers if they exist to ensure idempotency
DROP TRIGGER IF EXISTS update_products_updated_at ON public.products;
DROP TRIGGER IF EXISTS update_product_variants_updated_at ON public.product_variants;
DROP TRIGGER IF EXISTS update_orders_updated_at ON public.orders;

CREATE TRIGGER update_products_updated_at BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_product_variants_updated_at BEFORE UPDATE ON public.product_variants FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_orders_updated_at BEFORE UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


-- =================================================================
-- 8. ROW LEVEL SECURITY (RLS)
-- =================================================================
-- Enable RLS for all tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_addresses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.discounts ENABLE ROW LEVEL SECURITY;
-- Add any new tables here in the future
-- ALTER TABLE public.refunds ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE public.refund_line_items ENABLE ROW LEVEL SECURITY;

-- Drop existing policies before creating them to ensure idempotency
DROP POLICY IF EXISTS "Users can only see their own company's data." ON public.companies;
DROP POLICY IF EXISTS "Users can only see their own company's data." ON public.users;
DROP POLICY IF EXISTS "Users can only see their own company's data." ON public.company_settings;
DROP POLICY IF EXISTS "Users can only see their own company's data." ON public.products;
DROP POLICY IF EXISTS "Users can only see their own company's data." ON public.product_variants;
DROP POLICY IF EXISTS "Users can only see their own company's data." ON public.customers;
DROP POLICY IF EXISTS "Users can only see their own company's data." ON public.customer_addresses;
DROP POLICY IF EXISTS "Users can only see their own company's data." ON public.orders;
DROP POLICY IF EXISTS "Users can only see their own company's data." ON public.order_line_items;
DROP POLICY IF EXISTS "Users can only see their own company's data." ON public.discounts;

-- Generic policy creation function
CREATE OR REPLACE FUNCTION create_rls_policy(table_name TEXT)
RETURNS void AS $$
BEGIN
    EXECUTE format(
        'CREATE POLICY "Users can only see their own company''s data." ' ||
        'ON public.%I FOR ALL ' ||
        'USING (company_id = public.get_current_company_id());',
        table_name
    );
END;
$$ LANGUAGE plpgsql;

-- Apply policies to all tables with a company_id
SELECT create_rls_policy(table_name)
FROM information_schema.tables
WHERE table_schema = 'public'
AND table_name IN (
    'companies', 'users', 'company_settings', 'products', 'product_variants', 
    'customers', 'customer_addresses', 'orders', 'order_line_items', 'discounts'
);

-- =================================================================
-- 9. UNIQUE CONSTRAINTS
-- =================================================================
-- Drop existing constraints before adding them
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS unique_external_product_id_per_company;
ALTER TABLE public.product_variants DROP CONSTRAINT IF EXISTS unique_sku_per_company;
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS unique_order_number_per_company;
ALTER TABLE public.discounts DROP CONSTRAINT IF EXISTS unique_discount_code_per_company;

ALTER TABLE public.products ADD CONSTRAINT unique_external_product_id_per_company UNIQUE (company_id, external_product_id);
ALTER TABLE public.product_variants ADD CONSTRAINT unique_sku_per_company UNIQUE (company_id, sku);
ALTER TABLE public.orders ADD CONSTRAINT unique_order_number_per_company UNIQUE (company_id, order_number);
ALTER TABLE public.discounts ADD CONSTRAINT unique_discount_code_per_company UNIQUE (company_id, code);

-- =================================================================
-- 10. GRANT PERMISSIONS
-- =================================================================
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO service_role;
