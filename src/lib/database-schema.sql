--
-- PostgreSQL database schema for InvoChat
--
-- This script is designed to be idempotent, meaning it can be run multiple times
-- on the same database without causing errors. It handles creating, updating,
-- and securing all necessary database objects for the application.
--

-- Enable the pgcrypto extension for gen_random_uuid()
create extension if not exists pgcrypto with schema public;
-- Enable the vault extension for secrets management
create extension if not exists "supabase_vault" with schema "vault";
-- Enable the uuid-ossp extension for uuid_generate_v4() if needed
create extension if not exists "uuid-ossp" with schema extensions;


--------------------------------------------------------------------------------
-- Helper Functions
--------------------------------------------------------------------------------

-- Function to get the company_id from the current user's session claims
create or replace function public.get_current_company_id()
returns uuid as $$
begin
  return (auth.jwt()->>'app_metadata')::jsonb->>'company_id';
end;
$$ language plpgsql stable security invoker;

-- Function to get the role from the current user's session claims
create or replace function public.get_current_user_role()
returns text as $$
begin
  return (auth.jwt()->>'app_metadata')::jsonb->>'role';
end;
$$ language plpgsql stable security invoker;


--------------------------------------------------------------------------------
-- Table Definitions
--------------------------------------------------------------------------------

-- Stores company information
create table if not exists public.companies (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    created_at timestamptz not null default now()
);

-- Stores user profiles, linking them to companies and auth.users
create table if not exists public.users (
    id uuid primary key references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    email text,
    role text default 'Member', -- 'Owner', 'Admin', 'Member'
    deleted_at timestamptz,
    created_at timestamptz default now()
);

-- Stores company-specific settings and business rules
create table if not exists public.company_settings (
    company_id uuid primary key references public.companies(id) on delete cascade,
    dead_stock_days integer not null default 90,
    fast_moving_days integer not null default 30,
    predictive_stock_days integer not null default 7,
    overstock_multiplier integer not null default 3,
    high_value_threshold integer not null default 100000, -- in cents
    currency text default 'USD',
    timezone text default 'UTC',
    tax_rate numeric(5,4) default 0.0,
    promo_sales_lift_multiplier real not null default 2.5,
    custom_rules jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);

-- Stores core product information
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
    inventory_quantity integer not null default 0,
    external_variant_id text,
    deleted_at timestamptz,
    created_at timestamptz default now(),
    updated_at timestamptz,
    unique(company_id, sku),
    unique(company_id, external_variant_id)
);

-- Stores supplier information
create table if not exists public.suppliers (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    name text not null,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    deleted_at timestamptz,
    created_at timestamptz not null default now()
);

-- Stores customer information
create table if not exists public.customers (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    customer_name text,
    email text,
    total_orders integer default 0,
    total_spent integer default 0, -- in cents
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz default now(),
    unique(company_id, email)
);

-- Stores order headers
create table if not exists public.orders (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    customer_id uuid references public.customers(id) on delete set null,
    order_number text not null,
    external_order_id text,
    financial_status text,
    fulfillment_status text,
    currency text,
    subtotal integer not null default 0, -- in cents
    total_tax integer default 0,
    total_shipping integer default 0,
    total_discounts integer default 0,
    total_amount integer not null,
    source_platform text,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);

-- Stores order line items
create table if not exists public.order_line_items (
    id uuid primary key default gen_random_uuid(),
    order_id uuid not null references public.orders(id) on delete cascade,
    variant_id uuid references public.product_variants(id) on delete set null,
    company_id uuid not null references public.companies(id) on delete cascade,
    product_name text,
    variant_title text,
    sku text,
    quantity integer not null,
    price integer not null, -- in cents
    total_discount integer default 0,
    tax_amount integer default 0,
    cost_at_time integer, -- in cents
    external_line_item_id text
);

-- Audit trail for all inventory movements
create table if not exists public.inventory_ledger (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    change_type text not null, -- e.g., 'sale', 'restock', 'adjustment'
    quantity_change integer not null,
    new_quantity integer not null,
    related_id uuid, -- e.g., order_id, purchase_order_id
    notes text,
    created_at timestamptz not null default now()
);

-- Conversation history for the AI chat
create table if not exists public.conversations (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    title text not null,
    is_starred boolean default false,
    created_at timestamptz default now(),
    last_accessed_at timestamptz default now()
);

-- Individual messages within a conversation
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

-- E-commerce platform integrations
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
    updated_at timestamptz
);

-- Stores fees for sales channels to calculate net margin
create table if not exists public.channel_fees (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    channel_name text not null,
    percentage_fee numeric(5, 4) not null,
    fixed_fee integer not null, -- in cents
    created_at timestamptz default now(),
    updated_at timestamptz,
    unique(company_id, channel_name)
);

-- Stores user feedback on AI responses
create table if not exists public.user_feedback (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    subject_id text not null,
    subject_type text not null, -- e.g., 'anomaly_explanation', 'chat_response'
    feedback text not null, -- 'helpful' or 'unhelpful'
    created_at timestamptz default now()
);

-- Logs all webhook events to prevent replay attacks
create table if not exists public.webhook_events (
    id uuid primary key default gen_random_uuid(),
    integration_id uuid not null references public.integrations(id) on delete cascade,
    webhook_id text not null,
    processed_at timestamptz default now(),
    created_at timestamptz default now(),
    unique(integration_id, webhook_id)
);

-- Logs background data export jobs
create table if not exists public.export_jobs (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    requested_by_user_id uuid not null references auth.users(id) on delete cascade,
    status text not null default 'pending',
    download_url text,
    expires_at timestamptz,
    created_at timestamptz not null default now()
);

-- Audit Log for significant actions
create table if not exists public.audit_log (
    id bigserial primary key,
    company_id uuid references public.companies(id) on delete cascade,
    user_id uuid references auth.users(id) on delete set null,
    action text not null,
    details jsonb,
    created_at timestamptz default now()
);

-- Login history for security auditing
create table if not exists public.login_history (
  id bigserial primary key,
  user_id uuid references auth.users(id) on delete cascade,
  company_id uuid references public.companies(id) on delete cascade,
  ip_address inet,
  user_agent text,
  login_at timestamptz default now()
);


--------------------------------------------------------------------------------
-- Triggers and Functions
--------------------------------------------------------------------------------

-- Trigger to create a company and associate the user on new user signup
create or replace function public.handle_new_user()
returns trigger as $$
declare
  v_company_id uuid;
begin
  -- Create a new company for the user
  insert into public.companies (name)
  values (new.raw_user_meta_data->>'company_name')
  returning id into v_company_id;

  -- Insert into our public users table
  insert into public.users (id, company_id, email, role)
  values (new.id, v_company_id, new.email, 'Owner');
  
  -- Update the user's app_metadata with the new company_id and role
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', v_company_id, 'role', 'Owner')
  where id = new.id;
  
  return new;
end;
$$ language plpgsql security definer;

-- Drop trigger if it exists before creating it
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();


-- Trigger to update inventory quantity when a new ledger entry is added
create or replace function public.update_variant_quantity_from_ledger()
returns trigger as $$
begin
    update public.product_variants
    set inventory_quantity = new.new_quantity,
        updated_at = now()
    where id = new.variant_id;
    return new;
end;
$$ language plpgsql;

-- Drop trigger if it exists before creating it
drop trigger if exists on_inventory_ledger_insert on public.inventory_ledger;
create trigger on_inventory_ledger_insert
    after insert on public.inventory_ledger
    for each row
    execute function public.update_variant_quantity_from_ledger();


-- The main function to record an order from an external platform
-- This version handles both Shopify and WooCommerce payloads
-- DROP an old version of the function if it exists with a different signature.
DROP FUNCTION IF EXISTS public.record_order_from_platform(uuid, jsonb);
-- DROP the current version of the function to allow for signature changes.
DROP FUNCTION IF EXISTS public.record_order_from_platform(uuid, text, jsonb);

CREATE OR REPLACE FUNCTION public.record_order_from_platform(
    p_company_id uuid,
    p_platform text,
    p_order_payload jsonb
)
RETURNS uuid AS $$
DECLARE
    v_customer_id uuid;
    v_order_id uuid;
    v_variant_id uuid;
    line_item jsonb;
    v_customer_name text;
    v_customer_email text;
    v_sku text;
    v_quantity integer;
    v_current_stock integer;
BEGIN
    -- 1. Extract and find/create customer
    IF p_platform = 'shopify' THEN
        v_customer_email := p_order_payload->'customer'->>'email';
        v_customer_name := p_order_payload->'customer'->>'first_name' || ' ' || p_order_payload->'customer'->>'last_name';
    ELSIF p_platform = 'woocommerce' THEN
        v_customer_email := p_order_payload->'billing'->>'email';
        v_customer_name := p_order_payload->'billing'->>'first_name' || ' ' || p_order_payload->'billing'->>'last_name';
    END IF;

    IF v_customer_email IS NOT NULL THEN
        SELECT id INTO v_customer_id FROM public.customers
        WHERE company_id = p_company_id AND email = v_customer_email;

        IF v_customer_id IS NULL THEN
            INSERT INTO public.customers (company_id, customer_name, email, total_orders, total_spent, first_order_date)
            VALUES (p_company_id, v_customer_name, v_customer_email, 0, 0, (p_order_payload->>'created_at')::date)
            RETURNING id INTO v_customer_id;
        END IF;
    END IF;

    -- 2. Insert the order
    INSERT INTO public.orders (company_id, customer_id, order_number, external_order_id, financial_status, fulfillment_status, currency, subtotal, total_tax, total_shipping, total_discounts, total_amount, source_platform, created_at)
    VALUES (
        p_company_id,
        v_customer_id,
        p_order_payload->>'order_number',
        p_order_payload->>'id',
        p_order_payload->>'financial_status',
        p_order_payload->>'fulfillment_status',
        p_order_payload->>'currency',
        ( (p_order_payload->>'subtotal_price')::numeric * 100 )::integer,
        ( (p_order_payload->>'total_tax')::numeric * 100 )::integer,
        ( (p_order_payload->>'total_shipping_price_set'->'shop_money'->>'amount')::numeric * 100 )::integer,
        ( (p_order_payload->>'total_discounts')::numeric * 100 )::integer,
        ( (p_order_payload->>'total_price')::numeric * 100 )::integer,
        p_platform,
        (p_order_payload->>'created_at')::timestamptz
    ) RETURNING id INTO v_order_id;
    
    -- 3. Loop through line items, insert them, and update inventory
    FOR line_item IN SELECT * FROM jsonb_array_elements(p_order_payload->'line_items')
    LOOP
        v_sku := line_item->>'sku';
        v_quantity := (line_item->>'quantity')::integer;

        -- Find the corresponding variant
        SELECT id INTO v_variant_id FROM public.product_variants
        WHERE company_id = p_company_id AND sku = v_sku;

        -- Insert line item
        INSERT INTO public.order_line_items (order_id, company_id, variant_id, product_name, sku, quantity, price)
        VALUES (
            v_order_id,
            p_company_id,
            v_variant_id,
            line_item->>'title',
            v_sku,
            v_quantity,
            ( (line_item->>'price')::numeric * 100 )::integer
        );

        -- Update inventory ledger if the variant exists
        IF v_variant_id IS NOT NULL THEN
            -- Get current stock before updating
            SELECT inventory_quantity INTO v_current_stock FROM public.product_variants
            WHERE id = v_variant_id;

            INSERT INTO public.inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id)
            VALUES (p_company_id, v_variant_id, 'sale', -v_quantity, v_current_stock - v_quantity, v_order_id);
        END IF;
    END LOOP;

    -- 4. Update customer stats
    UPDATE public.customers
    SET
        total_orders = total_orders + 1,
        total_spent = total_spent + ( (p_order_payload->>'total_price')::numeric * 100 )::integer
    WHERE id = v_customer_id;

    RETURN v_order_id;
END;
$$ LANGUAGE plpgsql;


--------------------------------------------------------------------------------
-- Row-Level Security (RLS)
--------------------------------------------------------------------------------

-- Enable RLS for all tables
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
alter table public.user_feedback enable row level security;
alter table public.webhook_events enable row level security;
alter table public.export_jobs enable row level security;
alter table public.audit_log enable row level security;
alter table public.login_history enable row level security;

-- Policies for 'companies' table
drop policy if exists "Allow full access based on company_id" on public.companies;
create policy "Allow full access based on company_id" on public.companies for all using (id = get_current_company_id()) with check (id = get_current_company_id());

-- Policies for 'users' table
drop policy if exists "Allow users to view other users in their company" on public.users;
create policy "Allow users to view other users in their company" on public.users for select using (company_id = get_current_company_id());
drop policy if exists "Allow admins/owners to manage users in their company" on public.users;
create policy "Allow admins/owners to manage users in their company" on public.users for all using (company_id = get_current_company_id() and get_current_user_role() in ('Admin', 'Owner')) with check (company_id = get_current_company_id());

-- Generic policy for most tables
create or replace function create_rls_policy(table_name text)
returns void as $$
begin
  execute format('
    drop policy if exists "Allow full access based on company_id" on public.%I;
    create policy "Allow full access based on company_id" on public.%I
    for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());',
    table_name, table_name
  );
end;
$$ language plpgsql;

select create_rls_policy('company_settings');
select create_rls_policy('products');
select create_rls_policy('product_variants');
select create_rls_policy('suppliers');
select create_rls_policy('customers');
select create_rls_policy('orders');
select create_rls_policy('order_line_items');
select create_rls_policy('inventory_ledger');
select create_rls_policy('conversations');
select create_rls_policy('messages');
select create_rls_policy('integrations');
select create_rls_policy('channel_fees');
select create_rls_policy('user_feedback');
select create_rls_policy('audit_log');
select create_rls_policy('login_history');

-- Policies for 'export_jobs'
drop policy if exists "Allow users to manage their own company''s export jobs" on public.export_jobs;
create policy "Allow users to manage their own company''s export jobs" on public.export_jobs for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

-- Policies for 'webhook_events' (accessible by service role only, no user RLS needed)
-- We can create a permissive policy but rely on the table being in a non-public schema
-- or having no grants for the `authenticated` role. For now, we'll lock it down.
drop policy if exists "Deny all access to webhook_events" on public.webhook_events;
create policy "Deny all access to webhook_events" on public.webhook_events for all using (false) with check (false);


--------------------------------------------------------------------------------
-- Indexes for Performance
--------------------------------------------------------------------------------

create index if not exists idx_products_company_id on public.products(company_id);
create index if not exists idx_product_variants_company_id_sku on public.product_variants(company_id, sku);
create index if not exists idx_product_variants_product_id on public.product_variants(product_id);
create index if not exists idx_orders_company_id_created_at on public.orders(company_id, created_at desc);
create index if not exists idx_customers_company_id_email on public.customers(company_id, email);
create index if not exists idx_inventory_ledger_variant_id on public.inventory_ledger(variant_id);
create index if not exists idx_inventory_ledger_company_id_created_at on public.inventory_ledger(company_id, created_at desc);
create index if not exists idx_conversations_user_id on public.conversations(user_id);
create index if not exists idx_messages_conversation_id on public.messages(conversation_id);
create index if not exists idx_integrations_company_id on public.integrations(company_id);


--------------------------------------------------------------------------------
-- Grant Permissions
--------------------------------------------------------------------------------

-- Grant usage on the public schema to authenticated users
grant usage on schema public to authenticated;

-- Grant all privileges on all tables in the public schema to authenticated users
grant all on all tables in schema public to authenticated;
grant all on all functions in schema public to authenticated;
grant all on all sequences in schema public to authenticated;

-- Allow service_role to bypass RLS (crucial for triggers and admin tasks)
alter table public.companies bypass row level security;
alter table public.users bypass row level security;
alter table public.company_settings bypass row level security;
alter table public.products bypass row level security;
alter table public.product_variants bypass row level security;
alter table public.suppliers bypass row level security;
alter table public.customers bypass row level security;
alter table public.orders bypass row level security;
alter table public.order_line_items bypass row level security;
alter table public.inventory_ledger bypass row level security;
alter table public.conversations bypass row level security;
alter table public.messages bypass row level security;
alter table public.integrations bypass row level security;
alter table public.channel_fees bypass row level security;
alter table public.user_feedback bypass row level security;
alter table public.webhook_events bypass row level security;
alter table public.export_jobs bypass row level security;
alter table public.audit_log bypass row level security;
alter table public.login_history bypass row level security;


-- Grant access to Supabase Vault for service roles to manage secrets
grant usage on schema vault to service_role;
grant all on all tables in schema vault to service_role;


--------------------------------------------------------------------------------
-- Performance Views (Materialized Views)
--------------------------------------------------------------------------------

-- Materialized view for fast dashboard metrics
create materialized view if not exists public.company_dashboard_metrics as
select
  c.id as company_id,
  coalesce(sum(oli.price * oli.quantity), 0)::integer as total_revenue,
  coalesce(sum((oli.price - coalesce(oli.cost_at_time, 0)) * oli.quantity), 0)::integer as total_profit,
  count(distinct o.id) as total_orders
from companies c
left join orders o on c.id = o.company_id
left join order_line_items oli on o.id = oli.order_id
group by c.id;

create unique index if not exists idx_company_dashboard_metrics_company_id on public.company_dashboard_metrics (company_id);

-- Function to refresh the materialized views
create or replace function public.refresh_materialized_views(p_company_id uuid)
returns void as $$
begin
  refresh materialized view concurrently public.company_dashboard_metrics;
end;
$$ language plpgsql security definer;
