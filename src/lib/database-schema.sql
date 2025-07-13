
-- Enable UUID generation
create extension if not exists "uuid-ossp" with schema "extensions";

-- #################################################################
-- ### 1. Tables
-- #################################################################

-- ## Companies & Users
-- Core tables for multi-tenancy.

create table if not exists public.companies (
    id uuid not null primary key default uuid_generate_v4(),
    name text not null,
    created_at timestamptz not null default now()
);

create table if not exists public.users (
    id uuid references auth.users not null primary key,
    company_id uuid not null references public.companies on delete cascade,
    email text,
    role text default 'Member',
    deleted_at timestamptz,
    created_at timestamptz default now()
);

create table if not exists public.company_settings (
    company_id uuid not null primary key references public.companies on delete cascade,
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
    high_value_threshold integer not null default 100000
);

-- ## Product Catalog
-- Tables for managing products and their variants.

create table if not exists public.products (
    id uuid not null primary key default uuid_generate_v4(),
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
    deleted_at timestamptz
);
create unique index if not exists products_company_external_id_idx on public.products (company_id, external_product_id);

create table if not exists public.product_variants (
    id uuid not null primary key default gen_random_uuid(),
    product_id uuid not null references public.products on delete cascade,
    company_id uuid not null references public.companies on delete cascade,
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
    updated_at timestamptz
);
create unique index if not exists variants_company_sku_idx on public.product_variants (company_id, sku);
create unique index if not exists variants_company_external_id_idx on public.product_variants (company_id, external_variant_id);

-- ## Inventory Management
-- Ledger for all stock movements.

create table if not exists public.inventory_ledger (
    id uuid not null primary key default gen_random_uuid(),
    company_id uuid not null references public.companies on delete cascade,
    variant_id uuid not null references public.product_variants on delete cascade,
    change_type text not null, -- e.g., 'sale', 'restock', 'return', 'adjustment'
    quantity_change integer not null,
    new_quantity integer not null,
    related_id uuid, -- e.g., order_id, purchase_order_id
    notes text,
    created_at timestamptz not null default now()
);

-- ## Sales & Customers
-- Tables for orders, line items, and customer data.

create table if not exists public.customers (
    id uuid not null primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies on delete cascade,
    customer_name text,
    email text,
    total_orders integer default 0,
    total_spent integer default 0, -- in cents
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz default now()
);
create unique index if not exists customers_company_email_idx on public.customers (company_id, email);

create table if not exists public.orders (
    id uuid not null primary key default gen_random_uuid(),
    company_id uuid not null references public.companies on delete cascade,
    order_number text not null,
    external_order_id text,
    customer_id uuid references public.customers on delete set null,
    financial_status text default 'pending',
    fulfillment_status text default 'unfulfilled',
    currency text default 'USD',
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
    updated_at timestamptz
);
create unique index if not exists orders_company_external_id_idx on public.orders (company_id, external_order_id);

create table if not exists public.order_line_items (
    id uuid not null primary key default gen_random_uuid(),
    order_id uuid not null references public.orders on delete cascade,
    company_id uuid not null references public.companies on delete cascade,
    variant_id uuid references public.product_variants on delete set null,
    product_name text,
    variant_title text,
    sku text,
    quantity integer not null,
    price integer not null, -- in cents
    total_discount integer default 0,
    tax_amount integer default 0,
    cost_at_time integer,
    external_line_item_id text
);

-- ## Suppliers
-- Table for managing supplier/vendor information.

create table if not exists public.suppliers (
    id uuid not null primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies on delete cascade,
    name text not null,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz not null default now(),
    deleted_at timestamptz
);

-- ## AI & Chat
-- Tables for storing conversations and messages.

create table if not exists public.conversations (
    id uuid not null primary key default uuid_generate_v4(),
    user_id uuid not null references auth.users on delete cascade,
    company_id uuid not null references public.companies on delete cascade,
    title text not null,
    created_at timestamptz default now(),
    last_accessed_at timestamptz default now(),
    is_starred boolean default false
);

create table if not exists public.messages (
    id uuid not null primary key default uuid_generate_v4(),
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

-- ## Integrations & System
-- Tables for managing external integrations and system logs.

create table if not exists public.integrations (
    id uuid not null primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies on delete cascade,
    platform text not null,
    shop_domain text,
    shop_name text,
    is_active boolean default false,
    last_sync_at timestamptz,
    sync_status text,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);
create unique index if not exists integrations_company_platform_idx on public.integrations (company_id, platform);

create table if not exists public.webhook_events (
    id uuid not null primary key default gen_random_uuid(),
    integration_id uuid not null references public.integrations on delete cascade,
    webhook_id text not null,
    processed_at timestamptz default now(),
    created_at timestamptz default now()
);
create unique index if not exists webhook_events_integration_webhook_id_idx on public.webhook_events (integration_id, webhook_id);

create table if not exists public.audit_log (
    id bigserial primary key,
    company_id uuid references public.companies on delete set null,
    user_id uuid references auth.users on delete set null,
    action text not null,
    details jsonb,
    created_at timestamptz default now()
);

create table if not exists public.channel_fees (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies on delete cascade,
    channel_name text not null,
    percentage_fee numeric not null,
    fixed_fee integer not null, -- in cents
    created_at timestamptz default now(),
    updated_at timestamptz,
    unique(company_id, channel_name)
);

create table if not exists public.export_jobs (
    id uuid not null primary key default gen_random_uuid(),
    company_id uuid not null references public.companies on delete cascade,
    requested_by_user_id uuid not null references auth.users on delete set null,
    status text not null default 'pending',
    download_url text,
    expires_at timestamptz,
    created_at timestamptz not null default now()
);

create table if not exists public.user_feedback (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users on delete cascade,
    company_id uuid not null references public.companies on delete cascade,
    subject_id text not null,
    subject_type text not null, -- e.g., 'anomaly_explanation', 'ai_chat_response'
    feedback text not null, -- 'helpful' or 'unhelpful'
    created_at timestamptz not null default now()
);

-- #################################################################
-- ### 2. Indexes
-- #################################################################
-- Create indexes for performance on frequently queried columns.

create index if not exists products_company_id_idx on public.products (company_id);
create index if not exists product_variants_product_id_idx on public.product_variants (product_id);
create index if not exists product_variants_company_id_sku_idx on public.product_variants (company_id, sku);
create index if not exists orders_company_id_created_at_idx on public.orders (company_id, created_at desc);
create index if not exists order_line_items_order_id_idx on public.order_line_items (order_id);
create index if not exists order_line_items_variant_id_idx on public.order_line_items (variant_id);
create index if not exists customers_company_id_idx on public.customers (company_id);
create index if not exists suppliers_company_id_idx on public.suppliers (company_id);
create index if not exists inventory_ledger_variant_id_created_at_idx on public.inventory_ledger (variant_id, created_at desc);
create index if not exists messages_conversation_id_created_at_idx on public.messages (conversation_id, created_at desc);
create index if not exists integrations_company_id_idx on public.integrations (company_id);

-- #################################################################
-- ### 3. Helper Functions
-- #################################################################
-- Helper functions for RLS policies and triggers.

create or replace function public.get_current_company_id()
returns uuid
language sql stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid;
$$;

create or replace function public.get_current_user_role()
returns text
language sql stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'role', '');
$$;

-- #################################################################
-- ### 4. Core Business Logic Functions
-- #################################################################

-- ## User & Company Setup
-- Function to create a company and link a new user to it.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
as $$
declare
  company_id uuid;
begin
  -- Create a new company for the new user
  insert into public.companies (name)
  values (new.raw_app_meta_data->>'company_name')
  returning id into company_id;

  -- Link the new user to the new company
  insert into public.users (id, company_id, email, role)
  values (new.id, company_id, new.email, 'Owner');
  
  -- Update the user's app_metadata with the new company_id
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id, 'role', 'Owner')
  where id = new.id;
  
  return new;
end;
$$;

-- ## Inventory & Order Processing

-- Trigger function to update product_variants.inventory_quantity from the ledger
create or replace function public.update_variant_quantity_from_ledger()
returns trigger
language plpgsql
security definer
as $$
begin
  update public.product_variants
  set inventory_quantity = new.new_quantity,
      updated_at = now()
  where id = new.variant_id;
  return new;
end;
$$;

-- Function to handle an order from an external platform
drop function if exists public.record_order_from_platform(uuid, text, jsonb);
drop function if exists public.record_order_from_platform(p_company_id uuid, p_platform text, p_order_payload jsonb);

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
    v_customer_name text;
    v_customer_email text;
    line_item jsonb;
    v_sku text;
    v_cost_at_time integer;
begin
    -- Extract and find/create customer
    v_customer_name := coalesce(
        p_order_payload->'customer'->>'first_name' || ' ' || p_order_payload->'customer'->>'last_name',
        p_order_payload->'billing'->>'first_name' || ' ' || p_order_payload->'billing'->>'last_name',
        'Guest'
    );
    v_customer_email := coalesce(p_order_payload->'customer'->>'email', p_order_payload->'billing'->>'email');

    if v_customer_email is not null then
        select id into v_customer_id from public.customers where company_id = p_company_id and email = v_customer_email;
        if v_customer_id is null then
            insert into public.customers (company_id, customer_name, email)
            values (p_company_id, v_customer_name, v_customer_email)
            returning id into v_customer_id;
        end if;
    else
      v_customer_id := null;
    end if;

    -- Create the order
    insert into public.orders (
        company_id, order_number, external_order_id, customer_id, financial_status, fulfillment_status,
        total_amount, subtotal, total_tax, total_shipping, total_discounts, source_platform, created_at
    ) values (
        p_company_id,
        p_order_payload->>'id',
        p_order_payload->>'id',
        v_customer_id,
        p_order_payload->>'financial_status',
        coalesce(p_order_payload->>'fulfillment_status', 'unfulfilled'),
        (p_order_payload->>'total_price')::numeric * 100,
        (p_order_payload->>'subtotal_price')::numeric * 100,
        (p_order_payload->>'total_tax')::numeric * 100,
        (p_order_payload->>'total_shipping_price_set'->'shop_money'->>'amount')::numeric * 100,
        (p_order_payload->>'total_discounts')::numeric * 100,
        p_platform,
        (p_order_payload->>'created_at')::timestamptz
    )
    returning id into v_order_id;
    
    -- Process line items
    for line_item in select * from jsonb_array_elements(p_order_payload->'line_items')
    loop
        v_sku := coalesce(line_item->>'sku', 'SKU-UNKNOWN-' || (line_item->>'variant_id'));
        
        select id, cost into v_variant_id, v_cost_at_time
        from public.product_variants
        where company_id = p_company_id and sku = v_sku;

        insert into public.order_line_items (
            order_id, company_id, variant_id, product_name, variant_title, sku, quantity, price, total_discount, tax_amount, cost_at_time, external_line_item_id
        ) values (
            v_order_id,
            p_company_id,
            v_variant_id,
            line_item->>'title',
            line_item->>'variant_title',
            v_sku,
            (line_item->>'quantity')::integer,
            (line_item->>'price')::numeric * 100,
            (line_item->>'total_discount')::numeric * 100,
            (line_item->'tax_lines'->0->>'price')::numeric * 100,
            v_cost_at_time,
            line_item->>'id'
        );
        
        -- Update inventory ledger if variant exists
        if v_variant_id is not null then
            insert into public.inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id)
            select
                p_company_id,
                v_variant_id,
                'sale',
                -(line_item->>'quantity')::integer,
                pv.inventory_quantity - (line_item->>'quantity')::integer,
                v_order_id
            from public.product_variants pv
            where pv.id = v_variant_id;
        end if;
    end loop;
end;
$$;


-- #################################################################
-- ### 5. Triggers
-- #################################################################

-- Trigger to handle new user sign-ups
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Trigger to update inventory quantity when ledger changes
drop trigger if exists on_inventory_ledger_insert on public.inventory_ledger;
create trigger on_inventory_ledger_insert
  after insert on public.inventory_ledger
  for each row execute procedure public.update_variant_quantity_from_ledger();


-- #################################################################
-- ### 6. Row Level Security (RLS)
-- #################################################################

-- Enable RLS on all tables
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
alter table public.webhook_events enable row level security;
alter table public.audit_log enable row level security;
alter table public.channel_fees enable row level security;
alter table public.export_jobs enable row level security;
alter table public.user_feedback enable row level security;

-- Disable RLS on tables that don't need it (only for service_role access)
alter table public.companies disable row level security;
alter table public.company_settings disable row level security;
alter table public.users disable row level security;
alter table public.products disable row level security;
alter table public.product_variants disable row level security;
alter table public.orders disable row level security;
alter table public.order_line_items disable row level security;
alter table public.customers disable row level security;
alter table public.suppliers disable row level security;
alter table public.inventory_ledger disable row level security;
alter table public.integrations disable row level security;
alter table public.conversations disable row level security;
alter table public.messages disable row level security;
alter table public.channel_fees disable row level security;
alter table public.export_jobs disable row level security;
alter table public.user_feedback disable row level security;
alter table public.webhook_events disable row level security;

-- Policies
drop policy if exists "Allow full access based on company_id" on public.companies;
create policy "Allow full access based on company_id" on public.companies for all using (id = get_current_company_id()) with check (id = get_current_company_id());
drop policy if exists "Allow full access based on company_id" on public.users;
create policy "Allow full access based on company_id" on public.users for all using (company_id = get_current_company_id());
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
drop policy if exists "Allow full access based on company_id" on public.conversations;
create policy "Allow full access based on company_id" on public.conversations for all using (company_id = get_current_company_id() and user_id = auth.uid()) with check (company_id = get_current_company_id() and user_id = auth.uid());
drop policy if exists "Allow full access based on company_id" on public.messages;
create policy "Allow full access based on company_id" on public.messages for all using (company_id = get_current_company_id());
drop policy if exists "Allow full access based on company_id" on public.integrations;
create policy "Allow full access based on company_id" on public.integrations for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());
drop policy if exists "Allow full access based on company_id" on public.channel_fees;
create policy "Allow full access based on company_id" on public.channel_fees for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());
drop policy if exists "Allow full access based on company_id" on public.export_jobs;
create policy "Allow full access based on company_id" on public.export_jobs for all using (company_id = get_current_company_id() and requested_by_user_id = auth.uid()) with check (company_id = get_current_company_id() and requested_by_user_id = auth.uid());
drop policy if exists "Allow read access for service roles" on public.webhook_events;
create policy "Allow read access for service roles" on public.webhook_events for select to service_role using (true);
drop policy if exists "Allow insert access for service roles" on public.webhook_events;
create policy "Allow insert access for service roles" on public.webhook_events for insert to service_role with check (true);
drop policy if exists "Allow full access based on company_id" on public.user_feedback;
create policy "Allow full access based on company_id" on public.user_feedback for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());
drop policy if exists "Allow admin full access" on public.audit_log;
create policy "Allow admin full access" on public.audit_log for all to service_role using (get_current_user_role() in ('Admin', 'Owner'));

-- #################################################################
-- ### 7. Performance Views
-- #################################################################

create or replace view public.company_dashboard_metrics as
select
    c.id as company_id,
    coalesce(sum(o.total_amount), 0) as total_revenue,
    coalesce(sum(o.total_amount) - sum(oli.cost_at_time * oli.quantity), 0) as total_profit,
    coalesce(count(distinct o.id), 0) as total_orders
from
    companies c
left join
    orders o on c.id = o.company_id and o.created_at >= now() - interval '30 days'
left join
    order_line_items oli on o.id = oli.order_id
group by
    c.id;

-- Ensure RLS is enabled for the view
alter view public.company_dashboard_metrics owner to postgres;
alter view public.company_dashboard_metrics enable row level security;
drop policy if exists "Allow read access based on company_id" on public.company_dashboard_metrics;
create policy "Allow read access based on company_id" on public.company_dashboard_metrics for select using (company_id = get_current_company_id());
