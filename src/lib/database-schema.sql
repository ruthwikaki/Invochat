
-- ===============================================================================================
-- InvoChat Database Schema
--
-- This script is designed to be idempotent (re-runnable) and sets up the entire public schema
-- for the InvoChat application, including tables, functions, and security policies.
-- ===============================================================================================


-- ===============================================================================================
-- 1. EXTENSIONS
--
-- Enable necessary PostgreSQL extensions.
-- ===============================================================================================

-- Enable the pgcrypto extension for gen_random_uuid()
create extension if not exists pgcrypto with schema public;

-- Enable the uuid-ossp extension for additional UUID functions if needed
create extension if not exists "uuid-ossp" with schema public;


-- ===============================================================================================
-- 2. TABLES
--
-- Define the core tables for the application. All tables are created with "IF NOT EXISTS"
-- to ensure the script can be re-run without errors.
-- ===============================================================================================

-- Stores company information. Each user belongs to one company.
create table if not exists public.companies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  deleted_at timestamptz,
  created_at timestamptz not null default now()
);
comment on table public.companies is 'Stores company information. Each company is a distinct tenant.';

-- Stores user information and their role within a company.
create table if not exists public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  company_id uuid not null references public.companies(id),
  email text,
  role text default 'member'::text not null check (role in ('owner', 'admin', 'member')),
  deleted_at timestamptz,
  created_at timestamptz default now()
);
comment on table public.users is 'Stores application-specific user data, linking auth.users to a company.';

-- Stores company-specific settings and business rules.
create table if not exists public.company_settings (
  company_id uuid primary key references public.companies(id) on delete cascade,
  dead_stock_days integer not null default 90,
  fast_moving_days integer not null default 30,
  overstock_multiplier integer not null default 3,
  high_value_threshold integer not null default 100000, -- in cents
  predictive_stock_days integer not null default 7,
  currency text default 'USD'::text,
  timezone text default 'UTC'::text,
  promo_sales_lift_multiplier real not null default 2.5,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);
comment on table public.company_settings is 'Configuration and business rules for each company.';

-- Stores product master data.
create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id),
  title text not null,
  description text,
  handle text,
  product_type text,
  tags text[],
  status text,
  image_url text,
  external_product_id text,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  constraint unique_external_product_id unique (company_id, external_product_id)
);
comment on table public.products is 'Master data for products. A product can have multiple variants.';

-- Stores product variants (SKUs). This is the core inventory item.
create table if not exists public.product_variants (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  company_id uuid not null references public.companies(id),
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
  external_variant_id text,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  constraint unique_sku_per_company unique (company_id, sku),
  constraint unique_external_variant_id unique (company_id, external_variant_id)
);
comment on table public.product_variants is 'Specific variants of a product, representing the stock-keeping unit (SKU).';

-- Stores customer information.
create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id),
  customer_name text,
  email text,
  total_orders integer default 0,
  total_spent integer default 0, -- in cents
  first_order_date date,
  deleted_at timestamptz,
  created_at timestamptz not null default now()
);
comment on table public.customers is 'Stores customer data, aggregated from sales.';

-- Stores sales orders.
create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id),
  customer_id uuid references public.customers(id) on delete set null,
  order_number text not null,
  external_order_id text,
  financial_status text,
  fulfillment_status text,
  currency text,
  subtotal integer, -- in cents
  total_tax integer, -- in cents
  total_shipping integer, -- in cents
  total_discounts integer, -- in cents
  total_amount integer not null, -- in cents
  source_platform text,
  notes text,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);
comment on table public.orders is 'Records sales orders from all integrated platforms.';

-- Stores individual line items for each order.
create table if not exists public.order_line_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  variant_id uuid references public.product_variants(id) on delete set null,
  company_id uuid not null references public.companies(id),
  product_name text,
  variant_title text,
  sku text,
  quantity integer not null,
  price integer not null, -- in cents
  total_discount integer, -- in cents
  tax_amount integer, -- in cents
  cost_at_time integer, -- in cents
  external_line_item_id text
);
comment on table public.order_line_items is 'Individual items within a sales order.';

-- Stores supplier information.
create table if not exists public.suppliers (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id),
  name text not null,
  email text,
  phone text,
  default_lead_time_days integer,
  notes text,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);
comment on table public.suppliers is 'Stores vendor and supplier information.';

-- Joins products with their primary suppliers.
create table if not exists public.product_supplier (
  product_id uuid not null references public.products(id) on delete cascade,
  supplier_id uuid not null references public.suppliers(id) on delete cascade,
  company_id uuid not null references public.companies(id),
  is_primary boolean default true,
  primary key (product_id, supplier_id, company_id)
);
comment on table public.product_supplier is 'Associates products with their suppliers.';

-- Stores sales channel fees for accurate net margin calculations.
create table if not exists public.channel_fees (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id),
  channel_name text not null,
  percentage_fee numeric not null,
  fixed_fee integer not null, -- in cents
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  constraint unique_channel_per_company unique (company_id, channel_name)
);
comment on table public.channel_fees is 'Stores fee structures for different sales channels.';

-- Transactional log of all inventory movements.
create table if not exists public.inventory_ledger (
  id uuid primary key default gen_random_uuid(),
  variant_id uuid not null references public.product_variants(id) on delete cascade,
  company_id uuid not null references public.companies(id),
  change_type text not null, -- e.g., 'sale', 'restock', 'return', 'adjustment'
  quantity_change integer not null,
  new_quantity integer not null,
  related_id uuid, -- e.g., order_id, purchase_order_id
  notes text,
  created_at timestamptz not null default now()
);
comment on table public.inventory_ledger is 'An immutable log of all inventory changes for auditing.';

-- Stores chat conversation metadata.
create table if not exists public.conversations (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users on delete cascade,
    company_id uuid not null references public.companies on delete cascade,
    title text not null,
    is_starred boolean default false,
    created_at timestamptz not null default now(),
    last_accessed_at timestamptz not null default now()
);
comment on table public.conversations is 'Stores metadata for user chat sessions.';

-- Stores individual chat messages.
create table if not exists public.messages (
    id uuid primary key default gen_random_uuid(),
    conversation_id uuid not null references public.conversations on delete cascade,
    company_id uuid not null references public.companies on delete cascade,
    role text not null check (role in ('user', 'assistant')),
    content text,
    visualization jsonb,
    confidence numeric,
    assumptions text[],
    component text,
    component_props jsonb,
    is_error boolean default false,
    created_at timestamptz not null default now()
);
comment on table public.messages is 'Stores individual messages within a chat conversation.';

-- Stores integration connection details.
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
    updated_at timestamptz
);
comment on table public.integrations is 'Stores details of connected third-party platforms.';

-- Stores a log of webhook events to prevent replay attacks.
create table if not exists public.webhook_events (
    id uuid primary key default gen_random_uuid(),
    integration_id uuid not null references public.integrations(id) on delete cascade,
    webhook_id text not null,
    created_at timestamptz default now(),
    constraint unique_webhook_event unique (integration_id, webhook_id)
);
comment on table public.webhook_events is 'Logs processed webhook IDs to prevent replay attacks.';

-- Stores user feedback on AI responses for model tuning.
create table if not exists public.user_feedback (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id),
    company_id uuid not null references public.companies(id),
    subject_id text not null, -- e.g., message_id, anomaly_id
    subject_type text not null, -- e.g., 'anomaly_explanation', 'chat_response'
    feedback text not null check (feedback in ('helpful', 'unhelpful')),
    created_at timestamptz not null default now()
);
comment on table public.user_feedback is 'Captures user feedback on AI-generated content.';

-- Stores a general audit log for important actions.
create table if not exists public.audit_log (
    id bigserial primary key,
    company_id uuid references public.companies(id),
    user_id uuid references auth.users(id),
    action text not null,
    details jsonb,
    created_at timestamptz default now()
);
comment on table public.audit_log is 'A general-purpose audit trail for significant application events.';

-- Stores information about data export jobs.
create table if not exists public.export_jobs (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id),
    requested_by_user_id uuid not null references auth.users(id),
    status text not null default 'pending', -- pending, processing, completed, failed
    download_url text,
    expires_at timestamptz,
    created_at timestamptz not null default now()
);
comment on table public.export_jobs is 'Tracks asynchronous data export jobs.';


-- ===============================================================================================
-- 3. VIEWS
--
-- Create materialized views for performance-intensive dashboard queries.
-- ===============================================================================================

drop materialized view if exists public.company_dashboard_metrics;
create materialized view if not exists public.company_dashboard_metrics as
select
  c.id as company_id,
  coalesce(sum(o.total_amount), 0)::integer as total_sales_value,
  coalesce(sum(oli.price * oli.quantity - coalesce(oli.cost_at_time, 0) * oli.quantity), 0)::integer as total_profit,
  count(distinct o.id) as total_orders,
  (coalesce(sum(o.total_amount), 0) / nullif(count(distinct o.id), 0))::integer as average_order_value,
  count(distinct pv.id) as total_skus,
  coalesce(sum(pv.inventory_quantity * pv.cost), 0)::integer as total_inventory_value
from companies c
left join orders o on c.id = o.company_id
left join order_line_items oli on o.id = oli.order_id
left join product_variants pv on c.id = pv.company_id
group by c.id;


-- ===============================================================================================
-- 4. INDEXES
--
-- Add indexes to foreign keys and commonly queried columns for performance.
-- ===============================================================================================
create index if not exists idx_users_company_id on public.users(company_id);
create index if not exists idx_products_company_id on public.products(company_id);
create index if not exists idx_product_variants_product_id on public.product_variants(product_id);
create index if not exists idx_product_variants_company_id_sku on public.product_variants(company_id, sku);
create index if not exists idx_orders_company_id_created_at on public.orders(company_id, created_at desc);
create index if not exists idx_order_line_items_order_id on public.order_line_items(order_id);
create index if not exists idx_order_line_items_variant_id on public.order_line_items(variant_id);
create index if not exists idx_inventory_ledger_variant_id_created_at on public.inventory_ledger(variant_id, created_at desc);
create index if not exists idx_inventory_ledger_company_id_created_at on public.inventory_ledger(company_id, created_at desc);
create index if not exists idx_suppliers_company_id on public.suppliers(company_id);
create index if not exists idx_customers_company_id on public.customers(company_id);
create index if not exists idx_conversations_user_id on public.conversations(user_id);
create index if not exists idx_messages_conversation_id on public.messages(conversation_id);
create index if not exists idx_integrations_company_id on public.integrations(company_id);


-- ===============================================================================================
-- 5. SECURITY & ROW-LEVEL SECURITY (RLS)
--
-- This section defines the security rules for the application. It includes helper functions
-- to get the current user's context and policies to enforce multi-tenancy.
--
-- The structure is critical:
-- 1. Drop all dependent policies.
-- 2. Drop all helper functions.
-- 3. Re-create all helper functions.
-- 4. Re-create all policies.
-- ===============================================================================================

-- Step 1: Drop all existing policies that depend on the helper functions.
-- This is necessary to avoid dependency errors when recreating the functions.

drop policy if exists "Allow full access based on company_id" on public.companies;
drop policy if exists "Allow full access based on company_id" on public.company_settings;
drop policy if exists "Users can only see their own company's data." on public.company_settings;
drop policy if exists "Allow full access based on company_id" on public.products;
drop policy if exists "Users can only see their own company's data." on public.products;
drop policy if exists "Allow full access based on company_id" on public.product_variants;
drop policy if exists "Users can only see their own company's data." on public.product_variants;
drop policy if exists "Allow full access based on company_id" on public.inventory_ledger;
drop policy if exists "Users can only see their own company's data." on public.inventory_ledger;
drop policy if exists "Allow full access based on company_id" on public.customers;
drop policy if exists "Users can only see their own company's data." on public.customers;
drop policy if exists "Allow full access based on company_id" on public.orders;
drop policy if exists "Users can only see their own company's data." on public.orders;
drop policy if exists "Allow full access based on company_id" on public.order_line_items;
drop policy if exists "Users can only see their own company's data." on public.order_line_items;
drop policy if exists "Allow full access based on company_id" on public.suppliers;
drop policy if exists "Users can only see their own company's data." on public.suppliers;
drop policy if exists "Allow full access to own conversations" on public.conversations;
drop policy if exists "Users can only see their own company's data." on public.conversations;
drop policy if exists "Allow full access to messages in own conversations" on public.messages;
drop policy if exists "Users can only see their own company's data." on public.messages;
drop policy if exists "Allow full access based on company_id" on public.integrations;
drop policy if exists "Users can only see their own company's data." on public.integrations;
drop policy if exists "Allow read access to company audit log" on public.audit_log;
drop policy if exists "Allow read access to webhook_events" on public.webhook_events;
drop policy if exists "Users can see other users in their own company." on public.users;
drop policy if exists "Allow read access to other users in same company" on public.users;
drop policy if exists "Users can only see their own company." on public.companies;


-- Step 2: Drop the helper functions.

drop function if exists public.get_current_company_id();
drop function if exists public.get_current_user_role();


-- Step 3: Re-create the helper functions.

create or replace function public.get_current_company_id()
returns uuid
language sql
security definer
stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid;
$$;
comment on function public.get_current_company_id() is 'Retrieves the company_id from the current user''s JWT claims.';

create or replace function public.get_current_user_role()
returns text
language sql
security definer
stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'user_role', '');
$$;
comment on function public.get_current_user_role() is 'Retrieves the user_role from the current user''s JWT claims.';


-- Step 4: Re-create all tables, triggers, and policies.

-- This trigger function automatically creates a company and a user in the public schema
-- when a new user signs up in the auth schema.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid;
  v_user_role text;
begin
  -- Create a new company for the user
  insert into public.companies (name)
  values (new.raw_user_meta_data->>'company_name')
  returning id into v_company_id;

  -- Set the user's role to 'owner'
  v_user_role := 'owner';

  -- Create a corresponding user in the public.users table
  insert into public.users (id, company_id, email, role)
  values (new.id, v_company_id, new.email, v_user_role);

  -- Update the user's app_metadata in the auth schema with the new company_id and role
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', v_company_id, 'user_role', v_user_role)
  where id = new.id;

  return new;
end;
$$;
comment on function public.handle_new_user() is 'Trigger function to provision a new company and user upon signup.';

-- Drop existing trigger to ensure a clean slate, then re-create it.
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- This trigger updates the `inventory_quantity` on the `product_variants` table
-- whenever a new entry is added to the `inventory_ledger`.
create or replace function public.update_variant_quantity_from_ledger()
returns trigger
language plpgsql
as $$
begin
  update public.product_variants
  set inventory_quantity = new.new_quantity
  where id = new.variant_id;
  return new;
end;
$$;
comment on function public.update_variant_quantity_from_ledger() is 'Trigger to keep inventory_quantity on product_variants in sync with the ledger.';

-- Drop existing trigger, then re-create it.
drop trigger if exists on_inventory_ledger_insert on public.inventory_ledger;
create trigger on_inventory_ledger_insert
  after insert on public.inventory_ledger
  for each row execute procedure public.update_variant_quantity_from_ledger();


-- Step 5: Enable Row-Level Security and create policies for each table.

alter table public.companies enable row level security;
create policy "Users can only see their own company." on public.companies for select using (id = get_current_company_id());
create policy "Allow full access based on company_id" on public.companies for all using (id = get_current_company_id());

alter table public.users enable row level security;
create policy "Users can see other users in their own company." on public.users for select using (company_id = get_current_company_id());
create policy "Allow read access to other users in same company" on public.users for select using (company_id = get_current_company_id());

alter table public.company_settings enable row level security;
create policy "Users can only see their own company's data." on public.company_settings for select using (company_id = get_current_company_id());
create policy "Allow full access based on company_id" on public.company_settings for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

alter table public.products enable row level security;
create policy "Users can only see their own company's data." on public.products for select using (company_id = get_current_company_id());
create policy "Allow full access based on company_id" on public.products for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

alter table public.product_variants enable row level security;
create policy "Users can only see their own company's data." on public.product_variants for select using (company_id = get_current_company_id());
create policy "Allow full access based on company_id" on public.product_variants for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

alter table public.inventory_ledger enable row level security;
create policy "Users can only see their own company's data." on public.inventory_ledger for select using (company_id = get_current_company_id());
create policy "Allow full access based on company_id" on public.inventory_ledger for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

alter table public.customers enable row level security;
create policy "Users can only see their own company's data." on public.customers for select using (company_id = get_current_company_id());
create policy "Allow full access based on company_id" on public.customers for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

alter table public.orders enable row level security;
create policy "Users can only see their own company's data." on public.orders for select using (company_id = get_current_company_id());
create policy "Allow full access based on company_id" on public.orders for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

alter table public.order_line_items enable row level security;
create policy "Users can only see their own company's data." on public.order_line_items for select using (company_id = get_current_company_id());
create policy "Allow full access based on company_id" on public.order_line_items for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

alter table public.suppliers enable row level security;
create policy "Users can only see their own company's data." on public.suppliers for select using (company_id = get_current_company_id());
create policy "Allow full access based on company_id" on public.suppliers for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

alter table public.conversations enable row level security;
create policy "Users can only see their own company's data." on public.conversations for select using (company_id = get_current_company_id());
create policy "Allow full access to own conversations" on public.conversations for all using (user_id = auth.uid());

alter table public.messages enable row level security;
create policy "Users can only see their own company's data." on public.messages for select using (company_id = get_current_company_id());
create policy "Allow full access to messages in own conversations" on public.messages for all using (conversation_id in (select id from conversations where user_id = auth.uid()));

alter table public.integrations enable row level security;
create policy "Users can only see their own company's data." on public.integrations for select using (company_id = get_current_company_id());
create policy "Allow full access based on company_id" on public.integrations for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

alter table public.audit_log enable row level security;
create policy "Allow read access to company audit log" on public.audit_log for select using (company_id = get_current_company_id());

alter table public.webhook_events enable row level security;
create policy "Allow read access to webhook_events" on public.webhook_events for select using (true); -- Webhooks are validated by HMAC, not user session

-- Disable RLS for vault secrets because they are managed by Supabase's internal functions
alter table if exists vault.secrets disable row level security;


-- ===============================================================================================
-- 6. RPC FUNCTIONS
--
-- Functions designed to be called from the application layer via Supabase's RPC mechanism.
-- These encapsulate business logic and complex queries.
-- ===============================================================================================

drop function if exists public.get_dashboard_metrics(uuid, integer);
create or replace function public.get_dashboard_metrics(p_company_id uuid, p_days integer)
returns table (
  total_sales_value integer,
  total_profit integer,
  average_order_value integer,
  total_orders bigint,
  total_skus bigint,
  low_stock_items_count bigint,
  dead_stock_items_count bigint,
  total_inventory_value integer,
  sales_trend_data jsonb,
  inventory_by_category_data jsonb,
  top_customers_data jsonb
)
language plpgsql
as $$
declare
  v_end_date timestamptz := now();
  v_start_date timestamptz := v_end_date - (p_days || ' days')::interval;
begin
  return query
  with date_series as (
    select generate_series(v_start_date::date, v_end_date::date, '1 day'::interval) as date
  ),
  company_context as (
    select p_company_id::uuid as company_id
  )
  select
    -- Core Metrics
    (select coalesce(sum(o.total_amount), 0) from orders o where o.company_id = cc.company_id and o.created_at between v_start_date and v_end_date)::integer as total_sales_value,
    (select coalesce(sum(oli.quantity * (oli.price - coalesce(oli.cost_at_time, 0))), 0) from order_line_items oli join orders o on oli.order_id = o.id where o.company_id = cc.company_id and o.created_at between v_start_date and v_end_date)::integer as total_profit,
    (select coalesce(avg(o.total_amount), 0) from orders o where o.company_id = cc.company_id and o.created_at between v_start_date and v_end_date)::integer as average_order_value,
    (select count(*) from orders o where o.company_id = cc.company_id and o.created_at between v_start_date and v_end_date) as total_orders,
    (select count(*) from product_variants pv where pv.company_id = cc.company_id and pv.deleted_at is null) as total_skus,
    -- Inventory Health
    0::bigint as low_stock_items_count, -- Placeholder, to be implemented
    0::bigint as dead_stock_items_count, -- Placeholder
    (select coalesce(sum(pv.inventory_quantity * pv.cost), 0) from product_variants pv where pv.company_id = cc.company_id and pv.deleted_at is null)::integer as total_inventory_value,
    -- Chart Data
    (
      select jsonb_agg(d) from (
        select ds.date::text, coalesce(sum(o.total_amount), 0)::integer as "Sales"
        from date_series ds
        left join orders o on o.created_at::date = ds.date and o.company_id = cc.company_id
        group by ds.date
        order by ds.date
      ) d
    ) as sales_trend_data,
    (
        select jsonb_agg(d) from (
            select
                coalesce(p.product_type, 'Uncategorized') as name,
                sum(pv.inventory_quantity * pv.cost)::integer as value
            from product_variants pv
            join products p on pv.product_id = p.id
            where pv.company_id = cc.company_id and pv.deleted_at is null
            group by p.product_type
            order by value desc
            limit 10
        ) d
    ) as inventory_by_category_data,
    (
        select jsonb_agg(d) from (
            select c.customer_name as name, sum(o.total_amount)::integer as value
            from orders o
            join customers c on o.customer_id = c.id
            where o.company_id = cc.company_id
            group by c.customer_name
            order by value desc
            limit 5
        ) d
    ) as top_customers_data
  from company_context cc;
end;
$$;


drop function if exists public.get_inventory_analytics(uuid);
create or replace function public.get_inventory_analytics(p_company_id uuid)
returns table (
    total_inventory_value integer,
    total_products bigint,
    total_variants bigint,
    low_stock_items bigint
)
language plpgsql
as $$
begin
    return query
    select
        (select coalesce(sum(pv.inventory_quantity * pv.cost), 0) from public.product_variants pv where pv.company_id = p_company_id and pv.deleted_at is null)::integer,
        (select count(*) from public.products p where p.company_id = p_company_id and p.deleted_at is null),
        (select count(*) from public.product_variants pv where pv.company_id = p_company_id and pv.deleted_at is null),
        0::bigint; -- Placeholder for low stock
end;
$$;

drop function if exists public.record_order_from_platform(uuid, jsonb, text);
drop function if exists public.record_order_from_platform(company_id uuid, order_payload jsonb, platform text);
create or replace function public.record_order_from_platform(
    p_company_id uuid,
    p_order_payload jsonb,
    p_platform text
)
returns void
language plpgsql
as $$
declare
    v_customer_id uuid;
    v_order_id uuid;
    v_line_item jsonb;
    v_variant_id uuid;
    v_cost integer;
begin
    -- Upsert customer
    insert into public.customers (company_id, email, customer_name)
    values (
        p_company_id,
        p_order_payload->'billing'->>'email',
        p_order_payload->>'first_name' || ' ' || p_order_payload->>'last_name'
    )
    on conflict (company_id, email) do update set
        customer_name = excluded.customer_name
    returning id into v_customer_id;

    -- Upsert order
    insert into public.orders (company_id, external_order_id, customer_id, order_number, financial_status, fulfillment_status, currency, total_amount, source_platform, created_at, updated_at)
    values (
        p_company_id,
        p_order_payload->>'id',
        v_customer_id,
        p_order_payload->>'number',
        p_order_payload->>'financial_status',
        p_order_payload->>'fulfillment_status',
        p_order_payload->>'currency',
        (p_order_payload->>'total'::numeric * 100)::integer,
        p_platform,
        (p_order_payload->>'date_created_gmt')::timestamptz,
        (p_order_payload->>'date_modified_gmt')::timestamptz
    )
    on conflict (company_id, external_order_id) do update set
        financial_status = excluded.financial_status,
        fulfillment_status = excluded.fulfillment_status,
        total_amount = excluded.total_amount,
        updated_at = excluded.updated_at
    returning id into v_order_id;

    -- Insert line items
    for v_line_item in select * from jsonb_array_elements(p_order_payload->'line_items')
    loop
        -- Find variant and its cost
        select pv.id, pv.cost into v_variant_id, v_cost
        from public.product_variants pv
        where pv.company_id = p_company_id
        and pv.sku = v_line_item->>'sku';

        insert into public.order_line_items (order_id, company_id, variant_id, sku, product_name, quantity, price, cost_at_time, external_line_item_id)
        values (
            v_order_id,
            p_company_id,
            v_variant_id,
            v_line_item->>'sku',
            v_line_item->>'name',
            (v_line_item->>'quantity')::integer,
            (v_line_item->>'price'::numeric * 100)::integer,
            v_cost,
            v_line_item->>'id'
        )
        on conflict do nothing;
    end loop;
end;
$$;
