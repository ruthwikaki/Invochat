
-- =================================================================
-- InvoChat Master Database Schema
--
-- This script is idempotent and can be re-run safely.
-- It is designed to set up the entire database from scratch,
-- including tables, views, functions, and security policies.
-- =================================================================

-- Step 0: Install Required Extensions
create extension if not exists "uuid-ossp" with schema extensions;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_stat_statements with schema extensions;

-- =================================================================
-- Step 1: Core Table Definitions
-- =================================================================

-- Companies Table
create table if not exists public.companies (
    id uuid primary key default uuid_generate_v4(),
    name text not null,
    created_at timestamptz not null default now()
);
comment on table public.companies is 'Stores information about each tenant company.';

-- Users Table
-- This table is a public representation of auth.users, linked to a company.
create table if not exists public.users (
    id uuid primary key references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    email text,
    role text default 'Member' check (role in ('Owner', 'Admin', 'Member')),
    deleted_at timestamptz,
    created_at timestamptz default now()
);
comment on table public.users is 'User profiles linked to their respective companies.';

-- Company Settings Table
create table if not exists public.company_settings (
    company_id uuid primary key references public.companies(id) on delete cascade,
    dead_stock_days int not null default 90,
    fast_moving_days int not null default 30,
    predictive_stock_days int not null default 7,
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
    overstock_multiplier int not null default 3,
    high_value_threshold int not null default 100000 -- in cents
);
comment on table public.company_settings is 'Tenant-specific business logic and settings.';

-- Integrations Table
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
comment on table public.integrations is 'Stores connection details for third-party e-commerce platforms.';

-- Webhook Events Table
create table if not exists public.webhook_events (
    id uuid primary key default gen_random_uuid(),
    integration_id uuid not null references public.integrations(id) on delete cascade,
    webhook_id text not null,
    processed_at timestamptz default now(),
    created_at timestamptz default now(),
    unique(integration_id, webhook_id)
);
comment on table public.webhook_events is 'Logs incoming webhook IDs to prevent replay attacks.';

-- Products Table
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
    fts_document tsvector,
    created_at timestamptz not null default now(),
    updated_at timestamptz,
    unique(company_id, external_product_id)
);
comment on table public.products is 'Core product information.';

-- Product Variants Table
create table if not exists public.product_variants (
    id uuid primary key default uuid_generate_v4(),
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
    price int, -- in cents
    compare_at_price int, -- in cents
    cost int, -- in cents
    inventory_quantity int not null default 0,
    location text,
    external_variant_id text,
    created_at timestamptz default now(),
    updated_at timestamptz default now(),
    unique(company_id, sku),
    unique(company_id, external_variant_id)
);
comment on table public.product_variants is 'Specific variants of a product, representing the sellable unit.';

-- Inventory Ledger Table
create table if not exists public.inventory_ledger (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    change_type text not null,
    quantity_change int not null,
    new_quantity int not null,
    related_id uuid, -- e.g., order_id, purchase_order_id
    notes text,
    created_at timestamptz not null default now()
);
comment on table public.inventory_ledger is 'Transactional log of all inventory movements.';

-- Customers Table
create table if not exists public.customers (
  id uuid primary key default uuid_generate_v4(),
  company_id uuid not null references public.companies(id) on delete cascade,
  customer_name text not null,
  email text,
  total_orders int default 0,
  total_spent int default 0, -- in cents
  first_order_date date,
  deleted_at timestamptz,
  created_at timestamptz default now()
);
comment on table public.customers is 'Customer information, aggregated from sales data.';

-- Orders Table
create table if not exists public.orders (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    order_number text not null,
    external_order_id text,
    customer_id uuid references public.customers(id),
    financial_status text default 'pending',
    fulfillment_status text default 'unfulfilled',
    currency text default 'USD',
    subtotal int not null default 0, -- in cents
    total_tax int default 0, -- in cents
    total_shipping int default 0, -- in cents
    total_discounts int default 0, -- in cents
    total_amount int not null, -- in cents
    source_platform text,
    source_name text,
    tags text[],
    notes text,
    cancelled_at timestamptz,
    created_at timestamptz default now(),
    updated_at timestamptz default now(),
    unique(company_id, external_order_id)
);
comment on table public.orders is 'Sales order information from connected platforms.';

-- Order Line Items Table
create table if not exists public.order_line_items (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    order_id uuid not null references public.orders(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete set null,
    product_name text not null,
    variant_title text,
    sku text not null,
    quantity int not null,
    price int not null, -- in cents
    total_discount int default 0,
    tax_amount int default 0,
    cost_at_time int, -- in cents
    fulfillment_status text default 'unfulfilled',
    requires_shipping boolean default true,
    external_line_item_id text
);
comment on table public.order_line_items is 'Individual line items for each sales order.';

-- Suppliers Table
create table if not exists public.suppliers (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    name text not null,
    email text,
    phone text,
    default_lead_time_days int,
    notes text,
    created_at timestamptz not null default now()
);
comment on table public.suppliers is 'Information about vendors and suppliers.';

-- Purchase Orders Table
create table if not exists public.purchase_orders (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    supplier_id uuid references public.suppliers(id) on delete set null,
    status text not null default 'Draft',
    po_number text not null,
    total_cost int not null, -- in cents
    expected_arrival_date date,
    idempotency_key uuid unique,
    created_at timestamptz not null default now()
);
comment on table public.purchase_orders is 'Records of purchase orders sent to suppliers.';

-- Purchase Order Line Items Table
create table if not exists public.purchase_order_line_items (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    quantity int not null,
    cost int not null
);
comment on table public.purchase_order_line_items is 'Individual line items for each purchase order.';

-- Chat & AI Tables
create table if not exists public.conversations (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users on delete cascade,
  company_id uuid not null references public.companies on delete cascade,
  title text not null,
  created_at timestamptz default now(),
  last_accessed_at timestamptz default now(),
  is_starred boolean default false
);

create table if not exists public.messages (
  id uuid primary key default uuid_generate_v4(),
  conversation_id uuid not null references public.conversations on delete cascade,
  company_id uuid not null references public.companies on delete cascade,
  role text not null,
  content text,
  component text,
  component_props jsonb,
  visualization jsonb,
  confidence numeric,
  assumptions text[],
  created_at timestamptz default now(),
  is_error boolean default false
);

-- =================================================================
-- Step 2: Indexes for Performance
-- =================================================================

-- Add indexes for frequently queried columns and foreign keys.
create index if not exists idx_users_company_id on public.users(company_id);
create index if not exists idx_products_company_id on public.products(company_id);
create index if not exists idx_product_variants_company_id on public.product_variants(company_id);
create index if not exists idx_product_variants_sku on public.product_variants(company_id, sku);
create index if not exists idx_inventory_ledger_variant_id on public.inventory_ledger(variant_id);
create index if not exists idx_inventory_ledger_company_id_created_at on public.inventory_ledger(company_id, created_at desc);
create index if not exists idx_orders_company_id_created_at on public.orders(company_id, created_at desc);
create index if not exists idx_order_line_items_order_id on public.order_line_items(order_id);
create index if not exists idx_order_line_items_variant_id on public.order_line_items(variant_id);
create index if not exists idx_customers_company_id on public.customers(company_id);
create index if not exists idx_suppliers_company_id on public.suppliers(company_id);
create index if not exists idx_purchase_orders_company_id on public.purchase_orders(company_id);
create index if not exists idx_purchase_order_line_items_po_id on public.purchase_order_line_items(purchase_order_id);
create index if not exists idx_conversations_user_id on public.conversations(user_id);

-- Index for full-text search on products
create index if not exists products_fts_document_idx on public.products using gin (fts_document);

-- =================================================================
-- Step 3: Views for Simplified Queries
-- =================================================================

-- A view to get customer details with aggregated sales data
create or replace view public.customers_view as
select
    c.*,
    count(o.id) as total_orders,
    coalesce(sum(o.total_amount), 0) as total_spent
from public.customers c
left join public.orders o on c.id = o.customer_id
group by c.id;

-- A view to get order details with customer info
create or replace view public.orders_view as
select
    o.*,
    c.customer_name,
    c.email as customer_email
from public.orders o
left join public.customers c on o.customer_id = c.id;

-- A view to get product variant details with parent product info
create or replace view public.product_variants_with_details as
select
    pv.*,
    p.title as product_title,
    p.status as product_status,
    p.image_url
from public.product_variants pv
join public.products p on pv.product_id = p.id;

-- =================================================================
-- Step 4: Functions and Triggers
-- =================================================================

-- Function to handle new user creation
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
  -- Extract company_id from the user's metadata, falling back to creating a new company
  company_id := (new.raw_app_meta_data->>'company_id')::uuid;
  user_email := new.email;
  
  if company_id is null then
    -- If no company_id, it's a new signup, create a new company
    company_name := new.raw_app_meta_data->>'company_name';
    insert into public.companies (name) values (coalesce(company_name, user_email))
    returning id into company_id;
    
    -- Insert the user with 'Owner' role
    insert into public.users (id, company_id, email, role)
    values (new.id, company_id, user_email, 'Owner');
  else
    -- User is being invited to an existing company
    insert into public.users (id, company_id, email, role)
    values (new.id, company_id, user_email, 'Member');
  end if;

  -- Update the user's app_metadata with the final company_id and role
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id, 'role', 'Owner')
  where id = new.id;
  
  return new;
end;
$$;

-- Trigger to call handle_new_user on auth.users insert
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Function to handle full-text search trigger
create or replace function public.update_products_fts_document()
returns trigger
language plpgsql
as $$
begin
    new.fts_document := to_tsvector('english', coalesce(new.title, '') || ' ' || coalesce(new.description, '') || ' ' || coalesce(new.product_type, ''));
    return new;
end;
$$;

-- Trigger for full-text search
drop trigger if exists update_products_fts_trigger on public.products;
create trigger update_products_fts_trigger
before insert or update on public.products
for each row
execute function public.update_products_fts_document();

-- Function to record a sale and update inventory atomically
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
as $$
declare
    v_customer_id uuid;
    v_order_id uuid;
    v_total_amount int := 0;
    v_item jsonb;
    v_variant record;
    v_line_item_total int;
    v_quantity_to_deduct int;
begin
    -- Find or create customer
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
        v_total_amount := v_total_amount + ((v_item->>'unit_price')::int * (v_item->>'quantity')::int);
    end loop;

    -- Create order
    insert into public.orders (company_id, order_number, customer_id, total_amount, external_order_id, notes)
    values (p_company_id, 'ORD-' || (select nextval('order_number_seq')), v_customer_id, v_total_amount, p_external_id, p_notes)
    returning id into v_order_id;

    -- Create line items and update inventory
    foreach v_item in array p_sale_items
    loop
        -- Find the variant and lock the row to prevent race conditions
        select * into v_variant from public.product_variants
        where company_id = p_company_id and sku = (v_item->>'sku')
        for update;

        if v_variant is null then
            raise exception 'Product variant with SKU % not found.', v_item->>'sku';
        end if;
        
        v_quantity_to_deduct := (v_item->>'quantity')::int;

        -- Prevent inventory from going negative
        if v_variant.inventory_quantity < v_quantity_to_deduct then
            raise exception 'Insufficient stock for SKU %. Required: %, Available: %', v_variant.sku, v_quantity_to_deduct, v_variant.inventory_quantity;
        end if;

        v_line_item_total := (v_item->>'unit_price')::int * v_quantity_to_deduct;

        insert into public.order_line_items (order_id, company_id, variant_id, product_name, sku, quantity, price, cost_at_time)
        values (v_order_id, p_company_id, v_variant.id, v_item->>'product_name', v_variant.sku, v_quantity_to_deduct, v_item->>'unit_price'::int, v_item->>'cost_at_time'::int);

        update public.product_variants
        set inventory_quantity = inventory_quantity - v_quantity_to_deduct
        where id = v_variant.id;
        
        insert into public.inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes)
        values (p_company_id, v_variant.id, 'sale', -v_quantity_to_deduct, v_variant.inventory_quantity - v_quantity_to_deduct, v_order_id, 'Order ' || p_external_id);

    end loop;

    return v_order_id;
end;
$$;


-- =================================================================
-- Step 5: Row-Level Security (RLS)
-- =================================================================

-- Helper function to get the current user's company_id
create or replace function public.get_company_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select nullif(current_setting('app.current_company_id', true), '')::uuid;
$$;


-- Procedure to enable RLS on a table if it exists
create or replace procedure public.enable_rls_on_table(p_table_name text)
language plpgsql
as $$
begin
  if exists (select 1 from pg_tables where schemaname = 'public' and tablename = p_table_name) then
    execute format('alter table public.%I enable row level security', p_table_name);
    execute format('alter table public.%I force row level security', p_table_name);
  end if;
end;
$$;

-- Procedure to apply all RLS policies
create or replace procedure public.apply_rls_policies()
language plpgsql
as $$
declare
  r record;
begin
  -- Drop existing policies to ensure a clean slate
  for r in (select policyname, tablename from pg_policies where schemaname = 'public')
  loop
    execute 'DROP POLICY IF EXISTS ' || quote_ident(r.policyname) || ' ON public.' || quote_ident(r.tablename);
  end loop;

  -- Apply policies to all tables
  create policy "Allow all access to own company data" on public.companies
    for all using (id = get_company_id());

  create policy "Allow all access to own company data" on public.users
    for all using (company_id = get_company_id());
  
  create policy "Allow all access to own company data" on public.company_settings
    for all using (company_id = get_company_id());

  create policy "Allow all access to own company data" on public.products
    for all using (company_id = get_company_id());
    
  create policy "Allow all access to own company data" on public.product_variants
    for all using (company_id = get_company_id());
    
  create policy "Allow all access to own company data" on public.inventory_ledger
    for all using (company_id = get_company_id());

  create policy "Allow all access to own company data" on public.orders
    for all using (company_id = get_company_id());

  create policy "Allow all access to own company data" on public.order_line_items
    for all using (company_id = get_company_id());
    
  create policy "Allow all access to own company data" on public.customers
    for all using (company_id = get_company_id());

  create policy "Allow all access to own company data" on public.suppliers
    for all using (company_id = get_company_id());
    
  create policy "Allow all access to own company data" on public.purchase_orders
    for all using (company_id = get_company_id());
    
  create policy "Allow all access to own company data" on public.purchase_order_line_items
    for all using (company_id = get_company_id());

  create policy "Allow all access to own company data" on public.integrations
    for all using (company_id = get_company_id());
    
  create policy "Allow all access to own company data" on public.conversations
    for all using (company_id = get_company_id());

  create policy "Allow all access to own company data" on public.messages
    for all using (company_id = get_company_id());

  create policy "Allow all access to own company data" on public.webhook_events
    for all using (integration_id in (select id from public.integrations where company_id = get_company_id()));

  -- Enable RLS on all tables
  for r in (
      select tablename from pg_tables where schemaname = 'public'
  )
  loop
    call public.enable_rls_on_table(r.tablename);
  end loop;

end;
$$;

-- Execute the procedure to apply all policies
call public.apply_rls_policies();

-- =================================================================
-- Final: Grant usage on schema to authenticated users
-- =================================================================
grant usage on schema public to authenticated;
grant all on all tables in schema public to authenticated;
grant all on all functions in schema public to authenticated;
grant all on all sequences in schema public to authenticated;

alter default privileges in schema public grant all on tables to authenticated;
alter default privileges in schema public grant all on functions to authenticated;
alter default privileges in schema public grant all on sequences to authenticated;

-- Make sure anon role cannot access public tables by default
revoke all on schema public from anon;
revoke all on all tables in schema public from anon;

-- But grant anon access to the handle_new_user function which it needs to create an account
grant execute on function public.handle_new_user() to anon;
