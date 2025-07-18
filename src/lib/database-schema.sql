
-- ---
-- InvoChat Base Schema
-- ---

-- ---
-- Extensions
-- ---
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";
CREATE EXTENSION IF NOT EXISTS "pg_trgm" WITH SCHEMA "extensions";

-- ---
-- Types
-- ---
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'app_role') THEN
        CREATE TYPE public.app_role AS ENUM ('Owner', 'Admin', 'Member');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'app_permission') THEN
        CREATE TYPE public.app_permission AS ENUM ('products.read', 'products.write', 'orders.read', 'team.manage');
    END IF;
END
$$;

-- ---
-- Tables
-- ---

-- Stores company-level information.
CREATE TABLE IF NOT EXISTS public.companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;

-- Maps users to companies and defines their roles.
CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email TEXT,
    role public.app_role NOT NULL DEFAULT 'Member'::public.app_role,
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- Stores company-specific settings for business logic.
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id UUID PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days INT NOT NULL DEFAULT 90,
    fast_moving_days INT NOT NULL DEFAULT 30,
    predictive_stock_days INT NOT NULL DEFAULT 7,
    overstock_multiplier INT NOT NULL DEFAULT 3,
    high_value_threshold INT NOT NULL DEFAULT 1000, -- in cents
    promo_sales_lift_multiplier REAL NOT NULL DEFAULT 2.5,
    currency TEXT DEFAULT 'USD',
    timezone TEXT DEFAULT 'UTC',
    tax_rate NUMERIC DEFAULT 0,
    custom_rules JSONB,
    subscription_status TEXT DEFAULT 'trial',
    subscription_plan TEXT DEFAULT 'starter',
    subscription_expires_at TIMESTAMPTZ,
    stripe_customer_id TEXT,
    stripe_subscription_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ
);
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;

-- Manages integrations with e-commerce platforms.
CREATE TABLE IF NOT EXISTS public.integrations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform TEXT NOT NULL,
    shop_domain TEXT,
    shop_name TEXT,
    is_active BOOLEAN DEFAULT false,
    last_sync_at TIMESTAMPTZ,
    sync_status TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE (company_id, platform)
);
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;


-- Stores product information.
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
    fts_document TSVECTOR,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ,
    UNIQUE(company_id, external_product_id)
);
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS fts_document_idx ON public.products USING GIN (fts_document);

-- Stores product variants (SKUs).
CREATE TABLE IF NOT EXISTS public.product_variants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku TEXT NOT NULL,
    title TEXT,
    option1_name TEXT, option1_value TEXT,
    option2_name TEXT, option2_value TEXT,
    option3_name TEXT, option3_value TEXT,
    barcode TEXT,
    price INT, -- in cents
    compare_at_price INT, -- in cents
    cost INT, -- in cents
    inventory_quantity INT NOT NULL DEFAULT 0,
    location TEXT,
    external_variant_id TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    UNIQUE(company_id, sku)
);
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_product_variants_sku ON public.product_variants(company_id, sku);

-- Stores customer information.
CREATE TABLE IF NOT EXISTS public.customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name TEXT NOT NULL,
    email TEXT,
    total_orders INT DEFAULT 0,
    total_spent INT DEFAULT 0,
    first_order_date DATE,
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;

-- Stores order information.
CREATE TABLE IF NOT EXISTS public.orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number TEXT NOT NULL,
    external_order_id TEXT,
    customer_id UUID REFERENCES public.customers(id),
    financial_status TEXT DEFAULT 'pending',
    fulfillment_status TEXT DEFAULT 'unfulfilled',
    currency TEXT DEFAULT 'USD',
    subtotal INT NOT NULL DEFAULT 0,
    total_tax INT DEFAULT 0,
    total_shipping INT DEFAULT 0,
    total_discounts INT DEFAULT 0,
    total_amount INT NOT NULL,
    source_platform TEXT,
    source_name TEXT,
    tags TEXT[],
    notes TEXT,
    cancelled_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(company_id, external_order_id)
);
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_orders_company_created ON public.orders(company_id, created_at DESC);

-- Stores line items for each order.
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id) ON DELETE RESTRICT,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_name TEXT NOT NULL,
    variant_title TEXT,
    sku TEXT NOT NULL,
    quantity INT NOT NULL,
    price INT NOT NULL,
    total_discount INT DEFAULT 0,
    tax_amount INT DEFAULT 0,
    cost_at_time INT,
    fulfillment_status TEXT DEFAULT 'unfulfilled',
    requires_shipping BOOLEAN DEFAULT true,
    external_line_item_id TEXT
);
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON public.order_line_items(variant_id);


-- Stores supplier information.
CREATE TABLE IF NOT EXISTS public.suppliers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    default_lead_time_days INT,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;

-- Stores purchase order information.
CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id UUID REFERENCES public.suppliers(id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'Draft',
    po_number TEXT NOT NULL,
    total_cost INT NOT NULL,
    expected_arrival_date DATE,
    idempotency_key UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;

-- Stores line items for each purchase order.
CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    purchase_order_id UUID NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id) ON DELETE RESTRICT,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    quantity INT NOT NULL,
    cost INT NOT NULL
);
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;

-- Stores a ledger of all inventory movements.
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type TEXT NOT NULL, -- e.g., 'sale', 'purchase_order', 'reconciliation', 'manual_adjustment'
    quantity_change INT NOT NULL,
    new_quantity INT NOT NULL,
    related_id UUID, -- e.g., order_id, purchase_order_id
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_created ON public.inventory_ledger(variant_id, created_at DESC);

-- Stores chat conversation history.
CREATE TABLE IF NOT EXISTS public.conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    is_starred BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now(),
    last_accessed_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

-- Stores individual messages within conversations.
CREATE TABLE IF NOT EXISTS public.messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role TEXT NOT NULL,
    content TEXT,
    component TEXT,
    component_props JSONB,
    visualization JSONB,
    confidence NUMERIC,
    assumptions TEXT[],
    is_error BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id ON public.messages(conversation_id);

-- Stores audit logs for important actions.
CREATE TABLE IF NOT EXISTS public.audit_log (
    id BIGSERIAL PRIMARY KEY,
    company_id UUID REFERENCES public.companies(id),
    user_id UUID REFERENCES auth.users(id),
    action TEXT NOT NULL,
    details JSONB,
    created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

-- Stores webhook event IDs to prevent replay attacks.
CREATE TABLE IF NOT EXISTS public.webhook_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id UUID NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id TEXT NOT NULL,
    processed_at TIMESTAMPTZ DEFAULT now(),
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(integration_id, webhook_id)
);
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;

-- ---
-- Views
-- ---
DROP VIEW IF EXISTS public.product_variants_with_details;
CREATE VIEW public.product_variants_with_details AS
SELECT
    pv.*,
    p.title AS product_title,
    p.status AS product_status,
    p.image_url,
    p.product_type
FROM public.product_variants pv
JOIN public.products p ON pv.product_id = p.id
WHERE p.deleted_at IS NULL AND pv.deleted_at IS NULL;

-- ---
-- RLS Policies
-- ---
ALTER publication supabase_realtime ADD TABLE public.integrations;

-- Helper function to get company_id from user's app_metadata
CREATE OR REPLACE FUNCTION public.get_my_company_id()
RETURNS UUID AS $$
DECLARE
    company_id UUID;
BEGIN
    SELECT current_setting('request.jwt.claims', true)::jsonb->'app_metadata'->>'company_id'
    INTO company_id;
    RETURN company_id;
END;
$$ LANGUAGE plpgsql STABLE;

-- Generic policy for tables with a company_id column
CREATE OR REPLACE FUNCTION public.create_company_based_rls(table_name TEXT)
RETURNS void AS $$
BEGIN
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', table_name);
    EXECUTE format('DROP POLICY IF EXISTS "Allow full access based on company" ON public.%I;', table_name);
    EXECUTE format(
        'CREATE POLICY "Allow full access based on company" ON public.%I FOR ALL USING (company_id = public.get_my_company_id());',
        table_name
    );
END;
$$ LANGUAGE plpgsql;

-- Apply RLS to all relevant tables
SELECT public.create_company_based_rls(table_name)
FROM information_schema.tables
WHERE table_schema = 'public' AND table_name IN (
    'companies', 'users', 'company_settings', 'integrations', 'products',
    'product_variants', 'customers', 'orders', 'order_line_items',
    'suppliers', 'purchase_orders', 'purchase_order_line_items',
    'inventory_ledger', 'conversations', 'messages', 'audit_log', 'webhook_events'
);

-- Special policy for users table to allow users to see their own record
DROP POLICY IF EXISTS "Allow users to see their own record" ON public.users;
CREATE POLICY "Allow users to see their own record" ON public.users
FOR SELECT USING (id = auth.uid());

-- ---
-- Functions
-- ---

-- Function to handle new user creation
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    new_company_id UUID;
    user_email TEXT;
    company_name TEXT;
    invited_company_id UUID;
BEGIN
    -- Extract company_name from metadata if it's a new signup
    company_name := new.raw_app_meta_data->>'company_name';
    user_email := new.email;
    invited_company_id := new.raw_app_meta_data->>'company_id';

    IF invited_company_id IS NOT NULL THEN
        -- This is an invited user.
        INSERT INTO public.users (id, company_id, email, role)
        VALUES (new.id, invited_company_id, user_email, 'Member');

        -- Update the user's metadata in auth.users
        UPDATE auth.users
        SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', invited_company_id, 'role', 'Member')
        WHERE id = new.id;
    ELSIF company_name IS NOT NULL THEN
        -- This is a new user creating a new company.
        INSERT INTO public.companies (name) VALUES (company_name) RETURNING id INTO new_company_id;

        INSERT INTO public.users (id, company_id, email, role)
        VALUES (new.id, new_company_id, user_email, 'Owner');

        -- Update the user's metadata in auth.users
        UPDATE auth.users
        SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'role', 'Owner')
        WHERE id = new.id;
    END IF;

    RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
-- Set the search_path to handle SECURITY DEFINER functions safely
ALTER FUNCTION public.handle_new_user() SET search_path = public;

-- Trigger to call the function on new user signup
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Helper function to check user permissions
CREATE OR REPLACE FUNCTION public.check_user_permission(p_user_id UUID, p_required_role public.app_role)
RETURNS boolean AS $$
DECLARE
    user_role public.app_role;
BEGIN
    SELECT role INTO user_role FROM public.users WHERE id = p_user_id;

    IF user_role IS NULL THEN
        RETURN false; -- User not found in our public users table
    END IF;

    -- Owners have all permissions of an Admin
    IF p_required_role = 'Admin' AND (user_role = 'Owner' OR user_role = 'Admin') THEN
        RETURN true;
    END IF;

    -- Exact role match for other cases
    IF user_role = p_required_role THEN
        RETURN true;
    END IF;

    RETURN false;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;
ALTER FUNCTION public.check_user_permission(UUID, public.app_role) SET search_path = public;
