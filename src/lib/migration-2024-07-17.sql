-- Drop the old, problematic trigger and function if they exist.
-- This ensures a clean state before creating the new, correct objects.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS handle_new_user();

-- Helper function to get the company_id from the JWT.
-- This is used by all row-level security policies.
create or replace function get_company_id()
returns uuid
language sql
security definer
set search_path = public
as $$
    select (auth.jwt()->>'company_id')::uuid;
$$;


-- =================================================================
-- 1. COMPANIES TABLE
-- Stores basic information about each company tenant.
-- =================================================================
create table if not exists public.companies (
    id uuid not null default uuid_generate_v4(),
    name text not null,
    created_at timestamp with time zone not null default now(),
    primary key (id)
);
alter table public.companies enable row level security;
drop policy if exists "Allow all access to own company" on public.companies;
create policy "Allow all access to own company"
on public.companies
for all
using ( id = get_company_id() );


-- =================================================================
-- 2. USERS TABLE (PUBLIC)
-- A public-schema mirror of auth.users for easier joins and RLS.
-- =================================================================
create table if not exists public.users (
    id uuid not null references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    email text,
    role text default 'Member',
    deleted_at timestamp with time zone,
    created_at timestamp with time zone default now(),
    primary key (id)
);
alter table public.users enable row level security;
drop policy if exists "Allow users to see themselves" on public.users;
create policy "Allow users to see themselves"
on public.users
for select
using ( id = auth.uid() );

drop policy if exists "Allow admin to see other users in their company" on public.users;
create policy "Allow admin to see other users in their company"
on public.users
for select
using ( company_id = get_company_id() and (select role from public.users where id = auth.uid()) = 'Admin' );

-- Add the 'role' column if it doesn't exist.
alter table public.users add column if not exists role text default 'Member';


-- =================================================================
-- 3. HANDLE NEW USER FUNCTION
-- This server-side function creates a company and user profile.
-- It's called from the application's signup server action.
-- =================================================================
create or replace function public.handle_new_user()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    new_company_id uuid;
    new_user_id uuid := auth.uid();
    user_company_name text := auth.jwt()->'raw_user_meta_data'->>'company_name';
begin
    -- Create a new company for the user
    insert into public.companies (name)
    values (user_company_name)
    returning id into new_company_id;

    -- Create a public user profile linked to the company
    insert into public.users (id, company_id, email, role)
    values (new_user_id, new_company_id, auth.jwt()->>'email', 'Owner');

    -- Update the user's app_metadata with the new company_id and role
    perform update_user_app_metadata(new_user_id, jsonb_build_object('company_id', new_company_id, 'role', 'Owner'));
end;
$$;
grant execute on function public.handle_new_user() to authenticated;


-- =================================================================
-- 4. UPDATE USER METADATA FUNCTION
-- A secure helper function to update auth.users metadata.
-- =================================================================
create or replace function public.update_user_app_metadata(user_id uuid, metadata jsonb)
returns void
language plpgsql
security definer
as $$
begin
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || metadata
  where id = user_id;
end;
$$;


-- =================================================================
-- 5. OTHER TABLE CREATIONS WITH `IF NOT EXISTS`
-- These ensure that all required application tables exist.
-- =================================================================
create table if not exists public.products (
    id uuid not null default uuid_generate_v4() primary key,
    company_id uuid not null references public.companies(id) on delete cascade,
    title text not null,
    description text,
    handle text,
    product_type text,
    tags text[],
    status text,
    image_url text,
    external_product_id text,
    created_at timestamp with time zone not null default now(),
    updated_at timestamp with time zone,
    unique(company_id, external_product_id)
);
alter table public.products enable row level security;
drop policy if exists "Allow all access to own company" on public.products;
create policy "Allow all access to own company" on public.products for all using (company_id = get_company_id());

create table if not exists public.product_variants (
    id uuid not null default uuid_generate_v4() primary key,
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
    price integer,
    compare_at_price integer,
    cost integer,
    inventory_quantity integer not null default 0,
    location text,
    external_variant_id text,
    created_at timestamp with time zone default now(),
    updated_at timestamp with time zone default now(),
    unique(company_id, sku),
    unique(company_id, external_variant_id)
);
alter table public.product_variants enable row level security;
drop policy if exists "Allow all access to own company" on public.product_variants;
create policy "Allow all access to own company" on public.product_variants for all using (company_id = get_company_id());

create table if not exists public.inventory_ledger (
    id uuid not null default uuid_generate_v4() primary key,
    company_id uuid not null references public.companies(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    change_type text not null,
    quantity_change integer not null,
    new_quantity integer not null,
    related_id uuid,
    notes text,
    created_at timestamp with time zone not null default now()
);
alter table public.inventory_ledger enable row level security;
drop policy if exists "Allow all access to own company" on public.inventory_ledger;
create policy "Allow all access to own company" on public.inventory_ledger for all using (company_id = get_company_id());

create table if not exists public.suppliers (
    id uuid not null default uuid_generate_v4() primary key,
    company_id uuid not null references public.companies(id) on delete cascade,
    name text not null,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamp with time zone not null default now()
);
alter table public.suppliers enable row level security;
drop policy if exists "Allow all access to own company" on public.suppliers;
create policy "Allow all access to own company" on public.suppliers for all using (company_id = get_company_id());


create table if not exists public.customers (
    id uuid not null default uuid_generate_v4() primary key,
    company_id uuid not null references public.companies(id) on delete cascade,
    customer_name text not null,
    email text,
    total_orders integer default 0,
    total_spent integer default 0,
    first_order_date date,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone default now()
);
alter table public.customers enable row level security;
drop policy if exists "Allow all access to own company" on public.customers;
create policy "Allow all access to own company" on public.customers for all using (company_id = get_company_id());


create table if not exists public.purchase_orders (
    id uuid not null default uuid_generate_v4() primary key,
    company_id uuid not null references public.companies(id) on delete cascade,
    supplier_id uuid references public.suppliers(id) on delete set null,
    status text not null default 'Draft',
    po_number text not null,
    total_cost integer not null,
    expected_arrival_date date,
    idempotency_key uuid,
    created_at timestamp with time zone not null default now(),
    unique(company_id, po_number)
);
alter table public.purchase_orders enable row level security;
drop policy if exists "Allow all access to own company" on public.purchase_orders;
create policy "Allow all access to own company" on public.purchase_orders for all using (company_id = get_company_id());


create table if not exists public.purchase_order_line_items (
    id uuid not null default uuid_generate_v4() primary key,
    purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    quantity integer not null,
    cost integer not null
);
-- Inherits RLS from purchase_orders.


create table if not exists public.orders (
    id uuid not null default uuid_generate_v4() primary key,
    company_id uuid not null references public.companies(id) on delete cascade,
    order_number text not null,
    external_order_id text,
    customer_id uuid references public.customers(id) on delete set null,
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
    created_at timestamp with time zone default now(),
    updated_at timestamp with time zone default now(),
    unique(company_id, external_order_id, source_platform)
);
alter table public.orders enable row level security;
drop policy if exists "Allow all access to own company" on public.orders;
create policy "Allow all access to own company" on public.orders for all using (company_id = get_company_id());


create table if not exists public.order_line_items (
    id uuid not null default uuid_generate_v4() primary key,
    order_id uuid not null references public.orders(id) on delete cascade,
    variant_id uuid references public.product_variants(id) on delete set null,
    company_id uuid not null references public.companies(id) on delete cascade,
    product_name text not null,
    variant_title text,
    sku text,
    quantity integer not null,
    price integer not null,
    total_discount integer default 0,
    tax_amount integer default 0,
    cost_at_time integer,
    external_line_item_id text
);
alter table public.order_line_items enable row level security;
drop policy if exists "Allow all access to own company" on public.order_line_items;
create policy "Allow all access to own company" on public.order_line_items for all using (company_id = get_company_id());


create table if not exists public.company_settings (
    company_id uuid not null primary key references public.companies(id) on delete cascade,
    dead_stock_days integer not null default 90,
    fast_moving_days integer not null default 30,
    overstock_multiplier integer not null default 3,
    high_value_threshold integer not null default 1000,
    created_at timestamp with time zone not null default now(),
    updated_at timestamp with time zone
);
alter table public.company_settings enable row level security;
drop policy if exists "Allow all access to own company" on public.company_settings;
create policy "Allow all access to own company" on public.company_settings for all using (company_id = get_company_id());

create table if not exists public.integrations (
    id uuid not null default uuid_generate_v4() primary key,
    company_id uuid not null references public.companies(id) on delete cascade,
    platform text not null,
    shop_domain text,
    shop_name text,
    is_active boolean default false,
    last_sync_at timestamp with time zone,
    sync_status text,
    created_at timestamp with time zone not null default now(),
    updated_at timestamp with time zone
);
alter table public.integrations enable row level security;
drop policy if exists "Allow all access to own company" on public.integrations;
create policy "Allow all access to own company" on public.integrations for all using (company_id = get_company_id());

create table if not exists public.conversations (
    id uuid not null default uuid_generate_v4() primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    title text not null,
    created_at timestamp with time zone default now(),
    last_accessed_at timestamp with time zone default now(),
    is_starred boolean default false
);
alter table public.conversations enable row level security;
drop policy if exists "Allow all access to own user" on public.conversations;
create policy "Allow all access to own user" on public.conversations for all using (user_id = auth.uid());


create table if not exists public.messages (
    id uuid not null default uuid_generate_v4() primary key,
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
    created_at timestamp with time zone default now()
);
alter table public.messages enable row level security;
drop policy if exists "Allow all access to own user" on public.messages;
create policy "Allow all access to own user" on public.messages for all using (company_id = get_company_id());


-- =================================================================
-- 6. VIEWS (using CREATE OR REPLACE)
-- =================================================================

-- View to combine product and variant info
create or replace view public.product_variants_with_details as
select
    pv.id,
    pv.product_id,
    pv.company_id,
    p.title as product_title,
    p.status as product_status,
    p.image_url,
    pv.sku,
    pv.title as variant_title,
    pv.price,
    pv.cost,
    pv.inventory_quantity,
    pv.location,
    pv.updated_at
from
    public.product_variants pv
join
    public.products p on pv.product_id = p.id
where
    pv.company_id = get_company_id();


-- =================================================================
-- 7. OTHER FUNCTIONS AND TRIGGERS
-- =================================================================
drop function if exists public.record_inventory_change();
create or replace function public.record_inventory_change()
returns trigger
language plpgsql
as $$
begin
    if TG_OP = 'UPDATE' and OLD.inventory_quantity <> NEW.inventory_quantity then
        insert into public.inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, notes)
        values (NEW.company_id, NEW.id, 'manual_adjustment', NEW.inventory_quantity - OLD.inventory_quantity, NEW.inventory_quantity, 'Manual quantity update');
    elsif TG_OP = 'INSERT' then
        insert into public.inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, notes)
        values (NEW.company_id, NEW.id, 'creation', NEW.inventory_quantity, NEW.inventory_quantity, 'Variant created');
    end if;
    return NEW;
end;
$$;
drop trigger if exists on_inventory_change on public.product_variants;
create trigger on_inventory_change
after insert or update of inventory_quantity on public.product_variants
for each row
execute function public.record_inventory_change();


drop function if exists public.get_or_create_customer();
create or replace function public.get_or_create_customer(p_company_id uuid, p_name text, p_email text)
returns uuid
language plpgsql
as $$
declare
    customer_uuid uuid;
begin
    select id into customer_uuid from public.customers where company_id = p_company_id and email = p_email limit 1;
    if customer_uuid is null then
        insert into public.customers (company_id, customer_name, email, first_order_date)
        values (p_company_id, p_name, p_email, current_date)
        returning id into customer_uuid;
    end if;
    return customer_uuid;
end;
$$;


-- Final grant to make sure the authenticated role can use the functions
grant execute on function public.get_company_id() to authenticated;
grant execute on function public.get_or_create_customer(uuid, text, text) to authenticated;
