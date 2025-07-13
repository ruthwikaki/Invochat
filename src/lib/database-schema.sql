
-- InvoChat - SaaS Inventory Management Database Schema
-- Version: 2.0
-- Description: This script sets up the full database schema for the multi-tenant SaaS application.
-- It includes tables for companies, users, products with variants, orders, and more.
-- It also establishes Row-Level Security (RLS) to ensure data isolation between tenants.

--
-- EXTENSIONS
--
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

--
-- CLEANUP (Idempotency)
-- Drop existing objects if they exist to ensure a clean slate.
--
-- Drop policies before functions they use
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public') LOOP
        EXECUTE 'ALTER TABLE public.' || quote_ident(r.tablename) || ' DISABLE ROW LEVEL SECURITY';
    END LOOP;
END $$;

-- Drop functions with CASCADE to also remove dependent triggers
DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;
DROP FUNCTION IF EXISTS public.set_updated_at() CASCADE;
DROP FUNCTION IF EXISTS public.get_current_company_id() CASCADE;
DROP FUNCTION IF EXISTS public.create_rls_policy(text) CASCADE;

-- Drop custom types
DROP TYPE IF EXISTS public.user_role;

-- Drop tables in reverse order of dependency
DROP TABLE IF EXISTS public.sync_state CASCADE;
DROP TABLE IF EXISTS public.sync_logs CASCADE;
DROP TABLE IF EXISTS public.channel_fees CASCADE;
DROP TABLE IF EXISTS public.user_feedback CASCADE;
DROP TABLE IF EXISTS public.alerts CASCADE;
DROP TABLE IF EXISTS public.export_jobs CASCADE;
DROP TABLE IF EXISTS public.audit_log CASCADE;
DROP TABLE IF EXISTS public.messages CASCADE;
DROP TABLE IF EXISTS public.conversations CASCADE;
DROP TABLE IF EXISTS public.refund_line_items CASCADE;
DROP TABLE IF EXISTS public.refunds CASCADE;
DROP TABLE IF EXISTS public.order_line_items CASCADE;
DROP TABLE IF EXISTS public.orders CASCADE;
DROP TABLE IF EXISTS public.discounts CASCADE;
DROP TABLE IF EXISTS public.customer_addresses CASCADE;
DROP TABLE IF EXISTS public.customers CASCADE;
DROP TABLE IF EXISTS public.product_variants CASCADE;
DROP TABLE IF EXISTS public.products CASCADE;
DROP TABLE IF EXISTS public.suppliers CASCADE;
DROP TABLE IF EXISTS public.company_settings CASCADE;
DROP TABLE IF EXISTS public.users CASCADE;
DROP TABLE IF EXISTS public.companies CASCADE;


--
-- TYPE DEFINITIONS
--
CREATE TYPE public.user_role AS ENUM ('Owner', 'Admin', 'Member');


--
-- TABLE CREATION
--

-- Core tenancy and user tables
CREATE TABLE public.companies (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.companies IS 'Stores information about each tenant company.';

CREATE TABLE public.users (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email text,
    role user_role NOT NULL DEFAULT 'Member',
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now()
);
COMMENT ON TABLE public.users IS 'Stores application-specific user data and their role within a company.';

CREATE TABLE public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    fast_moving_days integer NOT NULL DEFAULT 30,
    predictive_stock_days integer NOT NULL DEFAULT 7,
    overstock_multiplier numeric NOT NULL DEFAULT 3,
    high_value_threshold numeric NOT NULL DEFAULT 1000,
    promo_sales_lift_multiplier real NOT NULL DEFAULT 2.5,
    currency text DEFAULT 'USD',
    timezone text DEFAULT 'UTC',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);
COMMENT ON TABLE public.company_settings IS 'Stores business rule settings for each company.';

-- Product catalog tables
CREATE TABLE public.products (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
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
    updated_at timestamptz
);
CREATE UNIQUE INDEX idx_products_company_external_id ON public.products(company_id, external_product_id);
COMMENT ON TABLE public.products IS 'Stores parent product information.';

CREATE TABLE public.product_variants (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
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
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);
CREATE UNIQUE INDEX idx_variants_company_sku ON public.product_variants(company_id, sku) WHERE sku IS NOT NULL;
CREATE UNIQUE INDEX idx_variants_company_external_id ON public.product_variants(company_id, external_variant_id) WHERE external_variant_id IS NOT NULL;
COMMENT ON TABLE public.product_variants IS 'Stores individual product variants (SKUs).';

-- Customer and Order tables
CREATE TABLE public.customers (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name text,
    email text,
    total_orders integer DEFAULT 0,
    total_spent integer DEFAULT 0, -- in cents
    first_order_date date,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX idx_customers_company_email ON public.customers(company_id, email) WHERE email IS NOT NULL;
COMMENT ON TABLE public.customers IS 'Stores customer information.';

CREATE TABLE public.customer_addresses (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    customer_id uuid NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    address_type text NOT NULL DEFAULT 'shipping', -- 'shipping' or 'billing'
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
COMMENT ON TABLE public.customer_addresses IS 'Stores shipping and billing addresses for customers.';

CREATE TABLE public.orders (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number text NOT NULL,
    external_order_id text,
    customer_id uuid REFERENCES public.customers(id),
    financial_status text,
    fulfillment_status text,
    currency text,
    subtotal integer NOT NULL DEFAULT 0, -- in cents
    total_tax integer,
    total_shipping integer,
    total_discounts integer,
    total_amount integer NOT NULL,
    source_platform text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);
CREATE UNIQUE INDEX idx_orders_company_external_id ON public.orders(company_id, external_order_id) WHERE external_order_id IS NOT NULL;
COMMENT ON TABLE public.orders IS 'Stores sales order headers.';

CREATE TABLE public.order_line_items (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
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
    cost_at_time integer, -- in cents
    external_line_item_id text
);
COMMENT ON TABLE public.order_line_items IS 'Stores individual line items for each order.';

CREATE TABLE public.refunds (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    refund_number text NOT NULL,
    status text NOT NULL DEFAULT 'pending',
    reason text,
    note text,
    total_amount integer NOT NULL, -- in cents
    created_by_user_id uuid REFERENCES auth.users(id),
    external_refund_id text,
    created_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.refunds IS 'Stores refund information.';

CREATE TABLE public.refund_line_items (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    refund_id uuid NOT NULL REFERENCES public.refunds(id) ON DELETE CASCADE,
    order_line_item_id uuid NOT NULL REFERENCES public.order_line_items(id),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    quantity integer NOT NULL,
    amount integer NOT NULL, -- in cents
    restock boolean DEFAULT true
);
COMMENT ON TABLE public.refund_line_items IS 'Stores individual line items for each refund.';

CREATE TABLE public.discounts (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    code text NOT NULL,
    type text NOT NULL,
    value numeric NOT NULL,
    minimum_purchase numeric,
    usage_limit integer,
    usage_count integer DEFAULT 0,
    applies_to text DEFAULT 'all',
    starts_at timestamptz,
    ends_at timestamptz,
    is_active boolean DEFAULT true,
    created_at timestamptz DEFAULT now()
);
COMMENT ON TABLE public.discounts IS 'Stores discount and coupon codes.';


-- Other application tables
CREATE TABLE public.suppliers (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.integrations (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
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

CREATE TABLE public.conversations (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    created_at timestamptz DEFAULT now(),
    last_accessed_at timestamptz DEFAULT now(),
    is_starred boolean DEFAULT false
);

CREATE TABLE public.messages (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role text NOT NULL,
    content text,
    component text,
    component_props jsonb,
    visualization jsonb,
    confidence numeric,
    assumptions text[],
    is_error boolean DEFAULT false,
    created_at timestamptz DEFAULT now()
);

--
-- HELPER FUNCTIONS & TRIGGERS
--

-- Function to get the company_id from the current user's session
CREATE OR REPLACE FUNCTION public.get_current_company_id()
RETURNS uuid
LANGUAGE sql STABLE
AS $$
  SELECT
    CASE
      WHEN (current_setting('request.jwt.claims', true)::jsonb ->> 'app_metadata')::jsonb ->> 'company_id' IS NULL THEN NULL
      ELSE ((current_setting('request.jwt.claims', true)::jsonb ->> 'app_metadata')::jsonb ->> 'company_id')::uuid
    END;
$$;


-- This trigger automatically creates a company and a user row when a new user signs up
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER -- Required to insert into tables with RLS
AS $$
DECLARE
  new_company_id uuid;
  user_company_name text;
BEGIN
  -- Extract company name from metadata, defaulting if not present
  user_company_name := NEW.raw_app_meta_data->>'company_name';
  IF user_company_name IS NULL OR user_company_name = '' THEN
    user_company_name := NEW.email || '''s Company';
  END IF;

  -- Create a new company for the new user
  INSERT INTO public.companies (name)
  VALUES (user_company_name)
  RETURNING id INTO new_company_id;

  -- Create a corresponding user row in public.users
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (NEW.id, new_company_id, NEW.email, 'Owner');

  -- Update the user's app_metadata with the new company_id
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'role', 'Owner')
  WHERE id = NEW.id;

  RETURN NEW;
END;
$$;

-- Attaching the trigger to the auth.users table
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();


-- Function to automatically update 'updated_at' columns
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

--
-- ROW-LEVEL SECURITY (RLS) POLICIES
-- This is the core of our multi-tenant security model.
--

-- Helper function to dynamically create RLS policies on tables
CREATE OR REPLACE FUNCTION create_rls_policy(table_name text) RETURNS void AS $$
BEGIN
  EXECUTE format('
    ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;
    CREATE POLICY "Users can only see their own company''s data."
    ON public.%I FOR ALL
    USING (company_id = public.get_current_company_id());
  ', table_name, table_name);
END;
$$ LANGUAGE plpgsql;

-- Apply RLS policies to all tenant-specific tables
SELECT create_rls_policy('products');
SELECT create_rls_policy('product_variants');
SELECT create_rls_policy('orders');
SELECT create_rls_policy('order_line_items');
SELECT create_rls_policy('customers');
SELECT create_rls_policy('customer_addresses');
SELECT create_rls_policy('refunds');
SELECT create_rls_policy('refund_line_items');
SELECT create_rls_policy('discounts');
SELECT create_rls_policy('suppliers');
SELECT create_rls_policy('integrations');
SELECT create_rls_policy('conversations');
SELECT create_rls_policy('messages');

-- Special RLS for the users table itself
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can see other users in their own company"
ON public.users FOR SELECT
USING (company_id = public.get_current_company_id());
CREATE POLICY "Users can update their own data"
ON public.users FOR UPDATE
USING (id = auth.uid());

-- Special RLS for company_settings
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can access their own company's settings"
ON public.company_settings FOR ALL
USING (company_id = public.get_current_company_id());


--
-- TRIGGERS for `updated_at`
--
DROP TRIGGER IF EXISTS handle_updated_at ON public.products;
CREATE TRIGGER handle_updated_at BEFORE UPDATE ON public.products
  FOR EACH ROW EXECUTE PROCEDURE public.set_updated_at();

DROP TRIGGER IF EXISTS handle_updated_at ON public.product_variants;
CREATE TRIGGER handle_updated_at BEFORE UPDATE ON public.product_variants
  FOR EACH ROW EXECUTE PROCEDURE public.set_updated_at();

DROP TRIGGER IF EXISTS handle_updated_at ON public.orders;
CREATE TRIGGER handle_updated_at BEFORE UPDATE ON public.orders
  FOR EACH ROW EXECUTE PROCEDURE public.set_updated_at();

DROP TRIGGER IF EXISTS handle_updated_at ON public.company_settings;
CREATE TRIGGER handle_updated_at BEFORE UPDATE ON public.company_settings
  FOR EACH ROW EXECUTE PROCEDURE public.set_updated_at();

DROP TRIGGER IF EXISTS handle_updated_at ON public.integrations;
CREATE TRIGGER handle_updated_at BEFORE UPDATE ON public.integrations
  FOR EACH ROW EXECUTE PROCEDURE public.set_updated_at();

-- Grant usage on the schema to the authenticated role
GRANT USAGE ON SCHEMA public TO authenticated;
-- Grant select permissions on all current and future tables to the authenticated role
GRANT SELECT ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;


-- Finalizing the setup
-- Note: Materialized views and advanced RPC functions for analytics will be managed separately.
-- This script provides the core schema.

