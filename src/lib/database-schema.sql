
-- InvoChat Database Schema
-- Version: 2.0.0
-- Description: Sets up the complete database schema for the application,
-- including tables, roles, functions, and row-level security policies.
-- This script is designed to be idempotent and can be run multiple times safely.

--
-- ==== 1. Extensions ====
--
-- Enable the pgcrypto extension for gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

--
-- ==== 2. Custom Types ====
--
-- Drop existing types if they exist to ensure a clean slate
DROP TYPE IF EXISTS public.user_role;
DROP TYPE IF EXISTS public.order_status;
DROP TYPE IF EXISTS public.alert_type;
DROP TYPE IF EXISTS public.alert_severity;

-- Create custom types for roles, statuses, etc.
CREATE TYPE public.user_role AS ENUM ('Owner', 'Admin', 'Member');
CREATE TYPE public.order_status AS ENUM ('pending', 'completed', 'cancelled');
CREATE TYPE public.alert_type AS ENUM ('low_stock', 'dead_stock', 'profit_warning');
CREATE TYPE public.alert_severity AS ENUM ('info', 'warning', 'critical');

--
-- ==== 3. Tables ====
--
-- For idempotency, drop tables in reverse order of dependency.
DROP TABLE IF EXISTS public.refund_line_items CASCADE;
DROP TABLE IF EXISTS public.purchase_order_line_items CASCADE;
DROP TABLE IF EXISTS public.purchase_orders CASCADE;
DROP TABLE IF EXISTS public.order_line_items CASCADE;
DROP TABLE IF EXISTS public.orders CASCADE;
DROP TABLE IF EXISTS public.inventory_ledger CASCADE;
DROP TABLE IF EXISTS public.product_variants CASCADE;
DROP TABLE IF EXISTS public.products CASCADE;
DROP TABLE IF EXISTS public.suppliers CASCADE;
DROP TABLE IF EXISTS public.customers CASCADE;
DROP TABLE IF EXISTS public.conversations CASCADE;
DROP TABLE IF EXISTS public.messages CASCADE;
DROP TABLE IF EXISTS public.integrations CASCADE;
DROP TABLE IF EXISTS public.channel_fees CASCADE;
DROP TABLE IF EXISTS public.imports CASCADE;
DROP TABLE IF EXISTS public.export_jobs CASCADE;
DROP TABLE IF EXISTS public.audit_log CASCADE;
DROP TABLE IF EXISTS public.webhook_events CASCADE;
DROP TABLE IF EXISTS public.company_settings CASCADE;
DROP TABLE IF EXISTS public.profiles CASCADE;
DROP TABLE IF EXISTS public.companies CASCADE;
DROP TABLE IF EXISTS public.locations CASCADE;


-- Companies Table
CREATE TABLE public.companies (
    id uuid default gen_random_uuid() primary key,
    name text not null,
    created_at timestamptz default (now() at time zone 'utc'),
    updated_at timestamptz
);

-- Locations Table (for multi-warehouse support)
CREATE TABLE public.locations (
    id uuid default gen_random_uuid() primary key,
    company_id uuid not null references public.companies(id) on delete cascade,
    name text not null,
    is_default boolean default false,
    created_at timestamptz default (now() at time zone 'utc'),
    updated_at timestamptz,
    unique(company_id, name)
);

-- User Profiles Table
-- This table stores public-facing user information and links to auth.users.
CREATE TABLE public.profiles (
    user_id uuid primary key references auth.users(id) on delete cascade,
    company_id uuid references public.companies(id) on delete cascade,
    role public.user_role not null default 'Member',
    first_name text,
    last_name text,
    updated_at timestamptz
);

-- Company Settings Table
CREATE TABLE public.company_settings (
    company_id uuid primary key references public.companies(id) on delete cascade,
    dead_stock_days int not null default 90,
    fast_moving_days int not null default 30,
    predictive_stock_days int not null default 7,
    overstock_multiplier numeric not null default 3.0,
    high_value_threshold int not null default 100000,
    promo_sales_lift_multiplier numeric not null default 2.5,
    currency text not null default 'USD',
    timezone text not null default 'UTC',
    tax_rate numeric,
    custom_rules jsonb,
    subscription_plan text,
    subscription_status text,
    subscription_expires_at timestamptz,
    stripe_customer_id text,
    stripe_subscription_id text,
    created_at timestamptz default (now() at time zone 'utc'),
    updated_at timestamptz
);

-- Products Table
CREATE TABLE public.products (
    id uuid default gen_random_uuid() primary key,
    company_id uuid not null references public.companies(id) on delete cascade,
    title text not null,
    description text,
    handle text,
    product_type text,
    tags text[],
    status text default 'active',
    image_url text,
    external_product_id text,
    created_at timestamptz default (now() at time zone 'utc'),
    updated_at timestamptz,
    unique(company_id, external_product_id)
);

-- Product Variants Table
CREATE TABLE public.product_variants (
    id uuid default gen_random_uuid() primary key,
    product_id uuid not null references public.products(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    location_id uuid references public.locations(id) on delete set null,
    sku text,
    title text,
    option1_name text,
    option1_value text,
    option2_name text,
    option2_value text,
    option3_name text,
    option3_value text,
    barcode text,
    price int, -- in cents
    compare_at_price int, -- in cents
    cost int, -- in cents
    inventory_quantity int not null default 0,
    external_variant_id text,
    created_at timestamptz default (now() at time zone 'utc'),
    updated_at timestamptz,
    unique(company_id, sku),
    unique(company_id, external_variant_id)
);


-- Suppliers Table
CREATE TABLE public.suppliers (
    id uuid default gen_random_uuid() primary key,
    company_id uuid not null references public.companies(id) on delete cascade,
    name text not null,
    email text,
    phone text,
    default_lead_time_days int,
    notes text,
    created_at timestamptz default (now() at time zone 'utc'),
    updated_at timestamptz
);

-- Customers Table
CREATE TABLE public.customers (
    id uuid default gen_random_uuid() primary key,
    company_id uuid not null references public.companies(id) on delete cascade,
    customer_name text,
    email text,
    total_orders int not null default 0,
    total_spent int not null default 0,
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz default (now() at time zone 'utc'),
    updated_at timestamptz,
    unique(company_id, email)
);

-- Orders Table
CREATE TABLE public.orders (
    id uuid default gen_random_uuid() primary key,
    company_id uuid not null references public.companies(id) on delete cascade,
    order_number text not null,
    external_order_id text,
    customer_id uuid references public.customers(id) on delete set null,
    financial_status text,
    fulfillment_status text,
    currency text,
    subtotal int,
    total_tax int,
    total_shipping int,
    total_discounts int,
    total_amount int not null,
    source_platform text,
    created_at timestamptz default (now() at time zone 'utc'),
    updated_at timestamptz
);

-- Order Line Items Table
CREATE TABLE public.order_line_items (
    id uuid default gen_random_uuid() primary key,
    order_id uuid not null references public.orders(id) on delete cascade,
    variant_id uuid references public.product_variants(id) on delete set null,
    company_id uuid not null references public.companies(id) on delete cascade,
    product_name text,
    variant_title text,
    sku text,
    quantity int not null,
    price int not null,
    total_discount int,
    tax_amount int,
    cost_at_time int,
    external_line_item_id text
);

-- Refund Line Items Table (for accurate profit tracking)
CREATE TABLE public.refund_line_items (
    id uuid default gen_random_uuid() primary key,
    order_id uuid not null references public.orders(id) on delete cascade,
    line_item_id uuid references public.order_line_items(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    quantity int not null,
    reason text,
    refund_amount int not null, -- in cents
    restock_type text, -- e.g., 'no_restock', 'return'
    created_at timestamptz default (now() at time zone 'utc')
);


-- Inventory Ledger Table
CREATE TABLE public.inventory_ledger (
    id uuid default gen_random_uuid() primary key,
    company_id uuid not null references public.companies(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    location_id uuid references public.locations(id) on delete set null,
    change_type text not null,
    quantity_change int not null,
    new_quantity int not null,
    related_id uuid, -- e.g., order_id, po_id
    notes text,
    created_at timestamptz default (now() at time zone 'utc')
);

-- Integrations Table
CREATE TABLE public.integrations (
    id uuid default gen_random_uuid() primary key,
    company_id uuid not null references public.companies(id) on delete cascade,
    platform text not null,
    shop_domain text,
    shop_name text,
    is_active boolean default true,
    last_sync_at timestamptz,
    sync_status text,
    created_at timestamptz default (now() at time zone 'utc'),
    updated_at timestamptz,
    unique(company_id, platform)
);

-- Webhook Events Table (for replay protection)
CREATE TABLE public.webhook_events (
    id uuid default gen_random_uuid() primary key,
    integration_id uuid not null references public.integrations(id) on delete cascade,
    webhook_id text not null,
    processed_at timestamptz default (now() at time zone 'utc'),
    unique(integration_id, webhook_id)
);


-- AI/Chat Tables
CREATE TABLE public.conversations (
    id uuid default gen_random_uuid() primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    title text not null,
    is_starred boolean default false,
    created_at timestamptz default (now() at time zone 'utc'),
    last_accessed_at timestamptz default (now() at time zone 'utc')
);

CREATE TABLE public.messages (
    id uuid default gen_random_uuid() primary key,
    conversation_id uuid not null references public.conversations(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    role text not null,
    content text not null,
    visualization jsonb,
    component text,
    component_props jsonb,
    confidence float,
    assumptions text[],
    created_at timestamptz default (now() at time zone 'utc')
);

-- Data Import/Export Tables
CREATE TABLE public.imports (
    id uuid default gen_random_uuid() primary key,
    company_id uuid not null references public.companies(id) on delete cascade,
    created_by uuid not null references auth.users(id) on delete cascade,
    import_type text not null,
    file_name text,
    total_rows int,
    processed_rows int,
    failed_rows int,
    status text, -- e.g., 'processing', 'completed', 'failed'
    errors jsonb,
    summary jsonb,
    created_at timestamptz default (now() at time zone 'utc'),
    completed_at timestamptz
);

CREATE TABLE public.export_jobs (
    id uuid default gen_random_uuid() primary key,
    company_id uuid not null references public.companies(id) on delete cascade,
    requested_by_user_id uuid not null references auth.users(id) on delete cascade,
    status text not null default 'queued', -- 'queued', 'processing', 'completed', 'failed'
    file_url text,
    error_message text,
    created_at timestamptz default (now() at time zone 'utc'),
    completed_at timestamptz
);

--
-- ==== 4. Views ====
--
-- For idempotency, drop views first
DROP VIEW IF EXISTS public.product_variants_with_details;

-- A view to simplify querying inventory with all relevant details.
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.*,
    p.title as product_title,
    p.status as product_status,
    p.image_url,
    l.name as location_name
FROM
    public.product_variants pv
LEFT JOIN
    public.products p ON pv.product_id = p.id
LEFT JOIN
    public.locations l ON pv.location_id = l.id;


--
-- ==== 5. Functions ====
--
-- These functions handle business logic and provide helpers for RLS policies.
-- Using `CREATE OR REPLACE` makes this script idempotent.

-- Helper function to get the current user's company ID
CREATE OR REPLACE FUNCTION public.get_current_company_id()
RETURNS uuid
LANGUAGE sql STABLE
AS $$
  select company_id from public.profiles where user_id = auth.uid();
$$;

-- Function to set the updated_at column automatically
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = (now() at time zone 'utc');
    RETURN NEW;
END;
$$;


-- Main function to handle new user sign-ups
CREATE OR REPLACE FUNCTION public.on_auth_user_created()
RETURNS TRIGGER
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
    VALUES (v_company_name)
    RETURNING id INTO v_company_id;

    -- Create the user's profile with 'Owner' role
    INSERT INTO public.profiles (user_id, company_id, role)
    VALUES (NEW.id, v_company_id, 'Owner');
    
    RETURN NEW;
END;
$$;


-- Function to apply the `set_updated_at` trigger to a list of tables
CREATE OR REPLACE FUNCTION public.apply_updated_at_trigger(tables text[])
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    table_name text;
BEGIN
    FOREACH table_name IN ARRAY tables
    LOOP
        EXECUTE format('
            DROP TRIGGER IF EXISTS handle_updated_at ON public.%I;
            CREATE TRIGGER handle_updated_at
            BEFORE UPDATE ON public.%I
            FOR EACH ROW
            EXECUTE FUNCTION public.set_updated_at();
        ', table_name, table_name);
    END LOOP;
END;
$$;

--
-- ==== 6. Triggers ====
--
-- Drop the user creation trigger if it exists
DROP TRIGGER IF EXISTS on_auth_user_created_trigger ON auth.users;

-- Trigger to create a company and profile when a new user signs up
CREATE TRIGGER on_auth_user_created_trigger
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.on_auth_user_created();

-- Apply the updated_at trigger to all relevant tables
SELECT public.apply_updated_at_trigger(ARRAY[
    'companies', 'profiles', 'company_settings', 'products', 'product_variants',
    'suppliers', 'customers', 'orders', 'integrations'
]);


--
-- ==== 7. Row-Level Security (RLS) ====
--

-- Enable RLS on all tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refund_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.imports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

-- Drop existing policies before creating new ones for idempotency
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.companies;
DROP POLICY IF EXISTS "Allow full access based on user_id" ON public.profiles;
DROP POLICY IF EXISTS "Allow read access to other profiles in the same company" ON public.profiles;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.company_settings;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.products;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.product_variants;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.inventory_ledger;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.locations;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.suppliers;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.customers;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.orders;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.order_line_items;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.refund_line_items;
DROP POLICY IF EXISTS "Allow full access to own conversations" ON public.conversations;
DROP POLICY IF EXISTS "Allow full access to messages in own conversations" ON public.messages;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.integrations;
DROP POLICY IF EXISTS "Allow read access based on company_id" ON public.webhook_events;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.imports;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.export_jobs;
DROP POLICY IF EXISTS "Allow read access based on company_id" ON public.audit_log;


-- RLS Policies
CREATE POLICY "Allow full access based on company_id" ON public.companies
    FOR ALL USING (id = get_current_company_id());

CREATE POLICY "Allow full access based on user_id" ON public.profiles
    FOR ALL USING (user_id = auth.uid());

CREATE POLICY "Allow read access to other profiles in the same company" ON public.profiles
    FOR SELECT USING (company_id = get_current_company_id());

CREATE POLICY "Allow full access based on company_id" ON public.company_settings
    FOR ALL USING (company_id = get_current_company_id());

CREATE POLICY "Allow full access based on company_id" ON public.products
    FOR ALL USING (company_id = get_current_company_id());

CREATE POLICY "Allow full access based on company_id" ON public.product_variants
    FOR ALL USING (company_id = get_current_company_id());

CREATE POLICY "Allow full access based on company_id" ON public.inventory_ledger
    FOR ALL USING (company_id = get_current_company_id());

CREATE POLICY "Allow full access based on company_id" ON public.locations
    FOR ALL USING (company_id = get_current_company_id());

CREATE POLICY "Allow full access based on company_id" ON public.suppliers
    FOR ALL USING (company_id = get_current_company_id());

CREATE POLICY "Allow full access based on company_id" ON public.customers
    FOR ALL USING (company_id = get_current_company_id());

CREATE POLICY "Allow full access based on company_id" ON public.orders
    FOR ALL USING (company_id = get_current_company_id());

CREATE POLICY "Allow full access based on company_id" ON public.order_line_items
    FOR ALL USING (company_id = get_current_company_id());
    
CREATE POLICY "Allow full access based on company_id" ON public.refund_line_items
    FOR ALL USING (company_id = get_current_company_id());

CREATE POLICY "Allow full access to own conversations" ON public.conversations
    FOR ALL USING (user_id = auth.uid());

CREATE POLICY "Allow full access to messages in own conversations" ON public.messages
    FOR ALL USING (company_id = get_current_company_id() AND conversation_id IN (SELECT id FROM public.conversations WHERE user_id = auth.uid()));

CREATE POLICY "Allow full access based on company_id" ON public.integrations
    FOR ALL USING (company_id = get_current_company_id());

CREATE POLICY "Allow read access based on company_id" ON public.webhook_events
    FOR SELECT USING (integration_id IN (SELECT id FROM public.integrations WHERE company_id = get_current_company_id()));

CREATE POLICY "Allow full access based on company_id" ON public.imports
    FOR ALL USING (company_id = get_current_company_id());

CREATE POLICY "Allow full access based on company_id" ON public.export_jobs
    FOR ALL USING (company_id = get_current_company_id());

--
-- ==== 8. Indexes ====
--
-- Create indexes for performance on frequently queried columns.
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_company_id ON public.product_variants(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_sku ON public.product_variants(sku);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON public.orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON public.order_line_items(variant_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id ON public.inventory_ledger(variant_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_change_type ON public.inventory_ledger(change_type);
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers(company_id);
CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON public.suppliers(company_id);
CREATE INDEX IF NOT EXISTS idx_conversations_user_id ON public.conversations(user_id);
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id ON public.messages(conversation_id);


--
-- ==== 9. Finalization ====
--
-- The schema setup is complete.
--

