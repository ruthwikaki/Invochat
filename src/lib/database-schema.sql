-- InvoChat Database Schema
-- Version: 1.0.1
-- Description: Sets up the initial database schema for the InvoChat application.

-- Enable UUID generation
create extension if not exists "uuid-ossp";

-- Enable cryptographic functions
create extension if not exists "pgcrypto";

-- Grant usage on the auth schema to the postgres user
grant usage on schema auth to postgres;
grant all on all tables in schema auth to postgres;
grant all on all functions in schema auth to postgres;
grant all on all sequences in schema auth to postgres;

-- Custom Types
do $$
begin
    if not exists (select 1 from pg_type where typname = 'user_role') then
        create type public.user_role as enum ('Owner', 'Admin', 'Member');
    end if;
end$$;

-- Tables
create table if not exists public.companies (
    id uuid primary key default uuid_generate_v4(),
    name text not null,
    created_at timestamptz not null default now()
);
alter table public.companies enable row level security;


create table if not exists public.users (
    id uuid primary key references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    email text,
    role public.user_role default 'Member',
    deleted_at timestamptz,
    created_at timestamptz default now()
);
alter table public.users enable row level security;


create table if not exists public.company_settings (
    company_id uuid primary key references public.companies(id) on delete cascade,
    dead_stock_days int not null default 90,
    fast_moving_days int not null default 30,
    overstock_multiplier int not null default 3,
    high_value_threshold int not null default 1000, -- in cents
    predictive_stock_days int not null default 7,
    currency text default 'USD',
    timezone text default 'UTC',
    tax_rate numeric default 0.0,
    promo_sales_lift_multiplier real not null default 2.5,
    custom_rules jsonb,
    subscription_status text default 'trial',
    subscription_plan text default 'starter',
    subscription_expires_at timestamptz,
    stripe_customer_id text,
    stripe_subscription_id text,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);
alter table public.company_settings enable row level security;


create table if not exists public.products (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id),
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
    updated_at timestamptz
);
alter table public.products enable row level security;


create table if not exists public.product_variants (
    id uuid primary key default gen_random_uuid(),
    product_id uuid not null references public.products(id) on delete cascade,
    company_id uuid not null references public.companies(id),
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
    inventory_quantity int not null default 0,
    location text,
    external_variant_id text,
    deleted_at timestamptz,
    created_at timestamptz default now(),
    updated_at timestamptz default now()
);
alter table public.product_variants enable row level security;


create table if not exists public.customers (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id),
    customer_name text not null,
    email text,
    total_orders int default 0,
    total_spent int default 0, -- in cents
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz default now()
);
alter table public.customers enable row level security;


create table if not exists public.orders (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id),
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


create table if not exists public.order_line_items (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id),
    order_id uuid not null references public.orders(id) on delete cascade,
    product_id uuid not null references public.products(id),
    variant_id uuid not null references public.product_variants(id),
    product_name text not null,
    variant_title text,
    sku text not null,
    quantity int not null,
    price int not null, -- in cents
    total_discount int default 0, -- in cents
    tax_amount int default 0, -- in cents
    cost_at_time int, -- in cents
    fulfillment_status text default 'unfulfilled',
    requires_shipping boolean default true,
    external_line_item_id text
);
alter table public.order_line_items enable row level security;


create table if not exists public.suppliers (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id),
    name text not null,
    email text,
    phone text,
    default_lead_time_days int,
    notes text,
    created_at timestamptz not null default now()
);
alter table public.suppliers enable row level security;


create table if not exists public.purchase_orders (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id),
    supplier_id uuid references public.suppliers(id),
    status text not null default 'Draft',
    po_number text not null,
    total_cost int not null, -- in cents
    expected_arrival_date date,
    idempotency_key uuid,
    created_at timestamptz not null default now()
);
alter table public.purchase_orders enable row level security;


create table if not exists public.purchase_order_line_items (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id),
    purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id),
    quantity int not null,
    cost int not null -- in cents
);
alter table public.purchase_order_line_items enable row level security;


create table if not exists public.inventory_ledger (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id),
    variant_id uuid not null references public.product_variants(id),
    change_type text not null, -- 'sale', 'purchase_order', 'reconciliation', 'manual_adjustment'
    quantity_change int not null,
    new_quantity int not null,
    related_id uuid, -- e.g., order_id, purchase_order_id
    notes text,
    created_at timestamptz not null default now()
);
alter table public.inventory_ledger enable row level security;


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


create table if not exists public.conversations (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid not null references auth.users(id),
    company_id uuid not null references public.companies(id),
    title text not null,
    is_starred boolean default false,
    created_at timestamptz default now(),
    last_accessed_at timestamptz default now()
);
alter table public.conversations enable row level security;


create table if not exists public.messages (
    id uuid primary key default uuid_generate_v4(),
    conversation_id uuid not null references public.conversations(id) on delete cascade,
    company_id uuid not null references public.companies(id),
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


create table if not exists public.webhook_events (
    id uuid primary key default gen_random_uuid(),
    integration_id uuid not null references public.integrations(id) on delete cascade,
    webhook_id text not null,
    processed_at timestamptz default now(),
    created_at timestamptz default now()
);
alter table public.webhook_events enable row level security;

-- Unique Constraints
alter table public.integrations drop constraint if exists integrations_company_id_platform_key;
alter table public.integrations add constraint integrations_company_id_platform_key unique (company_id, platform);

alter table public.webhook_events drop constraint if exists webhook_events_integration_id_webhook_id_key;
alter table public.webhook_events add constraint webhook_events_integration_id_webhook_id_key unique (integration_id, webhook_id);

alter table public.product_variants drop constraint if exists product_variants_company_id_external_variant_id_key;
alter table public.product_variants add constraint product_variants_company_id_external_variant_id_key unique (company_id, external_variant_id);

alter table public.products drop constraint if exists products_company_id_external_product_id_key;
alter table public.products add constraint products_company_id_external_product_id_key unique (company_id, external_product_id);


-- Helper Functions
create or replace function public.get_company_id()
returns uuid
language sql
security definer
set search_path = public
as $$
    select (auth.jwt()->>'app_metadata')::jsonb->>'company_id'::text;
$$;


-- Row Level Security (RLS) Policies
drop policy if exists "Allow users to see their own company" on public.companies;
create policy "Allow users to see their own company"
on public.companies for select
using (id = public.get_company_id());

drop policy if exists "Allow users to manage their own settings" on public.company_settings;
create policy "Allow users to manage their own settings"
on public.company_settings for all
using (company_id = public.get_company_id());

drop policy if exists "Allow users to manage their own data" on public.products;
create policy "Allow users to manage their own data" on public.products for all using (company_id = public.get_company_id());
drop policy if exists "Allow users to manage their own data" on public.product_variants;
create policy "Allow users to manage their own data" on public.product_variants for all using (company_id = public.get_company_id());
drop policy if exists "Allow users to manage their own data" on public.customers;
create policy "Allow users to manage their own data" on public.customers for all using (company_id = public.get_company_id());
drop policy if exists "Allow users to manage their own data" on public.orders;
create policy "Allow users to manage their own data" on public.orders for all using (company_id = public.get_company_id());
drop policy if exists "Allow users to manage their own data" on public.order_line_items;
create policy "Allow users to manage their own data" on public.order_line_items for all using (company_id = public.get_company_id());
drop policy if exists "Allow users to manage their own data" on public.suppliers;
create policy "Allow users to manage their own data" on public.suppliers for all using (company_id = public.get_company_id());
drop policy if exists "Allow users to manage their own data" on public.purchase_orders;
create policy "Allow users to manage their own data" on public.purchase_orders for all using (company_id = public.get_company_id());
drop policy if exists "Allow users to manage their own data" on public.purchase_order_line_items;
create policy "Allow users to manage their own data" on public.purchase_order_line_items for all using (company_id = public.get_company_id());
drop policy if exists "Allow users to manage their own data" on public.inventory_ledger;
create policy "Allow users to manage their own data" on public.inventory_ledger for all using (company_id = public.get_company_id());
drop policy if exists "Allow users to manage their own data" on public.integrations;
create policy "Allow users to manage their own data" on public.integrations for all using (company_id = public.get_company_id());
drop policy if exists "Allow users to see their own team" on public.users;
create policy "Allow users to see their own team" on public.users for select using (company_id = public.get_company_id());
drop policy if exists "Allow users to manage their conversations" on public.conversations;
create policy "Allow users to manage their conversations" on public.conversations for all using (company_id = public.get_company_id());
drop policy if exists "Allow users to manage their messages" on public.messages;
create policy "Allow users to manage their messages" on public.messages for all using (company_id = public.get_company_id());
drop policy if exists "Allow users to manage their own webhook events" on public.webhook_events;
create policy "Allow users to manage their own webhook events" on public.webhook_events for all using (integration_id in (select id from public.integrations where company_id = public.get_company_id()));

-- This is the function that will be called by the trigger
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
  -- Extract company_name from app_metadata.
  company_name := new.raw_app_meta_data->>'company_name';
  user_email := new.email;
  
  -- Create a new company for the new user.
  insert into public.companies (name)
  values (company_name)
  returning id into company_id;

  -- Create a corresponding user entry in the public.users table.
  insert into public.users (id, company_id, email, role)
  values (new.id, company_id, user_email, 'Owner');
  
  -- Update the user's app_metadata in auth.users to include the new company_id.
  -- This is crucial for RLS policies to work correctly.
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id, 'role', 'Owner')
  where id = new.id;
  
  return new;
end;
$$;

-- A security definer function to create the trigger
create or replace function public.security_definer_handle_new_user()
returns void
language plpgsql
security definer
as $$
begin
  -- Drop the trigger if it exists
  if exists (
    select 1
    from pg_trigger
    where tgname = 'on_auth_user_created'
  ) then
    drop trigger on_auth_user_created on auth.users;
  end if;

  -- Create the trigger to call the handle_new_user function
  create trigger on_auth_user_created
    after insert on auth.users
    for each row execute procedure public.handle_new_user();
end;
$$;

-- Execute the security definer function to create the trigger
select public.security_definer_handle_new_user();


-- Views for easier data access
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
    pv.deleted_at,
    pv.created_at,
    pv.updated_at,
    p.title as product_title,
    p.status as product_status,
    p.image_url as image_url,
    p.product_type
from
    public.product_variants pv
join
    public.products p on pv.product_id = p.id
where pv.deleted_at is null and p.deleted_at is null;


create or replace view public.customers_view as
select
    c.id,
    c.company_id,
    c.customer_name,
    c.email,
    count(o.id) as total_orders,
    sum(o.total_amount) as total_spent,
    min(o.created_at) as first_order_date,
    c.created_at
from
    public.customers c
left join
    public.orders o on c.id = o.customer_id
where c.deleted_at is null
group by
    c.id;
    

create or replace view public.orders_view as
select
    o.id,
    o.company_id,
    o.order_number,
    o.created_at,
    c.email as customer_email,
    o.financial_status,
    o.fulfillment_status,
    o.total_amount,
    o.source_platform
from
    public.orders o
left join
    public.customers c on o.customer_id = c.id
where c.deleted_at is null;


-- Indexes for performance
create index if not exists idx_products_company_id on public.products(company_id);
create index if not exists idx_product_variants_product_id on public.product_variants(product_id);
create index if not exists idx_product_variants_sku on public.product_variants(company_id, sku);
create index if not exists idx_orders_company_id on public.orders(company_id);
create index if not exists idx_order_line_items_order_id on public.order_line_items(order_id);
create index if not exists idx_inventory_ledger_variant_id on public.inventory_ledger(variant_id);

-- Add a GIN index for full-text search on products
create index if not exists products_fts_document_idx on public.products using gin(fts_document);

-- Function and trigger to update the fts_document column automatically
create or replace function update_fts_document()
returns trigger as $$
begin
    new.fts_document :=
        to_tsvector('english', coalesce(new.title, '')) ||
        to_tsvector('english', coalesce(new.description, ''));
    return new;
end;
$$ language plpgsql;

-- Drop trigger if it exists before creating it
do $$
begin
    if not exists (
        select 1 from pg_trigger where tgname = 'tsvectorupdate' and tgrelid = 'public.products'::regclass
    ) then
        create trigger tsvectorupdate
        before insert or update on public.products
        for each row execute procedure update_fts_document();
    end if;
end;
$$;
