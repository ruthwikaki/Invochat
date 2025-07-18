
-- Enable UUID generation
create extension if not exists "uuid-ossp";

-- Create a custom type for user roles for better type safety
do $$
begin
    if not exists (select 1 from pg_type where typname = 'user_role') then
        create type user_role as enum ('Owner', 'Admin', 'Member');
    end if;
end$$;

-- Grant usage on the auth schema to the postgres role
grant usage on schema auth to postgres;
grant all on all tables in schema auth to postgres;
grant all on all functions in schema auth to postgres;
grant all on all sequences in schema a auth to postgres;

-- COMPANIES
create table if not exists companies (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  created_at timestamptz not null default now()
);

-- USER PROFILES
create table if not exists users (
  id uuid primary key references auth.users(id) not null,
  company_id uuid references companies(id) on delete cascade not null,
  email text,
  role user_role not null default 'Member',
  deleted_at timestamz,
  created_at timestamptz default now()
);

-- COMPANY SETTINGS
create table if not exists company_settings (
  company_id uuid primary key references companies(id) on delete cascade not null,
  dead_stock_days int not null default 90,
  fast_moving_days int not null default 30,
  overstock_multiplier int not null default 3,
  high_value_threshold int not null default 100000, -- in cents
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

-- Helper functions to get user ID and claims from JWT
create or replace function get_user_id()
returns uuid
language sql stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::json->>'sub', '')::uuid;
$$;

create or replace function get_company_id()
returns uuid
language sql stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::json->'app_metadata'->>'company_id', '')::uuid;
$$;

create or replace function get_user_role()
returns text
language sql stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::json->'app_metadata'->>'role', '');
$$;

-- Function to handle new user creation and company association
create or replace function handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  company_id_var uuid;
  user_role_var user_role;
  company_name_var text;
begin
  -- Extract company name from auth.users metadata, default if not present
  company_name_var := new.raw_app_meta_data->>'company_name';
  if company_name_var is null or company_name_var = '' then
    company_name_var := new.email || '''s Company';
  end if;

  -- Create a new company for the user
  insert into public.companies (name)
  values (company_name_var)
  returning id into company_id_var;
  
  -- The first user of a company is always the Owner
  user_role_var := 'Owner';

  -- Create a profile for the new user
  insert into public.users (id, company_id, email, role)
  values (new.id, company_id_var, new.email, user_role_var);

  -- Update the user's app_metadata in auth.users to include company_id and role
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id_var, 'role', user_role_var)
  where id = new.id;

  return new;
end;
$$;

-- Trigger to call handle_new_user on new user sign-up
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


-- RLS Policies
alter table companies enable row level security;
drop policy if exists "Allow users to see their own company" on companies;
create policy "Allow users to see their own company"
  on companies for select
  using (id = get_company_id());

alter table users enable row level security;
drop policy if exists "Allow users to see profiles in their own company" on users;
create policy "Allow users to see profiles in their own company"
  on users for select
  using (company_id = get_company_id());

alter table company_settings enable row level security;
drop policy if exists "Allow users to see settings for their own company" on company_settings;
create policy "Allow users to see settings for their own company"
  on company_settings for all
  using (company_id = get_company_id());

-- PRODUCTS
create table if not exists products (
  id uuid primary key default uuid_generate_v4(),
  company_id uuid references companies(id) on delete cascade not null,
  title text not null,
  description text,
  handle text,
  product_type text,
  tags text[],
  status text, -- e.g., 'active', 'draft', 'archived'
  image_url text,
  external_product_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  fts_document tsvector,
  deleted_at timestamptz
);
alter table products enable row level security;
drop policy if exists "Allow users to manage products in their own company" on products;
create policy "Allow users to manage products in their own company"
  on products for all
  using (company_id = get_company_id());
alter table products drop constraint if exists products_company_id_external_product_id_key;
alter table products add constraint products_company_id_external_product_id_key unique (company_id, external_product_id);


-- PRODUCT VARIANTS
create table if not exists product_variants (
    id uuid primary key default gen_random_uuid(),
    product_id uuid not null references products(id) on delete cascade,
    company_id uuid not null references companies(id) on delete cascade,
    sku text not null,
    title text, -- e.g., 'Large / Blue'
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
    external_variant_id text,
    created_at timestamptz default now(),
    updated_at timestamptz default now(),
    location text,
    deleted_at timestamptz
);
alter table product_variants enable row level security;
drop policy if exists "Allow users to manage variants in their own company" on product_variants;
create policy "Allow users to manage variants in their own company"
  on product_variants for all
  using (company_id = get_company_id());
alter table product_variants drop constraint if exists product_variants_company_id_sku_key;
alter table product_variants add constraint product_variants_company_id_sku_key unique(company_id, sku);
alter table product_variants drop constraint if exists product_variants_company_id_external_variant_id_key;
alter table product_variants add constraint product_variants_company_id_external_variant_id_key unique(company_id, external_variant_id);


-- SUPPLIERS
create table if not exists suppliers (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid references companies(id) on delete cascade not null,
    name text not null,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz not null default now()
);
alter table suppliers enable row level security;
drop policy if exists "Allow users to manage suppliers in their own company" on suppliers;
create policy "Allow users to manage suppliers in their own company"
  on suppliers for all
  using (company_id = get_company_id());


-- CUSTOMERS
create table if not exists customers (
  id uuid primary key default uuid_generate_v4(),
  company_id uuid references companies(id) on delete cascade not null,
  customer_name text not null,
  email text,
  total_orders int default 0,
  total_spent int default 0, -- in cents
  first_order_date date,
  deleted_at timestamptz,
  created_at timestamptz default now()
);
alter table customers enable row level security;
drop policy if exists "Allow users to manage customers in their own company" on customers;
create policy "Allow users to manage customers in their own company"
  on customers for all
  using (company_id = get_company_id());


-- ORDERS
create table if not exists orders (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references companies(id) on delete cascade,
    order_number text not null,
    external_order_id text,
    customer_id uuid references customers(id),
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
alter table orders enable row level security;
drop policy if exists "Allow users to manage orders in their own company" on orders;
create policy "Allow users to manage orders in their own company"
  on orders for all
  using (company_id = get_company_id());


-- ORDER LINE ITEMS
create table if not exists order_line_items (
    id uuid primary key default gen_random_uuid(),
    order_id uuid not null references orders(id) on delete cascade,
    company_id uuid not null references companies(id) on delete cascade,
    product_id uuid not null references products(id) on delete cascade,
    variant_id uuid not null references product_variants(id) on delete cascade,
    product_name text not null,
    variant_title text,
    sku text not null,
    quantity int not null,
    price int not null, -- in cents
    total_discount int default 0, -- in cents
    tax_amount int default 0, -- in cents
    cost_at_time int, -- cost of goods in cents at time of sale
    fulfillment_status text default 'unfulfilled',
    requires_shipping boolean default true,
    external_line_item_id text
);
alter table order_line_items enable row level security;
drop policy if exists "Allow users to manage line items in their own company" on order_line_items;
create policy "Allow users to manage line items in their own company"
  on order_line_items for all
  using (company_id = get_company_id());

-- VIEWS
create or replace view product_variants_with_details as
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
    pv.created_at,
    pv.updated_at,
    pv.location,
    pv.deleted_at,
    p.title as product_title,
    p.status as product_status,
    p.image_url
from
    product_variants pv
join
    products p on pv.product_id = p.id;

create or replace view customers_view as
select
    c.id,
    c.company_id,
    c.customer_name,
    c.email,
    c.total_orders,
    c.total_spent,
    c.first_order_date,
    c.created_at
from
    customers c
where
    c.deleted_at is null;

create or replace view orders_view as
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
    orders o
left join
    customers c on o.customer_id = c.id;


-- INTEGRATIONS
create table if not exists integrations (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references companies(id) on delete cascade,
    platform text not null,
    shop_domain text,
    shop_name text,
    is_active boolean default false,
    last_sync_at timestamptz,
    sync_status text,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);
alter table integrations enable row level security;
drop policy if exists "Allow users to manage integrations in their own company" on integrations;
create policy "Allow users to manage integrations in their own company"
  on integrations for all
  using (company_id = get_company_id());
alter table integrations drop constraint if exists integrations_company_id_platform_key;
alter table integrations add constraint integrations_company_id_platform_key unique (company_id, platform);

-- WEBHOOK EVENTS
create table if not exists webhook_events (
    id uuid primary key default gen_random_uuid(),
    integration_id uuid not null references integrations(id) on delete cascade,
    webhook_id text not null,
    processed_at timestamptz default now(),
    created_at timestamptz default now()
);
alter table webhook_events drop constraint if exists webhook_events_integration_id_webhook_id_key;
alter table webhook_events add constraint webhook_events_integration_id_webhook_id_key unique (integration_id, webhook_id);

-- CONVERSATIONS & MESSAGES (for AI Chat)
create table if not exists conversations (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references auth.users(id) on delete cascade not null,
  company_id uuid references companies(id) on delete cascade not null,
  title text not null,
  created_at timestamptz default now(),
  last_accessed_at timestamptz default now(),
  is_starred boolean default false
);
alter table conversations enable row level security;
drop policy if exists "Allow users to manage their own conversations" on conversations;
create policy "Allow users to manage their own conversations"
  on conversations for all
  using (user_id = get_user_id());


create table if not exists messages (
    id uuid primary key default uuid_generate_v4(),
    conversation_id uuid references conversations(id) on delete cascade not null,
    company_id uuid references companies(id) on delete cascade not null,
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
alter table messages enable row level security;
drop policy if exists "Allow users to manage messages in their own company" on messages;
create policy "Allow users to manage messages in their own company"
  on messages for all
  using (company_id = get_company_id());


-- INVENTORY LEDGER
create table if not exists inventory_ledger (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references companies(id) on delete cascade,
    variant_id uuid not null references product_variants(id) on delete cascade,
    change_type text not null, -- 'sale', 'purchase_order', 'manual_adjustment', 'reconciliation'
    quantity_change int not null,
    new_quantity int not null,
    related_id uuid, -- e.g., order_id, purchase_order_id
    notes text,
    created_at timestamptz not null default now()
);
alter table inventory_ledger enable row level security;
drop policy if exists "Allow users to view inventory ledger in their own company" on inventory_ledger;
create policy "Allow users to view inventory ledger in their own company"
  on inventory_ledger for select
  using (company_id = get_company_id());


-- PURCHASE ORDERS
create table if not exists purchase_orders (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid references companies(id) on delete cascade not null,
    supplier_id uuid references suppliers(id),
    status text not null default 'Draft',
    po_number text not null,
    total_cost integer not null, -- in cents
    expected_arrival_date date,
    created_at timestamptz not null default now(),
    idempotency_key uuid
);
alter table purchase_orders enable row level security;
drop policy if exists "Allow users to manage purchase orders in their own company" on purchase_orders;
create policy "Allow users to manage purchase orders in their own company"
  on purchase_orders for all
  using (company_id = get_company_id());

create table if not exists purchase_order_line_items (
    id uuid primary key default uuid_generate_v4(),
    purchase_order_id uuid references purchase_orders(id) on delete cascade not null,
    company_id uuid references companies(id) on delete cascade not null,
    variant_id uuid references product_variants(id) not null,
    quantity integer not null,
    cost integer not null -- cost per unit in cents
);
alter table purchase_order_line_items enable row level security;
drop policy if exists "Allow users to manage PO line items in their own company" on purchase_order_line_items;
create policy "Allow users to manage PO line items in their own company"
  on purchase_order_line_items for all
  using (company_id = get_company_id());

-- Additional Tables for future features
create table if not exists refunds (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references companies(id) on delete cascade,
    order_id uuid not null references orders(id) on delete cascade,
    refund_number text not null,
    status text not null default 'pending',
    reason text,
    note text,
    total_amount int not null, -- in cents
    created_by_user_id uuid references auth.users(id),
    external_refund_id text,
    created_at timestamptz default now()
);
alter table refunds enable row level security;
drop policy if exists "Allow users to manage refunds in their own company" on refunds;
create policy "Allow users to manage refunds in their own company"
  on refunds for all
  using (company_id = get_company_id());

create table if not exists refund_line_items (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references companies(id) on delete cascade,
    refund_id uuid not null references refunds(id) on delete cascade,
    order_line_item_id uuid not null references order_line_items(id) on delete cascade,
    quantity int not null,
    amount int not null,
    restock boolean default true
);
alter table refund_line_items enable row level security;
drop policy if exists "Allow users to manage refund line items in their own company" on refund_line_items;
create policy "Allow users to manage refund line items in their own company"
  on refund_line_items for all
  using (company_id = get_company_id());

create table if not exists discounts (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references companies(id) on delete cascade,
    code text not null,
    type text not null, -- 'percentage', 'fixed_amount'
    value int not null, -- cents for fixed, basis points for percentage
    minimum_purchase int, -- cents
    usage_limit int,
    usage_count int default 0,
    applies_to text default 'all', -- 'all', 'products', 'collections'
    starts_at timestamptz,
    ends_at timestamptz,
    is_active boolean default true,
    created_at timestamptz default now()
);
alter table discounts enable row level security;
drop policy if exists "Allow users to manage discounts in their own company" on discounts;
create policy "Allow users to manage discounts in their own company"
  on discounts for all
  using (company_id = get_company_id());

create table if not exists customer_addresses (
    id uuid primary key default gen_random_uuid(),
    customer_id uuid not null references customers(id) on delete cascade,
    address_type text not null default 'shipping', -- 'shipping', 'billing'
    first_name text,
    last_name text,
    company text,
    address1 text,
    address2 text,
    city text,
    province_code text,
    country_code text,
    zip text,
    phone text,
    is_default boolean default false
);
alter table customer_addresses enable row level security;
drop policy if exists "Allow users to manage customer addresses in their own company" on customer_addresses;
create policy "Allow users to manage customer addresses in their own company"
  on customer_addresses for all
  using (exists (select 1 from customers where id = customer_id and company_id = get_company_id()));


create table if not exists channel_fees (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references companies(id) on delete cascade,
    channel_name text not null,
    percentage_fee numeric not null,
    fixed_fee numeric not null,
    created_at timestamptz default now(),
    updated_at timestamptz
);
alter table channel_fees enable row level security;
drop policy if exists "Allow users to manage channel fees in their own company" on channel_fees;
create policy "Allow users to manage channel fees in their own company"
  on channel_fees for all
  using (company_id = get_company_id());

create table if not exists audit_log (
    id bigserial primary key,
    company_id uuid references companies(id) on delete cascade,
    user_id uuid references auth.users(id),
    action text not null,
    details jsonb,
    created_at timestamptz default now()
);
alter table audit_log enable row level security;
drop policy if exists "Allow owners to view audit log in their own company" on audit_log;
create policy "Allow owners to view audit log in their own company"
  on audit_log for select
  using (company_id = get_company_id() and get_user_role() = 'Owner');

create table if not exists export_jobs (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references companies(id) on delete cascade,
    requested_by_user_id uuid not null references auth.users(id),
    status text not null default 'pending', -- pending, processing, completed, failed
    download_url text,
    expires_at timestamptz,
    created_at timestamptz not null default now()
);
alter table export_jobs enable row level security;
drop policy if exists "Allow users to manage their own export jobs" on export_jobs;
create policy "Allow users to manage their own export jobs"
  on export_jobs for all
  using (requested_by_user_id = get_user_id());
  
-- Create indexes for performance
create index if not exists idx_products_company_id on products(company_id);
create index if not exists idx_product_variants_company_id on product_variants(company_id);
create index if not exists idx_product_variants_product_id on product_variants(product_id);
create index if not exists idx_orders_company_id on orders(company_id);
create index if not exists idx_order_line_items_order_id on order_line_items(order_id);
create index if not exists idx_inventory_ledger_variant_id on inventory_ledger(variant_id);
create index if not exists idx_inventory_ledger_company_id on inventory_ledger(company_id);
create index if not exists idx_customers_company_id on customers(company_id);
create index if not exists idx_suppliers_company_id on suppliers(company_id);

-- Create a function to check user role within their company
create or replace function check_user_permission(p_user_id uuid, p_required_role text)
returns boolean as $$
declare
    user_role text;
begin
    select role into user_role from public.users where id = p_user_id;

    if user_role is null then
        return false;
    end if;

    if p_required_role = 'Owner' and user_role = 'Owner' then
        return true;
    elsif p_required_role = 'Admin' and (user_role = 'Owner' or user_role = 'Admin') then
        return true;
    end if;

    return false;
end;
$$ language plpgsql stable;
