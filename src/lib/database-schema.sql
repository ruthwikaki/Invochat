-- This script is designed to be idempotent, meaning it can be run multiple times without causing errors.

-- 1. Extensions
-- Ensure necessary extensions are enabled.
create extension if not exists "uuid-ossp";
create extension if not exists "vector";

-- 2. Custom Types
-- It's often better to drop and recreate types if they change, but for this app, we'll assume they are stable.
do $$
begin
    if not exists (select 1 from pg_type where typname = 'user_role') then
        create type public.user_role as enum ('Owner', 'Admin', 'Member');
    end if;
end$$;


-- 3. Helper Functions
-- These functions provide utility for other parts of the database, like getting the current user's ID or company ID from a JWT.

-- Extracts the company_id from the current user's JWT.
-- Returns the company_id UUID or null if not found.
create or replace function public.get_current_company_id()
returns uuid
language sql
security definer
set search_path = public
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid;
$$;

-- Extracts the user's role from the current user's JWT.
-- Returns the role as text or null if not found.
create or replace function public.get_current_user_role()
returns text
language sql
security definer
set search_path = public
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'role', '');
$$;


-- 4. Tables
-- The core data structures for the application.

create table if not exists public.companies (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.users (
    id uuid references auth.users not null primary key,
    company_id uuid references public.companies on delete cascade not null,
    email text,
    role public.user_role not null default 'Member', -- Use the custom type
    deleted_at timestamptz,
    created_at timestamptz default now()
);

create table if not exists public.company_settings (
  company_id uuid primary key references public.companies on delete cascade not null,
  dead_stock_days integer not null default 90,
  fast_moving_days integer not null default 30,
  overstock_multiplier integer not null default 3,
  high_value_threshold integer not null default 1000,
  predictive_stock_days integer not null default 7,
  promo_sales_lift_multiplier real not null default 2.5,
  currency text default 'USD',
  timezone text default 'UTC',
  created_at timestamptz not null default now(),
  updated_at timestamptz
);

create table if not exists public.products (
  id uuid primary key default uuid_generate_v4(),
  company_id uuid not null references public.companies on delete cascade,
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
create index if not exists idx_products_company_id on public.products(company_id);


create table if not exists public.product_variants (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products on delete cascade,
  company_id uuid not null references public.companies on delete cascade,
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
  external_variant_id text,
  weight numeric,
  weight_unit text,
  created_at timestamptz default now(),
  updated_at timestamptz,
  unique(company_id, sku),
  unique(company_id, external_variant_id)
);
create index if not exists idx_variants_product_id on public.product_variants(product_id);
create index if not exists idx_variants_company_id on public.product_variants(company_id);


create table if not exists public.suppliers (
  id uuid primary key default uuid_generate_v4(),
  company_id uuid not null references public.companies on delete cascade,
  name text not null,
  email text,
  phone text,
  default_lead_time_days integer,
  notes text,
  created_at timestamptz not null default now(),
  unique(company_id, name)
);

create table if not exists public.customers (
  id uuid primary key default uuid_generate_v4(),
  company_id uuid not null references public.companies on delete cascade,
  customer_name text not null,
  email text,
  total_orders integer default 0,
  total_spent numeric default 0,
  first_order_date date,
  deleted_at timestamptz,
  created_at timestamptz default now()
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies on delete cascade,
  order_number text not null,
  external_order_id text,
  customer_id uuid references public.customers on delete set null,
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
  updated_at timestamptz
);

create table if not exists public.order_line_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders on delete cascade,
  company_id uuid not null references public.companies on delete cascade,
  variant_id uuid references public.product_variants on delete set null,
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

create table if not exists public.inventory_ledger (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies on delete cascade,
  variant_id uuid not null references public.product_variants on delete cascade,
  change_type text not null,
  quantity_change integer not null,
  new_quantity integer not null,
  related_id uuid,
  notes text,
  created_at timestamptz not null default now()
);

create table if not exists public.conversations (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users on delete cascade,
  company_id uuid not null references public.companies on delete cascade,
  title text not null,
  is_starred boolean default false,
  created_at timestamptz default now(),
  last_accessed_at timestamptz default now()
);

create table if not exists public.messages (
  id uuid primary key default uuid_generate_v4(),
  conversation_id uuid not null references public.conversations on delete cascade,
  company_id uuid not null references public.companies on delete cascade,
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

create table if not exists public.integrations (
  id uuid primary key default uuid_generate_v4(),
  company_id uuid not null references public.companies on delete cascade,
  platform text not null,
  shop_domain text,
  shop_name text,
  is_active boolean default false,
  last_sync_at timestamptz,
  sync_status text,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  unique(company_id, platform)
);

create table if not exists public.channel_fees (
  id uuid primary key default uuid_generate_v4(),
  company_id uuid not null references public.companies on delete cascade,
  channel_name text not null,
  percentage_fee numeric not null,
  fixed_fee numeric not null,
  created_at timestamptz default now(),
  updated_at timestamptz,
  unique(company_id, channel_name)
);

create table if not exists public.export_jobs (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies on delete cascade,
    requested_by_user_id uuid not null references auth.users on delete cascade,
    status text not null default 'pending',
    download_url text,
    expires_at timestamptz,
    created_at timestamptz not null default now()
);

create table if not exists public.audit_log (
    id bigserial primary key,
    company_id uuid references public.companies on delete cascade,
    user_id uuid references auth.users on delete set null,
    action text not null,
    details jsonb,
    created_at timestamptz default now()
);

-- Correct definition for webhook_events table
create table if not exists public.webhook_events (
    id uuid primary key default gen_random_uuid(),
    integration_id uuid not null references public.integrations on delete cascade,
    webhook_id text not null,
    created_at timestamptz default now(),
    unique(integration_id, webhook_id)
);


-- 5. Data Processing & Business Logic Functions

-- This function is called automatically when a new user signs up.
-- It creates a new company and a corresponding entry in our public.users table.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  new_company_id uuid;
  user_email text;
  company_name text;
begin
  -- 1. Create a new company for the user.
  company_name := new.raw_app_meta_data ->> 'company_name';
  if company_name is null then
    -- Fallback if company_name is not in app_metadata
    company_name := 'My Company';
  end if;

  insert into public.companies (name)
  values (company_name)
  returning id into new_company_id;

  -- 2. Create an entry in our public.users table.
  user_email := new.email;
  insert into public.users (id, company_id, email, role)
  values (new.id, new_company_id, user_email, 'Owner');

  -- 3. Update the user's app_metadata with the new company_id and role.
  -- This makes it accessible in RLS policies via get_current_company_id().
  new.raw_app_meta_data := new.raw_app_meta_data || jsonb_build_object(
      'company_id', new_company_id,
      'role', 'Owner'
  );

  return new;
end;
$$;

-- Function to handle inventory changes and log them transactionally
create or replace function public.update_inventory_and_log(
    p_company_id uuid,
    p_variant_id uuid,
    p_quantity_change integer,
    p_change_type text,
    p_related_id uuid default null,
    p_notes text default null
)
returns integer
language plpgsql
as $$
declare
    new_quantity_val integer;
begin
    -- Update the inventory quantity for the specific variant
    update public.product_variants
    set inventory_quantity = inventory_quantity + p_quantity_change
    where id = p_variant_id and company_id = p_company_id
    returning inventory_quantity into new_quantity_val;

    -- If the update was successful, log the change
    if new_quantity_val is not null then
        insert into public.inventory_ledger(company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes)
        values (p_company_id, p_variant_id, p_change_type, p_quantity_change, new_quantity_val, p_related_id, p_notes);
    else
        -- This case handles if the variant_id doesn't exist or doesn't belong to the company
        raise exception 'Product variant not found or does not belong to the specified company.';
    end if;
    
    return new_quantity_val;
end;
$$;

-- This is the main function for processing orders from external platforms
drop function if exists public.record_order_from_platform(uuid, text, jsonb);
create or replace function public.record_order_from_platform(
    p_company_id uuid,
    p_platform text,
    p_order_payload jsonb
)
returns uuid
language plpgsql
as $$
declare
    v_customer_id uuid;
    v_order_id uuid;
    v_variant_id uuid;
    v_line_item jsonb;
    v_customer_name text;
    v_customer_email text;
    v_external_order_id text;
    v_order_number text;
begin
    -- Check if the order has already been processed to prevent duplicates
    v_external_order_id := p_order_payload ->> 'id';
    
    if exists (select 1 from public.orders where external_order_id = v_external_order_id and company_id = p_company_id) then
        -- Order already exists, so we can skip it.
        return null;
    end if;
    
    -- Extract and find or create the customer
    if p_platform = 'shopify' then
        v_customer_name := concat_ws(' ', p_order_payload -> 'customer' ->> 'first_name', p_order_payload -> 'customer' ->> 'last_name');
        v_customer_email := p_order_payload -> 'customer' ->> 'email';
    elsif p_platform = 'woocommerce' then
        v_customer_name := concat_ws(' ', p_order_payload -> 'billing' ->> 'first_name', p_order_payload -> 'billing' ->> 'last_name');
        v_customer_email := p_order_payload -> 'billing' ->> 'email';
    else
        -- Fallback for other platforms or manual entries
        v_customer_name := 'Unknown Customer';
        v_customer_email := null;
    end if;

    if v_customer_email is not null then
        select id into v_customer_id from public.customers where email = v_customer_email and company_id = p_company_id;
        if v_customer_id is null then
            insert into public.customers (company_id, customer_name, email, first_order_date)
            values (p_company_id, v_customer_name, v_customer_email, (p_order_payload ->> 'created_at')::date)
            returning id into v_customer_id;
        end if;
    else
        v_customer_id := null;
    end if;

    -- Extract order number
    if p_platform = 'shopify' then
        v_order_number := p_order_payload ->> 'order_number';
    else
        v_order_number := p_order_payload ->> 'number';
    end if;

    -- Insert the main order record
    insert into public.orders (company_id, order_number, external_order_id, customer_id, financial_status, fulfillment_status, total_amount, source_platform, created_at, notes)
    values (
        p_company_id,
        v_order_number,
        v_external_order_id,
        v_customer_id,
        p_order_payload ->> 'financial_status',
        p_order_payload ->> 'fulfillment_status',
        ( (p_order_payload ->> 'total_price')::numeric * 100 )::integer,
        p_platform,
        (p_order_payload ->> 'created_at')::timestamptz,
        p_order_payload ->> 'note'
    ) returning id into v_order_id;
    
    -- Loop through line items, insert them, and update inventory
    for v_line_item in select * from jsonb_array_elements(p_order_payload -> 'line_items')
    loop
        -- Find the corresponding product variant in our DB
        select id into v_variant_id from public.product_variants
        where sku = (v_line_item ->> 'sku') and company_id = p_company_id;

        -- Even if the variant isn't found, we still log the sale.
        -- This prevents data loss if a product was deleted from inventory but sold.
        insert into public.order_line_items (order_id, company_id, variant_id, product_name, sku, quantity, price, external_line_item_id)
        values (
            v_order_id,
            p_company_id,
            v_variant_id,
            v_line_item ->> 'name',
            v_line_item ->> 'sku',
            (v_line_item ->> 'quantity')::integer,
            ( (v_line_item ->> 'price')::numeric * 100 )::integer,
            v_line_item ->> 'id'
        );

        -- If we found a matching variant, update its inventory
        if v_variant_id is not null then
            perform public.update_inventory_and_log(
                p_company_id,
                v_variant_id,
                -1 * (v_line_item ->> 'quantity')::integer, -- Decrement stock
                'sale',
                v_order_id,
                'Sale from ' || p_platform || ' order ' || v_order_number
            );
        end if;
    end loop;

    return v_order_id;
end;
$$;


-- 6. Triggers
-- Automatically call the handle_new_user function when a new user is created in the auth.users table.
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


-- 7. Row Level Security (RLS) Policies
-- These policies are the primary security mechanism, ensuring users can only access data for their own company.

-- Enable RLS for all relevant tables
alter table public.companies enable row level security;
alter table public.users enable row level security;
alter table public.company_settings enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.suppliers enable row level security;
alter table public.customers enable row level security;
alter table public.orders enable row level security;
alter table public.order_line_items enable row level security;
alter table public.inventory_ledger enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.integrations enable row level security;
alter table public.channel_fees enable row level security;
alter table public.export_jobs enable row level security;
alter table public.audit_log enable row level security;
alter table public.webhook_events enable row level security;


-- Create policies for each table
drop policy if exists "Allow full access based on company_id" on public.companies;
create policy "Allow full access based on company_id" on public.companies for all using (id = get_current_company_id()) with check (id = get_current_company_id());

drop policy if exists "Allow full access based on company_id" on public.users;
create policy "Allow full access based on company_id" on public.users for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

drop policy if exists "Allow full access based on company_id" on public.company_settings;
create policy "Allow full access based on company_id" on public.company_settings for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

drop policy if exists "Allow full access based on company_id" on public.products;
create policy "Allow full access based on company_id" on public.products for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

drop policy if exists "Allow full access based on company_id" on public.product_variants;
create policy "Allow full access based on company_id" on public.product_variants for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

drop policy if exists "Allow full access based on company_id" on public.suppliers;
create policy "Allow full access based on company_id" on public.suppliers for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

drop policy if exists "Allow full access based on company_id" on public.customers;
create policy "Allow full access based on company_id" on public.customers for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

drop policy if exists "Allow full access based on company_id" on public.orders;
create policy "Allow full access based on company_id" on public.orders for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

drop policy if exists "Allow full access based on company_id" on public.order_line_items;
create policy "Allow full access based on company_id" on public.order_line_items for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

drop policy if exists "Allow full access based on company_id" on public.inventory_ledger;
create policy "Allow full access based on company_id" on public.inventory_ledger for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

drop policy if exists "Allow full access to own conversations" on public.conversations;
create policy "Allow full access to own conversations" on public.conversations for all using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "Allow full access based on company_id" on public.messages;
create policy "Allow full access based on company_id" on public.messages for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

drop policy if exists "Allow full access based on company_id" on public.integrations;
create policy "Allow full access based on company_id" on public.integrations for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

drop policy if exists "Allow full access based on company_id" on public.channel_fees;
create policy "Allow full access based on company_id" on public.channel_fees for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

drop policy if exists "Allow access to own jobs" on public.export_jobs;
create policy "Allow access to own jobs" on public.export_jobs for all using (requested_by_user_id = auth.uid()) with check (requested_by_user_id = auth.uid());

drop policy if exists "Allow full access based on company_id" on public.audit_log;
create policy "Allow full access based on company_id" on public.audit_log for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

-- This policy ensures users can only access webhook events related to their own company's integrations.
drop policy if exists "Allow access based on company" on public.webhook_events;
create policy "Allow access based on company" on public.webhook_events for all
using ((select company_id from public.integrations where id = webhook_events.integration_id) = get_current_company_id());

-- 8. Granting Permissions
-- Grant usage permissions on the public schema to the authenticated role.
-- This allows authenticated users to interact with the tables and functions.
grant usage on schema public to authenticated;
grant all privileges on all tables in schema public to authenticated;
grant all privileges on all functions in schema public to authenticated;
grant all privileges on all sequences in schema public to authenticated;

-- Grant permissions to the service_role for full access.
grant usage on schema public to service_role;
grant all privileges on all tables in schema public to service_role;
grant all privileges on all functions in schema public to service_role;
grant all privileges on all sequences in schema public to service_role;

-- 9. Performance Views
-- Create a materialized view for dashboard metrics. This pre-calculates expensive queries.
drop materialized view if exists public.company_dashboard_metrics;
create materialized view public.company_dashboard_metrics as
select
  p.company_id,
  (now() at time zone 'utc')::date as calculation_date,
  coalesce(sum(v.price * v.inventory_quantity), 0)::bigint as total_inventory_value,
  count(distinct p.id) as total_products,
  count(v.id) as total_variants,
  sum(case when v.inventory_quantity <= 0 then 1 else 0 end)::integer as out_of_stock_variants
from public.products p
join public.product_variants v on p.id = v.product_id
group by p.company_id;

-- Add an index for faster lookups
create unique index if not exists idx_company_dashboard_metrics_p_key on public.company_dashboard_metrics(company_id, calculation_date);
