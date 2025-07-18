-- Enable UUID generation
create extension if not exists "uuid-ossp";

-- Custom Types
do $$
begin
    if not exists (select 1 from pg_type where typname = 'user_role') then
        create type public.user_role as enum ('Owner', 'Admin', 'Member');
    end if;
end$$;


-- Grant access to schemas for the postgres user
grant all on schema public to postgres;
grant all on schema auth to postgres;
grant all on schema storage to postgres;
grant all on schema vault to postgres;

-- COMPANIES
create table if not exists public.companies (
    id uuid primary key default uuid_generate_v4(),
    name text not null,
    created_at timestamptz not null default now()
);
-- RLS for companies
alter table public.companies enable row level security;
drop policy if exists "Allow users to see their own company" on public.companies;
create policy "Allow users to see their own company"
on public.companies for select
using (auth.jwt()->>'company_id' is not null and id = (auth.jwt()->>'company_id')::uuid);


-- USERS (public facing user profiles)
create table if not exists public.users (
    id uuid primary key references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    email text,
    role public.user_role default 'Member',
    deleted_at timestamptz,
    created_at timestamptz default now()
);
-- RLS for users
alter table public.users enable row level security;
drop policy if exists "Allow users to see other members of their company" on public.users;
create policy "Allow users to see other members of their company"
on public.users for select
using (auth.jwt()->>'company_id' is not null and company_id = (auth.jwt()->>'company_id')::uuid);
drop policy if exists "Allow owner to manage their company members" on public.users;
create policy "Allow owner to manage their company members"
on public.users for all
using (
    auth.jwt()->>'company_id' is not null AND
    company_id = (auth.jwt()->>'company_id')::uuid AND
    (select role from public.users where id = auth.uid()) = 'Owner'
);


-- COMPANY_SETTINGS
create table if not exists public.company_settings (
    company_id uuid primary key references public.companies(id) on delete cascade,
    dead_stock_days int not null default 90,
    fast_moving_days int not null default 30,
    overstock_multiplier int not null default 3,
    high_value_threshold int not null default 100000, -- in cents
    predictive_stock_days int not null default 7,
    currency text default 'USD',
    timezone text default 'UTC',
    tax_rate numeric default 0,
    custom_rules jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz,
    -- Stripe specific fields
    subscription_status text default 'trial',
    subscription_plan text default 'starter',
    subscription_expires_at timestamptz,
    stripe_customer_id text,
    stripe_subscription_id text,
    -- AI specific settings
    promo_sales_lift_multiplier real not null default 2.5
);
-- RLS for company_settings
alter table public.company_settings enable row level security;
drop policy if exists "Allow users to manage their own company settings" on public.company_settings;
create policy "Allow users to manage their own company settings"
on public.company_settings for all
using (auth.jwt()->>'company_id' is not null and company_id = (auth.jwt()->>'company_id')::uuid);


-- PRODUCTS
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
    deleted_at timestamptz
);
create index if not exists idx_products_company_id on public.products(company_id);
create index if not exists idx_products_external_id on public.products(external_product_id);
alter table public.products drop constraint if exists products_company_id_external_product_id_key;
alter table public.products add constraint products_company_id_external_product_id_key unique (company_id, external_product_id);

-- RLS for products
alter table public.products enable row level security;
drop policy if exists "Allow users to manage their own company products" on public.products;
create policy "Allow users to manage their own company products"
on public.products for all
using (auth.jwt()->>'company_id' is not null and company_id = (auth.jwt()->>'company_id')::uuid);


-- PRODUCT_VARIANTS
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
    price int, -- in cents
    compare_at_price int, -- in cents
    cost int, -- in cents
    inventory_quantity int not null default 0,
    location text,
    external_variant_id text,
    created_at timestamptz default now(),
    updated_at timestamptz default now(),
    deleted_at timestamptz
);
create index if not exists idx_variants_product_id on public.product_variants(product_id);
create index if not exists idx_variants_sku_company_id on public.product_variants(sku, company_id);
alter table public.product_variants drop constraint if exists product_variants_company_id_sku_key;
alter table public.product_variants add constraint product_variants_company_id_sku_key unique (company_id, sku);
alter table public.product_variants drop constraint if exists product_variants_company_id_external_variant_id_key;
alter table public.product_variants add constraint product_variants_company_id_external_variant_id_key unique(company_id, external_variant_id);

-- RLS for product_variants
alter table public.product_variants enable row level security;
drop policy if exists "Allow users to manage their own company variants" on public.product_variants;
create policy "Allow users to manage their own company variants"
on public.product_variants for all
using (auth.jwt()->>'company_id' is not null and company_id = (auth.jwt()->>'company_id')::uuid);

-- VIEWS
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
    pv.location,
    pv.external_variant_id,
    pv.created_at,
    pv.updated_at,
    pv.deleted_at,
    p.title as product_title,
    p.status as product_status,
    p.image_url
from
    public.product_variants pv
join
    public.products p on pv.product_id = p.id
where
    p.deleted_at is null;


-- SUPPLIERS
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
-- RLS for suppliers
alter table public.suppliers enable row level security;
drop policy if exists "Allow users to manage their own company suppliers" on public.suppliers;
create policy "Allow users to manage their own company suppliers"
on public.suppliers for all
using (auth.jwt()->>'company_id' is not null and company_id = (auth.jwt()->>'company_id')::uuid);


-- INTEGRATIONS
create table if not exists public.integrations (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    platform text not null, -- e.g., 'shopify', 'woocommerce'
    shop_domain text,
    shop_name text,
    is_active boolean default false,
    last_sync_at timestamptz,
    sync_status text, -- e.g., 'syncing', 'success', 'failed'
    created_at timestamptz not null default now(),
    updated_at timestamptz
);
alter table public.integrations drop constraint if exists integrations_company_id_platform_key;
alter table public.integrations add constraint integrations_company_id_platform_key unique (company_id, platform);
-- RLS for integrations
alter table public.integrations enable row level security;
drop policy if exists "Allow users to manage their own company integrations" on public.integrations;
create policy "Allow users to manage their own company integrations"
on public.integrations for all
using (auth.jwt()->>'company_id' is not null and company_id = (auth.jwt()->>'company_id')::uuid);

-- CONVERSATIONS & MESSAGES (For AI Chat)
create table if not exists public.conversations (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid not null references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    title text not null,
    created_at timestamptz default now(),
    last_accessed_at timestamptz default now(),
    is_starred boolean default false
);
-- RLS for conversations
alter table public.conversations enable row level security;
drop policy if exists "Allow users to manage their own conversations" on public.conversations;
create policy "Allow users to manage their own conversations"
on public.conversations for all
using (auth.uid() = user_id);

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
-- RLS for messages
alter table public.messages enable row level security;
drop policy if exists "Allow users to manage their own messages" on public.messages;
create policy "Allow users to manage their own messages"
on public.messages for all
using (exists (select 1 from conversations where id = conversation_id and user_id = auth.uid()));


-- WEBHOOK_EVENTS (For preventing replay attacks)
create table if not exists public.webhook_events (
    id uuid primary key default gen_random_uuid(),
    integration_id uuid not null references public.integrations(id) on delete cascade,
    webhook_id text not null,
    processed_at timestamptz default now(),
    created_at timestamptz default now()
);
alter table public.webhook_events drop constraint if exists webhook_events_integration_id_webhook_id_key;
alter table public.webhook_events add constraint webhook_events_integration_id_webhook_id_key unique (integration_id, webhook_id);

-- Helper functions to get user ID and company ID from JWT
create or replace function auth.get_user_id()
returns uuid
language sql stable
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

create or replace function auth.get_company_id()
returns uuid
language sql stable
as $$
  select nullif(current_setting('request.jwt.claim.company_id', true), '')::uuid;
$$;


-- This function handles the creation of a new company and user profile
-- when a new user signs up via Supabase Auth.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer -- This is crucial to allow the function to write to tables
set search_path = public
as $$
declare
  new_company_id uuid;
  new_user_email text;
  company_name text;
begin
  -- Extract user email and desired company name from auth.users
  select raw_user_meta_data->>'company_name', email into company_name, new_user_email from auth.users where id = new.id;

  -- Create a new company for the user
  insert into public.companies (name)
  values (coalesce(company_name, 'My Company'))
  returning id into new_company_id;

  -- Create a user profile in the public.users table
  insert into public.users (id, company_id, email, role)
  values (new.id, new_company_id, new_user_email, 'Owner');

  -- Update the user's app_metadata in auth.users to include the new company_id
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'role', 'Owner')
  where id = new.id;

  return new;
end;
$$;

-- Drop the trigger if it already exists to ensure idempotency
drop trigger if exists on_auth_user_created on auth.users;

-- Create the trigger that calls the function after a new user is created
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


grant execute on function public.handle_new_user() to postgres;
grant all on table public.companies to postgres;
grant all on table public.users to postgres;

-- Dummy tables for PRD features not yet implemented
create table if not exists public.orders (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    order_number text not null,
    external_order_id text,
    customer_id uuid, -- no reference yet
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
alter table public.orders enable row level security;
drop policy if exists "Allow users to manage their own company orders" on public.orders;
create policy "Allow users to manage their own company orders"
on public.orders for all
using (auth.jwt()->>'company_id' is not null and company_id = (auth.jwt()->>'company_id')::uuid);


create table if not exists public.order_line_items (
    id uuid primary key default gen_random_uuid(),
    order_id uuid not null references public.orders(id) on delete cascade,
    company_id uuid not null,
    product_id uuid not null, -- references public.products
    variant_id uuid not null, -- references public.product_variants
    product_name text not null,
    variant_title text,
    sku text not null,
    quantity int not null,
    price int not null,
    total_discount int default 0,
    tax_amount int default 0,
    cost_at_time int,
    fulfillment_status text default 'unfulfilled',
    requires_shipping boolean default true,
    external_line_item_id text
);
alter table public.order_line_items enable row level security;
drop policy if exists "Allow users to manage their own company order lines" on public.order_line_items;
create policy "Allow users to manage their own company order lines"
on public.order_line_items for all
using (auth.jwt()->>'company_id' is not null and company_id = (auth.jwt()->>'company_id')::uuid);


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
alter table public.customers enable row level security;
drop policy if exists "Allow users to manage their own company customers" on public.customers;
create policy "Allow users to manage their own company customers"
on public.customers for all
using (auth.jwt()->>'company_id' is not null and company_id = (auth.jwt()->>'company_id')::uuid);


create table if not exists public.purchase_orders (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    supplier_id uuid references public.suppliers(id),
    status text not null default 'Draft',
    po_number text not null,
    total_cost int not null, -- in cents
    expected_arrival_date date,
    created_at timestamptz not null default now(),
    idempotency_key uuid
);
alter table public.purchase_orders enable row level security;
drop policy if exists "Allow users to manage their own company purchase orders" on public.purchase_orders;
create policy "Allow users to manage their own company purchase orders"
on public.purchase_orders for all
using (auth.jwt()->>'company_id' is not null and company_id = (auth.jwt()->>'company_id')::uuid);


create table if not exists public.purchase_order_line_items (
    id uuid primary key default uuid_generate_v4(),
    purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
    company_id uuid not null,
    variant_id uuid not null references public.product_variants(id),
    quantity int not null,
    cost int not null -- in cents
);
alter table public.purchase_order_line_items enable row level security;
drop policy if exists "Allow users to manage their own company PO lines" on public.purchase_order_line_items;
create policy "Allow users to manage their own company PO lines"
on public.purchase_order_line_items for all
using (auth.jwt()->>'company_id' is not null and company_id = (auth.jwt()->>'company_id')::uuid);


create table if not exists public.inventory_ledger (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    change_type text not null, -- sale, purchase_order, reconciliation, manual_adjustment
    quantity_change int not null,
    new_quantity int not null,
    related_id uuid, -- e.g., order_id, purchase_order_id
    notes text,
    created_at timestamptz not null default now()
);
alter table public.inventory_ledger enable row level security;
drop policy if exists "Allow users to manage their own company inventory ledger" on public.inventory_ledger;
create policy "Allow users to manage their own company inventory ledger"
on public.inventory_ledger for all
using (auth.jwt()->>'company_id' is not null and company_id = (auth.jwt()->>'company_id')::uuid);


-- More dummy tables
create table if not exists public.discounts (id uuid primary key default gen_random_uuid(), company_id uuid not null, code text not null, type text not null, value int not null, minimum_purchase int, usage_limit int, usage_count int default 0, applies_to text default 'all', starts_at timestamptz, ends_at timestamptz, is_active boolean default true, created_at timestamptz default now());
create table if not exists public.customer_addresses (id uuid primary key default gen_random_uuid(), customer_id uuid not null, address_type text not null default 'shipping', first_name text, last_name text, company text, address1 text, address2 text, city text, province_code text, country_code text, zip text, phone text, is_default boolean default false);
create table if not exists public.refunds (id uuid primary key default gen_random_uuid(), company_id uuid not null, order_id uuid not null, refund_number text not null, status text not null default 'pending', reason text, note text, total_amount int not null, created_by_user_id uuid, external_refund_id text, created_at timestamptz default now());
create table if not exists public.refund_line_items (id uuid primary key default gen_random_uuid(), refund_id uuid not null, order_line_item_id uuid not null, quantity int not null, amount int not null, restock boolean default true, company_id uuid not null);
create table if not exists public.audit_log (id bigserial primary key, company_id uuid, user_id uuid, action text not null, details jsonb, created_at timestamptz default now());
create table if not exists public.export_jobs (id uuid primary key default uuid_generate_v4(), company_id uuid not null, requested_by_user_id uuid not null, status text not null default 'pending', download_url text, expires_at timestamptz, created_at timestamptz not null default now());
create table if not exists public.channel_fees (id uuid primary key default uuid_generate_v4(), company_id uuid not null references public.companies(id), channel_name text not null, percentage_fee numeric not null, fixed_fee numeric not null, created_at timestamptz default now(), updated_at timestamptz);

-- Views
create or replace view public.customers_view as
select
    c.id,
    c.company_id,
    c.customer_name,
    c.email,
    coalesce(o.total_orders, 0) as total_orders,
    coalesce(o.total_spent, 0) as total_spent,
    c.first_order_date,
    c.created_at
from
    public.customers c
left join (
    select
        customer_id,
        count(*) as total_orders,
        sum(total_amount) as total_spent
    from
        public.orders
    group by
        customer_id
) o on c.id = o.customer_id
where c.deleted_at is null;


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
