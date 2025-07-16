-- ARVO Database Schema
-- Version: 2.1.0
-- This script is IDEMPOTENT and can be run safely multiple times.

-- ---------------------------------------------------------------------
-- SETUP EXTENSIONS
-- ---------------------------------------------------------------------
-- Enable the UUID extension if it's not already enabled.
create extension if not exists "uuid-ossp" with schema extensions;

-- ---------------------------------------------------------------------
-- HELPER FUNCTIONS
-- ---------------------------------------------------------------------
-- Helper function to get the company_id from the current user's JWT claims.
-- This is used in Row-Level Security (RLS) policies.
-- DROP and CREATE ensures we have the latest version of the function.
drop function if exists public.get_company_id();
create or replace function public.get_company_id()
returns uuid
language sql
stable
as $$
  select (nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid);
$$;


-- ---------------------------------------------------------------------
-- CLEANUP OLD, FAULTY OBJECTS
-- This section explicitly removes objects from previous, incorrect schema versions
-- to ensure this script can run successfully on a database that was set up
-- with a broken script.
-- ---------------------------------------------------------------------
-- Attempt to drop the faulty trigger on the protected auth.users table.
-- This will only succeed if run by a SUPERUSER, but we include it for cleanup.
DO $$
BEGIN
   IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'on_auth_user_created') THEN
      DROP TRIGGER on_auth_user_created ON auth.users;
   END IF;
EXCEPTION
   WHEN OTHERS THEN
      -- Ignore errors if the current user doesn't have permission,
      -- as the trigger is not used by the new schema anyway.
      RAISE NOTICE 'Could not drop trigger on_auth_user_created. This is expected if you are not a superuser.';
END;
$$;


-- ---------------------------------------------------------------------
-- TABLE CREATION
-- Using 'CREATE TABLE IF NOT EXISTS' for idempotency.
-- ---------------------------------------------------------------------

-- Stores company information
create table if not exists public.companies (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  created_at timestamptz not null default now()
);

-- Stores user profiles and links them to a company
create table if not exists public.users (
  id uuid primary key references auth.users(id) on delete cascade not null,
  company_id uuid references public.companies(id) on delete cascade not null,
  role text default 'Member' not null,
  email text,
  deleted_at timestamptz,
  created_at timestamptz default now()
);

-- Stores company-specific settings for business logic
create table if not exists public.company_settings (
    company_id uuid primary key references public.companies(id) on delete cascade not null,
    dead_stock_days integer not null default 90,
    fast_moving_days integer not null default 30,
    overstock_multiplier integer not null default 3,
    high_value_threshold integer not null default 100000, -- in cents
    predictive_stock_days integer not null default 7,
    currency text default 'USD',
    timezone text default 'UTC',
    tax_rate numeric default 0,
    custom_rules jsonb,
    subscription_status text default 'trial',
    subscription_plan text default 'starter',
    subscription_expires_at timestamptz,
    stripe_customer_id text,
    stripe_subscription_id text,
    promo_sales_lift_multiplier real not null default 2.5,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);

-- Stores products
create table if not exists public.products (
  id uuid primary key default uuid_generate_v4(),
  company_id uuid not null references public.companies(id) on delete cascade,
  title text not null,
  description text,
  handle text,
  product_type text,
  tags text[],
  status text default 'active',
  image_url text,
  external_product_id text,
  fts_document tsvector,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  unique(company_id, external_product_id)
);

-- Stores product variants (SKUs)
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
  price integer, -- in cents
  compare_at_price integer, -- in cents
  cost integer, -- in cents
  inventory_quantity integer not null default 0,
  location text,
  external_variant_id text,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  unique(company_id, sku),
  unique(company_id, external_variant_id)
);

-- Stores suppliers/vendors
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

-- Stores customer information
create table if not exists public.customers (
  id uuid primary key default uuid_generate_v4(),
  company_id uuid not null references public.companies(id) on delete cascade,
  customer_name text not null,
  email text,
  total_orders integer default 0,
  total_spent integer default 0, -- in cents
  first_order_date date,
  deleted_at timestamptz,
  created_at timestamptz default now()
);

-- Stores sales orders
create table if not exists public.orders (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    order_number text not null,
    external_order_id text,
    customer_id uuid references public.customers(id),
    status text not null default 'pending',
    financial_status text default 'pending',
    fulfillment_status text default 'unfulfilled',
    currency text default 'USD',
    subtotal integer not null default 0, -- in cents
    total_tax integer default 0, -- in cents
    total_shipping integer default 0, -- in cents
    total_discounts integer default 0, -- in cents
    total_amount integer not null, -- in cents
    source_platform text,
    source_name text,
    tags text[],
    notes text,
    cancelled_at timestamptz,
    created_at timestamptz default now(),
    updated_at timestamptz default now()
);

-- Stores line items for each sales order
create table if not exists public.order_line_items (
    id uuid primary key default gen_random_uuid(),
    order_id uuid not null references public.orders(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    product_id uuid references public.products(id),
    variant_id uuid references public.product_variants(id),
    product_name text not null,
    variant_title text,
    sku text,
    quantity integer not null,
    price integer not null, -- in cents
    total_discount integer default 0, -- in cents
    tax_amount integer default 0, -- in cents
    cost_at_time integer, -- in cents
    fulfillment_status text default 'unfulfilled',
    requires_shipping boolean default true,
    external_line_item_id text
);

-- Stores purchase orders
create table if not exists public.purchase_orders (
  id uuid primary key default uuid_generate_v4(),
  company_id uuid not null references public.companies(id) on delete cascade,
  supplier_id uuid references public.suppliers(id),
  status text not null default 'Draft',
  po_number text not null,
  total_cost integer not null, -- in cents
  expected_arrival_date date,
  idempotency_key uuid,
  created_at timestamptz not null default now()
);

-- Stores line items for each purchase order
create table if not exists public.purchase_order_line_items (
  id uuid primary key default uuid_generate_v4(),
  purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
  variant_id uuid not null references public.product_variants(id),
  quantity integer not null,
  cost integer not null -- in cents
);

-- Stores inventory movement history
create table if not exists public.inventory_ledger (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  variant_id uuid not null references public.product_variants(id),
  change_type text not null,
  quantity_change integer not null,
  new_quantity integer not null,
  related_id uuid,
  notes text,
  created_at timestamptz not null default now()
);

-- Stores platform integrations
create table if not exists public.integrations (
  id uuid primary key default uuid_generate_v4(),
  company_id uuid not null references public.companies(id) on delete cascade,
  platform text not null,
  shop_domain text,
  shop_name text,
  is_active boolean default false,
  last_sync_at timestamptz,
  sync_status text,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);

-- Stores chat conversation metadata
create table if not exists public.conversations (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid not null references public.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    title text not null,
    created_at timestamptz default now(),
    last_accessed_at timestamptz default now(),
    is_starred boolean default false
);

-- Stores individual chat messages
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

-- ---------------------------------------------------------------------
-- VIEWS
-- Using 'CREATE OR REPLACE VIEW' for idempotency.
-- ---------------------------------------------------------------------
-- Drop the view first to handle potential column renames or type changes.
DROP VIEW IF EXISTS public.product_variants_with_details;
-- A unified view for inventory display, joining products and variants.
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    v.id,
    v.product_id,
    p.title as product_title,
    p.status as product_status,
    p.image_url,
    v.sku,
    v.title,
    v.inventory_quantity,
    v.price,
    v.cost,
    v.location,
    v.company_id
FROM
    public.product_variants v
JOIN
    public.products p ON v.product_id = p.id;


-- ---------------------------------------------------------------------
-- DATABASE FUNCTIONS & TRIGGERS
-- Using 'DROP ... IF EXISTS' and 'CREATE' for idempotency.
-- ---------------------------------------------------------------------

-- Function to create a new company and user profile upon signup.
drop function if exists public.handle_new_user();
create function public.handle_new_user()
returns void
language plpgsql
security definer
as $$
declare
  v_company_id uuid;
  v_user_email text;
  v_company_name text;
begin
  -- Get company name from auth.users metadata, falling back to a default.
  v_company_name := (select raw_app_meta_data ->> 'company_name' from auth.users where id = auth.uid());
  if v_company_name is null or v_company_name = '' then
    v_company_name := 'My Company';
  end if;

  -- Create a new company
  insert into public.companies (name)
  values (v_company_name)
  returning id into v_company_id;

  -- Get the new user's email
  v_user_email := (select email from auth.users where id = auth.uid());

  -- Create a new user profile, linking them to the new company
  insert into public.users (id, company_id, role, email)
  values (auth.uid(), v_company_id, 'Owner', v_user_email);

  -- Update the user's app_metadata in the auth schema with the new company_id
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', v_company_id, 'role', 'Owner')
  where id = auth.uid();

  -- Create default settings for the new company
  insert into public.company_settings (company_id)
  values (v_company_id);
end;
$$;


-- ---------------------------------------------------------------------
-- ROW-LEVEL SECURITY (RLS)
-- This is a critical security layer.
-- ---------------------------------------------------------------------
-- This procedure drops and recreates RLS policies for a given table.
-- It standardizes the policy application, ensuring consistency.
create or replace procedure public.apply_rls_policies(
    table_name regclass,
    policy_type text default 'company'
)
language plpgsql
as $$
declare
    table_oid oid := table_name::oid;
    has_company_id_column boolean;
begin
    -- Check if the table has a 'company_id' column
    select exists (
        select 1
        from pg_attribute
        where attrelid = table_oid
        and attname = 'company_id'
        and not attisdropped
    ) into has_company_id_column;

    -- Drop existing policies to prevent conflicts
    execute format('DROP POLICY IF EXISTS "Allow all access to own company data" ON %I;', table_name);
    execute format('DROP POLICY IF EXISTS "Allow read access to own company data" ON %I;', table_name);

    if policy_type = 'user' and has_company_id_column then
        -- Policy for user-specific tables like 'conversations'
        execute format('CREATE POLICY "Allow all access to own company data" ON %I FOR ALL USING (company_id = public.get_company_id() AND user_id = auth.uid()) WITH CHECK (company_id = public.get_company_id() AND user_id = auth.uid());', table_name);
    elsif has_company_id_column then
        -- Standard policy for most tables with a company_id
        execute format('CREATE POLICY "Allow all access to own company data" ON %I FOR ALL USING (company_id = public.get_company_id()) WITH CHECK (company_id = public.get_company_id());', table_name);
    elsif table_name::text = 'public.companies' then
        -- Special policy for the companies table itself, checking its own id
        execute format('CREATE POLICY "Allow read access to own company" ON %I FOR SELECT USING (id = public.get_company_id());', table_name);
    elsif table_name::text = 'public.purchase_order_line_items' then
         -- Special policy for line items, checking through the parent PO
        execute format('CREATE POLICY "Allow all access via parent PO" ON %I FOR ALL USING (EXISTS (SELECT 1 FROM purchase_orders po WHERE po.id = purchase_order_id AND po.company_id = public.get_company_id()));', table_name);
    else
        -- Raise a notice if a table cannot be protected automatically
        raise notice 'Could not apply standard RLS policy to table %. It does not have a company_id column.', table_name;
    end if;
end;
$$;


-- A procedure to enable RLS and apply policies to all relevant tables.
create or replace procedure public.enable_all_rls()
language plpgsql
as $$
declare
    table_rec record;
begin
    for table_rec in (select tablename from pg_tables where schemaname = 'public')
    loop
        -- Enable RLS on the table
        execute format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', table_rec.tablename);
        
        -- Apply the appropriate policy
        if table_rec.tablename in ('conversations', 'messages') then
             call public.apply_rls_policies(table_rec.tablename::regclass, 'user');
        else
            call public.apply_rls_policies(table_rec.tablename::regclass, 'company');
        end if;
    end loop;
end;
$$;

-- Execute the procedure to apply RLS to all tables in the public schema.
CALL public.enable_all_rls();

-- Grant usage on the public schema to authenticated users
GRANT USAGE ON SCHEMA public TO authenticated;
-- Grant all permissions on all tables in the public schema to authenticated users
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO authenticated;

-- Grant usage for the extensions schema to authenticated role
GRANT USAGE ON SCHEMA extensions TO authenticated;

logger.info("Database schema setup/update complete.");