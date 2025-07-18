-- Enable UUID extension
create extension if not exists "uuid-ossp";

-- Grant usage on the 'auth' schema to the 'postgres' role
grant usage on schema auth to postgres;
grant all on all tables in schema auth to postgres;
grant all on all functions in schema auth to postgres;
grant all on all sequences in schema auth to postgres;

-- Create user_role type if it doesn't exist
do $$
begin
    if not exists (select 1 from pg_type where typname = 'user_role') then
        create type public.user_role as enum ('Owner', 'Admin', 'Member');
    end if;
end$$;

-- Custom Claim for Company ID
create or replace function public.get_company_id()
returns uuid
language sql stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid;
$$;

-- Custom Claim for User Role
create or replace function public.get_user_role()
returns text
language sql stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'user_role', '');
$$;

-- Function to get user ID from JWT
create or replace function public.get_user_id()
returns uuid
language sql stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'sub', '')::uuid;
$$;


-- Companies Table
create table if not exists public.companies (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  created_at timestamptz not null default now()
);

-- Users Table (public schema)
create table if not exists public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  email text,
  role user_role default 'Member',
  deleted_at timestamptz,
  created_at timestamptz default now()
);

-- Function to handle new user signup
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  company_id uuid;
  user_id uuid := new.id;
  user_email text := new.email;
  company_name text := new.raw_app_meta_data ->> 'company_name';
begin
  -- Create a new company for the user
  insert into public.companies (name)
  values (coalesce(company_name, 'My Company'))
  returning id into company_id;

  -- Create a corresponding user in the public.users table
  insert into public.users (id, company_id, email, role)
  values (user_id, company_id, user_email, 'Owner');

  -- Update the user's app_metadata with the new company_id and role
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id, 'user_role', 'Owner')
  where id = user_id;

  return new;
end;
$$;


-- Trigger to call handle_new_user on new user signup
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


-- Row Level Security (RLS) Policies

-- Policies for companies table
alter table public.companies enable row level security;
drop policy if exists "Allow users to see their own company" on public.companies;
create policy "Allow users to see their own company" on public.companies for select using (id = get_company_id());

-- Policies for users table
alter table public.users enable row level security;
drop policy if exists "Allow users to see other users in their company" on public.users;
create policy "Allow users to see other users in their company" on public.users for select using (company_id = get_company_id());
drop policy if exists "Allow owners to manage users in their company" on public.users;
create policy "Allow owners to manage users in their company" on public.users for all using (company_id = get_company_id() and get_user_role() = 'Owner');


-- Products Table
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
  fts_document tsvector,
  deleted_at timestamptz
);
alter table public.products enable row level security;
drop policy if exists "Allow users to manage products in their company" on public.products;
create policy "Allow users to manage products in their company" on public.products for all using (company_id = get_company_id());


-- Product Variants Table
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
  price int,
  compare_at_price int,
  cost int,
  inventory_quantity int not null default 0,
  external_variant_id text,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  location text,
  deleted_at timestamptz
);
alter table public.product_variants enable row level security;
drop policy if exists "Allow users to manage variants in their company" on public.product_variants;
create policy "Allow users to manage variants in their company" on public.product_variants for all using (company_id = get_company_id());

-- Customers Table
create table if not exists public.customers (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    customer_name text not null,
    email text,
    total_orders int default 0,
    total_spent int default 0,
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz default now()
);
alter table public.customers enable row level security;
drop policy if exists "Allow users to manage customers in their company" on public.customers;
create policy "Allow users to manage customers in their company" on public.customers for all using (company_id = get_company_id());


-- Orders Table
create table if not exists public.orders (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    order_number text not null,
    external_order_id text,
    customer_id uuid references public.customers(id),
    financial_status text default 'pending',
    fulfillment_status text default 'unfulfilled',
    currency text default 'USD',
    subtotal int not null default 0,
    total_tax int default 0,
    total_shipping int default 0,
    total_discounts int default 0,
    total_amount int not null,
    source_platform text,
    source_name text,
    tags text[],
    notes text,
    cancelled_at timestamptz,
    created_at timestamptz default now(),
    updated_at timestamptz default now()
);
alter table public.orders enable row level security;
drop policy if exists "Allow users to manage orders in their company" on public.orders;
create policy "Allow users to manage orders in their company" on public.orders for all using (company_id = get_company_id());

-- Order Line Items Table
create table if not exists public.order_line_items (
    id uuid primary key default gen_random_uuid(),
    order_id uuid not null references public.orders(id) on delete cascade,
    product_id uuid not null references public.products(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    product_name text not null,
    variant_title text,
    sku text not null,
    quantity int not null,
    price int not null,
    total_discount int default 0,
    tax_amount int default 0,
    cost_at_time int,
    fulfillment_status text default 'unfulfilled',
    requires_shipping boolean default true,
    external_line_item_id text
);
alter table public.order_line_items enable row level security;
drop policy if exists "Allow users to manage order line items in their company" on public.order_line_items;
create policy "Allow users to manage order line items in their company" on public.order_line_items for all using (company_id = get_company_id());

-- Suppliers Table
create table if not exists public.suppliers (
  id uuid primary key default uuid_generate_v4(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  email text,
  phone text,
  default_lead_time_days int,
  notes text,
  created_at timestamptz not null default now()
);
alter table public.suppliers enable row level security;
drop policy if exists "Allow users to manage suppliers in their company" on public.suppliers;
create policy "Allow users to manage suppliers in their company" on public.suppliers for all using (company_id = get_company_id());

-- Purchase Orders Table
create table if not exists public.purchase_orders (
  id uuid primary key default uuid_generate_v4(),
  company_id uuid not null references public.companies(id) on delete cascade,
  supplier_id uuid references public.suppliers(id),
  status text not null default 'Draft',
  po_number text not null,
  total_cost int not null,
  expected_arrival_date date,
  created_at timestamptz not null default now(),
  idempotency_key uuid
);
alter table public.purchase_orders enable row level security;
drop policy if exists "Allow users to manage purchase orders in their company" on public.purchase_orders;
create policy "Allow users to manage purchase orders in their company" on public.purchase_orders for all using (company_id = get_company_id());

-- Purchase Order Line Items Table
create table if not exists public.purchase_order_line_items (
    id uuid primary key default uuid_generate_v4(),
    purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    quantity int not null,
    cost int not null
);
alter table public.purchase_order_line_items enable row level security;
drop policy if exists "Allow users to manage PO line items in their company" on public.purchase_order_line_items;
create policy "Allow users to manage PO line items in their company" on public.purchase_order_line_items for all using (company_id = get_company_id());


-- Company Settings Table
create table if not exists public.company_settings (
  company_id uuid primary key references public.companies(id) on delete cascade,
  dead_stock_days int not null default 90,
  fast_moving_days int not null default 30,
  overstock_multiplier int not null default 3,
  high_value_threshold int not null default 1000,
  predictive_stock_days int not null default 7,
  currency text default 'USD',
  timezone text default 'UTC',
  tax_rate numeric default 0,
  custom_rules jsonb,
  promo_sales_lift_multiplier real not null default 2.5,
  subscription_status text default 'trial',
  subscription_plan text default 'starter',
  subscription_expires_at timestamptz,
  stripe_customer_id text,
  stripe_subscription_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);
alter table public.company_settings enable row level security;
drop policy if exists "Allow users to manage settings for their own company" on public.company_settings;
create policy "Allow users to manage settings for their own company" on public.company_settings for all using (company_id = get_company_id());

-- Integrations Table
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
alter table public.integrations enable row level security;
drop policy if exists "Allow users to manage integrations for their own company" on public.integrations;
create policy "Allow users to manage integrations for their own company" on public.integrations for all using (company_id = get_company_id());

-- Conversations Table
create table if not exists public.conversations (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid not null references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    title text not null,
    created_at timestamptz default now(),
    last_accessed_at timestamptz default now(),
    is_starred boolean default false
);
alter table public.conversations enable row level security;
drop policy if exists "Users can manage their own conversations" on public.conversations;
create policy "Users can manage their own conversations" on public.conversations for all using (user_id = get_user_id());


-- Messages Table
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
alter table public.messages enable row level security;
drop policy if exists "Allow users to manage messages in their company" on public.messages;
create policy "Allow users to manage messages in their company" on public.messages for all using (company_id = get_company_id());

-- Webhook Events Table
create table if not exists public.webhook_events (
    id uuid primary key default gen_random_uuid(),
    integration_id uuid not null references public.integrations(id) on delete cascade,
    webhook_id text not null,
    processed_at timestamptz default now(),
    created_at timestamptz default now(),
    unique(integration_id, webhook_id)
);
alter table public.webhook_events enable row level security;
drop policy if exists "Allow system to manage webhooks" on public.webhook_events;
create policy "Allow system to manage webhooks" on public.webhook_events for all using (true); -- Managed by service_role key


-- Channel Fees Table
create table if not exists public.channel_fees (
  id uuid primary key default uuid_generate_v4(),
  company_id uuid not null references public.companies(id) on delete cascade,
  channel_name text not null,
  percentage_fee numeric not null,
  fixed_fee numeric not null,
  created_at timestamptz default now(),
  updated_at timestamptz
);
alter table public.channel_fees enable row level security;
drop policy if exists "Allow users to manage channel fees in their company" on public.channel_fees;
create policy "Allow users to manage channel fees in their company" on public.channel_fees for all using (company_id = get_company_id());

-- Create a unique index on company_id and channel_name
create unique index if not exists channel_fees_company_id_channel_name_idx on public.channel_fees (company_id, channel_name);

-- Inventory Ledger Table
create table if not exists public.inventory_ledger (
  id uuid primary key default gen_random_uuid(),
  variant_id uuid not null references public.product_variants(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  change_type text not null,
  quantity_change int not null,
  new_quantity int not null,
  related_id uuid,
  notes text,
  created_at timestamptz not null default now()
);
alter table public.inventory_ledger enable row level security;
drop policy if exists "Allow users to manage inventory ledger in their company" on public.inventory_ledger;
create policy "Allow users to manage inventory ledger in their company" on public.inventory_ledger for all using (company_id = get_company_id());
create index if not exists idx_inventory_ledger_variant_id on public.inventory_ledger(variant_id);


--
-- Add more tables here as needed
-- Refunds, Discounts, Customer Addresses, etc.
--

create table if not exists public.refunds (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    order_id uuid not null references public.orders(id) on delete cascade,
    refund_number text not null,
    status text not null default 'pending',
    reason text,
    note text,
    total_amount int not null,
    created_by_user_id uuid references auth.users(id),
    external_refund_id text,
    created_at timestamptz default now()
);

create table if not exists public.refund_line_items (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    refund_id uuid not null references public.refunds(id) on delete cascade,
    order_line_item_id uuid not null references public.order_line_items(id) on delete cascade,
    quantity int not null,
    amount int not null,
    restock boolean default true
);

create table if not exists public.discounts (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    code text not null,
    type text not null, -- 'percentage', 'fixed_amount'
    value int not null,
    minimum_purchase int,
    usage_limit int,
    usage_count int default 0,
    applies_to text default 'all', -- 'all', 'products', 'collections'
    starts_at timestamptz,
    ends_at timestamptz,
    is_active boolean default true,
    created_at timestamptz default now()
);

create table if not exists public.customer_addresses (
    id uuid primary key default gen_random_uuid(),
    customer_id uuid not null references public.customers(id) on delete cascade,
    address_type text not null default 'shipping',
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
    is_default boolean default false
);

create table if not exists public.export_jobs (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    requested_by_user_id uuid not null references auth.users(id),
    status text not null default 'pending',
    download_url text,
    expires_at timestamptz,
    created_at timestamptz not null default now()
);
alter table public.export_jobs enable row level security;
drop policy if exists "Allow users to see their own export jobs" on public.export_jobs;
create policy "Allow users to see their own export jobs" on public.export_jobs for select using (requested_by_user_id = get_user_id());


-- Audit Log Table
create table if not exists public.audit_log (
    id bigserial primary key,
    company_id uuid references public.companies(id),
    user_id uuid references auth.users(id),
    action text not null,
    details jsonb,
    created_at timestamptz default now()
);
alter table public.audit_log enable row level security;
drop policy if exists "Allow admins/owners to view audit logs for their company" on public.audit_log;
create policy "Allow admins/owners to view audit logs for their company" on public.audit_log for select using (company_id = get_company_id() and get_user_role() in ('Admin', 'Owner'));

-- Unique constraints
alter table public.product_variants add constraint product_variants_company_id_sku_key unique (company_id, sku);
alter table public.integrations add constraint integrations_company_id_platform_key unique (company_id, platform);

-- Indexes for performance
create index if not exists idx_product_variants_company_id_sku on public.product_variants (company_id, sku);
create index if not exists idx_orders_company_id_created_at on public.orders (company_id, created_at desc);
create index if not exists idx_customers_company_id on public.customers (company_id);

-- This is a sample function. You may want to expand it based on your needs.
create or replace function public.check_user_permission(p_user_id uuid, p_required_role text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
    user_role_text text;
begin
    select role into user_role_text from public.users where id = p_user_id;

    if p_required_role = 'Owner' then
        return user_role_text = 'Owner';
    elsif p_required_role = 'Admin' then
        return user_role_text in ('Owner', 'Admin');
    end if;
    return false;
end;
$$;
