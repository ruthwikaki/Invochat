
-- InvoChat Database Schema
-- Version: 1.5.0
-- Description: This script sets up all tables, roles, functions, and RLS policies
-- required for the InvoChat application.

-- 1. Extensions
-- Ensure required extensions are enabled.
create extension if not exists "uuid-ossp" with schema extensions;
create extension if not exists "vector" with schema extensions;
create extension if not exists "pg_cron" with schema extensions;
grant usage on schema cron to postgres;
grant all privileges on all tables in schema cron to postgres;


-- 2. Helper Functions
-- These functions are used throughout the schema, particularly for RLS.

-- Function to get the company_id from the current user's JWT claims.
create or replace function public.get_current_company_id()
returns uuid
language sql stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::json->>'company_id', '')::uuid;
$$;

-- Function to get the role from the current user's JWT claims.
create or replace function public.get_current_user_role()
returns text
language sql stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::json->>'user_role', '');
$$;

-- 3. Core Tables

-- Companies table to store company information.
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid not null default uuid_generate_v4() primary key,
    name text not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);
comment on table public.companies is 'Stores company information.';

-- Company Settings table
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid not null primary key references public.companies(id) on delete cascade,
    dead_stock_days integer not null default 90,
    fast_moving_days integer not null default 30,
    overstock_multiplier numeric not null default 3,
    high_value_threshold numeric not null default 1000,
    predictive_stock_days integer not null default 7,
    currency text not null default 'USD',
    timezone text not null default 'UTC',
    tax_rate numeric,
    custom_rules jsonb,
    subscription_plan text,
    subscription_status text,
    subscription_expires_at timestamptz,
    stripe_customer_id text,
    stripe_subscription_id text,
    promo_sales_lift_multiplier numeric not null default 2.5,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);
comment on table public.company_settings is 'Stores business logic settings for each company.';

-- Products table to store product catalog information.
CREATE TABLE IF NOT EXISTS public.products (
    id uuid not null default uuid_generate_v4() primary key,
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
comment on table public.products is 'Stores product catalog information.';
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_products_tags ON public.products USING gin(tags);


-- Product Variants table to store individual SKUs.
CREATE TABLE IF NOT EXISTS public.product_variants (
    id uuid not null default uuid_generate_v4() primary key,
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
    inventory_quantity integer not null default 0,
    external_variant_id text,
    created_at timestamptz not null default now(),
    updated_at timestamptz,
    unique(company_id, sku),
    unique(company_id, external_variant_id)
);
comment on table public.product_variants is 'Stores individual stock keeping units (SKUs) for each product.';
CREATE INDEX IF NOT EXISTS idx_product_variants_company_id ON public.product_variants(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_sku ON public.product_variants(sku);


-- Suppliers table
CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid not null default uuid_generate_v4() primary key,
    company_id uuid not null references public.companies(id) on delete cascade,
    name text not null,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz not null default now(),
    unique(company_id, name)
);
comment on table public.suppliers is 'Stores supplier and vendor information.';


-- Inventory Ledger table for tracking stock movements.
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid not null default uuid_generate_v4() primary key,
    company_id uuid not null references public.companies(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    change_type text not null, -- e.g., 'sale', 'purchase_order', 'reconciliation', 'manual_adjustment', 'transfer_in', 'transfer_out'
    quantity_change integer not null,
    new_quantity integer not null,
    related_id uuid, -- e.g., order_id, purchase_order_id
    notes text,
    created_at timestamptz not null default now()
);
comment on table public.inventory_ledger is 'Records every change in stock quantity for auditing.';
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id ON public.inventory_ledger(variant_id);


-- Customers table
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid not null default uuid_generate_v4() primary key,
    company_id uuid not null references public.companies(id) on delete cascade,
    customer_name text,
    email text,
    total_orders integer not null default 0,
    total_spent integer not null default 0,
    first_order_date date,
    deleted_at timestamptz,
    external_customer_id text,
    created_at timestamptz not null default now(),
    unique(company_id, email)
);
comment on table public.customers is 'Stores customer information.';


-- Orders table
CREATE TABLE IF NOT EXISTS public.orders (
    id uuid not null default uuid_generate_v4() primary key,
    company_id uuid not null references public.companies(id) on delete cascade,
    order_number text not null,
    external_order_id text,
    customer_id uuid references public.customers(id) on delete set null,
    financial_status text,
    fulfillment_status text,
    currency text,
    subtotal integer not null,
    total_tax integer,
    total_shipping integer,
    total_discounts integer,
    total_amount integer not null,
    source_platform text,
    created_at timestamptz not null default now(),
    updated_at timestamptz,
    unique(company_id, external_order_id)
);
comment on table public.orders is 'Stores sales order information.';
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON public.orders(created_at desc);


-- Order Line Items table
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid not null default uuid_generate_v4() primary key,
    order_id uuid not null references public.orders(id) on delete cascade,
    variant_id uuid references public.product_variants(id) on delete set null,
    company_id uuid not null references public.companies(id) on delete cascade,
    product_name text,
    variant_title text,
    sku text,
    quantity integer not null,
    price integer not null CHECK (price >= 0),
    total_discount integer CHECK (total_discount >= 0),
    tax_amount integer CHECK (tax_amount >= 0),
    cost_at_time integer CHECK (cost_at_time >= 0),
    external_line_item_id text,
    unique(order_id, external_line_item_id)
);
comment on table public.order_line_items is 'Stores individual items within a sales order.';
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON public.order_line_items(variant_id);


-- Integrations table
CREATE TABLE IF NOT EXISTS public.integrations (
    id uuid not null default uuid_generate_v4() primary key,
    company_id uuid not null references public.companies(id) on delete cascade,
    platform text not null,
    shop_domain text,
    shop_name text,
    is_active boolean not null default true,
    last_sync_at timestamptz,
    sync_status text,
    created_at timestamptz not null default now(),
    updated_at timestamptz,
    unique(company_id, platform)
);
comment on table public.integrations is 'Stores third-party integration settings.';

-- Purchase Orders table
CREATE TABLE IF NOT EXISTS public.purchase_orders (
  id uuid not null default uuid_generate_v4() primary key,
  company_id uuid not null references public.companies(id) on delete cascade,
  supplier_id uuid references public.suppliers(id) on delete set null,
  status text not null default 'draft',
  po_number text not null,
  total_cost integer not null,
  expected_arrival_date date,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  created_by uuid references auth.users(id),
  unique(company_id, po_number)
);
comment on table public.purchase_orders is 'Stores purchase order information.';

-- Purchase Order Line Items table
CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
  id uuid not null default uuid_generate_v4() primary key,
  purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
  variant_id uuid not null references public.product_variants(id) on delete cascade,
  quantity integer not null,
  cost integer not null CHECK (cost >= 0)
);
comment on table public.purchase_order_line_items is 'Stores individual items within a purchase order.';

-- User Feedback table
CREATE TABLE IF NOT EXISTS public.user_feedback (
    id uuid not null default uuid_generate_v4() primary key,
    user_id uuid not null references auth.users(id),
    company_id uuid not null references public.companies(id),
    subject_id text not null,
    subject_type text not null, -- e.g., 'ai_response', 'suggestion'
    feedback text not null, -- 'helpful' or 'unhelpful'
    created_at timestamptz not null default now()
);
comment on table public.user_feedback is 'Stores user feedback on AI interactions and suggestions.';

-- Webhook Events table
CREATE TABLE IF NOT EXISTS public.webhook_events (
    id uuid not null default uuid_generate_v4() primary key,
    integration_id uuid not null references public.integrations(id) on delete cascade,
    webhook_id text not null,
    processed_at timestamptz not null default now(),
    unique(integration_id, webhook_id)
);
comment on table public.webhook_events is 'Logs incoming webhooks to prevent replay attacks.';


-- 4. Authentication and User Management

-- Function to create a company and associate it with a new user.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  new_company_id uuid;
begin
  -- Create a new company for the user
  insert into public.companies (name)
  values (new.raw_user_meta_data->>'company_name')
  returning id into new_company_id;

  -- Update the user's app_metadata with the new company_id and role
  update auth.users
  set app_metadata = jsonb_set(
      jsonb_set(
          coalesce(app_metadata, '{}'::jsonb),
          '{company_id}', to_jsonb(new_company_id)
      ),
      '{role}', to_jsonb('Owner'::text)
  )
  where id = new.id;
  
  return new;
end;
$$;

-- Trigger to call handle_new_user on new user creation.
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


-- 5. Row Level Security (RLS) Policies

-- Function to dynamically create a standard RLS policy for a table.
create or replace function create_company_rls_policy(table_name text)
returns void as $$
begin
    execute format('
        ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;
    ', table_name);

    -- This check prevents the function from failing on the 'companies' table itself.
    -- The policy for the 'companies' table is created manually below.
    if table_name <> 'companies' then
      execute format('
          DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.%I;
          CREATE POLICY "Allow full access based on company_id"
          ON public.%I
          FOR ALL
          USING (company_id = get_current_company_id())
          WITH CHECK (company_id = get_current_company_id());
      ', table_name, table_name);
    end if;
end;
$$ language plpgsql;

-- Apply RLS to all relevant tables
select create_company_rls_policy(table_name)
from information_schema.tables
where table_schema = 'public' and table_name not in (
    'webhook_events' -- Webhooks are handled by service role
);

-- Manual RLS policy for the 'companies' table
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.companies;
CREATE POLICY "Allow full access based on company_id"
ON public.companies
FOR ALL
-- FIX: Use the 'id' column on the companies table, not 'company_id'
USING (id = get_current_company_id())
WITH CHECK (id = get_current_company_id());


-- 6. Database Views and Materialized Views
-- These views provide pre-aggregated data for performance.

-- Product Variants with Details View
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.*,
    p.title as product_title,
    p.status as product_status,
    p.product_type,
    p.image_url
FROM
    public.product_variants pv
JOIN
    public.products p ON pv.product_id = p.id;


-- 7. Stored Procedures (RPC)
-- These are the functions called by the application backend.

-- Procedure to record a sale from a platform payload
create or replace function public.record_order_from_platform(p_company_id uuid, p_order_payload jsonb, p_platform text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_customer_id uuid;
  v_order_id uuid;
  v_variant_id uuid;
  line_item jsonb;
  v_sku text;
begin
  -- Find or create customer
  -- ... customer logic ...

  -- Create order
  -- ... order logic ...

  -- Process line items and update inventory
  for line_item in select * from jsonb_array_elements(p_order_payload->'line_items') loop
    v_sku := line_item->>'sku';
    
    -- Find variant_id based on SKU
    select id into v_variant_id from product_variants where sku = v_sku and company_id = p_company_id;
    
    if v_variant_id is not null then
      -- Use a transaction block with row-level locking to prevent race conditions
      begin
        -- Lock the variant row for the duration of this transaction
        perform * from product_variants where id = v_variant_id for update;

        -- Update inventory quantity
        update product_variants
        set inventory_quantity = inventory_quantity - (line_item->>'quantity')::int
        where id = v_variant_id;
        
        -- Insert into ledger
        -- ... ledger logic ...
      exception when others then
        raise notice 'Failed to process line item for SKU %: %', v_sku, SQLERRM;
      end;
    else
      raise notice 'SKU not found for line item: %', v_sku;
    end if;
  end loop;
end;
$$;


-- Procedure to get dashboard metrics
create or replace function public.get_dashboard_metrics(p_company_id uuid, p_days int)
returns json
language plpgsql
as $$
declare
  metrics json;
begin
  -- Dummy implementation for now
  select json_build_object(
      'total_revenue', 100000,
      'revenue_change', 10.5,
      'total_sales', 500,
      'sales_change', 5.2,
      'new_customers', 50,
      'customers_change', -2.1,
      'dead_stock_value', 15000,
      'sales_over_time', '[]'::json,
      'top_selling_products', '[]'::json,
      'inventory_summary', '{"total_value": 500000, "in_stock_value": 400000, "low_stock_value": 50000, "dead_stock_value": 50000}'::json
  ) into metrics;
  return metrics;
end;
$$;

-- Procedure to create purchase orders from suggestions
create or replace function create_purchase_orders_from_suggestions(
    p_company_id uuid,
    p_user_id uuid,
    p_suggestions jsonb
)
returns integer as $$
declare
    supplier_id uuid;
    supplier_name text;
    po_id uuid;
    suggestion jsonb;
    item record;
    po_count integer := 0;
    po_total_cost integer;
begin
    for suggestion in select * from jsonb_array_elements(p_suggestions)
    loop
        supplier_id := (suggestion->>'supplier_id')::uuid;
        select name into supplier_name from public.suppliers where id = supplier_id;

        -- Create a new purchase order
        insert into public.purchase_orders (company_id, supplier_id, po_number, total_cost, created_by)
        values (
            p_company_id,
            supplier_id,
            'PO-' || (select count(*) + 1 from purchase_orders where company_id = p_company_id),
            (suggestion->>'suggested_reorder_quantity')::integer * (suggestion->>'unit_cost')::integer,
            p_user_id
        ) returning id into po_id;
        
        -- Add line item to the PO
        insert into public.purchase_order_line_items (purchase_order_id, variant_id, quantity, cost)
        values (
            po_id,
            (suggestion->>'variant_id')::uuid,
            (suggestion->>'suggested_reorder_quantity')::integer,
            (suggestion->>'unit_cost')::integer
        );

        -- Create an audit log entry
        insert into public.audit_log (company_id, user_id, action, details)
        values (
            p_company_id,
            p_user_id,
            'purchase_order_created',
            jsonb_build_object(
                'po_id', po_id,
                'supplier_name', supplier_name,
                'item_count', 1,
                'total_cost', (suggestion->>'suggested_reorder_quantity')::integer * (suggestion->>'unit_cost')::integer
            )
        );

        po_count := po_count + 1;
    end loop;

    return po_count;
end;
$$ language plpgsql security definer;

-- Final cleanup and comments
comment on function public.handle_new_user is 'Trigger function to provision a new company for a user upon sign-up.';
comment on function public.get_current_company_id is 'Retrieves the company ID from the current user''s JWT claims.';

-- END OF SCHEMA
