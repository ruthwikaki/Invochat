
-- Enable the UUID extension if it's not already enabled.
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
-- Enable the pg_stat_statements extension for monitoring query performance.
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";
-- Enable the pgcrypto extension for cryptographic functions.
CREATE EXTENSION IF NOT EXISTS "pgcrypto";


-- Define custom types for company roles and integration platforms.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'company_role') THEN
        CREATE TYPE public.company_role AS ENUM ('Owner', 'Admin', 'Member');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'integration_platform') THEN
        CREATE TYPE public.integration_platform AS ENUM ('shopify', 'woocommerce', 'amazon_fba');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'message_role') THEN
        CREATE TYPE public.message_role AS ENUM ('user', 'assistant', 'tool');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'feedback_type') THEN
      CREATE TYPE public.feedback_type AS ENUM ('helpful', 'unhelpful');
    END IF;
END$$;


-- Create the companies table to store company information.
CREATE TABLE IF NOT EXISTS public.companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    owner_id UUID NOT NULL REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.companies IS 'Stores company information.';

-- Create the company_users table to manage user roles within companies.
CREATE TABLE IF NOT EXISTS public.company_users (
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE,
    role company_role NOT NULL DEFAULT 'Member',
    PRIMARY KEY (user_id, company_id)
);
COMMENT ON TABLE public.company_users IS 'Manages user roles within companies.';


-- Enable Row-Level Security (RLS) for all tables in the public schema.
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;

-- RLS policy for companies: Users can only see their own company.
DROP POLICY IF EXISTS "Users can see their own company" ON public.companies;
CREATE POLICY "Users can see their own company" ON public.companies FOR SELECT
USING (id IN (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));

-- RLS policy for company_users: Users can only see their own association record.
DROP POLICY IF EXISTS "Users can see their own company_users record" ON public.company_users;
CREATE POLICY "Users can see their own company_users record" ON public.company_users FOR SELECT
USING (user_id = auth.uid());


-- This function handles the automatic creation of a company and association
-- of the new user as the owner when a user signs up.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  company_id UUID;
  company_name TEXT;
BEGIN
  -- Extract company name from user metadata, default if not provided
  company_name := new.raw_user_meta_data ->> 'company_name';
  IF company_name IS NULL OR company_name = '' THEN
    company_name := new.email;
  END IF;

  -- Create a new company for the new user
  INSERT INTO public.companies (name, owner_id)
  VALUES (company_name, new.id)
  RETURNING id INTO company_id;

  -- Link the new user to the new company as 'Owner'
  INSERT INTO public.company_users (user_id, company_id, role)
  VALUES (new.id, company_id, 'Owner');
  
  -- Update the user's app_metadata with the new company_id
  UPDATE auth.users
  SET app_metadata = app_metadata || jsonb_build_object('company_id', company_id)
  WHERE id = new.id;

  RETURN new;
END;
$$;
COMMENT ON FUNCTION public.handle_new_user() IS 'Trigger function to create a company for a new user.';

-- Create a trigger that executes the handle_new_user function after a new user is inserted.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Create other application tables
CREATE TABLE IF NOT EXISTS public.products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    external_product_id TEXT,
    title TEXT NOT NULL,
    description TEXT,
    handle TEXT,
    product_type TEXT,
    tags TEXT[],
    status TEXT,
    image_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, external_product_id)
);
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage their own products" ON public.products
    FOR ALL USING (company_id IN (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));

CREATE TABLE IF NOT EXISTS public.product_variants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    external_variant_id TEXT,
    sku TEXT NOT NULL,
    title TEXT,
    option1_name TEXT,
    option1_value TEXT,
    option2_name TEXT,
    option2_value TEXT,
    option3_name TEXT,
    option3_value TEXT,
    barcode TEXT,
    price INTEGER,
    compare_at_price INTEGER,
    cost INTEGER,
    inventory_quantity INTEGER NOT NULL DEFAULT 0,
    location TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, sku),
    UNIQUE(company_id, external_variant_id)
);
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage their own product variants" ON public.product_variants
    FOR ALL USING (company_id IN (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));

CREATE TABLE IF NOT EXISTS public.suppliers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    notes TEXT,
    default_lead_time_days INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ
);
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage their own suppliers" ON public.suppliers
    FOR ALL USING (company_id IN (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));


ALTER TABLE public.product_variants
ADD COLUMN IF NOT EXISTS supplier_id UUID REFERENCES public.suppliers(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS reorder_point INTEGER,
ADD COLUMN IF NOT EXISTS reorder_quantity INTEGER;


CREATE TABLE IF NOT EXISTS public.integrations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform integration_platform NOT NULL,
    shop_domain TEXT,
    shop_name TEXT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    last_sync_at TIMESTAMPTZ,
    sync_status TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, platform)
);
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage their own integrations" ON public.integrations
    FOR ALL USING (company_id IN (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));

-- Add RPC function to check user permissions
CREATE OR REPLACE FUNCTION public.check_user_permission(
  p_user_id UUID,
  p_required_role company_role
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  user_role company_role;
BEGIN
  SELECT role INTO user_role
  FROM public.company_users
  WHERE user_id = p_user_id;

  IF user_role IS NULL THEN
    RETURN FALSE;
  END IF;

  IF p_required_role = 'Owner' AND user_role = 'Owner' THEN
    RETURN TRUE;
  ELSIF p_required_role = 'Admin' AND user_role IN ('Owner', 'Admin') THEN
    RETURN TRUE;
  END IF;
  
  RETURN FALSE;
END;
$$;

-- Add RPC function to remove a user from a company
CREATE OR REPLACE FUNCTION public.remove_user_from_company(p_user_id uuid, p_company_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  DELETE FROM public.company_users
  WHERE user_id = p_user_id AND company_id = p_company_id;
END;
$$;

-- Add RPC function to update a user's role
CREATE OR REPLACE FUNCTION public.update_user_role_in_company(p_user_id uuid, p_company_id uuid, p_new_role company_role)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.company_users
  SET role = p_new_role
  WHERE user_id = p_user_id AND company_id = p_company_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_users_for_company(p_company_id uuid)
RETURNS TABLE (id uuid, email text, role company_role)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT u.id, u.email, cu.role
  FROM auth.users u
  JOIN public.company_users cu ON u.id = cu.user_id
  WHERE cu.company_id = p_company_id;
END;
$$;

-- Add RPC function to get company ID for a user
CREATE OR REPLACE FUNCTION public.get_company_id_for_user(p_user_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_company_id uuid;
BEGIN
  SELECT company_id INTO v_company_id
  FROM public.company_users
  WHERE user_id = p_user_id;
  
  RETURN v_company_id;
END;
$$;

CREATE TABLE IF NOT EXISTS public.customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    external_customer_id TEXT,
    name TEXT,
    email TEXT,
    phone TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ,
    UNIQUE(company_id, external_customer_id)
);
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage their own customers" ON public.customers
    FOR ALL USING (company_id IN (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));

CREATE TABLE IF NOT EXISTS public.orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    external_order_id TEXT,
    order_number TEXT NOT NULL,
    customer_id UUID REFERENCES public.customers(id) ON DELETE SET NULL,
    financial_status TEXT,
    fulfillment_status TEXT,
    currency TEXT,
    subtotal INTEGER NOT NULL,
    total_tax INTEGER,
    total_shipping INTEGER,
    total_discounts INTEGER,
    total_amount INTEGER NOT NULL,
    source_platform TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, external_order_id)
);
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage their own orders" ON public.orders
    FOR ALL USING (company_id IN (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));

CREATE TABLE IF NOT EXISTS public.order_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id UUID REFERENCES public.product_variants(id) ON DELETE SET NULL,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    external_line_item_id TEXT,
    product_name TEXT,
    variant_title TEXT,
    sku TEXT,
    quantity INTEGER NOT NULL,
    price INTEGER NOT NULL,
    total_discount INTEGER,
    tax_amount INTEGER,
    cost_at_time INTEGER
);
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage their own line items" ON public.order_line_items
    FOR ALL USING (company_id IN (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));

CREATE OR REPLACE FUNCTION public.get_dead_stock_report(p_company_id uuid, p_days int DEFAULT 90)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
WITH variant_last_sale AS (
  SELECT li.variant_id, MAX(o.created_at) AS last_sale_at
  FROM public.order_line_items li
  JOIN public.orders o ON o.id = li.order_id
  WHERE o.company_id = p_company_id
    AND o.fulfillment_status != 'cancelled'
  GROUP BY li.variant_id
),
params AS (
  SELECT COALESCE(cs.dead_stock_days, p_days) AS ds_days
  FROM public.company_settings cs
  WHERE cs.company_id = p_company_id
  LIMIT 1
),
dead AS (
  SELECT
    v.id                             AS variant_id,
    v.product_id,
    v.title                          AS variant_title,
    v.sku                            AS variant_sku,
    p.title                          AS product_title,
    v.inventory_quantity,
    v.cost,
    (v.inventory_quantity * v.cost) AS value,
    ls.last_sale_at
  FROM public.product_variants v
  JOIN public.products p ON p.id = v.product_id
  LEFT JOIN variant_last_sale ls ON ls.variant_id = v.id
  CROSS JOIN params
  WHERE v.company_id = p_company_id
    AND v.inventory_quantity > 0
    AND v.cost IS NOT NULL
    AND (ls.last_sale_at IS NULL OR ls.last_sale_at < (now() - make_interval(days => params.ds_days)))
)
SELECT jsonb_build_object(
  'deadStockItems', COALESCE(jsonb_agg(to_jsonb(dead)), '[]'::jsonb),
  'totalValue',     COALESCE(SUM(dead.value), 0)
)
FROM dead;
$$;
