
-- Enable the UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";

-- Enable the pgcrypto extension for encryption
CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";

-- Set up PostGIS for spatial queries if needed in the future
-- CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA extensions;


-- Create custom types for roles and platforms
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'company_role') THEN
        CREATE TYPE public.company_role AS ENUM ('Owner', 'Admin', 'Member');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'integration_platform') THEN
        CREATE TYPE public.integration_platform AS ENUM ('shopify', 'woocommerce', 'amazon_fba');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'message_role') THEN
        CREATE TYPE public.message_role AS ENUM ('user', 'assistant', 'system', 'tool');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'feedback_type') THEN
        CREATE TYPE public.feedback_type AS ENUM ('helpful', 'unhelpful');
    END IF;
END
$$;

-- Create Companies Table
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    name text NOT NULL,
    owner_id uuid NOT NULL REFERENCES auth.users(id),
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

-- Create Company Users Junction Table
CREATE TABLE IF NOT EXISTS public.company_users (
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role public.company_role DEFAULT 'Member'::public.company_role NOT NULL,
    PRIMARY KEY (company_id, user_id)
);

-- Create Suppliers Table
CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    notes text,
    default_lead_time_days integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);

-- Create Products Table
CREATE TABLE IF NOT EXISTS public.products (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    external_product_id text,
    title text NOT NULL,
    description text,
    handle text,
    product_type text,
    status text,
    tags text[],
    image_url text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    deleted_at timestamp with time zone,
    version integer DEFAULT 1 NOT NULL,
    CONSTRAINT unique_product_external_id UNIQUE(company_id, external_product_id)
);

-- Create Product Variants Table
CREATE TABLE IF NOT EXISTS public.product_variants (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    external_variant_id text,
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
    reserved_quantity integer DEFAULT 0 NOT NULL,
    in_transit_quantity integer DEFAULT 0 NOT NULL,
    location text,
    supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL,
    reorder_point integer,
    reorder_quantity integer,
    lead_time_days integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    deleted_at timestamp with time zone,
    version integer DEFAULT 1 NOT NULL,
    CONSTRAINT unique_variant_external_id UNIQUE (company_id, external_variant_id),
    CONSTRAINT unique_variant_sku UNIQUE (company_id, sku)
);

-- Create Customers Table
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    external_customer_id text,
    name text,
    email text,
    phone text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    deleted_at timestamp with time zone,
    CONSTRAINT unique_customer_external_id UNIQUE(company_id, external_customer_id)
);

-- Create Orders Table
CREATE TABLE IF NOT EXISTS public.orders (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    external_order_id text,
    order_number text NOT NULL,
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
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    CONSTRAINT unique_order_external_id UNIQUE(company_id, external_order_id)
);

-- Create Order Line Items Table
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id uuid REFERENCES public.product_variants(id) ON DELETE SET NULL,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    external_line_item_id text,
    product_name text,
    variant_title text,
    sku text,
    quantity integer NOT NULL,
    price integer NOT NULL, -- in cents
    total_discount integer, -- in cents
    tax_amount integer, -- in cents
    cost_at_time integer -- in cents
);

-- Create Refunds Table
CREATE TABLE IF NOT EXISTS public.refunds (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    external_refund_id text,
    refund_number text NOT NULL,
    status text NOT NULL,
    reason text,
    note text,
    total_amount integer NOT NULL,
    created_by_user_id uuid REFERENCES auth.users(id),
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

-- Create Purchase Orders Table
CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.suppliers(id),
    po_number text NOT NULL,
    status text NOT NULL DEFAULT 'Draft',
    total_cost integer NOT NULL,
    expected_arrival_date date,
    idempotency_key uuid,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);

-- Create Purchase Order Line Items Table
CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    purchase_order_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    quantity integer NOT NULL,
    cost integer NOT NULL -- in cents
);

-- Create Integrations Table
CREATE TABLE IF NOT EXISTS public.integrations (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform public.integration_platform NOT NULL,
    shop_domain text,
    shop_name text,
    is_active boolean DEFAULT true,
    last_sync_at timestamp with time zone,
    sync_status text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    CONSTRAINT unique_company_platform UNIQUE (company_id, platform)
);

-- Create Inventory Ledger Table
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id),
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    change_type text NOT NULL, -- e.g., 'sale', 'purchase_order', 'manual_adjustment', 'reconciliation'
    related_id uuid, -- e.g., order_id, po_id
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

-- Create Conversations Table
CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    last_accessed_at timestamp with time zone DEFAULT now() NOT NULL,
    is_starred boolean DEFAULT false NOT NULL
);

-- Create Messages Table
CREATE TABLE IF NOT EXISTS public.messages (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role public.message_role NOT NULL,
    content text NOT NULL,
    visualization jsonb,
    component text,
    component_props jsonb,
    confidence double precision,
    assumptions text[],
    is_error boolean,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

-- Create Company Settings Table
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer DEFAULT 90 NOT NULL,
    fast_moving_days integer DEFAULT 30 NOT NULL,
    predictive_stock_days integer DEFAULT 7 NOT NULL,
    currency text DEFAULT 'USD' NOT NULL,
    timezone text DEFAULT 'UTC' NOT NULL,
    tax_rate numeric(5,4) DEFAULT 0.00 NOT NULL,
    overstock_multiplier integer DEFAULT 3 NOT NULL,
    high_value_threshold integer DEFAULT 100000 NOT NULL, -- in cents
    alert_settings jsonb,
    email_notifications boolean DEFAULT true NOT NULL,
    morning_briefing_enabled boolean DEFAULT true NOT NULL,
    morning_briefing_time time without time zone DEFAULT '08:00:00' NOT NULL,
    low_stock_threshold integer DEFAULT 10 NOT NULL,
    critical_stock_threshold integer DEFAULT 3 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);

-- Create Channel Fees Table
CREATE TABLE IF NOT EXISTS public.channel_fees (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    channel_name text NOT NULL,
    percentage_fee numeric(5,2),
    fixed_fee integer, -- in cents
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    CONSTRAINT unique_company_channel UNIQUE (company_id, channel_name)
);

-- Create Export Jobs Table
CREATE TABLE IF NOT EXISTS public.export_jobs (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    requested_by_user_id uuid NOT NULL REFERENCES auth.users(id),
    status text NOT NULL DEFAULT 'pending', -- pending, processing, completed, failed
    download_url text,
    expires_at timestamp with time zone,
    error_message text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_at timestamp with time zone
);

-- Create Audit Log Table
CREATE TABLE IF NOT EXISTS public.audit_log (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id uuid REFERENCES auth.users(id),
    action text NOT NULL,
    details jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

-- Create Alert History Table (for read/dismiss status)
CREATE TABLE IF NOT EXISTS public.alert_history (
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    alert_id text NOT NULL, -- Not a FK, corresponds to a dynamically generated alert
    status text NOT NULL, -- 'read' or 'dismissed'
    read_at timestamp with time zone,
    dismissed_at timestamp with time zone,
    PRIMARY KEY (company_id, alert_id)
);


-- Create Feedback Table
CREATE TABLE IF NOT EXISTS public.feedback (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    subject_id text NOT NULL, -- ID of the thing being rated (e.g., message_id)
    subject_type text NOT NULL, -- e.g., 'message', 'report'
    feedback public.feedback_type NOT NULL, -- 'helpful' or 'unhelpful'
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

-- Create a table to track webhook events and prevent replay attacks
CREATE TABLE IF NOT EXISTS public.webhook_events (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    UNIQUE (integration_id, webhook_id)
);

-- Set up Row Level Security (RLS) policies
-- Enable RLS for all relevant tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.alert_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.feedback ENABLE ROW LEVEL SECURITY;

-- Helper function to get the company_id for the current user
CREATE OR REPLACE FUNCTION public.get_company_id_for_user(p_user_id uuid)
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT company_id FROM public.company_users WHERE user_id = p_user_id LIMIT 1;
$$;

-- Generic RLS policy for tables with a company_id column
CREATE OR REPLACE FUNCTION public.create_company_rls_policy(table_name text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    EXECUTE format('
        DROP POLICY IF EXISTS "Enable access for company members" ON public.%I;
        CREATE POLICY "Enable access for company members"
        ON public.%I
        FOR ALL
        TO authenticated
        USING (company_id = public.get_company_id_for_user(auth.uid()))
        WITH CHECK (company_id = public.get_company_id_for_user(auth.uid()));
    ', table_name, table_name);
END;
$$;

-- Apply the generic RLS policy to all company-scoped tables
SELECT public.create_company_rls_policy(table_name)
FROM information_schema.tables
WHERE table_schema = 'public' AND table_name IN (
    'suppliers', 'products', 'product_variants', 'customers', 'orders', 'order_line_items',
    'purchase_orders', 'purchase_order_line_items', 'integrations', 'inventory_ledger',
    'conversations', 'messages', 'company_settings', 'channel_fees', 'export_jobs',
    'audit_log', 'alert_history', 'feedback'
);

-- RLS for companies table (users can see their own company)
DROP POLICY IF EXISTS "Users can see their own company" ON public.companies;
CREATE POLICY "Users can see their own company"
ON public.companies
FOR SELECT
TO authenticated
USING (id = public.get_company_id_for_user(auth.uid()));

-- RLS for company_users table (users can see their own membership)
DROP POLICY IF EXISTS "Users can see their own company membership" ON public.company_users;
CREATE POLICY "Users can see their own company membership"
ON public.company_users
FOR SELECT
TO authenticated
USING (user_id = auth.uid());


-- Create a function to be called by a trigger on new user signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  new_company_id uuid;
  company_name text;
BEGIN
    -- Extract company name from user metadata, default if not present
    company_name := new.raw_user_meta_data->>'company_name';
    IF company_name IS NULL OR company_name = '' THEN
        company_name := new.email;
    END IF;

    -- Create a new company for the new user
    INSERT INTO public.companies (name, owner_id)
    VALUES (company_name, new.id)
    RETURNING id INTO new_company_id;

    -- Link the user to the new company as an Owner
    INSERT INTO public.company_users (company_id, user_id, role)
    VALUES (new_company_id, new.id, 'Owner');

    -- Create default settings for the new company
    INSERT INTO public.company_settings (company_id)
    VALUES (new_company_id);

    -- Update the user's app_metadata with the new company_id
    -- This makes it available in the JWT for RLS policies
    UPDATE auth.users
    SET app_metadata = app_metadata || jsonb_build_object('company_id', new_company_id)
    WHERE id = new.id;
    
    RETURN new;
END;
$$;

-- Create the trigger on the auth.users table
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- Create a view for product variants that includes product details
-- This simplifies many common queries.
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT 
    pv.id,
    pv.product_id,
    pv.company_id,
    pv.sku,
    pv.title,
    p.title AS product_title,
    p.status AS product_status,
    p.image_url,
    p.product_type,
    pv.price,
    pv.compare_at_price,
    pv.cost,
    pv.inventory_quantity,
    pv.location,
    pv.barcode,
    pv.external_variant_id,
    pv.supplier_id,
    pv.reorder_point,
    pv.reorder_quantity,
    pv.option1_name,
    pv.option1_value,
    pv.option2_name,
    pv.option2_value,
    pv.option3_name,
    pv.option3_value,
    pv.created_at,
    pv.updated_at,
    (p.title || ' ' || COALESCE(pv.title, '') || ' ' || pv.sku) AS fts
FROM 
    public.product_variants pv
JOIN 
    public.products p ON pv.product_id = p.id;

-- Fix missing get_dead_stock_report function
-- This function is referenced by get_dashboard_metrics but was never defined.

-- Create the missing get_dead_stock_report function
CREATE OR REPLACE FUNCTION public.get_dead_stock_report(p_company_id uuid)
RETURNS TABLE (
    sku text,
    product_name text,
    quantity integer,
    total_value numeric,
    last_sale_date timestamp with time zone
)
LANGUAGE sql
STABLE
AS $$
    WITH company_settings AS (
        SELECT dead_stock_days
        FROM public.company_settings 
        WHERE company_id = p_company_id
    ),
    dead_stock_cutoff AS (
        SELECT CURRENT_DATE - INTERVAL '1 day' * COALESCE((SELECT dead_stock_days FROM company_settings), 90) AS cutoff_date
    ),
    last_sales AS (
        SELECT 
            oli.sku,
            MAX(o.created_at) AS last_sale_date
        FROM public.order_line_items oli
        JOIN public.orders o ON oli.order_id = o.id
        WHERE o.company_id = p_company_id
            AND o.financial_status = 'paid'
        GROUP BY oli.sku
    ),
    dead_stock_variants AS (
        SELECT 
            pv.sku,
            pv.title AS variant_title,
            p.title AS product_title,
            pv.inventory_quantity,
            COALESCE(pv.cost, 0) AS cost,
            ls.last_sale_date
        FROM public.product_variants pv
        JOIN public.products p ON pv.product_id = p.id
        LEFT JOIN last_sales ls ON pv.sku = ls.sku
        CROSS JOIN dead_stock_cutoff dsc
        WHERE pv.company_id = p_company_id
            AND pv.inventory_quantity > 0
            AND (ls.last_sale_date IS NULL OR ls.last_sale_date < dsc.cutoff_date)
    )
    SELECT 
        dsv.sku,
        COALESCE(dsv.variant_title, dsv.product_title) AS product_name,
        dsv.inventory_quantity AS quantity,
        (dsv.inventory_quantity * dsv.cost) AS total_value,
        dsv.last_sale_date
    FROM dead_stock_variants dsv
    ORDER BY total_value DESC;
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION public.get_dead_stock_report(uuid) TO authenticated;

-- Add comment for documentation
COMMENT ON FUNCTION public.get_dead_stock_report(uuid) IS 'Returns dead stock items for a company based on dead_stock_days setting and sales history';
