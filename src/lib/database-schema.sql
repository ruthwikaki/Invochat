
-- ------------------------------------------------------------------------------------------------
-- 1. Helper Functions for Security & Policies
-- ------------------------------------------------------------------------------------------------

-- Helper function to get the current user's ID from the JWT
create or replace function public.get_current_user_id()
returns uuid
language sql stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::json->>'sub', '')::uuid;
$$;
-- The `security definer` clause allows this function to be used in RLS policies
-- where the user might not have direct access to the `auth.users` table.
create or replace function public.get_current_company_id()
returns uuid
language sql stable security definer
as $$
  select nullif(current_setting('request.jwt.claims', true)::json->'app_metadata'->>'company_id', '')::uuid;
$$;


-- ------------------------------------------------------------------------------------------------
-- 2. User & Company Setup on Signup
--
-- This trigger automatically creates a new company for a user upon signup and links them.
-- It also sets the user's role to 'Owner'.
-- ------------------------------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  new_company_id uuid;
  user_company_name text;
begin
  -- Extract company name from metadata, falling back to a default if not present
  user_company_name := new.raw_app_meta_data->>'company_name';
  if user_company_name is null or user_company_name = '' then
    user_company_name := new.email || '''s Company';
  end if;
  
  -- Create a new company for the new user
  insert into public.companies (name)
  values (user_company_name)
  returning id into new_company_id;

  -- Create a corresponding entry in the public.users table
  insert into public.users (id, company_id, email, role)
  values (new.id, new_company_id, new.email, 'Owner');

  -- Update the user's app_metadata with the new company_id and role
  update auth.users
  set raw_app_meta_data = new.raw_app_meta_data || 
    jsonb_build_object('company_id', new_company_id, 'role', 'Owner')
  where id = new.id;
  
  return new;
end;
$$;

-- Drop trigger if it exists to ensure a clean setup
drop trigger if exists on_auth_user_created on auth.users;

-- Create the trigger to fire after a new user is inserted into auth.users
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


-- ------------------------------------------------------------------------------------------------
-- 3. Table Creation
--
-- Note: Foreign key constraints are added after all tables are created to avoid order-of-operation issues.
-- RLS (Row-Level Security) is enabled on all tables that store company-specific data.
-- ------------------------------------------------------------------------------------------------

-- Companies: Stores basic company information.
create table if not exists public.companies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now()
);
alter table public.companies enable row level security;

-- Users: A public mirror of auth.users with company and role information.
create table if not exists public.users (
    id uuid primary key references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    email text,
    role text default 'Member', -- e.g., 'Owner', 'Admin', 'Member'
    deleted_at timestamptz,
    created_at timestamptz default now()
);
alter table public.users enable row level security;

-- Company Settings: Stores configuration specific to each company.
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
alter table public.company_settings enable row level security;

-- Suppliers: Stores vendor information.
create table if not exists public.suppliers (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  email text,
  phone text,
  default_lead_time_days integer,
  notes text,
  created_at timestamptz not null default now()
);
alter table public.suppliers enable row level security;

-- Products: The core product catalog.
create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null,
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
  constraint uq_product_external_id unique (company_id, external_product_id)
);
alter table public.products enable row level security;

-- Product Variants: Specific versions of a product (e.g., by size or color).
create table if not exists public.product_variants (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null,
  company_id uuid not null,
  sku text not null,
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
  updated_at timestamptz default now(),
  constraint uq_variant_sku unique (company_id, sku),
  constraint uq_variant_external_id unique (company_id, external_variant_id)
);
alter table public.product_variants enable row level security;

-- Customers: Stores customer information.
create table if not exists public.customers (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null,
    customer_name text,
    email text,
    total_orders integer default 0,
    total_spent numeric default 0,
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz default now()
);
alter table public.customers enable row level security;


-- Orders: Core table for sales orders.
create table if not exists public.orders (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null,
    order_number text not null,
    external_order_id text,
    customer_id uuid,
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
alter table public.orders enable row level security;

-- Order Line Items: Individual items within an order.
create table if not exists public.order_line_items (
    id uuid primary key default gen_random_uuid(),
    order_id uuid not null,
    company_id uuid not null,
    variant_id uuid,
    product_name text not null,
    variant_title text,
    sku text,
    quantity integer not null,
    price integer not null,
    total_discount integer default 0,
    tax_amount integer default 0,
    cost_at_time integer,
    fulfillment_status text default 'unfulfilled',
    requires_shipping boolean default true,
    external_line_item_id text
);
alter table public.order_line_items enable row level security;


-- Inventory Ledger: An immutable log of all stock movements.
create table if not exists public.inventory_ledger (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null,
  variant_id uuid not null,
  change_type text not null, -- e.g., 'sale', 'restock', 'return', 'adjustment'
  quantity_change integer not null,
  new_quantity integer not null,
  related_id uuid, -- e.g., order_id, purchase_order_id
  notes text,
  created_at timestamptz not null default now()
);
alter table public.inventory_ledger enable row level security;


-- Integrations: Stores credentials and status for connected platforms.
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
alter table public.integrations enable row level security;


-- Conversations: Stores chat history.
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

-- Messages: Individual messages within a conversation.
create table if not exists public.messages (
    id uuid primary key default gen_random_uuid(),
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

-- Webhook Events: Log to prevent replay attacks.
create table if not exists public.webhook_events (
    id uuid primary key default gen_random_uuid(),
    integration_id uuid not null references public.integrations(id) on delete cascade,
    webhook_id text not null,
    processed_at timestamptz default now(),
    created_at timestamptz default now(),
    constraint uq_webhook_id unique (webhook_id)
);
alter table public.webhook_events enable row level security;

-- ------------------------------------------------------------------------------------------------
-- 4. Foreign Key Constraints
--
-- Defined after all tables are created to prevent circular dependency issues.
-- ------------------------------------------------------------------------------------------------

alter table public.product_variants add constraint fk_product
  foreign key (product_id) references public.products(id) on delete cascade;

alter table public.orders add constraint fk_customer
  foreign key (customer_id) references public.customers(id) on delete set null;
  
alter table public.order_line_items add constraint fk_order
  foreign key (order_id) references public.orders(id) on delete cascade;

alter table public.order_line_items add constraint fk_variant
  foreign key (variant_id) references public.product_variants(id) on delete set null;
  
alter table public.inventory_ledger add constraint fk_variant_ledger
  foreign key (variant_id) references public.product_variants(id) on delete cascade;


-- ------------------------------------------------------------------------------------------------
-- 5. Row-Level Security (RLS) Policies
--
-- These policies ensure that users can only access data belonging to their own company.
-- ------------------------------------------------------------------------------------------------

-- Companies: Users can see their own company.
drop policy if exists "Allow full access based on company_id" on public.companies;
create policy "Allow full access based on company_id"
  on public.companies for all
  using (id = get_current_company_id());

-- Users: Users can see all other users within their own company.
drop policy if exists "Allow full access to own company users" on public.users;
create policy "Allow full access to own company users"
  on public.users for all
  using (company_id = get_current_company_id());
  
-- Company Settings
drop policy if exists "Allow full access to own settings" on public.company_settings;
create policy "Allow full access to own settings"
  on public.company_settings for all
  using (company_id = get_current_company_id());
  
-- Suppliers
drop policy if exists "Allow full access to own suppliers" on public.suppliers;
create policy "Allow full access to own suppliers"
  on public.suppliers for all
  using (company_id = get_current_company_id());
  
-- Products
drop policy if exists "Allow full access to own products" on public.products;
create policy "Allow full access to own products"
  on public.products for all
  using (company_id = get_current_company_id());
  
-- Product Variants
drop policy if exists "Allow full access to own variants" on public.product_variants;
create policy "Allow full access to own variants"
  on public.product_variants for all
  using (company_id = get_current_company_id());
  
-- Customers
drop policy if exists "Allow full access to own customers" on public.customers;
create policy "Allow full access to own customers"
  on public.customers for all
  using (company_id = get_current_company_id());

-- Orders
drop policy if exists "Allow full access to own orders" on public.orders;
create policy "Allow full access to own orders"
  on public.orders for all
  using (company_id = get_current_company_id());

-- Order Line Items
drop policy if exists "Allow full access to own line items" on public.order_line_items;
create policy "Allow full access to own line items"
  on public.order_line_items for all
  using (company_id = get_current_company_id());
  
-- Inventory Ledger
drop policy if exists "Allow full access to own ledger" on public.inventory_ledger;
create policy "Allow full access to own ledger"
  on public.inventory_ledger for all
  using (company_id = get_current_company_id());
  
-- Integrations
drop policy if exists "Allow full access to own integrations" on public.integrations;
create policy "Allow full access to own integrations"
  on public.integrations for all
  using (company_id = get_current_company_id());

-- Conversations: Users can access their own conversations.
drop policy if exists "Allow access to own conversations" on public.conversations;
create policy "Allow access to own conversations"
  on public.conversations for all
  using (user_id = get_current_user_id());
  
-- Messages: Users can access messages in conversations they are part of.
drop policy if exists "Allow access to own messages" on public.messages;
create policy "Allow access to own messages"
  on public.messages for all
  using ((
    select user_id from public.conversations
    where id = messages.conversation_id
  ) = get_current_user_id());
  
-- Webhook Events: Only functions with elevated privileges can access.
-- The policy checks that the integration being referenced belongs to the current user's company.
drop policy if exists "Allow service access based on integration" on public.webhook_events;
create policy "Allow service access based on integration"
  on public.webhook_events for all
  using ((select company_id from public.integrations where id = webhook_events.integration_id) = get_current_company_id());


-- ------------------------------------------------------------------------------------------------
-- 6. Core Database Functions
-- ------------------------------------------------------------------------------------------------
-- Main function to process sales from different platforms
drop function if exists public.record_order_from_platform(uuid, text, jsonb);
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
    v_line_item record;
    v_customer_name text;
    v_customer_email text;
    v_order_number text;
    v_financial_status text;
    v_fulfillment_status text;
    v_total_amount integer;
    v_external_order_id text;
begin
    -- Extract data based on the platform
    if p_platform = 'shopify' then
        v_customer_name := coalesce(
            p_order_payload->'customer'->>'first_name', ''
        ) || ' ' || coalesce(
            p_order_payload->'customer'->>'last_name', ''
        );
        v_customer_email := p_order_payload->'customer'->>'email';
        v_order_number := p_order_payload->>'name';
        v_financial_status := p_order_payload->>'financial_status';
        v_fulfillment_status := p_order_payload->>'fulfillment_status';
        v_total_amount := (p_order_payload->>'total_price')::numeric * 100;
        v_external_order_id := p_order_payload->>'id';

    elsif p_platform = 'woocommerce' then
        v_customer_name := coalesce(
            p_order_payload->'billing'->>'first_name', ''
        ) || ' ' || coalesce(
            p_order_payload->'billing'->>'last_name', ''
        );
        v_customer_email := p_order_payload->'billing'->>'email';
        v_order_number := '#' || (p_order_payload->>'number');
        v_financial_status := case when (p_order_payload->>'paid')::boolean = true then 'paid' else 'pending' end;
        v_fulfillment_status := p_order_payload->>'status'; -- e.g., processing, completed
        v_total_amount := (p_order_payload->>'total')::numeric * 100;
        v_external_order_id := p_order_payload->>'id';

    else
        raise exception 'Unsupported platform: %', p_platform;
    end if;

    -- Find or create customer
    if v_customer_email is not null then
        select id into v_customer_id from public.customers
        where company_id = p_company_id and email = v_customer_email;

        if v_customer_id is null then
            insert into public.customers (company_id, customer_name, email, first_order_date)
            values (p_company_id, v_customer_name, v_customer_email, (p_order_payload->>'created_at')::date)
            returning id into v_customer_id;
        end if;
    end if;
    
    -- Insert the order
    insert into public.orders (company_id, order_number, external_order_id, customer_id, financial_status, fulfillment_status, total_amount, source_platform, created_at)
    values (p_company_id, v_order_number, v_external_order_id, v_customer_id, v_financial_status, v_fulfillment_status, v_total_amount, p_platform, (p_order_payload->>'created_at')::timestamptz)
    returning id into v_order_id;
    
    -- Insert line items and update inventory
    for v_line_item in select * from jsonb_to_recordset(p_order_payload->'line_items') as x(sku text, name text, quantity integer, price numeric, id text)
    loop
        select id into v_variant_id from public.product_variants
        where company_id = p_company_id and sku = v_line_item.sku;
        
        if v_variant_id is not null then
            -- Insert the line item
            insert into public.order_line_items (order_id, company_id, variant_id, product_name, sku, quantity, price, external_line_item_id)
            values (v_order_id, p_company_id, v_variant_id, v_line_item.name, v_line_item.sku, v_line_item.quantity, v_line_item.price * 100, v_line_item.id);

            -- Update inventory
            perform public.update_inventory_quantity(
                p_company_id,
                v_variant_id,
                -v_line_item.quantity,
                'sale',
                v_order_id,
                'Sale from order ' || v_order_number
            );
        else
            -- Log a warning or handle cases where the SKU doesn't exist
        end if;
    end loop;
    
    return v_order_id;
end;
$$;


-- Helper function to safely update inventory and log the change
create or replace function public.update_inventory_quantity(
    p_company_id uuid,
    p_variant_id uuid,
    p_quantity_change integer,
    p_change_type text,
    p_related_id uuid default null,
    p_notes text default null
)
returns void
language plpgsql
security definer
as $$
declare
    v_new_quantity integer;
begin
    update public.product_variants
    set inventory_quantity = inventory_quantity + p_quantity_change
    where id = p_variant_id and company_id = p_company_id
    returning inventory_quantity into v_new_quantity;
    
    if found then
        insert into public.inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes)
        values (p_company_id, p_variant_id, p_change_type, p_quantity_change, v_new_quantity, p_related_id, p_notes);
    else
        raise exception 'Product variant not found or access denied. VariantID: %, CompanyID: %', p_variant_id, p_company_id;
    end if;
end;
$$;


-- ------------------------------------------------------------------------------------------------
-- 7. Views for Reporting and Analytics
-- ------------------------------------------------------------------------------------------------
create or replace view public.product_variants_with_details as
select
    pv.*,
    p.title as product_title,
    p.status as product_status,
    p.image_url
from public.product_variants pv
join public.products p on pv.product_id = p.id
where pv.company_id = get_current_company_id();


-- Final setup: Grant usage on schema and table access to authenticated users
grant usage on schema public to authenticated;
grant select on all tables in schema public to authenticated;
grant insert on all tables in schema public to authenticated;
grant update on all tables in schema public to authenticated;
grant delete on all tables in schema public to authenticated;

grant usage on schema public to service_role;
grant all on all tables in schema public to service_role;
grant all on all functions in schema public to service_role;
grant all on all sequences in schema public to service_role;


-- Grant access to the service role for the vault schema
grant usage on schema vault to service_role;
grant all on all tables in schema vault to service_role;

-- Allow authenticated users to execute functions in the public schema
grant execute on all functions in schema public to authenticated;

-- Ensure the 'postgres' user (used by Supabase internally) owns the new objects.
-- This prevents permission issues with future Supabase-managed operations.
-- alter table public.companies owner to postgres;
-- alter table public.users owner to postgres;
-- alter table public.company_settings owner to postgres;
-- alter table public.suppliers owner to postgres;
-- alter table public.products owner to postgres;
-- alter table public.product_variants owner to postgres;
-- alter table public.customers owner to postgres;
-- alter table public.orders owner to postgres;
-- alter table public.order_line_items owner to postgres;
-- alter table public.inventory_ledger owner to postgres;
-- alter table public.integrations owner to postgres;
-- alter table public.conversations owner to postgres;
-- alter table public.messages owner to postgres;
-- alter table public.webhook_events owner to postgres;

-- alter function public.get_current_user_id() owner to postgres;
-- alter function public.get_current_company_id() owner to postgres;
-- alter function public.handle_new_user() owner to postgres;
-- alter function public.record_order_from_platform(uuid, text, jsonb) owner to postgres;
-- alter function public.update_inventory_quantity(uuid, uuid, integer, text, uuid, text) owner to postgres;

-- alter view public.product_variants_with_details owner to postgres;


-- Supabase already manages the ownership of auth schema objects, so we don't touch them.
-- The `authenticator` role is a special Supabase role used for RLS.
-- grant select on table public.users to authenticator;
-- grant select on table public.companies to authenticator;

-- Done.
