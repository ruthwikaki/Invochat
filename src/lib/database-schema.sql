-- InvoChat Database Schema
-- Version: 2.0.0
-- Description: This script sets up the entire database schema for InvoChat.
-- It is designed to be idempotent and can be run safely on new or existing databases.

-- =============================================
-- Extensions
-- =============================================
-- Enable UUID generation
create extension if not exists "uuid-ossp" with schema extensions;
-- Enable vector support for embeddings
create extension if not exists "vector" with schema extensions;
-- Enable cryptographic functions
create extension if not exists "pgcrypto" with schema extensions;

-- =============================================
-- Helper Functions
-- =============================================

-- Helper function to get the company_id from the JWT claims.
-- This is a security-critical function used in RLS policies.
drop function if exists public.get_company_id();
create or replace function public.get_company_id()
returns uuid
language sql
security definer
set search_path = public
as $$
  select (current_setting('request.jwt.claims', true)::jsonb ->> 'company_id')::uuid;
$$;

-- Helper function to get the user_id from the JWT claims.
drop function if exists public.get_user_id();
create or replace function public.get_user_id()
returns uuid
language sql
security definer
set search_path = public
as $$
  select (current_setting('request.jwt.claims', true)::jsonb ->> 'sub')::uuid;
$$;


-- =============================================
-- Cleanup Old Problematic Objects
-- =============================================
-- This section removes objects from previous, flawed versions of the schema
-- to ensure a clean slate for the correct definitions.

-- Drop the old trigger on auth.users if it exists (this was a permissions error source)
DO $$
BEGIN
   IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'on_auth_user_created') THEN
      DROP TRIGGER on_auth_user_created ON auth.users;
      RAISE NOTICE 'Dropped old trigger: on_auth_user_created';
   END IF;
END
$$;

-- Drop old, potentially problematic functions if they exist.
DROP FUNCTION IF EXISTS public.handle_new_user();


-- =============================================
-- Tables
-- =============================================

-- Companies Table
create table if not exists public.companies (
    id uuid not null default uuid_generate_v4() primary key,
    name text not null,
    created_at timestamptz not null default now()
);
comment on table public.companies is 'Stores information about each company tenant.';

-- Users Table (publicly accessible user data)
create table if not exists public.users (
    id uuid not null primary key, -- This is the foreign key to auth.users.id
    company_id uuid not null references public.companies(id) on delete cascade,
    email text,
    role text default 'Member'::text,
    deleted_at timestamptz,
    created_at timestamptz default now()
);
comment on table public.users is 'Stores public user information and links them to a company.';
create index if not exists users_company_id_idx on public.users (company_id);


-- Company Settings Table
create table if not exists public.company_settings (
    company_id uuid not null primary key references public.companies(id) on delete cascade,
    dead_stock_days integer not null default 90,
    fast_moving_days integer not null default 30,
    overstock_multiplier integer not null default 3,
    high_value_threshold integer not null default 1000,
    predictive_stock_days integer not null default 7,
    currency text default 'USD',
    timezone text default 'UTC',
    tax_rate numeric default 0,
    custom_rules jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz,
    subscription_status text default 'trial',
    subscription_plan text default 'starter',
    subscription_expires_at timestamptz,
    stripe_customer_id text,
    stripe_subscription_id text,
    promo_sales_lift_multiplier real not null default 2.5
);
comment on table public.company_settings is 'Tenant-specific business logic settings.';

-- Products Table
create table if not exists public.products (
    id uuid not null default uuid_generate_v4() primary key,
    company_id uuid not null references public.companies(id) on delete cascade,
    title text not null,
    description text,
    handle text,
    product_type text,
    tags text[],
    status text,
    image_url text,
    external_product_id text,
    created_at timestamptz not null default now(),
    updated_at timestamptz,
    fts_document tsvector
);
comment on table public.products is 'Core product information.';
create index if not exists products_company_id_idx on public.products (company_id);
create unique index if not exists products_company_external_id_unique_idx on public.products (company_id, external_product_id) where external_product_id is not null;
CREATE INDEX IF NOT EXISTS products_fts_document_idx ON public.products USING GIN (fts_document);


-- Product Variants Table
create table if not exists public.product_variants (
    id uuid not null default gen_random_uuid() primary key,
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
    location text,
    external_variant_id text,
    created_at timestamptz default now(),
    updated_at timestamptz default now()
);
comment on table public.product_variants is 'Specific variations of a product, like size or color.';
create index if not exists product_variants_product_id_idx on public.product_variants (product_id);
create index if not exists product_variants_company_id_idx on public.product_variants (company_id);
create index if not exists product_variants_sku_company_id_idx on public.product_variants (sku, company_id);
create unique index if not exists product_variants_company_external_id_unique_idx on public.product_variants (company_id, external_variant_id) where external_variant_id is not null;

-- Inventory Ledger Table
create table if not exists public.inventory_ledger (
    id uuid not null default gen_random_uuid() primary key,
    company_id uuid not null references public.companies(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    change_type text not null, -- e.g., 'sale', 'purchase_order', 'reconciliation', 'manual_adjustment'
    quantity_change integer not null,
    new_quantity integer not null,
    related_id uuid, -- e.g., order_id, purchase_order_id
    notes text,
    created_at timestamptz not null default now()
);
comment on table public.inventory_ledger is 'Transactional log of all stock movements.';
create index if not exists inventory_ledger_variant_id_company_id_idx on public.inventory_ledger (variant_id, company_id);
create index if not exists inventory_ledger_change_type_idx on public.inventory_ledger (change_type);
create index if not exists inventory_ledger_created_at_idx on public.inventory_ledger (created_at desc);

-- Suppliers Table
create table if not exists public.suppliers (
    id uuid not null default uuid_generate_v4() primary key,
    company_id uuid not null references public.companies(id) on delete cascade,
    name text not null,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz not null default now()
);
comment on table public.suppliers is 'Vendor information.';
create index if not exists suppliers_company_id_idx on public.suppliers (company_id);

-- Customers Table
create table if not exists public.customers (
    id uuid not null default uuid_generate_v4() primary key,
    company_id uuid not null references public.companies(id) on delete cascade,
    customer_name text not null,
    email text,
    total_orders integer default 0,
    total_spent integer default 0,
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz default now()
);
comment on table public.customers is 'Customer records.';
create index if not exists customers_company_id_idx on public.customers (company_id);

-- Orders Table
create table if not exists public.orders (
    id uuid not null default gen_random_uuid() primary key,
    company_id uuid not null references public.companies(id) on delete cascade,
    order_number text not null,
    external_order_id text,
    customer_id uuid references public.customers(id),
    status text not null default 'pending',
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
    updated_at timestamptz default now()
);
comment on table public.orders is 'Sales order information.';
create index if not exists orders_company_id_idx on public.orders (company_id);
create index if not exists orders_created_at_company_id_idx on public.orders (company_id, created_at desc);
create unique index if not exists orders_company_external_id_unique_idx on public.orders (company_id, external_order_id) where external_order_id is not null;

-- Order Line Items Table
create table if not exists public.order_line_items (
    id uuid not null default gen_random_uuid() primary key,
    order_id uuid not null references public.orders(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    product_id uuid references public.products(id),
    variant_id uuid references public.product_variants(id),
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
create index if not exists order_line_items_order_id_idx on public.order_line_items (order_id);
create index if not exists order_line_items_variant_id_idx on public.order_line_items (variant_id);

-- Purchase Orders Table
create table if not exists public.purchase_orders (
    id uuid not null default uuid_generate_v4() primary key,
    company_id uuid not null references public.companies(id) on delete cascade,
    supplier_id uuid references public.suppliers(id),
    status text not null default 'Draft',
    po_number text not null,
    total_cost integer not null,
    expected_arrival_date date,
    idempotency_key uuid,
    created_at timestamptz not null default now()
);
comment on table public.purchase_orders is 'Purchase orders sent to suppliers.';
create index if not exists purchase_orders_company_id_idx on public.purchase_orders (company_id);
create unique index if not exists po_company_idempotency_key_unique on public.purchase_orders(company_id, idempotency_key);

-- Purchase Order Line Items Table
create table if not exists public.purchase_order_line_items (
    id uuid not null default uuid_generate_v4() primary key,
    purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id),
    quantity integer not null,
    cost integer not null
);
comment on table public.purchase_order_line_items is 'Individual items within a purchase order.';
create index if not exists po_line_items_po_id_idx on public.purchase_order_line_items (purchase_order_id);
create index if not exists po_line_items_variant_id_idx on public.purchase_order_line_items (variant_id);

-- Integrations Table
create table if not exists public.integrations (
    id uuid not null default uuid_generate_v4() primary key,
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
comment on table public.integrations is 'Stores connection details for third-party platforms.';
create index if not exists integrations_company_id_idx on public.integrations (company_id);
create unique index if not exists integrations_company_id_platform_unique on public.integrations (company_id, platform);

-- Conversations Table (for AI Chat)
create table if not exists public.conversations (
    id uuid not null default uuid_generate_v4() primary key,
    user_id uuid not null references public.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    title text not null,
    created_at timestamptz default now(),
    last_accessed_at timestamptz default now(),
    is_starred boolean default false
);
comment on table public.conversations is 'Stores chat conversation history.';
create index if not exists conversations_user_id_idx on public.conversations (user_id);

-- Messages Table (for AI Chat)
create table if not exists public.messages (
    id uuid not null default uuid_generate_v4() primary key,
    conversation_id uuid not null references public.conversations(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    role text not null, -- 'user' or 'assistant'
    content text,
    component text,
    component_props jsonb,
    visualization jsonb,
    confidence numeric,
    assumptions text[],
    is_error boolean default false,
    created_at timestamptz default now()
);
comment on table public.messages is 'Individual messages within a chat conversation.';
create index if not exists messages_conversation_id_idx on public.messages (conversation_id);

-- Webhook Events Table (for preventing replay attacks)
create table if not exists public.webhook_events (
    id uuid not null default gen_random_uuid() primary key,
    integration_id uuid not null references public.integrations(id) on delete cascade,
    webhook_id text not null,
    processed_at timestamptz default now(),
    created_at timestamptz default now()
);
comment on table public.webhook_events is 'Logs processed webhooks to prevent replay attacks.';
create unique index if not exists webhook_events_integration_webhook_id_unique on public.webhook_events (integration_id, webhook_id);

-- Audit Log Table
create table if not exists public.audit_log (
    id bigserial primary key,
    company_id uuid references public.companies(id) on delete set null,
    user_id uuid references public.users(id) on delete set null,
    action text not null,
    details jsonb,
    created_at timestamptz default now()
);
comment on table public.audit_log is 'Records significant actions performed by users.';
create index if not exists audit_log_company_id_idx on public.audit_log (company_id);
create index if not exists audit_log_user_id_idx on public.audit_log (user_id);
create index if not exists audit_log_action_idx on public.audit_log (action);

-- Channel Fees Table (for net margin calculations)
create table if not exists public.channel_fees (
    id uuid not null default uuid_generate_v4() primary key,
    company_id uuid not null references public.companies(id) on delete cascade,
    channel_name text not null,
    percentage_fee numeric not null,
    fixed_fee numeric not null,
    created_at timestamptz default now(),
    updated_at timestamptz
);
comment on table public.channel_fees is 'Stores fee structures for different sales channels.';
create unique index if not exists channel_fees_company_channel_unique on public.channel_fees (company_id, channel_name);

-- =============================================
-- Account Setup and Management Functions
-- =============================================

-- This function is called by the application after a user signs up.
-- It creates the company, the public user record, and default settings.
create or replace function public.handle_new_user()
returns uuid
language plpgsql
security definer -- This is crucial for it to be able to write to tables
set search_path = public
as $$
declare
  new_company_id uuid;
  new_user_id uuid := auth.uid();
  company_name text := (current_setting('request.jwt.claims', true)::jsonb -> 'raw_app_meta_data' ->> 'company_name');
  user_email text := (current_setting('request.jwt.claims', true)::jsonb ->> 'email');
begin
  -- 1. Create a new company for the user
  insert into public.companies (name)
  values (company_name)
  returning id into new_company_id;

  -- 2. Create the corresponding public user record
  insert into public.users (id, company_id, email, role)
  values (new_user_id, new_company_id, user_email, 'Owner');

  -- 3. Create default settings for the new company
  insert into public.company_settings (company_id)
  values (new_company_id);

  -- 4. Update the user's app_metadata with the new company_id and role
  perform auth.update_user_app_metadata(new_user_id, jsonb_build_object(
      'company_id', new_company_id,
      'role', 'Owner'
  ));

  return new_company_id;
end;
$$;


-- =============================================
-- Row-Level Security (RLS) Policies
-- =============================================

-- This procedure is a helper to apply a standard RLS policy to multiple tables.
create or replace procedure public.apply_rls_policies(table_name regclass)
language plpgsql
as $$
begin
  -- Enable RLS on the table
  execute format('alter table %s enable row level security', table_name);

  -- Drop existing policy to ensure it can be replaced
  execute format('drop policy if exists "Allow all access to own company data" on %s', table_name);
  
  -- Create the new, correct policy
  -- For tables with a direct company_id column
  if exists (select 1 from information_schema.columns where table_name::regclass::text = columns.table_name and column_name = 'company_id') then
      execute format('create policy "Allow all access to own company data" on %s for all using (company_id = public.get_company_id()) with check (company_id = public.get_company_id())', table_name);
  -- Special handling for purchase_order_line_items
  elsif table_name = 'public.purchase_order_line_items'::regclass then
       execute format('create policy "Allow all access to own company data" on %s for all using (exists(select 1 from purchase_orders po where po.id = %s.purchase_order_id and po.company_id = public.get_company_id())) with check (exists(select 1 from purchase_orders po where po.id = %s.purchase_order_id and po.company_id = public.get_company_id()))', table_name, table_name, table_name);
  end if;

  -- Grant permissions to authenticated users
  execute format('grant select, insert, update, delete on %s to authenticated', table_name);
end;
$$;

-- Apply RLS to all relevant tables
do $$
declare
    table_name text;
begin
    for table_name in select tablename from pg_tables where schemaname = 'public' and tablename not in ('webhook_events') -- webhook_events is handled by service_role
    loop
        call public.apply_rls_policies(table_name::regclass);
    end loop;
end;
$$;


-- =============================================
-- Views (for denormalized data and analytics)
-- =============================================

-- Drop the view if it exists to handle potential column renames or type changes
drop view if exists public.product_variants_with_details;
-- Recreate the view with the correct definition
create or replace view public.product_variants_with_details as
select
    pv.*,
    p.title as product_title,
    p.status as product_status,
    p.image_url as image_url,
    p.product_type
from public.product_variants pv
join public.products p on pv.product_id = p.id;

-- Ensure RLS is also applied to the view
alter view public.product_variants_with_details owner to postgres;
drop policy if exists "Allow read access to own company data" on public.product_variants_with_details;
create policy "Allow read access to own company data" on public.product_variants_with_details for select using (company_id = public.get_company_id());
grant select on public.product_variants_with_details to authenticated;


-- =============================================
-- Grant Usage on Schemas
-- =============================================
grant usage on schema public to authenticated;
grant usage on schema public to service_role;

-- Grant permissions for all tables in the public schema to the service_role key
grant all on all tables in schema public to service_role;
grant all on all functions in schema public to service_role;
grant all on all sequences in schema public to service_role;

-- Grant permissions for anon key
grant usage on schema public to anon;
grant select on public.companies to anon; -- Example: if you need to check company existence publicly


-- Final notice
select 'Database schema setup and security policies applied successfully.' as "status";
