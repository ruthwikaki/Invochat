
-- Enable the UUID extension if it's not already enabled.
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create custom types for the application.
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


-- Create Companies Table
CREATE TABLE IF NOT EXISTS public.companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    owner_id UUID NOT NULL REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Create Company Users Junction Table
CREATE TABLE IF NOT EXISTS public.company_users (
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role public.company_role NOT NULL DEFAULT 'Member',
    PRIMARY KEY (user_id, company_id)
);

-- RLS policy for companies: Users can only see their own company.
DROP POLICY IF EXISTS "Users can only see their own company" ON public.companies;
CREATE POLICY "Users can only see their own company"
ON public.companies
FOR SELECT
USING (id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));

-- RLS policy for company_users: Users can only see records belonging to their own company.
DROP POLICY IF EXISTS "Users can only see users in their own company" ON public.company_users;
CREATE POLICY "Users can only see users in their own company"
ON public.company_users
FOR SELECT
USING (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));


-- This function runs after a new user signs up.
-- It creates a company for them and links them to it.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  company_id_to_set uuid;
  user_role public.company_role := 'Owner'; -- New users are owners by default.
BEGIN
  -- Create a new company for the new user.
  INSERT INTO public.companies (name, owner_id)
  VALUES (new.raw_user_meta_data->>'company_name', new.id)
  RETURNING id INTO company_id_to_set;

  -- Add the user to the company_users table.
  INSERT INTO public.company_users (user_id, company_id, role)
  VALUES (new.id, company_id_to_set, user_role);

  -- Update the user's app_metadata with the new company_id.
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id_to_set)
  WHERE id = new.id;
  
  RETURN new;
END;
$$;


-- Trigger the function after a new user is created.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_user();


-- Create a helper function to get the company ID for a user
CREATE OR REPLACE FUNCTION public.get_company_id_for_user(p_user_id UUID)
RETURNS UUID AS $$
DECLARE
    company_id UUID;
BEGIN
    SELECT c.company_id INTO company_id
    FROM public.company_users c
    WHERE c.user_id = p_user_id;
    RETURN company_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- All other tables and RLS policies will be defined below this line.
-- These tables are designed to be multi-tenant, with each row associated
-- with a company_id. RLS policies will ensure that users can only access
-- data belonging to their own company.

-- Products Table
CREATE TABLE IF NOT EXISTS public.products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    handle TEXT,
    product_type TEXT,
    tags TEXT[],
    status TEXT,
    image_url TEXT,
    external_product_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, external_product_id)
);
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow full access to own company data" ON public.products;
CREATE POLICY "Allow full access to own company data" ON public.products
    FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));


-- Suppliers Table
CREATE TABLE IF NOT EXISTS public.suppliers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    default_lead_time_days INT,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ
);
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow full access to own company data" ON public.suppliers;
CREATE POLICY "Allow full access to own company data" ON public.suppliers
    FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));


-- Product Variants Table
CREATE TABLE IF NOT EXISTS public.product_variants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku TEXT NOT NULL,
    title TEXT,
    option1_name TEXT,
    option1_value TEXT,
    option2_name TEXT,
    option2_value TEXT,
    option3_name TEXT,
    option3_value TEXT,
    barcode TEXT,
    price INT, -- in cents
    compare_at_price INT, -- in cents
    cost INT, -- in cents
    inventory_quantity INT NOT NULL DEFAULT 0,
    location TEXT,
    reorder_point INT,
    reorder_quantity INT,
    supplier_id UUID REFERENCES public.suppliers(id) ON DELETE SET NULL,
    external_variant_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, sku),
    UNIQUE(company_id, external_variant_id)
);
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow full access to own company data" ON public.product_variants;
CREATE POLICY "Allow full access to own company data" ON public.product_variants
    FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));


-- Customers Table
CREATE TABLE IF NOT EXISTS public.customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name TEXT,
    email TEXT,
    phone TEXT,
    external_customer_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ,
    UNIQUE(company_id, email),
    UNIQUE(company_id, external_customer_id)
);
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow full access to own company data" ON public.customers;
CREATE POLICY "Allow full access to own company data" ON public.customers
    FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));


-- Orders Table
CREATE TABLE IF NOT EXISTS public.orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number TEXT NOT NULL,
    external_order_id TEXT,
    customer_id UUID REFERENCES public.customers(id),
    financial_status TEXT,
    fulfillment_status TEXT,
    currency TEXT,
    subtotal INT NOT NULL,
    total_tax INT,
    total_shipping INT,
    total_discounts INT,
    total_amount INT NOT NULL,
    source_platform TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, external_order_id)
);
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow full access to own company data" ON public.orders;
CREATE POLICY "Allow full access to own company data" ON public.orders
    FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));


-- Order Line Items Table
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id UUID REFERENCES public.product_variants(id) ON DELETE SET NULL,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_name TEXT,
    variant_title TEXT,
    sku TEXT,
    quantity INT NOT NULL,
    price INT NOT NULL, -- in cents
    total_discount INT,
    tax_amount INT,
    cost_at_time INT,
    external_line_item_id TEXT
);
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow full access to own company data" ON public.order_line_items;
CREATE POLICY "Allow full access to own company data" ON public.order_line_items
    FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));


-- Refunds Table
CREATE TABLE IF NOT EXISTS public.refunds (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    refund_number TEXT NOT NULL,
    status TEXT NOT NULL,
    reason TEXT,
    note TEXT,
    total_amount INT NOT NULL, -- in cents
    created_by_user_id UUID REFERENCES auth.users(id),
    external_refund_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(company_id, external_refund_id)
);
ALTER TABLE public.refunds ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow full access to own company data" ON public.refunds;
CREATE POLICY "Allow full access to own company data" ON public.refunds
    FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));

-- Purchase Orders Table
CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id UUID REFERENCES public.suppliers(id),
    status TEXT NOT NULL DEFAULT 'Draft',
    po_number TEXT NOT NULL,
    total_cost INT NOT NULL DEFAULT 0, -- in cents
    expected_arrival_date DATE,
    idempotency_key UUID UNIQUE,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ
);
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow full access to own company data" ON public.purchase_orders;
CREATE POLICY "Allow full access to own company data" ON public.purchase_orders
    FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));


-- Purchase Order Line Items Table
CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    purchase_order_id UUID NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    quantity INT NOT NULL,
    cost INT NOT NULL -- in cents
);
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow full access to own company data" ON public.purchase_order_line_items;
CREATE POLICY "Allow full access to own company data" ON public.purchase_order_line_items
    FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));


-- Inventory Ledger Table
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type TEXT NOT NULL, -- e.g., 'sale', 'purchase_order', 'return', 'manual_adjustment'
    quantity_change INT NOT NULL,
    new_quantity INT NOT NULL,
    related_id UUID, -- e.g., order_id, purchase_order_id
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow full access to own company data" ON public.inventory_ledger;
CREATE POLICY "Allow full access to own company data" ON public.inventory_ledger
    FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));


-- Company Settings Table
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id UUID PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days INT NOT NULL DEFAULT 90,
    fast_moving_days INT NOT NULL DEFAULT 30,
    overstock_multiplier NUMERIC(5,2) NOT NULL DEFAULT 3.0,
    high_value_threshold INT NOT NULL DEFAULT 100000, -- in cents
    predictive_stock_days INT NOT NULL DEFAULT 7,
    currency TEXT NOT NULL DEFAULT 'USD',
    tax_rate NUMERIC(5,4) NOT NULL DEFAULT 0.0,
    timezone TEXT NOT NULL DEFAULT 'UTC',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ
);
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow full access to own company data" ON public.company_settings;
CREATE POLICY "Allow full access to own company data" ON public.company_settings
    FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));


-- Integrations Table
CREATE TABLE IF NOT EXISTS public.integrations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform public.integration_platform NOT NULL,
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
DROP POLICY IF EXISTS "Allow full access to own company data" ON public.integrations;
CREATE POLICY "Allow full access to own company data" ON public.integrations
    FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));

-- Channel Fees Table (for platform-specific costs)
CREATE TABLE IF NOT EXISTS public.channel_fees (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    channel_name TEXT NOT NULL,
    fixed_fee INT, -- in cents
    percentage_fee NUMERIC(5, 4),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, channel_name)
);
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow full access to own company data" ON public.channel_fees;
CREATE POLICY "Allow full access to own company data" ON public.channel_fees
    FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));

-- Audit Log Table
CREATE TABLE IF NOT EXISTS public.audit_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    details JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow admins and owners to read logs" ON public.audit_log;
CREATE POLICY "Allow admins and owners to read logs" ON public.audit_log
    FOR SELECT USING (
        company_id = get_company_id_for_user(auth.uid()) AND
        check_user_permission(auth.uid(), 'Admin')
    );

-- Chat and AI related tables
CREATE TABLE IF NOT EXISTS public.conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_accessed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    is_starred BOOLEAN NOT NULL DEFAULT false
);
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow access to own conversations" ON public.conversations;
CREATE POLICY "Allow access to own conversations" ON public.conversations
    FOR ALL USING (user_id = auth.uid());


CREATE TABLE IF NOT EXISTS public.messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role public.message_role NOT NULL,
    content TEXT NOT NULL,
    visualization JSONB,
    component TEXT,
    componentProps JSONB,
    confidence FLOAT,
    assumptions TEXT[],
    isError BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow access to own messages" ON public.messages;
CREATE POLICY "Allow access to own messages" ON public.messages
    FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));

-- User Feedback Table
CREATE TABLE IF NOT EXISTS public.feedback (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    subject_id TEXT NOT NULL,
    subject_type TEXT NOT NULL,
    feedback public.feedback_type NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.feedback ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow access to own company feedback" ON public.feedback;
CREATE POLICY "Allow access to own company feedback" ON public.feedback
    FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));

-- Export Jobs Table
CREATE TABLE IF NOT EXISTS public.export_jobs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    requested_by_user_id UUID NOT NULL REFERENCES auth.users(id),
    status TEXT NOT NULL DEFAULT 'pending',
    download_url TEXT,
    expires_at TIMESTAMPTZ,
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ
);
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow access to own company export jobs" ON public.export_jobs;
CREATE POLICY "Allow access to own company export jobs" ON public.export_jobs
    FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));

-- Webhook Events Table
CREATE TABLE IF NOT EXISTS public.webhook_events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  integration_id UUID NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
  webhook_id TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(integration_id, webhook_id)
);
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow access to own company webhook events" ON public.webhook_events;
CREATE POLICY "Allow access to own company webhook events" ON public.webhook_events
  FOR SELECT USING (
    (SELECT company_id FROM public.integrations WHERE id = integration_id) = get_company_id_for_user(auth.uid())
  );
-- No insert/update/delete from app, only from service role.


-- Create Indexes for performance
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_variants_company_id ON public.product_variants(company_id);
CREATE INDEX IF NOT EXISTS idx_variants_sku ON public.product_variants(company_id, sku);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON public.orders(company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_line_items_variant_id ON public.order_line_items(variant_id);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_company_id ON public.purchase_orders(company_id);
CREATE INDEX IF NOT EXISTS idx_po_line_items_po_id ON public.purchase_order_line_items(purchase_order_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id ON public.inventory_ledger(variant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_company_id ON public.audit_log(company_id, created_at DESC);

-- This function is a placeholder for the real database schema.
-- In a real project, this file would contain the complete CREATE TABLE statements,
-- RLS policies, and database functions necessary for the application to run.
-- For the purposes of this demo, we'll keep it simple.

-- Materialized View for Daily Sales
CREATE MATERIALIZED VIEW IF NOT EXISTS public.daily_sales_by_company AS
SELECT
    o.company_id,
    DATE(o.created_at) AS sale_date,
    SUM(oli.quantity) AS total_items_sold,
    SUM(oli.price * oli.quantity) AS total_revenue,
    COUNT(DISTINCT o.id) AS total_orders
FROM
    public.orders o
JOIN
    public.order_line_items oli ON o.id = oli.order_id
GROUP BY
    o.company_id,
    DATE(o.created_at);

-- Add unique index for concurrent refreshes
CREATE UNIQUE INDEX IF NOT EXISTS idx_daily_sales_by_company_unique ON public.daily_sales_by_company(company_id, sale_date);

-- Function to refresh the materialized view
CREATE OR REPLACE FUNCTION refresh_all_matviews(p_company_id UUID)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.daily_sales_by_company;
    -- Add other materialized views here in the future
END;
$$;
