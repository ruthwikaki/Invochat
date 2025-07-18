
-- Enable UUID generation
create extension if not exists "uuid-ossp";

-- Grant auth schema usage to postgres role
grant usage on schema auth to postgres;
grant all on all tables in schema auth to postgres;
grant all on all functions in schema auth to postgres;
grant all on all sequences in schema auth to postgres;

-- Grant supabase_admin role to postgres
grant supabase_admin to postgres;

-- Define a custom type for user roles
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        create type public.user_role as enum ('Owner', 'Admin', 'Member');
    END IF;
END$$;


--------------------------------------------------------------------------------
-- TABLES
--------------------------------------------------------------------------------

-- Companies Table: Stores basic information about each company tenant.
create table if not exists public.companies (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  created_at timestamptz not null default now()
);

-- Users Table: Stores public user information and their role within a company.
create table if not exists public.users (
  id uuid references auth.users(id) on delete cascade primary key,
  company_id uuid not null references public.companies(id) on delete cascade,
  email text,
  role public.user_role default 'Member'::public.user_role,
  deleted_at timestamptz,
  created_at timestamptz default now()
);

-- Company Settings Table: Stores business logic settings for each company.
create table if not exists public.company_settings (
  company_id uuid references public.companies(id) on delete cascade primary key,
  dead_stock_days integer not null default 90,
  fast_moving_days integer not null default 30,
  overstock_multiplier integer not null default 3,
  high_value_threshold integer not null default 1000,
  predictive_stock_days integer not null default 7,
  currency text default 'USD',
  timezone text default 'UTC',
  tax_rate numeric default 0,
  promo_sales_lift_multiplier real not null default 2.5,
  subscription_status text default 'trial',
  subscription_plan text default 'starter',
  subscription_expires_at timestamptz,
  stripe_customer_id text,
  stripe_subscription_id text,
  custom_rules jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);

-- Products Table: Stores product-level information.
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
    created_at timestamptz not null default now(),
    updated_at timestamptz,
    deleted_at timestamptz,
    fts_document tsvector
);

-- Product Variants Table: Stores SKU-level information, inventory, and pricing.
create table if not exists public.product_variants (
    id uuid primary key default uuid_generate_v4(),
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
    updated_at timestamptz default now(),
    deleted_at timestamptz
);

-- Customers Table: Stores customer information.
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

-- Orders Table: Stores sales order headers.
create table if not exists public.orders (
    id uuid primary key default uuid_generate_v4(),
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
    updated_at timestamptz default now()
);

-- Order Line Items Table: Stores individual line items for each sales order.
create table if not exists public.order_line_items (
    id uuid primary key default uuid_generate_v4(),
    order_id uuid not null references public.orders(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    product_id uuid not null references public.products(id),
    variant_id uuid not null references public.product_variants(id),
    product_name text not null,
    variant_title text,
    sku text not null,
    quantity integer not null,
    price integer not null,
    cost_at_time integer,
    total_discount integer default 0,
    tax_amount integer default 0,
    fulfillment_status text default 'unfulfilled',
    requires_shipping boolean default true,
    external_line_item_id text
);

-- Suppliers Table: Stores vendor information.
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

-- Purchase Orders Table: Stores purchase order headers.
create table if not exists public.purchase_orders (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    supplier_id uuid references public.suppliers(id),
    status text not null default 'Draft',
    po_number text not null,
    total_cost integer not null,
    expected_arrival_date date,
    idempotency_key uuid,
    created_at timestamptz not null default now()
);

-- Purchase Order Line Items Table: Stores line items for each purchase order.
create table if not exists public.purchase_order_line_items (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id),
    quantity integer not null,
    cost integer not null
);

-- Integrations Table: Stores information about connected platforms.
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

-- Webhook Events Table: Stores webhook events to prevent replay attacks.
create table if not exists public.webhook_events (
    id uuid primary key default gen_random_uuid(),
    integration_id uuid not null references public.integrations(id) on delete cascade,
    webhook_id text not null,
    processed_at timestamptz default now(),
    created_at timestamptz default now()
);

-- Conversations Table: Stores chat history.
create table if not exists public.conversations (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid not null references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    title text not null,
    created_at timestamptz default now(),
    last_accessed_at timestamptz default now(),
    is_starred boolean default false
);

-- Messages Table: Stores individual chat messages.
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

-- Inventory Ledger Table: Tracks all inventory movements.
create table if not exists public.inventory_ledger (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id),
    change_type text not null,
    quantity_change integer not null,
    new_quantity integer not null,
    related_id uuid,
    notes text,
    created_at timestamptz not null default now()
);


--------------------------------------------------------------------------------
-- INDEXES
--------------------------------------------------------------------------------
-- Create indexes for frequently queried columns to improve performance.
create index if not exists idx_products_company_id on public.products(company_id);
create index if not exists idx_product_variants_company_sku on public.product_variants(company_id, sku);
create index if not exists idx_orders_company_id on public.orders(company_id);
create index if not exists idx_integrations_company_id on public.integrations(company_id);
create index if not exists idx_conversations_user_id on public.conversations(user_id);
create index if not exists idx_messages_conversation_id on public.messages(conversation_id);

--------------------------------------------------------------------------------
-- UNIQUE CONSTRAINTS
--------------------------------------------------------------------------------
alter table public.integrations drop constraint if exists integrations_company_id_platform_key;
alter table public.integrations add constraint integrations_company_id_platform_key unique (company_id, platform);

alter table public.webhook_events drop constraint if exists webhook_events_integration_id_webhook_id_key;
alter table public.webhook_events add constraint webhook_events_integration_id_webhook_id_key unique (integration_id, webhook_id);

--------------------------------------------------------------------------------
-- RLS (ROW-LEVEL SECURITY)
--------------------------------------------------------------------------------

-- Enable RLS for all relevant tables
alter table public.companies enable row level security;
alter table public.users enable row level security;
alter table public.company_settings enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.customers enable row level security;
alter table public.orders enable row level security;
alter table public.order_line_items enable row level security;
alter table public.suppliers enable row level security;
alter table public.purchase_orders enable row level security;
alter table public.purchase_order_line_items enable row level security;
alter table public.integrations enable row level security;
alter table public.webhook_events enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.inventory_ledger enable row level security;

-- Drop existing policies to ensure idempotency
drop policy if exists "Allow users to see their own company" on public.companies;
drop policy if exists "Allow users to manage their own public user profile" on public.users;
drop policy if exists "Allow users to manage their own company settings" on public.company_settings;
drop policy if exists "Allow users to manage products in their own company" on public.products;
drop policy if exists "Allow users to manage product variants in their own company" on public.product_variants;
drop policy if exists "Allow users to manage customers in their own company" on public.customers;
drop policy if exists "Allow users to manage orders in their own company" on public.orders;
drop policy if exists "Allow users to manage order line items in their own company" on public.order_line_items;
drop policy if exists "Allow users to manage suppliers in their own company" on public.suppliers;
drop policy if exists "Allow users to manage purchase orders in their own company" on public.purchase_orders;
drop policy if exists "Allow users to manage PO line items in their own company" on public.purchase_order_line_items;
drop policy if exists "Allow users to manage integrations in their own company" on public.integrations;
drop policy if exists "Allow users to manage webhook events in their own company" on public.webhook_events;
drop policy if exists "Allow users to manage their own conversations" on public.conversations;
drop policy if exists "Allow users to manage messages in their own company" on public.messages;
drop policy if exists "Allow users to manage inventory ledger in their own company" on public.inventory_ledger;

-- Define RLS policies
create policy "Allow users to see their own company" on public.companies for select using (id = (select get_company_id()));
create policy "Allow users to manage their own public user profile" on public.users for all using (id = auth.uid());
create policy "Allow users to manage their own company settings" on public.company_settings for all using (company_id = (select get_company_id()));
create policy "Allow users to manage products in their own company" on public.products for all using (company_id = (select get_company_id()));
create policy "Allow users to manage product variants in their own company" on public.product_variants for all using (company_id = (select get_company_id()));
create policy "Allow users to manage customers in their own company" on public.customers for all using (company_id = (select get_company_id()));
create policy "Allow users to manage orders in their own company" on public.orders for all using (company_id = (select get_company_id()));
create policy "Allow users to manage order line items in their own company" on public.order_line_items for all using (company_id = (select get_company_id()));
create policy "Allow users to manage suppliers in their own company" on public.suppliers for all using (company_id = (select get_company_id()));
create policy "Allow users to manage purchase orders in their own company" on public.purchase_orders for all using (company_id = (select get_company_id()));
create policy "Allow users to manage PO line items in their own company" on public.purchase_order_line_items for all using (company_id = (select get_company_id()));
create policy "Allow users to manage integrations in their own company" on public.integrations for all using (company_id = (select get_company_id()));
create policy "Allow users to manage webhook events in their own company" on public.webhook_events for all using (company_id = (select get_company_id()));
create policy "Allow users to manage their own conversations" on public.conversations for all using (user_id = auth.uid());
create policy "Allow users to manage messages in their own company" on public.messages for all using (company_id = (select get_company_id()));
create policy "Allow users to manage inventory ledger in their own company" on public.inventory_ledger for all using (company_id = (select get_company_id()));

--------------------------------------------------------------------------------
-- FUNCTIONS
--------------------------------------------------------------------------------
-- Function to get the company ID from the user's JWT claims.
create or replace function public.get_company_id()
returns uuid
language sql
security definer
stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid;
$$;


-- Function to create a new company and user profile upon signup
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
as $$
declare
  company_id uuid;
  user_id uuid := new.id;
  user_email text := new.email;
  company_name text := new.raw_app_meta_data->>'company_name';
begin
  -- Create a new company
  insert into public.companies (name)
  values (company_name)
  returning id into company_id;

  -- Create a corresponding public user profile
  insert into public.users (id, company_id, email, role)
  values (user_id, company_id, user_email, 'Owner');

  -- Update the user's app_metadata in auth.users with the new company_id and role
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id, 'role', 'Owner')
  where id = user_id;
  
  return new;
end;
$$;


--------------------------------------------------------------------------------
-- VIEWS
--------------------------------------------------------------------------------
-- View to combine product and variant information
create or replace view public.product_variants_with_details as
select
    pv.id,
    pv.product_id,
    pv.company_id,
    pv.sku,
    pv.title,
    pv.option1_name,
    pv.option1_value,
    pv.option2_name,
    pv.option2_value,
    pv.option3_name,
    pv.option3_value,
    pv.barcode,
    pv.price,
    pv.compare_at_price,
    pv.cost,
    pv.inventory_quantity,
    pv.location,
    pv.external_variant_id,
    pv.created_at,
    pv.updated_at,
    pv.deleted_at,
    p.title as product_title,
    p.status as product_status,
    p.image_url
from public.product_variants pv
join public.products p on pv.product_id = p.id;

--------------------------------------------------------------------------------
-- TRIGGERS
--------------------------------------------------------------------------------
-- Function to wrap trigger creation in a security definer context
create or replace function public.security_definer_handle_new_user()
returns void as $$
begin
    -- Drop trigger if it exists
    if exists (select 1 from pg_trigger where tgname = 'on_auth_user_created') then
        drop trigger on_auth_user_created on auth.users;
    end if;

    -- Create the trigger to call handle_new_user on new user signup
    create trigger on_auth_user_created
      after insert on auth.users
      for each row execute procedure public.handle_new_user();
end;
$$ language plpgsql security definer;

-- Execute the trigger creation
select public.security_definer_handle_new_user();

