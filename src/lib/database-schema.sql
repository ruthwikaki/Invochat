-- This script can be used to set up your Supabase database schema.
-- For a fresh project, you can run this file in its entirety.
-- For an existing project, you may need to run sections selectively.

-- =============================================================================
-- Enable required extensions
-- =============================================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "moddatetime";

-- =============================================================================
-- Enum Types
-- =============================================================================
DO $$ BEGIN
    CREATE TYPE public.company_role AS ENUM ('Owner', 'Admin', 'Member');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE public.integration_platform AS ENUM ('shopify', 'woocommerce', 'amazon_fba');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE public.message_role AS ENUM ('user', 'assistant', 'tool');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE public.feedback_type AS ENUM ('helpful', 'unhelpful');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;


-- =============================================================================
-- Companies and Users
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    name text NOT NULL,
    owner_id uuid NOT NULL REFERENCES auth.users(id),
    created_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.company_users (
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role public.company_role DEFAULT 'Member'::public.company_role NOT NULL,
    PRIMARY KEY (company_id, user_id)
);
ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;

-- =============================================================================
-- Settings Tables
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    fast_moving_days integer NOT NULL DEFAULT 30,
    overstock_multiplier integer NOT NULL DEFAULT 3,
    high_value_threshold integer NOT NULL DEFAULT 100000, -- in cents
    predictive_stock_days integer NOT NULL DEFAULT 7,
    currency text NOT NULL DEFAULT 'USD',
    timezone text NOT NULL DEFAULT 'UTC',
    tax_rate numeric(5,4) NOT NULL DEFAULT 0,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER handle_updated_at BEFORE UPDATE ON public.company_settings FOR EACH ROW EXECUTE FUNCTION moddatetime('updated_at');

CREATE TABLE IF NOT EXISTS public.channel_fees (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    channel_name text NOT NULL,
    percentage_fee numeric(5,2),
    fixed_fee integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    UNIQUE (company_id, channel_name)
);
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER handle_updated_at BEFORE UPDATE ON public.channel_fees FOR EACH ROW EXECUTE FUNCTION moddatetime('updated_at');

-- =============================================================================
-- Core Inventory Tables
-- =============================================================================
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
    updated_at timestamp with time zone
);
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX IF NOT EXISTS products_company_id_external_product_id_idx ON public.products(company_id, external_product_id);
CREATE TRIGGER handle_updated_at BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION moddatetime('updated_at');


CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER handle_updated_at BEFORE UPDATE ON public.suppliers FOR EACH ROW EXECUTE FUNCTION moddatetime('updated_at');

CREATE TABLE IF NOT EXISTS public.product_variants (
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
    inventory_quantity integer NOT NULL DEFAULT 0,
    location text,
    external_variant_id text,
    supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL,
    reorder_point integer,
    reorder_quantity integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX IF NOT EXISTS product_variants_company_id_sku_idx ON public.product_variants(company_id, sku);
CREATE UNIQUE INDEX IF NOT EXISTS product_variants_company_id_external_variant_id_idx ON public.product_variants(company_id, external_variant_id);
CREATE TRIGGER handle_updated_at BEFORE UPDATE ON public.product_variants FOR EACH ROW EXECUTE FUNCTION moddatetime('updated_at');

-- =============================================================================
-- Order and Sales Tables
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text,
    email text,
    phone text,
    external_customer_id text,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER handle_updated_at BEFORE UPDATE ON public.customers FOR EACH ROW EXECUTE FUNCTION moddatetime('updated_at');

CREATE TABLE IF NOT EXISTS public.orders (
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
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX IF NOT EXISTS orders_company_id_external_order_id_idx ON public.orders(company_id, external_order_id);
CREATE TRIGGER handle_updated_at BEFORE UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION moddatetime('updated_at');

CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id uuid REFERENCES public.product_variants(id) ON DELETE SET NULL,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
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
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.refunds (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE RESTRICT,
    refund_number text NOT NULL,
    status text NOT NULL,
    reason text,
    note text,
    total_amount integer NOT NULL,
    created_by_user_id uuid REFERENCES auth.users(id),
    external_refund_id text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.refunds ENABLE ROW LEVEL SECURITY;

-- =============================================================================
-- Purchase Order Tables
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL,
    status text NOT NULL DEFAULT 'Draft',
    po_number text NOT NULL,
    total_cost integer NOT NULL,
    expected_arrival_date date,
    idempotency_key uuid,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER handle_updated_at BEFORE UPDATE ON public.purchase_orders FOR EACH ROW EXECUTE FUNCTION moddatetime('updated_at');

CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    purchase_order_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE RESTRICT,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    quantity integer NOT NULL,
    cost integer NOT NULL
);
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;

-- =============================================================================
-- Logging and History Tables
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;


CREATE TABLE IF NOT EXISTS public.audit_log (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id uuid REFERENCES auth.users(id),
    action text NOT NULL,
    details jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

-- =============================================================================
-- AI and Integrations Tables
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    last_accessed_at timestamp with time zone DEFAULT now() NOT NULL,
    is_starred boolean NOT NULL DEFAULT false
);
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.messages (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role public.message_role NOT NULL,
    content text NOT NULL,
    visualization jsonb,
    component text,
    componentProps jsonb,
    confidence real,
    assumptions text[],
    isError boolean,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.integrations (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform public.integration_platform NOT NULL,
    shop_domain text,
    shop_name text,
    is_active boolean NOT NULL DEFAULT true,
    last_sync_at timestamp with time zone,
    sync_status text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    UNIQUE (company_id, platform)
);
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER handle_updated_at BEFORE UPDATE ON public.integrations FOR EACH ROW EXECUTE FUNCTION moddatetime('updated_at');

CREATE TABLE IF NOT EXISTS public.imports (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    created_by uuid NOT NULL REFERENCES auth.users(id),
    import_type text NOT NULL,
    file_name text NOT NULL,
    status text NOT NULL DEFAULT 'processing',
    total_rows integer,
    processed_rows integer,
    failed_rows integer,
    errors jsonb,
    summary jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_at timestamp with time zone
);
ALTER TABLE public.imports ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.feedback (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users(id),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    subject_id text NOT NULL,
    subject_type text NOT NULL,
    feedback public.feedback_type NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.feedback ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.webhook_events (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    UNIQUE (webhook_id)
);
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.export_jobs (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    requested_by_user_id uuid NOT NULL REFERENCES auth.users(id),
    status text NOT NULL DEFAULT 'queued',
    download_url text,
    expires_at timestamp with time zone,
    error_message text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_at timestamp with time zone
);
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;


-- =============================================================================
-- Row Level Security (RLS) Policies
-- =============================================================================

-- Helper function to get the company ID for the currently authenticated user
CREATE OR REPLACE FUNCTION public.get_company_id_for_user(p_user_id uuid)
RETURNS uuid AS $$
DECLARE
    company_id uuid;
BEGIN
    SELECT c.company_id INTO company_id
    FROM public.company_users c
    WHERE c.user_id = p_user_id
    LIMIT 1;
    RETURN company_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Function to check user permissions
CREATE OR REPLACE FUNCTION public.check_user_permission(p_user_id uuid, p_required_role company_role)
RETURNS boolean AS $$
DECLARE
  user_role company_role;
BEGIN
  SELECT role INTO user_role from public.company_users where user_id = p_user_id;
  IF p_required_role = 'Admin' THEN
    RETURN user_role IN ('Admin', 'Owner');
  ELSIF p_required_role = 'Owner' THEN
    RETURN user_role = 'Owner';
  ELSE
    RETURN TRUE; -- All roles have 'Member' level access
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Policies for all tables
DO $$
DECLARE
    t_name text;
BEGIN
    FOR t_name IN 
        SELECT table_name FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
    LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', t_name);
        EXECUTE format('DROP POLICY IF EXISTS "User can see their own company data" ON public.%I;', t_name);
        EXECUTE format(
            'CREATE POLICY "User can see their own company data" ON public.%I FOR SELECT USING (company_id = public.get_company_id_for_user(auth.uid()));',
            t_name
        );
        EXECUTE format('DROP POLICY IF EXISTS "User can manage their own company data" ON public.%I;', t_name);
        EXECUTE format(
            'CREATE POLICY "User can manage their own company data" ON public.%I FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));',
            t_name
        );
    END LOOP;
END;
$$;

-- Allow users to see their own company and company_user records
DROP POLICY IF EXISTS "Users can see their own company" ON public.companies;
CREATE POLICY "Users can see their own company" ON public.companies FOR SELECT USING (id = public.get_company_id_for_user(auth.uid()));

DROP POLICY IF EXISTS "Users can see their own company_users" ON public.company_users;
CREATE POLICY "Users can see their own company_users" ON public.company_users FOR SELECT USING (company_id = public.get_company_id_for_user(auth.uid()));

-- Owners can manage their company
DROP POLICY IF EXISTS "Owners can manage their company" ON public.companies;
CREATE POLICY "Owners can manage their company" ON public.companies FOR ALL USING (id = public.get_company_id_for_user(auth.uid()) AND owner_id = auth.uid());

-- Admins and Owners can manage company_users
DROP POLICY IF EXISTS "Admins can manage team members" ON public.company_users;
CREATE POLICY "Admins can manage team members" ON public.company_users FOR ALL
USING (company_id = public.get_company_id_for_user(auth.uid()))
WITH CHECK (public.check_user_permission(auth.uid(), 'Admin'));


-- =============================================================================
-- Auth Hook: Automatically create company and settings on new user signup
-- =============================================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
    new_company_id uuid;
BEGIN
    -- Create a new company for the user
    INSERT INTO public.companies (name, owner_id)
    VALUES (new.raw_user_meta_data->>'company_name', new.id)
    RETURNING id INTO new_company_id;

    -- Link the user to the new company as Owner
    INSERT INTO public.company_users (company_id, user_id, role)
    VALUES (new_company_id, new.id, 'Owner');

    -- Create default settings for the new company
    INSERT INTO public.company_settings (company_id)
    VALUES (new_company_id);

    -- Update the user's app_metadata with the new company_id
    UPDATE auth.users
    SET app_metadata = app_metadata || jsonb_build_object('company_id', new_company_id)
    WHERE id = new.id;

    RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop the trigger if it already exists to avoid errors on re-run
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Create the trigger to fire after a new user is inserted
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- =============================================================================
-- Views
-- =============================================================================

-- Product Variants with Product Details
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT 
    pv.*,
    p.title as product_title,
    p.status as product_status,
    p.image_url,
    p.product_type
FROM public.product_variants pv
JOIN public.products p ON pv.product_id = p.id;


-- Orders with Customer Details
CREATE OR REPLACE VIEW public.orders_view AS
SELECT 
    o.*,
    c.email as customer_email
FROM public.orders o
LEFT JOIN public.customers c ON o.customer_id = c.id;

-- Customers with Sales Summary
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
FROM public.customers c
LEFT JOIN public.orders o ON c.id = o.customer_id
WHERE c.deleted_at IS NULL
GROUP BY c.id, c.company_id, c.name, c.email, c.created_at;

-- Audit Log with User Email
CREATE OR REPLACE VIEW public.audit_log_view AS
SELECT 
    al.*,
    u.email AS user_email
FROM public.audit_log al
LEFT JOIN auth.users u ON al.user_id = u.id;


-- Feedback with Message Context
CREATE OR REPLACE VIEW public.feedback_view AS
SELECT 
    f.*,
    u.email as user_email,
    um.content as user_message_content,
    am.content as assistant_message_content
FROM public.feedback f
JOIN auth.users u ON f.user_id = u.id
-- Join to get the user's original message if the feedback is on an assistant response
LEFT JOIN public.messages am ON f.subject_id = am.id AND f.subject_type = 'message'
LEFT JOIN public.messages um ON am.conversation_id = um.conversation_id AND um.created_at < am.created_at AND um.role = 'user'
ORDER BY um.created_at DESC
LIMIT 1;

-- Purchase Orders with Supplier Name
CREATE OR REPLACE VIEW public.purchase_orders_view AS
SELECT
    po.*,
    s.name as supplier_name,
    json_agg(json_build_object(
        'id', poli.id,
        'sku', pv.sku,
        'product_name', p.title,
        'quantity', poli.quantity,
        'cost', poli.cost
    )) as line_items
FROM public.purchase_orders po
LEFT JOIN public.suppliers s ON po.supplier_id = s.id
LEFT JOIN public.purchase_order_line_items poli ON po.id = poli.purchase_order_id
LEFT JOIN public.product_variants pv ON poli.variant_id = pv.id
LEFT JOIN public.products p ON pv.product_id = p.id
GROUP BY po.id, s.name;

-- =============================================================================
-- Stored Procedures (RPC)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_dead_stock_report(p_company_id uuid)
RETURNS TABLE (
  sku text,
  product_name text,
  quantity integer,
  total_value numeric,
  last_sale_date timestamptz
)
LANGUAGE sql STABLE
AS $$
WITH settings AS (
  SELECT COALESCE(dead_stock_days, 90) as days
  FROM public.company_settings
  WHERE company_id = p_company_id
),
last_sales AS (
  SELECT
    li.variant_id,
    max(o.created_at) as last_sale
  FROM public.order_line_items li
  JOIN public.orders o ON li.order_id = o.id
  WHERE li.company_id = p_company_id
  GROUP BY li.variant_id
)
SELECT
  pv.sku,
  p.title as product_name,
  pv.inventory_quantity as quantity,
  (pv.inventory_quantity * pv.cost)::numeric as total_value,
  ls.last_sale as last_sale_date
FROM public.product_variants pv
JOIN public.products p ON pv.product_id = p.id
LEFT JOIN last_sales ls ON pv.id = ls.variant_id
CROSS JOIN settings
WHERE pv.company_id = p_company_id
  AND pv.inventory_quantity > 0
  AND (ls.last_sale IS NULL OR ls.last_sale < (now() - (settings.days || ' days')::interval));
$$;

GRANT EXECUTE ON FUNCTION public.get_dead_stock_report(uuid) TO authenticated;
-- Add the new function here
CREATE OR REPLACE FUNCTION public.get_dead_stock_report(p_company_id uuid)
RETURNS TABLE (
  variant_id uuid,
  product_id uuid,
  variant_sku text,
  variant_title text,
  product_title text,
  inventory_quantity int,
  cost bigint,
  value bigint,
  last_sale_at timestamptz
)
LANGUAGE sql
STABLE
AS $$
WITH variant_last_sale AS (
  SELECT li.variant_id, MAX(o.created_at) AS last_sale_at
  FROM public.order_line_items li
  JOIN public.orders o ON o.id = li.order_id
  WHERE o.company_id = p_company_id AND o.fulfillment_status != 'cancelled'
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
  v.title,
  p.title AS product_title,
  v.inventory_quantity,
  v.cost::bigint,
  (v.inventory_quantity::bigint * v.cost::bigint) AS value,
  ls.last_sale_at
FROM public.product_variants v
LEFT JOIN variant_last_sale ls ON ls.variant_id = v.id
LEFT JOIN public.products p ON p.id = v.product_id
CROSS JOIN settings s
WHERE v.company_id = p_company_id
  AND v.inventory_quantity > 0
  AND (ls.last_sale_at IS NULL OR ls.last_sale_at < (now() - make_interval(days => s.days)));
$$;
