-- ARVO: Complete Database Schema

-- This file is intended to be run once to set up the database.
-- It is idempotent and can be run multiple times safely.

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
-- Enable vector extension for pgvector
CREATE EXTENSION IF NOT EXISTS "vector";

-- =============================================
-- ENUMS
-- =============================================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'company_role') THEN
    CREATE TYPE public.company_role AS ENUM ('Owner', 'Admin', 'Member');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'message_role') THEN
    CREATE TYPE public.message_role AS ENUM ('user', 'assistant', 'tool');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'feedback_type') THEN
    CREATE TYPE public.feedback_type AS ENUM ('helpful', 'unhelpful');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'integration_platform') THEN
    CREATE TYPE public.integration_platform AS ENUM ('shopify', 'woocommerce', 'amazon_fba');
  END IF;
END$$;


-- =============================================
-- TABLES
-- =============================================

-- Companies Table
CREATE TABLE IF NOT EXISTS public.companies (
  id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
  name text NOT NULL,
  owner_id uuid REFERENCES auth.users(id) NOT NULL,
  created_at timestamptz DEFAULT now() NOT NULL
);

-- Company Users Join Table
CREATE TABLE IF NOT EXISTS public.company_users (
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE NOT NULL,
  role public.company_role DEFAULT 'Member'::public.company_role NOT NULL,
  PRIMARY KEY (user_id, company_id)
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_company_users_user ON public.company_users (user_id);


-- Company Settings Table
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE NOT NULL,
    dead_stock_days integer DEFAULT 90 NOT NULL,
    fast_moving_days integer DEFAULT 30 NOT NULL,
    predictive_stock_days integer DEFAULT 7 NOT NULL,
    currency text DEFAULT 'USD'::text NOT NULL,
    timezone text DEFAULT 'UTC'::text NOT NULL,
    tax_rate real DEFAULT 0 NOT NULL,
    overstock_multiplier integer DEFAULT 3 NOT NULL,
    high_value_threshold integer DEFAULT 100000 NOT NULL,
    alert_settings jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz
);


-- Suppliers Table
CREATE TABLE IF NOT EXISTS public.suppliers (
  id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
  company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE NOT NULL,
  name text NOT NULL,
  email text,
  phone text,
  default_lead_time_days integer,
  notes text,
  created_at timestamptz DEFAULT now() NOT NULL,
  updated_at timestamptz
);

-- Products Table
CREATE TABLE IF NOT EXISTS public.products (
  id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
  company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE NOT NULL,
  title text NOT NULL,
  description text,
  handle text,
  product_type text,
  tags text[],
  status text,
  image_url text,
  external_product_id text,
  created_at timestamptz DEFAULT now() NOT NULL,
  updated_at timestamptz
);
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_products_company_external_id ON public.products(company_id, external_product_id);


-- Product Variants Table
CREATE TABLE IF NOT EXISTS public.product_variants (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    product_id uuid REFERENCES public.products(id) ON DELETE CASCADE NOT NULL,
    company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE NOT NULL,
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
    reorder_point integer,
    reorder_quantity integer,
    supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz
);
CREATE INDEX IF NOT EXISTS idx_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_variants_company_id ON public.product_variants(company_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_variants_company_sku ON public.product_variants(company_id, sku);
CREATE UNIQUE INDEX IF NOT EXISTS idx_variants_company_external_id ON public.product_variants(company_id, external_variant_id);


-- Customers Table
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE NOT NULL,
    name text,
    email text,
    phone text,
    external_customer_id text,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz,
    deleted_at timestamptz
);
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers(company_id);


-- Orders Table
CREATE TABLE IF NOT EXISTS public.orders (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE NOT NULL,
    order_number text NOT NULL,
    external_order_id text,
    customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
    financial_status text,
    fulfillment_status text,
    currency text,
    subtotal integer NOT NULL,
    total_tax integer,
    total_shipping integer,
    total_discounts integer,
    total_amount integer NOT NULL,
    source_platform text,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz
);
CREATE INDEX IF NOT EXISTS idx_orders_company_id_created_at ON public.orders(company_id, created_at DESC);


-- Order Line Items Table
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    order_id uuid REFERENCES public.orders(id) ON DELETE CASCADE NOT NULL,
    variant_id uuid REFERENCES public.product_variants(id) ON DELETE SET NULL,
    company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE NOT NULL,
    product_name text,
    variant_title text,
    sku text,
    quantity integer NOT NULL,
    price integer NOT NULL,
    total_discount integer,
    tax_amount integer,
    cost_at_time integer,
    external_line_item_id text
);
CREATE INDEX IF NOT EXISTS idx_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_line_items_variant_id ON public.order_line_items(variant_id);

-- Inventory Ledger Table
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE NOT NULL,
    variant_id uuid REFERENCES public.product_variants(id) ON DELETE CASCADE NOT NULL,
    change_type text NOT NULL, -- e.g., 'sale', 'purchase_order', 'reconciliation', 'manual_adjustment'
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid,
    notes text,
    created_at timestamptz DEFAULT now() NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id_created_at ON public.inventory_ledger(variant_id, created_at DESC);


-- =============================================
-- FUNCTIONS & TRIGGERS
-- =============================================

-- Function to handle new user signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_name text;
  v_lock_key bigint;
BEGIN
  -- Advisory lock per user to prevent concurrent trigger re-entry
  v_lock_key := ('x' || substr(md5(new.id::text), 1, 16))::bit(64)::bigint;
  perform pg_advisory_xact_lock(v_lock_key);

  -- If already associated, do nothing (idempotent)
  SELECT cu.company_id INTO v_company_id
  FROM public.company_users cu
  WHERE cu.user_id = new.id
  LIMIT 1;

  IF v_company_id IS NOT NULL THEN
    RETURN new;
  END IF;

  v_name := COALESCE(new.raw_user_meta_data->>'company_name',
                     'Company for ' || COALESCE(new.email, new.id::text));

  INSERT INTO public.companies (name, owner_id)
  VALUES (v_name, new.id)
  RETURNING id INTO v_company_id;

  -- Create company settings with defaults
  INSERT INTO public.company_settings (company_id)
  VALUES (v_company_id)
  ON CONFLICT (company_id) DO NOTHING;

  INSERT INTO public.company_users (user_id, company_id, role)
  VALUES (new.id, v_company_id, 'Owner')
  ON CONFLICT DO NOTHING;

  UPDATE auth.users
     SET raw_app_meta_data = COALESCE(raw_app_meta_data, '{}'::jsonb)
                           || jsonb_build_object('company_id', v_company_id)
   WHERE id = new.id;

  RETURN new;
END;
$$;
ALTER function public.handle_new_user() owner to postgres;

-- Trigger to call handle_new_user on new user signup
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
  

-- =============================================
-- RLS (Row-Level Security)
-- =============================================

-- Enable RLS for all tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;

-- Policies for companies
CREATE POLICY "Allow user to read their own company" ON public.companies FOR SELECT
  USING (id IN (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));

-- Policies for company_users
CREATE POLICY "Allow user to read their own company user associations" ON public.company_users FOR SELECT
  USING (company_id IN (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));

-- Generic policies for tables with a company_id
DO $$
DECLARE
  table_name text;
BEGIN
  FOR table_name IN SELECT tbl.table_name FROM information_schema.tables tbl WHERE tbl.table_schema = 'public' AND tbl.table_name NOT IN ('companies', 'company_users')
  LOOP
     EXECUTE format('CREATE POLICY "Allow full access based on company" ON public.%I FOR ALL USING (company_id IN (SELECT company_id FROM public.company_users WHERE user_id = auth.uid())) WITH CHECK (company_id IN (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));', table_name);
  END LOOP;
END;
$$;


-- =============================================
-- RPC FUNCTIONS
-- =============================================

CREATE OR REPLACE FUNCTION public.get_dead_stock_report(p_company_id uuid)
RETURNS TABLE(sku text, product_name text, quantity integer, total_value bigint, last_sale_date timestamptz)
LANGUAGE plpgsql
AS $$
DECLARE
    v_dead_stock_days int;
BEGIN
    SELECT cs.dead_stock_days INTO v_dead_stock_days
    FROM public.company_settings cs
    WHERE cs.company_id = p_company_id;

    IF v_dead_stock_days IS NULL THEN
        v_dead_stock_days := 90;
    END IF;

    RETURN QUERY
    WITH last_sales AS (
        SELECT
            oli.variant_id,
            MAX(o.created_at) as last_sale
        FROM public.order_line_items oli
        JOIN public.orders o ON oli.order_id = o.id
        WHERE o.company_id = p_company_id
        GROUP BY oli.variant_id
    )
    SELECT
        pv.sku,
        p.title AS product_name,
        pv.inventory_quantity AS quantity,
        (pv.inventory_quantity * pv.cost)::bigint AS total_value,
        ls.last_sale
    FROM public.product_variants pv
    JOIN public.products p ON pv.product_id = p.id
    LEFT JOIN last_sales ls ON pv.id = ls.variant_id
    WHERE pv.company_id = p_company_id
      AND pv.inventory_quantity > 0
      AND (ls.last_sale IS NULL OR ls.last_sale < (NOW() - (v_dead_stock_days || ' days')::interval));
END;
$$;

CREATE OR REPLACE FUNCTION public.get_reorder_suggestions(p_company_id uuid)
RETURNS TABLE (
    variant_id uuid,
    product_id uuid,
    sku text,
    product_name text,
    supplier_id uuid,
    supplier_name text,
    current_quantity integer,
    suggested_reorder_quantity integer,
    unit_cost integer
)
LANGUAGE sql
STABLE
AS $$
SELECT
    pv.id AS variant_id,
    pv.product_id,
    pv.sku,
    p.title AS product_name,
    pv.supplier_id,
    s.name AS supplier_name,
    pv.inventory_quantity AS current_quantity,
    pv.reorder_quantity AS suggested_reorder_quantity,
    pv.cost AS unit_cost
FROM
    public.product_variants pv
JOIN
    public.products p ON pv.product_id = p.id
LEFT JOIN
    public.suppliers s ON pv.supplier_id = s.id
WHERE
    pv.company_id = p_company_id
    AND pv.reorder_point IS NOT NULL
    AND pv.inventory_quantity <= pv.reorder_point;
$$;


-- A view for sales data
CREATE OR REPLACE VIEW public.sales AS
SELECT
  o.id AS order_id,
  o.company_id,
  o.order_number,
  o.created_at,
  o.financial_status AS status,
  oli.variant_id,
  p.id AS product_id,
  oli.quantity,
  oli.price AS unit_price,
  (oli.quantity * oli.price) AS line_total
FROM 
  public.orders o
JOIN 
  public.order_line_items oli ON oli.order_id = o.id
JOIN
  public.product_variants pv ON pv.id = oli.variant_id
JOIN
  public.products p ON p.id = pv.product_id;

-- Ensure the policies are applied to the view owner
ALTER VIEW public.sales OWNER TO postgres;

```