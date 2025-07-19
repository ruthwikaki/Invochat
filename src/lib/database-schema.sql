-- Protect the "storage" schema from being exposed to the public
revoke all on schema storage from public;
revoke all on all tables in schema storage from public;

-- Protect the "graphql" schema from being exposed to the public
revoke all on schema graphql from public;
revoke all on all tables in schema graphql from public;

-- Drop existing tables to ensure a clean slate
drop table if exists "public"."product_variants" cascade;
drop table if exists "public"."products" cascade;
drop table if exists "public"."suppliers" cascade;
drop table if exists "public"."orders" cascade;
drop table if exists "public"."order_line_items" cascade;
drop table if exists "public"."refunds" cascade;
drop table if exists "public"."customers" cascade;
drop table if exists "public"."inventory_ledger" cascade;
drop table if exists "public"."company_settings" cascade;
drop table if exists "public"."companies" cascade;
drop table if exists "public"."integrations" cascade;
drop table if exists "public"."export_jobs" cascade;
drop table if exists "public"."user_feedback" cascade;
drop table if exists "public"."audit_log" cascade;
drop table if exists "public"."channel_fees" cascade;
drop table if exists "public"."webhook_events" cascade;
drop table if exists "public"."purchase_orders" cascade;
drop table if exists "public"."purchase_order_line_items" cascade;

-- Custom types
do $$
begin
  if not exists (select 1 from pg_type where typname = 'user_role') then
    create type user_role as enum ('Owner', 'Admin', 'Member');
  end if;
  if not exists (select 1 from pg_type where typname = 'po_status') then
    create type po_status as enum ('Draft', 'Ordered', 'Partially Received', 'Received', 'Cancelled');
  end if;
end$$;

-- Table for Companies
create table if not exists companies (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    created_at timestamptz not null default now()
);

-- Table for Users (from Supabase Auth, but with a profile table for roles)
-- Add custom claims to the JWT for company_id and role
alter table auth.users add column if not exists company_id uuid references companies(id);

-- Table for User Roles within a company
create table if not exists user_company_roles (
    user_id uuid references auth.users(id) on delete cascade not null,
    company_id uuid references companies(id) on delete cascade not null,
    role user_role not null default 'Member',
    primary key (user_id, company_id)
);

-- Table for Suppliers
create table if not exists suppliers (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references companies(id) on delete cascade,
    name text not null,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz not null default now()
);
alter table suppliers enable row level security;

-- Table for Products
create table if not exists products (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references companies(id) on delete cascade,
    title text not null,
    description text,
    handle text, -- For Shopify-like URL handles
    product_type text,
    tags text[],
    status text, -- e.g., 'active', 'draft', 'archived'
    image_url text,
    external_product_id text,
    created_at timestamptz not null default now(),
    updated_at timestamptz,
    unique(company_id, external_product_id)
);
alter table products enable row level security;
create index if not exists idx_products_company_id on products(company_id);

-- Table for Product Variants (SKUs)
create table if not exists product_variants (
    id uuid primary key default gen_random_uuid(),
    product_id uuid not null references products(id) on delete cascade,
    company_id uuid not null references companies(id) on delete cascade,
    sku text not null,
    title text,
    option1_name text,
    option1_value text,
    option2_name text,
    option2_value text,
    option3_name text,
    option3_value text,
    barcode text,
    price integer, -- in cents
    compare_at_price integer, -- in cents
    cost integer, -- in cents
    inventory_quantity integer not null default 0,
    location text,
    external_variant_id text,
    created_at timestamptz not null default now(),
    updated_at timestamptz,
    unique(company_id, sku),
    unique(company_id, external_variant_id)
);
alter table product_variants enable row level security;
create index if not exists idx_variants_company_id_sku on product_variants(company_id, sku);
create index if not exists idx_variants_product_id on product_variants(product_id);

-- Table for Orders
create table if not exists orders (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references companies(id) on delete cascade,
    order_number text not null,
    external_order_id text,
    customer_id uuid, -- Can be null for guest checkouts
    financial_status text,
    fulfillment_status text,
    currency char(3),
    subtotal integer not null,
    total_tax integer,
    total_shipping integer,
    total_discounts integer,
    total_amount integer not null,
    source_platform text,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);
alter table orders enable row level security;
create index if not exists idx_orders_company_id on orders(company_id);
create index if not exists idx_orders_created_at on orders(created_at);

-- Table for Order Line Items
create table if not exists order_line_items (
    id uuid primary key default gen_random_uuid(),
    order_id uuid not null references orders(id) on delete cascade,
    variant_id uuid references product_variants(id) on delete set null,
    company_id uuid not null references companies(id) on delete cascade,
    product_name text,
    variant_title text,
    sku text,
    quantity integer not null,
    price integer not null, -- in cents
    total_discount integer,
    tax_amount integer,
    cost_at_time integer,
    external_line_item_id text
);
alter table order_line_items enable row level security;
create index if not exists idx_order_line_items_order_id on order_line_items(order_id);
create index if not exists idx_order_line_items_variant_id on order_line_items(variant_id);

-- Table for Customers
create table if not exists customers (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references companies(id) on delete cascade,
    customer_name text,
    email text,
    external_customer_id text,
    created_at timestamptz not null default now(),
    deleted_at timestamptz,
    unique(company_id, email),
    unique(company_id, external_customer_id)
);
alter table customers enable row level security;
create index if not exists idx_customers_company_id on customers(company_id);

-- Add foreign key constraint from orders to customers
alter table orders add constraint fk_orders_customer_id foreign key (customer_id) references customers(id) on delete set null;

-- Table for Inventory Ledger
create table if not exists inventory_ledger (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references companies(id) on delete cascade,
    variant_id uuid not null references product_variants(id) on delete cascade,
    change_type text not null, -- e.g., 'sale', 'purchase_order', 'return', 'manual_adjustment'
    quantity_change integer not null,
    new_quantity integer not null,
    related_id uuid, -- e.g., order_id, purchase_order_id
    notes text,
    created_at timestamptz not null default now()
);
alter table inventory_ledger enable row level security;
create index if not exists idx_inventory_ledger_variant_id on inventory_ledger(variant_id, created_at desc);

-- Table for Company-specific Settings
create table if not exists company_settings (
    company_id uuid primary key references companies(id) on delete cascade,
    dead_stock_days integer not null default 90,
    fast_moving_days integer not null default 30,
    overstock_multiplier real not null default 3.0,
    high_value_threshold integer not null default 100000, -- in cents
    predictive_stock_days integer not null default 7,
    currency char(3) not null default 'USD',
    tax_rate real not null default 0.0,
    timezone text not null default 'UTC',
    created_at timestamptz not null default now(),
    updated_at timestamptz
);
alter table company_settings enable row level security;

-- Table for Integrations
create table if not exists integrations (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references companies(id) on delete cascade,
    platform text not null, -- e.g., 'shopify', 'woocommerce'
    shop_domain text,
    shop_name text,
    is_active boolean not null default true,
    last_sync_at timestamptz,
    sync_status text,
    created_at timestamptz not null default now(),
    updated_at timestamptz,
    unique(company_id, platform)
);
alter table integrations enable row level security;

-- Table for Purchase Orders
create table if not exists purchase_orders (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  supplier_id uuid references suppliers(id) on delete set null,
  status po_status not null default 'Draft',
  po_number text not null,
  total_cost integer not null,
  expected_arrival_date date,
  idempotency_key uuid,
  created_at timestamptz not null default now()
);
alter table purchase_orders enable row level security;

-- Table for PO Line Items
create table if not exists purchase_order_line_items (
  id uuid primary key default gen_random_uuid(),
  purchase_order_id uuid not null references purchase_orders(id) on delete cascade,
  variant_id uuid not null references product_variants(id) on delete cascade,
  quantity integer not null,
  cost integer not null -- in cents
);
alter table purchase_order_line_items enable row level security;


-- Enable Row Level Security (RLS) for all tables
-- This ensures users can only access data belonging to their company.
create policy "Users can see their own company data"
on companies for select
using (auth.uid() in (select user_id from user_company_roles where company_id = id));

create policy "Users can update their own company"
on companies for update
using (auth.uid() in (select user_id from user_company_roles where company_id = id and role in ('Owner', 'Admin')));

create policy "Users can manage roles in their company"
on user_company_roles for all
using (company_id = (select company_id from user_company_roles where user_id = auth.uid()));

create policy "Users can manage their company settings"
on company_settings for all
using (company_id = (select company_id from user_company_roles where user_id = auth.uid()));

create policy "Users can manage products in their company"
on products for all
using (company_id = (select company_id from user_company_roles where user_id = auth.uid()));

create policy "Users can manage variants in their company"
on product_variants for all
using (company_id = (select company_id from user_company_roles where user_id = auth.uid()));

create policy "Users can manage orders in their company"
on orders for all
using (company_id = (select company_id from user_company_roles where user_id = auth.uid()));

create policy "Users can manage order items in their company"
on order_line_items for all
using (company_id = (select company_id from user_company_roles where user_id = auth.uid()));

create policy "Users can manage customers in their company"
on customers for all
using (company_id = (select company_id from user_company_roles where user_id = auth.uid()));

create policy "Users can manage suppliers in their company"
on suppliers for all
using (company_id = (select company_id from user_company_roles where user_id = auth.uid()));

create policy "Users can manage ledger entries in their company"
on inventory_ledger for all
using (company_id = (select company_id from user_company_roles where user_id = auth.uid()));

create policy "Users can manage integrations in their company"
on integrations for all
using (company_id = (select company_id from user_company_roles where user_id = auth.uid()));

create policy "Users can manage purchase orders in their company"
on purchase_orders for all
using (company_id = (select company_id from user_company_roles where user_id = auth.uid()));

create policy "Users can manage po line items in their company"
on purchase_order_line_items for all
using (purchase_order_id in (select id from purchase_orders where company_id = (select company_id from user_company_roles where user_id = auth.uid())));


-- Function to handle new user sign-up
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  new_company_id uuid;
begin
  -- Create a new company for the new user
  insert into public.companies (name)
  values (new.raw_user_meta_data->>'company_name')
  returning id into new_company_id;

  -- Update the user's custom claims with the new company_id
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id)
  where id = new.id;

  -- Add the user to the user_company_roles table as Owner
  insert into public.user_company_roles (user_id, company_id, role)
  values (new.id, new_company_id, 'Owner');

  return new;
end;
$$;

-- Trigger to call the function after a new user is created
create or replace trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Function to check user permissions
create or replace function public.check_user_permission(p_user_id uuid, p_required_role user_role)
returns boolean
language plpgsql
security definer
as $$
begin
  return exists (
    select 1
    from public.user_company_roles
    where user_id = p_user_id
    and role >= p_required_role
  );
end;
$$;

-- Create views for simplified querying
create or replace view public.product_variants_with_details as
select
    pv.*,
    p.title as product_title,
    p.status as product_status,
    p.image_url
from
    public.product_variants pv
join
    public.products p on pv.product_id = p.id;

create or replace view public.orders_view as
select
    o.*,
    c.customer_name,
    c.email as customer_email
from
    public.orders o
left join
    public.customers c on o.customer_id = c.id;

create or replace view public.customers_view as
select
    c.*,
    count(o.id) as total_orders,
    sum(o.total_amount) as total_spent,
    min(o.created_at) as first_order_date
from
    public.customers c
left join
    public.orders o on c.id = o.customer_id
group by
    c.id;


-- Advanced RPC functions for analytics
create or replace function public.get_dead_stock_report(p_company_id uuid)
returns table (
    sku text,
    product_name text,
    quantity integer,
    total_value numeric,
    last_sale_date timestamptz
)
language plpgsql
as $$
begin
    return query
    with last_sales as (
      select
        oli.variant_id,
        max(o.created_at) as last_sale_date
      from public.order_line_items oli
      join public.orders o on oli.order_id = o.id
      where oli.company_id = p_company_id
      group by oli.variant_id
    )
    select
        pv.sku,
        p.title as product_name,
        pv.inventory_quantity as quantity,
        (pv.inventory_quantity * pv.cost)::numeric / 100 as total_value,
        ls.last_sale_date
    from public.product_variants pv
    join public.products p on pv.product_id = p.id
    left join last_sales ls on pv.id = ls.variant_id
    where
        pv.company_id = p_company_id
        and pv.inventory_quantity > 0
        and (
          ls.last_sale_date is null
          or ls.last_sale_date < now() - (select dead_stock_days from public.company_settings where company_id = p_company_id) * interval '1 day'
        );
end;
$$;


-- Function to record a sale and update inventory atomically
create or replace function record_sale_transaction(
    p_company_id uuid,
    p_user_id uuid,
    p_customer_name text,
    p_customer_email text,
    p_payment_method text,
    p_notes text,
    p_sale_items jsonb[],
    p_external_id text default null
)
returns uuid
language plpgsql
as $$
declare
    v_customer_id uuid;
    v_order_id uuid;
    v_item jsonb;
    v_variant_id uuid;
    v_quantity_sold integer;
    v_current_stock integer;
    v_new_stock integer;
begin
    -- Find or create customer
    select id into v_customer_id from customers
    where company_id = p_company_id and email = p_customer_email;

    if v_customer_id is null then
        insert into customers (company_id, customer_name, email)
        values (p_company_id, p_customer_name, p_customer_email)
        returning id into v_customer_id;
    end if;

    -- Create order
    insert into orders (company_id, customer_id, order_number, total_amount, subtotal)
    values (
        p_company_id,
        v_customer_id,
        'ORD-' || substr(md5(random()::text), 0, 10),
        (select sum((item->>'unit_price')::integer * (item->>'quantity')::integer) from unnest(p_sale_items) as item),
        (select sum((item->>'unit_price')::integer * (item->>'quantity')::integer) from unnest(p_sale_items) as item)
    )
    returning id into v_order_id;

    -- Process line items
    foreach v_item in array p_sale_items
    loop
        select id into v_variant_id from product_variants
        where company_id = p_company_id and sku = (v_item->>'sku');
        v_quantity_sold := (v_item->>'quantity')::integer;

        if v_variant_id is not null then
            -- Insert line item
            insert into order_line_items (order_id, company_id, variant_id, sku, product_name, quantity, price, cost_at_time)
            values (v_order_id, p_company_id, v_variant_id, v_item->>'sku', v_item->>'product_name', v_quantity_sold, (v_item->>'unit_price')::integer, (v_item->>'cost_at_time')::integer);

            -- Update inventory
            update product_variants
            set inventory_quantity = inventory_quantity - v_quantity_sold
            where id = v_variant_id
            returning inventory_quantity into v_new_stock;

            -- Create ledger entry
            insert into inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id)
            values (p_company_id, v_variant_id, 'sale', -v_quantity_sold, v_new_stock, v_order_id);
        else
            -- If SKU doesn't exist, still log it for reporting
             insert into order_line_items (order_id, company_id, sku, product_name, quantity, price)
             values (v_order_id, p_company_id, v_item->>'sku', v_item->>'product_name', v_quantity_sold, (v_item->>'unit_price')::integer);
        end if;
    end loop;

    return v_order_id;
end;
$$;
