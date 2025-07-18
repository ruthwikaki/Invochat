
-- ===============================================================================================
-- 1. UTILITY FUNCTIONS
-- ===============================================================================================

-- Helper function to get the company ID from the JWT claims.
-- Note: We cast to UUID to ensure type safety.
create or replace function get_company_id()
returns uuid
language sql
as $$
  select (auth.jwt()->>'company_id')::uuid
$$;

-- Helper function to get the user ID from the JWT claims.
create or replace function get_user_id()
returns uuid
language sql
as $$
  select (auth.jwt()->>'sub')::uuid
$$;


-- ===============================================================================================
-- 2. ENABLE EXTENSIONS
-- ===============================================================================================
create extension if not exists "uuid-ossp" with schema public;
create extension if not exists pgcrypto with schema public;


-- ===============================================================================================
-- 3. PERMISSIONS & AUTHORIZATION
-- ===============================================================================================
-- These grants are necessary for the handle_new_user function and other logic to work correctly.
-- Grant usage on the auth schema to the postgres role
grant usage on schema auth to postgres;
-- Grant all privileges on all tables in the auth schema to the postgres role
grant all on all tables in schema auth to postgres;
-- Grant all privileges on all functions in the auth schema to the postgres role
grant all on all functions in schema auth to postgres;
-- Grant all privileges on all sequences in the auth schema to the postgres role
grant all on all sequences in schema auth to postgres;


-- =A. CREATE USER ROLE TYPE
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        create type public.user_role as enum ('Owner', 'Admin', 'Member');
    END IF;
END
$$;

-- ===============================================================================================
-- 4. TABLES
-- ===============================================================================================
-- Note: Tables are created without foreign keys initially to avoid order-of-creation issues.
-- Foreign keys are added in a separate section at the end.

create table if not exists public.companies (
    id uuid not null primary key default uuid_generate_v4(),
    name text not null,
    created_at timestamptz not null default now()
);

create table if not exists public.users (
    id uuid references auth.users(id) not null primary key,
    company_id uuid not null,
    email text,
    role user_role not null default 'Member',
    deleted_at timestamptz,
    created_at timestamptz default now()
);

create table if not exists public.products (
    id uuid not null primary key default uuid_generate_v4(),
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
    fts_document tsvector,
    deleted_at timestamptz
);

create table if not exists public.product_variants (
    id uuid not null primary key default gen_random_uuid(),
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
    price int,
    compare_at_price int,
    cost int,
    inventory_quantity int not null default 0,
    location text,
    external_variant_id text,
    created_at timestamptz default now(),
    updated_at timestamptz default now(),
    deleted_at timestamptz
);

create table if not exists public.suppliers (
    id uuid not null primary key default uuid_generate_v4(),
    company_id uuid not null,
    name text not null,
    email text,
    phone text,
    default_lead_time_days int,
    notes text,
    created_at timestamptz not null default now()
);

create table if not exists public.purchase_orders (
    id uuid not null primary key default uuid_generate_v4(),
    company_id uuid not null,
    supplier_id uuid,
    status text not null default 'Draft',
    po_number text not null,
    total_cost int not null,
    expected_arrival_date date,
    idempotency_key uuid,
    created_at timestamptz not null default now()
);

create table if not exists public.purchase_order_line_items (
    id uuid not null primary key default uuid_generate_v4(),
    purchase_order_id uuid not null,
    company_id uuid not null,
    variant_id uuid not null,
    quantity int not null,
    cost int not null
);

create table if not exists public.customers (
    id uuid not null primary key default uuid_generate_v4(),
    company_id uuid not null,
    customer_name text not null,
    email text,
    total_orders int default 0,
    total_spent int default 0,
    first_order_date date,
    created_at timestamptz default now(),
    deleted_at timestamptz
);

create table if not exists public.orders (
    id uuid not null primary key default gen_random_uuid(),
    company_id uuid not null,
    order_number text not null,
    external_order_id text,
    customer_id uuid,
    financial_status text default 'pending',
    fulfillment_status text default 'unfulfilled',
    currency text default 'USD',
    subtotal int not null default 0,
    total_tax int default 0,
    total_shipping int default 0,
    total_discounts int default 0,
    total_amount int not null,
    source_platform text,
    source_name text,
    tags text[],
    notes text,
    cancelled_at timestamptz,
    created_at timestamptz default now(),
    updated_at timestamptz default now()
);

create table if not exists public.order_line_items (
    id uuid not null primary key default gen_random_uuid(),
    company_id uuid not null,
    order_id uuid not null,
    product_id uuid not null,
    variant_id uuid not null,
    product_name text not null,
    variant_title text,
    sku text not null,
    quantity int not null,
    price int not null,
    cost_at_time int,
    total_discount int default 0,
    tax_amount int default 0,
    fulfillment_status text default 'unfulfilled',
    requires_shipping boolean default true,
    external_line_item_id text
);

create table if not exists public.inventory_ledger (
    id uuid not null primary key default gen_random_uuid(),
    company_id uuid not null,
    variant_id uuid not null,
    change_type text not null,
    quantity_change int not null,
    new_quantity int not null,
    related_id uuid,
    notes text,
    created_at timestamptz not null default now()
);

create table if not exists public.integrations (
    id uuid not null primary key default uuid_generate_v4(),
    company_id uuid not null,
    platform text not null,
    shop_domain text,
    shop_name text,
    is_active boolean default false,
    last_sync_at timestamptz,
    sync_status text,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);

create table if not exists public.company_settings (
    company_id uuid not null primary key,
    dead_stock_days int not null default 90,
    fast_moving_days int not null default 30,
    overstock_multiplier int not null default 3,
    high_value_threshold int not null default 1000,
    predictive_stock_days int not null default 7,
    currency text default 'USD',
    timezone text default 'UTC',
    tax_rate numeric default 0,
    custom_rules jsonb,
    subscription_status text default 'trial',
    subscription_plan text default 'starter',
    subscription_expires_at timestamptz,
    stripe_customer_id text,
    stripe_subscription_id text,
    promo_sales_lift_multiplier real not null default 2.5,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);

create table if not exists public.conversations (
    id uuid not null primary key default uuid_generate_v4(),
    user_id uuid not null,
    company_id uuid not null,
    title text not null,
    is_starred boolean default false,
    created_at timestamptz default now(),
    last_accessed_at timestamptz default now()
);

create table if not exists public.messages (
    id uuid not null primary key default uuid_generate_v4(),
    conversation_id uuid not null,
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

create table if not exists public.webhook_events (
  id uuid primary key default gen_random_uuid(),
  integration_id uuid not null,
  webhook_id text not null,
  processed_at timestamptz default now(),
  created_at timestamptz default now()
);


-- ===============================================================================================
-- 5. FOREIGN KEYS & CONSTRAINTS
-- ===============================================================================================

-- Drop constraints first to ensure idempotency
alter table public.users drop constraint if exists users_company_id_fkey;
alter table public.users add constraint users_company_id_fkey foreign key (company_id) references public.companies(id) on delete cascade;

alter table public.products drop constraint if exists products_company_id_fkey;
alter table public.products add constraint products_company_id_fkey foreign key (company_id) references public.companies(id) on delete cascade;

alter table public.product_variants drop constraint if exists product_variants_product_id_fkey;
alter table public.product_variants add constraint product_variants_product_id_fkey foreign key (product_id) references public.products(id) on delete cascade;
alter table public.product_variants drop constraint if exists product_variants_company_id_fkey;
alter table public.product_variants add constraint product_variants_company_id_fkey foreign key (company_id) references public.companies(id) on delete cascade;
alter table public.product_variants drop constraint if exists product_variants_sku_company_id_unique;
alter table public.product_variants add constraint product_variants_sku_company_id_unique unique (sku, company_id);

alter table public.suppliers drop constraint if exists suppliers_company_id_fkey;
alter table public.suppliers add constraint suppliers_company_id_fkey foreign key (company_id) references public.companies(id) on delete cascade;

alter table public.purchase_orders drop constraint if exists purchase_orders_company_id_fkey;
alter table public.purchase_orders add constraint purchase_orders_company_id_fkey foreign key (company_id) references public.companies(id) on delete cascade;
alter table public.purchase_orders drop constraint if exists purchase_orders_supplier_id_fkey;
alter table public.purchase_orders add constraint purchase_orders_supplier_id_fkey foreign key (supplier_id) references public.suppliers(id) on delete set null;
alter table public.purchase_orders drop constraint if exists purchase_orders_po_number_company_id_unique;
alter table public.purchase_orders add constraint purchase_orders_po_number_company_id_unique unique(po_number, company_id);
alter table public.purchase_orders drop constraint if exists purchase_orders_idempotency_key_unique;
alter table public.purchase_orders add constraint purchase_orders_idempotency_key_unique unique (idempotency_key);

alter table public.purchase_order_line_items drop constraint if exists po_line_items_company_id_fkey;
alter table public.purchase_order_line_items add constraint po_line_items_company_id_fkey foreign key (company_id) references public.companies(id) on delete cascade;
alter table public.purchase_order_line_items drop constraint if exists po_line_items_purchase_order_id_fkey;
alter table public.purchase_order_line_items add constraint po_line_items_purchase_order_id_fkey foreign key (purchase_order_id) references public.purchase_orders(id) on delete cascade;
alter table public.purchase_order_line_items drop constraint if exists po_line_items_variant_id_fkey;
alter table public.purchase_order_line_items add constraint po_line_items_variant_id_fkey foreign key (variant_id) references public.product_variants(id) on delete cascade;

alter table public.customers drop constraint if exists customers_company_id_fkey;
alter table public.customers add constraint customers_company_id_fkey foreign key (company_id) references public.companies(id) on delete cascade;

alter table public.orders drop constraint if exists orders_company_id_fkey;
alter table public.orders add constraint orders_company_id_fkey foreign key (company_id) references public.companies(id) on delete cascade;
alter table public.orders drop constraint if exists orders_customer_id_fkey;
alter table public.orders add constraint orders_customer_id_fkey foreign key (customer_id) references public.customers(id) on delete set null;

alter table public.order_line_items drop constraint if exists line_items_company_id_fkey;
alter table public.order_line_items add constraint line_items_company_id_fkey foreign key (company_id) references public.companies(id) on delete cascade;
alter table public.order_line_items drop constraint if exists line_items_order_id_fkey;
alter table public.order_line_items add constraint line_items_order_id_fkey foreign key (order_id) references public.orders(id) on delete cascade;
alter table public.order_line_items drop constraint if exists line_items_product_id_fkey;
alter table public.order_line_items add constraint line_items_product_id_fkey foreign key (product_id) references public.products(id) on delete cascade;
alter table public.order_line_items drop constraint if exists line_items_variant_id_fkey;
alter table public.order_line_items add constraint line_items_variant_id_fkey foreign key (variant_id) references public.product_variants(id) on delete cascade;

alter table public.inventory_ledger drop constraint if exists inventory_ledger_company_id_fkey;
alter table public.inventory_ledger add constraint inventory_ledger_company_id_fkey foreign key (company_id) references public.companies(id) on delete cascade;
alter table public.inventory_ledger drop constraint if exists inventory_ledger_variant_id_fkey;
alter table public.inventory_ledger add constraint inventory_ledger_variant_id_fkey foreign key (variant_id) references public.product_variants(id) on delete cascade;

alter table public.integrations drop constraint if exists integrations_company_id_fkey;
alter table public.integrations add constraint integrations_company_id_fkey foreign key (company_id) references public.companies(id) on delete cascade;
alter table public.integrations drop constraint if exists integrations_company_id_platform_key;
alter table public.integrations add constraint integrations_company_id_platform_key unique(company_id, platform);

alter table public.company_settings drop constraint if exists company_settings_company_id_fkey;
alter table public.company_settings add constraint company_settings_company_id_fkey foreign key (company_id) references public.companies(id) on delete cascade;

alter table public.conversations drop constraint if exists conversations_user_id_fkey;
alter table public.conversations add constraint conversations_user_id_fkey foreign key (user_id) references auth.users(id) on delete cascade;
alter table public.conversations drop constraint if exists conversations_company_id_fkey;
alter table public.conversations add constraint conversations_company_id_fkey foreign key (company_id) references public.companies(id) on delete cascade;

alter table public.messages drop constraint if exists messages_conversation_id_fkey;
alter table public.messages add constraint messages_conversation_id_fkey foreign key (conversation_id) references public.conversations(id) on delete cascade;
alter table public.messages drop constraint if exists messages_company_id_fkey;
alter table public.messages add constraint messages_company_id_fkey foreign key (company_id) references public.companies(id) on delete cascade;

alter table public.webhook_events drop constraint if exists webhook_events_integration_id_fkey;
alter table public.webhook_events add constraint webhook_events_integration_id_fkey foreign key (integration_id) references public.integrations(id) on delete cascade;
alter table public.webhook_events drop constraint if exists webhook_events_integration_id_webhook_id_key;
alter table public.webhook_events add constraint webhook_events_integration_id_webhook_id_key unique (integration_id, webhook_id);

-- ===============================================================================================
-- 6. VIEWS
-- ===============================================================================================

create or replace view public.product_variants_with_details as
select
    pv.id,
    pv.product_id,
    pv.company_id,
    pv.sku,
    pv.title,
    pv.option1_name,
    pv.option1_value,
    pv.option2_name,
    pv.option2_value,
    pv.option3_name,
    pv.option3_value,
    pv.barcode,
    pv.price,
    pv.compare_at_price,
    pv.cost,
    pv.inventory_quantity,
    pv.external_variant_id,
    pv.location,
    pv.created_at,
    pv.updated_at,
    pv.deleted_at,
    p.title as product_title,
    p.status as product_status,
    p.image_url as image_url,
    p.product_type as product_type
from
    public.product_variants pv
join
    public.products p on pv.product_id = p.id;

create or replace view public.orders_view as
select
    o.id,
    o.company_id,
    o.order_number,
    o.created_at,
    o.financial_status,
    o.fulfillment_status,
    o.total_amount,
    o.source_platform,
    c.email as customer_email
from
    public.orders o
left join
    public.customers c on o.customer_id = c.id;

create or replace view public.customers_view as
select
    c.id,
    c.company_id,
    c.customer_name,
    c.email,
    c.first_order_date,
    c.created_at,
    coalesce(count(o.id), 0)::int as total_orders,
    coalesce(sum(o.total_amount), 0)::int as total_spent
from
    public.customers c
left join
    public.orders o on c.id = o.customer_id
where
    c.deleted_at is null
group by
    c.id, c.company_id, c.customer_name, c.email;

-- ===============================================================================================
-- 7. DATABASE FUNCTIONS & TRIGGERS
-- ===============================================================================================

-- Function to handle new user setup
create or replace function public.handle_new_user()
returns trigger
language plpgsql
as $$
declare
  new_company_id uuid;
  user_email text;
  company_name text;
begin
  -- 1. Create a new company
  company_name := new.raw_app_meta_data->>'company_name';
  insert into public.companies (name)
  values (company_name)
  returning id into new_company_id;

  -- 2. Insert into our public users table
  user_email := new.email;
  insert into public.users (id, company_id, email, role)
  values (new.id, new_company_id, user_email, 'Owner');
  
  -- 3. Update the user's app_metadata with the new company_id
  new.raw_app_meta_data := new.raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'role', 'Owner');
  
  return new;
end;
$$;


-- Wrapper function with SECURITY DEFINER to create the trigger on auth.users
create or replace function public.security_definer_handle_new_user()
returns void
language plpgsql
security definer
as $$
begin
    if not exists (
        select 1
        from pg_trigger
        where tgname = 'on_auth_user_created'
    ) then
        create trigger on_auth_user_created
        before insert on auth.users
        for each row
        execute function public.handle_new_user();
    end if;
end;
$$;

-- Execute the wrapper function to create the trigger
select public.security_definer_handle_new_user();


-- ===============================================================================================
-- 8. ROW-LEVEL SECURITY (RLS) POLICIES
-- ===============================================================================================

-- Enable RLS for all tables
alter table public.companies enable row level security;
alter table public.users enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.suppliers enable row level security;
alter table public.purchase_orders enable row level security;
alter table public.purchase_order_line_items enable row level security;
alter table public.customers enable row level security;
alter table public.orders enable row level security;
alter table public.order_line_items enable row level security;
alter table public.inventory_ledger enable row level security;
alter table public.integrations enable row level security;
alter table public.company_settings enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;

-- Policies for 'companies' table
drop policy if exists "Allow users to see their own company" on public.companies;
create policy "Allow users to see their own company" on public.companies
for select using (id = get_company_id());

-- Policies for 'users' table
drop policy if exists "Allow users to see other users in their company" on public.users;
create policy "Allow users to see other users in their company" on public.users
for select using (company_id = get_company_id());
drop policy if exists "Allow owner to manage users in their company" on public.users;
create policy "Allow owner to manage users in their company" on public.users
for all using (company_id = get_company_id() and (select role from public.users where id = get_user_id()) = 'Owner');


-- Policies for all other tables (general case)
-- This macro simplifies policy creation for tables that just need company_id matching.
create or replace procedure create_rls_policy_if_not_exists(table_name_param text)
language plpgsql
as $$
declare
  policy_name_select text;
  policy_name_insert text;
  policy_name_update text;
  policy_name_delete text;
begin
  policy_name_select := 'Allow select access to own company data on ' || table_name_param;
  policy_name_insert := 'Allow insert access to own company data on ' || table_name_param;
  policy_name_update := 'Allow update access to own company data on ' || table_name_param;
  policy_name_delete := 'Allow delete access to own company data on ' || table_name_param;

  -- SELECT Policy
  if not exists (select 1 from pg_policies where policyname = policy_name_select and tablename = table_name_param) then
    execute format('create policy "%s" on public.%I for select using (company_id = get_company_id())', policy_name_select, table_name_param);
  end if;

  -- INSERT Policy
  if not exists (select 1 from pg_policies where policyname = policy_name_insert and tablename = table_name_param) then
    execute format('create policy "%s" on public.%I for insert with check (company_id = get_company_id())', policy_name_insert, table_name_param);
  end if;

  -- UPDATE Policy
  if not exists (select 1 from pg_policies where policyname = policy_name_update and tablename = table_name_param) then
    execute format('create policy "%s" on public.%I for update using (company_id = get_company_id())', policy_name_update, table_name_param);
  end if;

  -- DELETE Policy
  if not exists (select 1 from pg_policies where policyname = policy_name_delete and tablename = table_name_param) then
    execute format('create policy "%s" on public.%I for delete using (company_id = get_company_id())', policy_name_delete, table_name_param);
  end if;
end;
$$;

-- Apply the generic RLS policies to all relevant tables
call create_rls_policy_if_not_exists('products');
call create_rls_policy_if_not_exists('product_variants');
call create_rls_policy_if_not_exists('suppliers');
call create_rls_policy_if_not_exists('purchase_orders');
call create_rls_policy_if_not_exists('purchase_order_line_items');
call create_rls_policy_if_not_exists('customers');
call create_rls_policy_if_not_exists('orders');
call create_rls_policy_if_not_exists('order_line_items');
call create_rls_policy_if_not_exists('inventory_ledger');
call create_rls_policy_if_not_exists('integrations');
call create_rls_policy_if_not_exists('company_settings');

-- Policies for 'conversations' table (user-specific)
drop policy if exists "Allow users to access their own conversations" on public.conversations;
create policy "Allow users to access their own conversations" on public.conversations
for all using (user_id = get_user_id() and company_id = get_company_id());

-- Policies for 'messages' table (user-specific)
drop policy if exists "Allow users to access messages in their own conversations" on public.messages;
create policy "Allow users to access messages in their own conversations" on public.messages
for all using (company_id = get_company_id() and conversation_id in (
  select id from public.conversations where user_id = get_user_id()
));


-- Force RLS for table owners as well
alter table public.companies force row level security;
alter table public.users force row level security;
alter table public.products force row level security;
alter table public.product_variants force row level security;
alter table public.suppliers force row level security;
alter table public.purchase_orders force row level security;
alter table public.purchase_order_line_items force row level security;
alter table public.customers force row level security;
alter table public.orders force row level security;
alter table public.order_line_items force row level security;
alter table public.inventory_ledger force row level security;
alter table public.integrations force row level security;
alter table public.company_settings force row level security;
alter table public.conversations force row level security;
alter table public.messages force row level security;
