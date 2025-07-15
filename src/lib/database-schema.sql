-- InvoChat Database Schema
-- Version: 1.5.0
-- Description: Adds critical performance indexes and integrity constraints.

-- Section 1: Extensions & Basic Setup
-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
-- Enable vector support for future AI features
CREATE EXTENSION IF NOT EXISTS "vector";

-- Section 2: Helper Functions
-- Function to get company_id from a user's JWT claims
CREATE OR REPLACE FUNCTION get_company_id()
RETURNS UUID AS $$
BEGIN
    RETURN (current_setting('request.jwt.claims', true)::jsonb ->> 'company_id')::UUID;
END;
$$ LANGUAGE plpgsql STABLE;

-- Function to get user_id from a user's JWT claims
CREATE OR REPLACE FUNCTION get_user_id()
RETURNS UUID AS $$
BEGIN
    RETURN (current_setting('request.jwt.claims', true)::jsonb ->> 'sub')::UUID;
END;
$$ LANGUAGE plpgsql STABLE;

-- Function to get user role from JWT claims
CREATE OR REPLACE FUNCTION get_user_role()
RETURNS TEXT AS $$
BEGIN
  RETURN current_setting('request.jwt.claims', true)::jsonb ->> 'user_role';
END;
$$ LANGUAGE plpgsql STABLE;


-- Section 3: Drop Existing Objects (Idempotent)
-- This section makes the script safe to re-run by dropping objects that will be redefined.
DO $$ BEGIN DROP VIEW IF EXISTS public.product_variants_with_details; EXCEPTION WHEN others THEN END; $$;
DO $$ BEGIN DROP VIEW IF EXISTS public.sales_by_day; EXCEPTION WHEN others THEN END; $$;
DO $$ BEGIN DROP VIEW IF EXISTS public.inventory_summary; EXCEPTION WHEN others THEN END; $$;
DO $$ BEGIN DROP VIEW IF EXISTS public.monthly_revenue; EXCEPTION WHEN others THEN END; $$;
DO $$ BEGIN DROP MATERIALIZED VIEW IF EXISTS public.daily_sales_stats; EXCEPTION WHEN others THEN END; $$;
DO $$ BEGIN DROP MATERIALIZED VIEW IF EXISTS public.product_sales_stats; EXCEPTION WHEN others THEN END; $$;

-- Drop dependent functions before dropping tables
DO $$ BEGIN DROP FUNCTION IF EXISTS public.get_dashboard_metrics(uuid, integer); EXCEPTION WHEN others THEN END; $$;
DO $$ BEGIN DROP FUNCTION IF EXISTS public.get_reorder_suggestions(uuid); EXCEPTION WHEN others THEN END; $$;

-- Safely drop RLS policies
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to manage own data" ON public.companies; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to manage data" ON public.products; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow read access to own company data" ON public.products; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to manage variants" ON public.product_variants; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow read access to own company variants" ON public.product_variants; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to manage orders" ON public.orders; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to read orders" ON public.orders; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to manage line items" ON public.order_line_items; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to read line items" ON public.order_line_items; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to manage suppliers" ON public.suppliers; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow read access for own company" ON public.suppliers; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow members to manage POs" ON public.purchase_orders; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow members to read POs" ON public.purchase_orders; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow members to manage PO line items" ON public.purchase_order_line_items; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow members to read PO line items" ON public.purchase_order_line_items; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to manage ledger" ON public.inventory_ledger; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow members to read ledger" ON public.inventory_ledger; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to manage settings" ON public.company_settings; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow members to read their integrations" ON public.integrations; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow members to manage their integrations" ON public.integrations; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow members to read customers" ON public.customers; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow members to manage customers" ON public.customers; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow access to own conversations" ON public.conversations; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow access to own messages" ON public.messages; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow access to own audit logs" ON public.audit_log; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to manage fees" ON public.channel_fees; EXCEPTION WHEN undefined_object THEN END; $$;


-- Section 4: Table Definitions
-- Contains all CREATE TABLE statements with constraints.

CREATE TABLE IF NOT EXISTS public.companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE NOT NULL,
    email TEXT,
    role TEXT DEFAULT 'member',
    created_at TIMESTAMPTZ DEFAULT now(),
    deleted_at TIMESTAMPTZ
);

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
    fts_document TSVECTOR, -- For full-text search
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE (company_id, external_product_id)
);

CREATE TABLE IF NOT EXISTS public.product_variants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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
    price INTEGER, -- Stored in cents
    compare_at_price INTEGER,
    cost INTEGER, -- Stored in cents
    inventory_quantity INTEGER NOT NULL DEFAULT 0,
    location TEXT,
    external_variant_id TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE (company_id, sku),
    UNIQUE (company_id, external_variant_id)
);

CREATE TABLE IF NOT EXISTS public.customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name TEXT NOT NULL,
    email TEXT,
    total_orders INTEGER DEFAULT 0,
    total_spent INTEGER DEFAULT 0, -- Stored in cents
    first_order_date DATE,
    created_at TIMESTAMPTZ DEFAULT now(),
    deleted_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS public.orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number TEXT NOT NULL,
    external_order_id TEXT,
    customer_id UUID REFERENCES public.customers(id),
    status TEXT NOT NULL DEFAULT 'pending',
    financial_status TEXT DEFAULT 'pending',
    fulfillment_status TEXT DEFAULT 'unfulfilled',
    currency TEXT DEFAULT 'USD',
    subtotal INTEGER NOT NULL DEFAULT 0,
    total_tax INTEGER DEFAULT 0,
    total_shipping INTEGER DEFAULT 0,
    total_discounts INTEGER DEFAULT 0,
    total_amount INTEGER NOT NULL,
    source_platform TEXT,
    source_name TEXT,
    tags TEXT[],
    notes TEXT,
    cancelled_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(company_id, external_order_id)
);

CREATE TABLE IF NOT EXISTS public.order_line_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    product_id UUID REFERENCES public.products(id),
    variant_id UUID REFERENCES public.product_variants(id),
    product_name TEXT NOT NULL,
    variant_title TEXT,
    sku TEXT,
    quantity INTEGER NOT NULL,
    price INTEGER NOT NULL, -- Stored in cents
    total_discount INTEGER DEFAULT 0,
    tax_amount INTEGER DEFAULT 0,
    cost_at_time INTEGER,
    fulfillment_status TEXT DEFAULT 'unfulfilled',
    requires_shipping BOOLEAN DEFAULT true,
    external_line_item_id TEXT
);

CREATE TABLE IF NOT EXISTS public.suppliers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    default_lead_time_days INTEGER,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id UUID REFERENCES public.suppliers(id),
    status TEXT NOT NULL DEFAULT 'Draft',
    po_number TEXT NOT NULL,
    total_cost INTEGER NOT NULL,
    expected_arrival_date DATE,
    idempotency_key UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (idempotency_key)
);

CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    purchase_order_id UUID NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id),
    quantity INTEGER NOT NULL,
    cost INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type TEXT NOT NULL, -- e.g., 'sale', 'purchase_order', 'reconciliation'
    quantity_change INTEGER NOT NULL,
    new_quantity INTEGER NOT NULL,
    related_id UUID,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id UUID PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days INTEGER NOT NULL DEFAULT 90,
    fast_moving_days INTEGER NOT NULL DEFAULT 30,
    overstock_multiplier INTEGER NOT NULL DEFAULT 3,
    high_value_threshold INTEGER NOT NULL DEFAULT 1000, -- Stored in dollars
    predictive_stock_days INTEGER NOT NULL DEFAULT 7,
    currency TEXT DEFAULT 'USD',
    timezone TEXT DEFAULT 'UTC',
    tax_rate NUMERIC DEFAULT 0,
    custom_rules JSONB,
    promo_sales_lift_multiplier real NOT NULL DEFAULT 2.5,
    subscription_status TEXT DEFAULT 'trial',
    subscription_plan TEXT DEFAULT 'starter',
    subscription_expires_at TIMESTAMPTZ,
    stripe_customer_id TEXT,
    stripe_subscription_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS public.integrations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform TEXT NOT NULL, -- e.g., 'shopify', 'woocommerce'
    shop_domain TEXT,
    shop_name TEXT,
    is_active BOOLEAN DEFAULT false,
    last_sync_at TIMESTAMPTZ,
    sync_status TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, platform)
);

CREATE TABLE IF NOT EXISTS public.conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    is_starred BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now(),
    last_accessed_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role TEXT NOT NULL, -- 'user' or 'assistant'
    content TEXT,
    component TEXT,
    component_props JSONB,
    visualization JSONB,
    confidence NUMERIC,
    assumptions TEXT[],
    is_error BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.audit_log (
    id bigserial PRIMARY KEY,
    company_id UUID REFERENCES public.companies(id),
    user_id UUID REFERENCES auth.users(id),
    action TEXT NOT NULL,
    details JSONB,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.channel_fees (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    channel_name TEXT NOT NULL,
    percentage_fee NUMERIC NOT NULL,
    fixed_fee NUMERIC NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, channel_name)
);

CREATE TABLE IF NOT EXISTS public.export_jobs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    requested_by_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'pending',
    download_url TEXT,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.webhook_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id UUID NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id TEXT NOT NULL,
    processed_at TIMESTAMPTZ DEFAULT now(),
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(integration_id, webhook_id)
);


-- Section 5: Data Integrity Constraints

ALTER TABLE public.product_variants 
  ADD CONSTRAINT check_price_non_negative CHECK (price IS NULL OR price >= 0),
  ADD CONSTRAINT check_cost_non_negative CHECK (cost IS NULL OR cost >= 0);

ALTER TABLE public.orders
  ADD CONSTRAINT check_total_amount_positive CHECK (total_amount IS NULL OR total_amount >= 0);


-- Section 6: Indexes for Performance

-- Standard foreign key indexes
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_company_id ON public.product_variants(company_id);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON public.orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON public.order_line_items(variant_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id ON public.inventory_ledger(variant_id);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_supplier_id ON public.purchase_orders(supplier_id);

-- Performance-critical indexes
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON public.orders(company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_created_at ON public.inventory_ledger(company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_product_variants_inventory_quantity ON public.product_variants(company_id, inventory_quantity) WHERE inventory_quantity > 0;

-- Full-text search index
CREATE INDEX IF NOT EXISTS products_fts_document_idx ON public.products USING GIN (fts_document);


-- Section 7: Views
-- Definitions for simplified data access and analytics.

CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT 
    pv.*,
    p.title AS product_title,
    p.status AS product_status,
    p.image_url,
    p.product_type
FROM 
    public.product_variants pv
JOIN 
    public.products p ON pv.product_id = p.id;

CREATE OR REPLACE VIEW public.sales_by_day AS
SELECT 
    company_id,
    date_trunc('day', created_at) AS sale_date,
    SUM(total_amount) as daily_revenue,
    COUNT(id) as daily_orders,
    SUM((SELECT SUM(quantity) FROM public.order_line_items WHERE order_id = o.id)) as daily_units_sold
FROM 
    public.orders o
WHERE 
    status <> 'cancelled' AND financial_status = 'paid'
GROUP BY 
    company_id, sale_date;


-- Section 8: Database Functions (RPC)
-- Core business logic encapsulated in secure, callable functions.

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    v_company_id UUID;
BEGIN
    -- Create a new company for the new user
    INSERT INTO public.companies (name)
    VALUES (new.raw_user_meta_data ->> 'company_name')
    RETURNING id INTO v_company_id;

    -- Insert a corresponding entry in the public.users table
    INSERT INTO public.users (id, company_id, email, role)
    VALUES (new.id, v_company_id, new.email, 'Owner');
    
    -- Update the user's app_metadata with the new company_id
    UPDATE auth.users
    SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', v_company_id, 'user_role', 'Owner')
    WHERE id = new.id;
    
    RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.create_purchase_orders_from_suggestions(
    p_company_id UUID,
    p_user_id UUID,
    p_suggestions JSONB,
    p_idempotency_key UUID
)
RETURNS INT AS $$
DECLARE
    supplier_id UUID;
    po_id UUID;
    suggestion JSONB;
    item JSONB;
    grouped_suggestions JSONB;
    total_cost INT;
    new_po_count INT := 0;
BEGIN
    -- Prevent duplicate submissions
    IF EXISTS (SELECT 1 FROM public.purchase_orders WHERE idempotency_key = p_idempotency_key) THEN
        RETURN 0;
    END IF;

    -- Group suggestions by supplier_id
    SELECT jsonb_object_agg(s.supplier_id, s.suggestions)
    INTO grouped_suggestions
    FROM (
        SELECT 
            (elem ->> 'supplier_id')::UUID AS supplier_id,
            jsonb_agg(elem) AS suggestions
        FROM jsonb_array_elements(p_suggestions) elem
        WHERE (elem ->> 'supplier_id') IS NOT NULL
        GROUP BY (elem ->> 'supplier_id')::UUID
    ) s;

    IF grouped_suggestions IS NULL THEN
        RETURN 0;
    END IF;
    
    -- Loop through each supplier group
    FOR supplier_id, suggestion IN SELECT * FROM jsonb_each(grouped_suggestions)
    LOOP
        -- Wrap in a transaction block
        BEGIN
            total_cost := 0;
            -- Create a new Purchase Order for the supplier
            INSERT INTO public.purchase_orders (company_id, supplier_id, po_number, total_cost, status, idempotency_key)
            VALUES (
                p_company_id,
                supplier_id,
                'PO-' || to_char(now(), 'YYYYMMDD') || '-' || (SELECT COUNT(*) + 1 FROM public.purchase_orders WHERE company_id = p_company_id),
                0, -- Placeholder, will update later
                'Ordered',
                p_idempotency_key
            ) RETURNING id INTO po_id;

            -- Loop through items for this supplier
            FOR item IN SELECT * FROM jsonb_array_elements(suggestion)
            LOOP
                INSERT INTO public.purchase_order_line_items (purchase_order_id, variant_id, quantity, cost)
                VALUES (
                    po_id,
                    (item ->> 'variant_id')::UUID,
                    (item ->> 'suggested_reorder_quantity')::INT,
                    (item ->> 'unit_cost')::INT
                );
                total_cost := total_cost + ((item ->> 'suggested_reorder_quantity')::INT * (item ->> 'unit_cost')::INT);
            END LOOP;

            -- Update the total cost of the PO
            UPDATE public.purchase_orders SET total_cost = total_cost WHERE id = po_id;
            
            new_po_count := new_po_count + 1;
        EXCEPTION WHEN others THEN
            RAISE WARNING 'Error creating PO for supplier %: %', supplier_id, SQLERRM;
            -- If any part fails, the transaction for this PO will be rolled back.
            -- Continue to the next supplier.
            CONTINUE;
        END;

    END LOOP;

    RETURN new_po_count;
END;
$$ LANGUAGE plpgsql;

-- Section 9: Triggers
-- Automated actions that respond to database events.

-- Trigger for new user signup
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Trigger for fts_document update
DROP TRIGGER IF EXISTS tsvector_update_trigger ON public.products;
CREATE TRIGGER tsvector_update_trigger BEFORE INSERT OR UPDATE
ON public.products FOR EACH ROW EXECUTE PROCEDURE
tsvector_update_trigger(fts_document, 'pg_catalog.english', title, description, product_type);


-- Section 10: Row-Level Security (RLS)
-- The core of the multi-tenant security model.

-- Enable RLS on all relevant tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Allow company members to manage own data" ON public.companies
FOR ALL USING (id = get_company_id());

CREATE POLICY "Allow members to manage their company data" ON public.users
FOR ALL USING (company_id = get_company_id());

CREATE POLICY "Allow company members to manage data" ON public.products
FOR ALL USING (company_id = get_company_id());

CREATE POLICY "Allow company members to manage variants" ON public.product_variants
FOR ALL USING (company_id = get_company_id());

CREATE POLICY "Allow company members to manage orders" ON public.orders
FOR ALL USING (company_id = get_company_id());

CREATE POLICY "Allow company members to manage line items" ON public.order_line_items
FOR ALL USING (company_id = get_company_id());

CREATE POLICY "Allow company members to manage suppliers" ON public.suppliers
FOR ALL USING (company_id = get_company_id());

CREATE POLICY "Allow members to manage POs" ON public.purchase_orders
FOR ALL USING (company_id = get_company_id());

CREATE POLICY "Allow members to manage PO line items" ON public.purchase_order_line_items
FOR ALL USING (purchase_order_id IN (SELECT id FROM public.purchase_orders WHERE company_id = get_company_id()));

CREATE POLICY "Allow company members to manage ledger" ON public.inventory_ledger
FOR ALL USING (company_id = get_company_id());

CREATE POLICY "Allow company members to manage settings" ON public.company_settings
FOR ALL USING (company_id = get_company_id());

CREATE POLICY "Allow members to manage their integrations" ON public.integrations
FOR ALL USING (company_id = get_company_id());

CREATE POLICY "Allow members to manage customers" ON public.customers
FOR ALL USING (company_id = get_company_id());

CREATE POLICY "Allow access to own conversations" ON public.conversations
FOR ALL USING (user_id = get_user_id());

CREATE POLICY "Allow access to own messages" ON public.messages
FOR ALL USING (company_id = get_company_id() AND conversation_id IN (SELECT id FROM public.conversations WHERE user_id = get_user_id()));

CREATE POLICY "Allow access to own audit logs" ON public.audit_log
FOR SELECT USING (company_id = get_company_id());

CREATE POLICY "Allow company members to manage fees" ON public.channel_fees
FOR ALL USING (company_id = get_company_id());
