
-- ### CORE EXTENSIONS ###
-- These extensions provide functions for UUID generation and other core features.
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "vector";

-- ### INITIAL TABLE CREATION ###
-- Create all tables with their basic columns. Foreign keys and complex constraints will be added later.
-- This section is safe to run on an existing database as it uses `IF NOT EXISTS`.

CREATE TABLE IF NOT EXISTS public.companies (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.users (
    id uuid PRIMARY KEY,
    company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE,
    email text,
    role text DEFAULT 'member'::text,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days int NOT NULL DEFAULT 90,
    fast_moving_days int NOT NULL DEFAULT 30,
    predictive_stock_days int NOT NULL DEFAULT 7,
    currency text DEFAULT 'USD',
    timezone text DEFAULT 'UTC',
    tax_rate numeric DEFAULT 0,
    custom_rules jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    subscription_status text DEFAULT 'trial',
    subscription_plan text DEFAULT 'starter',
    subscription_expires_at timestamptz,
    stripe_customer_id text,
    stripe_subscription_id text,
    promo_sales_lift_multiplier real NOT NULL DEFAULT 2.5,
    overstock_multiplier integer NOT NULL DEFAULT 3,
    high_value_threshold integer NOT NULL DEFAULT 1000
);

CREATE TABLE IF NOT EXISTS public.products (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
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

CREATE TABLE IF NOT EXISTS public.product_variants (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id uuid NOT NULL,
    company_id uuid NOT NULL,
    sku text,
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
    inventory_quantity integer NOT NULL DEFAULT 0,
    external_variant_id text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    location text
);

CREATE TABLE IF NOT EXISTS public.orders (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    order_number text NOT NULL,
    external_order_id text,
    customer_id uuid,
    status text NOT NULL DEFAULT 'pending',
    financial_status text DEFAULT 'pending',
    fulfillment_status text DEFAULT 'unfulfilled',
    currency text DEFAULT 'USD',
    subtotal integer NOT NULL DEFAULT 0,
    total_tax integer DEFAULT 0,
    total_shipping integer DEFAULT 0,
    total_discounts integer DEFAULT 0,
    total_amount integer NOT NULL,
    source_platform text,
    source_name text,
    tags text[],
    notes text,
    cancelled_at timestamptz,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id uuid NOT NULL,
    product_id uuid,
    variant_id uuid,
    company_id uuid NOT NULL,
    product_name text NOT NULL,
    variant_title text,
    sku text,
    quantity integer NOT NULL,
    price integer NOT NULL,
    total_discount integer DEFAULT 0,
    tax_amount integer DEFAULT 0,
    cost_at_time integer,
    fulfillment_status text DEFAULT 'unfulfilled',
    requires_shipping boolean DEFAULT true,
    external_line_item_id text
);

CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    variant_id uuid NOT NULL,
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    supplier_id uuid,
    status text NOT NULL DEFAULT 'Draft',
    po_number text NOT NULL,
    total_cost integer NOT NULL,
    expected_arrival_date date,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    purchase_order_id uuid NOT NULL,
    variant_id uuid NOT NULL,
    quantity integer NOT NULL,
    cost integer NOT NULL
);

CREATE TABLE IF NOT EXISTS public.customers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    customer_name text NOT NULL,
    email text,
    total_orders integer DEFAULT 0,
    total_spent integer DEFAULT 0,
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.integrations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    platform text NOT NULL,
    shop_domain text,
    shop_name text,
    is_active boolean DEFAULT false,
    last_sync_at timestamptz,
    sync_status text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.audit_log (
    id bigserial PRIMARY KEY,
    company_id uuid,
    user_id uuid,
    action text NOT NULL,
    details jsonb,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.webhook_events (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id text NOT NULL,
    processed_at timestamptz DEFAULT now(),
    created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL,
    company_id uuid NOT NULL,
    title text NOT NULL,
    created_at timestamptz DEFAULT now(),
    last_accessed_at timestamptz DEFAULT now(),
    is_starred boolean DEFAULT false
);

CREATE TABLE IF NOT EXISTS public.messages (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL,
    role text NOT NULL,
    content text,
    component text,
    component_props jsonb,
    visualization jsonb,
    confidence numeric,
    assumptions text[],
    created_at timestamptz DEFAULT now(),
    is_error boolean DEFAULT false
);

-- ### DEPENDENT OBJECT CLEANUP ###
-- Drop all views and policies that might depend on table structures we are about to change.
-- This prevents "cannot alter type of a column used by a view" errors.

DROP MATERIALIZED VIEW IF EXISTS public.company_dashboard_metrics;
DROP VIEW IF EXISTS public.product_variants_with_details;

-- Drop all RLS policies before altering tables
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT DISTINCT tablename FROM pg_policies WHERE schemaname = 'public') LOOP
        EXECUTE 'ALTER TABLE public.' || quote_ident(r.tablename) || ' DISABLE ROW LEVEL SECURITY';
        EXECUTE 'DROP POLICY IF EXISTS "Allow company members to read" ON public.' || quote_ident(r.tablename);
        EXECUTE 'DROP POLICY IF EXISTS "Allow company members to manage" ON public.' || quote_ident(r.tablename);
        EXECUTE 'DROP POLICY IF EXISTS "Allow admins to read audit logs for their company" ON public.' || quote_ident(r.tablename);
        EXECUTE 'DROP POLICY IF EXISTS "Allow user to manage messages in their conversations" ON public.' || quote_ident(r.tablename);
        EXECUTE 'DROP POLICY IF EXISTS "Users can only access their own company data" ON public.' || quote_ident(r.tablename);
    END LOOP;
END $$;

-- Drop the old insecure function
DROP FUNCTION IF EXISTS get_my_company_id();


-- ### TABLE ALTERATIONS ###
-- Add columns, change types, and add constraints. This section is idempotent.

-- Add company_id to tables that were missing it
ALTER TABLE public.order_line_items ADD COLUMN IF NOT EXISTS company_id uuid;
ALTER TABLE public.product_variants ADD COLUMN IF NOT EXISTS company_id uuid;
ALTER TABLE public.inventory_ledger ADD COLUMN IF NOT EXISTS company_id uuid;

-- Add user_id to audit log
ALTER TABLE public.audit_log ADD COLUMN IF NOT EXISTS user_id uuid;
ALTER TABLE public.audit_log ADD COLUMN IF NOT EXISTS company_id uuid;

-- Add idempotency key to purchase orders
ALTER TABLE public.purchase_orders ADD COLUMN IF NOT EXISTS idempotency_key text;

-- Add fts_document for full-text search on products
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS fts_document tsvector;

-- Standardize all monetary values to INTEGER (cents)
ALTER TABLE public.product_variants ALTER COLUMN cost TYPE integer;
ALTER TABLE public.company_settings ALTER COLUMN high_value_threshold TYPE integer;
ALTER TABLE public.customers ALTER COLUMN total_spent TYPE integer;
ALTER TABLE public.orders ALTER COLUMN subtotal TYPE integer;
ALTER TABLE public.orders ALTER COLUMN total_tax TYPE integer;
ALTER TABLE public.orders ALTER COLUMN total_shipping TYPE integer;
ALTER TABLE public.orders ALTER COLUMN total_discounts TYPE integer;
ALTER TABLE public.orders ALTER COLUMN total_amount TYPE integer;
ALTER TABLE public.order_line_items ALTER COLUMN price TYPE integer;
ALTER TABLE public.order_line_items ALTER COLUMN total_discount TYPE integer;
ALTER TABLE public.order_line_items ALTER COLUMN tax_amount TYPE integer;
ALTER TABLE public.order_line_items ALTER COLUMN cost_at_time TYPE integer;
ALTER TABLE public.purchase_orders ALTER COLUMN total_cost TYPE integer;
ALTER TABLE public.purchase_order_line_items ALTER COLUMN cost TYPE integer;

-- Add NOT NULL constraints
ALTER TABLE public.product_variants ALTER COLUMN sku SET NOT NULL;
ALTER TABLE public.product_variants ALTER COLUMN inventory_quantity SET NOT NULL;
ALTER TABLE public.products ALTER COLUMN company_id SET NOT NULL;
ALTER TABLE public.product_variants ALTER COLUMN company_id SET NOT NULL;
ALTER TABLE public.product_variants ALTER COLUMN product_id SET NOT NULL;
ALTER TABLE public.orders ALTER COLUMN company_id SET NOT NULL;
ALTER TABLE public.order_line_items ALTER COLUMN company_id SET NOT NULL;
ALTER TABLE public.order_line_items ALTER COLUMN order_id SET NOT NULL;
ALTER TABLE public.inventory_ledger ALTER COLUMN company_id SET NOT NULL;
ALTER TABLE public.inventory_ledger ALTER COLUMN variant_id SET NOT NULL;

-- Add UNIQUE constraints
ALTER TABLE public.products ADD CONSTRAINT products_company_id_external_product_id_key UNIQUE (company_id, external_product_id);
ALTER TABLE public.product_variants ADD CONSTRAINT product_variants_company_id_external_variant_id_key UNIQUE (company_id, external_variant_id);
ALTER TABLE public.webhook_events ADD CONSTRAINT webhook_events_integration_id_webhook_id_key UNIQUE (integration_id, webhook_id);

-- ### INDEXING ###
-- Create indexes for performance on frequently queried columns.

CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products (company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_company_id ON public.product_variants (company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_sku_company ON public.product_variants (sku, company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants (product_id);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders (company_id);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON public.orders (customer_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_company_id ON public.order_line_items (company_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items (order_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON public.order_line_items (variant_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_company_id ON public.inventory_ledger (company_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id ON public.inventory_ledger (variant_id);
CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON public.suppliers (company_id);
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers (company_id);
CREATE INDEX IF NOT EXISTS idx_customers_email ON public.customers (email);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_company_id ON public.purchase_orders (company_id);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_supplier_id ON public.purchase_orders (supplier_id);
CREATE INDEX IF NOT EXISTS idx_purchase_order_line_items_purchase_order_id ON public.purchase_order_line_items (purchase_order_id);
CREATE INDEX IF NOT EXISTS idx_purchase_order_line_items_variant_id ON public.purchase_order_line_items (variant_id);
CREATE INDEX IF NOT EXISTS idx_products_fts_document ON public.products USING GIN (fts_document);
CREATE UNIQUE INDEX IF NOT EXISTS po_company_idempotency_idx ON public.purchase_orders (company_id, idempotency_key) WHERE idempotency_key IS NOT NULL;


-- ### HELPER FUNCTIONS & TRIGGERS ###

-- Function to get the company_id for the currently authenticated user
CREATE OR REPLACE FUNCTION get_user_company_id()
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN (SELECT raw_app_meta_data->>'company_id' FROM auth.users WHERE id = auth.uid())::uuid;
END;
$$;

-- Trigger to associate a new auth.user with a company and create a public.user record
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_company_id uuid;
    v_company_name text := new.raw_app_meta_data->>'company_name';
BEGIN
    -- Check if a company_id is provided in metadata (e.g., from an invite)
    IF new.raw_app_meta_data->>'company_id' IS NOT NULL THEN
        v_company_id := (new.raw_app_meta_data->>'company_id')::uuid;
    ELSE
        -- If no company_id, create a new company for the user
        INSERT INTO public.companies (name)
        VALUES (v_company_name)
        RETURNING id INTO v_company_id;
    END IF;

    -- Insert into public.users table
    INSERT INTO public.users (id, company_id, email, role)
    VALUES (new.id, v_company_id, new.email, 'Owner');

    -- Update the user's app_metadata with the company_id
    UPDATE auth.users
    SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', v_company_id)
    WHERE id = new.id;
    
    RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_user();


-- ### VIEWS & MATERIALIZED VIEWS ###

-- A view to simplify querying product variants with their parent product details.
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT 
    pv.*,
    p.title AS product_title,
    p.status AS product_status,
    p.image_url
FROM 
    public.product_variants pv
JOIN 
    public.products p ON pv.product_id = p.id;

-- A materialized view for faster dashboard metric calculations.
CREATE MATERIALIZED VIEW IF NOT EXISTS public.company_dashboard_metrics AS
SELECT
    c.id AS company_id,
    oli.sku,
    o.created_at,
    oli.quantity,
    oli.price,
    oli.cost_at_time
FROM
    public.companies c
JOIN
    public.orders o ON c.id = o.company_id
JOIN
    public.order_line_items oli ON o.id = oli.order_id
WHERE o.status = 'completed';

CREATE UNIQUE INDEX IF NOT EXISTS idx_company_dashboard_metrics_company_id_sku_created_at ON public.company_dashboard_metrics (company_id, sku, created_at);


-- ### ROW-LEVEL SECURITY (RLS) ###
-- Enable RLS and apply policies to all relevant tables.

-- Generic policy for most tables
DO $$
DECLARE
    t_name TEXT;
BEGIN
    FOR t_name IN 
        SELECT table_name FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name IN (
            'products', 'product_variants', 'orders', 'order_line_items', 
            'inventory_ledger', 'suppliers', 'purchase_orders', 'purchase_order_line_items', 
            'customers', 'integrations', 'company_settings', 'conversations'
        )
    LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t_name);
        EXECUTE format('DROP POLICY IF EXISTS "Allow company members to manage" ON public.%I', t_name);
        EXECUTE format('CREATE POLICY "Allow company members to manage" ON public.%I FOR ALL USING (company_id = get_user_company_id()) WITH CHECK (company_id = get_user_company_id())', t_name);
    END LOOP;
END $$;

-- Special policy for the audit_log table (read-only for admins)
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow admins to read audit logs for their company"
ON public.audit_log FOR SELECT
USING (company_id = get_user_company_id() AND (SELECT role FROM public.users WHERE id = auth.uid()) = 'Admin');

-- Special policy for messages (users can only see their own)
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow user to manage messages in their conversations"
ON public.messages FOR ALL
USING (EXISTS (
    SELECT 1 FROM conversations 
    WHERE conversations.id = messages.conversation_id AND conversations.user_id = auth.uid()
));

-- Policy for companies table (users can only see their own company)
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only see their own company"
ON public.companies FOR SELECT
USING (id = get_user_company_id());

-- Policy for users table (users can see other users in their own company)
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can see other members of their company"
ON public.users FOR SELECT
USING (company_id = get_user_company_id());


-- Set the search path for the supabase_auth_admin role to ensure functions are found
ALTER ROLE supabase_auth_admin SET search_path = extensions,auth,public;
