
-- Enable UUID extension
create extension if not exists "uuid-ossp" with schema "extensions";

-- For fuzzy string matching
create extension if not exists "pg_trgm" with schema "public";

-- Enable pgroonga for full-text search
create extension if not exists "pgroonga" with schema "public";

-- Remove existing tables to ensure a clean slate, in reverse order of dependency
drop table if exists public.refund_line_items;
drop table if exists public.refunds;
drop table if exists public.purchase_order_line_items;
drop table if exists public.purchase_orders;
drop table if exists public.order_line_items;
drop table if exists public.orders;
drop table if exists public.inventory_ledger;
drop table if exists public.product_variants;
drop table if exists public.products;
drop table if exists public.suppliers;
drop table if exists public.customer_addresses;
drop table if exists public.customers;
drop table if exists public.discounts;
drop table if exists public.integrations;
drop table if exists public.channel_fees;
drop table if exists public.company_settings;
drop table if exists public.users;
drop table if exists public.companies;
drop table if exists public.conversations;
drop table if exists public.messages;
drop table if exists public.audit_log;
drop table if exists public.export_jobs;
drop table if exists public.webhook_events;

drop function if exists public.handle_new_user();
drop function if exists public.authorize_user_for_company(uuid, uuid);
drop function if exists public.record_sale_transaction(uuid, uuid, text, text, text, text, jsonb);
drop function if exists public.update_inventory_quantity_for_sale(uuid, integer, uuid);
drop view if exists public.product_variants_with_details;

-- Create core tables
create table public.companies (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  created_at timestamptz not null default now()
);
comment on table public.companies is 'Stores company information.';

create table public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  email text,
  role text default 'Member'::text check (role in ('Owner', 'Admin', 'Member')),
  deleted_at timestamptz,
  created_at timestamptz default now()
);
comment on table public.users is 'Stores user profiles and their company association.';

create table public.company_settings (
    company_id uuid primary key references public.companies(id) on delete cascade,
    dead_stock_days integer not null default 90,
    fast_moving_days integer not null default 30,
    overstock_multiplier integer not null default 3,
    high_value_threshold integer not null default 1000,
    predictive_stock_days integer not null default 7,
    currency text default 'USD',
    timezone text default 'UTC',
    tax_rate numeric default 0,
    promo_sales_lift_multiplier real not null default 2.5,
    custom_rules jsonb,
    subscription_status text default 'trial',
    subscription_plan text default 'starter',
    subscription_expires_at timestamptz,
    stripe_customer_id text,
    stripe_subscription_id text,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);
comment on table public.company_settings is 'Stores settings specific to each company.';

create table public.suppliers (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    name text not null,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz not null default now()
);
comment on table public.suppliers is 'Stores supplier and vendor information.';

create table public.products (
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
comment on table public.products is 'Core product information.';

create table public.product_variants (
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
    price integer,
    compare_at_price integer,
    cost integer,
    inventory_quantity integer not null default 0,
    location text,
    external_variant_id text,
    created_at timestamptz default now(),
    updated_at timestamptz,
    unique(company_id, sku)
);
comment on table public.product_variants is 'Specific variations of a product.';

create table public.customers (
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
comment on table public.customers is 'Stores customer information.';

create table public.orders (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    order_number text not null,
    external_order_id text,
    customer_id uuid references public.customers(id),
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
    updated_at timestamptz,
    unique(company_id, external_order_id)
);
comment on table public.orders is 'Stores sales order information.';

create table public.order_line_items (
    id uuid primary key default uuid_generate_v4(),
    order_id uuid not null references public.orders(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    product_id uuid references public.products(id),
    variant_id uuid references public.product_variants(id),
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
comment on table public.order_line_items is 'Individual items within a sales order.';

create table public.inventory_ledger (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    change_type text not null,
    quantity_change integer not null,
    new_quantity integer not null,
    related_id uuid,
    notes text,
    created_at timestamptz not null default now()
);
comment on table public.inventory_ledger is 'Tracks all changes to inventory levels.';

create table public.purchase_orders (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    supplier_id uuid references public.suppliers(id),
    status text not null default 'Draft',
    po_number text not null,
    total_cost integer not null,
    expected_arrival_date date,
    created_at timestamptz not null default now()
);
comment on table public.purchase_orders is 'Stores purchase orders for restocking inventory.';

create table public.purchase_order_line_items (
    id uuid primary key default uuid_generate_v4(),
    purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    quantity integer not null,
    cost integer not null
);
comment on table public.purchase_order_line_items is 'Individual items within a purchase order.';

create table public.integrations (
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
comment on table public.integrations is 'Stores integration settings for platforms like Shopify.';

create table public.conversations (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid references auth.users(id) on delete cascade,
    company_id uuid references public.companies(id) on delete cascade,
    title text not null,
    created_at timestamptz default now(),
    last_accessed_at timestamptz default now(),
    is_starred boolean default false
);
comment on table public.conversations is 'Stores chat conversation history.';

create table public.messages (
    id uuid primary key default uuid_generate_v4(),
    conversation_id uuid references public.conversations(id) on delete cascade,
    company_id uuid references public.companies(id) on delete cascade,
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
comment on table public.messages is 'Stores individual messages within a conversation.';

create table public.audit_log (
    id bigserial primary key,
    company_id uuid references public.companies(id),
    user_id uuid references auth.users(id),
    action text not null,
    details jsonb,
    created_at timestamptz default now()
);
comment on table public.audit_log is 'Records significant events for auditing purposes.';

create table public.export_jobs (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    requested_by_user_id uuid not null references auth.users(id) on delete cascade,
    status text not null default 'pending',
    download_url text,
    expires_at timestamptz,
    created_at timestamptz not null default now()
);
comment on table public.export_jobs is 'Tracks data export requests.';

create table public.webhook_events (
    id uuid primary key default uuid_generate_v4(),
    integration_id uuid not null references public.integrations(id) on delete cascade,
    webhook_id text not null,
    processed_at timestamptz default now(),
    created_at timestamptz default now(),
    unique(integration_id, webhook_id)
);
comment on table public.webhook_events is 'Deduplicates incoming webhooks to prevent reprocessing.';

-- Functions and Triggers
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  company_id uuid;
  company_name text;
begin
  -- Get company name from auth.users metadata, or use a default
  company_name := new.raw_app_meta_data->>'company_name';
  if company_name is null or company_name = '' then
    company_name := 'My Company';
  end if;
  
  -- Create a new company for the new user
  insert into public.companies (name)
  values (company_name)
  returning id into company_id;
  
  -- Create a corresponding public.users entry
  insert into public.users (id, company_id, email, role)
  values (new.id, company_id, new.email, 'Owner');

  -- Update the user's app_metadata with the new company_id
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id, 'role', 'Owner')
  where id = new.id;
  
  return new;
end;
$$;

-- Trigger to call handle_new_user on new user signup
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Drop existing RLS policies before creating new ones
alter table public.companies disable row level security;
drop policy if exists "Users can only see their own company" on public.companies;
alter table public.users disable row level security;
drop policy if exists "Users can see other members of their company" on public.users;
alter table public.company_settings disable row level security;
drop policy if exists "Users can only see their own company settings" on public.company_settings;

-- Enable Row Level Security (RLS)
alter table public.companies enable row level security;
alter table public.users enable row level security;
alter table public.company_settings enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.orders enable row level security;
alter table public.order_line_items enable row level security;
alter table public.customers enable row level security;
alter table public.suppliers enable row level security;
alter table public.purchase_orders enable row level security;
alter table public.purchase_order_line_items enable row level security;
alter table public.inventory_ledger enable row level security;
alter table public.integrations enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.audit_log enable row level security;
alter table public.export_jobs enable row level security;

-- Policies
create policy "Users can only see their own company" on public.companies for select using (id = (current_setting('request.jwt.claims', true)::jsonb ->> 'app_metadata')::jsonb ->> 'company_id');

create policy "Users can see other members of their company" on public.users for select using (company_id = (current_setting('request.jwt.claims', true)::jsonb ->> 'app_metadata')::jsonb ->> 'company_id');

create policy "Users can only see their own company settings" on public.company_settings for all using (company_id = (current_setting('request.jwt.claims', true)::jsonb ->> 'app_metadata')::jsonb ->> 'company_id');

create policy "Enable all access for company members" on public.products for all using (company_id = (current_setting('request.jwt.claims', true)::jsonb ->> 'app_metadata')::jsonb ->> 'company_id');
create policy "Enable all access for company members" on public.product_variants for all using (company_id = (current_setting('request.jwt.claims', true)::jsonb ->> 'app_metadata')::jsonb ->> 'company_id');
create policy "Enable all access for company members" on public.orders for all using (company_id = (current_setting('request.jwt.claims', true)::jsonb ->> 'app_metadata')::jsonb ->> 'company_id');
create policy "Enable all access for company members" on public.order_line_items for all using (company_id = (current_setting('request.jwt.claims', true)::jsonb ->> 'app_metadata')::jsonb ->> 'company_id');
create policy "Enable all access for company members" on public.customers for all using (company_id = (current_setting('request.jwt.claims', true)::jsonb ->> 'app_metadata')::jsonb ->> 'company_id');
create policy "Enable all access for company members" on public.suppliers for all using (company_id = (current_setting('request.jwt.claims', true)::jsonb ->> 'app_metadata')::jsonb ->> 'company_id');
create policy "Enable all access for company members" on public.purchase_orders for all using (company_id = (current_setting('request.jwt.claims', true)::jsonb ->> 'app_metadata')::jsonb ->> 'company_id');
create policy "Enable all access for company members" on public.purchase_order_line_items for all using (company_id = (current_setting('request.jwt.claims', true)::jsonb ->> 'app_metadata')::jsonb ->> 'company_id');
create policy "Enable all access for company members" on public.inventory_ledger for all using (company_id = (current_setting('request.jwt.claims', true)::jsonb ->> 'app_metadata')::jsonb ->> 'company_id');
create policy "Enable all access for company members" on public.integrations for all using (company_id = (current_setting('request.jwt.claims', true)::jsonb ->> 'app_metadata')::jsonb ->> 'company_id');
create policy "Enable all access for company members" on public.audit_log for all using (company_id = (current_setting('request.jwt.claims', true)::jsonb ->> 'app_metadata')::jsonb ->> 'company_id');
create policy "Users can see their own conversations" on public.conversations for all using (user_id = auth.uid());
create policy "Users can see messages in their conversations" on public.messages for all using (conversation_id in (select id from public.conversations where user_id = auth.uid()));
create policy "Users can see their own export jobs" on public.export_jobs for all using (requested_by_user_id = auth.uid());


-- Indexes for performance
create index if not exists idx_products_company_id on public.products(company_id);
create index if not exists idx_product_variants_product_id on public.product_variants(product_id);
create index if not exists idx_product_variants_sku on public.product_variants(sku);
create index if not exists idx_orders_company_id on public.orders(company_id);
create index if not exists idx_orders_customer_id on public.orders(customer_id);
create index if not exists idx_order_line_items_order_id on public.order_line_items(order_id);
create index if not exists idx_order_line_items_variant_id on public.order_line_items(variant_id);
create index if not exists idx_inventory_ledger_variant_id_created_at on public.inventory_ledger(variant_id, created_at desc);
create index if not exists idx_suppliers_company_id on public.suppliers(company_id);
create index if not exists idx_customers_email on public.customers(email);
create index if not exists idx_orders_external_order_id on public.orders(external_order_id);

-- Secure search function
create or replace function public.search_products(p_company_id uuid, p_search_term text)
returns setof public.products
language sql
as $$
  select *
  from public.products
  where company_id = p_company_id and title &@~ p_search_term;
$$;

-- Full-text search index on secure function
create index if not exists pgroonga_products_title_index on public.products using pgroonga (title);

-- Drop view before creating to handle column changes
drop view if exists public.product_variants_with_details;

-- Create a view for easy querying of product variants with parent product details
create or replace view public.product_variants_with_details as
select 
    pv.id,
    pv.product_id,
    pv.company_id,
    p.title as product_title,
    p.status as product_status,
    p.image_url,
    p.product_type,
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
    pv.updated_at
from 
    public.product_variants pv
join 
    public.products p on pv.product_id = p.id;

comment on view public.product_variants_with_details is 'Combines product variants with their parent product details for easier querying.';
