
-- ### InvoChat Database Schema ###
-- This script is idempotent and can be run safely on new or existing databases.

-- --- Extensions ---
-- Enable UUID generation
create extension if not exists "uuid-ossp" with schema extensions;
-- Enable pgcrypto for cryptographic functions
create extension if not exists "pgcrypto" with schema extensions;


-- --- Types ---
-- Define custom types for roles and statuses
do $$
begin
    if not exists (select 1 from pg_type where typname = 'user_role') then
        create type public.user_role as enum ('Owner', 'Admin', 'Member');
    end if;
    if not exists (select 1 from pg_type where typname = 'integration_platform') then
        create type public.integration_platform as enum ('shopify', 'woocommerce', 'amazon_fba');
    end if;
     if not exists (select 1 from pg_type where typname = 'sync_status') then
        create type public.sync_status as enum ('syncing_products', 'syncing_sales', 'syncing', 'success', 'failed', 'idle');
    end if;
    if not exists (select 1 from pg_type where typname = 'product_status') then
        create type public.product_status as enum ('active', 'archived', 'draft');
    end if;
end
$$;


-- --- Tables ---

-- Companies Table
create table if not exists public.companies (
  id uuid not null primary key default uuid_generate_v4(),
  name text not null,
  created_at timestamptz not null default now()
);

-- Company Settings Table
create table if not exists public.company_settings (
  company_id uuid not null primary key references public.companies(id) on delete cascade,
  dead_stock_days integer not null default 90,
  overstock_multiplier integer not null default 3,
  high_value_threshold integer not null default 1000,
  fast_moving_days integer not null default 30,
  predictive_stock_days integer not null default 7,
  promo_sales_lift_multiplier real not null default 2.5,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);

-- Users Table (bridges auth.users and companies)
create table if not exists public.users (
  id uuid not null primary key references auth.users(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  email text,
  role public.user_role not null default 'Member',
  deleted_at timestamptz,
  created_at timestamptz default now()
);

-- Integrations Table
create table if not exists public.integrations (
  id uuid not null primary key default uuid_generate_v4(),
  company_id uuid not null references public.companies(id) on delete cascade,
  platform public.integration_platform not null,
  shop_domain text,
  shop_name text,
  is_active boolean default false,
  last_sync_at timestamptz,
  sync_status public.sync_status default 'idle',
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  unique(company_id, platform)
);

-- Products Table
create table if not exists public.products (
  id uuid not null primary key default uuid_generate_v4(),
  company_id uuid not null references public.companies(id) on delete cascade,
  title text not null,
  description text,
  handle text,
  product_type text,
  tags text[],
  status public.product_status,
  image_url text,
  external_product_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  unique(company_id, external_product_id)
);

-- Product Variants Table
create table if not exists public.product_variants (
  id uuid not null primary key default gen_random_uuid(),
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
  price integer,
  compare_at_price integer,
  cost integer,
  inventory_quantity integer not null default 0,
  weight numeric,
  weight_unit text,
  external_variant_id text,
  created_at timestamptz default now(),
  updated_at timestamptz,
  unique(company_id, sku),
  unique(company_id, external_variant_id)
);

-- Inventory Ledger Table
create table if not exists public.inventory_ledger (
  id uuid not null primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  variant_id uuid not null references public.product_variants(id) on delete cascade,
  change_type text not null,
  quantity_change integer not null,
  new_quantity integer not null,
  related_id uuid,
  notes text,
  created_at timestamptz not null default now()
);

-- Customers Table
create table if not exists public.customers (
    id uuid not null primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    customer_name text,
    email text,
    total_orders integer default 0,
    total_spent integer default 0,
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz default now(),
    unique(company_id, email)
);

-- Orders Table
create table if not exists public.orders (
  id uuid not null primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  order_number text not null,
  external_order_id text,
  customer_id uuid references public.customers(id),
  financial_status text,
  fulfillment_status text,
  currency text,
  subtotal integer not null default 0,
  total_tax integer default 0,
  total_shipping integer default 0,
  total_discounts integer default 0,
  total_amount integer not null,
  source_platform text,
  created_at timestamptz default now(),
  updated_at timestamptz
);

-- Order Line Items Table
create table if not exists public.order_line_items (
  id uuid not null primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  variant_id uuid references public.product_variants(id) on delete set null,
  company_id uuid not null references public.companies(id) on delete cascade,
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

-- Suppliers Table
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

-- Conversations Table
create table if not exists public.conversations (
  id uuid not null primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  title text not null,
  created_at timestamptz default now(),
  last_accessed_at timestamptz default now(),
  is_starred boolean default false
);

-- Messages Table
create table if not exists public.messages (
  id uuid not null primary key default uuid_generate_v4(),
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

-- Audit Log Table
create table if not exists public.audit_log (
  id bigserial primary key,
  company_id uuid references public.companies(id) on delete cascade,
  user_id uuid references auth.users(id),
  action text not null,
  details jsonb,
  created_at timestamptz default now()
);

-- Webhook Events Table - Corrected Definition
drop table if exists public.webhook_events cascade;
create table public.webhook_events (
  id uuid primary key default gen_random_uuid(),
  integration_id uuid not null references public.integrations(id) on delete cascade,
  webhook_id text not null,
  processed_at timestamptz default now(),
  created_at timestamptz default now(),
  unique(integration_id, webhook_id)
);


-- --- Helper Functions ---

create or replace function public.get_current_company_id()
returns uuid
language sql stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid;
$$;


-- --- Auth Triggers & Functions ---

-- This function runs when a new user signs up.
-- It creates a company, a settings entry, and a user record in the public schema.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
as $$
declare
  new_company_id uuid;
  user_role public.user_role := 'Owner';
begin
  -- Create a new company for the user
  insert into public.companies (name)
  values (new.raw_app_meta_data->>'company_name')
  returning id into new_company_id;

  -- Create a settings entry for the new company
  insert into public.company_settings (company_id)
  values (new_company_id);

  -- Create a corresponding public user profile
  insert into public.users (id, company_id, email, role)
  values (new.id, new_company_id, new.email, user_role);

  -- Update the user's app_metadata with the new company_id and role
  update auth.users
  set raw_app_meta_data = new.raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'role', user_role)
  where id = new.id;

  return new;
end;
$$;

-- Drop the trigger if it exists, then recreate it.
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();

-- This function runs when an existing user is invited to a company.
create or replace function public.handle_invited_user()
returns trigger
language plpgsql
security definer
as $$
declare
  user_role public.user_role := 'Member';
begin
  -- Create a public user profile for the invited user
  insert into public.users (id, company_id, email, role)
  values (new.id, (new.raw_app_meta_data->>'company_id')::uuid, new.email, user_role);

  -- Update the invited user's role in their metadata
  update auth.users
  set raw_app_meta_data = new.raw_app_meta_data || jsonb_build_object('role', user_role)
  where id = new.id;

  return new;
end;
$$;

-- Drop trigger if it exists, then recreate it.
drop trigger if exists on_auth_user_invited on auth.users;
create trigger on_auth_user_invited
  after insert on auth.users
  for each row
  when ((new.raw_app_meta_data->>'company_id') is not null and (new.raw_app_meta_data->>'provider') is null)
  execute function public.handle_invited_user();


-- --- Data Sync Functions ---

-- A single function to process incoming orders from any platform
drop function if exists public.record_order_from_platform(uuid, text, jsonb);
create or replace function public.record_order_from_platform(
    p_company_id uuid,
    p_platform text,
    p_order_payload jsonb
)
returns void
language plpgsql
as $$
declare
    v_customer_id uuid;
    v_order_id uuid;
    v_variant_id uuid;
    v_line_item jsonb;
    v_customer_email text;
    v_customer_name text;
    v_external_order_id text;
    v_order_created_at timestamptz;
begin
    -- Extract customer and order details based on platform
    if p_platform = 'shopify' then
        v_customer_email := p_order_payload->'customer'->>'email';
        v_customer_name := coalesce(
            p_order_payload->'customer'->>'first_name' || ' ' || p_order_payload->'customer'->>'last_name',
            p_order_payload->'customer'->>'email'
        );
        v_external_order_id := p_order_payload->>'id';
        v_order_created_at := (p_order_payload->>'created_at')::timestamptz;
    elsif p_platform = 'woocommerce' then
        v_customer_email := p_order_payload->'billing'->>'email';
        v_customer_name := coalesce(
            p_order_payload->'billing'->>'first_name' || ' ' || p_order_payload->'billing'->>'last_name',
            p_order_payload->'billing'->>'email'
        );
        v_external_order_id := p_order_payload->>'id';
        v_order_created_at := (p_order_payload->>'date_created_gmt')::timestamptz;
    else
        -- Fallback for manual or other integrations
        v_customer_email := p_order_payload->'customer'->>'email';
        v_customer_name := p_order_payload->'customer'->>'name';
        v_external_order_id := p_order_payload->>'id';
        v_order_created_at := (p_order_payload->>'created_at')::timestamptz;
    end if;

    -- Find or create the customer record
    if v_customer_email is not null then
        insert into public.customers (company_id, email, customer_name, first_order_date, total_orders, total_spent)
        values (p_company_id, v_customer_email, v_customer_name, v_order_created_at::date, 1, (p_order_payload->>'total_price')::numeric * 100)
        on conflict (company_id, email) do update
        set
            total_orders = customers.total_orders + 1,
            total_spent = customers.total_spent + (p_order_payload->>'total_price')::numeric * 100
        returning id into v_customer_id;
    end if;

    -- Create the order record
    insert into public.orders (company_id, customer_id, order_number, external_order_id, financial_status, fulfillment_status, total_amount, source_platform, created_at)
    values (
        p_company_id,
        v_customer_id,
        p_order_payload->>'name' or p_order_payload->>'order_number' or ('#' || (p_order_payload->>'id')),
        v_external_order_id,
        p_order_payload->>'financial_status',
        p_order_payload->>'fulfillment_status',
        (p_order_payload->>'total_price')::numeric * 100,
        p_platform,
        v_order_created_at
    )
    on conflict do nothing
    returning id into v_order_id;
    
    -- If order already exists, do nothing further
    if v_order_id is null then
        return;
    end if;

    -- Process line items
    for v_line_item in select * from jsonb_array_elements(p_order_payload->'line_items')
    loop
        -- Find the corresponding product variant
        select id into v_variant_id
        from public.product_variants
        where company_id = p_company_id and (
            sku = v_line_item->>'sku'
            or external_variant_id = v_line_item->>'id'
        )
        limit 1;
        
        -- Insert line item record
        insert into public.order_line_items (order_id, company_id, variant_id, product_name, sku, quantity, price, cost_at_time, external_line_item_id)
        values (
            v_order_id,
            p_company_id,
            v_variant_id,
            v_line_item->>'name',
            v_line_item->>'sku',
            (v_line_item->>'quantity')::integer,
            ((v_line_item->>'price')::numeric * 100)::integer,
            (select cost from public.product_variants where id = v_variant_id),
            v_line_item->>'id'
        );

        -- If variant exists, update inventory
        if v_variant_id is not null then
            update public.product_variants
            set inventory_quantity = inventory_quantity - (v_line_item->>'quantity')::integer
            where id = v_variant_id;

            -- Create inventory ledger entry
            insert into public.inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id)
            select p_company_id, v_variant_id, 'sale', -(v_line_item->>'quantity')::integer, pv.inventory_quantity, v_order_id
            from public.product_variants pv
            where pv.id = v_variant_id;
        end if;
    end loop;
end;
$$;


-- --- Row Level Security (RLS) ---
-- Enable RLS for all tables
alter table public.companies enable row level security;
alter table public.users enable row level security;
alter table public.company_settings enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.inventory_ledger enable row level security;
alter table public.customers enable row level security;
alter table public.orders enable row level security;
alter table public.order_line_items enable row level security;
alter table public.suppliers enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.integrations enable row level security;
alter table public.audit_log enable row level security;
alter table public.webhook_events enable row level security;

-- Policies
drop policy if exists "Allow full access based on company_id" on public.companies;
create policy "Allow full access based on company_id" on public.companies for all using (id = get_current_company_id()) with check (id = get_current_company_id());

drop policy if exists "Allow full access to own user data" on public.users;
create policy "Allow full access to own user data" on public.users for all using (id = auth.uid()) with check (id = auth.uid());
drop policy if exists "Allow read access to other users in same company" on public.users;
create policy "Allow read access to other users in same company" on public.users for select using (company_id = get_current_company_id());

drop policy if exists "Allow full access based on company_id" on public.company_settings;
create policy "Allow full access based on company_id" on public.company_settings for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

drop policy if exists "Allow full access based on company_id" on public.products;
create policy "Allow full access based on company_id" on public.products for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

drop policy if exists "Allow full access based on company_id" on public.product_variants;
create policy "Allow full access based on company_id" on public.product_variants for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

drop policy if exists "Allow full access based on company_id" on public.inventory_ledger;
create policy "Allow full access based on company_id" on public.inventory_ledger for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

drop policy if exists "Allow full access based on company_id" on public.customers;
create policy "Allow full access based on company_id" on public.customers for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

drop policy if exists "Allow full access based on company_id" on public.orders;
create policy "Allow full access based on company_id" on public.orders for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

drop policy if exists "Allow full access based on company_id" on public.order_line_items;
create policy "Allow full access based on company_id" on public.order_line_items for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

drop policy if exists "Allow full access based on company_id" on public.suppliers;
create policy "Allow full access based on company_id" on public.suppliers for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

drop policy if exists "Allow full access to own conversations" on public.conversations;
create policy "Allow full access to own conversations" on public.conversations for all using (user_id = auth.uid() and company_id = get_current_company_id()) with check (user_id = auth.uid() and company_id = get_current_company_id());

drop policy if exists "Allow full access to messages in own conversations" on public.messages;
create policy "Allow full access to messages in own conversations" on public.messages for all using (company_id = get_current_company_id() and conversation_id in (select id from public.conversations where user_id = auth.uid()));

drop policy if exists "Allow full access based on company_id" on public.integrations;
create policy "Allow full access based on company_id" on public.integrations for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

drop policy if exists "Allow read access to company audit log" on public.audit_log;
create policy "Allow read access to company audit log" on public.audit_log for select using (company_id = get_current_company_id());

drop policy if exists "Allow read access to webhook_events" on public.webhook_events;
create policy "Allow read access to webhook_events" on public.webhook_events for select using (
    integration_id in (select id from public.integrations where company_id = get_current_company_id())
);

-- Force RLS for all users, including service_role
alter table public.companies force row level security;
alter table public.users force row level security;
alter table public.company_settings force row level security;
alter table public.products force row level security;
alter table public.product_variants force row level security;
alter table public.inventory_ledger force row level security;
alter table public.customers force row level security;
alter table public.orders force row level security;
alter table public.order_line_items force row level security;
alter table public.suppliers force row level security;
alter table public.conversations force row level security;
alter table public.messages force row level security;
alter table public.integrations force row level security;
alter table public.audit_log force row level security;
alter table public.webhook_events force row level security;
