
-- Drop existing types and functions if they exist, to ensure a clean setup.
-- This makes the script idempotent (runnable multiple times without errors).
drop type if exists user_role;
create type user_role as enum ('Owner', 'Admin', 'Member');

drop trigger if exists on_auth_user_created on auth.users;
drop function if exists public.handle_new_user;
drop function if exists public.get_user_id;
drop function if exists public.get_company_id;

-- Grant necessary permissions to the postgres role on the auth schema.
-- This is required for the handle_new_user function to work correctly.
grant usage on schema auth to postgres;
grant all on all tables in schema auth to postgres;
grant all on all sequences in schema auth to postgres;

--
-- Name: get_company_id(); Type: FUNCTION; Schema: public; Owner: -
--
create or replace function public.get_company_id()
returns uuid
language sql
security definer
set search_path to public
as $$
    select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid;
$$;

--
-- Name: get_user_id(); Type: FUNCTION; Schema: public; Owner: -
--
create or replace function public.get_user_id()
returns uuid
language sql
security definer
set search_path to public
as $$
    select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'sub', '')::uuid;
$$;

--
-- Name: handle_new_user(); Type: FUNCTION; Schema: public; Owner: -
--
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path to public
as $$
declare
  company_id uuid;
  user_email text;
  company_name text;
begin
  -- Extract company name from the user's metadata, defaulting if not present
  company_name := new.raw_app_meta_data ->> 'company_name';
  if company_name is null or company_name = '' then
    company_name := new.email || '''s Company';
  end if;

  -- Create a new company for the new user
  insert into public.companies (name)
  values (company_name)
  returning id into company_id;

  -- Insert a corresponding record into the public.users table
  insert into public.users (id, company_id, email, role)
  values (new.id, company_id, new.email, 'Owner');

  -- Update the user's app_metadata with the new company_id and role
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id, 'role', 'Owner')
  where id = new.id;

  return new;
end;
$$;

--
-- Name: on_auth_user_created(); Type: TRIGGER; Schema: auth; Owner: -
--
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Create Tables
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    name text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.users (
    id uuid NOT NULL PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email text,
    role user_role NOT NULL DEFAULT 'Member',
    deleted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer DEFAULT 90 NOT NULL,
    fast_moving_days integer DEFAULT 30 NOT NULL,
    overstock_multiplier integer DEFAULT 3 NOT NULL,
    high_value_threshold integer DEFAULT 100000 NOT NULL,
    predictive_stock_days integer DEFAULT 7 NOT NULL,
    currency text DEFAULT 'USD',
    timezone text DEFAULT 'UTC',
    tax_rate numeric DEFAULT 0,
    custom_rules jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.products (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    description text,
    handle text,
    product_type text,
    tags text[],
    status text,
    image_url text,
    external_product_id text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    fts_document tsvector,
    deleted_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.product_variants (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku text NOT NULL,
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
    inventory_quantity integer DEFAULT 0 NOT NULL,
    location text,
    external_variant_id text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    deleted_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL,
    status text DEFAULT 'Draft'::text NOT NULL,
    po_number text NOT NULL,
    total_cost integer NOT NULL,
    expected_arrival_date date,
    idempotency_key uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    purchase_order_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    quantity integer NOT NULL,
    cost integer NOT NULL
);

CREATE TABLE IF NOT EXISTS public.orders (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number text NOT NULL,
    external_order_id text,
    customer_id uuid,
    financial_status text DEFAULT 'pending',
    fulfillment_status text DEFAULT 'unfulfilled',
    currency text DEFAULT 'USD',
    subtotal integer DEFAULT 0 NOT NULL,
    total_tax integer DEFAULT 0,
    total_shipping integer DEFAULT 0,
    total_discounts integer DEFAULT 0,
    total_amount integer NOT NULL,
    source_platform text,
    created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id),
    product_name text NOT NULL,
    variant_title text,
    sku text NOT NULL,
    quantity integer NOT NULL,
    price integer NOT NULL,
    cost_at_time integer,
    total_discount integer DEFAULT 0,
    tax_amount integer DEFAULT 0,
    external_line_item_id text
);

CREATE TABLE IF NOT EXISTS public.customers (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name text NOT NULL,
    email text,
    total_orders integer DEFAULT 0,
    total_spent integer DEFAULT 0,
    first_order_date date,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.integrations (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform text NOT NULL,
    shop_domain text,
    shop_name text,
    is_active boolean DEFAULT false,
    last_sync_at timestamp with time zone,
    sync_status text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    is_starred boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now(),
    last_accessed_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.messages (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role text NOT NULL,
    content text,
    component text,
    component_props jsonb,
    visualization jsonb,
    confidence numeric,
    assumptions text[],
    is_error boolean default false,
    created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.webhook_events (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id text NOT NULL,
    processed_at timestamp with time zone DEFAULT now(),
    created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.audit_log (
    id bigserial PRIMARY KEY,
    company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    action text NOT NULL,
    details jsonb,
    created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.export_jobs (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    requested_by_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    status text NOT NULL DEFAULT 'pending',
    download_url text,
    expires_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.channel_fees (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    channel_name text NOT NULL,
    percentage_fee numeric NOT NULL,
    fixed_fee numeric NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone
);

-- ADD CONSTRAINTS and INDEXES
ALTER TABLE public.integrations DROP CONSTRAINT IF EXISTS integrations_company_id_platform_key;
ALTER TABLE public.integrations ADD CONSTRAINT integrations_company_id_platform_key UNIQUE (company_id, platform);

ALTER TABLE public.product_variants DROP CONSTRAINT IF EXISTS product_variants_company_id_sku_key;
ALTER TABLE public.product_variants ADD CONSTRAINT product_variants_company_id_sku_key UNIQUE (company_id, sku);

CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_variants_sku ON public.product_variants(sku);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_ledger_variant_id ON public.inventory_ledger(variant_id);

-- ROW LEVEL SECURITY (RLS)
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;


-- POLICIES
DROP POLICY IF EXISTS "Allow users to see their own company" ON public.companies;
CREATE POLICY "Allow users to see their own company" ON public.companies FOR SELECT USING (id = get_company_id());

DROP POLICY IF EXISTS "Allow users to see their own profile" ON public.users;
CREATE POLICY "Allow users to see their own profile" ON public.users FOR SELECT USING (id = get_user_id());

DROP POLICY IF EXISTS "Allow users to see their own team" ON public.users;
CREATE POLICY "Allow users to see their own team" ON public.users FOR SELECT USING (company_id = get_company_id());

DROP POLICY IF EXISTS "Allow owner to manage their team" ON public.users;
CREATE POLICY "Allow owner to manage their team" ON public.users FOR ALL USING (
    company_id = get_company_id() AND
    (SELECT role FROM public.users WHERE id = get_user_id()) = 'Owner'
);

DROP POLICY IF EXISTS "Allow all access to own company data" ON public.company_settings;
CREATE POLICY "Allow all access to own company data" ON public.company_settings FOR ALL USING (company_id = get_company_id());

DROP POLICY IF EXISTS "Allow all access to own company data" ON public.products;
CREATE POLICY "Allow all access to own company data" ON public.products FOR ALL USING (company_id = get_company_id());

DROP POLICY IF EXISTS "Allow all access to own company data" ON public.product_variants;
CREATE POLICY "Allow all access to own company data" ON public.product_variants FOR ALL USING (company_id = get_company_id());

DROP POLICY IF EXISTS "Allow all access to own company data" ON public.suppliers;
CREATE POLICY "Allow all access to own company data" ON public.suppliers FOR ALL USING (company_id = get_company_id());

DROP POLICY IF EXISTS "Allow all access to own company data" ON public.purchase_orders;
CREATE POLICY "Allow all access to own company data" ON public.purchase_orders FOR ALL USING (company_id = get_company_id());

DROP POLICY IF EXISTS "Allow all access to own company data" ON public.purchase_order_line_items;
CREATE POLICY "Allow all access to own company data" ON public.purchase_order_line_items FOR ALL USING (company_id = get_company_id());

DROP POLICY IF EXISTS "Allow all access to own company data" ON public.orders;
CREATE POLICY "Allow all access to own company data" ON public.orders FOR ALL USING (company_id = get_company_id());

DROP POLICY IF EXISTS "Allow all access to own company data" ON public.order_line_items;
CREATE POLICY "Allow all access to own company data" ON public.order_line_items FOR ALL USING (company_id = get_company_id());

DROP POLICY IF EXISTS "Allow all access to own company data" ON public.customers;
CREATE POLICY "Allow all access to own company data" ON public.customers FOR ALL USING (company_id = get_company_id());

DROP POLICY IF EXISTS "Allow all access to own company data" ON public.inventory_ledger;
CREATE POLICY "Allow all access to own company data" ON public.inventory_ledger FOR ALL USING (company_id = get_company_id());

DROP POLICY IF EXISTS "Allow all access to own company data" ON public.integrations;
CREATE POLICY "Allow all access to own company data" ON public.integrations FOR ALL USING (company_id = get_company_id());

DROP POLICY IF EXISTS "Allow all access to own conversations" ON public.conversations;
CREATE POLICY "Allow all access to own conversations" ON public.conversations FOR ALL USING (user_id = get_user_id() AND company_id = get_company_id());

DROP POLICY IF EXISTS "Allow all access to own messages" ON public.messages;
CREATE POLICY "Allow all access to own messages" ON public.messages FOR ALL USING (company_id = get_company_id());

DROP POLICY IF EXISTS "Allow all access to own company data" ON public.webhook_events;
CREATE POLICY "Allow all access to own company data" ON public.webhook_events FOR ALL USING (
    (SELECT company_id from public.integrations WHERE id = integration_id) = get_company_id()
);

DROP POLICY IF EXISTS "Allow all access to own company data" ON public.audit_log;
CREATE POLICY "Allow all access to own company data" ON public.audit_log FOR ALL USING (company_id = get_company_id());

DROP POLICY IF EXISTS "Allow all access to own company data" ON public.export_jobs;
CREATE POLICY "Allow all access to own company data" ON public.export_jobs FOR ALL USING (company_id = get_company_id());

DROP POLICY IF EXISTS "Allow all access to own company data" ON public.channel_fees;
CREATE POLICY "Allow all access to own company data" ON public.channel_fees FOR ALL USING (company_id = get_company_id());


-- Create VIEWS

-- Customer View
DROP VIEW IF EXISTS public.customers_view;
CREATE OR REPLACE VIEW public.customers_view AS
SELECT 
    c.id,
    c.company_id,
    c.customer_name,
    c.email,
    c.first_order_date,
    c.created_at,
    COALESCE(o.total_orders, 0) as total_orders,
    COALESCE(o.total_spent, 0) as total_spent
FROM 
    public.customers c
LEFT JOIN (
    SELECT 
        customer_id,
        COUNT(id) as total_orders,
        SUM(total_amount) as total_spent
    FROM 
        public.orders
    GROUP BY 
        customer_id
) o ON c.id = o.customer_id;

-- Product Variants with Details View
DROP VIEW IF EXISTS public.product_variants_with_details;
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT 
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
    pv.location,
    pv.external_variant_id,
    pv.created_at,
    pv.updated_at,
    pv.deleted_at,
    p.title as product_title,
    p.status as product_status,
    p.image_url
FROM 
    public.product_variants pv
JOIN 
    public.products p ON pv.product_id = p.id;


-- Orders View
DROP VIEW IF EXISTS public.orders_view;
CREATE OR REPLACE VIEW public.orders_view AS
SELECT 
    o.id,
    o.company_id,
    o.order_number,
    o.created_at,
    c.email AS customer_email,
    o.financial_status,
    o.fulfillment_status,
    o.total_amount,
    o.source_platform
FROM 
    public.orders o
LEFT JOIN 
    public.customers c ON o.customer_id = c.id;

-- Seed initial data for a better demo experience
INSERT INTO public.companies (id, name, created_at)
VALUES ('a1b2c3d4-e5f6-7890-1234-567890abcdef', 'ARVO Demo Company', now())
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.company_settings (company_id, dead_stock_days, fast_moving_days, overstock_multiplier, high_value_threshold, currency, timezone, created_at, updated_at)
VALUES ('a1b2c3d4-e5f6-7890-1234-567890abcdef', 90, 30, 3, 1000, 'USD', 'UTC', now(), now())
ON CONFLICT (company_id) DO NOTHING;

INSERT INTO public.integrations (company_id, platform, shop_name, is_active, sync_status, last_sync_at, created_at)
VALUES ('a1b2c3d4-e5f6-7890-1234-567890abcdef', 'amazon_fba', 'Amazon FBA (Demo)', true, 'idle', now(), now())
ON CONFLICT (company_id, platform) DO NOTHING;
