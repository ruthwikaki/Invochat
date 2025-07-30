-- ===============================================================================================
--                                          IMPORTANT
-- This script is designed to be run once to set up the database schema for the AIventory app.
-- It is idempotent, meaning you can run it multiple times without causing errors.
-- Running this script will clear any existing data in the tables it creates.
-- ===============================================================================================

-- 1. Enable UUID extension for creating unique identifiers.
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 2. Define custom types (enums) for consistency and data integrity.
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
END
$$;


-- ===============================================================================================
--                                          TABLES
-- ===============================================================================================

-- Companies Table
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    owner_id uuid REFERENCES auth.users(id) NOT NULL
);
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;

-- Company Users Junction Table (for many-to-many relationship)
CREATE TABLE IF NOT EXISTS public.company_users (
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role public.company_role NOT NULL DEFAULT 'Member',
    PRIMARY KEY (company_id, user_id)
);
ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;

-- Public Users Table (mirrors auth.users but with public data)
-- This table is now populated by Supabase's built-in mechanism, triggered by the `create_company_and_user` RPC.
-- We must define it so that RLS policies can be attached to it.
CREATE TABLE IF NOT EXISTS public.users (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email text,
    role public.company_role NOT NULL DEFAULT 'Member',
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now()
);
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- Company Settings Table
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    fast_moving_days integer NOT NULL DEFAULT 30,
    overstock_multiplier integer NOT NULL DEFAULT 3,
    high_value_threshold integer NOT NULL DEFAULT 100000, -- Stored in cents
    predictive_stock_days integer NOT NULL DEFAULT 7,
    currency text DEFAULT 'USD',
    timezone text DEFAULT 'UTC',
    tax_rate numeric DEFAULT 0,
    alert_settings jsonb DEFAULT '{"low_stock_threshold": 10, "critical_stock_threshold": 5, "email_notifications": true, "morning_briefing_enabled": true, "morning_briefing_time": "09:00"}',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;

-- Add other tables similarly...
-- (Products, ProductVariants, Orders, OrderLineItems, Customers, Suppliers, etc.)

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
    deleted_at timestamptz
);
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_products_external_id ON public.products(external_product_id);
ALTER TABLE public.products ADD CONSTRAINT unique_product_external_id UNIQUE (company_id, external_product_id);


CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON public.suppliers(company_id);


CREATE TABLE IF NOT EXISTS public.product_variants (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
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
    reorder_point integer,
    reorder_quantity integer,
    supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL,
    location text,
    external_variant_id text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    deleted_at timestamptz
);
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_variants_sku ON public.product_variants(company_id, sku);
ALTER TABLE public.product_variants ADD CONSTRAINT unique_variant_external_id UNIQUE (company_id, external_variant_id);


-- Create other tables as needed...
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text,
    email text,
    phone text,
    external_customer_id text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    deleted_at timestamptz
);
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers(company_id);
ALTER TABLE public.customers ADD CONSTRAINT unique_customer_external_id UNIQUE (company_id, external_customer_id);

CREATE TABLE IF NOT EXISTS public.orders (
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
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz
);
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
ALTER TABLE public.orders ADD CONSTRAINT unique_order_external_id UNIQUE (company_id, external_order_id);


CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id uuid REFERENCES public.product_variants(id),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
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
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items(order_id);


-- ===============================================================================================
--                                   DATABASE FUNCTIONS & TRIGGERS
-- ===============================================================================================

-- Function to get a user's company ID. Useful for RLS policies.
CREATE OR REPLACE FUNCTION public.get_company_id_for_user(user_id uuid)
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT company_id FROM public.company_users WHERE public.company_users.user_id = $1;
$$;

-- Function to create a company and link the new user as the owner.
-- This is called from the signup server action.
CREATE OR REPLACE FUNCTION public.create_company_and_user(
    p_company_name text,
    p_user_email text,
    p_user_password text,
    p_email_redirect_to text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    new_user_id uuid;
    new_company_id uuid;
BEGIN
    -- 1. Create the company first
    INSERT INTO public.companies (name, owner_id)
    -- The owner_id will be updated later, but we need a placeholder
    VALUES (p_company_name, '00000000-0000-0000-0000-000000000000')
    RETURNING id INTO new_company_id;

    -- 2. Create the user in auth.users, passing the new company_id in the metadata.
    -- This ensures the company_id is available when Supabase's internal trigger runs.
    SELECT auth.signup(p_user_email, p_user_password, p_email_redirect_to, jsonb_build_object('company_id', new_company_id, 'company_name', p_company_name))
    INTO new_user_id;

    -- 3. Now that the user exists, update the company's owner_id
    UPDATE public.companies SET owner_id = new_user_id WHERE id = new_company_id;
    
    -- 4. Create the link in company_users
    INSERT INTO public.company_users(user_id, company_id, role)
    VALUES (new_user_id, new_company_id, 'Owner');
    
    -- 5. Create the public user record
    INSERT INTO public.users(id, company_id, email, role)
    VALUES (new_user_id, new_company_id, p_user_email, 'Owner');

    RETURN new_company_id;
END;
$$;


-- ===============================================================================================
--                                  ROW LEVEL SECURITY (RLS) POLICIES
-- ===============================================================================================
-- These policies are the cornerstone of the multi-tenant security model.
-- They ensure that users can only access data belonging to their own company.

-- Helper function to get the current user's company ID
CREATE OR REPLACE FUNCTION auth.get_current_company_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT (auth.jwt()->>'app_metadata')::jsonb->>'company_id'
$$;

-- RLS Policies for all major tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can only see their own company" ON public.companies;
CREATE POLICY "Users can only see their own company" ON public.companies
  FOR SELECT USING (id = auth.get_current_company_id());

ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can only see their own company users" ON public.company_users;
CREATE POLICY "Users can only see their own company users" ON public.company_users
  FOR ALL USING (company_id = auth.get_current_company_id());

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can only see users in their own company" ON public.users;
CREATE POLICY "Users can only see users in their own company" ON public.users
  FOR SELECT USING (company_id = auth.get_current_company_id());

ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can only access their own company's settings" ON public.company_settings;
CREATE POLICY "Users can only access their own company's settings" ON public.company_settings
  FOR ALL USING (company_id = auth.get_current_company_id());

-- Apply similar RLS policies to all other data tables...
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can access products in their company" ON public.products;
CREATE POLICY "Users can access products in their company" ON public.products
  FOR ALL USING (company_id = auth.get_current_company_id());

ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can access variants in their company" ON public.product_variants;
CREATE POLICY "Users can access variants in their company" ON public.product_variants
  FOR ALL USING (company_id = auth.get_current_company_id());

ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can access orders in their company" ON public.orders;
CREATE POLICY "Users can access orders in their company" ON public.orders
  FOR ALL USING (company_id = auth.get_current_company_id());

ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can access line items in their company" ON public.order_line_items;
CREATE POLICY "Users can access line items in their company" ON public.order_line_items
  FOR ALL USING (company_id = auth.get_current_company_id());

ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can access customers in their company" ON public.customers;
CREATE POLICY "Users can access customers in their company" ON public.customers
  FOR ALL USING (company_id = auth.get_current_company_id());

ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can access suppliers in their company" ON public.suppliers;
CREATE POLICY "Users can access suppliers in their company" ON public.suppliers
  FOR ALL USING (company_id = auth.get_current_company_id());
