
-- =================================================================================================
-- InvoChat - Database Schema
--
-- This script is designed to be idempotent and can be run safely on new or existing databases.
-- It sets up all necessary tables, functions, triggers, and security policies for the application.
-- =================================================================================================

-- 1. Extensions
-- =================================================================================================
create extension if not exists "uuid-ossp";

-- =================================================================================================
-- 2. Helper Functions
-- =================================================================================================

-- Function to get the company ID of the currently authenticated user.
-- This is a security cornerstone for Row-Level Security (RLS).
create or replace function public.get_current_company_id()
returns uuid as $$
begin
  return (select raw_app_meta_data->>'company_id' from auth.users where id = auth.uid())::uuid;
end;
$$ language plpgsql security definer;

-- Function to get the role of the currently authenticated user for their company.
create or replace function public.get_current_user_role()
returns text as $$
begin
  return (select raw_app_meta_data->>'role' from auth.users where id = auth.uid());
end;
$$ language plpgsql security definer;


-- =================================================================================================
-- 3. Core Tables
-- =================================================================================================

-- Stores company information.
create table if not exists public.companies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now()
);

-- Stores company-specific settings.
create table if not exists public.company_settings (
    company_id uuid primary key references public.companies(id) on delete cascade,
    dead_stock_days integer not null default 90,
    fast_moving_days integer not null default 30,
    predictive_stock_days integer not null default 7,
    currency text default 'USD',
    timezone text default 'UTC',
    overstock_multiplier integer not null default 3,
    high_value_threshold integer not null default 100000, -- in cents
    promo_sales_lift_multiplier real not null default 2.5,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);

-- Stores information about suppliers/vendors.
create table if not exists public.suppliers (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  email text,
  phone text,
  default_lead_time_days integer,
  notes text,
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint uq_supplier_name unique (company_id, name)
);

-- Stores product information (parent products).
create table if not exists public.products (
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
  deleted_at timestamptz,
  constraint uq_external_product_id unique(company_id, external_product_id)
);

-- Stores product variants (the actual SKUs).
create table if not exists public.product_variants (
  id uuid primary key default gen_random_uuid(),
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
  price integer, -- in cents
  compare_at_price integer, -- in cents
  cost integer, -- in cents
  inventory_quantity integer not null default 0, -- Managed by trigger
  external_variant_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  deleted_at timestamptz,
  constraint uq_sku unique(company_id, sku),
  constraint uq_external_variant_id unique(company_id, external_variant_id)
);

-- Stores customer information.
create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  customer_name text not null,
  email text,
  total_orders integer default 0,
  total_spent integer default 0, -- in cents
  first_order_date date,
  deleted_at timestamptz,
  created_at timestamptz default now(),
  constraint uq_customer_email unique (company_id, email)
);

-- Stores sales orders.
create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  order_number text not null,
  external_order_id text,
  customer_id uuid references public.customers(id) on delete set null,
  financial_status text default 'pending',
  fulfillment_status text default 'unfulfilled',
  currency text default 'USD',
  subtotal integer not null default 0,
  total_tax integer default 0,
  total_shipping integer default 0,
  total_discounts integer default 0,
  total_amount integer not null,
  source_platform text,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  constraint uq_external_order unique (company_id, external_order_id)
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
  price integer not null, -- in cents
  total_discount integer default 0,
  tax_amount integer default 0,
  cost_at_time integer, -- in cents
  external_line_item_id text
);

-- Audit trail for all inventory movements. The source of truth for stock levels.
create table if not exists public.inventory_ledger (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    change_type text not null,
    quantity_change integer not null,
    new_quantity integer not null,
    created_at timestamptz not null default now(),
    related_id uuid, -- e.g., order_id for a sale
    notes text
);

-- Stores user invitations and roles within a company.
create table if not exists public.company_users (
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'Member', -- e.g., 'Owner', 'Admin', 'Member'
  primary key (company_id, user_id)
);

-- Stores integration settings.
create table if not exists public.integrations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  platform text not null,
  shop_domain text,
  shop_name text,
  is_active boolean default false,
  last_sync_at timestamptz,
  sync_status text,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  constraint uq_company_platform unique (company_id, platform)
);

-- Stores webhook events to prevent replay attacks.
create table if not exists public.webhook_events (
  id uuid primary key default gen_random_uuid(),
  integration_id uuid not null references public.integrations(id) on delete cascade,
  webhook_id text not null,
  processed_at timestamptz default now(),
  created_at timestamptz default now(),
  unique (integration_id, webhook_id)
);

-- Stores AI chat conversation history.
create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  title text not null,
  created_at timestamptz default now(),
  last_accessed_at timestamptz default now(),
  is_starred boolean default false
);

-- Stores individual messages within a conversation.
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  role text not null, -- 'user' or 'assistant'
  content text,
  component text,
  component_props jsonb,
  visualization jsonb,
  confidence numeric,
  assumptions text[],
  is_error boolean default false,
  created_at timestamptz default now()
);

-- Stores feedback on AI-generated content
create table if not exists public.user_feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  subject_id text not null,
  subject_type text not null, -- e.g., 'anomaly_explanation', 'ai_chat_message'
  feedback text not null, -- 'helpful' or 'unhelpful'
  created_at timestamptz default now()
);

-- =================================================================================================
-- 4. Indexes
-- =================================================================================================
create index if not exists idx_suppliers_company_id on public.suppliers(company_id);
create index if not exists idx_products_company_id on public.products(company_id);
create index if not exists idx_variants_product_id on public.product_variants(product_id);
create index if not exists idx_variants_sku on public.product_variants(company_id, sku);
create index if not exists idx_orders_company_created on public.orders(company_id, created_at desc);
create index if not exists idx_orders_customer_id on public.orders(customer_id);
create index if not exists idx_line_items_order_id on public.order_line_items(order_id);
create index if not exists idx_line_items_variant_id on public.order_line_items(variant_id);
create index if not exists idx_ledger_variant_id on public.inventory_ledger(variant_id);
create index if not exists idx_conversations_user_id on public.conversations(user_id);
create index if not exists idx_messages_conversation_id on public.messages(conversation_id);

-- =================================================================================================
-- 5. Database Functions
-- =================================================================================================

-- Function to handle new user sign-ups and associate them with a new company.
create or replace function public.handle_new_user()
returns trigger as $$
declare
  new_company_id uuid;
  company_name text;
begin
  -- Create a new company for the new user
  company_name := coalesce(new.raw_app_meta_data->>'company_name', 'My Company');
  insert into public.companies (name) values (company_name) returning id into new_company_id;

  -- Create a link in the company_users table
  insert into public.company_users (user_id, company_id, role)
  values (new.id, new_company_id, 'Owner');

  -- Update the user's app_metadata with the new company_id and role
  update auth.users
  set raw_app_meta_data = new.raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'role', 'Owner')
  where id = new.id;

  return new;
end;
$$ language plpgsql security definer;

-- Trigger to execute the handle_new_user function on new user creation.
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Function to update the inventory_quantity on product_variants table.
create or replace function public.update_variant_quantity_from_ledger()
returns trigger as $$
begin
  update public.product_variants
  set inventory_quantity = new.new_quantity
  where id = new.variant_id;
  return new;
end;
$$ language plpgsql;

-- Trigger to update inventory quantity after a new ledger entry.
drop trigger if exists on_inventory_ledger_insert on public.inventory_ledger;
create trigger on_inventory_ledger_insert
  after insert on public.inventory_ledger
  for each row execute procedure public.update_variant_quantity_from_ledger();

-- Function to record a sale from a platform, ensuring data consistency.
-- Drop legacy function signatures first to avoid conflicts
drop function if exists public.record_order_from_platform(uuid, text, jsonb);
drop function if exists public.record_order_from_platform(p_company_id uuid, p_platform text, p_order_payload jsonb);

create or replace function public.record_order_from_platform(p_company_id uuid, p_platform text, p_order_payload jsonb)
returns uuid as $$
declare
  v_customer_id uuid;
  v_order_id uuid;
  v_variant_id uuid;
  line_item jsonb;
  v_customer_name text;
  v_customer_email text;
begin
  -- 1. Find or Create Customer
  v_customer_email := p_order_payload->'customer'->>'email';
  v_customer_name := coalesce(
    p_order_payload->'customer'->>'first_name' || ' ' || p_order_payload->'customer'->>'last_name',
    v_customer_email,
    'Guest Customer'
  );

  select id into v_customer_id from public.customers where company_id = p_company_id and email = v_customer_email;

  if v_customer_id is null and v_customer_email is not null then
    insert into public.customers (company_id, customer_name, email)
    values (p_company_id, v_customer_name, v_customer_email)
    returning id into v_customer_id;
  end if;

  -- 2. Create Order
  insert into public.orders (
    company_id, order_number, external_order_id, customer_id, financial_status,
    fulfillment_status, total_amount, source_platform, created_at
  ) values (
    p_company_id,
    p_order_payload->>'id',
    p_order_payload->>'id',
    v_customer_id,
    p_order_payload->>'financial_status',
    p_order_payload->>'fulfillment_status',
    (p_order_payload->>'total_price')::numeric * 100,
    p_platform,
    (p_order_payload->>'created_at')::timestamptz
  ) returning id into v_order_id;

  -- 3. Process Line Items and update ledger
  for line_item in select * from jsonb_array_elements(p_order_payload->'line_items')
  loop
    select id into v_variant_id from public.product_variants where sku = line_item->>'sku' and company_id = p_company_id;

    if v_variant_id is not null then
      insert into public.order_line_items (
        order_id, variant_id, company_id, product_name, sku, quantity, price
      ) values (
        v_order_id,
        v_variant_id,
        p_company_id,
        line_item->>'name',
        line_item->>'sku',
        (line_item->>'quantity')::integer,
        (line_item->>'price')::numeric * 100
      );

      -- Create ledger entry for the sale
      insert into public.inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id)
      select
          p_company_id,
          v_variant_id,
          'sale',
          -(line_item->>'quantity')::integer,
          pv.inventory_quantity - (line_item->>'quantity')::integer,
          v_order_id
      from public.product_variants pv where pv.id = v_variant_id;
    end if;
  end loop;

  return v_order_id;
end;
$$ language plpgsql;

-- =================================================================================================
-- 6. Views
-- =================================================================================================

-- A view to combine product and variant details for easy querying.
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


-- A view for dashboard metrics, pre-calculating key values.
create or replace view public.company_dashboard_metrics as
select
    o.company_id,
    sum(oli.price * oli.quantity) as total_revenue,
    sum((oli.price - coalesce(oli.cost_at_time, 0)) * oli.quantity) as total_profit,
    count(distinct o.id) as total_orders,
    (sum(oli.price * oli.quantity) / count(distinct o.id)) as average_order_value,
    date_trunc('day', o.created_at) as sale_date
from
    public.orders o
join
    public.order_line_items oli on o.id = oli.order_id
group by
    o.company_id, date_trunc('day', o.created_at);

-- =================================================================================================
-- 7. Advanced Functions for Analytics
-- =================================================================================================
create or replace function public.get_dashboard_metrics(p_company_id uuid, p_days integer)
returns table (
    total_sales_value numeric,
    total_profit numeric,
    total_orders bigint,
    average_order_value numeric,
    total_inventory_value numeric,
    total_skus bigint,
    low_stock_items_count bigint,
    dead_stock_items_count bigint,
    top_customers_data jsonb,
    inventory_by_category_data jsonb,
    sales_trend_data jsonb
) as $$
begin
    return query
    with date_series as (
        select generate_series(
            current_date - (p_days - 1) * interval '1 day',
            current_date,
            '1 day'
        )::date as full_date
    ),
    company_metrics as (
        select * from public.company_dashboard_metrics
        where company_id = p_company_id
        and sale_date >= current_date - (p_days - 1) * interval '1 day'
    )
    select
        p_company_id::uuid as company_id,
        (select sum(total_revenue) from company_metrics)::numeric,
        (select sum(total_profit) from company_metrics)::numeric,
        (select count(*) from public.orders where company_id = p_company_id and created_at >= (now() - (p_days || ' days')::interval))::bigint,
        (select avg(total_amount) from public.orders where company_id = p_company_id and created_at >= (now() - (p_days || ' days')::interval))::numeric,
        (select sum(cost * inventory_quantity) from public.product_variants where company_id = p_company_id)::numeric,
        (select count(*) from public.product_variants where company_id = p_company_id)::bigint,
        0::bigint, -- low_stock_items_count placeholder
        0::bigint, -- dead_stock_items_count placeholder
        (select jsonb_agg(c) from (select customer_name as name, total_spent as value from public.customers where company_id = p_company_id order by total_spent desc limit 5) c)::jsonb,
        (select jsonb_agg(cat) from (select product_type as name, sum(cost * inventory_quantity) as value from public.product_variants pv join public.products p on pv.product_id = p.id where p.company_id = p_company_id and p.product_type is not null group by p.product_type) cat)::jsonb,
        (
            select jsonb_agg(st)
            from (
                select
                    ds.full_date as date,
                    coalesce(cm.total_revenue, 0) as "Sales"
                from date_series ds
                left join company_metrics cm on ds.full_date = cm.sale_date
                order by ds.full_date
            ) st
        )::jsonb;
end;
$$ language plpgsql;


-- =================================================================================================
-- 8. Row-Level Security (RLS)
-- =================================================================================================

-- Generic function to check if the current user belongs to the company of a given record.
create or replace function public.is_member_of_company(p_company_id uuid)
returns boolean as $$
begin
  return exists (select 1 from public.company_users where company_id = p_company_id and user_id = auth.uid());
end;
$$ language plpgsql;

-- Apply RLS to all tables
alter table public.companies enable row level security;
drop policy if exists "Allow full access based on company_id" on public.companies;
create policy "Allow full access based on company_id" on public.companies for all using (id = get_current_company_id()) with check (id = get_current_company_id());

alter table public.company_settings enable row level security;
drop policy if exists "Allow full access based on company_id" on public.company_settings;
create policy "Allow full access based on company_id" on public.company_settings for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

alter table public.suppliers enable row level security;
drop policy if exists "Allow full access based on company_id" on public.suppliers;
create policy "Allow full access based on company_id" on public.suppliers for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

alter table public.products enable row level security;
drop policy if exists "Allow full access based on company_id" on public.products;
create policy "Allow full access based on company_id" on public.products for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

alter table public.product_variants enable row level security;
drop policy if exists "Allow full access based on company_id" on public.product_variants;
create policy "Allow full access based on company_id" on public.product_variants for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

alter table public.customers enable row level security;
drop policy if exists "Allow full access based on company_id" on public.customers;
create policy "Allow full access based on company_id" on public.customers for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

alter table public.orders enable row level security;
drop policy if exists "Allow full access based on company_id" on public.orders;
create policy "Allow full access based on company_id" on public.orders for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

alter table public.order_line_items enable row level security;
drop policy if exists "Allow full access based on company_id" on public.order_line_items;
create policy "Allow full access based on company_id" on public.order_line_items for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

alter table public.inventory_ledger enable row level security;
drop policy if exists "Allow full access based on company_id" on public.inventory_ledger;
create policy "Allow full access based on company_id" on public.inventory_ledger for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

alter table public.company_users enable row level security;
drop policy if exists "Allow access to own company users" on public.company_users;
create policy "Allow access to own company users" on public.company_users for all using (company_id = get_current_company_id());

alter table public.integrations enable row level security;
drop policy if exists "Allow access based on company_id" on public.integrations;
create policy "Allow access based on company_id" on public.integrations for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

alter table public.webhook_events enable row level security;
drop policy if exists "Allow access based on company membership" on public.webhook_events;
create policy "Allow access based on company membership" on public.webhook_events for all using (
  exists (
    select 1 from public.integrations i
    where i.id = webhook_events.integration_id and i.company_id = get_current_company_id()
  )
);

alter table public.conversations enable row level security;
drop policy if exists "Allow access to own conversations" on public.conversations;
create policy "Allow access to own conversations" on public.conversations for all using (user_id = auth.uid());

alter table public.messages enable row level security;
drop policy if exists "Allow access based on company_id" on public.messages;
create policy "Allow access based on company_id" on public.messages for all using (company_id = get_current_company_id());

alter table public.user_feedback enable row level security;
drop policy if exists "Allow access based on company_id" on public.user_feedback;
create policy "Allow access based on company_id" on public.user_feedback for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());


-- Disable RLS for service_role access. Important for server-side functions.
alter table public.companies disable row level security;
alter table public.company_settings disable row level security;
alter table public.suppliers disable row level security;
alter table public.products disable row level security;
alter table public.product_variants disable row level security;
alter table public.customers disable row level security;
alter table public.orders disable row level security;
alter table public.order_line_items disable row level security;
alter table public.inventory_ledger disable row level security;
alter table public.company_users disable row level security;
alter table public.integrations disable row level security;
alter table public.webhook_events disable row level security;
alter table public.conversations disable row level security;
alter table public.messages disable row level security;
alter table public.user_feedback disable row level security;

grant usage on schema public to postgres, anon, authenticated, service_role;
grant all privileges on all tables in schema public to postgres, anon, authenticated, service_role;
grant all privileges on all functions in schema public to postgres, anon, authenticated, service_role;
grant all privileges on all sequences in schema public to postgres, anon, authenticated, service_role;
