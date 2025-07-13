-- InvoChat Database Schema
-- Version: 1.2
-- Description: This script sets up the initial database schema, including tables,
-- functions, and row-level security policies for a multi-tenant inventory management system.

-- ----------------------------------------
-- EXTENSIONS
-- ----------------------------------------
-- Enable UUID generation
create extension if not exists "uuid-ossp" with schema public;
-- Enable pgcrypto for hashing
create extension if not exists pgcrypto with schema public;

-- ----------------------------------------
-- HELPER FUNCTIONS
-- ----------------------------------------

-- Get the company_id from the current user's custom claims
create or replace function public.get_current_company_id()
returns uuid
language sql stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid;
$$;
-- Get the role from the current user's custom claims
create or replace function public.get_current_user_role()
returns text
language sql stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'role', '');
$$;


-- ----------------------------------------
-- TABLES
-- ----------------------------------------

-- Stores company information
create table if not exists public.companies (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  created_at timestamptz not null default now()
);

-- Stores user information and links them to a company
create table if not exists public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  email text,
  role text default 'member'::text,
  deleted_at timestamptz,
  created_at timestamptz default now()
);

-- Stores company-specific settings
create table if not exists public.company_settings (
  company_id uuid primary key references public.companies(id) on delete cascade,
  dead_stock_days integer not null default 90,
  overstock_multiplier integer not null default 3,
  high_value_threshold integer not null default 1000,
  fast_moving_days integer not null default 30,
  predictive_stock_days integer not null default 7,
  promo_sales_lift_multiplier real not null default 2.5,
  currency text default 'USD',
  timezone text default 'UTC',
  tax_rate numeric default 0,
  custom_rules jsonb,
  subscription_status text default 'trial',
  subscription_plan text default 'starter',
  subscription_expires_at timestamptz,
  stripe_customer_id text,
  stripe_subscription_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);
-- Alter numeric columns to integer as required by the application
alter table public.company_settings alter column overstock_multiplier type integer;
alter table public.company_settings alter column high_value_threshold type integer;


-- Stores product master data
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
  updated_at timestamptz
);
-- Add unique constraint for external product IDs per company
alter table public.products add constraint unique_external_product_id_per_company unique (company_id, external_product_id);


-- Stores product variants (SKUs)
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
  price integer, -- in cents
  compare_at_price integer, -- in cents
  cost integer, -- in cents
  inventory_quantity integer default 0,
  external_variant_id text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
alter table public.product_variants add column if not exists weight numeric;
alter table public.product_variants add column if not exists weight_unit text;

-- Add unique constraint for external variant IDs per company
alter table public.product_variants add constraint unique_external_variant_id_per_company unique (company_id, external_variant_id);
-- Add unique constraint for SKUs per company
alter table public.product_variants add constraint unique_sku_per_company unique (company_id, sku);


-- Stores supplier information
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

-- Stores customer information
create table if not exists public.customers (
  id uuid primary key default uuid_generate_v4(),
  company_id uuid not null references public.companies(id) on delete cascade,
  customer_name text not null,
  email text,
  total_orders integer default 0,
  total_spent numeric default 0,
  first_order_date date,
  deleted_at timestamptz,
  created_at timestamptz default now()
);

-- Stores customer addresses
create table if not exists public.customer_addresses (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id) on delete cascade,
  address_type text not null default 'shipping',
  first_name text,
  last_name text,
  company text,
  address1 text,
  address2 text,
  city text,
  province_code text,
  country_code text,
  zip text,
  phone text,
  is_default boolean default false
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
  updated_at timestamptz default now()
);
alter table public.orders add constraint unique_external_order_id_per_company unique (company_id, external_order_id);

-- Stores line items for sales orders
create table if not exists public.order_line_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  company_id uuid not null,
  product_id uuid references public.products(id),
  variant_id uuid references public.product_variants(id),
  product_name text not null,
  variant_title text,
  sku text,
  quantity integer not null,
  price integer not null,
  total_discount integer default 0,
  tax_amount integer default 0,
  cost_at_time integer, -- in cents
  fulfillment_status text default 'unfulfilled',
  requires_shipping boolean default true,
  external_line_item_id text
);

-- Stores refunds
create table if not exists public.refunds (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null,
  order_id uuid not null references public.orders(id),
  refund_number text not null,
  status text not null default 'pending',
  reason text,
  note text,
  total_amount numeric not null,
  created_by_user_id uuid references public.users(id),
  external_refund_id text,
  created_at timestamptz default now()
);

-- Stores line items for refunds
create table if not exists public.refund_line_items (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null,
  refund_id uuid not null references public.refunds(id) on delete cascade,
  order_line_item_id uuid not null references public.order_line_items(id),
  quantity integer not null,
  amount numeric not null,
  restock boolean default true
);

-- Stores promotions and discount codes
create table if not exists public.discounts (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null,
  code text not null,
  type text not null, -- e.g., 'percentage', 'fixed'
  value numeric not null,
  minimum_purchase numeric,
  usage_limit integer,
  usage_count integer default 0,
  applies_to text default 'all', -- 'all', 'product', 'category'
  starts_at timestamptz,
  ends_at timestamptz,
  is_active boolean default true,
  created_at timestamptz default now()
);

-- Stores integrations with other platforms
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

-- Audit log for important actions
create table if not exists public.audit_log (
  id bigserial primary key,
  company_id uuid,
  user_id uuid,
  action text not null,
  details jsonb,
  created_at timestamptz default now()
);

-- A ledger for all inventory movements
create table if not exists public.inventory_ledger (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id),
    variant_id uuid not null references public.product_variants(id),
    change_type text not null,
    quantity_change integer not null,
    new_quantity integer not null,
    related_id uuid,
    notes text,
    created_at timestamptz not null default now()
);

-- Stores chat conversation history
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

-- Stores data export jobs
create table if not exists public.export_jobs (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    requested_by_user_id uuid not null references auth.users(id),
    status text not null default 'pending',
    download_url text,
    expires_at timestamptz,
    created_at timestamptz not null default now()
);

-- Stores sales channel fees for net margin calculations
create table if not exists public.channel_fees (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    channel_name text not null,
    percentage_fee numeric not null,
    fixed_fee numeric not null,
    created_at timestamptz default now(),
    updated_at timestamptz,
    unique (company_id, channel_name)
);

-- Table for webhook replay protection
drop table if exists public.webhook_events;
create table if not exists public.webhook_events (
  id uuid primary key default gen_random_uuid(),
  integration_id uuid not null references public.integrations(id) on delete cascade,
  webhook_id text not null,
  created_at timestamptz not null default now(),
  unique(integration_id, webhook_id)
);

-- ----------------------------------------
-- DATABASE FUNCTIONS & TRIGGERS
-- ----------------------------------------

-- Function to handle new user setup
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  new_company_id uuid;
begin
  -- Create a new company for the user
  insert into public.companies (name)
  values (new.raw_app_meta_data->>'company_name')
  returning id into new_company_id;

  -- Create an entry in the public.users table
  insert into public.users (id, company_id, email, role)
  values (new.id, new_company_id, new.email, 'Owner');
  
  -- Update the user's app_metadata with the new company_id and role
  new.raw_app_meta_data := new.raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'role', 'Owner');

  return new;
end;
$$;

-- Trigger to execute the function on new user creation
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row
  when (new.raw_app_meta_data->>'company_name' is not null)
  execute function public.handle_new_user();


-- Drops the existing function if the return type is different
drop function if exists public.record_order_from_platform(uuid, text, jsonb);

-- Function to process and record an order from a platform like Shopify or WooCommerce
create or replace function public.record_order_from_platform(p_company_id uuid, p_platform text, p_order_payload jsonb)
returns uuid
language plpgsql
security definer
as $$
declare
    v_customer_id uuid;
    v_order_id uuid;
    v_variant_id uuid;
    line_item jsonb;
    v_sku text;
    v_email text;
begin
    -- Extract customer email
    v_email := p_order_payload->'customer'->>'email';
    
    -- Find or create customer
    if v_email is not null then
        select id into v_customer_id from public.customers
        where company_id = p_company_id and email = v_email;

        if v_customer_id is null then
            insert into public.customers (company_id, customer_name, email, total_orders, total_spent)
            values (
                p_company_id,
                coalesce(
                    p_order_payload->'customer'->>'first_name' || ' ' || p_order_payload->'customer'->>'last_name',
                    'Guest'
                ),
                v_email,
                1,
                (p_order_payload->>'total_price')::numeric
            ) returning id into v_customer_id;
        else
            update public.customers
            set total_orders = total_orders + 1,
                total_spent = total_spent + (p_order_payload->>'total_price')::numeric
            where id = v_customer_id;
        end if;
    end if;

    -- Insert order
    insert into public.orders (
        company_id,
        order_number,
        external_order_id,
        customer_id,
        financial_status,
        fulfillment_status,
        total_amount,
        subtotal,
        total_tax,
        total_discounts,
        created_at,
        source_platform
    )
    values (
        p_company_id,
        coalesce(p_order_payload->>'name', p_order_payload->>'number', 'N/A'),
        p_order_payload->>'id',
        v_customer_id,
        p_order_payload->>'financial_status',
        p_order_payload->>'fulfillment_status',
        (p_order_payload->>'total_price')::numeric * 100,
        (p_order_payload->>'subtotal_price')::numeric * 100,
        (p_order_payload->>'total_tax')::numeric * 100,
        (p_order_payload->>'total_discounts')::numeric * 100,
        (p_order_payload->>'created_at')::timestamptz,
        p_platform
    ) returning id into v_order_id;
    
    -- Insert line items
    for line_item in select * from jsonb_array_elements(p_order_payload->'line_items')
    loop
        v_sku := coalesce(line_item->>'sku', 'SKU-UNKNOWN-' || (line_item->>'id'));
        
        -- Find the corresponding product variant
        select id into v_variant_id from public.product_variants
        where company_id = p_company_id and sku = v_sku;

        insert into public.order_line_items (
            order_id,
            company_id,
            variant_id,
            product_name,
            variant_title,
            sku,
            quantity,
            price,
            external_line_item_id
        ) values (
            v_order_id,
            p_company_id,
            v_variant_id,
            line_item->>'name',
            line_item->>'variant_title',
            v_sku,
            (line_item->>'quantity')::integer,
            (line_item->>'price')::numeric * 100,
            line_item->>'id'
        );
    end loop;

    return v_order_id;
end;
$$;


-- ----------------------------------------
-- ROW-LEVEL SECURITY
-- ----------------------------------------
alter table public.companies enable row level security;
alter table public.users enable row level security;
alter table public.company_settings enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.suppliers enable row level security;
alter table public.customers enable row level security;
alter table public.customer_addresses enable row level security;
alter table public.orders enable row level security;
alter table public.order_line_items enable row level security;
alter table public.refunds enable row level security;
alter table public.refund_line_items enable row level security;
alter table public.discounts enable row level security;
alter table public.integrations enable row level security;
alter table public.audit_log enable row level security;
alter table public.inventory_ledger enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.export_jobs enable row level security;
alter table public.channel_fees enable row level security;
alter table public.webhook_events enable row level security;

-- Policies for tables with a direct company_id
create or replace policy "Allow full access based on company_id" on public.companies for all using (id = get_current_company_id()) with check (id = get_current_company_id());
create or replace policy "Allow access to own user record" on public.users for all using (id = auth.uid());
create or replace policy "Allow access to own company members" on public.users for select using (company_id = get_current_company_id());
create or replace policy "Allow full access based on company_id" on public.company_settings for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());
create or replace policy "Allow full access based on company_id" on public.products for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());
create or replace policy "Allow full access based on company_id" on public.product_variants for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());
create or replace policy "Allow full access based on company_id" on public.suppliers for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());
create or replace policy "Allow full access based on company_id" on public.customers for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());
create or replace policy "Allow full access based on company_id" on public.orders for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());
create or replace policy "Allow full access based on company_id" on public.order_line_items for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());
create or replace policy "Allow full access based on company_id" on public.refunds for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());
create or replace policy "Allow full access based on company_id" on public.refund_line_items for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());
create or replace policy "Allow full access based on company_id" on public.discounts for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());
create or replace policy "Allow full access based on company_id" on public.integrations for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());
create or replace policy "Allow full access based on company_id" on public.audit_log for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());
create or replace policy "Allow full access based on company_id" on public.inventory_ledger for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());
create or replace policy "Allow full access based on company_id" on public.messages for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());
create or replace policy "Allow full access based on company_id" on public.channel_fees for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

-- Policies for tables with indirect company_id linkage
drop policy if exists "Allow access to own company addresses" on public.customer_addresses;
create policy "Allow access to own company addresses" on public.customer_addresses for all
  using ((select company_id from public.customers where id = customer_addresses.customer_id) = get_current_company_id())
  with check ((select company_id from public.customers where id = customer_addresses.customer_id) = get_current_company_id());

create or replace policy "Allow user to manage their own conversations" on public.conversations for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create or replace policy "Allow user to manage their own company export jobs" on public.export_jobs for all
  using (company_id = get_current_company_id())
  with check (company_id = get_current_company_id());

drop policy if exists "Allow access based on integration's company" on public.webhook_events;
create policy "Allow access based on integration's company" on public.webhook_events for all
  using ((select company_id from public.integrations where id = webhook_events.integration_id) = get_current_company_id());


-- ----------------------------------------
-- VIEWS AND MATERIALIZED VIEWS
-- ----------------------------------------

-- Creates a denormalized view of variants with key product details for easier querying.
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

-- Materialized view for dashboard metrics to improve performance.
-- This should be refreshed periodically by a cron job.
create materialized view if not exists public.company_dashboard_metrics as
select
  c.id as company_id,
  -- Key metrics
  coalesce(sum(o.total_amount), 0) as total_sales_value,
  coalesce(sum(o.total_amount - oli.total_cost_at_time), 0) as total_profit,
  count(distinct o.id) as total_orders,
  count(distinct o.customer_id) as total_customers,
  coalesce(avg(o.total_amount), 0) as average_order_value,
  -- Inventory metrics
  count(distinct pv.id) as total_skus,
  sum(pv.inventory_quantity * pv.cost) as total_inventory_value
from
  public.companies c
left join
  public.orders o on c.id = o.company_id
left join
  (select order_id, sum(cost_at_time * quantity) as total_cost_at_time from public.order_line_items group by order_id) oli on o.id = oli.order_id
left join
  public.product_variants pv on c.id = pv.company_id
group by
  c.id;

-- Function to refresh all materialized views
create or replace function refresh_all_materialized_views()
returns void language plpgsql as $$
begin
  refresh materialized view concurrently public.company_dashboard_metrics;
end;
$$;


-- Finalizing permissions for Supabase access
grant usage on schema public to postgres, anon, authenticated, service_role;
grant all privileges on all tables in schema public to postgres, anon, authenticated, service_role;
grant all privileges on all functions in schema public to postgres, anon, authenticated, service_role;
grant all privileges on all sequences in schema public to postgres, anon, authenticated, service_role;

alter default privileges in schema public grant all on tables to postgres, anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to postgres, anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to postgres, anon, authenticated, service_role;


-- Initial seeding for demo/testing if needed (can be removed for production)
-- insert into public.companies(name) values ('Test Company');
-- insert into public.users(id, company_id, email) select id, (select id from public.companies limit 1), email from auth.users;

