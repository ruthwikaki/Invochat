
-- Enable UUID generation
create extension if not exists "uuid-ossp" with schema extensions;

-- Create a custom type for user roles
create type public.user_role as enum ('Owner', 'Admin', 'Member');

-- #################################################################
-- ###                      TABLES                               ###
-- #################################################################

-- Table: companies
-- Stores basic information about each company using the application.
create table if not exists public.companies (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  created_at timestamptz not null default now()
);
-- RLS for companies table
alter table public.companies enable row level security;
create policy "Users can view their own company" on public.companies for select using (auth.uid() in (select user_id from public.users where company_id = id));

-- Table: users
-- Stores user information and their association with a company.
create table if not exists public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  email text,
  role public.user_role not null default 'Member',
  deleted_at timestamptz,
  created_at timestamptz default now()
);
-- RLS for users table
alter table public.users enable row level security;
create policy "Users can view other users in their company" on public.users for select using (company_id = (select company_id from public.users where id = auth.uid()));

-- Table: company_settings
-- Stores various business logic settings for each company.
create table if not exists public.company_settings (
  company_id uuid primary key references public.companies(id) on delete cascade,
  dead_stock_days integer not null default 90,
  fast_moving_days integer not null default 30,
  overstock_multiplier integer not null default 3,
  high_value_threshold integer not null default 100000, -- in cents
  predictive_stock_days integer not null default 7,
  currency text default 'USD',
  timezone text default 'UTC',
  tax_rate numeric default 0,
  custom_rules jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);
-- RLS for company_settings table
alter table public.company_settings enable row level security;
create policy "Users can manage settings for their own company" on public.company_settings for all using (company_id = (select company_id from public.users where id = auth.uid()));

-- Table: integrations
-- Stores information about connected e-commerce platforms.
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
  unique (company_id, platform)
);
-- RLS for integrations table
alter table public.integrations enable row level security;
create policy "Users can manage integrations for their own company" on public.integrations for all using (company_id = (select company_id from public.users where id = auth.uid()));

-- Table: products
-- Stores core product information.
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
  unique(company_id, external_product_id)
);
-- RLS for products table
alter table public.products enable row level security;
create policy "Users can manage products for their own company" on public.products for all using (company_id = (select company_id from public.users where id = auth.uid()));

-- Table: product_variants
-- Stores individual product variants (SKUs).
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
  price integer, -- in cents
  compare_at_price integer, -- in cents
  cost integer, -- in cents
  inventory_quantity integer not null default 0,
  location text,
  external_variant_id text,
  created_at timestamptz default now(),
  updated_at timestamptz,
  unique(company_id, sku)
);
-- RLS for product_variants table
alter table public.product_variants enable row level security;
create policy "Users can manage variants for their own company" on public.product_variants for all using (company_id = (select company_id from public.users where id = auth.uid()));

-- Table: customers
-- Stores customer information.
create table if not exists public.customers (
  id uuid primary key default uuid_generate_v4(),
  company_id uuid not null references public.companies(id) on delete cascade,
  customer_name text,
  email text,
  total_orders integer default 0,
  total_spent integer default 0, -- in cents
  first_order_date date,
  deleted_at timestamptz,
  created_at timestamptz default now(),
  unique (company_id, email)
);
-- RLS for customers table
alter table public.customers enable row level security;
create policy "Users can manage customers for their own company" on public.customers for all using (company_id = (select company_id from public.users where id = auth.uid()));

-- Table: orders
-- Stores sales order headers.
create table if not exists public.orders (
    id uuid primary key default uuid_generate_v4(),
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
    created_at timestamptz default now(),
    updated_at timestamptz
);
-- RLS for orders table
alter table public.orders enable row level security;
create policy "Users can view orders for their own company" on public.orders for select using (company_id = (select company_id from public.users where id = auth.uid()));

-- Table: order_line_items
-- Stores line items for each sales order.
create table if not exists public.order_line_items (
    id uuid primary key default uuid_generate_v4(),
    order_id uuid not null references public.orders(id) on delete cascade,
    variant_id uuid references public.product_variants(id),
    company_id uuid not null references public.companies(id) on delete cascade,
    product_name text not null,
    variant_title text,
    sku text,
    quantity integer not null,
    price integer not null,
    total_discount integer default 0,
    tax_amount integer default 0,
    cost_at_time integer,
    external_line_item_id text
);
-- RLS for order_line_items table
alter table public.order_line_items enable row level security;
create policy "Users can view order line items for their own company" on public.order_line_items for select using (company_id = (select company_id from public.users where id = auth.uid()));


-- Table: suppliers
-- Stores supplier/vendor information.
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
-- RLS for suppliers table
alter table public.suppliers enable row level security;
create policy "Users can manage suppliers for their own company" on public.suppliers for all using (company_id = (select company_id from public.users where id = auth.uid()));

-- Table: purchase_orders
-- Stores purchase order headers.
create table if not exists public.purchase_orders (
  id uuid primary key default uuid_generate_v4(),
  company_id uuid not null references public.companies(id) on delete cascade,
  supplier_id uuid references public.suppliers(id),
  status text not null default 'Draft',
  po_number text not null,
  total_cost integer not null,
  expected_arrival_date date,
  created_at timestamptz not null default now(),
  idempotency_key uuid
);
-- RLS for purchase_orders table
alter table public.purchase_orders enable row level security;
create policy "Users can manage POs for their own company" on public.purchase_orders for all using (company_id = (select company_id from public.users where id = auth.uid()));

-- Table: purchase_order_line_items
-- Stores line items for each purchase order.
create table if not exists public.purchase_order_line_items (
  id uuid primary key default uuid_generate_v4(),
  purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
  variant_id uuid not null references public.product_variants(id),
  quantity integer not null,
  cost integer not null
);
-- RLS for po_line_items table
alter table public.purchase_order_line_items enable row level security;
create policy "Users can manage PO line items for their own company" on public.purchase_order_line_items for all using (
    purchase_order_id in (select id from public.purchase_orders where company_id = (select company_id from public.users where id = auth.uid()))
);

-- Table: inventory_ledger
-- Tracks all changes to inventory quantity for auditing purposes.
create table if not exists public.inventory_ledger (
  id uuid primary key default uuid_generate_v4(),
  variant_id uuid not null references public.product_variants(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  change_type text not null, -- e.g., 'sale', 'purchase_order', 'reconciliation'
  quantity_change integer not null,
  new_quantity integer not null,
  related_id uuid, -- e.g., order_id, purchase_order_id
  notes text,
  created_at timestamptz not null default now()
);
-- RLS for inventory_ledger table
alter table public.inventory_ledger enable row level security;
create policy "Users can view inventory ledger for their own company" on public.inventory_ledger for select using (company_id = (select company_id from public.users where id = auth.uid()));

-- Table: conversations
-- Stores chat conversation history.
create table if not exists public.conversations (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid not null references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    title text not null,
    created_at timestamptz default now(),
    last_accessed_at timestamptz default now(),
    is_starred boolean default false
);
-- RLS for conversations table
alter table public.conversations enable row level security;
create policy "Users can manage their own conversations" on public.conversations for all using (user_id = auth.uid());

-- Table: messages
-- Stores individual chat messages.
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
-- RLS for messages table
alter table public.messages enable row level security;
create policy "Users can manage messages in their own conversations" on public.messages for all using (
    conversation_id in (select id from public.conversations where user_id = auth.uid())
);

-- Table: webhook_events
-- Logs incoming webhook events to prevent replay attacks.
create table if not exists public.webhook_events (
    id uuid primary key default gen_random_uuid(),
    integration_id uuid not null references public.integrations(id) on delete cascade,
    webhook_id text not null,
    processed_at timestamptz default now(),
    created_at timestamptz default now(),
    unique(integration_id, webhook_id)
);
-- RLS for webhook_events table
alter table public.webhook_events enable row level security;
create policy "Service can insert webhook events" on public.webhook_events for insert with check (true);

-- #################################################################
-- ###                      VIEWS                                ###
-- #################################################################

-- This is the fixed view using CREATE OR REPLACE VIEW
create or replace view public.product_variants_with_details as
  select
    pv.*,
    p.title as product_title,
    p.status as product_status,
    p.image_url
  from
    public.product_variants pv
  join
    public.products p on pv.product_id = p.id;


-- #################################################################
-- ###                      FUNCTIONS & TRIGGERS                 ###
-- #################################################################

-- Function: handle_new_user
-- Automatically creates a company and a corresponding user profile when a new user signs up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  new_company_id uuid;
begin
  -- Create a new company for the user
  insert into public.companies (name)
  values (new.raw_user_meta_data->>'company_name')
  returning id into new_company_id;

  -- Create a new user profile linked to the new company
  insert into public.users (id, company_id, email, role)
  values (new.id, new_company_id, new.email, 'Owner');
  
  -- Update the user's app_metadata with the new company_id and role
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'role', 'Owner')
  where id = new.id;
  
  return new;
end;
$$;

-- Trigger: on_auth_user_created
-- Fires the handle_new_user function after a new user is created in the auth schema.
create or replace trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


-- Function to get user role
create or replace function public.get_user_role(p_user_id uuid)
returns text as $$
begin
  return (
    select raw_app_meta_data->>'role'
    from auth.users
    where id = p_user_id
  );
end;
$$ language plpgsql security definer;


-- #################################################################
-- ###                      INDEXES                              ###
-- #################################################################

-- Indexes for performance
create index if not exists idx_products_company_id on public.products(company_id);
create index if not exists idx_variants_company_id on public.product_variants(company_id);
create index if not exists idx_variants_product_id on public.product_variants(product_id);
create index if not exists idx_orders_company_id_created_at on public.orders(company_id, created_at desc);
create index if not exists idx_line_items_order_id on public.order_line_items(order_id);
create index if not exists idx_line_items_variant_id on public.order_line_items(variant_id);
create index if not exists idx_ledger_variant_id on public.inventory_ledger(variant_id);
create index if not exists idx_ledger_company_id on public.inventory_ledger(company_id);
create index if not exists idx_po_company_id on public.purchase_orders(company_id);
create index if not exists idx_po_supplier_id on public.purchase_orders(supplier_id);
create index if not exists idx_po_line_items_po_id on public.purchase_order_line_items(purchase_order_id);
create index if not exists idx_po_line_items_variant_id on public.purchase_order_line_items(variant_id);

-- #################################################################
-- ###                 ROW LEVEL SECURITY POLICIES               ###
-- #################################################################

-- Helper function to get the company_id for the currently authenticated user
create or replace function public.get_my_company_id()
returns uuid
language sql
security definer
as $$
  select raw_app_meta_data->>'company_id' from auth.users where id = auth.uid()
$$;

-- Helper function to check if the current user has a specific role
create or replace function public.is_user_role(p_role text)
returns boolean
language sql
security definer
as $$
  select (select raw_app_meta_data->>'role' from auth.users where id = auth.uid()) = p_role
$$;

-- Generic SELECT policy for any table with a company_id column
create or replace function public.create_company_select_policy(table_name text)
returns void as $$
begin
  execute format('
    create policy "Users can view records in their own company"
    on public.%I for select
    using (company_id = public.get_my_company_id());
  ', table_name);
end;
$$ language plpgsql;

-- Generic policy for write operations (INSERT, UPDATE, DELETE) restricted to Admins and Owners
create or replace function public.create_company_admin_write_policy(table_name text)
returns void as $$
begin
  execute format('
    create policy "Admins and Owners can manage records in their own company"
    on public.%I for all
    using (company_id = public.get_my_company_id())
    with check (
      company_id = public.get_my_company_id() and
      (public.is_user_role(''Admin'') or public.is_user_role(''Owner''))
    );
  ', table_name);
end;
$$ language plpgsql;

-- Drop existing policies before creating new ones to avoid conflicts
do $$
declare
  tbl text;
begin
  for tbl in 
    select table_name from information_schema.tables where table_schema = 'public'
  loop
    execute 'alter table public.' || quote_ident(tbl) || ' disable row level security;';
    execute 'drop policy if exists "Users can view records in their own company" on public.' || quote_ident(tbl) || ';';
    execute 'drop policy if exists "Admins and Owners can manage records in their own company" on public.' || quote_ident(tbl) || ';';
  end loop;
end;
$$;


-- Apply the new, stricter RLS policies
select public.create_company_admin_write_policy('companies');
select public.create_company_admin_write_policy('company_settings');
select public.create_company_admin_write_policy('integrations');
select public.create_company_admin_write_policy('products');
select public.create_company_admin_write_policy('product_variants');
select public.create_company_admin_write_policy('customers');
select public.create_company_admin_write_policy('suppliers');
select public.create_company_admin_write_policy('purchase_orders');
select public.create_company_admin_write_policy('purchase_order_line_items');
select public.create_company_select_policy('orders');
select public.create_company_select_policy('order_line_items');
select public.create_company_select_policy('inventory_ledger');

-- Re-enable RLS on all tables
do $$
declare
  tbl text;
begin
  for tbl in 
    select table_name from information_schema.tables where table_schema = 'public'
  loop
    execute 'alter table public.' || quote_ident(tbl) || ' enable row level security;';
  end loop;
end;
$$;

-- Special policies for users table
drop policy if exists "Users can view other users in their company" on public.users;
drop policy if exists "Users can update their own profile" on public.users;
create policy "Users can view other users in their company" on public.users for select using (company_id = public.get_my_company_id());
create policy "Users can update their own profile" on public.users for update using (id = auth.uid()) with check (id = auth.uid());
-- Note: User creation is handled by the handle_new_user trigger. Deletion is restricted.

-- Special policies for conversations and messages
drop policy if exists "Users can manage their own conversations" on public.conversations;
drop policy if exists "Users can manage messages in their own conversations" on public.messages;
create policy "Users can manage their own conversations" on public.conversations for all using (user_id = auth.uid());
create policy "Users can manage messages in their own conversations" on public.messages for all using (conversation_id in (select id from public.conversations where user_id = auth.uid()));

-- Grant usage on schemas
grant usage on schema public to postgres, anon, authenticated, service_role;
grant usage on schema realtime to postgres, anon, authenticated, service_role;
grant usage on schema extensions to postgres, anon, authenticated, service_role;
grant usage on schema vault to postgres, anon, authenticated, service_role;


-- Grant permissions
grant all on all tables in schema public to postgres, service_role;
grant all on all functions in schema public to postgres, service_role;
grant all on all sequences in schema public to postgres, service_role;

grant execute on function vault.secrets_read_by_name(text) to service_role;
grant execute on function vault.secrets_create(text,text,text) to service_ale;
grant execute on function vault.secrets_update(text,text,text) to service_role;

grant all privileges on schema vault to postgres;

-- Grant permissions for authenticated users (your app users)
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select, update on all sequences in schema public to authenticated;

grant select on all tables in schema storage to authenticated;
grant insert on all tables in schema storage to authenticated;
grant update on all tables in schema storage to authenticated;
grant delete on all tables in schema storage to authenticated;

grant usage on schema realtime to authenticated;
grant select on all tables in schema realtime to authenticated;
grant insert on all tables in schema realtime to authenticated;
grant update on all tables in schema realtime to authenticated;
grant delete on all tables in schema realtime to authenticated;

-- Grant permissions for anonymous users (if you have public data)
grant select on all tables in schema public to anon;
grant usage, select on all sequences in schema public to anon;
grant select on all tables in schema storage to anon;
grant insert on all tables in schema storage to anon;
grant usage on schema realtime to anon;
grant select on all tables in schema realtime to anon;

-- Apply default privileges for any new objects created in the future
alter default privileges in schema public grant all on tables to postgres, service_role;
alter default privileges in schema public grant all on functions to postgres, service_role;
alter default privileges in schema public grant all on sequences to postgres, service_role;

alter default privileges in schema public grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema public grant usage, select, update on sequences to authenticated;

alter default privileges in schema public grant select on tables to anon;
alter default privileges in schema public grant usage, select on sequences to anon;
