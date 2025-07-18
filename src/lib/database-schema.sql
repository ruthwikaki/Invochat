--
-- Universal App Setup Script
--
-- This script is designed to be idempotent (can be run multiple times without causing errors)
-- and will set up the necessary tables, functions, triggers, and policies for the application.

-- 1. Enable UUID extension
create extension if not exists "uuid-ossp" with schema "extensions";

--
-- ===============================================================================================
--                                           TABLES
-- ===============================================================================================
--

-- Companies Table: Stores information about each company tenant.
create table if not exists public.companies (
    id uuid primary key default uuid_generate_v4(),
    name text not null,
    created_at timestamptz not null default now()
);
comment on table public.companies is 'Stores information about each company tenant.';

-- Users Table: Stores user profiles linked to companies.
create table if not exists public.users (
    id uuid primary key references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    email text,
    role text default 'Member' check (role in ('Owner', 'Admin', 'Member')),
    deleted_at timestamptz,
    created_at timestamptz default now()
);
comment on table public.users is 'Stores user profiles linked to companies.';

-- Company Settings Table: Stores settings for each company.
create table if not exists public.company_settings (
    company_id uuid primary key references public.companies(id) on delete cascade,
    dead_stock_days int not null default 90,
    fast_moving_days int not null default 30,
    overstock_multiplier int not null default 3,
    high_value_threshold int not null default 100000, -- Stored in cents
    predictive_stock_days int not null default 7,
    currency text default 'USD',
    timezone text default 'UTC',
    tax_rate numeric default 0,
    subscription_status text default 'trial',
    subscription_plan text default 'starter',
    subscription_expires_at timestamptz,
    stripe_customer_id text,
    stripe_subscription_id text,
    promo_sales_lift_multiplier real not null default 2.5,
    custom_rules jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);
comment on table public.company_settings is 'Stores settings for each company.';

-- Products Table: Core product information.
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
    deleted_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz,
    unique (company_id, external_product_id)
);
comment on table public.products is 'Core product information.';

-- Product Variants Table: Specific variations of products (e.g., size, color).
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
    deleted_at timestamptz,
    created_at timestamptz default now(),
    updated_at timestamptz default now(),
    unique(company_id, sku),
    unique(company_id, external_variant_id)
);
comment on table public.product_variants is 'Specific variations of products (e.g., size, color). Prices/costs stored in cents.';

-- Customers Table: Stores customer data.
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
comment on table public.customers is 'Stores customer data. Total spent is in cents.';

-- Orders Table: Records sales orders.
create table if not exists public.orders (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    order_number text not null,
    external_order_id text,
    customer_id uuid references public.customers(id),
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
comment on table public.orders is 'Records sales orders. All monetary values are in cents.';

-- Order Line Items Table: Items within an order.
create table if not exists public.order_line_items (
    id uuid primary key default gen_random_uuid(),
    order_id uuid not null references public.orders(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    product_id uuid not null references public.products(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    product_name text not null,
    variant_title text,
    sku text not null,
    quantity integer not null,
    price integer not null, -- in cents
    total_discount integer default 0, -- in cents
    tax_amount integer default 0, -- in cents
    fulfillment_status text default 'unfulfilled',
    requires_shipping boolean default true,
    external_line_item_id text,
    cost_at_time integer -- in cents
);
comment on table public.order_line_items is 'Items within an order. All monetary values are in cents.';

-- Suppliers Table: Stores vendor information.
create table if not exists public.suppliers (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    name text not null,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz not null default now(),
    unique(company_id, name)
);
comment on table public.suppliers is 'Stores vendor information.';

-- Purchase Orders Table: Records purchase orders.
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
comment on table public.purchase_orders is 'Records purchase orders. Total cost is in cents.';

-- Purchase Order Line Items Table: Items within a PO.
create table if not exists public.purchase_order_line_items (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    quantity integer not null,
    cost integer not null
);
comment on table public.purchase_order_line_items is 'Items within a PO. Cost is in cents.';

-- Inventory Ledger Table: Tracks all inventory movements.
create table if not exists public.inventory_ledger (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    change_type text not null,
    quantity_change integer not null,
    new_quantity integer not null,
    related_id uuid, -- e.g., order_id, purchase_order_id
    notes text,
    created_at timestamptz not null default now()
);
comment on table public.inventory_ledger is 'Tracks all inventory movements.';

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
    updated_at timestamptz,
    unique(company_id, platform)
);
comment on table public.integrations is 'Stores information about connected platforms.';

-- Conversations Table: For the AI chat feature.
create table if not exists public.conversations (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid not null references auth.users on delete cascade,
    company_id uuid not null references public.companies on delete cascade,
    title text not null,
    is_starred boolean default false,
    created_at timestamptz default now(),
    last_accessed_at timestamptz default now()
);
comment on table public.conversations is 'For the AI chat feature.';

-- Messages Table: Stores individual chat messages.
create table if not exists public.messages (
    id uuid primary key default uuid_generate_v4(),
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
comment on table public.messages is 'Stores individual chat messages.';

-- Audit Log Table: Tracks important system events.
create table if not exists public.audit_log (
    id bigserial primary key,
    company_id uuid references public.companies(id) on delete cascade,
    user_id uuid references auth.users(id) on delete set null,
    action text not null,
    details jsonb,
    created_at timestamptz default now()
);
comment on table public.audit_log is 'Tracks important system events.';

-- Webhook Events Table: Prevents replay attacks for webhooks.
create table if not exists public.webhook_events (
    id uuid primary key default gen_random_uuid(),
    integration_id uuid not null references public.integrations(id) on delete cascade,
    webhook_id text not null,
    processed_at timestamptz default now(),
    created_at timestamptz default now(),
    unique(integration_id, webhook_id)
);
comment on table public.webhook_events is 'Prevents replay attacks for webhooks.';


--
-- ===============================================================================================
--                                          FUNCTIONS
-- ===============================================================================================
--

-- Function to get the company_id from a JWT.
create or replace function get_company_id()
returns uuid
language sql
security definer
set search_path = public
as $$
    select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'app_metadata', '')::jsonb ->> 'company_id' from auth.users where id = auth.uid();
$$;

-- Function to get the user_id from a JWT.
create or replace function get_user_id()
returns uuid
language sql
security definer
as $$
  select auth.uid();
$$;

--
-- ===============================================================================================
--                                          POLICIES
-- ===============================================================================================
--
-- Enable RLS for all tables
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
alter table public.inventory_ledger enable row level security;
alter table public.integrations enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.audit_log enable row level security;
alter table public.webhook_events enable row level security;

-- Drop existing policies to ensure a clean slate
drop policy if exists "Users can only see their own company" on public.companies;
drop policy if exists "Users can see other users in their company" on public.users;
drop policy if exists "Users can see their own company settings" on public.company_settings;
drop policy if exists "Users can manage records in their own company" on public.products;
drop policy if exists "Users can manage records in their own company" on public.product_variants;
drop policy if exists "Users can manage records in their own company" on public.customers;
drop policy if exists "Users can manage records in their own company" on public.orders;
drop policy if exists "Users can manage records in their own company" on public.order_line_items;
drop policy if exists "Users can manage records in their own company" on public.suppliers;
drop policy if exists "Users can manage records in their own company" on public.purchase_orders;
drop policy if exists "Users can manage records in their own company" on public.purchase_order_line_items;
drop policy if exists "Users can manage records in their own company" on public.inventory_ledger;
drop policy if exists "Users can manage records in their own company" on public.integrations;
drop policy if exists "Users can manage their own conversations" on public.conversations;
drop policy if exists "Users can manage their own messages" on public.messages;
drop policy if exists "Admins can manage audit logs for their company" on public.audit_log;
drop policy if exists "Users can manage webhook events for their company" on public.webhook_events;

-- Policies for companies
create policy "Users can only see their own company" on public.companies
for select using (id = get_company_id());

-- Policies for users
create policy "Users can see other users in their company" on public.users
for select using (company_id = get_company_id());

-- Policies for company_settings
create policy "Users can see their own company settings" on public.company_settings
for all using (company_id = get_company_id());

-- Generic policies for most tables
create policy "Users can manage records in their own company" on public.products
for all using (company_id = get_company_id());

create policy "Users can manage records in their own company" on public.product_variants
for all using (company_id = get_company_id());

create policy "Users can manage records in their own company" on public.customers
for all using (company_id = get_company_id());

create policy "Users can manage records in their own company" on public.orders
for all using (company_id = get_company_id());

create policy "Users can manage records in their own company" on public.order_line_items
for all using (company_id = get_company_id());

create policy "Users can manage records in their own company" on public.suppliers
for all using (company_id = get_company_id());

create policy "Users can manage records in their own company" on public.purchase_orders
for all using (company_id = get_company_id());

create policy "Users can manage records in their own company" on public.purchase_order_line_items
for all using (company_id = get_company_id());

create policy "Users can manage records in their own company" on public.inventory_ledger
for all using (company_id = get_company_id());

create policy "Users can manage records in their own company" on public.integrations
for all using (company_id = get_company_id());

-- Policies for chat
create policy "Users can manage their own conversations" on public.conversations
for all using (user_id = auth.uid());

create policy "Users can manage their own messages" on public.messages
for all using (company_id = get_company_id());

-- Policies for audit log (Admins only)
create policy "Admins can manage audit logs for their company" on public.audit_log
for all using (company_id = get_company_id())
with check (
  (select role from public.users where id = auth.uid()) in ('Admin', 'Owner')
);

-- Policies for webhook events
create policy "Users can manage webhook events for their company" on public.webhook_events
for all using (
    integration_id in (select id from public.integrations where company_id = get_company_id())
);

--
-- ===============================================================================================
--                                         TRIGGERS
-- ===============================================================================================
--

-- Function to handle new user creation
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  company_id uuid;
  user_company_name text;
begin
  -- Extract company name from metadata, fallback to a default
  user_company_name := new.raw_app_meta_data->>'company_name';
  if user_company_name is null or user_company_name = '' then
    user_company_name := new.email || '''s Company';
  end if;

  -- Create a new company for the user
  insert into public.companies (name)
  values (user_company_name)
  returning id into company_id;

  -- Create a corresponding user profile
  insert into public.users (id, company_id, email, role)
  values (new.id, company_id, new.email, 'Owner');

  -- Create default settings for the new company
  insert into public.company_settings (company_id)
  values (company_id);
  
  -- Update the user's app_metadata in the auth schema
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id, 'role', 'Owner')
  where id = new.id;

  return new;
end;
$$;

-- Trigger to call handle_new_user on new user signup
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


-- Function to keep public.users.email in sync with auth.users.email
create or replace function public.sync_user_email()
returns trigger
language plpgsql
as $$
begin
  update public.users
  set email = new.email
  where id = new.id;
  return new;
end;
$$;

-- Trigger for email sync
drop trigger if exists on_auth_user_email_updated on auth.users;
create trigger on_auth_user_email_updated
  after update of email on auth.users
  for each row execute procedure public.sync_user_email();

--
-- ===============================================================================================
--                                         VIEWS
-- ===============================================================================================
--

-- View for product variants with essential product details
create or replace view public.product_variants_with_details as
select
  pv.*,
  p.title as product_title,
  p.status as product_status,
  p.image_url
from public.product_variants pv
join public.products p on pv.product_id = p.id;

-- View for customers with aggregated sales data
create or replace view public.customers_view as
select
    c.id,
    c.company_id,
    c.customer_name,
    c.email,
    c.deleted_at,
    c.created_at,
    count(o.id) as total_orders,
    coalesce(sum(o.total_amount), 0) as total_spent,
    min(o.created_at) as first_order_date
from public.customers c
left join public.orders o on c.id = o.customer_id
group by c.id;

-- View for orders with customer email
create or replace view public.orders_view as
select
    o.*,
    c.email as customer_email
from public.orders o
left join public.customers c on o.customer_id = c.id;

--
-- ===============================================================================================
--                                         END OF SCRIPT
-- ===============================================================================================
--
