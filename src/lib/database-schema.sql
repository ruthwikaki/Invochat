-- We are using the pg_vector extension for embedding search.
-- More info: https://github.com/pgvector/pgvector
create extension if not exists vector with schema public;

-- We are using pgcrypto for random UUID generation.
create extension if not exists pgcrypto with schema public;

-- We are using pg_tle for trusted language extensions.
create extension if not exists pgtle with schema public;

-- And we are using vault for secret management.
create extension if not exists "supabase-vault" with schema "vault";


--
-- Tables
--

-- Stores company-level information. Each user belongs to a company.
create table public.companies (
    id uuid primary key default uuid_generate_v4(),
    name text not null,
    owner_id uuid references auth.users(id),
    created_at timestamptz not null default now()
);
comment on table public.companies is 'Stores company-level information. Each user belongs to a company.';

-- Enum for user roles within a company
create type public.company_role as enum ('Owner', 'Admin', 'Member');

-- Associates users with companies and defines their roles.
create table public.company_users (
    company_id uuid not null references public.companies(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    role company_role not null default 'Member',
    primary key(company_id, user_id)
);
comment on table public.company_users is 'Associates users with companies and defines their roles.';


-- This trigger is called when a new user signs up.
-- It creates a new company for the user and assigns them as the owner.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  company_id uuid;
begin
  -- Create a new company for the user
  insert into public.companies (name, owner_id)
  values (new.raw_user_meta_data->>'company_name', new.id)
  returning id into company_id;

  -- Add the user to the company_users table as Owner
  insert into public.company_users (company_id, user_id, role)
  values (company_id, new.id, 'Owner');

  -- Update the user's app_metadata with the company_id
  -- This is critical for RLS policies
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id)
  where id = new.id;
  
  return new;
end;
$$;

-- Create the trigger to fire after a new user is inserted
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


-- Stores company-specific settings for business logic.
create table public.company_settings (
    company_id uuid primary key references public.companies(id) on delete cascade,
    dead_stock_days int not null default 90,
    fast_moving_days int not null default 30,
    predictive_stock_days int not null default 7,
    currency text default 'USD',
    timezone text default 'UTC',
    tax_rate numeric default 0,
    overstock_multiplier int not null default 3,
    high_value_threshold int not null default 100000, -- in cents
    created_at timestamptz not null default now(),
    updated_at timestamptz,
    alert_settings jsonb default '{"low_stock_threshold": 10, "critical_stock_threshold": 5, "email_notifications": true, "morning_briefing_enabled": true, "morning_briefing_time": "09:00", "enabled_alert_types": ["low_stock", "out_of_stock", "overstock"], "dismissal_hours": 24}'::jsonb
);
comment on table public.company_settings is 'Stores company-specific settings for business logic.';

-- Enum for supported integration platforms
create type public.integration_platform as enum ('shopify', 'woocommerce', 'amazon_fba');

-- Stores information about connected third-party integrations.
create table public.integrations (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    platform integration_platform not null,
    shop_domain text,
    shop_name text,
    is_active boolean default false,
    last_sync_at timestamptz,
    sync_status text,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);
create unique index on public.integrations(company_id, platform);
comment on table public.integrations is 'Stores information about connected third-party integrations.';


-- Stores product information.
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
    fts_document tsvector,
    deleted_at timestamptz
);
create unique index on public.products(company_id, external_product_id);
comment on table public.products is 'Stores product information.';


-- Stores information about suppliers or vendors.
create table public.suppliers (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    name text not null,
    email text,
    phone text,
    default_lead_time_days int,
    notes text,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);
comment on table public.suppliers is 'Stores information about suppliers or vendors.';

-- Stores product variants (SKUs).
create table public.product_variants (
    id uuid primary key default gen_random_uuid(),
    product_id uuid not null references public.products(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    supplier_id uuid references public.suppliers(id) on delete set null,
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
    reorder_point int,
    reorder_quantity int,
    location text,
    external_variant_id text,
    created_at timestamptz default now() not null,
    updated_at timestamptz,
    deleted_at timestamptz,
    version int not null default 1,
    reserved_quantity int not null default 0,
    in_transit_quantity int not null default 0
);
create unique index on public.product_variants(company_id, sku);
create unique index on public.product_variants(company_id, external_variant_id);
comment on table public.product_variants is 'Stores product variants (SKUs).';


-- Stores customer information.
create table public.customers (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    name text,
    email text,
    phone text,
    external_customer_id text,
    created_at timestamptz default now(),
    updated_at timestamptz,
    deleted_at timestamptz
);
create unique index on public.customers(company_id, external_customer_id);
comment on table public.customers is 'Stores customer information.';


-- Stores sales order information.
create table public.orders (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    order_number text not null,
    external_order_id text,
    customer_id uuid references public.customers(id) on delete set null,
    financial_status text default 'pending',
    fulfillment_status text default 'unfulfilled',
    currency text default 'USD',
    subtotal int not null default 0,
    total_tax int default 0,
    total_shipping int default 0,
    total_discounts int default 0,
    total_amount int not null,
    source_platform text,
    created_at timestamptz default now() not null,
    updated_at timestamptz,
    cancelled_at timestamptz
);
create unique index on public.orders(company_id, external_order_id);
comment on table public.orders is 'Stores sales order information.';


-- Stores line items for each sales order.
create table public.order_line_items (
    id uuid primary key default gen_random_uuid(),
    order_id uuid not null references public.orders(id) on delete cascade,
    variant_id uuid references public.product_variants(id) on delete set null,
    company_id uuid not null references public.companies(id) on delete cascade,
    product_name text,
    variant_title text,
    sku text,
    quantity int not null,
    price int not null,
    total_discount int default 0,
    tax_amount int default 0,
    cost_at_time int,
    external_line_item_id text
);
comment on table public.order_line_items is 'Stores line items for each sales order.';


-- Stores purchase order information.
create table public.purchase_orders (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    supplier_id uuid references public.suppliers(id) on delete set null,
    status text not null default 'Draft',
    po_number text not null,
    total_cost int not null,
    expected_arrival_date date,
    idempotency_key uuid,
    notes text,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);
create unique index on public.purchase_orders(company_id, po_number);
comment on table public.purchase_orders is 'Stores purchase order information.';


-- Stores line items for each purchase order.
create table public.purchase_order_line_items (
    id uuid primary key default uuid_generate_v4(),
    purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    quantity int not null,
    cost int not null -- in cents
);
comment on table public.purchase_order_line_items is 'Stores line items for each purchase order.';


-- Table to store AI conversation history
create table public.conversations (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid not null references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    title text not null,
    created_at timestamptz default now() not null,
    last_accessed_at timestamptz default now() not null,
    is_starred boolean default false
);
comment on table public.conversations is 'Stores AI conversation history.';


-- Enum for message roles
create type public.message_role as enum ('user', 'assistant', 'tool');

-- Table to store individual messages in a conversation
create table public.messages (
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
    created_at timestamptz default now() not null
);
comment on table public.messages is 'Stores individual messages in a conversation.';


-- Records all inventory changes for audit purposes.
create table public.inventory_ledger (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    change_type text not null, -- 'sale', 'purchase_order', 'reconciliation', 'manual_adjustment'
    quantity_change int not null,
    new_quantity int not null,
    related_id uuid, -- e.g., order_id, purchase_order_id
    notes text,
    created_at timestamptz not null default now()
);
comment on table public.inventory_ledger is 'Records all inventory changes for audit purposes.';


-- Stores channel-specific fees for more accurate profit calculation.
create table public.channel_fees (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    channel_name text not null,
    percentage_fee numeric,
    fixed_fee numeric,
    created_at timestamptz default now(),
    updated_at timestamptz
);
create unique index on public.channel_fees(company_id, channel_name);
comment on table public.channel_fees is 'Stores channel-specific fees for more accurate profit calculation.';


-- Audit log for significant user actions.
create table public.audit_log (
    id bigserial primary key,
    company_id uuid references public.companies(id) on delete cascade,
    user_id uuid references auth.users(id) on delete set null,
    action text not null,
    details jsonb,
    created_at timestamptz default now()
);
comment on table public.audit_log is 'Audit log for significant user actions.';


-- Table for storing user feedback on AI responses
create type public.feedback_type as enum ('helpful', 'unhelpful');
create table public.feedback (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    subject_id text not null,
    subject_type text not null, -- 'message', 'alert', etc.
    feedback feedback_type not null,
    created_at timestamptz default now()
);
comment on table public.feedback is 'Stores user feedback on AI responses.';


-- Table for managing background data export jobs
create table public.export_jobs (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    requested_by_user_id uuid not null references auth.users(id) on delete cascade,
    status text not null default 'pending', -- pending, processing, completed, failed
    download_url text,
    expires_at timestamptz,
    created_at timestamptz not null default now(),
    completed_at timestamptz,
    error_message text
);
comment on table public.export_jobs is 'Manages background data export jobs.';


-- Table for tracking data import jobs
create table public.imports (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    created_by uuid not null references auth.users(id) on delete cascade,
    import_type text not null,
    file_name text not null,
    total_rows int,
    processed_rows int,
    failed_rows int,
    status text not null default 'pending', -- pending, processing, completed, completed_with_errors, failed
    errors jsonb,
    summary jsonb,
    created_at timestamptz default now(),
    completed_at timestamptz
);
comment on table public.imports is 'Tracks data import jobs.';


-- Table to prevent webhook replay attacks
create table public.webhook_events (
    id uuid primary key default gen_random_uuid(),
    integration_id uuid not null references public.integrations(id) on delete cascade,
    webhook_id text not null,
    created_at timestamptz default now()
);
create unique index on public.webhook_events(integration_id, webhook_id);
comment on table public.webhook_events is 'Stores processed webhook IDs to prevent replay attacks.';

--
-- RLS (Row Level Security)
--
alter table public.companies enable row level security;
alter table public.company_users enable row level security;
alter table public.company_settings enable row level security;
alter table public.integrations enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.suppliers enable row level security;
alter table public.customers enable row level security;
alter table public.orders enable row level security;
alter table public.order_line_items enable row level security;
alter table public.purchase_orders enable row level security;
alter table public.purchase_order_line_items enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.inventory_ledger enable row level security;
alter table public.channel_fees enable row level security;
alter table public.audit_log enable row level security;
alter table public.feedback enable row level security;
alter table public.export_jobs enable row level security;
alter table public.imports enable row level security;

-- Helper function to get company_id from JWT
drop function if exists auth.company_id();
create function auth.company_id()
returns uuid
language plpgsql
stable
as $$
declare
    company_id_val uuid;
begin
    -- Try to get company_id from app_metadata first
    company_id_val := (auth.jwt() -> 'app_metadata' ->> 'company_id')::uuid;
    
    -- Fallback to user_metadata if not in app_metadata
    if company_id_val is null then
        company_id_val := (auth.jwt() -> 'user_metadata' ->> 'company_id')::uuid;
    end if;

    -- As a final fallback, query the company_users table
    if company_id_val is null then
      select company_id into company_id_val from public.company_users where user_id = auth.uid();
    end if;
    
    return company_id_val;
end;
$$;


-- Policies
create policy "Users can only access their own company data" on public.companies for select using (id = auth.company_id());
create policy "Users can only access their own company users" on public.company_users for select using (company_id = auth.company_id());
create policy "Users can only access their own company settings" on public.company_settings for all using (company_id = auth.company_id());
create policy "Users can only access their own company integrations" on public.integrations for all using (company_id = auth.company_id());
create policy "Users can only access their own company products" on public.products for all using (company_id = auth.company_id());
create policy "Users can only access their own company variants" on public.product_variants for all using (company_id = auth.company_id());
create policy "Users can only access their own company suppliers" on public.suppliers for all using (company_id = auth.company_id());
create policy "Users can only access their own company customers" on public.customers for all using (company_id = auth.company_id());
create policy "Users can only access their own company orders" on public.orders for all using (company_id = auth.company_id());
create policy "Users can only access their own company order line items" on public.order_line_items for all using (company_id = auth.company_id());
create policy "Users can only access their own company POs" on public.purchase_orders for all using (company_id = auth.company_id());
create policy "Users can only access their own company PO line items" on public.purchase_order_line_items for all using (company_id = auth.company_id());
create policy "Users can only access their own conversations" on public.conversations for all using (user_id = auth.uid());
create policy "Users can only access messages in their conversations" on public.messages for all using (company_id = auth.company_id());
create policy "Users can only access their own inventory ledger" on public.inventory_ledger for all using (company_id = auth.company_id());
create policy "Users can only access their own channel fees" on public.channel_fees for all using (company_id = auth.company_id());
create policy "Users can only access their own audit log" on public.audit_log for all using (company_id = auth.company_id());
create policy "Users can only submit feedback for their company" on public.feedback for all using (company_id = auth.company_id());
create policy "Users can only access their own export jobs" on public.export_jobs for all using (company_id = auth.company_id());
create policy "Users can only access their own import jobs" on public.imports for all using (company_id = auth.company_id());


-- Create the auth.company_id() function that RLS policies need
CREATE OR REPLACE FUNCTION auth.company_id()
RETURNS UUID AS $$
DECLARE
    company_id_val UUID;
BEGIN
    -- Get company_id from JWT token
    -- First try app_metadata
    company_id_val := NULLIF(current_setting('request.jwt.claims', true)::JSONB -> 'app_metadata' ->> 'company_id', '')::UUID;
    
    -- If not found, try user_metadata  
    IF company_id_val IS NULL THEN
        company_id_val := NULLIF(current_setting('request.jwt.claims', true)::JSONB -> 'user_metadata' ->> 'company_id', '')::UUID;
    END IF;
    
    -- If still not found, get from users table
    IF company_id_val IS NULL THEN
        SELECT (raw_app_meta_data ->> 'company_id')::UUID
        INTO company_id_val
        FROM auth.users
        WHERE id = auth.uid();
    END IF;
    
    RETURN company_id_val;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- Fix RLS policies for all tables with company_id
-- Drop existing policies first
DROP POLICY IF EXISTS "Users can only access their own company data" ON orders;
DROP POLICY IF EXISTS "Users can only access their own company data" ON products;
DROP POLICY IF EXISTS "Users can only access their own company data" ON customers;
DROP POLICY IF EXISTS "Users can only access their own company data" ON product_variants;
DROP POLICY IF EXISTS "Users can only access their own company data" ON order_line_items;

-- Create new policies
CREATE POLICY "Users can access their company data" ON orders
    FOR ALL 
    USING (company_id = auth.company_id());

CREATE POLICY "Users can access their company data" ON products
    FOR ALL 
    USING (company_id = auth.company_id());

CREATE POLICY "Users can access their company data" ON customers
    FOR ALL 
    USING (company_id = auth.company_id());

CREATE POLICY "Users can access their company data" ON product_variants
    FOR ALL 
    USING (company_id = auth.company_id());

CREATE POLICY "Users can access their company data" ON order_line_items
    FOR ALL 
    USING (company_id = auth.company_id());
    
--
-- Functions
--

-- Drop function if it exists to handle return type changes
DROP FUNCTION IF EXISTS public.get_dashboard_metrics(uuid, integer);

-- Comprehensive dashboard metrics function
CREATE OR REPLACE FUNCTION public.get_dashboard_metrics(
  p_company_id uuid,
  p_days int DEFAULT 30
)
RETURNS TABLE (
  total_orders bigint,
  total_revenue bigint,
  total_customers bigint,
  inventory_count bigint,
  sales_series jsonb,
  top_products jsonb,
  inventory_summary jsonb,
  revenue_change double precision,
  orders_change double precision,
  customers_change double precision,
  dead_stock_value bigint
)
LANGUAGE sql
STABLE
AS $$
WITH time_window AS (
  SELECT
    now() - make_interval(days => p_days)            AS start_at,
    now() - make_interval(days => p_days * 2)        AS prev_start_at,
    now() - make_interval(days => p_days)            AS prev_end_at
),
filtered_orders AS (
  SELECT o.*
  FROM public.orders o
  JOIN time_window w ON true
  WHERE o.company_id = p_company_id
    AND o.created_at >= w.start_at
    AND o.cancelled_at IS NULL
),
prev_filtered_orders AS (
  SELECT o.*
  FROM public.orders o
  JOIN time_window w ON true
  WHERE o.company_id = p_company_id
    AND o.created_at BETWEEN w.prev_start_at AND w.prev_end_at
    AND o.cancelled_at IS NULL
),
day_series AS (
  SELECT date_trunc('day', o.created_at) AS day,
         SUM(o.total_amount)::bigint     AS revenue,
         COUNT(*)::int                   AS orders
  FROM filtered_orders o
  GROUP BY 1
  ORDER BY 1
),
top_products AS (
  SELECT
    p.id                                  AS product_id,
    p.title                               AS product_name,
    p.image_url,
    SUM(li.quantity)::int                 AS quantity_sold,
    SUM((li.price::bigint) * (li.quantity::bigint))   AS total_revenue
  FROM public.order_line_items li
  JOIN public.orders o   ON o.id = li.order_id
  LEFT JOIN public.products p ON p.id = li.product_id
  WHERE o.company_id = p_company_id
    AND o.cancelled_at IS NULL
    AND o.created_at >= (SELECT start_at FROM time_window)
  GROUP BY 1,2,3
  ORDER BY total_revenue DESC
  LIMIT 5
),
inventory_values AS (
  SELECT
    SUM((v.inventory_quantity::bigint) * (v.cost::bigint)) AS total_value,
    SUM(CASE WHEN v.reorder_point IS NULL OR v.inventory_quantity > v.reorder_point
             THEN (v.inventory_quantity::bigint) * (v.cost::bigint) ELSE 0 END) AS in_stock_value,
    SUM(CASE WHEN v.reorder_point IS NOT NULL
               AND v.inventory_quantity <= v.reorder_point
               AND v.inventory_quantity > 0
             THEN (v.inventory_quantity::bigint) * (v.cost::bigint) ELSE 0 END) AS low_stock_value
  FROM public.product_variants v
  WHERE v.company_id = p_company_id
    AND v.cost IS NOT NULL AND v.deleted_at IS NULL
),
variant_last_sale AS (
  SELECT li.variant_id, MAX(o.created_at) AS last_sale_at
  FROM public.order_line_items li
  JOIN public.orders o ON o.id = li.order_id
  WHERE o.company_id = p_company_id
    AND o.cancelled_at IS NULL
  GROUP BY li.variant_id
),
dead_stock AS (
  SELECT
    SUM((v.inventory_quantity::bigint) * (v.cost::bigint)) AS value
  FROM public.product_variants v
  LEFT JOIN variant_last_sale ls ON ls.variant_id = v.id
  LEFT JOIN public.company_settings cs ON cs.company_id = v.company_id
  WHERE v.company_id = p_company_id
    AND v.cost IS NOT NULL
    AND v.deleted_at IS NULL
    AND (
      ls.last_sale_at IS NULL
      OR ls.last_sale_at < (now() - make_interval(days => COALESCE(cs.dead_stock_days, 90)))
    )
),
current_period AS (
  SELECT
    COALESCE(COUNT(*), 0)::bigint                      AS orders,
    COALESCE(SUM(total_amount), 0)::bigint             AS revenue,
    COALESCE(COUNT(DISTINCT customer_id), 0)::bigint   AS customers
  FROM filtered_orders
),
previous_period AS (
  SELECT
    COALESCE(COUNT(*), 0)::bigint                      AS orders,
    COALESCE(SUM(total_amount), 0)::bigint             AS revenue,
    COALESCE(COUNT(DISTINCT customer_id), 0)::bigint   AS customers
  FROM prev_filtered_orders
)
SELECT
  (SELECT orders    FROM current_period) AS total_orders,
  (SELECT revenue   FROM current_period) AS total_revenue,
  (SELECT customers FROM current_period) AS total_customers,

  COALESCE((
    SELECT SUM(pv.inventory_quantity)
    FROM public.product_variants pv
    WHERE pv.company_id = p_company_id AND pv.deleted_at IS NULL
  ), 0)::bigint AS inventory_count,

  COALESCE((
    SELECT jsonb_agg(
      jsonb_build_object(
        'date', to_char(day, 'YYYY-MM-DD'),
        'revenue', revenue,
        'orders', orders
      )
      ORDER BY day
    )
    FROM day_series
  ), '[]'::jsonb) AS sales_series,

  COALESCE((SELECT jsonb_agg(to_jsonb(tp)) FROM top_products tp), '[]'::jsonb) AS top_products,

  jsonb_build_object(
    'total_value',     COALESCE((SELECT total_value     FROM inventory_values), 0),
    'in_stock_value',  COALESCE((SELECT in_stock_value  FROM inventory_values), 0),
    'low_stock_value', COALESCE((SELECT low_stock_value FROM inventory_values), 0),
    'dead_stock_value',COALESCE((SELECT value           FROM dead_stock), 0)
  ) AS inventory_summary,

  CASE WHEN (SELECT revenue FROM previous_period) = 0
       THEN 0.0
       ELSE (((SELECT revenue FROM current_period)::float
             - (SELECT revenue FROM previous_period)::float)
             / NULLIF((SELECT revenue FROM previous_period)::float, 0)) * 100
  END AS revenue_change,
  CASE WHEN (SELECT orders FROM previous_period) = 0
       THEN 0.0
       ELSE (((SELECT orders FROM current_period)::float
             - (SELECT orders FROM previous_period)::float)
             / NULLIF((SELECT orders FROM previous_period)::float, 0)) * 100
  END AS orders_change,
  CASE WHEN (SELECT customers FROM previous_period) = 0
       THEN 0.0
       ELSE (((SELECT customers FROM current_period)::float
             - (SELECT customers FROM previous_period)::float)
             / NULLIF((SELECT customers FROM previous_period)::float, 0)) * 100
  END AS customers_change,

  COALESCE((SELECT value FROM dead_stock), 0)::bigint AS dead_stock_value;
$$;

--
-- Indexes for Performance
--
create index if not exists idx_orders_company_created
  on orders(company_id, created_at);

create index if not exists idx_orders_company_cancelled
  on orders(company_id) where cancelled_at is null;

create index if not exists idx_olis_order
  on order_line_items(order_id);

create index if not exists idx_olis_company_variant
  on order_line_items(company_id, variant_id);

create index if not exists idx_products_company
  on products(company_id);

create index if not exists idx_variants_company
  on product_variants(company_id);

create index if not exists idx_customers_company
  on customers(company_id);

--
-- Materialized Views for Analytics
--
-- Drop existing materialized views if they exist
drop materialized view if exists public.sales_analytics_mat cascade;
drop materialized view if exists public.inventory_analytics_mat cascade;
drop materialized view if exists public.customer_analytics_mat cascade;
drop materialized view if exists public.product_variants_with_details_mat cascade;
drop materialized view if exists public.purchase_orders_view_mat cascade;
drop materialized view if exists public.audit_log_view_mat cascade;
drop materialized view if exists public.feedback_view_mat cascade;


-- Create a materialized view for product variants with details
create materialized view public.product_variants_with_details_mat as
select 
  pv.*,
  p.title as product_title,
  p.status as product_status,
  p.image_url,
  p.product_type
from public.product_variants pv
join public.products p on pv.product_id = p.id;
create unique index on public.product_variants_with_details_mat(id);

-- Create a materialized view for purchase orders with supplier name
create materialized view public.purchase_orders_view_mat as
select
  po.*,
  s.name as supplier_name,
  jsonb_agg(jsonb_build_object(
    'id', li.id,
    'sku', v.sku,
    'product_name', p.title,
    'quantity', li.quantity,
    'cost', li.cost
  )) as line_items
from public.purchase_orders po
left join public.suppliers s on po.supplier_id = s.id
left join public.purchase_order_line_items li on li.purchase_order_id = po.id
left join public.product_variants v on v.id = li.variant_id
left join public.products p on p.id = v.product_id
group by po.id, s.name;
create unique index on public.purchase_orders_view_mat(id);


-- Create a materialized view for the audit log with user emails
create materialized view public.audit_log_view_mat as
select
  al.id,
  al.company_id,
  al.created_at,
  u.email as user_email,
  al.action,
  al.details
from public.audit_log al
left join auth.users u on al.user_id = u.id;
create unique index on public.audit_log_view_mat(id);


-- Create a materialized view for feedback with related messages and user info
create materialized view public.feedback_view_mat as
select
  f.id,
  f.created_at,
  f.feedback,
  u.email as user_email,
  m.content as assistant_message_content,
  (select content from public.messages where id = m.id and role = 'user' limit 1) as user_message_content,
  f.company_id
from public.feedback f
join auth.users u on f.user_id = u.id
join public.messages m on f.subject_id = m.id and m.role = 'assistant';
create unique index on public.feedback_view_mat(id);

-- Refresh function for a single materialized view
create or replace function public.refresh_mat_view(view_name text)
returns void
language plpgsql
as $$
begin
  execute 'refresh materialized view concurrently ' || view_name;
end;
$$;

-- Function to refresh all materialized views for a company
create or replace function public.refresh_all_matviews(p_company_id uuid)
returns void
language plpgsql
as $$
begin
  -- Note: These views are not company-specific, so we refresh them all.
  -- In a larger multi-tenant system, these might be partitioned by company_id.
  perform public.refresh_mat_view('product_variants_with_details_mat');
  perform public.refresh_mat_view('purchase_orders_view_mat');
  perform public.refresh_mat_view('audit_log_view_mat');
  perform public.refresh_mat_view('feedback_view_mat');
end;
$$;
