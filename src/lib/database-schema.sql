
-- Drop dependent objects first in the correct order
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.get_current_company_id();
DROP FUNCTION IF EXISTS public.get_user_role();


-- =============================================
-- Helper Functions
-- =============================================

-- Function to get the current user's company_id from their JWT claims
create or replace function public.get_current_company_id()
returns uuid
language sql stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::json->>'company_id', '')::uuid;
$$;

-- Function to get the current user's role from their JWT claims
create or replace function public.get_user_role()
returns text
language sql stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::json->>'user_role', '');
$$;


-- =============================================
-- Core Tables
-- =============================================

-- Companies Table
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid default gen_random_uuid() primary key,
    name text not null,
    created_at timestamptz default now() not null
);

-- Users Table
-- Note: This table is an extension of auth.users and is linked by the id
CREATE TABLE IF NOT EXISTS public.users (
    id uuid primary key references auth.users(id) on delete cascade,
    company_id uuid references public.companies(id) on delete set null,
    role text default 'Member' not null,
    invited_at timestamptz default now(),
    last_login_at timestamptz
);

-- Company Settings Table
CREATE TABLE IF NOT EXISTS public.company_settings (
  company_id uuid primary key references public.companies(id) on delete cascade,
  dead_stock_days integer not null default 90,
  fast_moving_days integer not null default 30,
  overstock_multiplier numeric not null default 3.0,
  high_value_threshold numeric not null default 1000.00,
  predictive_stock_days integer not null default 7,
  created_at timestamptz default now() not null,
  updated_at timestamptz
);

-- Products Table
CREATE TABLE IF NOT EXISTS public.products (
  id uuid default gen_random_uuid() primary key,
  company_id uuid not null references public.companies(id) on delete cascade,
  title text not null,
  description text,
  handle text,
  product_type text,
  tags text[],
  status text,
  image_url text,
  external_product_id text,
  created_at timestamptz default now() not null,
  updated_at timestamptz,
  unique(company_id, external_product_id)
);
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_products_tags ON public.products USING GIN(tags);

-- Product Variants Table
CREATE TABLE IF NOT EXISTS public.product_variants (
  id uuid default gen_random_uuid() primary key,
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
  compare_at_price integer,
  cost integer, -- in cents
  inventory_quantity integer not null default 0,
  external_variant_id text,
  created_at timestamptz default now() not null,
  updated_at timestamptz,
  unique(company_id, sku),
  unique(company_id, external_variant_id)
);
CREATE INDEX IF NOT EXISTS idx_product_variants_company_id ON public.product_variants(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants(product_id);

-- Customers Table
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid default gen_random_uuid() primary key,
    company_id uuid not null references public.companies(id) on delete cascade,
    customer_name text,
    email text,
    total_orders integer not null default 0,
    total_spent integer not null default 0, -- in cents
    first_order_date timestamptz,
    created_at timestamptz default now() not null,
    deleted_at timestamptz,
    unique(company_id, email)
);

-- Orders Table
CREATE TABLE IF NOT EXISTS public.orders (
    id uuid default gen_random_uuid() primary key,
    company_id uuid not null references public.companies(id) on delete cascade,
    order_number text not null,
    external_order_id text,
    customer_id uuid references public.customers(id) on delete set null,
    financial_status text,
    fulfillment_status text,
    currency text,
    subtotal integer not null, -- in cents
    total_tax integer,
    total_shipping integer,
    total_discounts integer,
    total_amount integer not null,
    source_platform text,
    created_at timestamptz default now() not null,
    updated_at timestamptz
);

-- Order Line Items Table
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid default gen_random_uuid() primary key,
    order_id uuid not null references public.orders(id) on delete cascade,
    variant_id uuid references public.product_variants(id) on delete set null,
    company_id uuid not null references public.companies(id) on delete cascade,
    product_name text,
    variant_title text,
    sku text,
    quantity integer not null,
    price integer not null CHECK (price >= 0), -- in cents
    total_discount integer,
    tax_amount integer,
    cost_at_time integer CHECK (cost_at_time >= 0), -- in cents
    external_line_item_id text
);

-- Suppliers Table
CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid default gen_random_uuid() primary key,
    company_id uuid not null references public.companies(id) on delete cascade,
    name text not null,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz default now() not null
);

-- Inventory Ledger Table
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid default gen_random_uuid() primary key,
    company_id uuid not null references public.companies(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    change_type text not null,
    quantity_change integer not null,
    new_quantity integer not null,
    related_id uuid, -- e.g., order_id, po_id
    notes text,
    created_at timestamptz default now() not null
);

-- Integrations Table
CREATE TABLE IF NOT EXISTS public.integrations (
  id uuid default gen_random_uuid() primary key,
  company_id uuid not null references public.companies(id) on delete cascade,
  platform text not null,
  shop_domain text,
  shop_name text,
  is_active boolean default true not null,
  last_sync_at timestamptz,
  sync_status text,
  created_at timestamptz default now() not null,
  updated_at timestamptz,
  unique(company_id, platform)
);

-- Webhook Events Table
CREATE TABLE IF NOT EXISTS public.webhook_events (
  id uuid default gen_random_uuid() primary key,
  integration_id uuid not null references public.integrations(id) on delete cascade,
  webhook_id text not null,
  processed_at timestamptz default now() not null,
  unique(integration_id, webhook_id)
);

-- Audit Log Table
CREATE TABLE IF NOT EXISTS public.audit_log (
  id uuid default gen_random_uuid() primary key,
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid references auth.users(id),
  action text not null,
  details jsonb,
  created_at timestamptz default now() not null
);


-- =============================================
-- Auth Trigger for New User Setup
-- =============================================
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  v_company_id uuid;
  v_company_name text;
begin
  -- Extract company_name from metadata
  v_company_name := new.raw_user_meta_data->>'company_name';

  -- Create a new company for the user
  insert into public.companies (name)
  values (v_company_name)
  returning id into v_company_id;

  -- Create a corresponding entry in the public.users table
  insert into public.users (id, company_id, role)
  values (new.id, v_company_id, 'Owner');

  -- Update the user's app_metadata with the new company_id and role
  update auth.users
  set app_metadata = jsonb_set(
      jsonb_set(coalesce(app_metadata, '{}'::jsonb), '{company_id}', to_jsonb(v_company_id)),
      '{role}', to_jsonb('Owner'::text)
    )
  where id = new.id;

  return new;
end;
$$;

-- Create the trigger on the auth.users table
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


-- =============================================
-- Row-Level Security (RLS)
-- =============================================
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;

-- Drop existing policies before creating new ones
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.companies;
DROP POLICY IF EXISTS "Allow read access to other users in same company" ON public.users;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.company_settings;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.products;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.product_variants;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.inventory_ledger;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.customers;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.orders;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.order_line_items;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.suppliers;
DROP POLICY IF EXISTS "Allow full access to own conversations" ON public.conversations;
DROP POLICY IF EXISTS "Allow full access to messages in own conversations" ON public.messages;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.integrations;
DROP POLICY IF EXISTS "Allow read access to company audit log" ON public.audit_log;
DROP POLICY IF EXISTS "Allow read access to webhook_events" ON public.webhook_events;

-- Policies for tables
CREATE POLICY "Allow full access based on company_id" ON public.companies FOR ALL USING (id = get_current_company_id()) WITH CHECK (id = get_current_company_id());
CREATE POLICY "Allow read access to other users in same company" ON public.users FOR SELECT USING (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.company_settings FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.products FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.product_variants FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.inventory_ledger FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.customers FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.orders FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.order_line_items FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.suppliers FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Allow full access to own conversations" ON public.conversations FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Allow full access to messages in own conversations" ON public.messages FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.integrations FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Allow read access to company audit log" ON public.audit_log FOR SELECT USING (company_id = get_current_company_id());
CREATE POLICY "Allow read access to webhook_events" ON public.webhook_events FOR SELECT USING (EXISTS (SELECT 1 FROM public.integrations WHERE id = webhook_events.integration_id AND company_id = get_current_company_id()));


-- =============================================
-- Business Logic Functions
-- =============================================

-- Function to record an order from a platform
create or replace function public.record_order_from_platform(
    p_company_id uuid,
    p_order_payload jsonb,
    p_platform text
)
returns void
language plpgsql
security definer
as $$
declare
    v_customer_id uuid;
    v_order_id uuid;
    v_variant_id uuid;
    line_item jsonb;
    v_sku text;
    v_quantity int;
begin
    -- Find or create customer
    insert into public.customers (company_id, email, customer_name)
    values (
        p_company_id,
        p_order_payload->'billing_address'->>'email',
        coalesce(p_order_payload->'billing_address'->>'first_name' || ' ' || p_order_payload->'billing_address'->>'last_name', p_order_payload->'billing_address'->>'email')
    )
    on conflict (company_id, email) do update set customer_name = excluded.customer_name
    returning id into v_customer_id;

    -- Create order
    insert into public.orders (company_id, external_order_id, customer_id, order_number, financial_status, fulfillment_status, currency, subtotal, total_tax, total_shipping, total_discounts, total_amount, source_platform, created_at)
    values (
        p_company_id,
        p_order_payload->>'id',
        v_customer_id,
        p_order_payload->>'name',
        p_order_payload->>'financial_status',
        p_order_payload->>'fulfillment_status',
        p_order_payload->>'currency',
        (p_order_payload->>'subtotal_price')::numeric * 100,
        (p_order_payload->>'total_tax')::numeric * 100,
        (p_order_payload->>'total_shipping_price_set'->'shop_money'->>'amount')::numeric * 100,
        (p_order_payload->>'total_discounts')::numeric * 100,
        (p_order_payload->>'total_price')::numeric * 100,
        p_platform,
        (p_order_payload->>'created_at')::timestamptz
    )
    on conflict do nothing -- Basic idempotency
    returning id into v_order_id;
    
    if v_order_id is null then
      -- Order already existed, do nothing.
      return;
    end if;

    -- Create line items and update inventory
    for line_item in select * from jsonb_array_elements(p_order_payload->'line_items')
    loop
        v_sku := line_item->>'sku';
        v_quantity := (line_item->>'quantity')::int;

        -- Find the corresponding variant_id using the SKU
        select id into v_variant_id from public.product_variants where sku = v_sku and company_id = p_company_id limit 1;
        
        if v_variant_id is not null then
            insert into public.order_line_items (order_id, variant_id, company_id, product_name, sku, quantity, price)
            values (
                v_order_id,
                v_variant_id,
                p_company_id,
                line_item->>'title',
                v_sku,
                v_quantity,
                (line_item->>'price')::numeric * 100
            );

            -- Use a sub-transaction to update inventory to handle potential race conditions
            begin
                update public.product_variants
                set inventory_quantity = inventory_quantity - v_quantity
                where id = v_variant_id and company_id = p_company_id;

                insert into public.inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes)
                select
                    p_company_id,
                    v_variant_id,
                    'sale',
                    -v_quantity,
                    pv.inventory_quantity,
                    v_order_id,
                    'Order #' || p_order_payload->>'name'
                from public.product_variants pv where pv.id = v_variant_id;
            exception
                when others then
                    -- Log the error but don't fail the entire transaction
                    raise warning 'Inventory update failed for SKU %: %', v_sku, SQLERRM;
            end;
        else
            raise warning 'SKU % from order % not found in product_variants table.', v_sku, p_order_payload->>'name';
        end if;
    end loop;
end;
$$;


-- =============================================
-- Materialized Views for Performance
-- =============================================
CREATE MATERIALIZED VIEW IF NOT EXISTS public.company_dashboard_metrics AS
SELECT
    p.company_id,
    COUNT(DISTINCT p.id) AS total_products,
    COUNT(DISTINCT pv.sku) AS total_skus,
    SUM(pv.inventory_quantity) AS total_units,
    SUM(pv.inventory_quantity * pv.cost) / 100.0 AS total_inventory_value
FROM
    public.products p
JOIN
    public.product_variants pv ON p.id = pv.product_id
GROUP BY
    p.company_id;

-- Create a unique index for concurrent refreshing
CREATE UNIQUE INDEX IF NOT EXISTS company_dashboard_metrics_company_id_idx ON public.company_dashboard_metrics(company_id);

-- Function to refresh views
create or replace function public.refresh_all_materialized_views() returns void as $$
begin
    refresh materialized view concurrently public.company_dashboard_metrics;
end;
$$ language plpgsql security definer;
