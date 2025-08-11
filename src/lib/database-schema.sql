-- src/lib/database-schema.sql

-- Drop existing functions to ensure a clean slate
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.get_company_id_for_user(uuid);
DROP FUNCTION IF EXISTS public.check_user_permission(uuid, company_role);
DROP FUNCTION IF EXISTS public.record_order_from_platform(uuid, jsonb, text);
DROP FUNCTION IF EXISTS public.get_dashboard_metrics(uuid, int);

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create ENUM types for roles and platforms
CREATE TYPE public.company_role AS ENUM ('Owner', 'Admin', 'Member');
CREATE TYPE public.integration_platform AS ENUM ('shopify', 'woocommerce', 'amazon_fba');
CREATE TYPE public.message_role AS ENUM ('user', 'assistant', 'tool');
CREATE TYPE public.feedback_type AS ENUM ('helpful', 'unhelpful');


-- Companies Table: Stores company information
CREATE TABLE public.companies (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    name text NOT NULL,
    owner_id uuid NOT NULL REFERENCES auth.users(id),
    created_at timestamptz DEFAULT now() NOT NULL
);
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can see their own company" ON public.companies FOR SELECT USING (id IN (SELECT public.get_company_id_for_user(auth.uid())));

-- Company Users Table: Links users to companies with roles
CREATE TABLE public.company_users (
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role public.company_role DEFAULT 'Member'::public.company_role NOT NULL,
    PRIMARY KEY (user_id, company_id)
);
ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can see their own company memberships" ON public.company_users FOR SELECT USING (company_id IN (SELECT public.get_company_id_for_user(auth.uid())));

-- Company Settings Table
CREATE TABLE public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer DEFAULT 90 NOT NULL CHECK (dead_stock_days > 0),
    fast_moving_days integer DEFAULT 30 NOT NULL CHECK (fast_moving_days > 0),
    predictive_stock_days integer DEFAULT 7 NOT NULL CHECK (predictive_stock_days > 0),
    currency text DEFAULT 'USD' NOT NULL,
    timezone text DEFAULT 'UTC' NOT NULL,
    overstock_multiplier numeric DEFAULT 3 NOT NULL,
    high_value_threshold integer DEFAULT 100000 NOT NULL,
    tax_rate numeric(5,4) DEFAULT 0.0 NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz
);
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage their own company settings" ON public.company_settings FOR ALL USING (company_id IN (SELECT public.get_company_id_for_user(auth.uid())));

-- Products Table
CREATE TABLE public.products (
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
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz,
    UNIQUE(company_id, external_product_id)
);
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage products in their own company" ON public.products FOR ALL USING (company_id IN (SELECT public.get_company_id_for_user(auth.uid())));

-- Suppliers Table
CREATE TABLE public.suppliers (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz
);
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage suppliers in their own company" ON public.suppliers FOR ALL USING (company_id IN (SELECT public.get_company_id_for_user(auth.uid())));

-- Product Variants Table
CREATE TABLE public.product_variants (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
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
    price integer, -- in cents
    compare_at_price integer, -- in cents
    cost integer, -- in cents
    inventory_quantity integer DEFAULT 0 NOT NULL,
    location text,
    supplier_id uuid REFERENCES public.suppliers(id),
    reorder_point integer,
    reorder_quantity integer,
    external_variant_id text,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz,
    UNIQUE(company_id, sku)
);
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage variants in their own company" ON public.product_variants FOR ALL USING (company_id IN (SELECT public.get_company_id_for_user(auth.uid())));

-- Customers Table
CREATE TABLE public.customers (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text,
    email text,
    phone text,
    external_customer_id text,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz,
    deleted_at timestamptz,
    UNIQUE(company_id, external_customer_id)
);
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage customers in their own company" ON public.customers FOR ALL USING (company_id IN (SELECT public.get_company_id_for_user(auth.uid())));

-- Orders Table
CREATE TABLE public.orders (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
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
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz,
    UNIQUE(company_id, external_order_id)
);
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage orders in their own company" ON public.orders FOR ALL USING (company_id IN (SELECT public.get_company_id_for_user(auth.uid())));


-- Order Line Items Table
CREATE TABLE public.order_line_items (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id uuid REFERENCES public.product_variants(id),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_name text,
    variant_title text,
    sku text,
    quantity integer NOT NULL,
    price integer NOT NULL, -- in cents
    total_discount integer,
    tax_amount integer,
    cost_at_time integer,
    external_line_item_id text
);
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage line items in their own company" ON public.order_line_items FOR ALL USING (company_id IN (SELECT public.get_company_id_for_user(auth.uid())));

-- Purchase Orders Table
CREATE TABLE public.purchase_orders (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.suppliers(id),
    status text DEFAULT 'Draft' NOT NULL,
    po_number text NOT NULL,
    total_cost integer NOT NULL,
    expected_arrival_date date,
    idempotency_key uuid,
    notes text,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz
);
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage POs in their own company" ON public.purchase_orders FOR ALL USING (company_id IN (SELECT public.get_company_id_for_user(auth.uid())));

-- Purchase Order Line Items Table
CREATE TABLE public.purchase_order_line_items (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    purchase_order_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    quantity integer NOT NULL,
    cost integer NOT NULL -- in cents
);
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage PO line items in their own company" ON public.purchase_order_line_items FOR ALL USING (company_id IN (SELECT public.get_company_id_for_user(auth.uid())));

-- Inventory Ledger Table
CREATE TABLE public.inventory_ledger (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id),
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid,
    notes text,
    created_at timestamptz DEFAULT now() NOT NULL
);
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view inventory ledger in their own company" ON public.inventory_ledger FOR ALL USING (company_id IN (SELECT public.get_company_id_for_user(auth.uid())));

-- Integrations Table
CREATE TABLE public.integrations (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform public.integration_platform NOT NULL,
    shop_domain text,
    shop_name text,
    is_active boolean DEFAULT true NOT NULL,
    last_sync_at timestamptz,
    sync_status text,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz,
    UNIQUE (company_id, platform)
);
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage integrations in their own company" ON public.integrations FOR ALL USING (company_id IN (SELECT public.get_company_id_for_user(auth.uid())));

-- Helper function to get a user's company ID
CREATE OR REPLACE FUNCTION public.get_company_id_for_user(p_user_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN (
    SELECT company_id
    FROM public.company_users
    WHERE user_id = p_user_id
    LIMIT 1
  );
END;
$$;

-- Function to create a company and link it to the owner on new user signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  company_id_val uuid;
BEGIN
  -- Create a new company for the new user
  INSERT INTO public.companies (name, owner_id)
  VALUES (new.raw_user_meta_data->>'company_name', new.id)
  RETURNING id INTO company_id_val;

  -- Link the new user to their new company as an Owner
  INSERT INTO public.company_users (user_id, company_id, role)
  VALUES (new.id, company_id_val, 'Owner');
  
  -- Update the user's app_metadata with the company_id
  UPDATE auth.users
  SET app_metadata = jsonb_set(app_metadata, '{company_id}', to_jsonb(company_id_val))
  WHERE id = new.id;
  
  RETURN new;
END;
$$;

-- Trigger to call handle_new_user on new user creation in auth.users
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- Indexes for performance
CREATE INDEX idx_products_company_id ON public.products(company_id);
CREATE INDEX idx_variants_product_id ON public.product_variants(product_id);
CREATE INDEX idx_variants_company_sku ON public.product_variants(company_id, sku);
CREATE INDEX idx_orders_company_date ON public.orders(company_id, created_at DESC);
CREATE INDEX idx_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX idx_line_items_variant_id ON public.order_line_items(variant_id);

-- Function to check user permissions
CREATE OR REPLACE FUNCTION public.check_user_permission(p_user_id uuid, p_required_role public.company_role)
RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
    user_role public.company_role;
BEGIN
    SELECT role INTO user_role FROM public.company_users WHERE user_id = p_user_id;

    IF user_role IS NULL THEN
        RETURN FALSE;
    END IF;

    IF p_required_role = 'Owner' AND user_role = 'Owner' THEN
        RETURN TRUE;
    ELSIF p_required_role = 'Admin' AND (user_role = 'Owner' OR user_role = 'Admin') THEN
        RETURN TRUE;
    ELSE
        RETURN FALSE;
    END IF;
END;
$$;

-- Materialized View for Customers (to offload aggregation)
CREATE MATERIALIZED VIEW public.customers_view AS
SELECT
    c.id,
    c.company_id,
    c.name as customer_name,
    c.email,
    c.created_at,
    COUNT(o.id) as total_orders,
    COALESCE(SUM(o.total_amount), 0) as total_spent,
    MIN(o.created_at) as first_order_date
FROM public.customers c
LEFT JOIN public.orders o ON c.id = o.customer_id
WHERE c.deleted_at IS NULL
GROUP BY c.id;

CREATE UNIQUE INDEX ON public.customers_view (id);

-- Materialized View for Product Variants with Details
CREATE MATERIALIZED VIEW public.product_variants_with_details AS
SELECT
    v.*,
    p.title as product_title,
    p.status as product_status,
    p.image_url,
    p.product_type
FROM public.product_variants v
JOIN public.products p ON v.product_id = p.id;

CREATE UNIQUE INDEX ON public.product_variants_with_details (id);

-- Materialized View for Orders with Customer Details
CREATE MATERIALIZED VIEW public.orders_view AS
SELECT
    o.*,
    c.email as customer_email
FROM public.orders o
LEFT JOIN public.customers c ON o.customer_id = c.id;

CREATE UNIQUE INDEX ON public.orders_view (id);

-- RPC function to get dashboard metrics
CREATE OR REPLACE FUNCTION public.get_dashboard_metrics(p_company_id uuid, p_days int)
RETURNS json
LANGUAGE plpgsql
AS $$
DECLARE
    metrics json;
BEGIN
    SELECT json_build_object(
        'total_revenue', COALESCE(SUM(total_amount), 0),
        'total_orders', COUNT(id),
        'top_products', (
            SELECT json_agg(p)
            FROM (
                SELECT p.product_title, p.image_url, SUM(li.quantity) as quantity_sold, SUM(li.price * li.quantity) as total_revenue
                FROM public.order_line_items li
                JOIN public.product_variants_with_details p ON li.variant_id = p.id
                WHERE li.company_id = p_company_id AND li.created_at >= NOW() - (p_days || ' days')::interval
                GROUP BY p.product_title, p.image_url
                ORDER BY total_revenue DESC
                LIMIT 5
            ) p
        )
    )
    INTO metrics
    FROM public.orders_view
    WHERE company_id = p_company_id AND created_at >= NOW() - (p_days || ' days')::interval;
    RETURN metrics;
END;
$$;

-- Function to get dead stock report
CREATE OR REPLACE FUNCTION public.get_dead_stock_report(p_company_id uuid)
RETURNS TABLE (
  variant_id uuid,
  product_id uuid,
  sku text,
  product_name text,
  inventory_quantity int,
  cost bigint,
  total_value bigint,
  last_sale_date timestamptz
)
LANGUAGE sql
STABLE
AS $$
WITH variant_last_sale AS (
  SELECT li.variant_id, MAX(o.created_at) AS last_sale_at
  FROM public.order_line_items li
  JOIN public.orders o ON o.id = li.order_id
  WHERE o.company_id = p_company_id
  GROUP BY li.variant_id
),
settings AS (
  SELECT COALESCE(cs.dead_stock_days, 90) AS days
  FROM public.company_settings cs
  WHERE cs.company_id = p_company_id
)
SELECT
  v.id,
  v.product_id,
  v.sku,
  p.title as product_name,
  v.inventory_quantity,
  (v.cost)::bigint,
  (v.inventory_quantity::bigint * v.cost) as total_value,
  ls.last_sale_at
FROM public.product_variants v
LEFT JOIN variant_last_sale ls ON ls.variant_id = v.id
JOIN public.products p ON p.id = v.product_id
CROSS JOIN settings s
WHERE v.company_id = p_company_id
  AND v.inventory_quantity > 0
  AND (ls.last_sale_at IS NULL OR ls.last_sale_at < (now() - make_interval(days => s.days)));
$$;


-- Grant usage on the schema to the anon and authenticated roles
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

-- Grant select on all tables to anon and authenticated roles
GRANT SELECT ON ALL TABLES IN SCHEMA public TO anon, authenticated;

-- Grant execute on all functions to anon and authenticated roles
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO anon, authenticated, service_role;

-- Grant all privileges to the service_role for migrations and admin tasks
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO service_role;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO service_role;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO service_role;
