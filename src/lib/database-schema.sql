-- Grant access to the 'postgres' role for the auth schema
grant usage on schema auth to postgres;
grant all on all tables in schema auth to postgres;
grant all on all sequences in schema auth to postgres;
grant all on all functions in schema auth to postgres;

-- Enable UUID generation
create extension if not exists "uuid-ossp";

-- Custom Types
do $$
begin
    if not exists (select 1 from pg_type where typname = 'user_role') then
        create type public.user_role as enum ('Owner', 'Admin', 'Member');
    end if;
end$$;


-- #################################################################
--                         CORE DATA TABLES
-- #################################################################

create table if not exists public.companies (
    id uuid primary key default uuid_generate_v4(),
    name text not null,
    created_at timestamptz not null default now()
);

create table if not exists public.users (
    id uuid primary key references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    email text,
    role public.user_role not null default 'Member',
    deleted_at timestamptz,
    created_at timestamptz default now()
);

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
    overstock_multiplier integer not null default 3,
    high_value_threshold integer not null default 100000 -- in cents
);

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
    fts_document tsvector,
    deleted_at timestamptz
);

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
alter table public.product_variants drop constraint if exists product_variants_company_id_sku_key;
alter table public.product_variants add constraint product_variants_company_id_sku_key unique (company_id, sku);

create table if not exists public.inventory_ledger (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    change_type text not null,
    quantity_change int not null,
    new_quantity int not null,
    related_id uuid, -- e.g., order_id, purchase_order_id, etc.
    notes text,
    created_at timestamptz not null default now()
);

create table if not exists public.purchase_orders (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    supplier_id uuid references public.suppliers(id) on delete set null,
    status text not null default 'Draft',
    po_number text not null,
    total_cost int not null,
    expected_arrival_date date,
    idempotency_key uuid,
    created_at timestamptz not null default now()
);

create table if not exists public.purchase_order_line_items (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    quantity integer not null,
    cost integer not null
);

create table if not exists public.orders (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
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
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    order_id uuid not null references public.orders(id) on delete cascade,
    product_id uuid not null references public.products(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
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
    updated_at timestamptz
);
alter table public.integrations drop constraint if exists integrations_company_id_platform_key;
alter table public.integrations add constraint integrations_company_id_platform_key unique(company_id, platform);

create table if not exists public.conversations (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid not null references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    title text not null,
    created_at timestamptz default now(),
    last_accessed_at timestamptz default now(),
    is_starred boolean default false
);

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

create table if not exists public.customers (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    customer_name text not null,
    email text,
    total_orders int default 0,
    total_spent int default 0,
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz default now()
);

create table if not exists public.channel_fees (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    channel_name text not null,
    percentage_fee numeric not null,
    fixed_fee numeric not null,
    created_at timestamptz default now(),
    updated_at timestamptz
);
alter table public.channel_fees drop constraint if exists channel_fees_company_id_channel_name_key;
alter table public.channel_fees add constraint channel_fees_company_id_channel_name_key unique(company_id, channel_name);

create table if not exists public.webhook_events (
    id uuid primary key default gen_random_uuid(),
    integration_id uuid not null references public.integrations(id) on delete cascade,
    webhook_id text not null,
    processed_at timestamptz default now(),
    created_at timestamptz default now(),
    unique(integration_id, webhook_id)
);


-- #################################################################
--                     RLS & SECURITY POLICIES
-- #################################################################
alter table public.companies enable row level security;
alter table public.users enable row level security;
alter table public.company_settings enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.suppliers enable row level security;
alter table public.integrations enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.orders enable row level security;
alter table public.order_line_items enable row level security;
alter table public.inventory_ledger enable row level security;
alter table public.customers enable row level security;
alter table public.purchase_orders enable row level security;
alter table public.purchase_order_line_items enable row level security;
alter table public.channel_fees enable row level security;
alter table public.webhook_events enable row level security;

-- Utility Functions
create or replace function public.get_user_id()
returns uuid
language sql stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'sub', '')::uuid;
$$;

create or replace function public.get_company_id()
returns uuid
language sql stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb -> 'app_metadata' ->> 'company_id', '')::uuid;
$$;

-- RLS Policies
drop policy if exists "Allow users to see their own company" on public.companies;
create policy "Allow users to see their own company" on public.companies
for select using (id = public.get_company_id());

drop policy if exists "Allow users to see team members in their own company" on public.users;
create policy "Allow users to see team members in their own company" on public.users
for select using (company_id = public.get_company_id());

drop policy if exists "Allow users to manage settings for their own company" on public.company_settings;
create policy "Allow users to manage settings for their own company" on public.company_settings
for all using (company_id = public.get_company_id());

drop policy if exists "Allow users to manage data for their own company" on public.products;
create policy "Allow users to manage data for their own company" on public.products
for all using (company_id = public.get_company_id());

drop policy if exists "Allow users to manage data for their own company" on public.product_variants;
create policy "Allow users to manage data for their own company" on public.product_variants
for all using (company_id = public.get_company_id());

drop policy if exists "Allow users to manage data for their own company" on public.suppliers;
create policy "Allow users to manage data for their own company" on public.suppliers
for all using (company_id = public.get_company_id());

drop policy if exists "Allow users to manage data for their own company" on public.integrations;
create policy "Allow users to manage data for their own company" on public.integrations
for all using (company_id = public.get_company_id());

drop policy if exists "Allow users to manage their own conversations" on public.conversations;
create policy "Allow users to manage their own conversations" on public.conversations
for all using (user_id = public.get_user_id());

drop policy if exists "Allow users to manage messages in their own conversations" on public.messages;
create policy "Allow users to manage messages in their own conversations" on public.messages
for all using (company_id = public.get_company_id() and conversation_id in (select id from public.conversations where user_id = public.get_user_id()));

drop policy if exists "Allow users to view all data for their company" on public.orders;
create policy "Allow users to view all data for their company" on public.orders
for all using (company_id = public.get_company_id());

drop policy if exists "Allow users to view all data for their company" on public.order_line_items;
create policy "Allow users to view all data for their company" on public.order_line_items
for all using (company_id = public.get_company_id());

drop policy if exists "Allow users to view all data for their company" on public.inventory_ledger;
create policy "Allow users to view all data for their company" on public.inventory_ledger
for all using (company_id = public.get_company_id());

drop policy if exists "Allow users to manage customers for their company" on public.customers;
create policy "Allow users to manage customers for their company" on public.customers
for all using (company_id = public.get_company_id());

drop policy if exists "Allow users to manage data for their own company" on public.purchase_orders;
create policy "Allow users to manage data for their own company" on public.purchase_orders
for all using (company_id = public.get_company_id());

drop policy if exists "Allow users to manage data for their own company" on public.purchase_order_line_items;
create policy "Allow users to manage data for their own company" on public.purchase_order_line_items
for all using (company_id = public.get_company_id());

drop policy if exists "Allow users to manage channel fees for their company" on public.channel_fees;
create policy "Allow users to manage channel fees for their company" on public.channel_fees
for all using (company_id = public.get_company_id());

drop policy if exists "Allow users to manage webhook events for their company" on public.webhook_events;
create policy "Allow users to manage webhook events for their company" on public.webhook_events
for all using (integration_id in (select id from public.integrations where company_id = public.get_company_id()));


-- #################################################################
--                     TRIGGERS AND FUNCTIONS
-- #################################################################

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer -- This is crucial for it to have permission to write to public tables
set search_path = public
as $$
declare
  new_company_id uuid;
  user_company_name text;
begin
  -- Extract company name from auth.users metadata
  user_company_name := new.raw_app_meta_data ->> 'company_name';
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
  
  -- Create default settings for the new company
  insert into public.company_settings (company_id)
  values (new_company_id);

  -- Update the user's app_metadata in auth.users to include the new company_id
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'role', 'Owner')
  where id = new.id;
  
  return new;
end;
$$;

-- Drop the trigger if it already exists
drop trigger if exists on_auth_user_created on auth.users;

-- Create the trigger to fire after a new user is created in auth.users
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


create or replace function public.check_user_permission(p_user_id uuid, p_required_role text)
returns boolean
language plpgsql
security definer
as $$
declare
    user_role_text text;
begin
    select role into user_role_text from public.users where id = p_user_id;

    if user_role_text is null then
        return false; -- User not found in public.users
    end if;

    if p_required_role = 'Owner' then
        return user_role_text = 'Owner';
    elsif p_required_role = 'Admin' then
        return user_role_text in ('Owner', 'Admin');
    end if;
    
    return false;
end;
$$;

-- Example of a function for batch upserting (more performant than individual inserts)
create or replace function public.batch_upsert_costs(p_records jsonb, p_company_id uuid, p_user_id uuid)
returns void
language plpgsql
as $$
begin
    -- This function would contain logic to loop through p_records and upsert into product_variants
    -- It is a placeholder to show the pattern. A full implementation would parse the JSON
    -- and perform an UPDATE/INSERT operation.
    -- For now, this is handled by the application logic calling the db.
end;
$$;

-- #################################################################
--                           VIEWS
-- #################################################################

create or replace view public.product_variants_with_details as
select
    pv.*,
    p.title as product_title,
    p.status as product_status,
    p.image_url
from
    public.product_variants pv
join
    public.products p on pv.product_id = p.id
where
    p.deleted_at is null and pv.deleted_at is null;


create or replace view public.customers_view as
select
    c.*,
    (select count(*) from public.orders o where o.customer_id = c.id) as total_orders,
    (select sum(total_amount) from public.orders o where o.customer_id = c.id) as total_spent,
    (select min(created_at) from public.orders o where o.customer_id = c.id)::date as first_order_date
from
    public.customers c
where
    c.deleted_at is null;


create or replace view public.orders_view as
select
    o.*,
    c.email as customer_email
from
    public.orders o
left join
    public.customers c on o.customer_id = c.id;


-- Grant usage on the new views to the authenticated role
grant select on public.product_variants_with_details to authenticated;
grant select on public.customers_view to authenticated;
grant select on public.orders_view to authenticated;
