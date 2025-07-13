
-- =================================================================================================
--                              INVOCHAT DATABASE SCHEMA
--
-- This script is idempotent and can be run multiple times safely.
-- It is designed for a one-time setup in your Supabase project's SQL Editor.
--
-- Features:
-- - Creates all necessary tables for the application.
-- - Establishes foreign key relationships with cascading deletes.
-- - Implements Row-Level Security (RLS) for multi-tenancy.
-- - Defines helper functions and triggers for data consistency.
-- - Sets up performance-enhancing indexes.
--
-- V1.2.0
-- =================================================================================================


-- =================================================================================================
-- 1. EXTENSIONS & HELPER FUNCTIONS
-- =================================================================================================

-- Enable the pgcrypto extension for UUID generation if not already enabled.
create extension if not exists "pgcrypto" with schema "public";
create extension if not exists "uuid-ossp" with schema "public";

-- Function to get the company_id from the currently authenticated user's metadata.
-- This is a cornerstone of the multi-tenancy security model.
create or replace function public.get_current_company_id()
returns uuid
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb->'app_metadata'->>'company_id', '')::uuid;
$$;
comment on function public.get_current_company_id() is 'Retrieves the company_id for the currently authenticated user from their JWT claims.';

-- Function to get the role from the currently authenticated user's metadata.
create or replace function public.get_current_user_role()
returns text
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb->'app_metadata'->>'role', '')::text;
$$;
comment on function public.get_current_user_role() is 'Retrieves the role for the currently authenticated user from their JWT claims.';


-- =================================================================================================
-- 2. TABLE DEFINITIONS
-- =================================================================================================

-- Stores company information.
create table if not exists public.companies (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    created_at timestamptz not null default now()
);
comment on table public.companies is 'Stores basic information about each company (tenant).';

-- Stores user-to-company mappings and roles.
create table if not exists public.users (
    id uuid primary key references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    email text,
    role text default 'Member' check (role in ('Owner', 'Admin', 'Member')),
    deleted_at timestamptz,
    created_at timestamptz default now()
);
comment on table public.users is 'Maps authenticated users to companies and assigns roles.';
create index if not exists idx_users_company_id on public.users(company_id);

-- Stores company-specific settings.
create table if not exists public.company_settings (
    company_id uuid primary key references public.companies(id) on delete cascade,
    dead_stock_days integer not null default 90,
    fast_moving_days integer not null default 30,
    predictive_stock_days integer not null default 7,
    currency text default 'USD',
    timezone text default 'UTC',
    overstock_multiplier integer not null default 3,
    high_value_threshold integer not null default 100000, -- in cents
    created_at timestamptz not null default now(),
    updated_at timestamptz
);
comment on table public.company_settings is 'Configuration settings for each company.';

-- Stores product information.
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
comment on table public.products is 'Core product information, synced from external platforms.';
create index if not exists idx_products_company_id on public.products(company_id);
create index if not exists idx_products_external_id on public.products(external_product_id);

-- Stores product variant details.
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
    price integer, -- in cents
    compare_at_price integer, -- in cents
    cost integer, -- in cents
    inventory_quantity integer not null default 0,
    external_variant_id text,
    deleted_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz,
    unique(company_id, sku),
    unique(company_id, external_variant_id)
);
comment on table public.product_variants is 'Specific variants of a product, including SKU, price, and stock levels.';
create index if not exists idx_variants_product_id on public.product_variants(product_id);
create index if not exists idx_variants_company_id on public.product_variants(company_id);
create index if not exists idx_variants_sku on public.product_variants(sku);

-- Inventory ledger for tracking all stock movements.
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
comment on table public.inventory_ledger is 'Transactional log of all inventory changes for auditing (FIFO/LIFO).';
create index if not exists idx_ledger_variant_id_time on public.inventory_ledger(variant_id, created_at desc);

-- Stores supplier information.
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
comment on table public.suppliers is 'Vendor and supplier information.';
create index if not exists idx_suppliers_company_id on public.suppliers(company_id);

-- Stores customer information.
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
comment on table public.customers is 'Customer data, aggregated from sales.';
create index if not exists idx_customers_company_id on public.customers(company_id);

-- Stores sales orders.
create table if not exists public.orders (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    order_number text not null,
    external_order_id text,
    customer_id uuid references public.customers(id) on delete set null,
    financial_status text,
    fulfillment_status text,
    currency text,
    subtotal integer not null default 0,
    total_tax integer default 0,
    total_shipping integer default 0,
    total_discounts integer default 0,
    total_amount integer not null,
    source_platform text,
    created_at timestamptz not null default now(),
    updated_at timestamptz,
    unique(company_id, external_order_id)
);
comment on table public.orders is 'Sales orders synced from external platforms.';
create index if not exists idx_orders_company_id on public.orders(company_id);
create index if not exists idx_orders_customer_id on public.orders(customer_id);
create index if not exists idx_orders_created_at on public.orders(company_id, created_at desc);

-- Stores line items for each order.
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
comment on table public.order_line_items is 'Individual line items for each sales order.';
create index if not exists idx_order_line_items_order_id on public.order_line_items(order_id);
create index if not exists idx_order_line_items_variant_id on public.order_line_items(variant_id);

-- Stores AI conversation history.
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
create index if not exists idx_conversations_user_id on public.conversations(user_id);

-- Stores individual chat messages.
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
comment on table public.messages is 'Stores individual messages within a chat conversation.';
create index if not exists idx_messages_conversation_id on public.messages(conversation_id);

-- Stores integration connection details.
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
comment on table public.integrations is 'Stores connection details for external platforms like Shopify.';

-- Stores logs of webhook events to prevent replays.
create table if not exists public.webhook_events (
    id uuid primary key default gen_random_uuid(),
    integration_id uuid not null references public.integrations(id) on delete cascade,
    webhook_id text not null,
    processed_at timestamptz default now(),
    created_at timestamptz default now(),
    unique(integration_id, webhook_id)
);
comment on table public.webhook_events is 'Logs received webhook IDs to prevent replay attacks.';

-- Stores logs for user feedback on AI features
create table if not exists public.user_feedback (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    subject_id text not null, -- e.g., anomaly_id, message_id
    subject_type text not null, -- e.g., 'anomaly_explanation', 'ai_chat_response'
    feedback text not null, -- 'helpful' or 'unhelpful'
    created_at timestamptz default now()
);
comment on table public.user_feedback is 'Stores user feedback on AI-generated content.';

-- =================================================================================================
-- 3. DATABASE TRIGGERS & AUTOMATION
-- =================================================================================================

-- Trigger function to create a new company and user mapping on new user signup.
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
  -- Extract company name and email from the user's metadata
  company_name := new.raw_app_meta_data->>'company_name';
  user_email := new.email;

  -- Create a new company
  insert into public.companies (name)
  values (company_name)
  returning id into company_id;

  -- Create a mapping in the public.users table
  insert into public.users (id, company_id, email, role)
  values (new.id, company_id, user_email, 'Owner');
  
  -- Update the user's app_metadata with the new company_id and role
  update auth.users
  set raw_app_meta_data = new.raw_app_meta_data || jsonb_build_object('company_id', company_id, 'role', 'Owner')
  where id = new.id;
  
  return new;
end;
$$;
comment on function public.handle_new_user() is 'On new user signup, creates a company, maps the user to it as Owner, and updates JWT metadata.';

-- Drop the trigger if it exists before creating it
drop trigger if exists on_auth_user_created on auth.users;

-- Create the trigger to call the function after a new user is created in auth.users
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


-- Trigger function to update the inventory quantity on a product variant from the ledger.
create or replace function public.update_variant_quantity_from_ledger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.product_variants
  set inventory_quantity = new.new_quantity
  where id = new.variant_id;
  return new;
end;
$$;
comment on function public.update_variant_quantity_from_ledger() is 'Updates the master quantity on a variant whenever a ledger entry is created.';

-- Drop the trigger if it exists before creating it
drop trigger if exists on_inventory_ledger_insert on public.inventory_ledger;

-- Create the trigger to call the function after a new entry is added to the ledger
create trigger on_inventory_ledger_insert
  after insert on public.inventory_ledger
  for each row execute procedure public.update_variant_quantity_from_ledger();


-- =================================================================================================
-- 4. DATABASE FUNCTIONS (for application use)
-- =================================================================================================

-- Function to record a sale from any platform.
-- This is a transactional function that ensures all related tables are updated correctly.
create or replace function public.record_order_from_platform(
    p_company_id uuid,
    p_platform text,
    p_order_payload jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_customer_id uuid;
    v_order_id uuid;
    v_variant_id uuid;
    v_line_item jsonb;
    v_customer_name text;
    v_customer_email text;
    v_external_product_id text;
    v_product_id uuid;
    v_cost_at_time integer;
begin
    -- Step 1: Extract customer info and find or create the customer record
    if p_platform = 'shopify' then
        v_customer_name := coalesce(
            p_order_payload->'customer'->>'first_name' || ' ' || p_order_payload->'customer'->>'last_name',
            'Guest Customer'
        );
        v_customer_email := p_order_payload->'customer'->>'email';
    elsif p_platform = 'woocommerce' then
        v_customer_name := coalesce(
            p_order_payload->'billing'->>'first_name' || ' ' || p_order_payload->'billing'->>'last_name',
            'Guest Customer'
        );
        v_customer_email := p_order_payload->'billing'->>'email';
    else
        v_customer_name := 'Guest Customer';
        v_customer_email := null;
    end if;

    if v_customer_email is not null then
        select id into v_customer_id from public.customers
        where company_id = p_company_id and email = v_customer_email;

        if v_customer_id is null then
            insert into public.customers (company_id, customer_name, email, total_orders, total_spent, first_order_date)
            values (p_company_id, v_customer_name, v_customer_email, 0, 0, (p_order_payload->>'created_at')::date)
            returning id into v_customer_id;
        end if;
    end if;

    -- Step 2: Insert the main order record
    insert into public.orders (
        company_id, order_number, external_order_id, customer_id,
        financial_status, fulfillment_status, currency, subtotal,
        total_tax, total_shipping, total_discounts, total_amount, source_platform, created_at
    )
    values (
        p_company_id,
        p_order_payload->>'id',
        p_order_payload->>'id',
        v_customer_id,
        p_order_payload->>'financial_status',
        p_order_payload->>'fulfillment_status_name',
        p_order_payload->>'currency',
        (p_order_payload->>'subtotal_price')::numeric * 100,
        (p_order_payload->>'total_tax')::numeric * 100,
        (p_order_payload->>'total_shipping_price_set'->'shop_money'->>'amount')::numeric * 100,
        (p_order_payload->>'total_discounts')::numeric * 100,
        (p_order_payload->>'total_price')::numeric * 100,
        p_platform,
        (p_order_payload->>'created_at')::timestamptz
    )
    returning id into v_order_id;
    
    -- Step 3: Loop through line items, insert them, and update inventory
    for v_line_item in select * from jsonb_array_elements(p_order_payload->'line_items')
    loop
        -- Find the corresponding product variant in our DB
        select id, product_id, cost into v_variant_id, v_product_id, v_cost_at_time from public.product_variants
        where company_id = p_company_id and external_variant_id = v_line_item->>'variant_id';

        -- Insert the line item
        if v_variant_id is not null then
            insert into public.order_line_items (
                order_id, company_id, variant_id, product_name, sku, quantity, price, cost_at_time, external_line_item_id
            )
            values (
                v_order_id,
                p_company_id,
                v_variant_id,
                v_line_item->>'name',
                v_line_item->>'sku',
                (v_line_item->>'quantity')::integer,
                (v_line_item->>'price')::numeric * 100,
                v_cost_at_time,
                v_line_item->>'id'
            );

            -- Update inventory via ledger (which triggers quantity update)
            insert into public.inventory_ledger(company_id, variant_id, change_type, quantity_change, new_quantity, related_id)
            select 
                p_company_id,
                v_variant_id,
                'sale',
                -(v_line_item->>'quantity')::integer,
                pv.inventory_quantity - (v_line_item->>'quantity')::integer,
                v_order_id
            from public.product_variants pv where pv.id = v_variant_id;
            
        end if;
    end loop;
    
    -- Step 4: Update customer aggregate data
    if v_customer_id is not null then
        update public.customers
        set
            total_orders = total_orders + 1,
            total_spent = total_spent + ((p_order_payload->>'total_price')::numeric * 100)
        where id = v_customer_id;
    end if;
    
end;
$$;
comment on function public.record_order_from_platform is 'Standardizes and inserts an order from an external platform, updating customer and inventory data transactionally.';


-- =================================================================================================
-- 5. ROW-LEVEL SECURITY (RLS)
-- =================================================================================================

-- Enable RLS for all relevant tables
alter table public.companies enable row level security;
alter table public.users enable row level security;
alter table public.company_settings enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.inventory_ledger enable row level security;
alter table public.suppliers enable row level security;
alter table public.customers enable row level security;
alter table public.orders enable row level security;
alter table public.order_line_items enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.integrations enable row level security;
alter table public.webhook_events enable row level security;
alter table public.user_feedback enable row level security;


-- POLICIES
-- Users can only see their own company's data.

drop policy if exists "Allow full access based on company_id" on public.companies;
create policy "Allow full access based on company_id" on public.companies for all using (id = get_current_company_id()) with check (id = get_current_company_id());

drop policy if exists "Allow access to own user record" on public.users;
create policy "Allow access to own user record" on public.users for all using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists "Allow access based on company_id" on public.company_settings;
create policy "Allow access based on company_id" on public.company_settings for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

drop policy if exists "Allow access based on company_id" on public.products;
create policy "Allow access based on company_id" on public.products for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

drop policy if exists "Allow access based on company_id" on public.product_variants;
create policy "Allow access based on company_id" on public.product_variants for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

drop policy if exists "Allow access based on company_id" on public.inventory_ledger;
create policy "Allow access based on company_id" on public.inventory_ledger for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

drop policy if exists "Allow access based on company_id" on public.suppliers;
create policy "Allow access based on company_id" on public.suppliers for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

drop policy if exists "Allow access based on company_id" on public.customers;
create policy "Allow access based on company_id" on public.customers for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

drop policy if exists "Allow access based on company_id" on public.orders;
create policy "Allow access based on company_id" on public.orders for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

drop policy if exists "Allow access based on company_id" on public.order_line_items;
create policy "Allow access based on company_id" on public.order_line_items for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

drop policy if exists "Allow access based on user_id" on public.conversations;
create policy "Allow access based on user_id" on public.conversations for all using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "Allow access based on company_id" on public.messages;
create policy "Allow access based on company_id" on public.messages for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

drop policy if exists "Allow access based on company_id" on public.integrations;
create policy "Allow access based on company_id" on public.integrations for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

drop policy if exists "Allow access to admins for related company" on public.webhook_events;
create policy "Allow access to admins for related company" on public.webhook_events for all
using (
    (get_current_user_role() IN ('Admin', 'Owner')) and
    (company_id = get_current_company_id())
)
with check (
    (get_current_user_role() IN ('Admin', 'Owner')) and
    (company_id = get_current_company_id())
);

drop policy if exists "Allow access based on user_id" on public.user_feedback;
create policy "Allow access based on user_id" on public.user_feedback for all using (user_id = auth.uid()) with check (user_id = auth.uid());


-- Make tables accessible to authenticated users
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

-- Grant access to service_role for elevated operations
grant all on all tables in schema public to service_role;
grant all on all sequences in schema public to service_role;
grant all on all functions in schema public to service_role;

-- Anonymous users should have no access
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke all on all functions in schema public from anon;

-- =================================================================================================
-- 6. PERFORMANCE INDEXES
-- =================================================================================================

create index if not exists idx_orders_company_id_created_at on public.orders(company_id, created_at desc);
create index if not exists idx_product_variants_company_sku on public.product_variants(company_id, sku);
create index if not exists idx_customers_company_email on public.customers(company_id, email);
create index if not exists idx_inventory_ledger_company_variant on public.inventory_ledger(company_id, variant_id);

-- =================================================================================================
--                              END OF SCHEMA
-- =================================================================================================
