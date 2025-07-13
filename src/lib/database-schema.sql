
-- InvoChat SaaS Database Schema
-- Version: 2.0
-- Description: This script sets up a robust, multi-tenant database schema for a SaaS application.
-- It includes tables for products, variants, orders, customers, and more, with row-level security
-- enabled for all company-specific data.

-- =============================================
-- 1. INITIAL CLEANUP & EXTENSIONS
-- =============================================
-- Drop old tables and functions if they exist to ensure a clean slate.
-- Using CASCADE to handle dependencies and prevent errors during setup.
DROP TABLE IF EXISTS public.inventory CASCADE;
DROP TABLE IF EXISTS public.sales CASCADE;
DROP TABLE IF EXISTS public.sale_items CASCADE;
DROP TABLE IF EXISTS public.sync_logs CASCADE;
DROP TABLE IF EXISTS public.sync_state CASCADE;
DROP TABLE IF EXISTS public.purchase_orders CASCADE;
DROP TABLE IF EXISTS public.purchase_order_items CASCADE;

-- Drop functions and types with CASCADE to handle dependencies
DROP FUNCTION IF EXISTS handle_new_user() CASCADE;
DROP FUNCTION IF EXISTS get_current_company_id() CASCADE;
DROP FUNCTION IF EXISTS get_my_role(uuid) CASCADE;
DROP FUNCTION IF EXISTS is_company_member(uuid) CASCADE;
DROP FUNCTION IF EXISTS update_inventory_from_ledger() CASCADE;

DROP TYPE IF EXISTS user_role CASCADE;

-- Install necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =============================================
-- 2. CORE TABLE CREATION
-- =============================================

-- Table for companies (tenants)
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Table for user profiles, linked to a company
CREATE TABLE IF NOT EXISTS public.users (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email text,
    role text NOT NULL DEFAULT 'Member', -- 'Owner', 'Admin', 'Member'
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now()
);

-- Table for company-specific settings
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
    subscription_status text DEFAULT 'trial',
    subscription_plan text DEFAULT 'starter',
    subscription_expires_at timestamptz,
    stripe_customer_id text,
    stripe_subscription_id text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);

-- Products table (parent for variants)
CREATE TABLE IF NOT EXISTS public.products (
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
    UNIQUE(company_id, external_product_id)
);

-- Product Variants table (the actual sellable item with SKU)
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
    weight numeric,
    weight_unit text,
    inventory_quantity integer NOT NULL DEFAULT 0,
    external_variant_id text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    UNIQUE(company_id, sku)
);

-- Customers table
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name text NOT NULL,
    email text,
    total_orders integer DEFAULT 0,
    total_spent integer DEFAULT 0, -- in cents
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now()
);

-- Orders table
CREATE TABLE IF NOT EXISTS public.orders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number text NOT NULL,
    external_order_id text,
    customer_id uuid REFERENCES public.customers(id),
    financial_status text DEFAULT 'pending',
    fulfillment_status text DEFAULT 'unfulfilled',
    currency text DEFAULT 'USD',
    subtotal integer NOT NULL DEFAULT 0,
    total_tax integer DEFAULT 0,
    total_shipping integer DEFAULT 0,
    total_discounts integer DEFAULT 0,
    total_amount integer NOT NULL,
    source_platform text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    UNIQUE(company_id, external_order_id)
);

-- Order Line Items table
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id uuid REFERENCES public.product_variants(id),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_name text,
    variant_title text,
    sku text,
    quantity integer NOT NULL,
    price integer NOT NULL, -- in cents
    total_discount integer DEFAULT 0,
    tax_amount integer DEFAULT 0,
    cost_at_time integer, -- cost of the variant at the time of sale
    external_line_item_id text
);

-- Inventory Ledger for atomic stock movements
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type text NOT NULL, -- 'sale', 'restock', 'return', 'adjustment'
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid, -- e.g., order_id, purchase_order_id
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Suppliers table
CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Integrations table
CREATE TABLE IF NOT EXISTS public.integrations (
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

-- Conversations table for AI chat
CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    created_at timestamptz DEFAULT now(),
    last_accessed_at timestamptz DEFAULT now(),
    is_starred boolean DEFAULT false
);

-- Messages table for AI chat
CREATE TABLE IF NOT EXISTS public.messages (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role text NOT NULL, -- 'user', 'assistant'
    content text,
    component text,
    component_props jsonb,
    visualization jsonb,
    confidence numeric,
    assumptions text[],
    is_error boolean DEFAULT false,
    created_at timestamptz DEFAULT now()
);

-- =============================================
-- 3. FUNCTIONS & TRIGGERS
-- =============================================

-- Function to get the current user's company_id
CREATE OR REPLACE FUNCTION get_current_company_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid;
$$;


-- Function to handle new user creation
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  new_company_id uuid;
  new_user_role text;
BEGIN
  -- Create a new company for the user
  INSERT INTO public.companies (name)
  VALUES (new.raw_app_meta_data ->> 'company_name')
  RETURNING id INTO new_company_id;

  -- Insert a profile for the new user, linking them to the new company
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (new.id, new_company_id, new.email, 'Owner');
  
  -- Update the user's app_metadata with the new company_id and role
  UPDATE auth.users
  SET raw_app_meta_data = new.raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'role', 'Owner')
  WHERE id = new.id;
  
  RETURN new;
END;
$$;

-- Trigger to call handle_new_user on new user signup
CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION handle_new_user();


-- Trigger function to update inventory quantity
CREATE OR REPLACE FUNCTION update_inventory_from_ledger()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE public.product_variants
    SET inventory_quantity = NEW.new_quantity
    WHERE id = NEW.variant_id AND company_id = NEW.company_id;
    RETURN NEW;
END;
$$;

-- Trigger to update inventory after a ledger entry is created
CREATE OR REPLACE TRIGGER on_inventory_ledger_insert
    AFTER INSERT ON public.inventory_ledger
    FOR EACH ROW
    EXECUTE FUNCTION update_inventory_from_ledger();

-- =============================================
-- 4. ROW-LEVEL SECURITY (RLS)
-- =============================================
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refund_line_items ENABLE ROW LEVEL SECURITY;

-- Drop any existing RLS helper procedures/functions to avoid conflicts.
DROP FUNCTION IF EXISTS create_rls_policy(TEXT) CASCADE;
DROP PROCEDURE IF EXISTS create_rls_policy(TEXT) CASCADE;

-- Helper procedure to create RLS policies dynamically
CREATE OR REPLACE PROCEDURE create_rls_policy(
    table_name TEXT
)
LANGUAGE plpgsql
AS $$
BEGIN
    EXECUTE format(
        '
        DROP POLICY IF EXISTS "Users can only see their own company''s data." ON public.%I;
        CREATE POLICY "Users can only see their own company''s data."
        ON public.%I FOR ALL
        USING (company_id = public.get_current_company_id());
        ',
        table_name, table_name
    );
END;
$$;


-- Apply the RLS policies to all relevant tables
CALL create_rls_policy('company_settings');
CALL create_rls_policy('products');
CALL create_rls_policy('product_variants');
CALL create_rls_policy('customers');
CALL create_rls_policy('orders');
CALL create_rls_policy('order_line_items');
CALL create_rls_policy('suppliers');
CALL create_rls_policy('conversations');
CALL create_rls_policy('messages');
CALL create_rls_policy('integrations');
CALL create_rls_policy('inventory_ledger');
CALL create_rls_policy('refund_line_items');


-- Special RLS policies
DROP POLICY IF EXISTS "Users can only see their own company." ON public.companies;
CREATE POLICY "Users can only see their own company."
ON public.companies FOR SELECT
USING (id = public.get_current_company_id());

DROP POLICY IF EXISTS "Users can see other users in their own company." ON public.users;
CREATE POLICY "Users can see other users in their own company."
ON public.users FOR SELECT
USING (company_id = public.get_current_company_id());

-- =============================================
-- 5. INDEXES FOR PERFORMANCE
-- =============================================
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_variants_sku_company ON public.product_variants(sku, company_id);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id ON public.inventory_ledger(variant_id, created_at DESC);

-- Final success message
SELECT 'InvoChat Database Schema v2.0 setup complete.' as status;
