-- InvoChat SaaS Database Schema
-- Version: 2.0.0
-- Description: This script sets up the necessary tables, functions, and security policies
--              for a multi-tenant inventory management system. It's designed to be idempotent.

--
-- === EXTENSIONS ===
--
-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

--
-- === HELPER FUNCTIONS ===
--

-- Function to get the current user's company_id from their JWT claims.
-- Uses a CASE statement to ensure a UUID is always returned or NULL, preventing type mismatches.
DROP FUNCTION IF EXISTS get_current_company_id() CASCADE;
CREATE OR REPLACE FUNCTION get_current_company_id()
RETURNS uuid AS $$
BEGIN
  RETURN (
    CASE
      WHEN auth.jwt()->>'company_id' IS NOT NULL THEN (auth.jwt()->>'company_id')::uuid
      ELSE NULL
    END
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Function to automatically set the `updated_at` timestamp on a table.
DROP FUNCTION IF EXISTS set_updated_at() CASCADE;
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;


--
-- === AUTHENTICATION & MULTI-TENANCY SETUP ===
--

-- Trigger function to handle new user sign-ups.
-- It creates a new company and associates the user with it.
DROP FUNCTION IF EXISTS handle_new_user() CASCADE;
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  new_company_id uuid;
  user_company_name text := NEW.raw_user_meta_data->>'company_name';
BEGIN
  -- Create a new company for the user
  INSERT INTO public.companies (name)
  VALUES (user_company_name)
  RETURNING id INTO new_company_id;

  -- Update the user's app_metadata with the new company_id
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id)
  WHERE id = NEW.id;

  -- Create default settings for the new company
  INSERT INTO public.company_settings (company_id)
  VALUES (new_company_id);
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Trigger that executes the handle_new_user function after a new user is created in auth.users.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


--
-- === TABLE & INDEX CLEANUP (IDEMPOTENCY) ===
--
-- Drop tables in reverse order of dependency to avoid foreign key constraint errors.
DROP TABLE IF EXISTS "public"."refund_line_items" CASCADE;
DROP TABLE IF EXISTS "public"."refunds" CASCADE;
DROP TABLE IF EXISTS "public"."order_line_items" CASCADE;
DROP TABLE IF EXISTS "public"."customer_addresses" CASCADE;
DROP TABLE IF EXISTS "public"."orders" CASCADE;
DROP TABLE IF EXISTS "public"."customers" CASCADE;
DROP TABLE IF EXISTS "public"."product_variants" CASCADE;
DROP TABLE IF EXISTS "public"."products" CASCADE;
DROP TABLE IF EXISTS "public"."suppliers" CASCADE;
DROP TABLE IF EXISTS "public"."discounts" CASCADE;
DROP TABLE IF EXISTS "public"."integrations" CASCADE;
DROP TABLE IF EXISTS "public"."company_settings" CASCADE;
DROP TABLE IF EXISTS "public"."companies" CASCADE;

-- Drop old, simplified tables if they exist
DROP TABLE IF EXISTS "public"."inventory" CASCADE;
DROP TABLE IF EXISTS "public"."sales" CASCADE;
DROP TABLE IF EXISTS "public"."sale_items" CASCADE;


--
-- === TABLE CREATION ===
--

-- Companies table
CREATE TABLE public.companies (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.companies IS 'Represents a single business or tenant in the system.';

-- Company Settings table
CREATE TABLE public.company_settings (
  company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
  dead_stock_days integer NOT NULL DEFAULT 90,
  fast_moving_days integer NOT NULL DEFAULT 30,
  overstock_multiplier numeric NOT NULL DEFAULT 3.0,
  high_value_threshold numeric NOT NULL DEFAULT 1000.00,
  predictive_stock_days integer NOT NULL DEFAULT 7,
  promo_sales_lift_multiplier real NOT NULL DEFAULT 2.5,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz
);
COMMENT ON TABLE public.company_settings IS 'Stores business rule configurations for each company.';

-- Products table (parent for variants)
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
  CONSTRAINT unique_external_product_per_company UNIQUE (company_id, external_product_id)
);
COMMENT ON TABLE public.products IS 'Stores parent product information, grouping variants.';

-- Product Variants table (the actual inventory items)
CREATE TABLE public.product_variants (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
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
  compare_at_price integer,
  cost integer, -- in cents
  inventory_quantity integer NOT NULL DEFAULT 0,
  external_variant_id text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz,
  CONSTRAINT unique_sku_per_company UNIQUE (company_id, sku),
  CONSTRAINT unique_external_variant_per_company UNIQUE (company_id, external_variant_id)
);
COMMENT ON TABLE public.product_variants IS 'Represents a specific, stock-tracked version of a product.';

-- Customers table
CREATE TABLE public.customers (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  customer_name text,
  email text,
  total_orders integer NOT NULL DEFAULT 0,
  total_spent integer NOT NULL DEFAULT 0, -- in cents
  first_order_date date,
  created_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.customers IS 'Stores customer information.';

-- Orders table
CREATE TABLE public.orders (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  order_number text NOT NULL,
  external_order_id text,
  customer_id uuid REFERENCES public.customers(id),
  financial_status text,
  fulfillment_status text,
  currency text,
  subtotal integer NOT NULL,
  total_tax integer,
  total_shipping integer,
  total_discounts integer,
  total_amount integer NOT NULL,
  source_platform text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz,
  CONSTRAINT unique_external_order_per_company UNIQUE (company_id, external_order_id)
);
COMMENT ON TABLE public.orders IS 'Represents sales orders.';

-- Order Line Items table
CREATE TABLE public.order_line_items (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  variant_id uuid REFERENCES public.product_variants(id),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
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
COMMENT ON TABLE public.order_line_items IS 'Represents individual items within an order.';

-- Customer Addresses table
CREATE TABLE public.customer_addresses (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  customer_id uuid NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  address_type text NOT NULL CHECK (address_type IN ('shipping', 'billing')),
  first_name text,
  last_name text,
  company text,
  address1 text,
  address2 text,
  city text,
  province_code text,
  country_code text,
  zip text,
  phone text
);
COMMENT ON TABLE public.customer_addresses IS 'Stores shipping and billing addresses for customers.';

-- Refunds table
CREATE TABLE public.refunds (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  refund_number text NOT NULL,
  status text NOT NULL DEFAULT 'pending',
  reason text,
  note text,
  total_amount integer NOT NULL,
  external_refund_id text,
  created_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.refunds IS 'Stores information about refunds issued.';

-- Refund Line Items table
CREATE TABLE public.refund_line_items (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  refund_id uuid NOT NULL REFERENCES public.refunds(id) ON DELETE CASCADE,
  order_line_item_id uuid NOT NULL REFERENCES public.order_line_items(id),
  quantity integer NOT NULL,
  amount integer NOT NULL,
  restock boolean DEFAULT true
);
COMMENT ON TABLE public.refund_line_items IS 'Represents individual items within a refund.';

-- Discounts table
CREATE TABLE public.discounts (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  code text NOT NULL,
  type text NOT NULL,
  value numeric NOT NULL,
  usage_limit integer,
  usage_count integer DEFAULT 0,
  starts_at timestamptz,
  ends_at timestamptz,
  is_active boolean DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.discounts IS 'Stores discount codes and promotions.';

-- Suppliers table
CREATE TABLE public.suppliers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    default_lead_time_days INT,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT unique_supplier_name_per_company UNIQUE (company_id, name)
);
COMMENT ON TABLE public.suppliers IS 'Stores vendor information.';

-- Integrations table
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
  updated_at timestamptz,
  CONSTRAINT unique_platform_per_company UNIQUE (company_id, platform)
);
COMMENT ON TABLE public.integrations IS 'Manages connections to external platforms like Shopify.';


--
-- === TRIGGERS ===
--
-- Drop existing triggers before creating new ones to ensure idempotency.
DROP TRIGGER IF EXISTS update_products_updated_at ON public.products;
DROP TRIGGER IF EXISTS update_product_variants_updated_at ON public.product_variants;
DROP TRIGGER IF EXISTS update_orders_updated_at ON public.orders;
DROP TRIGGER IF EXISTS update_integrations_updated_at ON public.integrations;

-- Trigger to update 'updated_at' timestamp for products
CREATE TRIGGER update_products_updated_at
BEFORE UPDATE ON public.products
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Trigger to update 'updated_at' timestamp for product_variants
CREATE TRIGGER update_product_variants_updated_at
BEFORE UPDATE ON public.product_variants
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Trigger to update 'updated_at' timestamp for orders
CREATE TRIGGER update_orders_updated_at
BEFORE UPDATE ON public.orders
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Trigger to update 'updated_at' timestamp for integrations
CREATE TRIGGER update_integrations_updated_at
BEFORE UPDATE ON public.integrations
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

--
-- === INDEXES ===
--
-- Create indexes for frequently queried columns to improve performance.
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_company_id ON public.product_variants(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON public.orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON public.order_line_items(variant_id);
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers(company_id);
CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON public.suppliers(company_id);


--
-- === ROW-LEVEL SECURITY (RLS) ===
--

-- Helper function to create RLS policies on tables
DROP FUNCTION IF EXISTS create_rls_policy(text) CASCADE;
CREATE OR REPLACE FUNCTION create_rls_policy(table_name text)
RETURNS void AS $$
BEGIN
  EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', table_name);
  EXECUTE format('
    CREATE POLICY "Users can only see their own company''s data."
    ON public.%I FOR ALL
    USING (company_id = public.get_current_company_id());
  ', table_name);
END;
$$ LANGUAGE plpgsql;

-- Apply RLS policies to all company-scoped tables
SELECT create_rls_policy(table_name)
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN (
    'products',
    'product_variants',
    'orders',
    'order_line_items',
    'customers',
    'customer_addresses',
    'refunds',
    'refund_line_items',
    'discounts',
    'suppliers',
    'integrations',
    'company_settings'
  );

-- Special RLS for the companies table so a user can see their own company
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can only see their own company." ON public.companies;
CREATE POLICY "Users can only see their own company."
ON public.companies FOR SELECT
USING (id = public.get_current_company_id());


-- Grant permissions to authenticated users
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;
