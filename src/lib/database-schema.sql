-- src/lib/database-schema.sql

-- Drop existing objects in reverse order of dependency
drop view if exists public.feedback_view;
drop view if exists public.audit_log_view;
drop view if exists public.purchase_orders_view;
drop view if exists public.customers_view;
drop view if exists public.product_variants_with_details;
drop view if exists public.sales;

drop table if exists
  public.feedback,
  public.alert_history,
  public.alerts,
  public.inventory_ledger,
  public.purchase_order_line_items,
  public.purchase_orders,
  public.order_line_items,
  public.orders,
  public.customers,
  public.product_variants,
  public.products,
  public.company_settings,
  public.company_users,
  public.integrations,
  public.suppliers,
  public.companies,
  public.export_jobs,
  public.webhook_events,
  public.channel_fees
cascade;

drop function if exists public.handle_new_user cascade;
drop function if exists public.get_company_id_for_user cascade;
drop function if exists public.get_users_for_company cascade;
drop function if exists public.update_user_role_in_company cascade;
drop function if exists public.remove_user_from_company cascade;
drop function if exists public.check_user_permission cascade;
drop function if exists public.get_dashboard_metrics cascade;
drop function if exists public.record_order_from_platform cascade;
drop function if exists public.get_reorder_suggestions cascade;
drop function if exists public.get_dead_stock_report cascade;
drop function if exists public.get_supplier_performance_report cascade;
drop function if exists public.get_inventory_turnover cascade;
drop function if exists public.get_sales_analytics cascade;
drop function if exists public.get_inventory_analytics cascade;
drop function if exists public.get_customer_analytics cascade;
drop function if exists public.get_abc_analysis cascade;
drop function if exists public.get_sales_velocity cascade;
drop function if exists public.get_gross_margin_analysis cascade;
drop function if exists public.get_net_margin_by_channel cascade;
drop function if exists public.get_margin_trends cascade;
drop function if exists public.forecast_demand cascade;
drop function if exists public.get_historical_sales_for_sku cascade;
drop function if exists public.get_historical_sales_for_skus cascade;
drop function if exists public.adjust_inventory_quantity cascade;
drop function if exists public.reconcile_inventory_from_integration cascade;
drop function if exists public.create_full_purchase_order cascade;
drop function if exists public.update_full_purchase_order cascade;
drop function if exists public.create_purchase_orders_from_suggestions cascade;
drop function if exists public.refresh_all_matviews cascade;
drop function if exists public.get_alerts_with_status cascade;
drop function if exists public.get_financial_impact_of_promotion cascade;

drop type if exists public.company_role;
drop type if exists public.integration_platform;
drop type if exists public.message_role;
drop type if exists public.feedback_type;
drop type if exists public.po_line_item_type;

-- Type Definitions
create type public.company_role as enum ('Owner', 'Admin', 'Member');
create type public.integration_platform as enum ('shopify', 'woocommerce', 'amazon_fba');
create type public.message_role as enum ('user', 'assistant', 'tool');
create type public.feedback_type as enum ('helpful', 'unhelpful');
create type public.po_line_item_type as (
  variant_id uuid,
  quantity int,
  cost int
);

-- Table: companies
create table public.companies (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    owner_id uuid not null references auth.users(id),
    created_at timestamptz not null default now()
);

-- Table: company_users
create table public.company_users (
    user_id uuid not null references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    role public.company_role not null default 'Member',
    primary key (user_id, company_id)
);
create unique index if not exists ux_company_users_user on public.company_users (user_id);


-- Table: suppliers
create table public.suppliers (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    name text not null,
    email text,
    phone text,
    default_lead_time_days int,
    notes text,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);

-- Table: products
create table public.products (
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
    created_at timestamptz not null default now(),
    updated_at timestamptz,
    unique(company_id, external_product_id)
);

-- Table: product_variants
create table public.product_variants (
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
    price int,
    compare_at_price int,
    cost int,
    inventory_quantity int not null default 0,
    location text,
    external_variant_id text,
    reorder_point int,
    reorder_quantity int,
    supplier_id uuid references public.suppliers(id),
    created_at timestamptz not null default now(),
    updated_at timestamptz,
    unique(company_id, sku),
    unique(company_id, external_variant_id)
);

-- Table: customers
create table public.customers (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text,
  email text,
  phone text,
  external_customer_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  deleted_at timestamptz,
  unique(company_id, external_customer_id),
  unique(company_id, email)
);

-- Table: orders
create table public.orders (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    order_number text not null,
    external_order_id text,
    customer_id uuid references public.customers(id),
    financial_status text,
    fulfillment_status text,
    currency text,
    subtotal int not null,
    total_tax int,
    total_shipping int,
    total_discounts int,
    total_amount int not null,
    source_platform text,
    created_at timestamptz not null default now(),
    updated_at timestamptz,
    unique(company_id, external_order_id)
);

-- Table: order_line_items
create table public.order_line_items (
    id uuid primary key default gen_random_uuid(),
    order_id uuid not null references public.orders(id) on delete cascade,
    variant_id uuid references public.product_variants(id),
    company_id uuid not null references public.companies(id) on delete cascade,
    product_name text,
    variant_title text,
    sku text,
    quantity int not null,
    price int not null,
    total_discount int,
    tax_amount int,
    cost_at_time int,
    external_line_item_id text
);

-- ... other tables ...
create table public.inventory_ledger (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    change_type text not null, -- e.g., 'sale', 'purchase_order', 'manual_adjustment', 'reconciliation'
    quantity_change int not null,
    new_quantity int not null,
    related_id uuid, -- e.g., order_id or purchase_order_id
    notes text,
    created_at timestamptz not null default now()
);

-- VIEWS
create view public.product_variants_with_details as
select
    pv.*,
    p.title as product_title,
    p.status as product_status,
    p.image_url,
    p.product_type
from public.product_variants pv
join public.products p on pv.product_id = p.id;

create view public.customers_view as
select
    c.id,
    c.company_id,
    c.name as customer_name,
    c.email,
    (select count(*) from public.orders o where o.customer_id = c.id) as total_orders,
    (select sum(o.total_amount) from public.orders o where o.customer_id = c.id) as total_spent,
    (select min(o.created_at) from public.orders o where o.customer_id = c.id) as first_order_date,
    c.created_at
from public.customers c;

create view public.orders_view as
select 
    o.*,
    c.email as customer_email
from public.orders o
left join public.customers c on o.customer_id = c.id;

-- Enable RLS for all tables
alter table public.companies enable row level security;
alter table public.company_users enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.orders enable row level security;
alter table public.order_line_items enable row level security;
alter table public.customers enable row level security;
alter table public.suppliers enable row level security;
alter table public.inventory_ledger enable row level security;


-- RLS Policies
create policy "Allow user to manage their own company data"
on public.companies for all
using (id = (select get_company_id_for_user(auth.uid())));

create policy "Allow users to view their own company associations"
on public.company_users for select
using (auth.uid() = user_id);

-- A macro for creating policies for all company-scoped tables
do $$
declare
  table_name text;
begin
  for table_name in select t.table_name from information_schema.tables t where t.table_schema = 'public' and t.table_name not in ('companies', 'company_users')
  loop
    execute format('create policy "Allow user to manage their own %s" on public.%I for all using (company_id = (select get_company_id_for_user(auth.uid())))', table_name, table_name);
  end loop;
end;
$$;


-- handle_new_user function and trigger
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  v_company_id uuid;
  v_name text;
  v_lock_key bigint;
begin
  -- advisory lock per user to prevent concurrent trigger re-entry
  v_lock_key := ('x' || substr(md5(new.id::text), 1, 16))::bit(64)::bigint;
  perform pg_advisory_xact_lock(v_lock_key);

  -- if already associated, do nothing (idempotent)
  select cu.company_id into v_company_id
  from public.company_users cu
  where cu.user_id = new.id
  limit 1;

  if v_company_id is not null then
    return new;
  end if;

  v_name := coalesce(new.raw_user_meta_data->>'company_name',
                     'Company for ' || coalesce(new.email, new.id::text));

  insert into public.companies (name, owner_id)
  values (v_name, new.id)
  returning id into v_company_id;

  insert into public.company_users (user_id, company_id, role)
  values (new.id, v_company_id, 'Owner')
  on conflict do nothing; -- in case of concurrent insert

  update auth.users
     set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb)
                           || jsonb_build_object('company_id', v_company_id)
   where id = new.id;

  return new;
end;
$$;

alter function public.handle_new_user owner to postgres;


create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


-- Helper function to get company ID for a user
create or replace function public.get_company_id_for_user(user_id uuid)
returns uuid
language sql
security definer
as $$
  select company_id from public.company_users where public.company_users.user_id = $1 limit 1;
$$;

-- Other RPC functions
create or replace function public.get_reorder_suggestions(p_company_id uuid)
returns table (
    variant_id uuid,
    product_id uuid,
    sku text,
    product_name text,
    supplier_name text,
    supplier_id uuid,
    current_quantity int,
    suggested_reorder_quantity int,
    unit_cost int
)
language sql
as $$
    select
        pv.id as variant_id,
        pv.product_id,
        pv.sku,
        p.title as product_name,
        s.name as supplier_name,
        s.id as supplier_id,
        pv.inventory_quantity as current_quantity,
        coalesce(pv.reorder_quantity, 0) as suggested_reorder_quantity,
        pv.cost as unit_cost
    from public.product_variants pv
    join public.products p on pv.product_id = p.id
    left join public.suppliers s on pv.supplier_id = s.id
    where
        pv.company_id = p_company_id
        and pv.inventory_quantity <= coalesce(pv.reorder_point, 0);
$$;
