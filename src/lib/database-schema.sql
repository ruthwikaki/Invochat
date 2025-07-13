
-- =====================================================
-- Enable UUID generation
-- =====================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =====================================================
-- Custom Types
-- =====================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE public.user_role AS ENUM ('Owner', 'Admin', 'Member');
    END IF;
END$$;


-- =====================================================
-- Drop Existing Objects
-- =====================================================
-- This section ensures the script is idempotent (can be run multiple times)
-- by dropping objects that will be recreated.
DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;


-- =====================================================
-- Core Tables
-- =====================================================

-- Companies Table
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);

-- User Profiles Table
-- Stores app-specific user data, linking auth.users to a company.
CREATE TABLE IF NOT EXISTS public.users (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email text,
    role user_role NOT NULL DEFAULT 'Member'::user_role,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now()
);

-- Customers Table
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
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers(company_id);


-- Products Table (replaces 'inventory')
-- Acts as a parent for product variants
CREATE TABLE IF NOT EXISTS public.products (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    description text,
    handle text,
    product_type text,
    tags text[],
    status text DEFAULT 'active',
    image_url text,
    external_product_id text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);


-- =====================================================
-- Helper Functions & Triggers
-- =====================================================

-- Function to get the current user's company_id from their auth token
CREATE OR REPLACE FUNCTION public.get_current_company_id()
RETURNS uuid AS $$
BEGIN
    -- Cast the result to uuid to match the return type
    RETURN (
        SELECT (raw_app_meta_data->>'company_id')::uuid
        FROM auth.users
        WHERE id = auth.uid()
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Function to automatically create a company and user profile on new user signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
    new_company_id uuid;
    new_user_role public.user_role;
BEGIN
    -- Create a new company for the new user
    INSERT INTO public.companies (name)
    VALUES (new.raw_user_meta_data->>'company_name')
    RETURNING id INTO new_company_id;

    -- The first user of a company is always the Owner
    new_user_role := 'Owner';

    -- Insert a new row into the public.users table
    INSERT INTO public.users (id, company_id, email, role)
    VALUES (new.id, new_company_id, new.email, new_user_role);

    -- Update the user's app_metadata with the new company_id and role
    UPDATE auth.users
    SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'role', new_user_role)
    WHERE id = new.id;

    RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to call handle_new_user on new user creation in auth.users
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_user();

-- Function to update the updated_at timestamp on any table with the column
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- =====================================================
-- Main Data Tables (Shopify-like structure)
-- =====================================================

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
    inventory_quantity integer DEFAULT 0,
    external_variant_id text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_company_id ON public.product_variants(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_sku ON public.product_variants(sku);
ALTER TABLE public.product_variants DROP CONSTRAINT IF EXISTS unique_sku_per_company;
ALTER TABLE public.product_variants ADD CONSTRAINT unique_sku_per_company UNIQUE (company_id, sku);
CREATE TRIGGER update_product_variants_updated_at BEFORE UPDATE ON public.product_variants FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

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
    subtotal integer NOT NULL DEFAULT 0, -- in cents
    total_tax integer DEFAULT 0, -- in cents
    total_shipping integer DEFAULT 0, -- in cents
    total_discounts integer DEFAULT 0, -- in cents
    total_amount integer NOT NULL, -- in cents
    source_platform text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON public.orders(customer_id);
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS unique_order_number_per_company;
ALTER TABLE public.orders ADD CONSTRAINT unique_order_number_per_company UNIQUE (company_id, order_number);
CREATE TRIGGER update_orders_updated_at BEFORE UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

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
    total_discount integer DEFAULT 0, -- in cents
    tax_amount integer DEFAULT 0, -- in cents
    cost_at_time integer, -- in cents
    external_line_item_id text
);
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON public.order_line_items(variant_id);

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
CREATE INDEX IF NOT EXISTS idx_customer_addresses_customer_id ON public.customer_addresses(customer_id);

-- Discounts Table
CREATE TABLE IF NOT EXISTS public.discounts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    code text NOT NULL,
    type text NOT NULL, -- percentage/fixed_amount
    value numeric NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);
ALTER TABLE public.discounts DROP CONSTRAINT IF EXISTS unique_discount_code_per_company;
ALTER TABLE public.discounts ADD CONSTRAINT unique_discount_code_per_company UNIQUE (company_id, code);

-- Refunds Table
CREATE TABLE IF NOT EXISTS public.refunds (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    refund_number text NOT NULL,
    status text DEFAULT 'pending',
    reason text,
    note text,
    total_amount integer NOT NULL, -- in cents
    created_by_user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
    external_refund_id text,
    created_at timestamp with time zone DEFAULT now()
);
ALTER TABLE public.refunds DROP CONSTRAINT IF EXISTS unique_refund_number_per_company;
ALTER TABLE public.refunds ADD CONSTRAINT unique_refund_number_per_company UNIQUE (company_id, refund_number);
CREATE INDEX IF NOT EXISTS idx_refunds_order_id ON public.refunds(order_id);

-- Refund Line Items Table
CREATE TABLE IF NOT EXISTS public.refund_line_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    refund_id uuid NOT NULL REFERENCES public.refunds(id) ON DELETE CASCADE,
    order_line_item_id uuid NOT NULL REFERENCES public.order_line_items(id) ON DELETE CASCADE,
    quantity integer NOT NULL,
    amount integer NOT NULL, -- in cents
    restock boolean DEFAULT true
);
CREATE INDEX IF NOT EXISTS idx_refund_line_items_refund_id ON public.refund_line_items(refund_id);


-- =================================================================
-- SUPPORTING & APP-SPECIFIC TABLES
-- =================================================================

-- Company Settings Table
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    fast_moving_days integer NOT NULL DEFAULT 30,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone
);
CREATE TRIGGER update_company_settings_updated_at BEFORE UPDATE ON public.company_settings FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Integrations Table
CREATE TABLE IF NOT EXISTS public.integrations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform text NOT NULL, -- 'shopify', 'woocommerce', etc.
    shop_domain text,
    shop_name text,
    is_active boolean DEFAULT false,
    last_sync_at timestamp with time zone,
    sync_status text, -- 'syncing', 'success', 'failed', 'idle'
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone
);
CREATE TRIGGER update_integrations_updated_at BEFORE UPDATE ON public.integrations FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Suppliers Table
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

-- Conversations Table
CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    last_accessed_at timestamp with time zone DEFAULT now(),
    is_starred boolean DEFAULT false
);

-- Messages Table
CREATE TABLE IF NOT EXISTS public.messages (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
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
    created_at timestamp with time zone DEFAULT now()
);

-- Webhook Log Table (prevents replay attacks)
CREATE TABLE IF NOT EXISTS public.platform_webhook_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    platform text NOT NULL,
    external_webhook_id text NOT NULL,
    received_at timestamp with time zone DEFAULT now()
);
ALTER TABLE public.platform_webhook_events ADD CONSTRAINT unique_webhook_per_integration UNIQUE (integration_id, external_webhook_id);


-- =================================================================
-- ROW-LEVEL SECURITY (RLS) POLICIES
-- =================================================================
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_addresses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.discounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refunds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refund_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_webhook_events ENABLE ROW LEVEL SECURITY;


-- Function to automate RLS policy creation
CREATE OR REPLACE FUNCTION create_rls_policy(table_name TEXT) RETURNS void AS $$
BEGIN
    EXECUTE format('DROP POLICY IF EXISTS "Users can only see their own company''s data." ON public.%I', table_name);
    EXECUTE format('
        CREATE POLICY "Users can only see their own company''s data."
        ON public.%I
        FOR ALL
        USING (company_id = public.get_current_company_id());
    ', table_name);
END;
$$ LANGUAGE plpgsql;

-- Apply the RLS policy to all relevant tables
SELECT create_rls_policy(table_name)
FROM information_schema.tables
WHERE table_schema = 'public' AND table_name IN (
    'products', 'product_variants', 'orders', 'order_line_items',
    'customers', 'customer_addresses', 'discounts', 'refunds',
    'refund_line_items', 'suppliers', 'integrations', 'company_settings',
    'conversations', 'messages'
);

-- Special policy for companies table
DROP POLICY IF EXISTS "Users can only see their own company." ON public.companies;
CREATE POLICY "Users can only see their own company." ON public.companies
FOR SELECT USING (id = public.get_current_company_id());

-- Special policy for users table (allow users to see other users in their company)
DROP POLICY IF EXISTS "Users can see other users in their company." ON public.users;
CREATE POLICY "Users can see other users in their company." ON public.users
FOR SELECT USING (company_id = public.get_current_company_id());

-- Grant permissions for authenticated users on the new schema
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO authenticated;

-- Grant usage on the schema to the supabase_admin role
GRANT USAGE ON SCHEMA public TO supabase_admin;
GRANT ALL ON ALL TABLES IN SCHEMA public TO supabase_admin;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO supabase_admin;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO supabase_admin;
