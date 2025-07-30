-- Protect against accidentally dropping the entire public schema.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_namespace
    WHERE nspname = 'public'
  ) THEN
    CREATE SCHEMA public;
  END IF;
END $$;


-- #################################################################
-- #############           ENUMS & TYPES              ##############
-- #################################################################

-- Create ENUM types for status columns to enforce data consistency.
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
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'po_status') THEN
    CREATE TYPE public.po_status AS ENUM ('Draft', 'Ordered', 'Partially Received', 'Received', 'Cancelled');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'order_financial_status') THEN
    CREATE TYPE public.order_financial_status AS ENUM ('pending', 'paid', 'refunded', 'partially_refunded', 'voided');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'order_fulfillment_status') THEN
    CREATE TYPE public.order_fulfillment_status AS ENUM ('fulfilled', 'unfulfilled', 'partially_fulfilled', 'restocked');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'product_status') THEN
    CREATE TYPE public.product_status AS ENUM ('active', 'draft', 'archived');
  END IF;
END $$;


-- #################################################################
-- #############              TABLES                  ##############
-- #################################################################

CREATE TABLE IF NOT EXISTS public.companies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    owner_id UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.company_users (
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role company_role NOT NULL DEFAULT 'Member',
    PRIMARY KEY (company_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id UUID PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days INTEGER NOT NULL DEFAULT 90,
    fast_moving_days INTEGER NOT NULL DEFAULT 30,
    predictive_stock_days INTEGER NOT NULL DEFAULT 7,
    currency TEXT DEFAULT 'USD',
    timezone TEXT DEFAULT 'UTC',
    tax_rate NUMERIC DEFAULT 0,
    alert_settings JSONB DEFAULT '{}'::jsonb,
    overstock_multiplier INTEGER NOT NULL DEFAULT 3,
    high_value_threshold INTEGER NOT NULL DEFAULT 100000, -- in cents
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS public.suppliers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    default_lead_time_days INTEGER,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS public.products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    handle TEXT,
    product_type TEXT,
    tags TEXT[],
    status product_status DEFAULT 'active',
    image_url TEXT,
    external_product_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, external_product_id)
);

CREATE TABLE IF NOT EXISTS public.product_variants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id UUID REFERENCES public.suppliers(id) ON DELETE SET NULL,
    sku TEXT NOT NULL,
    title TEXT,
    option1_name TEXT,
    option1_value TEXT,
    option2_name TEXT,
    option2_value TEXT,
    option3_name TEXT,
    option3_value TEXT,
    barcode TEXT,
    price INTEGER, -- in cents
    compare_at_price INTEGER, -- in cents
    cost INTEGER, -- in cents
    inventory_quantity INTEGER NOT NULL DEFAULT 0,
    reorder_point INTEGER,
    reorder_quantity INTEGER,
    location TEXT,
    external_variant_id TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, sku),
    UNIQUE(company_id, external_variant_id)
);

CREATE TABLE IF NOT EXISTS public.customers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name TEXT,
    email TEXT,
    phone TEXT,
    external_customer_id TEXT,
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, email),
    UNIQUE(company_id, external_customer_id)
);

CREATE TABLE IF NOT EXISTS public.orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_id UUID REFERENCES public.customers(id) ON DELETE SET NULL,
    order_number TEXT NOT NULL,
    external_order_id TEXT,
    financial_status order_financial_status,
    fulfillment_status order_fulfillment_status,
    currency TEXT,
    subtotal INTEGER NOT NULL,
    total_tax INTEGER,
    total_shipping INTEGER,
    total_discounts INTEGER,
    total_amount INTEGER NOT NULL,
    source_platform TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS public.order_line_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id UUID REFERENCES public.product_variants(id) ON DELETE SET NULL, -- Use SET NULL to preserve sales history
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_name TEXT,
    variant_title TEXT,
    sku TEXT,
    quantity INTEGER NOT NULL,
    price INTEGER NOT NULL,
    total_discount INTEGER,
    tax_amount INTEGER,
    cost_at_time INTEGER,
    external_line_item_id TEXT
);

CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type TEXT NOT NULL, -- e.g., 'sale', 'purchase_order', 'reconciliation', 'manual_adjustment'
    quantity_change INTEGER NOT NULL,
    new_quantity INTEGER NOT NULL,
    related_id UUID, -- Optional ID for related record (e.g., order_id, po_id)
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id UUID REFERENCES public.suppliers(id) ON DELETE SET NULL,
    status po_status NOT NULL DEFAULT 'Draft',
    po_number TEXT NOT NULL,
    total_cost INTEGER NOT NULL,
    expected_arrival_date DATE,
    notes TEXT,
    idempotency_key UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, po_number)
);

CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    purchase_order_id UUID NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    quantity INTEGER NOT NULL,
    cost INTEGER NOT NULL
);

-- #################################################################
-- #############        SIGNUP & AUTH LOGIC           ##############
-- #################################################################

-- Function to create a company and user in a single transaction
DROP FUNCTION IF EXISTS public.create_company_and_user(text, text, text);
CREATE OR REPLACE FUNCTION public.create_company_and_user(
    p_company_name TEXT,
    p_user_email TEXT,
    p_user_password TEXT
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_company_id UUID;
  v_user_id UUID;
BEGIN
  -- 1. Create the company
  INSERT INTO public.companies (name)
  VALUES (p_company_name)
  RETURNING id INTO v_company_id;

  -- 2. Create the user in auth.users, passing company_id in metadata
  INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, recovery_token, recovery_sent_at, last_sign_in_at, raw_app_meta_data, created_at, updated_at, confirmation_token, email_change, email_change_sent_at, reauthentication_token, reauthentication_sent_at)
  VALUES (
    '00000000-0000-0000-0000-000000000000', gen_random_uuid(), 'authenticated', 'authenticated', p_user_email, crypt(p_user_password, gen_salt('bf')), now(), 'deprecated', now(), now(), 
    jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email'), 'company_id', v_company_id), 
    now(), now(), '', '', now(), '', now()
  ) RETURNING id INTO v_user_id;

  -- 3. Update the company with the owner_id
  UPDATE public.companies
  SET owner_id = v_user_id
  WHERE id = v_company_id;

  -- 4. Link user to company in the pivot table as Owner
  INSERT INTO public.company_users (company_id, user_id, role)
  VALUES (v_company_id, v_user_id, 'Owner');

  RETURN v_user_id;
END;
$$;


-- #################################################################
-- #############              VIEWS                   ##############
-- #################################################################

-- This view is no longer needed as the application will use auth.users and company_users directly.
DROP VIEW IF EXISTS public.users_view;

CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT 
    pv.*,
    p.title AS product_title,
    p.status AS product_status,
    p.image_url,
    p.product_type
FROM public.product_variants pv
JOIN public.products p ON pv.product_id = p.id;

CREATE OR REPLACE VIEW public.purchase_orders_view AS
SELECT 
    po.*,
    s.name as supplier_name,
    (
        SELECT json_agg(json_build_object(
            'id', poli.id,
            'sku', pv.sku,
            'product_name', p.title,
            'quantity', poli.quantity,
            'cost', poli.cost
        ))
        FROM public.purchase_order_line_items poli
        JOIN public.product_variants pv ON poli.variant_id = pv.id
        JOIN public.products p ON pv.product_id = p.id
        WHERE poli.purchase_order_id = po.id
    ) AS line_items
FROM public.purchase_orders po
LEFT JOIN public.suppliers s ON po.supplier_id = s.id;


-- #################################################################
-- #############        RLS (Row Level Security)      ##############
-- #################################################################

-- Enable RLS on all relevant tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
-- Add other tables as needed...

-- Policies
DROP POLICY IF EXISTS "Allow all access to own company" ON public.companies;
CREATE POLICY "Allow all access to own company" ON public.companies
FOR ALL
USING (id = (current_setting('request.jwt.claims', true)::jsonb ->> 'company_id')::uuid);

-- Generic policy for most tables
DO
$$
DECLARE
    t_name TEXT;
BEGIN
    FOR t_name IN
        SELECT table_name
        FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name NOT IN ('companies') -- companies has its own policy
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS "Allow all access based on company_id" ON public.%I;', t_name);
        EXECUTE format('
            CREATE POLICY "Allow all access based on company_id" ON public.%I
            FOR ALL
            USING (company_id = (current_setting(''request.jwt.claims'', true)::jsonb ->> ''company_id'')::uuid);
        ', t_name);
    END LOOP;
END;
$$;
