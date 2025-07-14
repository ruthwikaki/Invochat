
-- Enable UUID generation
create extension if not exists "uuid-ossp" with schema extensions;

-- Create the companies table
create table if not exists public.companies (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    created_at timestamptz not null default now(),
    deleted_at timestamptz
);
comment on table public.companies is 'Stores company/organization information.';

-- Create the users table to link auth.users with companies
create table if not exists public.users (
    id uuid primary key references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    email text,
    role text default 'member'::text check (role in ('owner', 'admin', 'member')),
    deleted_at timestamptz,
    created_at timestamptz default now()
);
comment on table public.users is 'Links Supabase auth users to companies and roles.';

-- Create the company_settings table
create table if not exists public.company_settings (
    company_id uuid primary key references public.companies(id) on delete cascade,
    dead_stock_days integer not null default 90,
    fast_moving_days integer not null default 30,
    predictive_stock_days integer not null default 7,
    overstock_multiplier integer not null default 3,
    high_value_threshold integer not null default 100000, -- Stored in cents
    currency text default 'USD'::text,
    timezone text default 'UTC'::text,
    tax_rate numeric default 0,
    promo_sales_lift_multiplier real not null default 2.5,
    custom_rules jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz,
    subscription_status text default 'trial'::text,
    subscription_plan text default 'starter'::text,
    subscription_expires_at timestamptz,
    stripe_customer_id text,
    stripe_subscription_id text
);
comment on table public.company_settings is 'Stores various business rule settings for each company.';

-- Create products table
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
comment on table public.products is 'Stores parent product information.';

-- Create product_variants table
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
    inventory_quantity integer not null default 0,
    external_variant_id text,
    created_at timestamptz default now(),
    updated_at timestamptz,
    deleted_at timestamptz,
    unique(company_id, sku),
    unique(company_id, external_variant_id)
);
comment on table public.product_variants is 'Stores individual product variants (SKUs).';

-- Create suppliers table
create table if not exists public.suppliers (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    name text not null,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz not null default now(),
    deleted_at timestamptz
);
comment on table public.suppliers is 'Stores supplier and vendor information.';

-- Create customers table
create table if not exists public.customers (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    customer_name text not null,
    email text,
    total_orders integer default 0,
    total_spent integer default 0, -- in cents
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz default now(),
    unique(company_id, email)
);
comment on table public.customers is 'Stores customer information.';

-- Create orders table
create table if not exists public.orders (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    order_number text not null,
    external_order_id text,
    customer_id uuid references public.customers(id) on delete set null,
    financial_status text default 'pending'::text,
    fulfillment_status text default 'unfulfilled'::text,
    currency text default 'USD'::text,
    subtotal integer not null default 0, -- in cents
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
    updated_at timestamptz,
    deleted_at timestamptz,
    unique(company_id, external_order_id)
);
comment on table public.orders is 'Stores sales order headers.';

-- Create order_line_items table
create table if not exists public.order_line_items (
    id uuid primary key default gen_random_uuid(),
    order_id uuid not null references public.orders(id) on delete cascade,
    variant_id uuid references public.product_variants(id) on delete set null,
    company_id uuid not null references public.companies(id) on delete cascade,
    product_name text not null,
    variant_title text,
    sku text,
    quantity integer not null,
    price integer not null, -- in cents
    total_discount integer default 0,
    tax_amount integer default 0,
    cost_at_time integer, -- in cents
    external_line_item_id text,
    unique(order_id, external_line_item_id)
);
comment on table public.order_line_items is 'Stores individual line items for each order.';

-- Create inventory_ledger table
create table if not exists public.inventory_ledger (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    change_type text not null,
    quantity_change integer not null,
    new_quantity integer not null,
    related_id uuid, -- e.g., order_id, refund_id, etc.
    notes text,
    created_at timestamptz not null default now()
);
comment on table public.inventory_ledger is 'Transactional log of all inventory movements.';

-- Create conversations table
create table if not exists public.conversations (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    title text not null,
    created_at timestamptz default now(),
    last_accessed_at timestamptz default now(),
    is_starred boolean default false
);
comment on table public.conversations is 'Stores metadata for AI chat conversations.';

-- Create messages table
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
comment on table public.messages is 'Stores individual messages within a conversation.';

-- Create integrations table
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
comment on table public.integrations is 'Stores configuration for third-party integrations.';

-- Create webhook_events table
create table if not exists public.webhook_events (
    id uuid primary key default gen_random_uuid(),
    integration_id uuid not null references public.integrations(id) on delete cascade,
    webhook_id text not null,
    processed_at timestamptz default now(),
    created_at timestamptz default now(),
    unique(integration_id, webhook_id)
);
comment on table public.webhook_events is 'Logs incoming webhook IDs to prevent replay attacks.';

-- Create audit_log table
create table if not exists public.audit_log (
    id bigserial primary key,
    company_id uuid references public.companies(id) on delete set null,
    user_id uuid references auth.users(id) on delete set null,
    action text not null,
    details jsonb,
    created_at timestamptz default now()
);
comment on table public.audit_log is 'Records important user and system actions.';

-- Create export_jobs table
create table if not exists public.export_jobs (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    requested_by_user_id uuid not null references auth.users(id) on delete cascade,
    status text not null default 'pending',
    download_url text,
    expires_at timestamptz,
    created_at timestamptz not null default now()
);
comment on table public.export_jobs is 'Tracks background data export jobs.';

-- Create channel_fees table
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
comment on table public.channel_fees is 'Stores fees for sales channels to calculate net margin.';

-- Create user_feedback table
create table if not exists public.user_feedback (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    subject_id text not null,
    subject_type text not null, -- e.g., 'anomaly_explanation', 'ai_response'
    feedback text not null, -- 'helpful' or 'unhelpful'
    created_at timestamptz not null default now()
);
comment on table public.user_feedback is 'Stores user feedback on AI-generated content.';

-- =================================================================
-- HELPER FUNCTIONS
-- =================================================================

-- Function to get the company_id from a JWT claim
create or replace function public.get_current_company_id()
returns uuid
language sql stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid;
$$;

-- Function to get user role from a JWT claim
create or replace function public.get_current_user_role()
returns text
language sql stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'role', '')::text;
$$;

-- Function to get the authenticated user's ID
create or replace function public.get_current_user_id()
returns uuid
language sql stable
as $$
  select auth.uid();
$$;

-- =================================================================
-- BUSINESS LOGIC FUNCTIONS
-- =================================================================

-- Function to handle new user sign-up
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer -- required to write to public.users table
as $$
declare
  company_id uuid;
  user_role text;
begin
  -- First, create a new company for the user
  insert into public.companies (name)
  values (new.raw_app_meta_data->>'company_name')
  returning id into company_id;

  -- Set the user's role to 'owner'
  user_role := 'owner';

  -- Now, insert a record into the public.users table
  insert into public.users (id, company_id, email, role)
  values (new.id, company_id, new.email, user_role);

  -- Update the user's app_metadata with the new company_id and role
  update auth.users
  set raw_app_meta_data = new.raw_app_meta_data || jsonb_build_object('company_id', company_id, 'role', user_role)
  where id = new.id;

  return new;
end;
$$;

-- Trigger to call handle_new_user on new user creation
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


-- Function to update product variant quantity based on ledger entries
create or replace function public.update_variant_quantity_from_ledger()
returns trigger
language plpgsql
as $$
begin
  update public.product_variants
  set inventory_quantity = new.new_quantity
  where id = new.variant_id and company_id = new.company_id;
  return new;
end;
$$;

-- Trigger to update inventory quantity after a new ledger entry
drop trigger if exists on_inventory_ledger_insert on public.inventory_ledger;
create trigger on_inventory_ledger_insert
  after insert on public.inventory_ledger
  for each row execute procedure public.update_variant_quantity_from_ledger();


-- Function to record an order from a platform payload
drop function if exists public.record_order_from_platform(uuid, text, jsonb);
create or replace function public.record_order_from_platform(
    p_company_id uuid,
    p_platform text,
    p_order_payload jsonb
)
returns uuid -- returns the internal order ID
language plpgsql
as $$
declare
    v_customer_id uuid;
    v_order_id uuid;
    v_variant_id uuid;
    v_line_item jsonb;
    v_order_number text;
    v_financial_status text;
    v_fulfillment_status text;
    v_email text;
    v_customer_name text;
    v_external_order_id text;
    v_created_at timestamptz;
begin
    -- Extract common fields based on platform
    if p_platform = 'shopify' then
        v_external_order_id := p_order_payload->>'id';
        v_order_number := p_order_payload->>'name';
        v_financial_status := p_order_payload->>'financial_status';
        v_fulfillment_status := p_order_payload->>'fulfillment_status';
        v_email := lower(p_order_payload->'customer'->>'email');
        v_customer_name := (p_order_payload->'customer'->>'first_name') || ' ' || (p_order_payload->'customer'->>'last_name');
        v_created_at := (p_order_payload->>'created_at')::timestamptz;
    elsif p_platform = 'woocommerce' then
        v_external_order_id := p_order_payload->>'id';
        v_order_number := '#' || (p_order_payload->>'id');
        v_financial_status := case when (p_order_payload->>'paid')::boolean then 'paid' else 'pending' end;
        v_fulfillment_status := p_order_payload->>'status';
        v_email := lower(p_order_payload->'billing'->>'email');
        v_customer_name := (p_order_payload->'billing'->>'first_name') || ' ' || (p_order_payload->'billing'->>'last_name');
        v_created_at := (p_order_payload->>'date_created_gmt')::timestamptz;
    else
        raise exception 'Unsupported platform: %', p_platform;
    end if;

    -- Find or create customer
    if v_email is not null then
        select id into v_customer_id from public.customers where company_id = p_company_id and email = v_email;
        if v_customer_id is null then
            insert into public.customers (company_id, customer_name, email, first_order_date)
            values (p_company_id, v_customer_name, v_email, v_created_at::date)
            returning id into v_customer_id;
        end if;
    end if;

    -- Upsert order header
    insert into public.orders (
        company_id, external_order_id, order_number, customer_id, financial_status, fulfillment_status,
        total_amount, subtotal, total_tax, total_shipping, total_discounts, source_platform, created_at
    )
    values (
        p_company_id, v_external_order_id, v_order_number, v_customer_id, v_financial_status, v_fulfillment_status,
        (p_order_payload->>'total_price')::numeric * 100,
        (p_order_payload->>'subtotal_price')::numeric * 100,
        (p_order_payload->>'total_tax')::numeric * 100,
        (p_order_payload->'total_shipping_price'->>'amount')::numeric * 100,
        (p_order_payload->>'total_discounts')::numeric * 100,
        p_platform, v_created_at
    )
    on conflict (company_id, external_order_id) do update set
        financial_status = excluded.financial_status,
        fulfillment_status = excluded.fulfillment_status,
        updated_at = now()
    returning id into v_order_id;
    
    -- Loop through line items
    for v_line_item in select * from jsonb_array_elements(p_order_payload->'line_items')
    loop
        -- Find variant by SKU
        select id into v_variant_id from public.product_variants where company_id = p_company_id and sku = v_line_item->>'sku';

        if v_variant_id is not null then
            -- Upsert line item
            insert into public.order_line_items (
                order_id, company_id, variant_id, product_name, sku, quantity, price, cost_at_time, external_line_item_id
            )
            values (
                v_order_id, p_company_id, v_variant_id, v_line_item->>'title', v_line_item->>'sku',
                (v_line_item->>'quantity')::integer,
                (v_line_item->>'price')::numeric * 100,
                (select cost from public.product_variants where id = v_variant_id),
                v_line_item->>'id'
            )
            on conflict (order_id, external_line_item_id) do nothing;
            
            -- Create inventory ledger entry for sale
            insert into public.inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id)
            values (
                p_company_id,
                v_variant_id,
                'sale',
                -(v_line_item->>'quantity')::integer,
                (select inventory_quantity from public.product_variants where id = v_variant_id) - (v_line_item->>'quantity')::integer,
                v_order_id
            );
        else
            -- Log skipped SKU
            insert into public.audit_log(company_id, action, details)
            values(p_company_id, 'skipped_line_item', jsonb_build_object('order_id', v_order_id, 'sku', v_line_item->>'sku', 'reason', 'SKU not found in product_variants'));
        end if;
    end loop;
    
    return v_order_id;
end;
$$;


-- =================================================================
-- PERFORMANCE VIEWS
-- =================================================================

-- View for dashboard metrics
drop view if exists public.company_dashboard_metrics;
create or replace view public.company_dashboard_metrics as
select
    p_company_id::uuid as company_id,
    sum(ol.price * ol.quantity) as total_sales_value,
    sum((ol.price - coalesce(ol.cost_at_time, 0)) * ol.quantity) as total_profit,
    avg(o.total_amount) as average_order_value,
    count(distinct o.id) as total_orders,
    count(distinct o.customer_id) as total_customers,
    sum(pv.cost * pv.inventory_quantity) as total_inventory_value,
    count(distinct p.id) as total_products,
    count(distinct pv.id) as total_variants
from orders o
join order_line_items ol on o.id = ol.order_id
join product_variants pv on ol.variant_id = pv.id
join products p on pv.product_id = p.id
where o.company_id = p_company_id;

-- =================================================================
-- RLS (ROW-LEVEL SECURITY) POLICIES
-- =================================================================

-- Enable RLS for all relevant tables
alter table public.companies enable row level security;
alter table public.users enable row level security;
alter table public.company_settings enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.suppliers enable row level security;
alter table public.orders enable row level security;
alter table public.order_line_items enable row level security;
alter table public.customers enable row level security;
alter table public.inventory_ledger enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.integrations enable row level security;
alter table public.webhook_events enable row level security;
alter table public.audit_log enable row level security;
alter table public.export_jobs enable row level security;
alter table public.channel_fees enable row level security;
alter table public.user_feedback enable row level security;

-- Disable RLS for auth-managed tables, as auth policies handle them.
-- Use "disable" instead of "bypass"
alter table auth.users disable row level security;

-- POLICIES
drop policy if exists "Allow full access based on company_id" on public.companies;
create policy "Allow full access based on company_id" on public.companies for all using (id = get_current_company_id()) with check (id = get_current_company_id());

drop policy if exists "Allow read access for company members" on public.users;
create policy "Allow read access for company members" on public.users for select using (company_id = get_current_company_id());

drop policy if exists "Allow full access based on company_id" on public.company_settings;
create policy "Allow full access based on company_id" on public.company_settings for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

drop policy if exists "Allow full access based on company_id" on public.products;
create policy "Allow full access based on company_id" on public.products for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

drop policy if exists "Allow full access based on company_id" on public.product_variants;
create policy "Allow full access based on company_id" on public.product_variants for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

drop policy if exists "Allow full access based on company_id" on public.suppliers;
create policy "Allow full access based on company_id" on public.suppliers for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

drop policy if exists "Allow full access based on company_id" on public.orders;
create policy "Allow full access based on company_id" on public.orders for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

drop policy if exists "Allow full access based on company_id" on public.order_line_items;
create policy "Allow full access based on company_id" on public.order_line_items for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

drop policy if exists "Allow full access based on company_id" on public.customers;
create policy "Allow full access based on company_id" on public.customers for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

drop policy if exists "Allow full access based on company_id" on public.inventory_ledger;
create policy "Allow full access based on company_id" on public.inventory_ledger for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

drop policy if exists "Allow access to own conversations" on public.conversations;
create policy "Allow access to own conversations" on public.conversations for all using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "Allow access to company messages" on public.messages;
create policy "Allow access to company messages" on public.messages for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

drop policy if exists "Allow admin access to integrations" on public.integrations;
create policy "Allow admin access to integrations" on public.integrations for all using (company_id = get_current_company_id() and get_current_user_role() in ('admin', 'owner')) with check (company_id = get_current_company_id());

drop policy if exists "Allow read access to all company members for integrations" on public.integrations;
create policy "Allow read access to all company members for integrations" on public.integrations for select using (company_id = get_current_company_id());

drop policy if exists "Allow access based on company_id" on public.webhook_events;
create policy "Allow access based on company_id" on public.webhook_events for all using (exists (select 1 from public.integrations i where i.id = webhook_events.integration_id and i.company_id = get_current_company_id())) with check (exists (select 1 from public.integrations i where i.id = webhook_events.integration_id and i.company_id = get_current_company_id()));

drop policy if exists "Allow read access to company members" on public.audit_log;
create policy "Allow read access to company members" on public.audit_log for select using (company_id = get_current_company_id());

drop policy if exists "Allow access to own export jobs" on public.export_jobs;
create policy "Allow access to own export jobs" on public.export_jobs for all using (requested_by_user_id = auth.uid()) with check (requested_by_user_id = auth.uid());

drop policy if exists "Allow full access based on company_id" on public.channel_fees;
create policy "Allow full access based on company_id" on public.channel_fees for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

drop policy if exists "Allow access to own company feedback" on public.user_feedback;
create policy "Allow access to own company feedback" on public.user_feedback for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());


-- =================================================================
-- INDEXES
-- =================================================================

create index if not exists idx_orders_company_id_created_at on public.orders (company_id, created_at desc);
create index if not exists idx_product_variants_company_id_sku on public.product_variants (company_id, sku);
create index if not exists idx_customers_company_id_email on public.customers (company_id, email);
create index if not exists idx_inventory_ledger_variant_id on public.inventory_ledger (variant_id);
create index if not exists idx_messages_conversation_id on public.messages (conversation_id);

-- Add some missing default uuid generation
alter table public.customer_addresses alter column id set default gen_random_uuid();
alter table public.refunds alter column id set default gen_random_uuid();
alter table public.refund_line_items alter column id set default gen_random_uuid();
alter table public.discounts alter column id set default gen_random_uuid();
alter table public.orders alter column id set default gen_random_uuid();
alter table public.order_line_items alter column id set default gen_random_uuid();
alter table public.product_variants alter column id set default gen_random_uuid();
alter table public.inventory_ledger alter column id set default gen_random_uuid();
alter table public.webhook_events alter column id set default gen_random_uuid();


-- Drop and recreate get_dashboard_metrics with correct parameter casting
drop function if exists public.get_dashboard_metrics(uuid, integer);
create or replace function public.get_dashboard_metrics(
    p_company_id uuid,
    p_days integer
)
returns table (
    "companyId" uuid,
    "totalSalesValue" numeric,
    "totalProfit" numeric,
    "averageOrderValue" numeric,
    "totalOrders" bigint,
    "totalCustomers" bigint,
    "totalInventoryValue" numeric,
    "totalSkus" bigint,
    "lowStockItemsCount" bigint,
    "deadStockItemsCount" bigint,
    "salesTrendData" jsonb,
    "inventoryByCategoryData" jsonb,
    "topCustomersData" jsonb
)
language sql
as $$
with date_series as (
    select generate_series(
        date_trunc('day', now() - (p_days - 1) * interval '1 day'),
        date_trunc('day', now()),
        '1 day'::interval
    )::date as "date"
),
sales_by_day as (
    select
        date_trunc('day', created_at)::date as "date",
        sum(total_amount) as "daily_sales"
    from public.orders
    where
        company_id = p_company_id
        and created_at >= now() - (p_days || ' days')::interval
    group by 1
),
trend_data as (
    select
        ds.date,
        coalesce(sbd.daily_sales, 0) as "Sales"
    from date_series ds
    left join sales_by_day sbd on ds.date = sbd.date
    order by ds.date
),
category_data as (
    select
        coalesce(p.product_type, 'Uncategorized') as name,
        sum(pv.inventory_quantity * pv.cost) as value
    from public.product_variants pv
    join public.products p on pv.product_id = p.id
    where pv.company_id = p_company_id and pv.inventory_quantity > 0 and pv.cost > 0
    group by 1
    order by 2 desc
    limit 5
),
top_customers as (
    select
       coalesce(c.customer_name, 'Guest') as name,
       sum(o.total_amount) as value
    from public.orders o
    left join public.customers c on o.customer_id = c.id
    where o.company_id = p_company_id and o.created_at >= now() - (p_days || ' days')::interval
    group by 1
    order by 2 desc
    limit 5
),
main_metrics as (
    select
        p_company_id::uuid as company_id,
        sum(o.total_amount) as total_sales_value,
        sum(ol.quantity * (ol.price - ol.cost_at_time)) as total_profit,
        avg(o.total_amount) as average_order_value,
        count(distinct o.id) as total_orders
    from public.orders o
    join public.order_line_items ol on o.id = ol.order_id
    where o.company_id = p_company_id and o.created_at >= now() - (p_days || ' days')::interval
),
inventory_metrics as (
    select
        sum(pv.inventory_quantity * pv.cost) as total_inventory_value,
        count(*) as total_skus
    from public.product_variants pv
    where pv.company_id = p_company_id
),
alert_counts as (
    select
        count(*) filter (where a.type = 'low_stock') as low_stock_items_count,
        count(*) filter (where a.type = 'dead_stock') as dead_stock_items_count
    from public.get_alerts(p_company_id) a
)
select
    mm.company_id,
    coalesce(mm.total_sales_value, 0) / 100.0,
    coalesce(mm.total_profit, 0) / 100.0,
    coalesce(mm.average_order_value, 0) / 100.0,
    coalesce(mm.total_orders, 0),
    (select count(distinct customer_id) from public.orders where company_id = p_company_id and created_at >= now() - (p_days || ' days')::interval) as total_customers,
    coalesce(im.total_inventory_value, 0) / 100.0,
    coalesce(im.total_skus, 0),
    coalesce(ac.low_stock_items_count, 0),
    coalesce(ac.dead_stock_items_count, 0),
    (select jsonb_agg(t) from trend_data t) as sales_trend_data,
    (select jsonb_agg(c) from category_data c) as inventory_by_category_data,
    (select jsonb_agg(tc) from top_customers tc) as top_customers_data
from
    main_metrics mm,
    inventory_metrics im,
    alert_counts ac;
$$;
