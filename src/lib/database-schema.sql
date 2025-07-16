-- InvoChat - Database Schema
--
-- This script is designed to be idempotent and can be run multiple times safely.
-- It creates tables if they don't exist and replaces views/functions to ensure
-- the schema is always up-to-date with the application's requirements.

-- ----------------------------
-- 1. Cleanup Old Objects
-- Drop the old trigger and function if they exist from previous faulty versions.
-- This resolves the "cannot drop function... because other objects depend on it" error.
-- ----------------------------
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS handle_new_user();


-- ----------------------------
-- 2. Enable Required Extensions
-- ----------------------------
create extension if not exists "uuid-ossp" with schema public;
create extension if not exists "pg_trgm" with schema public;

-- ----------------------------
-- 3. Create Custom Types
-- ----------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'app_role') THEN
        CREATE TYPE public.app_role AS ENUM ('Admin', 'Member');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'platform_name') THEN
        CREATE TYPE public.platform_name AS ENUM ('shopify', 'woocommerce', 'amazon_fba');
    END IF;
END
$$;

-- ----------------------------
-- 4. Create Tables
-- ----------------------------

-- Stores core company information.
create table if not exists public.companies (
  id uuid not null primary key default uuid_generate_v4(),
  name text not null,
  created_at timestamptz not null default now()
);
comment on table public.companies is 'Stores core company information.';

-- A public mapping of users to their companies and roles.
-- This table is populated by the handle_new_user function.
create table if not exists public.users (
  id uuid not null primary key references auth.users(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  role public.app_role not null default 'Member',
  email text,
  deleted_at timestamptz,
  created_at timestamptz default now()
);
comment on table public.users is 'Public user profiles with company and role mapping.';

-- Stores company-specific settings for business logic.
create table if not exists public.company_settings (
    company_id uuid not null primary key references public.companies(id) on delete cascade,
    dead_stock_days int not null default 90,
    fast_moving_days int not null default 30,
    overstock_multiplier int not null default 3,
    high_value_threshold int not null default 1000,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);
comment on table public.company_settings is 'Settings for AI analysis and business logic.';

-- Stores supplier/vendor information.
create table if not exists public.suppliers (
  id uuid not null primary key default uuid_generate_v4(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  email text,
  phone text,
  default_lead_time_days int,
  notes text,
  created_at timestamptz not null default now()
);
comment on table public.suppliers is 'Stores supplier and vendor information.';

-- Stores parent product information.
create table if not exists public.products (
  id uuid not null primary key default uuid_generate_v4(),
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
comment on table public.products is 'Stores parent product data from external platforms.';

-- Stores product variants (SKUs).
create table if not exists public.product_variants (
  id uuid not null primary key default gen_random_uuid(),
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
  location text,
  external_variant_id text,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  unique(company_id, sku),
  unique(company_id, external_variant_id)
);
comment on table public.product_variants is 'Stores individual product SKUs and their inventory levels.';

-- Stores customer information.
create table if not exists public.customers (
    id uuid not null primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    customer_name text not null,
    email text,
    total_orders int default 0,
    total_spent int default 0,
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz default now(),
    unique(company_id, email)
);
comment on table public.customers is 'Stores customer data, aggregated from sales.';


-- Stores order header information.
create table if not exists public.orders (
    id uuid not null primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    order_number text not null,
    external_order_id text,
    customer_id uuid references public.customers(id) on delete set null,
    status text not null default 'pending',
    financial_status text default 'pending',
    fulfillment_status text default 'unfulfilled',
    currency text default 'USD',
    subtotal int not null default 0,
    total_tax int default 0,
    total_shipping int default 0,
    total_discounts int default 0,
    total_amount int not null,
    source_platform text,
    created_at timestamptz default now(),
    updated_at timestamptz default now(),
    unique(company_id, external_order_id)
);
comment on table public.orders is 'Stores sales order header information.';


-- Stores order line item details.
create table if not exists public.order_line_items (
    id uuid not null primary key default gen_random_uuid(),
    order_id uuid not null references public.orders(id) on delete cascade,
    variant_id uuid references public.product_variants(id) on delete set null,
    company_id uuid not null references public.companies(id) on delete cascade,
    product_name text,
    variant_title text,
    sku text,
    quantity int not null,
    price int not null,
    total_discount int default 0,
    tax_amount int default 0,
    cost_at_time int,
    external_line_item_id text
);
comment on table public.order_line_items is 'Stores line item details for each sales order.';

-- Stores purchase order headers.
create table if not exists public.purchase_orders (
  id uuid not null primary key default uuid_generate_v4(),
  company_id uuid not null references public.companies(id) on delete cascade,
  supplier_id uuid references public.suppliers(id) on delete set null,
  status text not null default 'Draft',
  po_number text not null,
  total_cost int not null,
  expected_arrival_date date,
  idempotency_key uuid,
  created_at timestamptz not null default now(),
  unique(company_id, idempotency_key)
);
comment on table public.purchase_orders is 'Stores purchase order header information.';

-- Stores purchase order line items.
create table if not exists public.purchase_order_line_items (
  id uuid not null primary key default uuid_generate_v4(),
  purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
  variant_id uuid not null references public.product_variants(id) on delete cascade,
  quantity int not null,
  cost int not null
);
comment on table public.purchase_order_line_items is 'Stores line item details for each purchase order.';


-- Stores inventory changes over time.
create table if not exists public.inventory_ledger (
    id uuid not null primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    change_type text not null,
    quantity_change int not null,
    new_quantity int not null,
    related_id uuid, -- e.g., order_id, purchase_order_id
    notes text,
    created_at timestamptz not null default now()
);
comment on table public.inventory_ledger is 'Records every change to inventory quantity for auditing.';

-- Stores connected integrations.
create table if not exists public.integrations (
  id uuid not null primary key default uuid_generate_v4(),
  company_id uuid not null references public.companies(id) on delete cascade,
  platform public.platform_name not null,
  shop_domain text,
  shop_name text,
  is_active boolean default false,
  last_sync_at timestamptz,
  sync_status text,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  unique(company_id, platform)
);
comment on table public.integrations is 'Stores connected e-commerce platforms.';

-- Stores conversation history for the chat.
create table if not exists public.conversations (
    id uuid not null primary key default uuid_generate_v4(),
    user_id uuid not null references auth.users on delete cascade,
    company_id uuid not null references public.companies on delete cascade,
    title text not null,
    created_at timestamptz default now(),
    last_accessed_at timestamptz default now(),
    is_starred boolean default false
);
comment on table public.conversations is 'Stores AI chat conversation history.';

-- Stores individual chat messages.
create table if not exists public.messages (
    id uuid not null primary key default uuid_generate_v4(),
    conversation_id uuid not null references public.conversations on delete cascade,
    company_id uuid not null references public.companies on delete cascade,
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
comment on table public.messages is 'Stores individual messages within AI chat conversations.';

-- For webhook replay protection.
create table if not exists public.webhook_events (
  id uuid not null default gen_random_uuid() primary key,
  integration_id uuid not null references public.integrations(id) on delete cascade,
  webhook_id text not null,
  processed_at timestamptz default now(),
  created_at timestamptz default now(),
  unique(integration_id, webhook_id)
);
comment on table public.webhook_events is 'Prevents webhook replay attacks by logging processed webhook IDs.';


-- ----------------------------
-- 5. Create Functions & Triggers
-- ----------------------------

-- Function to handle new user setup.
-- This is called from the application's signup action.
create or replace function public.handle_new_user()
returns uuid
language plpgsql
security definer -- This allows the function to run with the permissions of the user who defined it.
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_name text := current_setting('request.jwt.claims', true)::jsonb->'app_metadata'->>'company_name';
  v_company_id uuid;
begin
  -- 1. Create a new company
  insert into public.companies (name)
  values (v_company_name)
  returning id into v_company_id;

  -- 2. Create the user's public profile, linking them to the new company
  insert into public.users (id, company_id, email, role)
  values (v_user_id, v_company_id, current_setting('request.jwt.claims', true)::jsonb->>'email', 'Admin');

  -- 3. Update the user's auth metadata with the new company ID
  perform auth.update_user_by_id(v_user_id, json_build_object('company_id', v_company_id)::jsonb);

  return v_company_id;
end;
$$;

-- Grant execute permission to authenticated users
grant execute on function public.handle_new_user() to authenticated;


-- Trigger to update inventory ledger on new sale.
create or replace function public.handle_sale_inventory_change()
returns trigger
language plpgsql
as $$
begin
  -- Decrease inventory for the sold variant
  update public.product_variants
  set inventory_quantity = inventory_quantity - NEW.quantity
  where id = NEW.variant_id;

  -- Create a ledger entry for the sale
  insert into public.inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes)
  select
    NEW.company_id,
    NEW.variant_id,
    'sale',
    -NEW.quantity,
    v.inventory_quantity - NEW.quantity,
    NEW.order_id,
    'Order #' || o.order_number
  from public.product_variants v
  join public.orders o on o.id = NEW.order_id
  where v.id = NEW.variant_id;

  return NEW;
end;
$$;

create or replace trigger on_new_order_line_item
  after insert on public.order_line_items
  for each row
  execute function public.handle_sale_inventory_change();


-- ----------------------------
-- 6. Create Indexes
-- ----------------------------
create index if not exists idx_products_company_id on public.products(company_id);
create index if not exists idx_variants_product_id on public.product_variants(product_id);
create index if not exists idx_variants_company_sku on public.product_variants(company_id, sku);
create index if not exists idx_orders_company_id on public.orders(company_id);
create index if not exists idx_order_line_items_order_id on public.order_line_items(order_id);
create index if not exists idx_inventory_ledger_variant_id on public.inventory_ledger(variant_id);
create index if not exists idx_conversations_user_id on public.conversations(user_id);


-- ----------------------------
-- 7. Create Views
-- ----------------------------

-- A view to combine product and variant information for easy querying.
create or replace view public.product_variants_with_details as
select
  pv.*,
  p.title as product_title,
  p.status as product_status,
  p.product_type,
  p.image_url
from
  public.product_variants pv
join
  public.products p on pv.product_id = p.id;


-- ----------------------------
-- 8. Enable Row-Level Security (RLS)
-- ----------------------------
alter table public.companies enable row level security;
alter table public.users enable row level security;
alter table public.company_settings enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.orders enable row level security;
alter table public.order_line_items enable row level security;
alter table public.customers enable row level security;
alter table public.suppliers enable row level security;
alter table public.purchase_orders enable row level security;
alter table public.purchase_order_line_items enable row level security;
alter table public.inventory_ledger enable row level security;
alter table public.integrations enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.webhook_events enable row level security;

-- Function to get the current user's company_id from their JWT claims.
create or replace function auth.user_company_id()
returns uuid
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb->>'company_id', '')::uuid;
$$;

-- Function to get the current user's role from their public profile.
create or replace function public.get_user_role(p_user_id uuid)
returns text
language plpgsql
security definer
as $$
declare
  v_role text;
begin
  select role into v_role from public.users where id = p_user_id;
  return v_role;
end;
$$;


-- ----------------------------
-- 9. Define RLS Policies
-- ----------------------------

-- Users can see their own company.
create or replace policy "Allow read access to own company" on public.companies
  for select using (id = auth.user_company_id());

-- Users can see other users within their own company.
create or replace policy "Allow read access to own team members" on public.users
  for select using (company_id = auth.user_company_id());

-- Users can only manage data within their own company.
create or replace policy "Allow full access for own company data" on public.company_settings
  for all using (company_id = auth.user_company_id());

create or replace policy "Allow full access for own company data" on public.products
  for all using (company_id = auth.user_company_id());

create or replace policy "Allow full access for own company data" on public.product_variants
  for all using (company_id = auth.user_company_id());

create or replace policy "Allow full access for own company data" on public.orders
  for all using (company_id = auth.user_company_id());

create or replace policy "Allow full access for own company data" on public.order_line_items
  for all using (company_id = auth.user_company_id());
  
create or replace policy "Allow full access for own company data" on public.customers
  for all using (company_id = auth.user_company_id());
  
create or replace policy "Allow full access for own company data" on public.suppliers
  for all using (company_id = auth.user_company_id());

create or replace policy "Allow full access for own company data" on public.purchase_orders
  for all using (company_id = auth.user_company_id());
  
create or replace policy "Allow full access for own company data" on public.purchase_order_line_items
  for all using (company_id = auth.user_company_id());
  
create or replace policy "Allow full access for own company data" on public.inventory_ledger
  for all using (company_id = auth.user_company_id());

create or replace policy "Allow full access for own company data" on public.integrations
  for all using (company_id = auth.user_company_id());

create or replace policy "Allow full access for own company data" on public.webhook_events
  for all using (true); -- Webhook processor uses service_role key

-- Users can only manage their own conversations and messages.
create or replace policy "Allow full access for own conversations" on public.conversations
  for all using (user_id = auth.uid());

create or replace policy "Allow full access for own messages" on public.messages
  for all using (company_id = auth.user_company_id());

-- Admins can update/delete team members in their own company.
create or replace policy "Allow admins to update team members" on public.users
  for update using (
    company_id = auth.user_company_id() and
    public.get_user_role(auth.uid()) = 'Admin'
  ) with check (
    company_id = auth.user_company_id() and
    public.get_user_role(auth.uid()) = 'Admin'
  );
  
create or replace policy "Allow admins to remove team members" on public.users
  for delete using (
    company_id = auth.user_company_id() and
    public.get_user_role(auth.uid()) = 'Admin' and
    id <> auth.uid() -- Prevent deleting self
  );

  
-- Grant all permissions to the Supabase service roles. This is safe.
grant all on all tables in schema public to service_role;
grant all on all functions in schema public to service_role;
grant all on all sequences in schema public to service_role;

-- Grant usage for authenticated users. RLS policies will handle the security.
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;
