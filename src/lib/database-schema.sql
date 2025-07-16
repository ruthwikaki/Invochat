
-- ### InvoChat Database Schema ###
-- This schema is designed for a multi-tenant inventory management system.
-- It uses Row-Level Security (RLS) to ensure that users can only access data belonging to their company.
-- Version: 2.0

-- ### Extensions ###
-- Enable the pgcrypto extension for generating UUIDs.
create extension if not exists "pgcrypto" with schema "extensions";
-- Enable the pg_stat_statements extension for monitoring query performance.
create extension if not exists "pg_stat_statements" with schema "extensions";
-- Enable the citext extension for case-insensitive text comparisons (useful for emails, etc.).
create extension if not exists "citext" with schema "extensions";


-- ### Helper Functions ###

-- Function to get the company_id from a user's JWT claims.
-- This is the core of our multi-tenancy enforcement.
create or replace function auth.get_company_id()
returns uuid
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid;
$$;

-- Function to get the user's role within their company from the JWT claims.
create or replace function auth.get_company_role()
returns text
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'company_role', '');
$$;

-- Function to check if a user is an admin or owner of their company.
create or replace function auth.is_company_admin()
returns boolean
language sql
stable
as $$
  select auth.get_company_role() in ('Admin', 'Owner');
$$;


-- ### Tables ###

-- Table: companies
-- Stores information about each company (tenant) in the system.
create table if not exists public.companies (
  id uuid default extensions.uuid_generate_v4() primary key,
  name text not null,
  created_at timestamptz default now() not null,
  updated_at timestamptz
);
-- RLS Policy: Only authenticated users belonging to the company can select their company's data.
-- No user should be able to update or delete a company record directly.
alter table public.companies enable row level security;
drop policy if exists "select_own_company" on public.companies;
create policy "select_own_company" on public.companies
  for select
  using (id = auth.get_company_id());

-- Table: users
-- This table is managed by Supabase Auth. We add a few app-specific columns.
-- Note: We don't store passwords here; that's handled by Supabase Auth.
-- The `company_id` and `company_role` are stored in `auth.users.raw_app_meta_data`.

-- Table: company_users
-- A junction table to link users to companies and assign them roles.
create table if not exists public.company_users (
    id uuid default extensions.uuid_generate_v4() primary key,
    company_id uuid references public.companies on delete cascade not null,
    user_id uuid references auth.users on delete cascade not null,
    role text check (role in ('Owner', 'Admin', 'Member')) default 'Member' not null,
    created_at timestamptz default now() not null,
    unique(company_id, user_id)
);
-- RLS Policy: Users can only see their own entry in the company_users table.
-- Admins can see all users within their company.
alter table public.company_users enable row level security;
drop policy if exists "manage_company_users" on public.company_users;
create policy "manage_company_users" on public.company_users
  for all
  using (company_id = auth.get_company_id())
  with check (company_id = auth.get_company_id() and auth.is_company_admin());

-- Table: company_settings
-- Stores settings specific to each company, like alert thresholds.
create table if not exists public.company_settings (
    company_id uuid references public.companies on delete cascade not null primary key,
    dead_stock_days int default 90 not null,
    fast_moving_days int default 30 not null,
    overstock_multiplier numeric default 3.0 not null,
    high_value_threshold int default 100000 not null, -- in cents
    predictive_stock_days int default 7 not null,
    currency text default 'USD' not null,
    tax_rate numeric default 0.0,
    timezone text default 'UTC' not null,
    created_at timestamptz default now() not null,
    updated_at timestamptz
);
-- RLS Policy: Users can read their own company settings. Only admins can update them.
alter table public.company_settings enable row level security;
drop policy if exists "manage_own_company_settings" on public.company_settings;
create policy "manage_own_company_settings" on public.company_settings
    for all
    using (company_id = auth.get_company_id())
    with check (company_id = auth.get_company_id() and auth.is_company_admin());


-- Table: products
-- Stores the parent product information.
create table if not exists public.products (
  id uuid default extensions.uuid_generate_v4() primary key,
  company_id uuid references public.companies on delete cascade not null,
  title text not null,
  description text,
  handle text,
  product_type text,
  tags text[],
  status text,
  image_url text,
  external_product_id text,
  created_at timestamptz default now() not null,
  updated_at timestamptz,
  unique(company_id, external_product_id)
);
-- RLS Policy: Users can manage products within their own company. Admins only for write.
alter table public.products enable row level security;
drop policy if exists "manage_own_company_products" on public.products;
create policy "manage_own_company_products" on public.products
  for all
  using (company_id = auth.get_company_id())
  with check (company_id = auth.get_company_id() and auth.is_company_admin());


-- Table: product_variants
-- Stores individual product variants (SKUs).
create table if not exists public.product_variants (
  id uuid default extensions.uuid_generate_v4() primary key,
  product_id uuid references public.products on delete cascade not null,
  company_id uuid references public.companies on delete cascade not null,
  sku text not null,
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
  inventory_quantity int default 0 not null,
  location text,
  external_variant_id text,
  created_at timestamptz default now() not null,
  updated_at timestamptz,
  unique(company_id, sku)
);
-- RLS Policy: Users can manage variants within their own company. Admins only for write.
alter table public.product_variants enable row level security;
drop policy if exists "manage_own_company_variants" on public.product_variants;
create policy "manage_own_company_variants" on public.product_variants
  for all
  using (company_id = auth.get_company_id())
  with check (company_id = auth.get_company_id() and auth.is_company_admin());


-- Table: suppliers
-- Stores supplier/vendor information.
create table if not exists public.suppliers (
  id uuid default extensions.uuid_generate_v4() primary key,
  company_id uuid references public.companies on delete cascade not null,
  name text not null,
  email text,
  phone text,
  default_lead_time_days int,
  notes text,
  created_at timestamptz default now() not null,
  updated_at timestamptz
);
-- RLS Policy: Users can manage suppliers within their own company. Admins only for write.
alter table public.suppliers enable row level security;
drop policy if exists "manage_own_company_suppliers" on public.suppliers;
create policy "manage_own_company_suppliers" on public.suppliers
  for all
  using (company_id = auth.get_company_id())
  with check (company_id = auth.get_company_id() and auth.is_company_admin());


-- Table: customers
-- Stores customer information, aggregated from orders.
create table if not exists public.customers (
  id uuid default extensions.uuid_generate_v4() primary key,
  company_id uuid references public.companies on delete cascade not null,
  customer_name text,
  email citext,
  total_orders int default 0 not null,
  total_spent int default 0 not null, -- in cents
  first_order_date timestamptz,
  created_at timestamptz default now() not null,
  deleted_at timestamptz,
  unique(company_id, email)
);
-- RLS Policy: Users can manage customers within their own company. Admins only for write.
alter table public.customers enable row level security;
drop policy if exists "manage_own_company_customers" on public.customers;
create policy "manage_own_company_customers" on public.customers
  for all
  using (company_id = auth.get_company_id())
  with check (company_id = auth.get_company_id() and auth.is_company_admin());


-- Table: orders
-- Stores order information from integrations.
create table if not exists public.orders (
    id uuid default extensions.uuid_generate_v4() primary key,
    company_id uuid references public.companies on delete cascade not null,
    order_number text not null,
    external_order_id text,
    customer_id uuid references public.customers on delete set null,
    financial_status text,
    fulfillment_status text,
    currency text,
    subtotal int, -- in cents
    total_tax int,
    total_shipping int,
    total_discounts int,
    total_amount int not null,
    source_platform text,
    created_at timestamptz default now() not null,
    updated_at timestamptz,
    unique(company_id, external_order_id, source_platform)
);
-- RLS Policy: Users can read orders within their own company.
alter table public.orders enable row level security;
drop policy if exists "select_own_company_orders" on public.orders;
create policy "select_own_company_orders" on public.orders
  for select
  using (company_id = auth.get_company_id());


-- Table: order_line_items
-- Stores line items for each order.
create table if not exists public.order_line_items (
    id uuid default extensions.uuid_generate_v4() primary key,
    order_id uuid references public.orders on delete cascade not null,
    variant_id uuid references public.product_variants on delete set null,
    company_id uuid references public.companies on delete cascade not null,
    product_name text,
    variant_title text,
    sku text,
    quantity int not null,
    price int not null, -- in cents
    total_discount int,
    tax_amount int,
    cost_at_time int,
    external_line_item_id text
);
-- RLS Policy: Users can read line items within their own company.
alter table public.order_line_items enable row level security;
drop policy if exists "select_own_company_line_items" on public.order_line_items;
create policy "select_own_company_line_items" on public.order_line_items
  for select
  using (company_id = auth.get_company_id());


-- Table: inventory_ledger
-- Tracks every change in inventory quantity for auditing.
create table if not exists public.inventory_ledger (
  id bigint generated by default as identity primary key,
  company_id uuid references public.companies on delete cascade not null,
  variant_id uuid references public.product_variants on delete cascade not null,
  change_type text not null, -- e.g., 'sale', 'purchase_order', 'manual_adjustment', 'reconciliation'
  quantity_change int not null,
  new_quantity int not null,
  related_id uuid, -- e.g., order_id, purchase_order_id
  notes text,
  created_at timestamptz default now() not null
);
-- RLS Policy: Users can read ledger entries within their own company.
alter table public.inventory_ledger enable row level security;
drop policy if exists "select_own_company_ledger" on public.inventory_ledger;
create policy "select_own_company_ledger" on public.inventory_ledger
  for select
  using (company_id = auth.get_company_id());


-- Table: integrations
-- Stores information about connected e-commerce platforms.
create table if not exists public.integrations (
  id uuid default extensions.uuid_generate_v4() primary key,
  company_id uuid references public.companies on delete cascade not null,
  platform text not null,
  shop_domain text,
  shop_name text,
  is_active boolean default true not null,
  last_sync_at timestamptz,
  sync_status text,
  created_at timestamptz default now() not null,
  updated_at timestamptz,
  unique(company_id, platform)
);
-- RLS Policy: Users can manage integrations for their own company. Admins only for write.
alter table public.integrations enable row level security;
drop policy if exists "manage_own_company_integrations" on public.integrations;
create policy "manage_own_company_integrations" on public.integrations
  for all
  using (company_id = auth.get_company_id())
  with check (company_id = auth.get_company_id() and auth.is_company_admin());


-- Table: conversations (for the AI chat)
create table if not exists public.conversations (
    id uuid default extensions.uuid_generate_v4() primary key,
    user_id uuid references auth.users on delete cascade not null,
    company_id uuid references public.companies on delete cascade not null,
    title text not null,
    created_at timestamptz default now() not null,
    last_accessed_at timestamptz default now() not null,
    is_starred boolean default false not null
);
-- RLS Policy: Users can only access their own conversations.
alter table public.conversations enable row level security;
drop policy if exists "manage_own_conversations" on public.conversations;
create policy "manage_own_conversations" on public.conversations
    for all
    using (user_id = auth.uid())
    with check (user_id = auth.uid());


-- Table: messages (for the AI chat)
create table if not exists public.messages (
    id uuid default extensions.uuid_generate_v4() primary key,
    conversation_id uuid references public.conversations on delete cascade not null,
    company_id uuid references public.companies on delete cascade not null,
    role text not null check (role in ('user', 'assistant')),
    content text not null,
    visualization jsonb,
    confidence numeric,
    assumptions text[],
    component text,
    component_props jsonb,
    created_at timestamptz default now() not null
);
-- RLS Policy: Users can only access messages in their own conversations.
alter table public.messages enable row level security;
drop policy if exists "manage_own_messages" on public.messages;
create policy "manage_own_messages" on public.messages
    for all
    using (conversation_id in (select id from public.conversations where user_id = auth.uid()));


-- ### Indexes ###
-- Add indexes to frequently queried columns to improve performance.
create index if not exists idx_products_company_id on public.products(company_id);
create index if not exists idx_variants_company_id on public.product_variants(company_id);
create index if not exists idx_variants_product_id on public.product_variants(product_id);
create index if not exists idx_suppliers_company_id on public.suppliers(company_id);
create index if not exists idx_customers_company_id on public.customers(company_id);
create index if not exists idx_orders_company_id_created_at on public.orders(company_id, created_at desc);
create index if not exists idx_line_items_order_id on public.order_line_items(order_id);
create index if not exists idx_ledger_variant_id on public.inventory_ledger(variant_id);
create index if not exists idx_ledger_company_id_created_at on public.inventory_ledger(company_id, created_at desc);
create index if not exists idx_conversations_user_id on public.conversations(user_id);


-- ### Triggers and Functions ###

-- Function to automatically create a company and link the new user as 'Owner'.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer -- Required to perform actions with elevated privileges.
set search_path = public
as $$
declare
  new_company_id uuid;
begin
  -- Create a new company for the user.
  insert into public.companies (name)
  values (new.raw_app_meta_data ->> 'company_name')
  returning id into new_company_id;

  -- Link the new user to the new company with the 'Owner' role.
  insert into public.company_users (company_id, user_id, role)
  values (new_company_id, new.id, 'Owner');

  -- Create default settings for the new company.
  insert into public.company_settings (company_id)
  values (new_company_id);

  -- Set the company_id and role in the user's JWT claims.
  -- This is critical for RLS to work correctly.
  update auth.users
  set raw_app_meta_data = new.raw_app_meta_data || jsonb_build_object(
      'company_id', new_company_id,
      'company_role', 'Owner'
    )
  where id = new.id;

  return new;
end;
$$;

-- Trigger to execute the handle_new_user function after a new user is created in Supabase Auth.
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


-- Function to automatically update the inventory count when a sale is recorded.
create or replace function public.handle_sale_inventory_change()
returns trigger
language plpgsql
as $$
begin
  -- Decrease the inventory quantity for the sold variant.
  update public.product_variants
  set inventory_quantity = inventory_quantity - new.quantity
  where id = new.variant_id and company_id = new.company_id;

  -- Create a ledger entry to track the change.
  insert into public.inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes)
  select
    new.company_id,
    new.variant_id,
    'sale',
    -new.quantity,
    pv.inventory_quantity,
    new.order_id,
    'Sale from order #' || (select order_number from public.orders where id = new.order_id)
  from public.product_variants pv
  where pv.id = new.variant_id;

  return new;
end;
$$;

-- Trigger to execute the inventory change function after a new line item is inserted.
drop trigger if exists on_line_item_insert on public.order_line_items;
create trigger on_line_item_insert
  after insert on public.order_line_items
  for each row execute procedure public.handle_sale_inventory_change();


-- Set up initial publications for Supabase Realtime (if needed).
begin;
  drop publication if exists supabase_realtime;
  create publication supabase_realtime;
end;

-- Add tables to the publication.
alter publication supabase_realtime add table public.integrations;
alter publication supabase_realtime add table public.conversations;
alter publication supabase_realtime add table public.messages;
