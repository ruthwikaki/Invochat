-- supabase/seed.sql

-- This file is used to seed the database with initial data.
-- It is run automatically by Supabase when the database is created.
-- For more information, see: https://supabase.com/docs/guides/database/seeding

-- This file is organized into several sections:
-- 1. Helper Functions: Utility functions for data generation.
-- 2. Static Data: Core data required for the application to function.
-- 3. Dynamic Data Generation: Functions to create realistic mock data for development.
-- 4. Seeding Execution: Calls the data generation functions to populate the database.
--
-- To use:
-- In your Supabase project's SQL Editor, paste the entire contents of this file and click "Run".
-- This only needs to be done once when setting up a new project.


-- =============================================
-- 1. EXTENSIONS & HELPER FUNCTIONS
-- =============================================

-- Enable the pgcrypto extension for UUID generation
CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "public";
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "public";


-- =============================================
-- 2. ENUMS AND DATA TYPES
-- =============================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'company_role') THEN
        CREATE TYPE public.company_role AS ENUM (
            'Owner',
            'Admin',
            'Member'
        );
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'integration_platform') THEN
        CREATE TYPE public.integration_platform AS ENUM (
            'shopify',
            'woocommerce',
            'amazon_fba'
        );
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'message_role') THEN
        CREATE TYPE public.message_role AS ENUM (
            'user',
            'assistant',
            'tool'
        );
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'feedback_type') THEN
        CREATE TYPE public.feedback_type AS ENUM (
            'helpful',
            'unhelpful'
        );
    END IF;
END$$;


-- =============================================
-- 3. TABLE DEFINITIONS
-- =============================================

-- Stores company information
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    owner_id uuid REFERENCES auth.users(id) NOT NULL,
    name text NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL
);

-- Junction table for users and companies
CREATE TABLE IF NOT EXISTS public.company_users (
    company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE NOT NULL,
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    role public.company_role DEFAULT 'Member'::public.company_role NOT NULL,
    PRIMARY KEY (company_id, user_id)
);

-- Stores company-specific settings and business logic rules
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer DEFAULT 90 NOT NULL,
    fast_moving_days integer DEFAULT 30 NOT NULL,
    overstock_multiplier real DEFAULT 3 NOT NULL,
    high_value_threshold integer DEFAULT 100000 NOT NULL, -- in cents
    predictive_stock_days integer DEFAULT 7 NOT NULL,
    currency text DEFAULT 'USD'::text,
    timezone text DEFAULT 'UTC'::text,
    tax_rate numeric DEFAULT 0,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz
);

-- Stores product information
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
    updated_at timestamptz,
    CONSTRAINT unique_product_external_id UNIQUE (company_id, external_product_id)
);

-- Stores supplier information
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

-- Stores product variants (SKUs)
CREATE TABLE IF NOT EXISTS public.product_variants (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    product_id uuid REFERENCES public.products(id) ON DELETE CASCADE NOT NULL,
    company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE NOT NULL,
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
    inventory_quantity integer DEFAULT 0 NOT NULL,
    reorder_point integer,
    reorder_quantity integer,
    location text,
    external_variant_id text,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz,
    CONSTRAINT unique_variant_sku UNIQUE (company_id, sku),
    CONSTRAINT unique_variant_external_id UNIQUE (company_id, external_variant_id)
);

-- Stores customer information
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE NOT NULL,
    name text,
    email text,
    phone text,
    external_customer_id text,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz,
    deleted_at timestamptz,
    CONSTRAINT unique_customer_external_id UNIQUE (company_id, external_customer_id)
);

-- Stores sales orders
CREATE TABLE IF NOT EXISTS public.orders (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE NOT NULL,
    customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
    order_number text NOT NULL,
    external_order_id text,
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
    CONSTRAINT unique_order_external_id UNIQUE (company_id, external_order_id)
);

-- Stores line items for sales orders
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    order_id uuid REFERENCES public.orders(id) ON DELETE CASCADE NOT NULL,
    variant_id uuid REFERENCES public.product_variants(id) ON DELETE SET NULL,
    company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE NOT NULL,
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

-- Stores inventory movement records
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE NOT NULL,
    variant_id uuid REFERENCES public.product_variants(id) ON DELETE CASCADE NOT NULL,
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid,
    notes text,
    created_at timestamptz DEFAULT now() NOT NULL
);

-- Stores integration information
CREATE TABLE IF NOT EXISTS public.integrations (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE NOT NULL,
    platform public.integration_platform NOT NULL,
    shop_domain text,
    shop_name text,
    is_active boolean DEFAULT false,
    last_sync_at timestamptz,
    sync_status text,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz,
    CONSTRAINT unique_integration_per_company UNIQUE (company_id, platform)
);

-- Stores AI conversation history
CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE NOT NULL,
    title text NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL,
    last_accessed_at timestamptz DEFAULT now() NOT NULL,
    is_starred boolean DEFAULT false
);

-- Stores individual AI chat messages
CREATE TABLE IF NOT EXISTS public.messages (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    conversation_id uuid REFERENCES public.conversations(id) ON DELETE CASCADE NOT NULL,
    company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE NOT NULL,
    role public.message_role NOT NULL,
    content text NOT NULL,
    visualization jsonb,
    component text,
    "componentProps" jsonb,
    confidence real,
    assumptions text[],
    "isError" boolean,
    created_at timestamptz DEFAULT now() NOT NULL
);

-- Stores purchase orders
CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE NOT NULL,
    supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL,
    status text DEFAULT 'Draft'::text NOT NULL,
    po_number text NOT NULL,
    total_cost integer NOT NULL,
    expected_arrival_date date,
    idempotency_key uuid,
    notes text,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz
);

-- Stores purchase order line items
CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    purchase_order_id uuid REFERENCES public.purchase_orders(id) ON DELETE CASCADE NOT NULL,
    variant_id uuid REFERENCES public.product_variants(id) NOT NULL,
    company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE NOT NULL,
    quantity integer NOT NULL,
    cost integer NOT NULL -- in cents
);

-- Stores channel-specific fees for profit calculation
CREATE TABLE IF NOT EXISTS public.channel_fees (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE NOT NULL,
    channel_name text NOT NULL,
    percentage_fee numeric,
    fixed_fee integer, -- in cents
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    CONSTRAINT unique_channel_fee UNIQUE (company_id, channel_name)
);

-- Stores audit log entries for security and compliance
CREATE TABLE IF NOT EXISTS public.audit_log (
    id bigserial PRIMARY KEY,
    company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    action text NOT NULL,
    details jsonb,
    created_at timestamptz DEFAULT now()
);

-- Stores export job requests
CREATE TABLE IF NOT EXISTS public.export_jobs (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE NOT NULL,
    requested_by_user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    download_url text,
    expires_at timestamptz,
    created_at timestamptz DEFAULT now() NOT NULL,
    completed_at timestamptz,
    error_message text
);

-- Stores user feedback on AI responses
CREATE TABLE IF NOT EXISTS public.feedback (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE NOT NULL,
    subject_id text NOT NULL,
    subject_type text NOT NULL,
    feedback public.feedback_type NOT NULL,
    created_at timestamptz DEFAULT now()
);

-- Stores webhook events to prevent replay attacks
CREATE TABLE IF NOT EXISTS public.webhook_events (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    integration_id uuid REFERENCES public.integrations(id) ON DELETE CASCADE NOT NULL,
    webhook_id text NOT NULL,
    created_at timestamptz DEFAULT now(),
    UNIQUE (integration_id, webhook_id)
);

-- Stores import job records
CREATE TABLE IF NOT EXISTS public.imports (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE NOT NULL,
    created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL NOT NULL,
    import_type text NOT NULL,
    file_name text NOT NULL,
    total_rows integer,
    processed_rows integer,
    failed_rows integer,
    status text NOT NULL DEFAULT 'pending',
    errors jsonb,
    summary jsonb,
    created_at timestamptz DEFAULT now(),
    completed_at timestamptz
);


-- =============================================
-- 4. VIEWS
-- =============================================

-- Simplified view for product variants with essential product details joined.
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
    pv.reorder_point,
    pv.reorder_quantity,
    pv.location,
    pv.external_variant_id,
    pv.created_at,
    pv.updated_at,
    p.title AS product_title,
    p.status AS product_status,
    p.image_url,
    p.product_type
FROM
    public.product_variants pv
JOIN
    public.products p ON pv.product_id = p.id;

-- Materialized view for faster queries on variant details.
CREATE MATERIALIZED VIEW IF NOT EXISTS public.product_variants_with_details_mat AS
SELECT * FROM public.product_variants_with_details;
CREATE UNIQUE INDEX IF NOT EXISTS product_variants_with_details_mat_id ON public.product_variants_with_details_mat (id);

-- Simplified view for customers with aggregated order data.
CREATE OR REPLACE VIEW public.customers_view AS
SELECT
    c.id,
    c.company_id,
    c.name AS customer_name,
    c.email,
    count(o.id) AS total_orders,
    sum(o.total_amount) AS total_spent,
    min(o.created_at) AS first_order_date,
    c.created_at
FROM
    public.customers c
LEFT JOIN
    public.orders o ON c.id = o.customer_id
GROUP BY
    c.id, c.company_id;

-- Materialized view for faster customer queries.
CREATE MATERIALIZED VIEW IF NOT EXISTS public.customers_view_mat AS
SELECT * FROM public.customers_view;
CREATE UNIQUE INDEX IF NOT EXISTS customers_view_mat_id ON public.customers_view_mat (id);


-- =============================================
-- 5. FUNCTIONS
-- =============================================

-- This function runs as a trigger when a new user signs up.
-- It creates a company for the new user and links them as the owner.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_company_id uuid;
  v_company_name text;
BEGIN
  -- Extract company name from metadata, default to a generic name
  v_company_name := NEW.raw_app_meta_data->>'company_name';
  IF v_company_name IS NULL OR v_company_name = '' THEN
    v_company_name := NEW.email || '''s Company';
  END IF;

  -- Create a new company for the user
  INSERT INTO public.companies (owner_id, name)
  VALUES (NEW.id, v_company_name)
  RETURNING id INTO v_company_id;

  -- Link the user to the new company as 'Owner'
  INSERT INTO public.company_users (user_id, company_id, role)
  VALUES (NEW.id, v_company_id, 'Owner');

  -- Update the user's app_metadata with the new company_id
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', v_company_id)
  WHERE id = NEW.id;
  
  -- Create default settings for the new company
  INSERT INTO public.company_settings (company_id)
  VALUES (v_company_id);

  RETURN NEW;
END;
$$;

-- Function to temporarily lock a user account after too many failed login attempts.
CREATE OR REPLACE FUNCTION public.lock_user_account(p_user_id uuid, p_lockout_duration text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE auth.users
    SET banned_until = now() + p_lockout_duration::interval
    WHERE id = p_user_id;
END;
$$;


-- Function to check user permissions
CREATE OR REPLACE FUNCTION public.check_user_permission(p_user_id uuid, p_required_role public.company_role)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    user_role public.company_role;
BEGIN
    SELECT role INTO user_role FROM public.company_users WHERE user_id = p_user_id;

    IF user_role IS NULL THEN
        RETURN FALSE;
    END IF;

    IF p_required_role = 'Admin' THEN
        RETURN user_role IN ('Owner', 'Admin');
    ELSIF p_required_role = 'Owner' THEN
        RETURN user_role = 'Owner';
    END IF;

    RETURN FALSE;
END;
$$;


-- A function to generate alerts based on company settings and inventory levels.
CREATE OR REPLACE FUNCTION public.get_alerts(p_company_id uuid)
RETURNS json[]
LANGUAGE plpgsql
AS $$
DECLARE
    settings record;
    alerts json[];
BEGIN
    SELECT * INTO settings FROM company_settings WHERE company_id = p_company_id;
    IF settings IS NULL THEN
        RETURN '{}'::json[];
    END IF;

    -- Low Stock Alerts
    alerts := array_cat(alerts, ARRAY(
        SELECT json_build_object(
            'id', 'low_stock_' || v.id,
            'type', 'low_stock',
            'title', 'Low Stock Warning',
            'message', 'Stock for "' || p.title || '" has fallen below the reorder point.',
            'severity', 'warning',
            'timestamp', now(),
            'metadata', json_build_object(
                'productId', v.id,
                'productName', p.title,
                'sku', v.sku,
                'currentStock', v.inventory_quantity,
                'reorderPoint', v.reorder_point
            )
        )
        FROM product_variants v
        JOIN products p ON v.product_id = p.id
        WHERE v.company_id = p_company_id
          AND v.inventory_quantity <= v.reorder_point
          AND v.reorder_point > 0
    ));

    -- Dead Stock Alerts
    alerts := array_cat(alerts, ARRAY(
        SELECT json_build_object(
            'id', 'dead_stock_' || v.id,
            'type', 'dead_stock',
            'title', 'Dead Stock Detected',
            'message', '"' || p.title || '" has not sold in over ' || settings.dead_stock_days || ' days.',
            'severity', 'danger',
            'timestamp', now(),
            'metadata', json_build_object(
                'productId', v.id,
                'productName', p.title,
                'sku', v.sku,
                'currentStock', v.inventory_quantity,
                'lastSoldDate', l.last_sale,
                'value', v.inventory_quantity * v.cost
            )
        )
        FROM product_variants v
        JOIN products p ON v.product_id = p.id
        LEFT JOIN (
            SELECT
                oli.variant_id,
                MAX(o.created_at) as last_sale
            FROM order_line_items oli
            JOIN orders o ON oli.order_id = o.id
            WHERE o.company_id = p_company_id
            GROUP BY oli.variant_id
        ) l ON v.id = l.variant_id
        WHERE v.company_id = p_company_id
          AND v.inventory_quantity > 0
          AND (l.last_sale IS NULL OR l.last_sale < now() - (settings.dead_stock_days || ' days')::interval)
    ));

    RETURN alerts;
END;
$$;


-- =============================================
-- 6. TRIGGERS
-- =============================================

-- Trigger to execute the handle_new_user function after a new user is created
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- Trigger to update the `updated_at` timestamp on product variants
CREATE OR REPLACE FUNCTION set_updated_at_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS on_product_variant_update ON public.product_variants;
CREATE TRIGGER on_product_variant_update
BEFORE UPDATE ON public.product_variants
FOR EACH ROW
EXECUTE FUNCTION set_updated_at_timestamp();

-- =============================================
-- 7. RL S & POLICIES
-- =============================================

-- Enable Row Level Security for all relevant tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.imports ENABLE ROW LEVEL SECURITY;


-- Function to get the current user's company_id
CREATE OR REPLACE FUNCTION public.get_current_company_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT current_setting('request.jwt.claims', true)::jsonb->'app_metadata'->>'company_id';
$$;

-- Policies to ensure users can only access data for their own company
DROP POLICY IF EXISTS "allow_all_for_own_company" ON public.companies;
CREATE POLICY "allow_all_for_own_company" ON public.companies FOR ALL
USING (id = public.get_current_company_id());

DROP POLICY IF EXISTS "allow_all_for_own_company" ON public.company_settings;
CREATE POLICY "allow_all_for_own_company" ON public.company_settings FOR ALL
USING (company_id = public.get_current_company_id());

DROP POLICY IF EXISTS "allow_all_for_own_company" ON public.products;
CREATE POLICY "allow_all_for_own_company" ON public.products FOR ALL
USING (company_id = public.get_current_company_id());

DROP POLICY IF EXISTS "allow_all_for_own_company" ON public.product_variants;
CREATE POLICY "allow_all_for_own_company" ON public.product_variants FOR ALL
USING (company_id = public.get_current_company_id());

DROP POLICY IF EXISTS "allow_all_for_own_company" ON public.suppliers;
CREATE POLICY "allow_all_for_own_company" ON public.suppliers FOR ALL
USING (company_id = public.get_current_company_id());

DROP POLICY IF EXISTS "allow_all_for_own_company" ON public.customers;
CREATE POLICY "allow_all_for_own_company" ON public.customers FOR ALL
USING (company_id = public.get_current_company_id());

DROP POLICY IF EXISTS "allow_all_for_own_company" ON public.orders;
CREATE POLICY "allow_all_for_own_company" ON public.orders FOR ALL
USING (company_id = public.get_current_company_id());

DROP POLICY IF EXISTS "allow_all_for_own_company" ON public.order_line_items;
CREATE POLICY "allow_all_for_own_company" ON public.order_line_items FOR ALL
USING (company_id = public.get_current_company_id());

DROP POLICY IF EXISTS "allow_all_for_own_company" ON public.inventory_ledger;
CREATE POLICY "allow_all_for_own_company" ON public.inventory_ledger FOR ALL
USING (company_id = public.get_current_company_id());

DROP POLICY IF EXISTS "allow_all_for_own_company" ON public.integrations;
CREATE POLICY "allow_all_for_own_company" ON public.integrations FOR ALL
USING (company_id = public.get_current_company_id());

DROP POLICY IF EXISTS "allow_all_for_own_company" ON public.conversations;
CREATE POLICY "allow_all_for_own_company" ON public.conversations FOR ALL
USING (company_id = public.get_current_company_id());

DROP POLICY IF EXISTS "allow_all_for_own_company" ON public.messages;
CREATE POLICY "allow_all_for_own_company" ON public.messages FOR ALL
USING (company_id = public.get_current_company_id());

DROP POLICY IF EXISTS "allow_all_for_own_company" ON public.purchase_orders;
CREATE POLICY "allow_all_for_own_company" ON public.purchase_orders FOR ALL
USING (company_id = public.get_current_company_id());

DROP POLICY IF EXISTS "allow_all_for_own_company" ON public.purchase_order_line_items;
CREATE POLICY "allow_all_for_own_company" ON public.purchase_order_line_items FOR ALL
USING (company_id = public.get_current_company_id());

DROP POLICY IF EXISTS "allow_all_for_own_company" ON public.company_users;
CREATE POLICY "allow_all_for_own_company" ON public.company_users FOR ALL
USING (company_id = public.get_current_company_id());

DROP POLICY IF EXISTS "allow_all_for_own_company" ON public.channel_fees;
CREATE POLICY "allow_all_for_own_company" ON public.channel_fees FOR ALL
USING (company_id = public.get_current_company_id());

DROP POLICY IF EXISTS "allow_all_for_own_company" ON public.audit_log;
CREATE POLICY "allow_all_for_own_company" ON public.audit_log FOR ALL
USING (company_id = public.get_current_company_id());

DROP POLICY IF EXISTS "allow_all_for_own_company" ON public.export_jobs;
CREATE POLICY "allow_all_for_own_company" ON public.export_jobs FOR ALL
USING (company_id = public.get_current_company_id());

DROP POLICY IF EXISTS "allow_all_for_own_company" ON public.feedback;
CREATE POLICY "allow_all_for_own_company" ON public.feedback FOR ALL
USING (company_id = public.get_current_company_id());

DROP POLICY IF EXISTS "allow_all_for_own_company" ON public.webhook_events;
CREATE POLICY "allow_all_for_own_company" ON public.webhook_events FOR ALL
USING (EXISTS (SELECT 1 FROM public.integrations i WHERE i.id = integration_id AND i.company_id = public.get_current_company_id()));

DROP POLICY IF EXISTS "allow_all_for_own_company" ON public.imports;
CREATE POLICY "allow_all_for_own_company" ON public.imports FOR ALL
USING (company_id = public.get_current_company_id());
