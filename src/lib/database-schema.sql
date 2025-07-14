
-- ### InvoChat Database Schema ###
-- This script is designed to be idempotent, meaning it can be run multiple
-- times without causing errors or creating duplicate objects.

-- 1. Extensions
-- Enable the UUID extension for generating unique identifiers.
create extension if not exists "uuid-ossp" with schema extensions;
-- Enable the PGroonga extension for fast full-text search.
create extension if not exists pgroonga with schema extensions;
-- Enable the Vault extension for encrypting secrets.
create extension if not exists "supabase_vault" with schema "vault";

-- 2. Custom Types
-- It's often better to manage custom types in code or use standard types.
-- For simplicity, we'll use TEXT and handle validation in the application layer.

-- 3. Tables
-- The core tables of the application are defined here.
-- We use "if not exists" to prevent errors on subsequent runs.

create table if not exists public.companies (
    id uuid primary key default uuid_generate_v4(),
    name text not null,
    created_at timestamptz not null default now()
);
comment on table public.companies is 'Stores information about each company or organization using the app.';

-- SECURITY FIX (#11, #74): Create a `profiles` table to store user-specific data, including roles.
-- This avoids trying to modify the protected `auth.users` table.
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  first_name text,
  last_name text,
  role text not null default 'Member', -- 'Admin' or 'Member'
  updated_at timestamptz,
  constraint proper_email check (email ~* '^[A-Za-z0-9._+%-]+@[A-Za-z0-9.-]+[.][A-Za-z]+$'),
  constraint check_user_role check (role in ('Admin', 'Member'))
);
comment on table public.profiles is 'Stores public profile information for each user.';

create table if not exists public.company_settings (
    company_id uuid primary key references public.companies(id) on delete cascade,
    dead_stock_days integer not null default 90,
    fast_moving_days integer not null default 30,
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
    promo_sales_lift_multiplier real not null default 2.5,
    overstock_multiplier integer not null default 3,
    high_value_threshold integer not null default 1000
);
comment on table public.company_settings is 'Stores business logic settings for each company.';

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
comment on table public.products is 'Stores product master data.';

create table if not exists public.locations (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    name text not null,
    is_default boolean default false,
    created_at timestamptz not null default now()
);
comment on table public.locations is 'Stores inventory locations like warehouses or stores.';

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
    location text, -- simple text field for bin location
    external_variant_id text,
    created_at timestamptz not null default now(),
    updated_at timestamptz,
    unique(company_id, sku),
    unique(company_id, external_variant_id)
);
comment on table public.product_variants is 'Stores individual product variants (SKUs).';

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
comment on table public.inventory_ledger is 'Transactional log of all inventory movements for auditing.';

create table if not exists public.customers (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    customer_name text,
    email text,
    total_orders integer default 0,
    total_spent numeric default 0,
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz default now()
);
comment on table public.customers is 'Stores customer information.';

create table if not exists public.orders (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    order_number text not null,
    external_order_id text,
    customer_id uuid references public.customers(id) on delete set null,
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
    updated_at timestamptz default now()
);
comment on table public.orders is 'Stores order information.';

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
comment on table public.order_line_items is 'Stores line items for each order.';

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
comment on table public.suppliers is 'Stores supplier and vendor information.';

create table if not exists public.purchase_orders (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    supplier_id uuid references public.suppliers(id) on delete set null,
    status text not null default 'Draft',
    po_number text not null,
    total_cost integer not null,
    expected_arrival_date date,
    created_at timestamptz not null default now()
);

create table if not exists public.purchase_order_line_items (
    id uuid primary key default uuid_generate_v4(),
    purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    quantity integer not null,
    cost integer not null
);

create table if not exists public.integrations (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    platform text not null, -- e.g., 'shopify', 'woocommerce'
    shop_domain text,
    shop_name text,
    is_active boolean default false,
    last_sync_at timestamptz,
    sync_status text,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);

create table if not exists public.conversations (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid not null references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    title text not null,
    created_at timestamptz default now(),
    last_accessed_at timestamptz default now(),
    is_starred boolean default false
);

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
    created_at timestamptz default now(),
    is_error boolean default false
);

create table if not exists public.audit_log (
  id bigserial primary key,
  company_id uuid references public.companies(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  action text not null,
  details jsonb,
  created_at timestamptz default now()
);

-- SECURITY FIX (#87): Add a unique constraint to prevent webhook deduplication issues.
create table if not exists public.webhook_events (
    id uuid primary key default gen_random_uuid(),
    integration_id uuid not null references public.integrations(id) on delete cascade,
    webhook_id text not null,
    processed_at timestamptz default now(),
    created_at timestamptz default now(),
    unique(integration_id, webhook_id)
);

-- 4. Helper Functions
-- These functions simplify RLS policies and other database logic.
-- SECURITY FIX (#74): Use `SECURITY INVOKER` instead of `SECURITY DEFINER`
-- to run functions with the permissions of the calling user, not as superuser.

create or replace function public.get_current_user_id()
returns uuid
language sql
security invoker
stable
as $$
  select auth.uid();
$$;

create or replace function public.get_current_company_id()
returns uuid
language sql
security invoker
stable
as $$
  select company_id from public.profiles where id = auth.uid();
$$;

-- 5. User Creation and Company Setup Trigger
-- This function automatically creates a company and profile for a new user.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer -- Must be definer to write to public.companies
set search_path = public
as $$
declare
  new_company_id uuid;
  company_name_from_meta text := new.raw_app_meta_data->>'company_name';
begin
  -- Create a new company for the user
  insert into public.companies (name)
  values (coalesce(company_name_from_meta, 'My Company'))
  returning id into new_company_id;

  -- Create a profile for the new user, linking them to the new company as 'Admin'
  insert into public.profiles (id, company_id, role)
  values (new.id, new_company_id, 'Admin');
  
  -- Create default settings for the new company
  insert into public.company_settings (company_id)
  values (new_company_id);

  return new;
end;
$$;

-- Drop the trigger if it exists, then create it.
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- 6. Row-Level Security (RLS) Policies
-- These policies enforce data isolation between companies.

alter table public.companies enable row level security;
alter table public.profiles enable row level security;
alter table public.company_settings enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.inventory_ledger enable row level security;
alter table public.customers enable row level security;
alter table public.orders enable row level security;
alter table public.order_line_items enable row level security;
alter table public.suppliers enable row level security;
alter table public.integrations enable row level security;
alter table public.purchase_orders enable row level security;
alter table public.purchase_order_line_items enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.audit_log enable row level security;
alter table public.webhook_events enable row level security;
alter table public.locations enable row level security;


-- Drop policies before creating them to ensure idempotency.
drop policy if exists "Allow full access based on company_id" on public.companies;
create policy "Allow full access based on company_id" on public.companies
  for all using (id = get_current_company_id()) with check (id = get_current_company_id());

drop policy if exists "Users can only see profiles in their own company" on public.profiles;
create policy "Users can only see profiles in their own company" on public.profiles
  for select using (company_id = get_current_company_id());

drop policy if exists "Users can update their own profile" on public.profiles;
create policy "Users can update their own profile" on public.profiles
  for update using (id = auth.uid());

-- Generic policies for most tables
create or replace function public.create_company_rls_policy(table_name text)
returns void as $$
begin
  execute format('
    drop policy if exists "Allow full access based on company_id" on public.%I;
    create policy "Allow full access based on company_id" on public.%I
      for all using (company_id = get_current_company_id())
      with check (company_id = get_current_company_id());
  ', table_name, table_name);
end;
$$ language plpgsql;

select public.create_company_rls_policy('company_settings');
select public.create_company_rls_policy('products');
select public.create_company_rls_policy('product_variants');
select public.create_company_rls_policy('inventory_ledger');
select public.create_company_rls_policy('customers');
select public.create_company_rls_policy('orders');
select public.create_company_rls_policy('order_line_items');
select public.create_company_rls_policy('suppliers');
select public.create_company_rls_policy('integrations');
select public.create_company_rls_policy('purchase_orders');
select public.create_company_rls_policy('purchase_order_line_items');
select public.create_company_rls_policy('audit_log');
select public.create_company_rls_policy('locations');

-- Specific RLS for conversations and messages based on user
drop policy if exists "Users can manage their own conversations" on public.conversations;
create policy "Users can manage their own conversations" on public.conversations
  for all using (user_id = auth.uid());

drop policy if exists "Users can manage messages in their conversations" on public.messages;
create policy "Users can manage messages in their conversations" on public.messages
  for all using (company_id = get_current_company_id());


-- 7. Database Views
-- These views simplify complex queries.

drop view if exists public.product_variants_with_details;
create or replace view public.product_variants_with_details as
select
  pv.*,
  p.title as product_title,
  p.status as product_status,
  p.image_url
from
  public.product_variants pv
  left join public.products p on pv.product_id = p.id;

-- 8. Indexes for Performance
-- Create indexes on frequently queried columns.
create index if not exists idx_products_company_id on public.products(company_id);
create index if not exists idx_variants_company_id on public.product_variants(company_id);
create index if not exists idx_variants_sku on public.product_variants(sku);
create index if not exists idx_orders_company_id on public.orders(company_id);
create index if not exists idx_orders_created_at on public.orders(created_at desc);
create index if not exists idx_line_items_order_id on public.order_line_items(order_id);
create index if not exists idx_ledger_variant_id on public.inventory_ledger(variant_id);
create index if not exists idx_ledger_created_at on public.inventory_ledger(created_at desc);

-- SECURITY FIX (#73, #91): Create a PGroonga index that includes company_id for secure full-text search.
drop index if exists pgroonga_products_title_index;
create index if not exists pgroonga_products_title_index on public.products using pgroonga (company_id, title);
comment on index pgroonga_products_title_index is 'Enables fast, secure full-text search on product titles, scoped to the company.';

-- Add other missing high-cardinality indexes
create index if not exists idx_orders_external_id on public.orders(external_order_id);
create index if not exists idx_customers_email on public.customers(email);


-- 9. RPC Functions for Business Logic
-- These functions encapsulate complex business logic and can be called from the application.
-- All functions are set to `SECURITY INVOKER` to run with the caller's permissions.

-- Example: Function to get dashboard metrics (this would be much more complex in a real app)
create or replace function public.get_dashboard_metrics(p_company_id uuid, p_days int)
returns jsonb
language plpgsql
security invoker
as $$
declare
    metrics jsonb;
begin
    -- This is a simplified example. A real implementation would involve complex queries.
    select jsonb_build_object(
        'total_revenue', 0,
        'revenue_change', 0,
        'total_sales', 0,
        'sales_change', 0,
        'new_customers', 0,
        'customers_change', 0,
        'dead_stock_value', 0,
        'sales_over_time', '[]'::jsonb,
        'top_selling_products', '[]'::jsonb,
        'inventory_summary', '{"total_value": 0, "in_stock_value": 0, "low_stock_value": 0, "dead_stock_value": 0}'::jsonb
    ) into metrics;
    return metrics;
end;
$$;

-- Add other RPC functions here...

-- Final grant to ensure authenticated users can use the public schema.
grant usage on schema public to authenticated;
grant all privileges on all tables in schema public to authenticated;
grant all privileges on all functions in schema public to authenticated;
grant all privileges on all sequences in schema public to authenticated;

-- Grant access to the pgroonga schema for searching
grant usage on schema pgroonga to authenticated;

comment on schema public is 'Standard public schema for application data';
