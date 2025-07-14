-- InvoChat Database Schema
-- Version: 1.3
-- Description: This script sets up the entire database, including tables,
--              functions, and row-level security policies. It is designed
--              to be idempotent and can be run safely on new or existing databases.

-- 1. Extensions
-- -----------------------------------------------------------------------------
create extension if not exists "uuid-ossp" with schema extensions;
create extension if not exists pgroonga with schema extensions;


-- 2. Helper Functions
-- These functions are used by policies and business logic.
-- -----------------------------------------------------------------------------

-- Get the company_id for the currently authenticated user.
drop function if exists public.get_current_company_id();
create or replace function public.get_current_company_id()
returns uuid
language sql
security definer
set search_path = public
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid;
$$;


-- Get the role for the currently authenticated user
drop function if exists public.get_current_user_role();
create or replace function public.get_current_user_role()
returns text
language sql
security definer
set search_path = public
as $$
    select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'user_role', '')::text;
$$;

-- 3. Table Definitions
-- -----------------------------------------------------------------------------

create table if not exists public.companies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now()
);
alter table public.companies enable row level security;

create table if not exists public.company_settings (
  company_id uuid primary key references public.companies(id) on delete cascade,
  dead_stock_days int not null default 90,
  fast_moving_days int not null default 30,
  overstock_multiplier int not null default 3,
  high_value_threshold int not null default 100000, -- in cents
  predictive_stock_days int not null default 7,
  promo_sales_lift_multiplier real not null default 2.5,
  currency text default 'USD',
  timezone text default 'UTC',
  tax_rate numeric default 0,
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
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  title text not null,
  description text,
  handle text,
  product_type text,
  tags text[],
  status text,
  image_url text,
  external_product_id text,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  unique(company_id, external_product_id)
);
alter table public.products enable row level security;

create table if not exists public.product_variants (
  id uuid primary key default gen_random_uuid(),
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
  price int, -- in cents
  compare_at_price int, -- in cents
  cost int, -- in cents
  inventory_quantity int not null default 0,
  external_variant_id text,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  unique(company_id, sku),
  unique(company_id, external_variant_id)
);
alter table public.product_variants enable row level security;

create table if not exists public.suppliers (
  id uuid primary key default gen_random_uuid(),
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

create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  customer_name text,
  email text,
  total_orders int default 0,
  total_spent int default 0,
  first_order_date date,
  deleted_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.customers enable row level security;

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  order_number text not null,
  external_order_id text,
  customer_id uuid references public.customers(id) on delete set null,
  financial_status text default 'pending',
  fulfillment_status text default 'unfulfilled',
  currency text default 'USD',
  subtotal int not null default 0,
  total_tax int default 0,
  total_shipping int default 0,
  total_discounts int default 0,
  total_amount int not null,
  source_platform text,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);
alter table public.orders enable row level security;

create table if not exists public.order_line_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  variant_id uuid references public.product_variants(id) on delete set null,
  company_id uuid not null references public.companies(id) on delete cascade,
  product_name text,
  variant_title text,
  sku text,
  quantity int not null,
  price int not null, -- in cents
  total_discount int default 0,
  tax_amount int default 0,
  cost_at_time int, -- in cents
  external_line_item_id text,
  unique(order_id, external_line_item_id)
);
alter table public.order_line_items enable row level security;


create table if not exists public.inventory_ledger (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    change_type text not null,
    quantity_change int not null,
    new_quantity int not null,
    related_id uuid, -- e.g., order_id, purchase_order_id
    notes text,
    created_at timestamptz not null default now()
);
alter table public.inventory_ledger enable row level security;


create table if not exists public.integrations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
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
alter table public.integrations enable row level security;


create table if not exists public.webhook_events (
  id uuid primary key default gen_random_uuid(),
  integration_id uuid not null references public.integrations(id) on delete cascade,
  webhook_id text not null,
  processed_at timestamptz default now(),
  created_at timestamptz default now(),
  unique(integration_id, webhook_id)
);
alter table public.webhook_events enable row level security;

create table if not exists public.conversations (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    title text not null,
    created_at timestamptz default now(),
    last_accessed_at timestamptz default now(),
    is_starred boolean default false
);
alter table public.conversations enable row level security;

create table if not exists public.messages (
    id uuid primary key default gen_random_uuid(),
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
alter table public.messages enable row level security;

create table if not exists public.audit_log (
  id bigserial primary key,
  company_id uuid references public.companies(id) on delete set null,
  user_id uuid references auth.users(id) on delete set null,
  action text not null,
  details jsonb,
  created_at timestamptz default now()
);
alter table public.audit_log enable row level security;


create table if not exists public.channel_fees (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  channel_name text not null,
  percentage_fee numeric not null,
  fixed_fee numeric not null,
  created_at timestamptz default now(),
  updated_at timestamptz,
  unique(company_id, channel_name)
);
alter table public.channel_fees enable row level security;

create table if not exists public.export_jobs (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  requested_by_user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending',
  download_url text,
  expires_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.export_jobs enable row level security;

create table if not exists public.user_feedback (
    id bigserial primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    subject_id text not null, -- Can be anomaly ID, message ID, etc.
    subject_type text not null, -- 'anomaly_explanation', 'ai_response'
    feedback text not null, -- 'helpful' or 'unhelpful'
    created_at timestamptz default now()
);
alter table public.user_feedback enable row level security;


-- 4. Indexes
-- -----------------------------------------------------------------------------
create index if not exists idx_products_company_id on public.products(company_id);
create index if not exists idx_product_variants_company_sku on public.product_variants(company_id, sku);
create index if not exists idx_product_variants_product_id on public.product_variants(product_id);
create index if not exists idx_orders_company_created_at on public.orders(company_id, created_at desc);
create index if not exists idx_order_line_items_order_id on public.order_line_items(order_id);
create index if not exists idx_inventory_ledger_variant_id on public.inventory_ledger(variant_id);
create index if not exists idx_inventory_ledger_company_id_created_at on public.inventory_ledger(company_id, created_at desc);
create index if not exists pgrn_products_title on public.products using pgroonga (title);


-- 5. Triggers and Functions for Business Logic
-- -----------------------------------------------------------------------------

-- This function runs after a user signs up.
-- It creates a company for them and links it to their user account.
drop function if exists public.handle_new_user();
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
as $$
declare
  new_company_id uuid;
begin
  -- Create a new company
  insert into public.companies (name)
  values (new.raw_user_meta_data ->> 'company_name')
  returning id into new_company_id;

  -- Update the user's app_metadata with the new company_id and role
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'user_role', 'Owner')
  where id = new.id;
  
  return new;
end;
$$;

-- Attach the function to the auth.users table as a trigger
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- This function updates the inventory_quantity on the product_variants table
-- whenever a new record is inserted into the inventory_ledger.
drop function if exists public.update_variant_quantity_from_ledger();
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

-- Attach the trigger to the inventory_ledger table
drop trigger if exists on_inventory_ledger_insert on public.inventory_ledger;
create trigger on_inventory_ledger_insert
  after insert on public.inventory_ledger
  for each row execute procedure public.update_variant_quantity_from_ledger();
  
-- Function to get users for a company
drop function if exists public.get_users_for_company(uuid);
create or replace function public.get_users_for_company(p_company_id uuid)
returns table (id uuid, email text, role text)
language plpgsql
as $$
begin
  return query
  select u.id, u.email, u.raw_app_meta_data ->> 'user_role' as role
  from auth.users u
  where (u.raw_app_meta_data ->> 'company_id')::uuid = p_company_id
  and u.deleted_at is null;
end;
$$;

-- Drop both potential old signatures before creating the correct one
drop function if exists public.record_order_from_platform(uuid, jsonb, text);
drop function if exists public.record_order_from_platform(p_company_id uuid, p_order_payload jsonb, p_platform text);
create or replace function public.record_order_from_platform(p_company_id uuid, p_order_payload jsonb, p_platform text)
returns void
language plpgsql
as $$
declare
  v_customer_id uuid;
  v_order_id uuid;
  line_item jsonb;
  v_variant_id uuid;
  v_cost_at_time int;
begin
  -- Find or create customer
  select id into v_customer_id from public.customers
  where company_id = p_company_id and email = (p_order_payload -> 'customer' ->> 'email');

  if v_customer_id is null then
    insert into public.customers (company_id, customer_name, email)
    values (
      p_company_id,
      p_order_payload -> 'customer' ->> 'first_name' || ' ' || p_order_payload -> 'customer' ->> 'last_name',
      p_order_payload -> 'customer' ->> 'email'
    )
    returning id into v_customer_id;
  end if;

  -- Create order
  insert into public.orders (company_id, order_number, external_order_id, customer_id, financial_status, fulfillment_status, total_amount, source_platform, created_at)
  values (
    p_company_id,
    p_order_payload ->> 'name',
    p_order_payload ->> 'id',
    v_customer_id,
    p_order_payload ->> 'financial_status',
    p_order_payload ->> 'fulfillment_status',
    (p_order_payload ->> 'total_price')::numeric * 100,
    p_platform,
    (p_order_payload ->> 'created_at')::timestamptz
  )
  returning id into v_order_id;
  
  -- Create line items and update inventory
  for line_item in select * from jsonb_array_elements(p_order_payload -> 'line_items')
  loop
    select id, cost into v_variant_id, v_cost_at_time from public.product_variants
    where company_id = p_company_id and sku = (line_item ->> 'sku');

    if v_variant_id is not null then
      insert into public.order_line_items (order_id, company_id, variant_id, product_name, sku, quantity, price, cost_at_time)
      values (
        v_order_id,
        p_company_id,
        v_variant_id,
        line_item ->> 'name',
        line_item ->> 'sku',
        (line_item ->> 'quantity')::int,
        (line_item ->> 'price')::numeric * 100,
        v_cost_at_time
      );
      
      -- Create inventory ledger entry for the sale
      insert into public.inventory_ledger(company_id, variant_id, change_type, quantity_change, new_quantity, related_id)
      select
          p_company_id,
          v_variant_id,
          'sale',
          -(line_item ->> 'quantity')::int,
          pv.inventory_quantity - (line_item ->> 'quantity')::int,
          v_order_id
      from public.product_variants pv
      where pv.id = v_variant_id;
    end if;
  end loop;
end;
$$;


-- 6. Performance Views
-- -----------------------------------------------------------------------------
drop view if exists public.company_dashboard_metrics;
create or replace view public.company_dashboard_metrics as
select
    c.id as company_id,
    c.name as company_name,
    coalesce(sum(o.total_amount), 0) as total_revenue,
    coalesce(count(distinct o.id), 0) as total_orders,
    coalesce(sum(o.total_amount) / nullif(count(distinct o.id), 0), 0) as avg_order_value,
    coalesce(sum(oli.price * oli.quantity - oli.cost_at_time * oli.quantity), 0) as total_profit
from
    companies c
left join orders o on c.id = o.company_id and o.created_at > (now() - interval '30 days')
left join order_line_items oli on o.id = oli.order_id
group by
    c.id, c.name;


-- This is a more complex function that uses a date series to ensure we have a row for every day,
-- even if there were no sales. This is crucial for accurate charting.
drop function if exists public.get_dashboard_metrics(uuid,integer);
create or replace function public.get_dashboard_metrics(p_company_id uuid, p_days integer)
returns table (
    totalSalesValue numeric,
    totalProfit numeric,
    averageOrderValue numeric,
    totalOrders bigint,
    totalSkus bigint,
    totalInventoryValue numeric,
    lowStockItemsCount bigint,
    deadStockItemsCount bigint,
    salesTrendData jsonb,
    inventoryByCategoryData jsonb,
    topCustomersData jsonb
)
language plpgsql
as $$
declare
    v_end_date date := current_date;
    v_start_date date := v_end_date - (p_days - 1) * interval '1 day';
begin
    return query
    with date_series as (
        select generate_series(v_start_date, v_end_date, '1 day'::interval)::date as day
    ),
    company_context as (
        select p_company_id::uuid as company_id
    ),
    daily_sales as (
        select
            d.day,
            coalesce(sum(o.total_amount), 0) as daily_revenue
        from date_series d
        cross join company_context cc
        left join public.orders o
            on o.company_id = cc.company_id
            and o.created_at::date = d.day
        group by d.day
    )
    select
        -- Aggregate Metrics
        (select sum(ds.daily_revenue) from daily_sales ds) as totalSalesValue,
        (select sum((oli.price - oli.cost_at_time) * oli.quantity) from public.order_line_items oli join public.orders o on oli.order_id = o.id where o.company_id = p_company_id and o.created_at >= v_start_date) as totalProfit,
        (select avg(o.total_amount) from public.orders o where o.company_id = p_company_id and o.created_at >= v_start_date) as averageOrderValue,
        (select count(*) from public.orders o where o.company_id = p_company_id and o.created_at >= v_start_date) as totalOrders,
        (select count(*) from public.product_variants pv where pv.company_id = p_company_id) as totalSkus,
        (select sum(pv.inventory_quantity * pv.cost) from public.product_variants pv where pv.company_id = p_company_id and pv.cost is not null) as totalInventoryValue,
        (select count(*) from public.get_reorder_suggestions(p_company_id)) as lowStockItemsCount,
        (select count(*) from public.get_dead_stock_report(p_company_id)) as deadStockItemsCount,

        -- Charting Data
        (select jsonb_agg(jsonb_build_object('date', ds.day, 'Sales', ds.daily_revenue)) from daily_sales ds) as salesTrendData,
        (
            select jsonb_agg(t) from (
                select p.product_type as name, sum(pv.inventory_quantity * pv.cost) as value
                from public.product_variants pv
                join public.products p on pv.product_id = p.id
                where pv.company_id = p_company_id and p.product_type is not null and pv.cost is not null
                group by p.product_type
                order by value desc
                limit 5
            ) t
        ) as inventoryByCategoryData,
        (
             select jsonb_agg(t) from (
                select c.customer_name as name, sum(o.total_amount) as value
                from public.orders o
                join public.customers c on o.customer_id = c.id
                where o.company_id = p_company_id and o.created_at >= v_start_date
                group by c.customer_name
                order by value desc
                limit 5
            ) t
        ) as topCustomersData;
end;
$$;


-- 7. Row-Level Security (RLS) Policies
-- These policies ensure that users can only access data for their own company.
-- -----------------------------------------------------------------------------

-- Companies: Users can see their own company.
drop policy if exists "Allow full access based on company_id" on public.companies;
create policy "Allow full access based on company_id" on public.companies
  for all using (id = get_current_company_id()) with check (id = get_current_company_id());

-- Settings: Users can access their own company's settings.
drop policy if exists "Allow full access based on company_id" on public.company_settings;
create policy "Allow full access based on company_id" on public.company_settings
  for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

-- Products: Users can access their own company's products.
drop policy if exists "Allow full access based on company_id" on public.products;
create policy "Allow full access based on company_id" on public.products
  for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

-- Product Variants: Users can access their own company's variants.
drop policy if exists "Allow full access based on company_id" on public.product_variants;
create policy "Allow full access based on company_id" on public.product_variants
  for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

-- Suppliers: Users can access their own company's suppliers.
drop policy if exists "Allow full access based on company_id" on public.suppliers;
create policy "Allow full access based on company_id" on public.suppliers
  for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

-- Customers: Users can access their own company's customers.
drop policy if exists "Allow full access based on company_id" on public.customers;
create policy "Allow full access based on company_id" on public.customers
  for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

-- Orders: Users can access their own company's orders.
drop policy if exists "Allow full access based on company_id" on public.orders;
create policy "Allow full access based on company_id" on public.orders
  for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

-- Order Line Items: Users can access their own company's line items.
drop policy if exists "Allow full access based on company_id" on public.order_line_items;
create policy "Allow full access based on company_id" on public.order_line_items
  for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

-- Inventory Ledger: Users can access their own company's ledger.
drop policy if exists "Allow full access based on company_id" on public.inventory_ledger;
create policy "Allow full access based on company_id" on public.inventory_ledger
  for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

-- Integrations: Users can access their own company's integrations.
drop policy if exists "Allow full access based on company_id" on public.integrations;
create policy "Allow full access based on company_id" on public.integrations
  for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

-- Webhook Events: Users can access webhooks for their own company.
drop policy if exists "Allow full access based on company_id" on public.webhook_events;
create policy "Allow full access based on company_id" on public.webhook_events
  for all using (company_id = (select company_id from integrations where id = integration_id and company_id = get_current_company_id()))
  with check (company_id = (select company_id from integrations where id = integration_id and company_id = get_current_company_id()));

-- Conversations: Users can only access their own conversations.
drop policy if exists "Allow full access to own conversations" on public.conversations;
create policy "Allow full access to own conversations" on public.conversations
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Messages: Users can only access messages in their own company's conversations.
drop policy if exists "Allow full access to own messages" on public.messages;
create policy "Allow full access to own messages" on public.messages
  for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

-- Audit Log: Admins and Owners can read their company's audit log.
drop policy if exists "Allow read access to company audit log" on public.audit_log;
create policy "Allow read access to company audit log" on public.audit_log
  for select using (company_id = get_current_company_id() and get_current_user_role() in ('Admin', 'Owner'));

-- Channel Fees: Users can access their own company's fees.
drop policy if exists "Allow full access based on company_id" on public.channel_fees;
create policy "Allow full access based on company_id" on public.channel_fees
    for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

-- Export Jobs: Users can access their own export jobs.
drop policy if exists "Allow access to own export jobs" on public.export_jobs;
create policy "Allow access to own export jobs" on public.export_jobs
    for all using (requested_by_user_id = auth.uid()) with check (requested_by_user_id = auth.uid());

-- User Feedback: Users can insert feedback for their own company.
drop policy if exists "Allow insert for own company" on public.user_feedback;
create policy "Allow insert for own company" on public.user_feedback
    for insert with check (company_id = get_current_company_id());

-- Disable RLS for auth.users as it's managed by Supabase Auth.
alter table auth.users disable row level security;
