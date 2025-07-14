-- ----------------------------------------------------------------------------------
--
-- ### ✨ InvoChat - Database Schema ###
--
-- This script is idempotent and can be run multiple times safely.
-- It is designed to be the single source of truth for the application's database structure.
--
-- To set up your Supabase project, copy the entire contents of this file
-- and paste it into the Supabase SQL Editor, then click "Run".
--
-- ----------------------------------------------------------------------------------

-- ----------------------------------------------------------------------------------
-- 1. Enable Required PostgreSQL Extensions
-- ----------------------------------------------------------------------------------
-- These extensions provide additional functionality used throughout the schema.
create extension if not exists "uuid-ossp" with schema extensions;
create extension if not exists "pgcrypto" with schema extensions;
create extension if not exists "pgroonga" with schema extensions;
-- ----------------------------------------------------------------------------------


-- ----------------------------------------------------------------------------------
-- 2. Create Core Application Tables
-- ----------------------------------------------------------------------------------
-- These tables form the backbone of the application's data model.

-- Manages company-specific information.
create table if not exists public.companies (
    id uuid primary key default uuid_generate_v4(),
    name text not null,
    created_at timestamptz not null default now()
);

-- Stores user profiles and their association with companies.
create table if not exists public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    email text,
    role text default 'Member' check (role in ('Owner', 'Admin', 'Member')),
    deleted_at timestamptz,
    created_at timestamptz default now()
);

-- Stores company-specific settings and business logic parameters.
create table if not exists public.company_settings (
    company_id uuid primary key references public.companies(id) on delete cascade,
    dead_stock_days integer not null default 90,
    fast_moving_days integer not null default 30,
    overstock_multiplier integer not null default 3,
    high_value_threshold integer not null default 1000,
    predictive_stock_days integer not null default 7,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);

-- Stores supplier information.
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

-- Stores base product information.
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
    updated_at timestamptz,
    unique(company_id, external_product_id)
);

-- Stores product variants (SKUs).
create table if not exists public.product_variants (
    id uuid primary key default uuid_generate_v4(),
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
    price integer,
    compare_at_price integer,
    cost integer,
    inventory_quantity integer not null default 0,
    location text null,
    external_variant_id text,
    created_at timestamptz default now(),
    updated_at timestamptz default now(),
    unique(company_id, external_variant_id),
    unique(company_id, sku)
);

-- Stores order information.
create table if not exists public.orders (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    order_number text not null,
    external_order_id text,
    customer_id uuid, -- No FK constraint to allow for guest checkouts
    financial_status text,
    fulfillment_status text,
    currency text,
    subtotal integer not null default 0,
    total_tax integer default 0,
    total_shipping integer default 0,
    total_discounts integer default 0,
    total_amount integer not null,
    source_platform text,
    created_at timestamptz default now(),
    updated_at timestamptz,
    unique(company_id, external_order_id)
);

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
    price integer not null,
    total_discount integer,
    tax_amount integer,
    cost_at_time integer,
    external_line_item_id text
);

-- Stores customer information.
create table if not exists public.customers (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    customer_name text not null,
    email text,
    total_orders integer default 0,
    total_spent integer default 0,
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz default now(),
    unique(company_id, email)
);

-- Tracks every change to inventory quantity for auditing.
create table if not exists public.inventory_ledger (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    change_type text not null,
    quantity_change integer not null,
    new_quantity integer not null,
    related_id uuid, -- e.g., order_id or purchase_order_id
    notes text,
    created_at timestamptz not null default now()
);

-- Stores purchase order headers.
create table if not exists public.purchase_orders (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    supplier_id uuid references public.suppliers(id) on delete set null,
    status text not null default 'Draft',
    po_number text not null,
    total_cost integer not null,
    expected_arrival_date date,
    created_at timestamptz not null default now()
);

-- Stores line items for each purchase order.
create table if not exists public.purchase_order_line_items (
    id uuid primary key default uuid_generate_v4(),
    purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    quantity integer not null,
    cost integer not null
);

-- Manages connections to external platforms (Shopify, etc.).
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
    updated_at timestamptz,
    unique(company_id, platform)
);

-- Stores records of processed webhooks to prevent duplicates.
create table if not exists public.webhook_events (
    id uuid primary key default gen_random_uuid(),
    integration_id uuid not null references public.integrations(id) on delete cascade,
    platform text not null,
    webhook_id text not null,
    processed_at timestamptz default now(),
    created_at timestamptz default now(),
    unique(integration_id, webhook_id)
);

-- Stores chat conversation history.
create table if not exists public.conversations (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid not null references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    title text not null,
    created_at timestamptz default now(),
    last_accessed_at timestamptz default now(),
    is_starred boolean default false
);

-- Stores individual chat messages.
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

-- Stores data export jobs.
create table if not exists public.export_jobs (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    requested_by_user_id uuid not null references auth.users(id) on delete cascade,
    status text not null default 'pending',
    download_url text,
    expires_at timestamptz,
    created_at timestamptz not null default now()
);
-- ----------------------------------------------------------------------------------


-- ----------------------------------------------------------------------------------
-- 3. Row-Level Security (RLS)
-- ----------------------------------------------------------------------------------
-- This is a critical security measure for our multi-tenant application.
-- It ensures that users can only access data belonging to their own company.

alter table public.companies enable row level security;
alter table public.profiles enable row level security;
alter table public.company_settings enable row level security;
alter table public.suppliers enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.orders enable row level security;
alter table public.order_line_items enable row level security;
alter table public.customers enable row level security;
alter table public.inventory_ledger enable row level security;
alter table public.purchase_orders enable row level security;
alter table public.purchase_order_line_items enable row level security;
alter table public.integrations enable row level security;
alter table public.webhook_events enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.export_jobs enable row level security;

-- Function to get the company_id from the current user's session claims.
create or replace function public.get_my_company_id()
returns uuid
language sql stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid;
$$;

-- Function to check if a user is an admin of their company.
create or replace function public.is_company_admin(p_company_id uuid)
returns boolean
language sql stable
as $$
  select exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and company_id = p_company_id
      and role in ('Admin', 'Owner')
  );
$$;

-- RLS Policies
-- Users can see their own profile.
create policy "Users can view their own profile" on public.profiles for select using (id = auth.uid());
-- Users can see the company they belong to.
create policy "Users can view their own company" on public.companies for select using (id = public.get_my_company_id());
-- Generic policy for most tables.
create policy "Users can access data within their own company" on public.company_settings for all using (company_id = public.get_my_company_id());
create policy "Users can access data within their own company" on public.suppliers for all using (company_id = public.get_my_company_id());
create policy "Users can access data within their own company" on public.products for all using (company_id = public.get_my_company_id());
create policy "Users can access data within their own company" on public.product_variants for all using (company_id = public.get_my_company_id());
create policy "Users can access data within their own company" on public.orders for all using (company_id = public.get_my_company_id());
create policy "Users can access data within their own company" on public.order_line_items for all using (company_id = public.get_my_company_id());
create policy "Users can access data within their own company" on public.customers for all using (company_id = public.get_my_company_id());
create policy "Users can access data within their own company" on public.inventory_ledger for all using (company_id = public.get_my_company_id());
create policy "Users can access data within their own company" on public.purchase_orders for all using (company_id = public.get_my_company_id());
create policy "Users can access data within their own company" on public.purchase_order_line_items for all using (company_id = public.get_my_company_id());
create policy "Users can access data within their own company" on public.integrations for all using (company_id = public.get_my_company_id());
create policy "Users can access data within their own company" on public.export_jobs for all using (company_id = public.get_my_company_id());

-- Webhook events are special, they don't have a user session. Access is granted to service_role only.
create policy "Service role can access webhook events" on public.webhook_events for all using (true) with check (true);

-- Conversations and messages are user-specific.
create policy "Users can access their own conversations" on public.conversations for all using (user_id = auth.uid());
create policy "Users can access messages in their own conversations" on public.messages for all using (company_id = public.get_my_company_id() and conversation_id in (select id from public.conversations where user_id = auth.uid()));

-- Admins/Owners have broader permissions for user management.
create policy "Admins can manage profiles in their company" on public.profiles for all
  using (company_id = public.get_my_company_id())
  with check (public.is_company_admin(company_id));
-- ----------------------------------------------------------------------------------


-- ----------------------------------------------------------------------------------
-- 4. Database Views
-- ----------------------------------------------------------------------------------
-- These views simplify complex queries and provide a denormalized layer for the application.

-- Drop the view before creating to handle column order changes
drop view if exists public.product_variants_with_details;

create or replace view public.product_variants_with_details as
select
    pv.*,
    p.title as product_title,
    p.status as product_status,
    p.image_url,
    p.product_type
from
    public.product_variants pv
join
    public.products p on pv.product_id = p.id;
-- ----------------------------------------------------------------------------------


-- ----------------------------------------------------------------------------------
-- 5. Database Functions & Triggers
-- ----------------------------------------------------------------------------------
-- These functions encapsulate business logic and are triggered by database events.

-- This function is called when a new user signs up.
-- It creates a new company, a profile for the user, and sets them as the owner.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer -- Must run with elevated privileges to create new data
as $$
declare
  new_company_id uuid;
  company_name text;
begin
  -- 1. Create a new company for the user.
  company_name := coalesce(new.raw_user_meta_data->>'company_name', new.email);
  insert into public.companies (name) values (company_name)
  returning id into new_company_id;

  -- 2. Create a profile for the new user, linking them to the company.
  insert into public.profiles (id, company_id, email, role)
  values (new.id, new_company_id, new.email, 'Owner');

  -- 3. Update the user's app_metadata with the new company_id and role.
  -- This makes it accessible in JWT claims for RLS.
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'role', 'Owner')
  where id = new.id;

  return new;
end;
$$;

-- This trigger calls the handle_new_user function after a new user is created.
create or replace trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


-- This function updates the product_variants table quantity and logs the change.
create or replace function public.update_inventory_quantity(
    p_variant_id uuid,
    p_company_id uuid,
    p_quantity_change integer,
    p_change_type text,
    p_related_id uuid default null,
    p_notes text default null
)
returns integer
language plpgsql
security invoker -- Run as the calling user
as $$
declare
    new_quantity integer;
begin
    -- Update the quantity and get the new value
    update public.product_variants
    set inventory_quantity = inventory_quantity + p_quantity_change
    where id = p_variant_id and company_id = p_company_id
    returning inventory_quantity into new_quantity;

    -- If no row was updated, raise an error
    if not found then
        raise exception 'Product variant not found or company ID mismatch';
    end if;

    -- Log the change in the inventory ledger
    insert into public.inventory_ledger(company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes)
    values (p_company_id, p_variant_id, p_change_type, p_quantity_change, new_quantity, p_related_id, p_notes);

    return new_quantity;
end;
$$;


-- This function handles recording a sale transaction.
create or replace function public.record_sale_transaction(
    p_company_id uuid,
    p_user_id uuid,
    p_customer_name text,
    p_customer_email text,
    p_payment_method text,
    p_notes text,
    p_sale_items jsonb[],
    p_external_id text
)
returns uuid
language plpgsql
security invoker
as $$
declare
    v_customer_id uuid;
    v_order_id uuid;
    v_total_amount integer := 0;
    v_item jsonb;
    v_variant_id uuid;
    v_unit_price integer;
    v_quantity integer;
begin
    -- Find or create the customer
    select id into v_customer_id from public.customers
    where company_id = p_company_id and email = p_customer_email;

    if v_customer_id is null then
        insert into public.customers (company_id, customer_name, email)
        values (p_company_id, p_customer_name, p_customer_email)
        returning id into v_customer_id;
    end if;

    -- Calculate total amount
    foreach v_item in array p_sale_items
    loop
        v_total_amount := v_total_amount + ((v_item->>'unit_price')::integer * (v_item->>'quantity')::integer);
    end loop;

    -- Create the order
    insert into public.orders (company_id, order_number, customer_id, total_amount, external_order_id)
    values (p_company_id, 'SALE-' || substr(uuid_generate_v4()::text, 1, 8), v_customer_id, v_total_amount, p_external_id)
    returning id into v_order_id;

    -- Create order line items and update inventory
    foreach v_item in array p_sale_items
    loop
        select id into v_variant_id from public.product_variants
        where company_id = p_company_id and sku = (v_item->>'sku');
        
        v_unit_price := (v_item->>'unit_price')::integer;
        v_quantity := (v_item->>'quantity')::integer;

        if v_variant_id is not null then
            insert into public.order_line_items (order_id, company_id, variant_id, product_name, sku, quantity, price, cost_at_time)
            values (v_order_id, p_company_id, v_variant_id, v_item->>'product_name', v_item->>'sku', v_quantity, v_unit_price, (v_item->>'cost_at_time')::integer);

            -- Decrease inventory
            perform public.update_inventory_quantity(v_variant_id, p_company_id, -v_quantity, 'sale', v_order_id);
        else
            -- Handle case where SKU might not exist
            insert into public.order_line_items (order_id, company_id, product_name, sku, quantity, price)
            values (v_order_id, p_company_id, v_item->>'product_name', v_item->>'sku', v_quantity, v_unit_price);
        end if;
    end loop;

    return v_order_id;
end;
$$;

-- Secure search function for products.
create or replace function public.search_products(p_company_id uuid, p_search_term text)
returns setof public.products
language sql stable
security invoker
as $$
    select *
    from public.products
    where
        company_id = p_company_id
        and title &@~ p_search_term;
$$;
-- ----------------------------------------------------------------------------------

-- ----------------------------------------------------------------------------------
-- 6. Database Indexes
-- ----------------------------------------------------------------------------------
-- These indexes are crucial for application performance, especially as data grows.

-- Indexes for foreign keys
create index if not exists idx_profiles_company_id on public.profiles(company_id);
create index if not exists idx_suppliers_company_id on public.suppliers(company_id);
create index if not exists idx_products_company_id on public.products(company_id);
create index if not exists idx_product_variants_product_id on public.product_variants(product_id);
create index if not exists idx_product_variants_company_id on public.product_variants(company_id);
create index if not exists idx_orders_company_id on public.orders(company_id);
create index if not exists idx_orders_customer_id on public.orders(customer_id);
create index if not exists idx_order_line_items_order_id on public.order_line_items(order_id);
create index if not exists idx_order_line_items_variant_id on public.order_line_items(variant_id);
create index if not exists idx_customers_company_id on public.customers(company_id);
create index if not exists idx_inventory_ledger_variant_id on public.inventory_ledger(variant_id);
create index if not exists idx_purchase_orders_supplier_id on public.purchase_orders(supplier_id);
create index if not exists idx_purchase_order_line_items_po_id on public.purchase_order_line_items(purchase_order_id);
create index if not exists idx_integrations_company_id on public.integrations(company_id);
create index if not exists idx_conversations_user_id on public.conversations(user_id);
create index if not exists idx_messages_conversation_id on public.messages(conversation_id);

-- Indexes for frequently queried columns
create index if not exists idx_product_variants_sku on public.product_variants(sku);
create index if not exists idx_products_external_id on public.products(external_product_id);
create index if not exists idx_product_variants_external_id on public.product_variants(external_variant_id);
create index if not exists idx_orders_external_id on public.orders(external_order_id);
create index if not exists idx_customers_email on public.customers(email);

-- PGroonga index for full-text search on products. This uses the secure search function.
drop index if exists pgroonga_products_title_index;
create index if not exists pgroonga_products_title_index on public.products using pgroonga (title);
-- ----------------------------------------------------------------------------------

-- That's it! Your database is now ready for InvoChat.

