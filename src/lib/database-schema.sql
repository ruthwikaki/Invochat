
-- Enable UUID extension
create extension if not exists "uuid-ossp" with schema extensions;

-- ## Private Schemas and Helper Functions ##

-- Create a helper function to get the current user's company_id
create or replace function public.get_current_company_id()
returns uuid
language sql
security definer
set search_path = public
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid;
$$;


-- Create a helper function to get the current user's role
create or replace function public.get_current_user_role()
returns text
language sql
security definer
set search_path = public
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'role', '');
$$;

-- ## Table Definitions ##

-- Companies Table: Stores company information
drop table if exists public.companies cascade;
create table public.companies (
    id uuid not null primary key default extensions.uuid_generate_v4(),
    name text not null,
    created_at timestamptz not null default now()
);
-- RLS for companies: only service_role can bypass.
-- User-specific access will be handled by other tables.
alter table public.companies enable row level security;


-- Users Table: A private table mapping auth.users to companies and roles
drop table if exists public.users cascade;
create table public.users (
  id uuid not null references auth.users(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  role text check (role in ('Owner', 'Admin', 'Member')) not null default 'Member',
  email text,
  deleted_at timestamptz,
  created_at timestamptz default now(),
  primary key (id, company_id)
);
alter table public.users enable row level security;
drop policy if exists "Allow full access based on company_id" on public.users;
create policy "Allow full access based on company_id" on public.users for all using (company_id = get_current_company_id());


-- Company Settings Table: Stores settings for each company
drop table if exists public.company_settings cascade;
create table public.company_settings (
    company_id uuid not null primary key references public.companies(id) on delete cascade,
    dead_stock_days int not null default 90,
    fast_moving_days int not null default 30,
    predictive_stock_days int not null default 7,
    overstock_multiplier int not null default 3,
    high_value_threshold int not null default 100000, -- in cents
    promo_sales_lift_multiplier real not null default 2.5,
    currency text default 'USD',
    timezone text default 'UTC',
    tax_rate numeric(5, 4) default 0.0,
    subscription_status text default 'trial',
    stripe_customer_id text,
    stripe_subscription_id text,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);
alter table public.company_settings enable row level security;
drop policy if exists "Allow full access based on company_id" on public.company_settings;
create policy "Allow full access based on company_id" on public.company_settings for all using (company_id = get_current_company_id());


-- Products Table: Core product catalog
drop table if exists public.products cascade;
create table public.products (
  id uuid not null primary key default extensions.uuid_generate_v4(),
  company_id uuid not null references public.companies(id) on delete cascade,
  title text not null,
  description text,
  handle text,
  product_type text,
  tags text[],
  status text default 'active',
  image_url text,
  external_product_id text,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  unique (company_id, external_product_id)
);
alter table public.products enable row level security;
drop policy if exists "Allow read access to all users in company" on public.products;
create policy "Allow read access to all users in company" on public.products for select using (company_id = get_current_company_id() and deleted_at is null);
drop policy if exists "Allow write access to admins/owners" on public.products;
create policy "Allow write access to admins/owners" on public.products for all using (company_id = get_current_company_id() and deleted_at is null) with check (get_current_user_role() in ('Admin', 'Owner'));


-- Product Variants Table: Specific versions of a product (e.g., size, color)
drop table if exists public.product_variants cascade;
create table public.product_variants (
  id uuid not null primary key default extensions.uuid_generate_v4(),
  product_id uuid not null references public.products(id) on delete cascade,
  company_id uuid not null,
  sku text,
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
  external_variant_id text,
  created_at timestamptz default now(),
  updated_at timestamptz,
  unique (company_id, sku),
  unique (company_id, external_variant_id)
);
alter table public.product_variants enable row level security;
drop policy if exists "Allow read access to all users in company" on public.product_variants;
create policy "Allow read access to all users in company" on public.product_variants for select using (company_id = get_current_company_id());
drop policy if exists "Allow write access to admins/owners" on public.product_variants;
create policy "Allow write access to admins/owners" on public.product_variants for all using (company_id = get_current_company_id()) with check (get_current_user_role() in ('Admin', 'Owner'));


-- Inventory Ledger Table: Transactional log of all inventory movements
drop table if exists public.inventory_ledger cascade;
create table public.inventory_ledger (
  id uuid primary key default extensions.uuid_generate_v4(),
  company_id uuid not null,
  variant_id uuid not null references public.product_variants(id) on delete restrict,
  change_type text not null, -- e.g., 'sale', 'restock', 'return', 'adjustment'
  quantity_change int not null,
  new_quantity int not null,
  related_id uuid, -- For linking to orders, POs, etc.
  notes text,
  created_at timestamptz not null default now()
);
alter table public.inventory_ledger enable row level security;
drop policy if exists "Allow full access based on company_id" on public.inventory_ledger;
create policy "Allow full access based on company_id" on public.inventory_ledger for all using (company_id = get_current_company_id());


-- Customers Table
drop table if exists public.customers cascade;
create table public.customers (
    id uuid not null primary key default extensions.uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    customer_name text,
    email text,
    total_orders int default 0,
    total_spent int default 0, -- in cents
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz default now(),
    unique(company_id, email)
);
alter table public.customers enable row level security;
drop policy if exists "Allow full access based on company_id" on public.customers;
create policy "Allow full access based on company_id" on public.customers for all using (company_id = get_current_company_id());


-- Orders Table
drop table if exists public.orders cascade;
create table public.orders (
    id uuid not null primary key default extensions.uuid_generate_v4(),
    company_id uuid not null,
    order_number text not null,
    external_order_id text,
    customer_id uuid references public.customers(id) on delete set null,
    financial_status text,
    fulfillment_status text,
    currency text,
    subtotal int not null default 0, -- in cents
    total_tax int default 0, -- in cents
    total_shipping int default 0, -- in cents
    total_discounts int default 0, -- in cents
    total_amount int not null, -- in cents
    source_platform text,
    created_at timestamptz default now(),
    updated_at timestamptz
);
alter table public.orders enable row level security;
drop policy if exists "Allow full access based on company_id" on public.orders;
create policy "Allow full access based on company_id" on public.orders for all using (company_id = get_current_company_id());


-- Order Line Items Table
drop table if exists public.order_line_items cascade;
create table public.order_line_items (
    id uuid not null primary key default extensions.uuid_generate_v4(),
    order_id uuid not null references public.orders(id) on delete cascade,
    variant_id uuid references public.product_variants(id) on delete set null,
    company_id uuid not null,
    product_name text,
    variant_title text,
    sku text,
    quantity int not null,
    price int not null, -- in cents
    total_discount int, -- in cents
    tax_amount int, -- in cents
    cost_at_time int, -- in cents
    external_line_item_id text
);
alter table public.order_line_items enable row level security;
drop policy if exists "Allow full access based on company_id" on public.order_line_items;
create policy "Allow full access based on company_id" on public.order_line_items for all using (company_id = get_current_company_id());


-- Suppliers Table
drop table if exists public.suppliers cascade;
create table public.suppliers (
    id uuid not null primary key default extensions.uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    name text not null,
    email text,
    phone text,
    default_lead_time_days int,
    notes text,
    deleted_at timestamptz,
    created_at timestamptz not null default now()
);
alter table public.suppliers enable row level security;
drop policy if exists "Allow full access based on company_id" on public.suppliers;
create policy "Allow full access based on company_id" on public.suppliers for all using (company_id = get_current_company_id());


-- Integrations Table
drop table if exists public.integrations cascade;
create table public.integrations (
    id uuid not null primary key default extensions.uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    platform text not null, -- 'shopify', 'woocommerce', etc.
    shop_domain text,
    shop_name text,
    is_active boolean default false,
    last_sync_at timestamptz,
    sync_status text,
    created_at timestamptz not null default now(),
    updated_at timestamptz,
    unique(company_id, platform)
);
alter table public.integrations enable row level security;
drop policy if exists "Allow full access based on company_id" on public.integrations;
create policy "Allow full access based on company_id" on public.integrations for all using (company_id = get_current_company_id());


-- Conversations Table
drop table if exists public.conversations cascade;
create table public.conversations (
    id uuid not null primary key default extensions.uuid_generate_v4(),
    user_id uuid not null references auth.users(id) on delete cascade,
    company_id uuid not null,
    title text not null,
    is_starred boolean default false,
    created_at timestamptz default now(),
    last_accessed_at timestamptz default now()
);
alter table public.conversations enable row level security;
drop policy if exists "Allow access to own conversations" on public.conversations;
create policy "Allow access to own conversations" on public.conversations for all using (user_id = auth.uid() and company_id = get_current_company_id());


-- Messages Table
drop table if exists public.messages cascade;
create table public.messages (
    id uuid not null primary key default extensions.uuid_generate_v4(),
    conversation_id uuid not null references public.conversations(id) on delete cascade,
    company_id uuid not null,
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
drop policy if exists "Allow access based on company_id" on public.messages;
create policy "Allow access based on company_id" on public.messages for all using (company_id = get_current_company_id());


-- Webhook Events Table
drop table if exists public.webhook_events cascade;
create table public.webhook_events (
    id uuid primary key default extensions.uuid_generate_v4(),
    integration_id uuid not null references public.integrations(id) on delete cascade,
    webhook_id text not null,
    processed_at timestamptz default now(),
    created_at timestamptz default now(),
    unique(integration_id, webhook_id)
);
alter table public.webhook_events enable row level security;
drop policy if exists "Allow full access to service role" on public.webhook_events;
create policy "Allow full access to service role" on public.webhook_events for all using (true) with check (true);


-- User Feedback Table
drop table if exists public.user_feedback cascade;
create table public.user_feedback (
    id uuid primary key default extensions.uuid_generate_v4(),
    company_id uuid not null,
    user_id uuid not null,
    subject_id text not null,
    subject_type text not null,
    feedback text not null, -- 'helpful' or 'unhelpful'
    created_at timestamptz default now()
);
alter table public.user_feedback enable row level security;
drop policy if exists "Allow full access based on company_id" on public.user_feedback;
create policy "Allow full access based on company_id" on public.user_feedback for all using (company_id = get_current_company_id());


-- Audit Log Table
drop table if exists public.audit_log cascade;
create table public.audit_log (
  id bigserial primary key,
  company_id uuid references public.companies(id) on delete cascade,
  user_id uuid,
  action text not null,
  details jsonb,
  created_at timestamptz default now()
);
alter table public.audit_log enable row level security;
drop policy if exists "Allow admin access based on company_id" on public.audit_log;
create policy "Allow admin access based on company_id" on public.audit_log for all using (company_id = get_current_company_id()) with check (get_current_user_role() in ('Admin', 'Owner'));

-- Channel Fees Table
drop table if exists public.channel_fees cascade;
create table public.channel_fees (
    id uuid not null primary key default extensions.uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    channel_name text not null,
    percentage_fee numeric(5, 4) not null,
    fixed_fee numeric(10, 2) not null,
    created_at timestamptz default now(),
    updated_at timestamptz,
    unique(company_id, channel_name)
);
alter table public.channel_fees enable row level security;
drop policy if exists "Allow full access based on company_id" on public.channel_fees;
create policy "Allow full access based on company_id" on public.channel_fees for all using (company_id = get_current_company_id());


-- Export Jobs Table
drop table if exists public.export_jobs cascade;
create table public.export_jobs (
    id uuid not null primary key default extensions.uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    requested_by_user_id uuid not null,
    status text not null default 'pending',
    download_url text,
    expires_at timestamptz,
    created_at timestamptz not null default now()
);
alter table public.export_jobs enable row level security;
drop policy if exists "Allow access based on user_id" on public.export_jobs;
create policy "Allow access based on user_id" on public.export_jobs for all using (requested_by_user_id = auth.uid());


-- ## Triggers and Functions ##

-- Function to create a company and assign the creating user as the owner.
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
  -- Extract details from the new user's metadata
  user_email := new.email;
  company_name := new.raw_app_meta_data ->> 'company_name';

  -- Create a new company
  insert into public.companies (name)
  values (coalesce(company_name, user_email || '''s Company'))
  returning id into company_id;

  -- Create a corresponding user record in the public.users table
  insert into public.users (id, company_id, role, email)
  values (new.id, company_id, 'Owner', user_email);

  -- Update the user's app_metadata with the new company_id and role
  update auth.users
  set raw_app_meta_data = new.raw_app_meta_data || jsonb_build_object('company_id', company_id, 'role', 'Owner')
  where id = new.id;

  return new;
end;
$$;

-- Trigger to call handle_new_user on new user creation
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


-- Trigger to automatically update the quantity in product_variants when inventory_ledger changes
create or replace function public.update_variant_quantity_from_ledger()
returns trigger
language plpgsql
as $$
begin
  update public.product_variants
  set inventory_quantity = new.new_quantity,
      updated_at = now()
  where id = new.variant_id;
  return new;
end;
$$;

drop trigger if exists on_inventory_ledger_insert on public.inventory_ledger;
create trigger on_inventory_ledger_insert
  after insert on public.inventory_ledger
  for each row
  execute procedure public.update_variant_quantity_from_ledger();

-- Drop old function signature to avoid conflicts
drop function if exists public.record_order_from_platform(uuid, text, jsonb);

-- Function to process and record an order from a platform's webhook payload
create or replace function public.record_order_from_platform(
    p_company_id uuid,
    p_platform text,
    p_order_payload jsonb
)
returns uuid
language plpgsql
security definer
as $$
declare
    v_customer_id uuid;
    v_order_id uuid;
    v_variant_id uuid;
    v_customer_name text;
    v_customer_email text;
    line_item jsonb;
    v_sku text;
    v_quantity int;
    v_current_stock int;
begin
    -- 1. Find or create customer
    if p_platform = 'shopify' then
        v_customer_email := p_order_payload -> 'customer' ->> 'email';
        v_customer_name := (p_order_payload -> 'customer' ->> 'first_name') || ' ' || (p_order_payload -> 'customer' ->> 'last_name');
    elsif p_platform = 'woocommerce' then
        v_customer_email := p_order_payload -> 'billing' ->> 'email';
        v_customer_name := (p_order_payload -> 'billing' ->> 'first_name') || ' ' || (p_order_payload -> 'billing' ->> 'last_name');
    else
        v_customer_email := 'anonymous@' || p_platform;
        v_customer_name := 'Platform Customer';
    end if;
    
    if v_customer_email is not null then
        select id into v_customer_id from public.customers where company_id = p_company_id and email = v_customer_email;
        if v_customer_id is null then
            insert into public.customers (company_id, customer_name, email)
            values (p_company_id, v_customer_name, v_customer_email)
            returning id into v_customer_id;
        end if;
    end if;

    -- 2. Create the order
    insert into public.orders (company_id, customer_id, order_number, external_order_id, financial_status, fulfillment_status, total_amount, source_platform, created_at)
    values (
        p_company_id,
        v_customer_id,
        p_order_payload ->> 'order_number',
        p_order_payload ->> 'id',
        p_order_payload ->> 'financial_status',
        p_order_payload ->> 'fulfillment_status',
        (p_order_payload ->> 'total_price')::numeric * 100,
        p_platform,
        (p_order_payload ->> 'created_at')::timestamptz
    )
    returning id into v_order_id;
    
    -- 3. Process line items and update inventory
    for line_item in select * from jsonb_array_elements(p_order_payload -> 'line_items')
    loop
        v_sku := line_item ->> 'sku';
        v_quantity := (line_item ->> 'quantity')::int;
        
        select id into v_variant_id from public.product_variants where company_id = p_company_id and sku = v_sku;

        if v_variant_id is not null then
            -- Insert line item
            insert into public.order_line_items (order_id, variant_id, company_id, sku, product_name, quantity, price)
            values (
                v_order_id,
                v_variant_id,
                p_company_id,
                v_sku,
                line_item ->> 'name',
                v_quantity,
                (line_item ->> 'price')::numeric * 100
            );

            -- Update inventory
            select inventory_quantity into v_current_stock from public.product_variants where id = v_variant_id;
            
            insert into public.inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id)
            values (p_company_id, v_variant_id, 'sale', -v_quantity, v_current_stock - v_quantity, v_order_id);
        else
            -- Log a warning or handle missing SKU
        end if;
    end loop;
    
    return v_order_id;
end;
$$;


-- ## Indexes for Performance ##
create index if not exists idx_products_company_id on public.products(company_id);
create index if not exists idx_product_variants_company_sku on public.product_variants(company_id, sku);
create index if not exists idx_orders_company_id_created_at on public.orders(company_id, created_at desc);
create index if not exists idx_inventory_ledger_variant_id on public.inventory_ledger(variant_id);


-- Performance View for Dashboard
create or replace view public.company_dashboard_metrics as
select
    p_company_id as company_id,
    sum(total_amount) as total_sales,
    avg(total_amount) as avg_sale_value
from public.orders
where company_id = p_company_id and created_at >= now() - interval '30 days'
group by p_company_id;

-- Enable RLS on all tables that need it
-- Note: Views do not support RLS directly. Security is enforced on the underlying tables.
alter table public.companies disable row level security;
alter table auth.users disable row level security;

-- Final RLS setup
alter table public.users enable row level security;
alter table public.company_settings enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.inventory_ledger enable row level security;
alter table public.customers enable row level security;
alter table public.orders enable row level security;
alter table public.order_line_items enable row level security;
alter table public.suppliers enable row level security;
alter table public.integrations enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.webhook_events enable row level security;
alter table public.user_feedback enable row level security;
alter table public.audit_log enable row level security;
alter table public.channel_fees enable row level security;
alter table public.export_jobs enable row level security;


-- This is a sample of the type of materialized view you might create for performance.
-- In a real production environment, you would have a cron job or a trigger to refresh this.
-- create materialized view if not exists daily_sales_summary as
-- select
--   date_trunc('day', created_at) as sale_day,
--   company_id,
--   sum(total_amount) as total_revenue
-- from public.orders
-- group by 1, 2;
--
-- create index if not exists idx_daily_sales_summary_company_day on daily_sales_summary(company_id, sale_day);

