--
-- Universal, Idempotent Database Setup Script for ARVO
--
-- This script is designed to be run safely at any time. It will:
--   - Create tables, views, and functions if they don't exist.
--   - Replace views and functions with their latest definitions if they do.
--   - Preserve all existing data in your tables.
--
-- It operates *only* on the 'public' schema and is safe to run on a new
-- or existing Supabase project.
--

-- 1. Enable necessary extensions
create extension if not exists "uuid-ossp";
create extension if not exists "vector";

--
-- ======== SECTION 1: CORE TABLES ========
--

-- Stores company information
create table if not exists public.companies (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  created_at timestamptz not null default now()
);

-- Stores user profiles, linked to a company. Populated by a function.
create table if not exists public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  email text,
  role text default 'Member'::text,
  deleted_at timestamptz,
  created_at timestamptz default now()
);

-- Stores company-specific business logic settings
create table if not exists public.company_settings (
    company_id uuid primary key references public.companies(id) on delete cascade,
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

-- Stores supplier information
create table if not exists public.suppliers (
  id uuid primary key default uuid_generate_v4(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  email text,
  phone text,
  default_lead_time_days integer,
  notes text,
  created_at timestamptz not null default now(),
  unique (company_id, name)
);

-- Stores main product information (parent products)
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
  unique (company_id, external_product_id)
);

-- Stores product variants (the actual SKUs with inventory)
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
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  location text,
  unique (company_id, sku),
  unique (company_id, external_variant_id)
);

--
-- ======== SECTION 2: TRANSACTIONAL & LOGGING TABLES ========
--

-- Stores customer information
create table if not exists public.customers (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    customer_name text not null,
    email text,
    total_orders integer default 0,
    total_spent integer default 0,
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz default now(),
    unique(company_id, email)
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
    updated_at timestamptz default now(),
    unique (company_id, external_order_id)
);

-- Stores individual items within a sales order
create table if not exists public.order_line_items (
    id uuid primary key default gen_random_uuid(),
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

-- Stores purchase orders
create table if not exists public.purchase_orders (
  id uuid primary key default uuid_generate_v4(),
  company_id uuid not null references public.companies(id) on delete cascade,
  supplier_id uuid references public.suppliers(id),
  status text not null default 'Draft',
  po_number text not null,
  total_cost integer not null,
  expected_arrival_date date,
  created_at timestamptz not null default now(),
  idempotency_key uuid,
  unique(company_id, po_number),
  unique(company_id, idempotency_key)
);

-- Stores items within a purchase order
create table if not exists public.purchase_order_line_items (
  id uuid primary key default uuid_generate_v4(),
  purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
  variant_id uuid not null references public.product_variants(id),
  quantity integer not null,
  cost integer not null
);

-- Stores a detailed log of every inventory change
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

--
-- ======== SECTION 3: INTEGRATION & SYSTEM TABLES ========
--

-- Stores information about connected e-commerce platforms
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

-- Stores webhook events to prevent replay attacks
create table if not exists public.webhook_events (
    id uuid primary key default gen_random_uuid(),
    integration_id uuid not null references public.integrations(id) on delete cascade,
    webhook_id text not null,
    processed_at timestamptz default now(),
    created_at timestamptz default now(),
    unique(integration_id, webhook_id)
);

-- Stores chat conversation metadata
create table if not exists public.conversations (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid not null references auth.users(id) on delete cascade,
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


--
-- ======== SECTION 4: DATABASE FUNCTIONS & TRIGGERS ========
--

-- Function to securely handle new user setup.
drop function if exists public.handle_new_user();
create or replace function public.handle_new_user()
returns uuid
language plpgsql
security definer
as $$
declare
  new_company_id uuid;
  new_user_id uuid := auth.uid();
  user_meta jsonb := (select raw_app_meta_data from auth.users where id = new_user_id);
  user_email text := (select email from auth.users where id = new_user_id);
  company_name text := user_meta ->> 'company_name';
begin
  -- 1. Create a new company for the user
  insert into public.companies (name)
  values (company_name)
  returning id into new_company_id;

  -- 2. Create the user's public profile, linking to the new company
  insert into public.users (id, company_id, email, role)
  values (new_user_id, new_company_id, user_email, 'Owner');
  
  -- 3. Update the user's private app_metadata with the new company_id
  update auth.users
  set raw_app_meta_data = user_meta || jsonb_build_object('company_id', new_company_id)
  where id = new_user_id;
  
  return new_company_id;
end;
$$;


-- Function to update the fts_document column on product changes
drop function if exists public.update_product_fts_document();
create or replace function public.update_product_fts_document()
returns trigger
language plpgsql
as $$
begin
  new.fts_document := to_tsvector('english', coalesce(new.title, '') || ' ' || coalesce(new.description, '') || ' ' || coalesce(new.product_type, '') || ' ' || coalesce(array_to_string(new.tags, ' '), ''));
  return new;
end;
$$;

-- Trigger to call the FTS update function
drop trigger if exists trg_update_product_fts on public.products;
create trigger trg_update_product_fts
before insert or update on public.products
for each row
execute function public.update_product_fts_document();


--
-- ======== SECTION 5: VIEWS ========
-- Views provide simplified, denormalized access to data for the application.
--

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
  p.title as product_title,
  p.status as product_status,
  p.product_type,
  p.image_url
from
  public.product_variants pv
join
  public.products p on pv.product_id = p.id;


--
-- ======== SECTION 6: INDEXES ========
-- Indexes are crucial for database query performance.
--

create index if not exists idx_products_company_id on public.products (company_id);
create index if not exists idx_variants_company_id on public.product_variants (company_id);
create index if not exists idx_variants_product_id on public.product_variants (product_id);
create index if not exists idx_variants_sku_company on public.product_variants (sku, company_id);
create index if not exists idx_orders_company_id on public.orders (company_id);
create index if not exists idx_order_line_items_order_id on public.order_line_items (order_id);
create index if not exists idx_order_line_items_variant_id on public.order_line_items (variant_id);
create index if not exists idx_ledger_company_variant on public.inventory_ledger (company_id, variant_id);
create index if not exists idx_products_fts_document on public.products using gin (fts_document);


--
-- ======== SECTION 7: ROW-LEVEL SECURITY (RLS) ========
-- RLS policies are the most critical security feature, ensuring data isolation between companies.
--

-- Enable RLS on all relevant tables
alter table public.companies enable row level security;
alter table public.users enable row level security;
alter table public.company_settings enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.suppliers enable row level security;
alter table public.customers enable row level security;
alter table public.orders enable row level security;
alter table public.order_line_items enable row level security;
alter table public.purchase_orders enable row level security;
alter table public.purchase_order_line_items enable row level security;
alter table public.inventory_ledger enable row level security;
alter table public.integrations enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.webhook_events enable row level security;

-- Utility function to get company_id from the user's claims
create or replace function public.get_my_company_id()
returns uuid
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid;
$$;

-- Utility function to get user's role from their claims
create or replace function public.get_my_role()
returns text
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'role', '');
$$;

-- Drop existing policies before creating new ones to ensure idempotency
drop policy if exists "allow_select_own_company" on public.companies;
drop policy if exists "allow_read_own_data" on public.users;
drop policy if exists "allow_all_own_company" on public.company_settings;
drop policy if exists "allow_all_own_company" on public.products;
drop policy if exists "allow_all_own_company" on public.product_variants;
drop policy if exists "allow_all_own_company" on public.suppliers;
drop policy if exists "allow_all_own_company" on public.customers;
drop policy if exists "allow_all_own_company" on public.orders;
drop policy if exists "allow_all_own_company" on public.order_line_items;
drop policy if exists "allow_all_own_company" on public.purchase_orders;
drop policy if exists "allow_all_own_company" on public.purchase_order_line_items;
drop policy if exists "allow_all_own_company" on public.inventory_ledger;
drop policy if exists "allow_all_own_company" on public.integrations;
drop policy if exists "allow_read_own_conversations" on public.conversations;
drop policy if exists "allow_all_own_messages" on public.messages;
drop policy if exists "allow_read_own_company_webhooks" on public.webhook_events;

-- Generic policies for most tables
create policy "allow_select_own_company" on public.companies for select using (id = public.get_my_company_id());
create policy "allow_read_own_data" on public.users for select using (company_id = public.get_my_company_id());
create policy "allow_all_own_company" on public.company_settings for all using (company_id = public.get_my_company_id());
create policy "allow_all_own_company" on public.products for all using (company_id = public.get_my_company_id());
create policy "allow_all_own_company" on public.product_variants for all using (company_id = public.get_my_company_id());
create policy "allow_all_own_company" on public.suppliers for all using (company_id = public.get_my_company_id());
create policy "allow_all_own_company" on public.customers for all using (company_id = public.get_my_company_id());
create policy "allow_all_own_company" on public.orders for all using (company_id = public.get_my_company_id());
create policy "allow_all_own_company" on public.order_line_items for all using (company_id = public.get_my_company_id());
create policy "allow_all_own_company" on public.purchase_orders for all using (company_id = public.get_my_company_id());
create policy "allow_all_own_company" on public.purchase_order_line_items for all using (purchase_order_id in (select id from public.purchase_orders where company_id = public.get_my_company_id()));
create policy "allow_all_own_company" on public.inventory_ledger for all using (company_id = public.get_my_company_id());
create policy "allow_all_own_company" on public.integrations for all using (company_id = public.get_my_company_id());

-- Chat-specific Policies
create policy "allow_read_own_conversations" on public.conversations for select using (company_id = public.get_my_company_id() and user_id = auth.uid());
create policy "allow_all_own_messages" on public.messages for all using (company_id = public.get_my_company_id() and conversation_id in (select id from public.conversations where user_id = auth.uid()));

-- Webhook policy - slightly different as it needs to check company_id on the related integration
create policy "allow_read_own_company_webhooks" on public.webhook_events for select using (integration_id in (select id from public.integrations where company_id = public.get_my_company_id()));
