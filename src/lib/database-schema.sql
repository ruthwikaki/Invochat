
-- InvoChat Database Schema
-- Version: 2.0
-- Description: Complete schema including tables, roles, functions, and RLS policies.
-- This script is designed to be idempotent and can be run multiple times safely.

-- Section 1: Extensions
-- Enable necessary extensions.
create extension if not exists "uuid-ossp" with schema extensions;
create extension if not exists pgroonga with schema extensions;


-- Section 2: Helper Functions
-- These functions are used by policies and triggers. They are dropped and recreated on each run.

drop function if exists public.get_current_user_role();
drop function if exists public.get_current_company_id();

create or replace function public.get_current_company_id()
returns uuid
language sql stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid;
$$;

create or replace function public.get_current_user_role()
returns text
language sql stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'role', '');
$$;


-- Section 3: Table Definitions
-- Create all tables with "IF NOT EXISTS" to ensure the script is idempotent.

create table if not exists public.companies (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    created_at timestamptz not null default now()
);

create table if not exists public.users (
    id uuid primary key references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    role text not null default 'Member' check (role in ('Owner', 'Admin', 'Member')),
    email text,
    deleted_at timestamptz,
    created_at timestamptz default now()
);

create table if not exists public.company_settings (
    company_id uuid primary key references public.companies(id) on delete cascade,
    dead_stock_days integer not null default 90,
    fast_moving_days integer not null default 30,
    predictive_stock_days integer not null default 7,
    overstock_multiplier integer not null default 3,
    high_value_threshold integer not null default 100000,
    currency text default 'USD',
    timezone text default 'UTC',
    tax_rate numeric default 0,
    promo_sales_lift_multiplier real not null default 2.5,
    custom_rules jsonb,
    subscription_status text default 'trial',
    subscription_plan text default 'starter',
    subscription_expires_at timestamptz,
    stripe_customer_id text,
    stripe_subscription_id text,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);

create table if not exists public.products (
    id uuid primary key default gen_random_uuid(),
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
    deleted_at timestamptz,
    unique(company_id, external_product_id)
);

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
    created_at timestamptz not null default now(),
    updated_at timestamptz,
    deleted_at timestamptz,
    unique(company_id, sku),
    unique(company_id, external_variant_id)
);

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

create table if not exists public.customers (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    customer_name text,
    email text,
    total_orders integer default 0,
    total_spent integer default 0,
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz default now()
);

create table if not exists public.orders (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    order_number text not null,
    external_order_id text,
    customer_id uuid references public.customers(id) on delete set null,
    financial_status text,
    fulfillment_status text,
    currency text,
    subtotal integer not null default 0,
    total_tax integer default 0,
    total_shipping integer default 0,
    total_discounts integer default 0,
    total_amount integer not null,
    source_platform text,
    created_at timestamptz not null default now(),
    updated_at timestamptz,
    unique(company_id, external_order_id)
);

create table if not exists public.order_line_items (
    id uuid primary key default gen_random_uuid(),
    order_id uuid not null references public.orders(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    variant_id uuid references public.product_variants(id) on delete set null,
    product_name text,
    variant_title text,
    sku text,
    quantity integer not null,
    price integer not null,
    total_discount integer default 0,
    tax_amount integer default 0,
    cost_at_time integer,
    external_line_item_id text
);

create table if not exists public.suppliers (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    name text not null,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz not null default now(),
    deleted_at timestamptz
);

create table if not exists public.conversations (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    title text not null,
    is_starred boolean default false,
    created_at timestamptz not null default now(),
    last_accessed_at timestamptz not null default now()
);

create table if not exists public.messages (
    id uuid primary key default gen_random_uuid(),
    conversation_id uuid not null references public.conversations(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    role text not null,
    content text,
    visualization jsonb,
    component text,
    component_props jsonb,
    confidence numeric,
    assumptions text[],
    is_error boolean default false,
    created_at timestamptz not null default now()
);

create table if not exists public.integrations (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    platform text not null,
    shop_domain text,
    shop_name text,
    is_active boolean default false,
    last_sync_at timestamptz,
    sync_status text,
    created_at timestamptz not null default now(),
    updated_at timestamptz,
    unique(company_id, platform)
);

create table if not exists public.channel_fees (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    channel_name text not null,
    percentage_fee numeric not null,
    fixed_fee numeric not null,
    created_at timestamptz default now(),
    updated_at timestamptz,
    unique(company_id, channel_name)
);

create table if not exists public.audit_log (
    id bigserial primary key,
    company_id uuid references public.companies(id) on delete cascade,
    user_id uuid references auth.users(id) on delete set null,
    action text not null,
    details jsonb,
    created_at timestamptz not null default now()
);

create table if not exists public.webhook_events (
    id uuid primary key default gen_random_uuid(),
    integration_id uuid not null references public.integrations(id) on delete cascade,
    webhook_id text not null,
    processed_at timestamptz not null default now(),
    unique(integration_id, webhook_id)
);

create table if not exists public.export_jobs (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    requested_by_user_id uuid not null references auth.users(id) on delete cascade,
    status text not null default 'pending',
    download_url text,
    expires_at timestamptz,
    created_at timestamptz not null default now()
);

create table if not exists public.user_feedback (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    subject_id text not null,
    subject_type text not null,
    feedback text not null, -- 'helpful' or 'unhelpful'
    created_at timestamptz not null default now()
);


-- Section 4: Database Functions & Triggers

-- Trigger to create a public user profile when a new auth user signs up
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  company_id uuid;
  user_email text;
begin
  -- First, create a company for the new user
  insert into public.companies (name)
  values (new.raw_app_meta_data ->> 'company_name')
  returning id into company_id;

  -- Then, insert a profile for the new user, linking them to the new company
  insert into public.users (id, company_id, role, email)
  values (new.id, company_id, 'Owner', new.email);
  
  -- Update the user's app_metadata with the new company_id and role
  update auth.users
  set raw_app_meta_data = new.raw_app_meta_data || jsonb_build_object('company_id', company_id, 'role', 'Owner')
  where id = new.id;
  
  return new;
end;
$$;

-- Drop trigger if it exists to ensure idempotency
drop trigger if exists on_auth_user_created on auth.users;
-- Create the trigger
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


-- Trigger to update product variant quantity from the inventory ledger
create or replace function public.update_variant_quantity_from_ledger()
returns trigger
language plpgsql
as $$
begin
  update public.product_variants
  set inventory_quantity = new.new_quantity
  where id = new.variant_id;
  return new;
end;
$$;

-- Drop trigger if it exists
drop trigger if exists on_inventory_ledger_insert on public.inventory_ledger;
-- Create the trigger
create trigger on_inventory_ledger_insert
  after insert on public.inventory_ledger
  for each row execute procedure public.update_variant_quantity_from_ledger();


-- Section 5: Indexes for Performance

create index if not exists idx_products_company_id on public.products(company_id);
create index if not exists idx_product_variants_product_id on public.product_variants(product_id);
create index if not exists idx_product_variants_company_sku on public.product_variants(company_id, sku);
create index if not exists idx_orders_company_created_at on public.orders(company_id, created_at desc);
create index if not exists idx_order_line_items_order_id on public.order_line_items(order_id);
create index if not exists idx_inventory_ledger_variant_id on public.inventory_ledger(variant_id);
create index if not exists idx_customers_company_id on public.customers(company_id);
create index if not exists idx_suppliers_company_id on public.suppliers(company_id);

-- Add PGroonga index for fast text search on products and variants
create index if not exists pgroonga_products_title_index on public.products using pgroonga (title);
create index if not exists pgroonga_variants_sku_index on public.product_variants using pgroonga (sku);


-- Section 6: Row Level Security (RLS)
-- Drop all policies first to handle dependencies, then re-create them.

-- Drop existing policies to ensure idempotency
drop policy if exists "Allow full access based on company_id" on public.companies;
drop policy if exists "Users can see other users in their own company." on public.users;
drop policy if exists "Allow read access to other users in same company" on public.users;
drop policy if exists "Allow user to update their own profile" on public.users;
drop policy if exists "Allow full access based on company_id" on public.company_settings;
drop policy if exists "Allow full access based on company_id" on public.products;
drop policy if exists "Allow full access based on company_id" on public.product_variants;
drop policy if exists "Allow full access based on company_id" on public.inventory_ledger;
drop policy if exists "Allow full access based on company_id" on public.customers;
drop policy if exists "Allow full access based on company_id" on public.orders;
drop policy if exists "Allow full access based on company_id" on public.order_line_items;
drop policy if exists "Allow full access based on company_id" on public.suppliers;
drop policy if exists "Allow full access to own conversations" on public.conversations;
drop policy if exists "Allow full access to messages in own conversations" on public.messages;
drop policy if exists "Allow full access based on company_id" on public.integrations;
drop policy if exists "Allow full access based on company_id" on public.channel_fees;
drop policy if exists "Allow full access based on company_id" on public.user_feedback;
drop policy if exists "Allow read access to company audit log" on public.audit_log;
drop policy if exists "Allow read access to webhook_events" on public.webhook_events;
drop policy if exists "Allow full access based on company_id" on public.export_jobs;

-- Enable RLS for all tables
alter table public.companies enable row level security;
alter table public.users enable row level security;
alter table public.company_settings enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.inventory_ledger enable row level security;
alter table public.customers enable row level security;
alter table public.orders enable row level security;
alter table public.order_line_items enable row level security;
alter table public.suppliers enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.integrations enable row level security;
alter table public.channel_fees enable row level security;
alter table public.audit_log enable row level security;
alter table public.webhook_events enable row level security;
alter table public.export_jobs enable row level security;
alter table public.user_feedback enable row level security;

-- RLS Policies Definitions
create policy "Allow full access based on company_id" on public.companies for all
  using (id = get_current_company_id())
  with check (id = get_current_company_id());

create policy "Users can see other users in their own company." on public.users for select
  using (company_id = get_current_company_id());
  
create policy "Allow user to update their own profile" on public.users for update
    using (id = auth.uid())
    with check (id = auth.uid());

create policy "Allow full access based on company_id" on public.company_settings for all
  using (company_id = get_current_company_id());

create policy "Allow full access based on company_id" on public.products for all
  using (company_id = get_current_company_id());

create policy "Allow full access based on company_id" on public.product_variants for all
  using (company_id = get_current_company_id());

create policy "Allow full access based on company_id" on public.inventory_ledger for all
  using (company_id = get_current_company_id());

create policy "Allow full access based on company_id" on public.customers for all
  using (company_id = get_current_company_id());

create policy "Allow full access based on company_id" on public.orders for all
  using (company_id = get_current_company_id());

create policy "Allow full access based on company_id" on public.order_line_items for all
  using (company_id = get_current_company_id());

create policy "Allow full access based on company_id" on public.suppliers for all
  using (company_id = get_current_company_id());

create policy "Allow full access to own conversations" on public.conversations for all
  using (user_id = auth.uid());

create policy "Allow full access to messages in own conversations" on public.messages for all
  using (company_id = get_current_company_id() and conversation_id in (select id from public.conversations where user_id = auth.uid()));

create policy "Allow full access based on company_id" on public.integrations for all
  using (company_id = get_current_company_id());
  
create policy "Allow full access based on company_id" on public.channel_fees for all
  using (company_id = get_current_company_id());

create policy "Allow full access based on company_id" on public.user_feedback for all
  using (company_id = get_current_company_id());

create policy "Allow read access to company audit log" on public.audit_log for select
  using (company_id = get_current_company_id());

create policy "Allow read access to webhook_events" on public.webhook_events for select
  using (integration_id in (select id from public.integrations where company_id = get_current_company_id()));

create policy "Allow full access based on company_id" on public.export_jobs for all
  using (company_id = get_current_company_id());

