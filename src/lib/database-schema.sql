
-- =================================================================
-- 1. UTILITY FUNCTIONS
-- =================================================================
-- These functions provide helpers for accessing user and company info
-- from within the database, primarily used for RLS policies.

-- Extracts the user ID from the JWT token.
create or replace function auth.get_user_id()
returns uuid
language sql stable
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

-- Extracts the company ID from the JWT token's app_metadata.
create or replace function auth.get_company_id()
returns uuid
language sql stable
as $$
  select nullif(current_setting('request.jwt.claim.app_metadata', true), '')::jsonb ->> 'company_id';
$$;

-- =================================================================
-- 2. ENUMS & TYPES
-- =================================================================
-- Define custom types used throughout the database schema.

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE public.user_role AS ENUM ('Owner', 'Admin', 'Member');
    END IF;
END$$;

-- =================================================================
-- 3. TABLES
-- =================================================================
-- The core tables that store all application data.

create table if not exists public.companies (
  id uuid not null primary key default uuid_generate_v4(),
  name text not null,
  created_at timestamptz not null default now()
);
comment on table public.companies is 'Stores company information.';

create table if not exists public.users (
  id uuid not null primary key references auth.users(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  email text,
  role user_role not null default 'Member',
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);
comment on table public.users is 'Stores user profiles linked to a company.';

create table if not exists public.company_settings (
    company_id uuid not null primary key references public.companies(id) on delete cascade,
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
    updated_at timestamptz,
    subscription_status text default 'trial',
    subscription_plan text default 'starter',
    subscription_expires_at timestamptz,
    stripe_customer_id text,
    stripe_subscription_id text,
    promo_sales_lift_multiplier real not null default 2.5
);
comment on table public.company_settings is 'Stores business logic settings for each company.';


create table if not exists public.integrations (
  id uuid not null primary key default uuid_generate_v4(),
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
comment on table public.integrations is 'Stores integration settings for each company.';

create table if not exists public.suppliers (
  id uuid not null primary key default uuid_generate_v4(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  email text,
  phone text,
  default_lead_time_days integer,
  notes text,
  created_at timestamptz not null default now()
);
comment on table public.suppliers is 'Stores supplier information.';


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
  deleted_at timestamptz,
  fts_document tsvector generated always as (to_tsvector('english', title || ' ' || coalesce(description, ''))) stored
);
comment on table public.products is 'Core product information.';

create index if not exists products_fts_document_idx on public.products using gin(fts_document);
create index if not exists products_company_id_external_id_idx on public.products(company_id, external_product_id);


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
  price integer,
  compare_at_price integer,
  cost integer,
  inventory_quantity integer not null default 0,
  location text,
  external_variant_id text,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  deleted_at timestamptz,
  unique (company_id, sku)
);
comment on table public.product_variants is 'Stores product variants and their inventory levels.';
create index if not exists variants_company_id_external_id_idx on public.product_variants(company_id, external_variant_id);


create table if not exists public.customers (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    customer_name text not null,
    email text,
    total_orders integer default 0,
    total_spent integer default 0,
    first_order_date date,
    created_at timestamptz default now(),
    deleted_at timestamptz,
    unique(company_id, email)
);
comment on table public.customers is 'Centralized customer data from all integrations.';


create table if not exists public.orders (
    id uuid primary key default gen_random_uuid(),
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
    updated_at timestamptz default now(),
    unique(company_id, external_order_id)
);
comment on table public.orders is 'Aggregated sales orders from all platforms.';

create table if not exists public.order_line_items (
    id uuid primary key default gen_random_uuid(),
    order_id uuid not null references public.orders(id) on delete cascade,
    product_id uuid not null references public.products(id) on delete set null,
    variant_id uuid not null references public.product_variants(id) on delete set null,
    company_id uuid not null references public.companies(id) on delete cascade,
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
comment on table public.order_line_items is 'Individual line items for each sales order.';

create table if not exists public.purchase_orders (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    supplier_id uuid references public.suppliers(id) on delete set null,
    status text not null default 'Draft',
    po_number text not null,
    total_cost integer not null,
    expected_arrival_date date,
    idempotency_key uuid,
    created_at timestamptz not null default now(),
    unique(company_id, po_number)
);
comment on table public.purchase_orders is 'Stores purchase orders for restocking inventory.';

create table if not exists public.purchase_order_line_items (
    id uuid primary key default uuid_generate_v4(),
    purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    quantity integer not null,
    cost integer not null
);
comment on table public.purchase_order_line_items is 'Individual line items for each purchase order.';


create table if not exists public.inventory_ledger (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    change_type text not null,
    quantity_change integer not null,
    new_quantity integer not null,
    related_id uuid, -- e.g., order_id or purchase_order_id
    notes text,
    created_at timestamptz not null default now()
);
comment on table public.inventory_ledger is 'Transactional log of all inventory movements.';


create table if not exists public.webhook_events (
    id uuid primary key default gen_random_uuid(),
    integration_id uuid not null references public.integrations(id) on delete cascade,
    webhook_id text not null,
    processed_at timestamptz default now(),
    created_at timestamptz default now(),
    unique (webhook_id)
);
comment on table public.webhook_events is 'Logs incoming webhook events to prevent replay attacks.';

-- =================================================================
-- 4. VIEWS
-- =================================================================
-- These views simplify querying complex, joined data.

create or replace view public.product_variants_with_details as
select
    pv.*,
    p.title as product_title,
    p.product_type,
    p.status as product_status,
    p.image_url
from public.product_variants pv
join public.products p on pv.product_id = p.id;

create or replace view public.customers_view as
select
    c.id,
    c.company_id,
    c.customer_name,
    c.email,
    c.first_order_date,
    c.created_at,
    coalesce(o.total_orders, 0) as total_orders,
    coalesce(o.total_spent, 0) as total_spent
from public.customers c
left join (
    select
        customer_id,
        count(id) as total_orders,
        sum(total_amount) as total_spent
    from public.orders
    group by customer_id
) o on c.id = o.customer_id;

create or replace view public.orders_view as
select
    o.id,
    o.company_id,
    o.order_number,
    o.created_at,
    o.fulfillment_status,
    o.financial_status,
    o.total_amount,
    o.source_platform,
    c.email as customer_email
from public.orders o
left join public.customers c on o.customer_id = c.id;


-- =================================================================
-- 5. FUNCTIONS & TRIGGERS
-- =================================================================
-- This section contains the core business logic of the application,
-- implemented as database functions and triggers.

-- Main trigger function to handle new user sign-ups.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  company_id uuid;
  user_email text;
  company_name text;
begin
  -- 1. Create a new company for the user
  company_name := new.raw_app_meta_data->>'company_name';
  if company_name is null then
    company_name := 'My Company'; -- Fallback company name
  end if;

  insert into public.companies (name)
  values (company_name)
  returning id into company_id;

  -- 2. Insert the user into the public users table
  user_email := new.email;
  insert into public.users (id, company_id, email, role)
  values (new.id, company_id, user_email, 'Owner');

  -- 3. Update the user's app_metadata with the new company_id and role
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id, 'role', 'Owner')
  where id = new.id;

  return new;
end;
$$;

-- Trigger to execute the handle_new_user function on new user creation
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


-- Function to check a user's role within their company.
create or replace function public.check_user_permission(p_user_id uuid, p_required_role text)
returns boolean
language plpgsql
security definer
as $$
begin
  return exists (
    select 1
    from public.users u
    where u.id = p_user_id
    and (
      (p_required_role = 'Owner' and u.role = 'Owner') or
      (p_required_role = 'Admin' and u.role in ('Owner', 'Admin'))
    )
  );
end;
$$;


-- =================================================================
-- 6. ROW-LEVEL SECURITY (RLS)
-- =================================================================
-- These policies ensure that users can only access data for their own company.

alter table public.companies enable row level security;
drop policy if exists "Users can view their own company" on public.companies;
create policy "Users can view their own company" on public.companies for select
using (id = auth.get_company_id());

alter table public.users enable row level security;
drop policy if exists "Users can view other users in their company" on public.users;
create policy "Users can view other users in their company" on public.users for select
using (company_id = auth.get_company_id());
drop policy if exists "Owners can manage users in their company" on public.users;
create policy "Owners can manage users in their company" on public.users for all
using (company_id = auth.get_company_id() and auth.get_user_role() in ('Owner', 'Admin'));


alter table public.company_settings enable row level security;
drop policy if exists "Users can view their own company settings" on public.company_settings;
create policy "Users can view their own company settings" on public.company_settings for select
using (company_id = auth.get_company_id());
drop policy if exists "Admins can update their own company settings" on public.company_settings;
create policy "Admins can update their own company settings" on public.company_settings for update
using (company_id = auth.get_company_id() and auth.get_user_role() in ('Owner', 'Admin'));


alter table public.integrations enable row level security;
drop policy if exists "Users can manage integrations for their own company" on public.integrations;
create policy "Users can manage integrations for their own company" on public.integrations for all
using (company_id = auth.get_company_id());

alter table public.products enable row level security;
drop policy if exists "Users can manage products for their own company" on public.products;
create policy "Users can manage products for their own company" on public.products for all
using (company_id = auth.get_company_id());

alter table public.product_variants enable row level security;
drop policy if exists "Users can manage variants for their own company" on public.product_variants;
create policy "Users can manage variants for their own company" on public.product_variants for all
using (company_id = auth.get_company_id());

alter table public.suppliers enable row level security;
drop policy if exists "Users can manage suppliers for their own company" on public.suppliers;
create policy "Users can manage suppliers for their own company" on public.suppliers for all
using (company_id = auth.get_company_id());

alter table public.customers enable row level security;
drop policy if exists "Users can manage customers for their own company" on public.customers;
create policy "Users can manage customers for their own company" on public.customers for all
using (company_id = auth.get_company_id());

alter table public.orders enable row level security;
drop policy if exists "Users can manage orders for their own company" on public.orders;
create policy "Users can manage orders for their own company" on public.orders for all
using (company_id = auth.get_company_id());

alter table public.order_line_items enable row level security;
drop policy if exists "Users can manage line items for their own company" on public.order_line_items;
create policy "Users can manage line items for their own company" on public.order_line_items for all
using (company_id = auth.get_company_id());

alter table public.purchase_orders enable row level security;
drop policy if exists "Users can manage POs for their own company" on public.purchase_orders;
create policy "Users can manage POs for their own company" on public.purchase_orders for all
using (company_id = auth.get_company_id());

alter table public.purchase_order_line_items enable row level security;
drop policy if exists "Users can manage PO line items for their own company" on public.purchase_order_line_items;
create policy "Users can manage PO line items for their own company" on public.purchase_order_line_items for all
using (company_id = auth.get_company_id());

alter table public.inventory_ledger enable row level security;
drop policy if exists "Users can view ledger for their own company" on public.inventory_ledger;
create policy "Users can view ledger for their own company" on public.inventory_ledger for select
using (company_id = auth.get_company_id());

-- =================================================================
-- 7. INITIAL DATA & GRANTS
-- =================================================================

-- Grant usage on the public schema to the authenticated role
grant usage on schema public to authenticated;

-- Grant select, insert, update, delete permissions on all tables in the public schema to the authenticated role
grant select, insert, update, delete on all tables in schema public to authenticated;
grant all privileges on all functions in schema public to authenticated;
grant all privileges on all sequences in schema public to authenticated;

-- Grant usage for the anon role, which is necessary for auth operations
grant usage on schema public to anon;


-- =================================================================
-- 8. EXTENSIONS
-- =================================================================
-- Ensure required PostgreSQL extensions are enabled.

create extension if not exists "uuid-ossp";
create extension if not exists "pg_net";
create extension if not exists "moddatetime";

-- Final message for the user running the script
select 'SUCCESS: ARVO database schema and policies have been set up.' as status;

    