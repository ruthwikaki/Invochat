-- =================================================================
-- ARVO: PRODUCTION-READY DATABASE SCHEMA (FINAL)
-- Description: This script sets up the complete database schema
-- for the application. It is idempotent and can be run safely
-- on new or existing databases.
-- =================================================================

-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- =================================================================
-- Types and Enums
-- =================================================================

-- Define a user role type
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE public.user_role AS ENUM ('Owner', 'Admin', 'Member');
    END IF;
END $$;

-- =================================================================
-- Tables
-- =================================================================

-- Companies Table: Stores company information
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);

-- Users Table: Stores app users, linked to auth.users
CREATE TABLE IF NOT EXISTS public.users (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email text,
    role public.user_role NOT NULL DEFAULT 'Member',
    deleted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now()
);

-- Company Settings Table
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    fast_moving_days integer NOT NULL DEFAULT 30,
    overstock_multiplier numeric NOT NULL DEFAULT 3,
    high_value_threshold numeric NOT NULL DEFAULT 1000,
    predictive_stock_days integer NOT NULL DEFAULT 7,
    promo_sales_lift_multiplier real NOT NULL DEFAULT 2.5,
    currency text DEFAULT 'USD',
    timezone text DEFAULT 'UTC',
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone
);

-- Products Table: The parent product record
CREATE TABLE IF NOT EXISTS public.products (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    description text,
    handle text,
    product_type text,
    tags text[],
    status text NOT NULL DEFAULT 'active', -- active, draft, archived
    image_url text,
    external_product_id text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone
);
ALTER TABLE public.products ADD CONSTRAINT unique_external_product_id_per_company UNIQUE (company_id, external_product_id);


-- Product Variants Table: Specific versions of a product (SKUs)
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
    inventory_quantity integer NOT NULL DEFAULT 0,
    external_variant_id text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone
);
ALTER TABLE public.product_variants ADD CONSTRAINT unique_sku_per_company UNIQUE (company_id, sku);
ALTER TABLE public.product_variants ADD CONSTRAINT unique_external_variant_id_per_company UNIQUE (company_id, external_variant_id);


-- Customers Table
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name text,
    email text,
    total_orders integer DEFAULT 0,
    total_spent integer DEFAULT 0, -- in cents
    first_order_date date,
    external_customer_id text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone
);
ALTER TABLE public.customers ADD CONSTRAINT unique_external_customer_id_per_company UNIQUE (company_id, external_customer_id);

-- Customer Addresses Table
CREATE TABLE IF NOT EXISTS public.customer_addresses (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id uuid NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
    address_type text NOT NULL DEFAULT 'shipping', -- billing or shipping
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

-- Orders Table
CREATE TABLE IF NOT EXISTS public.orders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number text NOT NULL,
    external_order_id text,
    customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
    financial_status text DEFAULT 'pending', -- pending, paid, refunded, etc.
    fulfillment_status text DEFAULT 'unfulfilled', -- unfulfilled, partial, fulfilled
    currency text DEFAULT 'USD',
    subtotal integer, -- in cents
    total_tax integer, -- in cents
    total_shipping integer, -- in cents
    total_discounts integer, -- in cents
    total_amount integer NOT NULL, -- in cents
    source_platform text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone
);
ALTER TABLE public.orders ADD CONSTRAINT unique_external_order_id_per_company UNIQUE (company_id, external_order_id);

-- Order Line Items Table
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE RESTRICT,
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

-- Discounts Table
CREATE TABLE IF NOT EXISTS public.discounts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    code text NOT NULL,
    type text NOT NULL, -- e.g., 'percentage', 'fixed_amount'
    value numeric NOT NULL,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.discounts ADD CONSTRAINT unique_discount_code_per_company UNIQUE (company_id, code);

-- Inventory Adjustments (Ledger) Table
CREATE TABLE IF NOT EXISTS public.inventory_adjustments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type text NOT NULL, -- sale, return, restock, count, damage, etc.
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    reason text,
    related_id text,
    created_by_user_id uuid REFERENCES public.users(id),
    created_at timestamp with time zone NOT NULL DEFAULT now()
);


-- =================================================================
-- Indexes for Performance
-- =================================================================

-- Product related indexes
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_sku_company ON public.product_variants(company_id, sku);

-- Order related indexes
CREATE INDEX IF NOT EXISTS idx_orders_company_id_created_at ON public.orders(company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON public.orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON public.order_line_items(variant_id);

-- Customer related indexes
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers(company_id);
CREATE INDEX IF NOT EXISTS idx_customer_addresses_customer_id ON public.customer_addresses(customer_id);

-- Inventory Adjustments index
CREATE INDEX IF NOT EXISTS idx_inventory_adjustments_variant_id ON public.inventory_adjustments(variant_id, created_at DESC);


-- =================================================================
-- Functions and Triggers
-- =================================================================

-- Function to handle user creation and company setup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_company_id uuid;
    v_company_name text := NEW.raw_user_meta_data->>'company_name';
BEGIN
    -- Create a new company for the user
    INSERT INTO public.companies (name)
    VALUES (COALESCE(v_company_name, 'My Company'))
    RETURNING id INTO v_company_id;

    -- Insert into our public users table
    INSERT INTO public.users (id, company_id, email, role)
    VALUES (NEW.id, v_company_id, NEW.email, 'Owner');
    
    -- Create default settings for the new company
    INSERT INTO public.company_settings (company_id)
    VALUES (v_company_id);

    -- Update the user's app_metadata with the new company_id
    UPDATE auth.users
    SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', v_company_id)
    WHERE id = NEW.id;

    RETURN NEW;
END;
$$;

-- Trigger to call handle_new_user on new user signup
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_user();

-- Function to update 'updated_at' columns automatically
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply the updated_at trigger to relevant tables
DO $$
DECLARE
  t text;
BEGIN
  FOR t IN SELECT table_name FROM information_schema.columns WHERE column_name = 'updated_at' AND table_schema = 'public'
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS handle_updated_at ON public.%I', t);
    EXECUTE format('CREATE TRIGGER handle_updated_at BEFORE UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column()', t);
  END LOOP;
END;
$$;


-- =================================================================
-- Row Level Security (RLS)
-- =================================================================
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_addresses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.discounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_adjustments ENABLE ROW LEVEL SECURITY;


-- Function to get the current user's company_id
CREATE OR REPLACE FUNCTION public.get_my_company_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT (auth.jwt()->'app_metadata'->>'company_id')::uuid;
$$;


-- RLS Policies
-- Users can only see data belonging to their own company.
CREATE POLICY "Allow access to own company data" ON public.companies FOR SELECT USING (id = public.get_my_company_id());
CREATE POLICY "Allow access to own company data" ON public.users FOR ALL USING (company_id = public.get_my_company_id());
CREATE POLICY "Allow access to own company data" ON public.company_settings FOR ALL USING (company_id = public.get_my_company_id());
CREATE POLICY "Allow access to own company data" ON public.products FOR ALL USING (company_id = public.get_my_company_id());
CREATE POLICY "Allow access to own company data" ON public.product_variants FOR ALL USING (company_id = public.get_my_company_id());
CREATE POLICY "Allow access to own company data" ON public.orders FOR ALL USING (company_id = public.get_my_company_id());
CREATE POLICY "Allow access to own company data" ON public.order_line_items FOR ALL USING (company_id = public.get_my_company_id());
CREATE POLICY "Allow access to own company data" ON public.customers FOR ALL USING (company_id = public.get_my_company_id());
CREATE POLICY "Allow access to own company data" ON public.customer_addresses FOR ALL USING (customer_id IN (SELECT id FROM public.customers WHERE company_id = public.get_my_company_id()));
CREATE POLICY "Allow access to own company data" ON public.discounts FOR ALL USING (company_id = public.get_my_company_id());
CREATE POLICY "Allow access to own company data" ON public.inventory_adjustments FOR ALL USING (company_id = public.get_my_company_id());


-- =================================================================
-- Permissions
-- =================================================================

-- Grant usage on the schema to authenticated users
GRANT USAGE ON SCHEMA public TO authenticated;
-- Grant all permissions on all tables to authenticated users
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;
-- Grant execute permissions on all functions to authenticated users
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;

-- Note: The service_role key bypasses RLS, so it can access all data.

-- =================================================================
-- Finalization Message
-- =================================================================
DO $$
BEGIN
  RAISE NOTICE 'Database schema setup and optimization completed successfully!';
END $$;
