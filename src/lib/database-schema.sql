
-- ### InvoChat Database Schema ###
-- This script is idempotent and can be run safely on a new or existing database.
-- It creates all necessary tables, functions, views, and security policies.

-- 1. Extensions
-- Enable the UUID generator extension if it doesn't exist.
create extension if not exists "uuid-ossp" with schema extensions;

-- 2. Custom Types
-- Define custom types used throughout the schema if they don't exist.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'app_role') THEN
        create type public.app_role as enum ('owner', 'admin', 'member');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'app_permission') THEN
        create type public.app_permission as enum ('all');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'permission_type') THEN
        create type public.permission_type as enum ('read', 'write');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'platform_type') THEN
        create type public.platform_type as enum ('shopify', 'woocommerce', 'amazon_fba');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'sync_status_type') THEN
        create type public.sync_status_type as enum ('syncing_products', 'syncing_sales', 'syncing', 'success', 'failed', 'idle');
    END IF;
END$$;


-- 3. Users and Companies
-- Create a public users table to mirror auth.users for easier RLS.
create table if not exists public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  company_id uuid not null,
  email text,
  role public.app_role not null default 'member',
  created_at timestamptz default now(),
  deleted_at timestamptz
);
comment on table public.users is 'Public user profiles, linked to a company.';

create table if not exists public.companies (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  created_at timestamptz not null default now()
);
comment on table public.companies is 'Represents a single company or tenant.';

-- Create a join table for many-to-many relationship between users and companies.
create table if not exists public.company_users (
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.app_role not null default 'member',
  primary key (company_id, user_id)
);
comment on table public.company_users is 'Associates users with companies and their roles.';

-- 4. Core Inventory Tables
create table if not exists public.products (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    title text not null,
    description text,
    handle text,
    product_type text,
    tags text[],
    status text,
    image_url text,
    external_product_id text,
    fts_document tsvector,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);
comment on table public.products is 'Stores main product information.';
create index if not exists idx_products_company_id on public.products(company_id);
create unique index if not exists idx_products_company_external_id on public.products(company_id, external_product_id);


create table if not exists public.product_variants (
    id uuid primary key default gen_random_uuid(),
    product_id uuid not null references public.products(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    sku text not null,
    title text,
    option1_name text,
    option1_value text,
    option2_name text,
    option2_value text,
    option3_name text,
    option3_value text,
    barcode text,
    price integer,
    compare_at_price integer,
    cost integer,
    inventory_quantity integer not null default 0,
    external_variant_id text,
    location text,
    created_at timestamptz default now(),
    updated_at timestamptz
);
comment on table public.product_variants is 'Stores individual product variants (SKUs).';
create index if not exists idx_product_variants_product_id on public.product_variants(product_id);
create index if not exists idx_product_variants_company_id on public.product_variants(company_id);
create index if not exists idx_product_variants_sku_company on public.product_variants(sku, company_id);
create unique index if not exists idx_product_variants_company_external_id on public.product_variants(company_id, external_variant_id);


create table if not exists public.inventory_ledger (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    change_type text not null,
    quantity_change integer not null,
    new_quantity integer not null,
    related_id uuid,
    notes text,
    created_at timestamptz not null default now()
);
comment on table public.inventory_ledger is 'Transactional log of all stock movements.';
create index if not exists idx_inventory_ledger_variant_id_created_at on public.inventory_ledger(variant_id, created_at desc);
create index if not exists idx_inventory_ledger_company_id on public.inventory_ledger(company_id);

-- 5. Sales & Customer Tables
create table if not exists public.customers (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    customer_name text not null,
    email text,
    total_orders integer default 0,
    total_spent integer default 0,
    first_order_date date,
    created_at timestamptz default now(),
    deleted_at timestamptz
);
comment on table public.customers is 'Stores customer data.';
create index if not exists idx_customers_company_id on public.customers(company_id);

create table if not exists public.orders (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    order_number text not null,
    external_order_id text,
    customer_id uuid references public.customers(id),
    financial_status text default 'pending',
    fulfillment_status text default 'unfulfilled',
    currency text default 'USD',
    subtotal integer not null default 0,
    total_tax integer default 0,
    total_shipping integer default 0,
    total_discounts integer default 0,
    total_amount integer not null,
    source_platform text,
    source_name text,
    tags text[],
    notes text,
    cancelled_at timestamptz,
    created_at timestamptz default now(),
    updated_at timestamptz
);
comment on table public.orders is 'Stores sales order information.';
create index if not exists idx_orders_company_id_created_at on public.orders(company_id, created_at desc);
create unique index if not exists idx_orders_company_external_id on public.orders(company_id, external_order_id);


create table if not exists public.order_line_items (
    id uuid primary key default gen_random_uuid(),
    order_id uuid not null references public.orders(id) on delete cascade,
    product_id uuid not null references public.products(id) on delete set null,
    variant_id uuid not null references public.product_variants(id) on delete set null,
    company_id uuid not null references public.companies(id) on delete cascade,
    product_name text not null,
    variant_title text,
    sku text,
    quantity integer not null,
    price integer not null,
    total_discount integer default 0,
    tax_amount integer default 0,
    cost_at_time integer,
    fulfillment_status text default 'unfulfilled',
    requires_shipping boolean default true,
    external_line_item_id text
);
comment on table public.order_line_items is 'Individual items within a sales order.';
create index if not exists idx_order_line_items_order_id on public.order_line_items(order_id);
create index if not exists idx_order_line_items_variant_id on public.order_line_items(variant_id);
create index if not exists idx_order_line_items_company_id on public.order_line_items(company_id);


-- 6. Supplier & Purchasing Tables
create table if not exists public.suppliers (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    name text not null,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz not null default now()
);
comment on table public.suppliers is 'Stores supplier information.';
create index if not exists idx_suppliers_company_id on public.suppliers(company_id);

create table if not exists public.purchase_orders (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    supplier_id uuid references public.suppliers(id) on delete set null,
    status text not null default 'Draft',
    po_number text not null,
    total_cost integer not null,
    expected_arrival_date date,
    idempotency_key uuid,
    created_at timestamptz not null default now()
);
comment on table public.purchase_orders is 'Stores purchase order information.';
create unique index if not exists idx_purchase_orders_idempotency_key on public.purchase_orders(idempotency_key);
create index if not exists idx_purchase_orders_company_id on public.purchase_orders(company_id);

create table if not exists public.purchase_order_line_items (
    id uuid primary key default uuid_generate_v4(),
    purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    quantity integer not null,
    cost integer not null
);
comment on table public.purchase_order_line_items is 'Individual items within a purchase order.';
create index if not exists idx_po_line_items_po_id on public.purchase_order_line_items(purchase_order_id);
create index if not exists idx_po_line_items_variant_id on public.purchase_order_line_items(variant_id);

-- 7. Configuration & App-specific Tables
create table if not exists public.integrations (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    platform platform_type not null,
    shop_domain text,
    shop_name text,
    is_active boolean default false,
    last_sync_at timestamptz,
    sync_status sync_status_type,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);
comment on table public.integrations is 'Stores configuration for third-party integrations.';
create unique index if not exists idx_integrations_company_platform on public.integrations(company_id, platform);

create table if not exists public.company_settings (
    company_id uuid primary key references public.companies(id) on delete cascade,
    dead_stock_days integer not null default 90,
    fast_moving_days integer not null default 30,
    overstock_multiplier integer not null default 3,
    high_value_threshold integer not null default 1000,
    predictive_stock_days integer not null default 7,
    promo_sales_lift_multiplier real not null default 2.5,
    currency text default 'USD',
    timezone text default 'UTC',
    tax_rate numeric default 0,
    subscription_status text default 'trial',
    subscription_plan text default 'starter',
    subscription_expires_at timestamptz,
    stripe_customer_id text,
    stripe_subscription_id text,
    custom_rules jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);
comment on table public.company_settings is 'Stores settings specific to each company.';

create table if not exists public.conversations (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid not null references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    title text not null,
    created_at timestamptz default now(),
    last_accessed_at timestamptz default now(),
    is_starred boolean default false
);
comment on table public.conversations is 'Stores AI chat conversation history.';

create table if not exists public.messages (
    id uuid primary key default uuid_generate_v4(),
    conversation_id uuid not null references public.conversations(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    role text not null,
    content text,
    component text,
    component_props jsonb,
    visualization jsonb,
    confidence numeric,
    assumptions text[],
    is_error boolean default false,
    created_at timestamptz default now()
);
comment on table public.messages is 'Stores individual messages within a conversation.';

create table if not exists public.audit_log (
    id bigserial primary key,
    company_id uuid references public.companies(id) on delete cascade,
    user_id uuid references auth.users(id) on delete set null,
    action text not null,
    details jsonb,
    created_at timestamptz default now()
);
comment on table public.audit_log is 'Logs significant user and system actions.';

create table if not exists public.webhook_events (
    id uuid primary key default gen_random_uuid(),
    integration_id uuid not null references public.integrations(id) on delete cascade,
    webhook_id text not null,
    created_at timestamptz default now(),
    processed_at timestamptz default now()
);
comment on table public.webhook_events is 'Prevents webhook replay attacks.';
create unique index if not exists idx_webhook_events_unique on public.webhook_events(integration_id, webhook_id);

-- 8. Functions & Triggers
-- Drop the old trigger if it exists from previous broken versions of this script.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();

-- This function is called by the application's signup action.
create or replace function public.handle_new_user()
returns uuid
language plpgsql
security definer -- a security definer function is required to create a company for a new user
set search_path = public
as $$
declare
  new_company_id uuid;
  new_user_id uuid := auth.uid();
  user_company_name text := current_setting('request.jwt.claims', true)::jsonb ->> 'company_name';
  user_email text := current_setting('request.jwt.claims', true)::jsonb ->> 'email';
begin
  -- Create a new company for the user
  insert into public.companies (name)
  values (user_company_name)
  returning id into new_company_id;

  -- Create a public user profile linked to the company
  insert into public.users (id, company_id, email, role)
  values (new_user_id, new_company_id, user_email, 'owner');

  -- Create a record in the join table
  insert into public.company_users (user_id, company_id, role)
  values (new_user_id, new_company_id, 'owner');

  return new_company_id;
end;
$$;
grant execute on function public.handle_new_user() to authenticated;


-- Helper function to get the current user's company_id from their JWT.
-- This is used in RLS policies.
create or replace function public.get_company_id()
returns uuid
language sql
stable
as $$
  select (nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid);
$$;

-- 9. Views (used for denormalized data access)
DROP VIEW IF EXISTS product_variants_with_details;
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT 
    pv.*,
    p.title as product_title,
    p.status as product_status,
    p.image_url
FROM 
    public.product_variants pv
JOIN 
    public.products p ON pv.product_id = p.id;

-- 10. Row-Level Security (RLS)
-- Enable RLS on all tables that contain company-specific data.
DO $$
DECLARE
    r record;
BEGIN
    FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename NOT LIKE 'pg_%' AND tablename NOT LIKE 'sql_%')
    LOOP
        EXECUTE 'ALTER TABLE public.' || quote_ident(r.tablename) || ' ENABLE ROW LEVEL SECURITY';
    END LOOP;
END$$;

-- Function to apply consistent RLS policies to tables
CREATE OR REPLACE PROCEDURE apply_rls_policies(table_name regclass)
LANGUAGE plpgsql
AS $$
DECLARE
    r record;
BEGIN
    -- Drop all existing policies on the table to ensure a clean slate
    FOR r IN (SELECT policyname FROM pg_policies WHERE tablename = table_name::text AND schemaname = 'public') LOOP
        EXECUTE 'DROP POLICY IF EXISTS ' || quote_ident(r.policyname) || ' ON ' || table_name;
    END LOOP;

    -- Generic policy for tables with a direct company_id column
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = table_name::text AND column_name = 'company_id'
    ) THEN
        EXECUTE format('CREATE POLICY "Allow full access to own company data" ON %I FOR ALL USING (company_id = public.get_company_id()) WITH CHECK (company_id = public.get_company_id())', table_name);
    END IF;
END;
$$;

-- Apply policies to all relevant tables
DO $$
DECLARE
    table_name text;
BEGIN
    FOR table_name IN 
        SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename NOT IN ('company_users', 'purchase_order_line_items', 'order_line_items')
    LOOP
        CALL apply_rls_policies(table_name::regclass);
    END LOOP;
END;
$$;

-- Custom policy for `companies` table (uses `id` instead of `company_id`)
DO $$
DECLARE
    r record;
BEGIN
    FOR r IN (SELECT policyname FROM pg_policies WHERE tablename = 'companies' AND schemaname = 'public') LOOP
        EXECUTE 'DROP POLICY IF EXISTS ' || quote_ident(r.policyname) || ' ON public.companies';
    END LOOP;
    CREATE POLICY "Allow read access to own company" ON public.companies FOR SELECT USING (id = public.get_company_id());
END;
$$;

-- Custom policy for `users` table
DO $$
DECLARE
    r record;
BEGIN
    FOR r IN (SELECT policyname FROM pg_policies WHERE tablename = 'users' AND schemaname = 'public') LOOP
        EXECUTE 'DROP POLICY IF EXISTS ' || quote_ident(r.policyname) || ' ON public.users';
    END LOOP;
    CREATE POLICY "Allow users to see other members of their company" ON public.users FOR SELECT USING (company_id = public.get_company_id());
    CREATE POLICY "Allow users to update their own record" ON public.users FOR UPDATE USING (id = auth.uid()) WITH CHECK (id = auth.uid());
END;
$$;

-- Custom policy for `company_users` table
DO $$
DECLARE
    r record;
BEGIN
    FOR r IN (SELECT policyname FROM pg_policies WHERE tablename = 'company_users' AND schemaname = 'public') LOOP
        EXECUTE 'DROP POLICY IF EXISTS ' || quote_ident(r.policyname) || ' ON public.company_users';
    END LOOP;
    CREATE POLICY "Allow users to access their own company_users record" ON public.company_users FOR ALL
        USING (company_id = public.get_company_id() AND user_id = auth.uid())
        WITH CHECK (company_id = public.get_company_id() AND user_id = auth.uid());
END;
$$;

-- Custom policy for `purchase_order_line_items` (checks parent company_id)
DO $$
DECLARE
    r record;
BEGIN
    FOR r IN (SELECT policyname FROM pg_policies WHERE tablename = 'purchase_order_line_items' AND schemaname = 'public') LOOP
        EXECUTE 'DROP POLICY IF EXISTS ' || quote_ident(r.policyname) || ' ON public.purchase_order_line_items';
    END LOOP;
    CREATE POLICY "Allow access based on parent purchase order" ON public.purchase_order_line_items FOR ALL
        USING (
            company_id = public.get_company_id()
        )
        WITH CHECK (
            company_id = public.get_company_id()
        );
END;
$$;

-- Custom policy for `order_line_items` (checks parent company_id)
DO $$
DECLARE
    r record;
BEGIN
    FOR r IN (SELECT policyname FROM pg_policies WHERE tablename = 'order_line_items' AND schemaname = 'public') LOOP
        EXECUTE 'DROP POLICY IF EXISTS ' || quote_ident(r.policyname) || ' ON public.order_line_items';
    END LOOP;
    CREATE POLICY "Allow access based on parent order" ON public.order_line_items FOR ALL
        USING (
           company_id = public.get_company_id()
        )
        WITH CHECK (
            company_id = public.get_company_id()
        );
END;
$$;

-- Grant usage on public schema to authenticated users
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- Grant access for service_role to bypass RLS (for background jobs)
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;

-- Grant access for anon role (for login/signup)
GRANT USAGE ON SCHEMA public TO anon;
GRANT SELECT ON public.companies TO anon;
