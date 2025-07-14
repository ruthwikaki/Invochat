
-- InvoChat Database Schema
-- Version: 2.0.0
-- Description: Complete schema including tables, functions, RLS policies, and performance optimizations.

-- 1. Extensions
-- Enable the pgcrypto extension for gen_random_uuid()
create extension if not exists pgcrypto with schema public;
-- Enable the pg_stat_statements extension for query performance monitoring
create extension if not exists pg_stat_statements with schema public;
-- Enable the uuid-ossp extension for additional UUID functions if needed
create extension if not exists "uuid-ossp" with schema public;


-- 2. Drop existing objects in reverse order of dependency to ensure a clean slate.
-- This entire section makes the script idempotent and safe to re-run.

-- A. Drop Policies (most dependent)
drop policy if exists "Allow full access based on company_id" on public.companies;
drop policy if exists "Users can see other users in their own company." on public.users;
drop policy if exists "Users can only see their own company's data." on public.users;
drop policy if exists "Allow read access to other users in same company" on public.users;
drop policy if exists "Allow update for own user" on public.users;
drop policy if exists "Allow full access based on company_id" on public.company_settings;
drop policy if exists "Allow full access based on company_id" on public.products;
drop policy if exists "Allow full access based on company_id" on public.product_variants;
drop policy if exists "Allow full access based on company_id" on public.inventory_ledger;
drop policy if exists "Allow full access based on company_id" on public.customers;
drop policy if exists "Allow full access based on company_id" on public.orders;
drop policy if exists "Allow full access based on company_id" on public.order_line_items;
drop policy if exists "Allow full access based on company_id" on public.suppliers;
drop policy if exists "Allow full access based on company_id" on public.conversations;
drop policy if exists "Allow full access based on company_id" on public.messages;
drop policy if exists "Allow full access based on company_id" on public.integrations;
drop policy if exists "Allow full access based on company_id" on public.channel_fees;
drop policy if exists "Allow full access based on company_id" on public.audit_log;
drop policy if exists "Allow read access to company audit log" on public.audit_log;
drop policy if exists "Allow full access based on company_id" on public.webhook_events;
drop policy if exists "Allow read access to webhook_events" on public.webhook_events;
drop policy if exists "Allow full access based on company_id" on public.user_feedback;

-- B. Drop Functions
drop function if exists public.get_current_user_role();
drop function if exists public.get_current_company_id();
drop function if exists public.handle_new_user();
drop function if exists public.update_variant_quantity_from_ledger();
drop function if exists public.record_sale_transaction(uuid, uuid, text, text, text, text, jsonb);
drop function if exists public.get_dashboard_metrics(uuid,integer);
drop function if exists public.record_order_from_platform(p_company_id uuid, p_order_payload jsonb, p_platform text);
drop function if exists public.record_order_from_platform(uuid,jsonb,text,text);


-- 3. Custom Types
-- Create custom types if they don't exist.
do $$
begin
    if not exists (select 1 from pg_type where typname = 'user_role') then
        create type public.user_role as enum ('Owner', 'Admin', 'Member');
    end if;
end$$;


-- 4. Tables
-- Create tables with the "if not exists" clause to prevent errors on re-runs.

create table if not exists public.companies (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    created_at timestamptz not null default now(),
    deleted_at timestamptz
);

create table if not exists public.users (
    id uuid primary key references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    email text,
    role public.user_role not null default 'Member',
    created_at timestamptz default now(),
    deleted_at timestamptz
);

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
    created_at timestamptz not null default now(),
    updated_at timestamptz
);

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
    created_at timestamptz not null default now(),
    updated_at timestamptz,
    deleted_at timestamptz,
    unique(company_id, external_product_id)
);

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
    created_at timestamptz not null default now(),
    updated_at timestamptz,
    unique(company_id, sku),
    unique(company_id, external_variant_id)
);

create table if not exists public.inventory_ledger (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    change_type text not null, -- 'sale', 'restock', 'return', 'adjustment'
    quantity_change int not null,
    new_quantity int not null,
    related_id uuid, -- e.g., order_line_item_id or purchase_order_item_id
    notes text,
    created_at timestamptz not null default now()
);

create table if not exists public.customers (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    customer_name text,
    email text,
    total_orders int default 0,
    total_spent int default 0, -- in cents
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz default now()
);

create table if not exists public.orders (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    order_number text not null,
    external_order_id text,
    customer_id uuid references public.customers(id) on delete set null,
    financial_status text,
    fulfillment_status text,
    currency text default 'USD',
    subtotal int not null default 0, -- in cents
    total_tax int default 0,
    total_shipping int default 0,
    total_discounts int default 0,
    total_amount int not null,
    source_platform text,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);

create table if not exists public.order_line_items (
    id uuid primary key default gen_random_uuid(),
    order_id uuid not null references public.orders(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    variant_id uuid references public.product_variants(id) on delete set null,
    product_name text,
    variant_title text,
    sku text,
    quantity int not null,
    price int not null, -- in cents
    total_discount int default 0,
    tax_amount int default 0,
    cost_at_time int,
    external_line_item_id text
);

create table if not exists public.suppliers (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    name text not null,
    email text,
    phone text,
    default_lead_time_days int,
    notes text,
    created_at timestamptz not null default now(),
    deleted_at timestamptz
);

create table if not exists public.conversations (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    title text not null,
    created_at timestamptz default now(),
    last_accessed_at timestamptz default now(),
    is_starred boolean default false
);

create table if not exists public.messages (
    id uuid primary key default gen_random_uuid(),
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

create table if not exists public.integrations (
    id uuid primary key default gen_random_uuid(),
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

create table if not exists public.channel_fees (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    channel_name text not null,
    percentage_fee numeric not null,
    fixed_fee integer not null, -- in cents
    created_at timestamptz default now(),
    updated_at timestamptz,
    unique(company_id, channel_name)
);

create table if not exists public.audit_log (
    id bigserial primary key,
    company_id uuid references public.companies(id) on delete cascade,
    user_id uuid references auth.users(id) on delete set null,
    action text not null,
    details jsonb,
    created_at timestamptz default now()
);

create table if not exists public.webhook_events (
    id uuid primary key default gen_random_uuid(),
    integration_id uuid not null references public.integrations(id) on delete cascade,
    webhook_id text not null,
    processed_at timestamptz default now(),
    created_at timestamptz default now(),
    unique(webhook_id)
);

create table if not exists public.export_jobs (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    requested_by_user_id uuid not null references auth.users(id) on delete cascade,
    status text not null default 'pending',
    download_url text,
    expires_at timestamptz,
    created_at timestamptz not null default now()
);

create table if not exists public.user_feedback (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    subject_id text not null,
    subject_type text not null,
    feedback text not null, -- 'helpful' or 'unhelpful'
    created_at timestamptz not null default now()
);


-- 5. Helper Functions
-- These functions are used by RLS policies and triggers.

-- Gets the company_id from the session claims.
create or replace function public.get_current_company_id()
returns uuid
language sql
security definer
set search_path = public
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid;
$$;

-- Gets the role from the session claims.
create or replace function public.get_current_user_role()
returns text
language sql
security definer
set search_path = public
as $$
    select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'role', '');
$$;


-- 6. Triggers and Trigger Functions
-- Functions that respond to database events.

-- Trigger function to create a new company and user profile on user signup.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  new_company_id uuid;
  new_user_role public.user_role;
begin
  -- Create a new company for the user
  insert into public.companies (name)
  values (new.raw_app_meta_data->>'company_name')
  returning id into new_company_id;

  -- Set the user's role to 'Owner'
  new_user_role := 'Owner';

  -- Create a corresponding user entry in public.users
  insert into public.users (id, company_id, email, role)
  values (new.id, new_company_id, new.email, new_user_role);

  -- Update the user's app_metadata with the new company_id and role
  update auth.users
  set raw_app_meta_data = new.raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'role', new_user_role)
  where id = new.id;

  return new;
end;
$$;

-- Attach the trigger to the auth.users table
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();


-- Trigger function to update product_variants.inventory_quantity from the ledger.
create or replace function public.update_variant_quantity_from_ledger()
returns trigger
language plpgsql
as $$
begin
  update public.product_variants
  set inventory_quantity = new.new_quantity
  where id = new.variant_id;
  return new;
end;
$$;

-- Attach the trigger to the inventory_ledger table
drop trigger if exists on_inventory_ledger_insert on public.inventory_ledger;
create trigger on_inventory_ledger_insert
  after insert on public.inventory_ledger
  for each row
  execute function public.update_variant_quantity_from_ledger();


-- 7. Database Functions (RPCs)
-- These are the functions the application backend calls for business logic.

-- Function to record a sale and automatically create/update customer and decrement inventory.
drop function if exists public.record_sale_transaction(uuid, uuid, text, text, text, text, jsonb);
create or replace function public.record_sale_transaction(
    p_company_id uuid,
    p_user_id uuid,
    p_customer_name text,
    p_customer_email text,
    p_payment_method text,
    p_notes text,
    p_sale_items jsonb, -- e.g., '[{"sku":"123","quantity":1,"unit_price":1000, "cost_at_time": 500}]'
    p_external_id text default null
)
returns uuid
language plpgsql
as $$
declare
  v_customer_id uuid;
  v_order_id uuid;
  v_variant_id uuid;
  v_total_amount int := 0;
  item record;
  v_line_item_id uuid;
begin
  -- Find or create customer
  if p_customer_email is not null then
    select id into v_customer_id from public.customers where email = p_customer_email and company_id = p_company_id;
    if v_customer_id is null then
      insert into public.customers (company_id, customer_name, email, first_order_date)
      values (p_company_id, p_customer_name, p_customer_email, current_date)
      returning id into v_customer_id;
    end if;
  end if;

  -- Create order
  insert into public.orders (company_id, order_number, customer_id, total_amount, notes, source_platform, external_order_id)
  values (p_company_id, 'ORD-' || (select count(*) + 1001 from orders), v_customer_id, 0, p_notes, p_payment_method, p_external_id)
  returning id into v_order_id;

  -- Process line items
  for item in select * from jsonb_to_recordset(p_sale_items) as x(sku text, quantity int, unit_price int, cost_at_time int, product_name text)
  loop
    select id into v_variant_id from public.product_variants where sku = item.sku and company_id = p_company_id;

    if v_variant_id is null then
        -- Optionally, handle cases where the SKU doesn't exist.
        -- For now, we'll skip it but a real app might create a placeholder product.
        continue;
    end if;
    
    insert into public.order_line_items (order_id, company_id, variant_id, sku, product_name, quantity, price, cost_at_time)
    values (v_order_id, p_company_id, v_variant_id, item.sku, item.product_name, item.quantity, item.unit_price, item.cost_at_time)
    returning id into v_line_item_id;

    v_total_amount := v_total_amount + (item.quantity * item.unit_price);
    
    -- Update inventory ledger
    insert into public.inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id)
    select p_company_id, v_variant_id, 'sale', -item.quantity, pv.inventory_quantity - item.quantity, v_line_item_id
    from public.product_variants pv where pv.id = v_variant_id;
    
  end loop;

  -- Update order total
  update public.orders set total_amount = v_total_amount where id = v_order_id;
  
  -- Update customer aggregates
  if v_customer_id is not null then
    update public.customers
    set total_spent = total_spent + v_total_amount,
        total_orders = total_orders + 1
    where id = v_customer_id;
  end if;
  
  return v_order_id;
end;
$$;

-- Function to get dashboard metrics.
drop function if exists public.get_dashboard_metrics(uuid,integer);
create or replace function public.get_dashboard_metrics(p_company_id uuid, p_days integer)
returns table (
    total_sales_value bigint,
    total_profit bigint,
    total_orders bigint,
    average_order_value bigint,
    total_inventory_value bigint,
    total_skus bigint,
    low_stock_items_count bigint,
    dead_stock_items_count bigint,
    sales_trend_data jsonb,
    inventory_by_category_data jsonb,
    top_customers_data jsonb
)
language plpgsql
as $$
begin
    return query
    with date_series as (
        select generate_series(
            (current_date - (p_days - 1) * interval '1 day'),
            current_date,
            '1 day'::interval
        )::date as date
    ),
    company_context as (
        select p_company_id::uuid as company_id
    ),
    daily_sales as (
        select
            o.created_at::date as date,
            sum(o.total_amount) as daily_revenue,
            sum(o.total_amount - coalesce(oli.total_cost, 0)) as daily_profit
        from orders o
        join (
            select order_id, sum(cost_at_time * quantity) as total_cost
            from order_line_items
            where company_id = p_company_id
            group by order_id
        ) oli on o.id = oli.order_id
        where o.company_id = p_company_id
        and o.created_at >= (current_date - (p_days - 1) * interval '1 day')
        group by o.created_at::date
    ),
    sales_trend as (
        select
            ds.date,
            coalesce(d.daily_revenue, 0) as "Sales"
        from date_series ds
        left join daily_sales d on ds.date = d.date
        order by ds.date
    )
    select
        -- Aggregate Metrics
        sum(coalesce(d.daily_revenue, 0))::bigint as total_sales_value,
        sum(coalesce(d.daily_profit, 0))::bigint as total_profit,
        (select count(*) from orders where company_id = p_company_id and created_at >= (current_date - (p_days - 1) * interval '1 day'))::bigint as total_orders,
        (avg(o.total_amount))::bigint as average_order_value,
        (select sum(cost * inventory_quantity) from product_variants where company_id = p_company_id)::bigint as total_inventory_value,
        (select count(*) from product_variants where company_id = p_company_id)::bigint as total_skus,
        0::bigint as low_stock_items_count, -- Placeholder
        0::bigint as dead_stock_items_count, -- Placeholder
        -- Chart Data
        (select jsonb_agg(json_build_object('date', date, 'Sales', "Sales")) from sales_trend) as sales_trend_data,
        (
            select jsonb_agg(cat)
            from (
                select
                    coalesce(p.product_type, 'Uncategorized') as name,
                    sum(pv.cost * pv.inventory_quantity) as value
                from product_variants pv
                join products p on pv.product_id = p.id
                where pv.company_id = p_company_id and pv.cost is not null and pv.inventory_quantity > 0
                group by p.product_type
                order by value desc
                limit 5
            ) cat
        ) as inventory_by_category_data,
        (
            select jsonb_agg(cust)
            from (
                select
                    c.customer_name as name,
                    sum(o.total_amount) as value
                from orders o
                join customers c on o.customer_id = c.id
                where o.company_id = p_company_id
                and o.created_at >= (current_date - (p_days - 1) * interval '1 day')
                group by c.customer_name
                order by value desc
                limit 5
            ) cust
        ) as top_customers_data
    from company_context
    left join daily_sales d on true -- Fake join to get one row
    left join orders o on o.company_id = company_context.company_id and o.created_at >= (current_date - (p_days - 1) * interval '1 day')
    group by company_context.company_id;
end;
$$;


-- 8. Row Level Security (RLS)
-- Enable RLS and define policies for all tables.

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
alter table public.channel_fees enable row level security;
alter table public.audit_log enable row level security;
alter table public.webhook_events enable row level security;
alter table public.user_feedback enable row level security;
alter table public.export_jobs enable row level security;

-- Force RLS for table owners (important for security)
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
alter table public.channel_fees force row level security;
alter table public.audit_log force row level security;
alter table public.webhook_events force row level security;
alter table public.user_feedback force row level security;
alter table public.export_jobs force row level security;

-- Policies
create policy "Allow full access based on company_id" on public.companies for all using (id = get_current_company_id()) with check (id = get_current_company_id());
create policy "Users can see other users in their own company." on public.users for select using (company_id = get_current_company_id());
create policy "Allow read access to other users in same company" on public.users for select using (company_id = get_current_company_id());
create policy "Allow update for own user" on public.users for update using (id = auth.uid());
create policy "Allow full access based on company_id" on public.company_settings for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());
create policy "Allow full access based on company_id" on public.products for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());
create policy "Allow full access based on company_id" on public.product_variants for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());
create policy "Allow full access based on company_id" on public.inventory_ledger for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());
create policy "Allow full access based on company_id" on public.customers for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());
create policy "Allow full access based on company_id" on public.orders for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());
create policy "Allow full access based on company_id" on public.order_line_items for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());
create policy "Allow full access based on company_id" on public.suppliers for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());
create policy "Allow full access based on company_id" on public.conversations for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());
create policy "Allow full access based on company_id" on public.messages for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());
create policy "Allow full access based on company_id" on public.integrations for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());
create policy "Allow full access based on company_id" on public.channel_fees for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());
create policy "Allow read access to company audit log" on public.audit_log for select using (company_id = get_current_company_id());
create policy "Allow read access to webhook_events" on public.webhook_events for select using (company_id = get_current_company_id());
create policy "Allow full access based on company_id" on public.user_feedback for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());
create policy "Allow access to own jobs" on public.export_jobs for all using (company_id = get_current_company_id() and requested_by_user_id = auth.uid());


-- 9. Indexes for Performance
-- Add indexes to foreign keys and commonly queried columns.

create index if not exists idx_users_company_id on public.users(company_id);
create index if not exists idx_products_company_id on public.products(company_id);
create index if not exists idx_variants_product_id on public.product_variants(product_id);
create index if not exists idx_variants_company_sku on public.product_variants(company_id, sku);
create index if not exists idx_ledger_variant_id on public.inventory_ledger(variant_id);
create index if not exists idx_ledger_company_created_at on public.inventory_ledger(company_id, created_at desc);
create index if not exists idx_orders_company_id on public.orders(company_id);
create index if not exists idx_orders_customer_id on public.orders(customer_id);
create index if not exists idx_orders_company_created_at on public.orders(company_id, created_at desc);
create index if not exists idx_line_items_order_id on public.order_line_items(order_id);
create index if not exists idx_line_items_variant_id on public.order_line_items(variant_id);


-- 10. Materialized Views (for performance-intensive queries)

-- Note: This is an example. In a real application, you'd create more complex materialized views for dashboard queries.
-- This view is currently not used but serves as a template.
create materialized view if not exists public.company_dashboard_metrics as
  select
    c.id as company_id,
    count(distinct p.id) as total_products,
    sum(pv.inventory_quantity) as total_units,
    sum(pv.inventory_quantity * pv.cost) / 100 as total_inventory_value
  from companies c
  left join products p on c.id = p.company_id
  left join product_variants pv on p.id = pv.product_id
  group by c.id;

-- You would refresh this view periodically, e.g., with a cron job.
-- REFRESH MATERIALIZED VIEW public.company_dashboard_metrics;

-- End of schema
