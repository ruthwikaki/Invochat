-- InvoChat Database Schema
-- Version: 1.3
-- Last Updated: 2024-07-16
-- Description: This script sets up the complete database schema for the InvoChat application,
-- including tables, roles, policies, functions, and triggers.

-- The recommended setup is to run this script in the Supabase SQL Editor.

-- Enable UUID extension
create extension if not exists "uuid-ossp" with schema extensions;

-- Create custom types
do $$
begin
  if not exists (select 1 from pg_type where typname = 'user_role') then
    create type public.user_role as enum ('Owner', 'Admin', 'Member');
  end if;
  if not exists (select 1 from pg_type where typname = 'order_status') then
    create type public.order_status as enum ('pending', 'paid', 'fulfilled', 'cancelled', 'refunded');
  end if;
  if not exists (select 1 from pg_type where typname = 'po_status') then
    create type public.po_status as enum ('draft', 'ordered', 'partially_received', 'received', 'cancelled');
  end if;
end$$;

-- Function to extract company_id from JWT claims
create or replace function public.get_current_company_id()
returns uuid
language sql stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::json->>'company_id', '')::uuid;
$$;


-- =============================================
-- SECTION 1: CORE TABLES (Users, Companies)
-- =============================================

-- Companies Table
-- Stores information about each company using the application.
create table if not exists public.companies (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);
-- RLS for Companies
alter table public.companies enable row level security;
create policy "Allow read access to own company" on public.companies for select using (id = get_current_company_id());

-- User Roles Table
-- Maps users to companies and defines their roles.
create table if not exists public.user_company_roles (
  user_id uuid not null references auth.users(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  role user_role not null default 'Member',
  primary key (user_id, company_id)
);
-- RLS for User Roles
alter table public.user_company_roles enable row level security;
create policy "Allow user to see their own role" on public.user_company_roles for select using (user_id = auth.uid());
create policy "Allow admin to manage roles in their company" on public.user_company_roles for all
  using (company_id = get_current_company_id() and check_user_is_admin(get_current_company_id(), auth.uid()))
  with check (company_id = get_current_company_id() and check_user_is_admin(get_current_company_id(), auth.uid()));


-- Company Settings Table
-- Stores business logic parameters for each company.
create table if not exists public.company_settings (
    company_id uuid primary key references public.companies(id) on delete cascade,
    dead_stock_days int not null default 90,
    fast_moving_days int not null default 30,
    overstock_multiplier numeric(5,2) not null default 3.0,
    high_value_threshold int not null default 100000, -- in cents
    predictive_stock_days int not null default 7,
    created_at timestamptz not null default now(),
    updated_at timestamptz,
    check (dead_stock_days > 0),
    check (fast_moving_days > 0)
);
-- RLS for Company Settings
alter table public.company_settings enable row level security;
create policy "Allow users to read their own company settings" on public.company_settings for select using (company_id = get_current_company_id());
create policy "Allow admin to update settings" on public.company_settings for update
  using (company_id = get_current_company_id() and check_user_is_admin(get_current_company_id(), auth.uid()));


-- =============================================
-- SECTION 2: SETUP TRIGGERS & FUNCTIONS
-- =============================================

-- Function to automatically create a company and role for a new user upon signup.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  new_company_id uuid;
  company_name text := new.raw_user_meta_data->>'company_name';
begin
  -- Create a new company for the user
  insert into public.companies (name)
  values (coalesce(company_name, 'My Company'))
  returning id into new_company_id;

  -- Add the user to the user_company_roles table as Owner
  insert into public.user_company_roles (user_id, company_id, role)
  values (new.id, new_company_id, 'Owner');

  -- Update the user's app_metadata with the company_id and role
  update auth.users
  set app_metadata = app_metadata || jsonb_build_object('company_id', new_company_id, 'role', 'Owner')
  where id = new.id;
  
  return new;
end;
$$;

-- Trigger to execute the handle_new_user function on new user creation
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();


-- Function to check if a user is an admin or owner of a given company.
create or replace function public.check_user_is_admin(p_company_id uuid, p_user_id uuid)
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1
    from public.user_company_roles
    where company_id = p_company_id
      and user_id = p_user_id
      and role in ('Admin', 'Owner')
  );
$$;

-- =============================================
-- SECTION 3: INVENTORY & PRODUCT TABLES
-- =============================================

-- Locations Table
create table if not exists public.locations (
  id uuid primary key default uuid_generate_v4(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  unique (company_id, name)
);
alter table public.locations enable row level security;
create policy "Allow access to own company locations" on public.locations for all using (company_id = get_current_company_id());

-- Suppliers Table
create table if not exists public.suppliers (
  id uuid primary key default uuid_generate_v4(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  email text,
  phone text,
  default_lead_time_days integer,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  check (default_lead_time_days is null or default_lead_time_days >= 0)
);
alter table public.suppliers enable row level security;
create policy "Allow access to own company suppliers" on public.suppliers for all using (company_id = get_current_company_id());

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
  unique (company_id, external_product_id)
);
alter table public.products enable row level security;
create policy "Allow access to own company products" on public.products for all using (company_id = get_current_company_id());
create index if not exists idx_products_tags on public.products using gin (tags);


-- Product Variants Table
create table if not exists public.product_variants (
  id uuid primary key default uuid_generate_v4(),
  product_id uuid not null references public.products(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  sku text,
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
  external_variant_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  unique (company_id, external_variant_id),
  unique (company_id, sku)
);
alter table public.product_variants enable row level security;
create policy "Allow access to own company variants" on public.product_variants for all using (company_id = get_current_company_id());


-- Inventory Levels Table (for multi-location support)
create table if not exists public.inventory_levels (
  variant_id uuid not null references public.product_variants(id) on delete cascade,
  location_id uuid not null references public.locations(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  quantity integer not null default 0,
  reorder_point integer,
  reorder_quantity integer,
  primary key (variant_id, location_id)
);
alter table public.inventory_levels enable row level security;
create policy "Allow access to own company inventory levels" on public.inventory_levels for all using (company_id = get_current_company_id());


-- =============================================
-- SECTION 4: SALES & CUSTOMER TABLES
-- =============================================

-- Customers Table
create table if not exists public.customers (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    customer_name text,
    email text,
    external_customer_id text,
    total_orders integer not null default 0,
    total_spent integer not null default 0,
    first_order_date date,
    created_at timestamptz not null default now(),
    deleted_at timestamptz,
    unique (company_id, email)
);
alter table public.customers enable row level security;
create policy "Allow access to own company customers" on public.customers for all using (company_id = get_current_company_id());


-- Orders Table
create table if not exists public.orders (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    order_number text,
    external_order_id text,
    customer_id uuid references public.customers(id),
    financial_status text,
    fulfillment_status text,
    currency text,
    subtotal integer not null,
    total_tax integer,
    total_shipping integer,
    total_discounts integer,
    total_amount integer not null,
    source_platform text,
    created_at timestamptz not null default now(),
    updated_at timestamptz,
    unique (company_id, external_order_id)
);
alter table public.orders enable row level security;
create policy "Allow access to own company orders" on public.orders for all using (company_id = get_current_company_id());


-- Order Line Items Table
create table if not exists public.order_line_items (
    id uuid primary key default uuid_generate_v4(),
    order_id uuid not null references public.orders(id) on delete cascade,
    variant_id uuid references public.product_variants(id),
    company_id uuid not null references public.companies(id) on delete cascade,
    product_name text,
    variant_title text,
    sku text,
    quantity integer not null,
    price integer not null,
    total_discount integer,
    tax_amount integer,
    cost_at_time integer,
    external_line_item_id text,
    check (quantity > 0),
    check (price >= 0),
    check (cost_at_time >= 0)
);
alter table public.order_line_items enable row level security;
create policy "Allow access to own company order line items" on public.order_line_items for all using (company_id = get_current_company_id());


-- =============================================
-- SECTION 5: PURCHASING TABLES
-- =============================================

create table if not exists public.purchase_orders (
  id uuid primary key default uuid_generate_v4(),
  company_id uuid not null references public.companies(id) on delete cascade,
  supplier_id uuid references public.suppliers(id),
  po_number text,
  status po_status not null default 'draft',
  total_cost integer not null,
  expected_arrival_date date,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);
alter table public.purchase_orders enable row level security;
create policy "Allow access to own company purchase orders" on public.purchase_orders for all using (company_id = get_current_company_id());


create table if not exists public.purchase_order_line_items (
  id uuid primary key default uuid_generate_v4(),
  purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
  variant_id uuid not null references public.product_variants(id),
  company_id uuid not null references public.companies(id) on delete cascade,
  quantity integer not null,
  cost integer not null,
  check (quantity > 0),
  check (cost >= 0)
);
alter table public.purchase_order_line_items enable row level security;
create policy "Allow access to own company PO line items" on public.purchase_order_line_items for all using (company_id = get_current_company_id());


-- =============================================
-- SECTION 6: INVENTORY LEDGER & TRIGGERS
-- =============================================

create table if not exists public.inventory_ledger (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    change_type text not null, -- e.g., 'sale', 'purchase_order', 'reconciliation'
    quantity_change integer not null,
    new_quantity integer not null,
    related_id uuid, -- e.g., order_id, purchase_order_id
    notes text,
    created_at timestamptz not null default now()
);
alter table public.inventory_ledger enable row level security;
create policy "Allow access to own company inventory ledger" on public.inventory_ledger for all using (company_id = get_current_company_id());


-- Trigger function to update inventory from sales
create or replace function public.handle_sale_inventory_change()
returns trigger
language plpgsql
as $$
declare
  new_quantity integer;
begin
  update public.product_variants
  set inventory_quantity = inventory_quantity - new.quantity
  where id = new.variant_id
  returning inventory_quantity into new_quantity;

  insert into public.inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes)
  values (new.company_id, new.variant_id, 'sale', -new.quantity, new_quantity, new.order_id, 'Order ' || (select order_number from public.orders where id = new.order_id));
  
  return new;
end;
$$;

-- Trigger to execute after an order line item is inserted
drop trigger if exists on_order_line_item_inserted on public.order_line_items;
create trigger on_order_line_item_inserted
  after insert on public.order_line_items
  for each row
  when (new.variant_id is not null)
  execute function public.handle_sale_inventory_change();


-- =============================================
-- SECTION 7: LOGGING & INTEGRATIONS
-- =============================================

create table if not exists public.audit_log (
  id uuid primary key default uuid_generate_v4(),
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid references auth.users(id),
  action text not null,
  details jsonb,
  created_at timestamptz not null default now()
);
alter table public.audit_log enable row level security;
create policy "Allow admin to read audit log" on public.audit_log for select using (company_id = get_current_company_id() and check_user_is_admin(get_current_company_id(), auth.uid()));


create table if not exists public.user_feedback (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id),
  company_id uuid not null references public.companies(id) on delete cascade,
  subject_id text not null,
  subject_type text not null, -- e.g., 'ai_response', 'alert'
  feedback text not null, -- 'helpful' or 'unhelpful'
  created_at timestamptz not null default now()
);
alter table public.user_feedback enable row level security;
create policy "Allow user to manage own feedback" on public.user_feedback for all using (user_id = auth.uid());


create table if not exists public.integrations (
  id uuid primary key default uuid_generate_v4(),
  company_id uuid not null references public.companies(id) on delete cascade,
  platform text not null,
  shop_domain text,
  shop_name text,
  is_active boolean not null default false,
  last_sync_at timestamptz,
  sync_status text,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  unique (company_id, platform)
);
alter table public.integrations enable row level security;
create policy "Allow access to own company integrations" on public.integrations for all using (company_id = get_current_company_id());


create table if not exists public.webhook_events (
    id uuid primary key default uuid_generate_v4(),
    integration_id uuid not null references public.integrations(id) on delete cascade,
    webhook_id text not null,
    processed_at timestamptz not null default now(),
    unique(integration_id, webhook_id)
);
alter table public.webhook_events enable row level security;
-- No policies needed as this is a server-only table.

-- =============================================
-- SECTION 8: CHAT & CONVERSATIONS
-- =============================================

create table if not exists public.conversations (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid not null references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    title text not null,
    is_starred boolean not null default false,
    created_at timestamptz not null default now(),
    last_accessed_at timestamptz not null default now()
);
alter table public.conversations enable row level security;
create policy "Allow user to manage own conversations" on public.conversations for all using (user_id = auth.uid());

create table if not exists public.messages (
    id uuid primary key default uuid_generate_v4(),
    conversation_id uuid not null references public.conversations(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    role text not null, -- 'user' or 'assistant'
    content text not null,
    visualization jsonb,
    component text,
    componentProps jsonb,
    confidence real,
    assumptions text[],
    isError boolean,
    created_at timestamptz not null default now()
);
alter table public.messages enable row level security;
create policy "Allow user to manage messages in own conversations" on public.messages for all using (exists (
    select 1 from public.conversations where id = conversation_id and user_id = auth.uid()
));


-- =============================================
-- SECTION 9: VIEWS & ANALYTICAL FUNCTIONS
-- =============================================

create or replace view public.product_variants_with_details as
select
  pv.*,
  p.title as product_title,
  p.status as product_status,
  p.image_url,
  (select l.id from public.inventory_levels il join public.locations l on il.location_id = l.id where il.variant_id = pv.id and l.is_default = true limit 1) as location_id,
  (select l.name from public.inventory_levels il join public.locations l on il.location_id = l.id where il.variant_id = pv.id and l.is_default = true limit 1) as location_name
from
  public.product_variants pv
  join public.products p on pv.product_id = p.id;


-- Grant usage on all schemas and tables to the authenticated role
grant usage on schema public to anon, authenticated;
grant all on all tables in schema public to anon, authenticated;
grant all on all functions in schema public to anon, authenticated;
grant all on all sequences in schema public to anon, authenticated;
