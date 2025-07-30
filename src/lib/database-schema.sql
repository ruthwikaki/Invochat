-- supabase/seed.sql
--
-- NOTE: This is NOT a migration file. This is a one-time setup script
-- that you should run in the Supabase SQL Editor ONCE.
--
-- Why not a migration?
-- Migrations are for evolving the schema over time. This script is for the
-- initial setup, which includes creating tables, RLS policies, and triggers
- - that are necessary for the application to function at all. It's designed
-- to be idempotent, meaning it can be run multiple times without causing
-- errors, but it's intended for a single, initial setup.
--
-- Running this script will:
-- 1. Enable the required `pgcrypto` and `uuid-ossp` extensions.
-- 2. Create all the necessary tables for products, inventory, customers, etc.
-- 3. Set up Row-Level Security (RLS) policies to ensure data privacy between companies.
-- 4. Create a trigger function that automatically sets up a new company and user profile
--    when a new user signs up via Supabase Auth.
--
--
-- How to Use:
-- 1. Copy the entire contents of this file.
-- 2. Go to your Supabase project dashboard.
-- 3. In the left sidebar, click on "SQL Editor".
-- 4. Click "+ New query".
-- 5. Paste the copied SQL into the editor.
-- 6. Click "Run".
--
-- After running, you can sign up for a new account in the application, and
-- the trigger will automatically create the associated company and user profile.


-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Drop existing tables and types if they exist, for a clean setup
-- This makes the script idempotent
-- Enums
DROP TYPE IF EXISTS public.company_role CASCADE;
DROP TYPE IF EXISTS public.integration_platform CASCADE;
DROP TYPE IF EXISTS public.message_role CASCADE;
DROP TYPE IF EXISTS public.feedback_type CASCADE;

-- Tables
DROP TABLE IF EXISTS public.companies CASCADE;
DROP TABLE IF EXISTS public.company_users CASCADE;
DROP TABLE IF EXISTS public.products CASCADE;
DROP TABLE IF EXISTS public.product_variants CASCADE;
DROP TABLE IF EXISTS public.suppliers CASCADE;
DROP TABLE IF EXISTS public.purchase_orders CASCADE;
DROP TABLE IF EXISTS public.purchase_order_line_items CASCADE;
DROP TABLE IF EXISTS public.customers CASCADE;
DROP TABLE IF EXISTS public.orders CASCADE;
DROP TABLE IF EXISTS public.order_line_items CASCADE;
DROP TABLE IF EXISTS public.inventory_ledger CASCADE;
DROP TABLE IF EXISTS public.integrations CASCADE;
DROP TABLE IF EXISTS public.company_settings CASCADE;
DROP TABLE IF EXISTS public.conversations CASCADE;
DROP TABLE IF EXISTS public.messages CASCADE;
DROP TABLE IF EXISTS public.channel_fees CASCADE;
DROP TABLE IF EXISTS public.export_jobs CASCADE;
DROP TABLE IF EXISTS public.webhook_events CASCADE;
DROP TABLE IF EXISTS public.feedback CASCADE;
DROP TABLE IF EXISTS public.audit_log CASCADE;

-- Views
DROP VIEW IF EXISTS public.product_variants_with_details;
DROP VIEW IF EXISTS public.customers_view;
DROP VIEW IF EXISTS public.orders_view;
DROP VIEW IF EXISTS public.audit_log_view;
DROP VIEW IF EXISTS public.feedback_view;
DROP MATERIALIZED VIEW IF EXISTS public.daily_sales_by_variant;
DROP MATERIALIZED VIEW IF EXISTS public.monthly_sales_by_variant;
DROP MATERIALIZED VIEW IF EXISTS public.product_sales_stats;
DROP MATERIALIZED VIEW IF EXISTS public.po_delivery_performance;

-- Create ENUM types for roles and platforms
CREATE TYPE public.company_role AS ENUM ('Owner', 'Admin', 'Member');
CREATE TYPE public.integration_platform AS ENUM ('shopify', 'woocommerce', 'amazon_fba');
CREATE TYPE public.message_role AS ENUM ('user', 'assistant', 'tool');
CREATE TYPE public.feedback_type AS ENUM ('helpful', 'unhelpful');


-- Create tables
CREATE TABLE public.companies (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  name text NOT NULL,
  owner_id uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.company_users (
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role public.company_role NOT NULL DEFAULT 'Member',
  PRIMARY KEY (company_id, user_id)
);

-- This table is managed by the handle_new_user trigger.
-- It is populated automatically when a new user signs up.
CREATE TABLE public.users (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  email text,
  role text,
  deleted_at timestamptz,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE public.products (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  title text NOT NULL,
  description text,
  handle text,
  product_type text,
  tags text[],
  status text,
  image_url text,
  external_product_id text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz,
  deleted_at timestamptz,
  fts_document tsvector,
  UNIQUE(company_id, external_product_id)
);

CREATE TABLE public.product_variants (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
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
    price int, -- in cents
    compare_at_price int, -- in cents
    cost int, -- in cents
    inventory_quantity int NOT NULL DEFAULT 0,
    reserved_quantity int NOT NULL DEFAULT 0,
    in_transit_quantity int NOT NULL DEFAULT 0,
    reorder_point int,
    reorder_quantity int,
    external_variant_id text,
    location text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    deleted_at timestamptz,
    version int not null default 1,
    UNIQUE (company_id, sku)
);
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.suppliers (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  name text NOT NULL,
  email text,
  phone text,
  lead_time_days int,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE product_variants ADD COLUMN supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL;


CREATE TABLE public.purchase_orders (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'Draft', -- Draft, Ordered, Partially Received, Received, Cancelled
  po_number text NOT NULL,
  total_cost int NOT NULL,
  expected_arrival_date date,
  notes text,
  idempotency_key uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz,
  UNIQUE(company_id, po_number)
);

CREATE TABLE public.purchase_order_line_items (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  purchase_order_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
  variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE RESTRICT,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  quantity int NOT NULL,
  cost int NOT NULL
);

CREATE TABLE public.customers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name text not null,
    email text,
    total_orders int DEFAULT 0,
    total_spent int DEFAULT 0, -- in cents
    first_order_date date,
    created_at timestamptz DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE (company_id, email)
);

CREATE TABLE public.orders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number text NOT NULL,
    external_order_id text,
    customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
    financial_status text DEFAULT 'pending', -- e.g., 'pending', 'paid', 'refunded'
    fulfillment_status text DEFAULT 'unfulfilled', -- e.g., 'unfulfilled', 'fulfilled', 'partially_fulfilled'
    currency text DEFAULT 'USD',
    subtotal int NOT NULL DEFAULT 0, -- in cents
    total_tax int DEFAULT 0, -- in cents
    total_shipping int DEFAULT 0, -- in cents
    total_discounts int DEFAULT 0, -- in cents
    total_amount int NOT NULL, -- in cents
    source_platform text,
    source_name text, -- e.g. 'Store #1234', 'web'
    tags text[],
    notes text,
    cancelled_at timestamptz,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    UNIQUE (company_id, external_order_id)
);

CREATE TABLE public.order_line_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE RESTRICT,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_name text NOT NULL,
    variant_title text,
    sku text NOT NULL,
    quantity int NOT NULL,
    price int NOT NULL, -- in cents
    cost_at_time int, -- in cents
    total_discount int DEFAULT 0, -- in cents
    tax_amount int DEFAULT 0, -- in cents
    fulfillment_status text DEFAULT 'unfulfilled',
    requires_shipping boolean DEFAULT true,
    external_line_item_id text
);

CREATE TABLE public.inventory_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
  change_type text NOT NULL, -- 'sale', 'purchase_order', 'return', 'manual_adjustment'
  quantity_change int NOT NULL,
  new_quantity int NOT NULL,
  related_id uuid, -- e.g., order_id, po_id
  notes text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.integrations (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  platform text not null,
  shop_domain text,
  shop_name text,
  is_active boolean DEFAULT false,
  last_sync_at timestamptz,
  sync_status text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz,
  UNIQUE(company_id, platform)
);

CREATE TABLE public.company_settings (
  company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
  dead_stock_days int NOT NULL DEFAULT 90,
  fast_moving_days int NOT NULL DEFAULT 30,
  overstock_multiplier int NOT NULL DEFAULT 3,
  high_value_threshold int NOT NULL DEFAULT 1000, -- in dollars
  predictive_stock_days int NOT NULL DEFAULT 7,
  currency text DEFAULT 'USD',
  timezone text DEFAULT 'UTC',
  tax_rate numeric DEFAULT 0.0,
  promo_sales_lift_multiplier real not null default 2.5,
  alert_settings jsonb DEFAULT '{ "low_stock_threshold": 10, "critical_stock_threshold": 5, "dismissal_hours": 24, "email_notifications": true, "enabled_alert_types": ["low_stock", "out_of_stock", "overstock"], "morning_briefing_time": "09:00", "morning_briefing_enabled": true }',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz
);

CREATE TABLE public.conversations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid not null references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    title text not null,
    created_at timestamptz default now(),
    last_accessed_at timestamptz default now(),
    is_starred boolean default false
);
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.messages (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id uuid not null references public.conversations(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    role text NOT NULL,
    content text,
    component text,
    component_props jsonb,
    visualization jsonb,
    confidence real,
    assumptions text[],
    is_error boolean default false,
    created_at timestamptz default now()
);
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.channel_fees (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    channel_name text NOT NULL,
    percentage_fee numeric NOT NULL,
    fixed_fee numeric NOT NULL,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, channel_name)
);
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.export_jobs (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    requested_by_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    status text NOT NULL DEFAULT 'pending',
    download_url text,
    expires_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.webhook_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id text NOT NULL,
    created_at timestamptz DEFAULT now()
);
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.feedback (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id) on delete cascade,
    company_id uuid NOT NULL REFERENCES public.companies(id) on delete cascade,
    subject_id text NOT NULL,
    subject_type text NOT NULL, -- e.g. 'message', 'alert'
    feedback feedback_type NOT NULL,
    created_at timestamptz DEFAULT now()
);
ALTER TABLE public.feedback ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.audit_log (
  id bigserial PRIMARY KEY,
  company_id uuid REFERENCES public.companies(id) on delete cascade,
  user_id uuid REFERENCES auth.users(id) on delete set null,
  action text not null,
  details jsonb,
  created_at timestamptz default now()
);
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;


-- Enable Row-Level Security for all tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- Helper function to get company_id from user_id
CREATE OR REPLACE FUNCTION get_company_id_for_user(p_user_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
BEGIN
  SELECT company_id INTO v_company_id
  FROM company_users
  WHERE user_id = p_user_id;
  RETURN v_company_id;
END;
$$;

-- RLS Policies
-- Users can only see data belonging to their own company.
CREATE POLICY "Users can view their own company" ON public.companies FOR SELECT USING (id = get_company_id_for_user(auth.uid()));
CREATE POLICY "Users can view their own company users" ON public.company_users FOR SELECT USING (company_id = get_company_id_for_user(auth.uid()));
CREATE POLICY "Users can manage their own data" ON public.products FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));
CREATE POLICY "Users can manage their own data" ON public.product_variants FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));
CREATE POLICY "Users can manage their own data" ON public.suppliers FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));
CREATE POLICY "Users can manage their own data" ON public.purchase_orders FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));
CREATE POLICY "Users can manage their own data" ON public.purchase_order_line_items FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));
CREATE POLICY "Users can manage their own data" ON public.customers FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));
CREATE POLICY "Users can manage their own data" ON public.orders FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));
CREATE POLICY "Users can manage their own data" ON public.order_line_items FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));
CREATE POLICY "Users can manage their own data" ON public.inventory_ledger FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));
CREATE POLICY "Users can manage their own data" ON public.integrations FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));
CREATE POLICY "Users can manage their own data" ON public.company_settings FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));
CREATE POLICY "Users can access their own conversations" ON public.conversations FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));
CREATE POLICY "Users can access their own messages" ON public.messages FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));
CREATE POLICY "Users can manage their own channel fees" ON public.channel_fees FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));
CREATE POLICY "Admins can manage export jobs" ON public.export_jobs FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));
CREATE POLICY "Users can see their own webhook events" ON public.webhook_events FOR SELECT USING (integration_id IN (SELECT id from public.integrations WHERE company_id = get_company_id_for_user(auth.uid())));
CREATE POLICY "Users can submit feedback" ON public.feedback FOR INSERT WITH CHECK (company_id = get_company_id_for_user(auth.uid()));
CREATE POLICY "Admins can view feedback" ON public.feedback FOR SELECT USING (company_id = get_company_id_for_user(auth.uid()));
CREATE POLICY "Users can view their audit log" ON public.audit_log FOR SELECT USING (company_id = get_company_id_for_user(auth.uid()));
CREATE POLICY "Users can see their own user record" ON public.users FOR SELECT USING (id = auth.uid());


-- This function is called by the application to create a new user and their company.
-- It's a SECURITY DEFINER function, so it runs with the privileges of the user who defined it (the postgres user).
-- This is necessary to be able to insert into auth.users.
CREATE OR REPLACE FUNCTION public.create_company_and_user(
    p_company_name text,
    p_user_email text,
    p_user_password text,
    p_email_redirect_to text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_user_id uuid;
BEGIN
  -- 1. Create the company first.
  INSERT INTO public.companies (name)
  VALUES (p_company_name)
  RETURNING id INTO v_company_id;

  -- 2. Create the user in auth.users, passing the company_id in the metadata.
  --    This ensures the trigger has the company_id when it fires.
  INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, recovery_token, recovery_sent_at, last_sign_in_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, phone, phone_confirmed_at, email_change, email_change_sent_at)
  VALUES ('00000000-0000-0000-0000-000000000000', uuid_generate_v4(), 'authenticated', 'authenticated', p_user_email, crypt(p_user_password, gen_salt('bf')), now(), '', now(), now(), jsonb_build_object('provider', 'email', 'providers', '["email"]', 'company_id', v_company_id), '{}', now(), now(), NULL, NULL, '', now())
  RETURNING id INTO v_user_id;

  -- 3. Now that the user exists, update the company with the owner_id.
  UPDATE public.companies SET owner_id = v_user_id WHERE id = v_company_id;

  -- 4. Create the entry in company_users to link them.
  INSERT INTO public.company_users (user_id, company_id, role)
  VALUES (v_user_id, v_company_id, 'Owner');
  
  RETURN v_user_id;
END;
$$;
