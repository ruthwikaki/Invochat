-- =================================================================
-- ARVO: PRODUCTION-READY DATABASE SCHEMA (SINGLE LOCATION)
-- =================================================================
-- This script is IDEMPOTENT and can be run safely multiple times.
-- It creates tables, functions, indexes, and applies security policies.

-- 1. Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =================================================================
-- TABLE & TYPE DEFINITIONS
-- =================================================================

-- Drop existing types if they exist to prevent conflicts
DROP TYPE IF EXISTS public.user_role;
-- Create user role type
CREATE TYPE public.user_role AS ENUM ('Owner', 'Admin', 'Member');

-- Rename the old 'inventory' table to 'products' for clarity
ALTER TABLE IF EXISTS public.inventory RENAME TO products;
ALTER INDEX IF EXISTS idx_inventory_company_sku RENAME TO idx_products_company_sku;

-- Create core tables if they don't exist
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    name text NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.users (
    id uuid PRIMARY KEY NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email text,
    role user_role NOT NULL DEFAULT 'Member'::user_role,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now()
);

-- Note: The 'products' table now represents the parent product.
-- The old 'inventory' table is effectively repurposed here.
CREATE TABLE IF NOT EXISTS public.products (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    description text,
    handle text,
    product_type text,
    tags text[],
    status text NOT NULL DEFAULT 'active',
    image_url text,
    external_product_id text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);

-- New table for product variants, as per your design
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
    updated_at timestamp with time zone DEFAULT now()
);

-- New table for orders, replacing the old 'sales' table
CREATE TABLE IF NOT EXISTS public.orders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number text NOT NULL,
    external_order_id text,
    customer_id uuid, -- FK added later
    financial_status text DEFAULT 'pending',
    fulfillment_status text DEFAULT 'unfulfilled',
    currency text DEFAULT 'USD',
    subtotal integer, -- in cents
    total_tax integer, -- in cents
    total_shipping integer, -- in cents
    total_discounts integer, -- in cents
    total_amount integer NOT NULL,
    source_platform text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);

-- New table for order line items, replacing 'sale_items'
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id uuid REFERENCES public.product_variants(id) ON DELETE SET NULL,
    company_id uuid NOT NULL,
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

CREATE TABLE IF NOT EXISTS public.customers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name text,
    email text,
    total_orders integer DEFAULT 0,
    total_spent integer DEFAULT 0, -- in cents
    first_order_date date,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now()
);

-- Now add the foreign key from orders to customers
ALTER TABLE public.orders
    ADD CONSTRAINT fk_orders_customer_id
    FOREIGN KEY (customer_id)
    REFERENCES public.customers(id)
    ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS public.refunds (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    refund_number text NOT NULL,
    reason text,
    note text,
    total_amount integer NOT NULL, -- in cents
    created_by_user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
    external_refund_id text,
    created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.refund_line_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    refund_id uuid NOT NULL REFERENCES public.refunds(id) ON DELETE CASCADE,
    order_line_item_id uuid NOT NULL REFERENCES public.order_line_items(id) ON DELETE CASCADE,
    quantity integer NOT NULL,
    amount integer NOT NULL, -- in cents
    restock boolean DEFAULT true
);

-- Other tables remain as they are (suppliers, integrations, settings, etc.)
CREATE TABLE IF NOT EXISTS public.suppliers (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  name text NOT NULL,
  email text,
  phone text,
  default_lead_time_days integer,
  notes text,
  created_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.integrations (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
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

CREATE TABLE IF NOT EXISTS public.company_settings (
  company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
  dead_stock_days integer NOT NULL DEFAULT 90,
  overstock_multiplier numeric NOT NULL DEFAULT 3,
  high_value_threshold numeric NOT NULL DEFAULT 1000,
  fast_moving_days integer NOT NULL DEFAULT 30,
  predictive_stock_days integer NOT NULL DEFAULT 7,
  currency text DEFAULT 'USD'::text,
  timezone text DEFAULT 'UTC'::text,
  promo_sales_lift_multiplier real NOT NULL DEFAULT 2.5,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone
);

-- =================================================================
-- INDEXES FOR PERFORMANCE
-- =================================================================

-- Product and Variant Indexes
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_company_id ON public.product_variants(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_sku ON public.product_variants(sku);

-- Order and Line Item Indexes
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON public.orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON public.orders(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON public.order_line_items(variant_id);

-- Other Essential Indexes
CREATE INDEX IF NOT EXISTS idx_customers_company_email ON public.customers(company_id, email);
CREATE INDEX IF NOT EXISTS idx_refunds_order_id ON public.refunds(order_id);

-- =================================================================
-- UNIQUE CONSTRAINTS FOR DATA INTEGRITY
-- =================================================================

ALTER TABLE public.product_variants ADD CONSTRAINT unique_sku_per_company UNIQUE (company_id, sku);
ALTER TABLE public.orders ADD CONSTRAINT unique_order_number_per_company UNIQUE (company_id, order_number);

-- =================================================================
-- FUNCTIONS & TRIGGERS
-- =================================================================

-- Function to set updated_at timestamp automatically
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply the trigger to relevant tables
CREATE TRIGGER update_products_updated_at BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_product_variants_updated_at BEFORE UPDATE ON public.product_variants FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_orders_updated_at BEFORE UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_integrations_updated_at BEFORE UPDATE ON public.integrations FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_company_settings_updated_at BEFORE UPDATE ON public.company_settings FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Function to handle new user sign-ups
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  v_company_id uuid;
  v_company_name text;
BEGIN
  -- Extract company name from metadata, default if not present
  v_company_name := NEW.raw_app_meta_data->>'company_name';
  IF v_company_name IS NULL OR v_company_name = '' THEN
    v_company_name := NEW.email;
  END IF;

  -- Create a new company for the user
  INSERT INTO public.companies (name)
  VALUES (v_company_name)
  RETURNING id INTO v_company_id;

  -- Insert into our public users table
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (NEW.id, v_company_id, NEW.email, 'Owner');
  
  -- Update the user's app_metadata with the new company_id
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', v_company_id)
  WHERE id = NEW.id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger for new user creation
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  WHEN (NEW.raw_app_meta_data->>'provider' IS NULL OR NEW.raw_app_meta_data->>'provider' = 'email')
  EXECUTE FUNCTION public.handle_new_user();


-- =================================================================
-- ROW LEVEL SECURITY (RLS)
-- =================================================================

-- Function to get the company_id from a user's claims
CREATE OR REPLACE FUNCTION auth.company_id()
RETURNS uuid
LANGUAGE sql STABLE
AS $$
  SELECT (current_setting('request.jwt.claims', true)::jsonb ->> 'company_id')::uuid
$$;

-- Function to check if a user has a specific role
CREATE OR REPLACE FUNCTION auth.has_role(role_to_check public.user_role)
RETURNS boolean
LANGUAGE sql STABLE
AS $$
  SELECT (current_setting('request.jwt.claims', true)::jsonb ->> 'role')::public.user_role = role_to_check
$$;

-- Apply RLS to all relevant tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refunds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refund_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;

-- Policies for tables with a `company_id` column
DO $$
DECLARE
  tbl text;
BEGIN
  FOR tbl IN
    SELECT table_name FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name IN (
      'companies', 'users', 'products', 'product_variants', 'orders', 'refunds', 'customers',
      'suppliers', 'integrations', 'company_settings'
    )
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS "allow_all_for_company_members" ON public.%I', tbl);
    EXECUTE format(
      'CREATE POLICY "allow_all_for_company_members" ON public.%I FOR ALL USING (company_id = auth.company_id()) WITH CHECK (company_id = auth.company_id())',
      tbl
    );
  END LOOP;
END;
$$;

-- Policies for tables that reference another table's company_id
DROP POLICY IF EXISTS "allow_all_for_company_members" ON public.order_line_items;
CREATE POLICY "allow_all_for_company_members" ON public.order_line_items FOR ALL
USING (
  company_id = auth.company_id() AND
  EXISTS (SELECT 1 FROM orders WHERE id = order_id AND company_id = auth.company_id())
)
WITH CHECK (
  company_id = auth.company_id()
);

DROP POLICY IF EXISTS "allow_all_for_company_members" ON public.refund_line_items;
CREATE POLICY "allow_all_for_company_members" ON public.refund_line_items FOR ALL
USING (
  EXISTS (
    SELECT 1 FROM refunds r
    JOIN orders o ON r.order_id = o.id
    WHERE r.id = refund_id AND o.company_id = auth.company_id()
  )
);

-- =================================================================
-- CLEANUP OLD TABLES
-- =================================================================
DROP TABLE IF EXISTS public.sales CASCADE;
DROP TABLE IF EXISTS public.sale_items CASCADE;
DROP TABLE IF EXISTS public.inventory_ledger CASCADE;
DROP TABLE IF EXISTS public.customer_addresses CASCADE;

-- Drop old functions if they exist
DROP FUNCTION IF EXISTS public.record_sale_transaction(uuid,text,text,text,numeric,text,text,text,jsonb);
DROP FUNCTION IF EXISTS public.record_sale_transaction_v2(uuid,text,text,text,numeric,text,text,text,jsonb);
DROP FUNCTION IF EXISTS public.is_member_of_company(uuid,uuid);

-- =================================================================
-- GRANT PERMISSIONS
-- =================================================================

-- Grant permissions to authenticated users
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
