
-- =================================================================
-- Reset Script (Optional)
-- Run this section to TRUNCATE all data and start fresh.
-- =================================================================
DO $$
DECLARE
  r RECORD;
BEGIN
  -- Disable triggers
  SET session_replication_role = 'replica';

  -- Truncate all tables in the public schema
  FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public') LOOP
    EXECUTE 'TRUNCATE TABLE public.' || quote_ident(r.tablename) || ' RESTART IDENTITY CASCADE';
  END LOOP;

  -- Delete non-admin users from auth.users
  DELETE FROM auth.users WHERE email NOT LIKE '%@google.com' AND email NOT LIKE '%@aiventory.com';

  -- Re-enable triggers
  SET session_replication_role = 'origin';

  RAISE NOTICE 'All application data has been truncated and non-admin users have been deleted.';
END $$;


-- =================================================================
-- Initial DB Setup
-- This script should be run in the Supabase SQL Editor ONCE.
-- =================================================================

-- 1. Create company_role enum
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'company_role') THEN
        CREATE TYPE public.company_role AS ENUM ('Owner', 'Admin', 'Member');
    END IF;
END$$;


-- 2. Create companies table
CREATE TABLE IF NOT EXISTS public.companies (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  owner_id uuid REFERENCES auth.users(id) ON DELETE SET NULL
);

-- 3. Create company_users join table
CREATE TABLE IF NOT EXISTS public.company_users (
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role public.company_role NOT NULL DEFAULT 'Member',
  PRIMARY KEY (company_id, user_id)
);

-- 4. Create company_settings table
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    fast_moving_days integer NOT NULL DEFAULT 30,
    predictive_stock_days integer NOT NULL DEFAULT 7,
    currency text DEFAULT 'USD',
    timezone text DEFAULT 'UTC',
    tax_rate numeric DEFAULT 0.0,
    overstock_multiplier integer NOT NULL DEFAULT 3,
    high_value_threshold integer NOT NULL DEFAULT 1000, -- Stored in cents
    alert_settings jsonb DEFAULT '{
        "dismissal_hours": 24,
        "email_notifications": true,
        "enabled_alert_types": ["low_stock", "out_of_stock", "overstock"],
        "low_stock_threshold": 10,
        "morning_briefing_time": "09:00",
        "critical_stock_threshold": 5,
        "morning_briefing_enabled": true
    }',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);


-- 5. Create handle_new_user function and trigger
-- This function is called when a new user signs up.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
  new_company_id uuid;
BEGIN
  -- Generate new company ID
  new_company_id := gen_random_uuid();
  
  -- Create company
  INSERT INTO public.companies (id, name, owner_id, created_at)
  VALUES (
    new_company_id,
    COALESCE(NEW.raw_user_meta_data->>'company_name', NEW.email || '''s Company'),
    NEW.id,
    now()
  );

  -- Create user record
  INSERT INTO public.company_users (user_id, company_id, role)
  VALUES (
    NEW.id,
    new_company_id,
    'Owner'
  );

  -- Create company settings with defaults
  INSERT INTO public.company_settings (
    company_id,
    dead_stock_days,
    fast_moving_days,
    predictive_stock_days,
    currency,
    timezone
  )
  VALUES (
    new_company_id,
    90,  -- dead_stock_days
    30,  -- fast_moving_days
    7,   -- predictive_stock_days
    'USD',
    'UTC'
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Log the error but don't fail the user creation
  RAISE LOG 'Error in handle_new_user for user %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. Create the trigger on the auth.users table
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- 7. Add company_id to user's app_metadata
-- This function is called by the trigger on the company_users table.
CREATE OR REPLACE FUNCTION public.add_company_id_to_user_metadata()
RETURNS trigger AS $$
BEGIN
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', NEW.company_id)
  WHERE id = NEW.user_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 8. Create trigger to update user metadata when they are added to a company
DROP TRIGGER IF EXISTS on_company_user_created ON public.company_users;
CREATE TRIGGER on_company_user_created
  AFTER INSERT ON public.company_users
  FOR EACH ROW EXECUTE FUNCTION public.add_company_id_to_user_metadata();


-- 9. RLS (Row Level Security) Policies
-- These policies ensure that users can only access data for their own company.

-- Enable RLS for all relevant tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.feedback ENABLE ROW LEVEL SECURITY;

-- Function to get the current user's company_id
CREATE OR REPLACE FUNCTION auth.get_current_company_id()
RETURNS uuid AS $$
DECLARE
  company_id uuid;
BEGIN
  SELECT raw_app_meta_data->>'company_id' INTO company_id
  FROM auth.users
  WHERE id = auth.uid();
  RETURN company_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- POLICY: Users can only see their own company's data
DROP POLICY IF EXISTS "allow_users_to_see_own_company_data" ON public.companies;
CREATE POLICY "allow_users_to_see_own_company_data" ON public.companies
  FOR SELECT USING (id = auth.get_current_company_id());

DROP POLICY IF EXISTS "allow_users_to_see_own_company_users" ON public.company_users;
CREATE POLICY "allow_users_to_see_own_company_users" ON public.company_users
  FOR ALL USING (company_id = auth.get_current_company_id());

-- Apply a generic policy to all other tables
DO $$
DECLARE
  tbl_name text;
BEGIN
  FOR tbl_name IN 
    SELECT table_name FROM information_schema.tables 
    WHERE table_schema = 'public' 
    AND table_name NOT IN ('companies', 'company_users')
  LOOP
    EXECUTE format(
      'DROP POLICY IF EXISTS "allow_all_for_company_members" ON public.%I;
       CREATE POLICY "allow_all_for_company_members" ON public.%I
       FOR ALL USING (company_id = auth.get_current_company_id());',
      tbl_name, tbl_name
    );
  END LOOP;
END $$;


-- Function to check user permissions
CREATE OR REPLACE FUNCTION public.check_user_permission(p_user_id uuid, p_required_role company_role)
RETURNS boolean AS $$
DECLARE
  user_role company_role;
BEGIN
  SELECT role INTO user_role FROM public.company_users WHERE user_id = p_user_id;
  IF user_role IS NULL THEN RETURN FALSE; END IF;
  
  IF p_required_role = 'Owner' THEN
    RETURN user_role = 'Owner';
  ELSIF p_required_role = 'Admin' THEN
    RETURN user_role IN ('Owner', 'Admin');
  END IF;
  RETURN FALSE;
END;
$$ LANGUAGE plpgsql;


-- Initial table creation for products, suppliers, etc.
CREATE TABLE IF NOT EXISTS public.products (
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
  updated_at timestamptz
);
CREATE UNIQUE INDEX IF NOT EXISTS products_company_external_id_idx ON public.products (company_id, external_product_id);

CREATE TABLE IF NOT EXISTS public.suppliers (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  name text NOT NULL,
  email text,
  phone text,
  default_lead_time_days integer,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.product_variants (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL,
  sku text NOT NULL,
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
  inventory_quantity integer NOT NULL DEFAULT 0,
  reorder_point integer,
  reorder_quantity integer,
  location text,
  external_variant_id text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz
);
CREATE UNIQUE INDEX IF NOT EXISTS variants_company_sku_idx ON public.product_variants (company_id, sku);
CREATE UNIQUE INDEX IF NOT EXISTS variants_company_external_id_idx ON public.product_variants (company_id, external_variant_id);


CREATE TABLE IF NOT EXISTS public.customers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    external_customer_id text,
    name text,
    email text,
    phone text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    deleted_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.orders (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number text NOT NULL,
    external_order_id text,
    customer_id uuid REFERENCES public.customers(id),
    financial_status text,
    fulfillment_status text,
    currency text,
    subtotal integer NOT NULL,
    total_tax integer,
    total_shipping integer,
    total_discounts integer,
    total_amount integer NOT NULL,
    source_platform text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id uuid REFERENCES public.product_variants(id),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_name text,
    variant_title text,
    sku text,
    quantity integer NOT NULL,
    price integer NOT NULL,
    total_discount integer,
    tax_amount integer,
    cost_at_time integer, -- cost of the variant at the time of sale
    external_line_item_id text
);

CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.suppliers(id),
    status text NOT NULL DEFAULT 'Draft',
    po_number text NOT NULL,
    total_cost integer NOT NULL,
    expected_arrival_date date,
    notes text,
    idempotency_key uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    purchase_order_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    quantity integer NOT NULL,
    cost integer NOT NULL
);

-- =================================================================
-- Views for simplified data access
-- =================================================================
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT 
    pv.*,
    p.title as product_title,
    p.status as product_status,
    p.image_url,
    p.product_type
FROM 
    public.product_variants pv
JOIN 
    public.products p ON pv.product_id = p.id;

CREATE OR REPLACE VIEW public.customers_view AS
SELECT
    c.id,
    c.company_id,
    c.name as customer_name,
    c.email,
    count(o.id) as total_orders,
    sum(o.total_amount) as total_spent,
    min(o.created_at) as first_order_date,
    c.created_at
FROM
    public.customers c
LEFT JOIN
    public.orders o ON c.id = o.customer_id
WHERE c.deleted_at IS NULL
GROUP BY
    c.id;
    
CREATE OR REPLACE VIEW public.orders_view AS
SELECT 
    o.*,
    c.email as customer_email
FROM 
    public.orders o
LEFT JOIN 
    public.customers c ON o.customer_id = c.id;


-- =================================================================
-- Additional Tables for App Features
-- =================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'integration_platform') THEN
        CREATE TYPE public.integration_platform AS ENUM ('shopify', 'woocommerce', 'amazon_fba');
    END IF;
END$$;

CREATE TABLE IF NOT EXISTS public.integrations (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  platform public.integration_platform NOT NULL,
  shop_domain text,
  shop_name text,
  is_active boolean DEFAULT false,
  last_sync_at timestamptz,
  sync_status text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz
);
CREATE UNIQUE INDEX IF NOT EXISTS integrations_company_platform_idx ON public.integrations (company_id, platform);

-- Conversations for AI Chat
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'message_role') THEN
        CREATE TYPE public.message_role AS ENUM ('user', 'assistant', 'tool');
    END IF;
END$$;


CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    created_at timestamptz DEFAULT now(),
    last_accessed_at timestamptz DEFAULT now(),
    is_starred boolean DEFAULT false
);

CREATE TABLE IF NOT EXISTS public.messages (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role public.message_role NOT NULL,
    content text NOT NULL,
    visualization jsonb,
    component text,
    componentProps jsonb,
    confidence real CHECK (confidence >= 0 AND confidence <= 1),
    assumptions text[],
    isError boolean default false,
    created_at timestamptz DEFAULT now()
);

-- Audit Log Table
CREATE TABLE IF NOT EXISTS public.audit_log (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    action text NOT NULL,
    details jsonb,
    created_at timestamptz DEFAULT now()
);


-- Feedback Table
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'feedback_type') THEN
        CREATE TYPE public.feedback_type AS ENUM ('helpful', 'unhelpful');
    END IF;
END$$;

CREATE TABLE IF NOT EXISTS public.feedback (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    subject_id text NOT NULL,
    subject_type text NOT NULL,
    feedback public.feedback_type NOT NULL,
    created_at timestamptz DEFAULT now()
);


-- Channel Fees Table
CREATE TABLE IF NOT EXISTS public.channel_fees (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    channel_name text NOT NULL,
    percentage_fee numeric,
    fixed_fee integer, -- in cents
    created_at timestamptz default now(),
    updated_at timestamptz
);
CREATE UNIQUE INDEX IF NOT EXISTS channel_fees_company_id_channel_name_idx ON public.channel_fees (company_id, channel_name);

-- Grant usage on schemas
GRANT USAGE ON SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT USAGE ON SCHEMA public TO supabase_admin;

-- Grant all privileges on tables
GRANT ALL ON ALL TABLES IN SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO supabase_admin;

-- Grant all privileges on functions
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO supabase_admin;

-- Grant all privileges on sequences
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO supabase_admin;
