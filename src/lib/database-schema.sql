-- InvoChat Schema v1.1
-- This script is designed to be idempotent and can be run safely multiple times.

-- 1. Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 2. Schemas
CREATE SCHEMA IF NOT EXISTS private;

-- 3. Helper Functions

-- Function to get the company_id from the currently authenticated user's profile
CREATE OR REPLACE FUNCTION public.get_current_company_id()
RETURNS UUID AS $$
BEGIN
  RETURN (
    SELECT company_id FROM public.profiles WHERE id = auth.uid()
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to automatically set the updated_at timestamp on a table
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = (now() at time zone 'utc');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Dynamic function to apply the updated_at trigger to a list of tables
CREATE OR REPLACE FUNCTION public.apply_updated_at_trigger(tables TEXT[])
RETURNS VOID AS $$
DECLARE
    tbl TEXT;
BEGIN
    FOREACH tbl IN ARRAY tables
    LOOP
        EXECUTE format(
            'DROP TRIGGER IF EXISTS handle_updated_at ON public.%I;
             CREATE TRIGGER handle_updated_at
             BEFORE UPDATE ON public.%I
             FOR EACH ROW
             EXECUTE FUNCTION public.set_updated_at();',
            tbl, tbl
        );
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- 4. Tables
-- Note: The order of table creation is important to respect foreign key constraints.

CREATE TABLE IF NOT EXISTS public.companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() at time zone 'utc')
);

CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    first_name TEXT,
    last_name TEXT,
    role TEXT NOT NULL DEFAULT 'Member',
    created_at TIMESTAMPTZ DEFAULT (now() at time zone 'utc'),
    updated_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id UUID PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days INT NOT NULL DEFAULT 90,
    fast_moving_days INT NOT NULL DEFAULT 30,
    overstock_multiplier INT NOT NULL DEFAULT 3,
    high_value_threshold INT NOT NULL DEFAULT 1000,
    predictive_stock_days INT NOT NULL DEFAULT 7,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() at time zone 'utc'),
    updated_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS public.suppliers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    default_lead_time_days INT,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() at time zone 'utc'),
    updated_at TIMESTAMPTZ
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
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() at time zone 'utc'),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, external_product_id)
);

CREATE TABLE IF NOT EXISTS public.product_variants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku TEXT,
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
    location TEXT, -- Simple text field for bin, shelf, etc.
    external_variant_id TEXT,
    created_at TIMESTAMPTZ DEFAULT (now() at time zone 'utc'),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, sku),
    UNIQUE(company_id, external_variant_id)
);

CREATE TABLE IF NOT EXISTS public.customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name TEXT,
    email TEXT,
    total_orders INT DEFAULT 0,
    total_spent INT DEFAULT 0, -- in cents
    first_order_date DATE,
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT (now() at time zone 'utc'),
    UNIQUE(company_id, email)
);

CREATE TABLE IF NOT EXISTS public.orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number TEXT NOT NULL,
    external_order_id TEXT,
    customer_id UUID REFERENCES public.customers(id),
    financial_status TEXT,
    fulfillment_status TEXT,
    currency TEXT,
    subtotal INT, -- in cents
    total_tax INT,
    total_shipping INT,
    total_discounts INT,
    total_amount INT NOT NULL,
    source_platform TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() at time zone 'utc'),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, external_order_id)
);

CREATE TABLE IF NOT EXISTS public.order_line_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id UUID REFERENCES public.product_variants(id),
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

CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id UUID REFERENCES public.suppliers(id),
    status TEXT NOT NULL DEFAULT 'Draft',
    po_number TEXT NOT NULL,
    total_cost INT NOT NULL, -- in cents
    expected_arrival_date DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() at time zone 'utc'),
    updated_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    purchase_order_id UUID NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id),
    quantity INT NOT NULL,
    cost INT NOT NULL -- in cents
);

CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type TEXT NOT NULL,
    quantity_change INT NOT NULL,
    new_quantity INT NOT NULL,
    related_id UUID,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() at time zone 'utc')
);

CREATE TABLE IF NOT EXISTS public.conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT (now() at time zone 'utc'),
    last_accessed_at TIMESTAMPTZ DEFAULT (now() at time zone 'utc'),
    is_starred BOOLEAN DEFAULT FALSE
);

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
    created_at TIMESTAMPTZ DEFAULT (now() at time zone 'utc'),
    is_error BOOLEAN DEFAULT FALSE
);

CREATE TABLE IF NOT EXISTS public.integrations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform TEXT NOT NULL,
    shop_domain TEXT,
    shop_name TEXT,
    is_active BOOLEAN DEFAULT FALSE,
    last_sync_at TIMESTAMPTZ,
    sync_status TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() at time zone 'utc'),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, platform)
);

CREATE TABLE IF NOT EXISTS public.webhook_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id UUID NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id TEXT NOT NULL,
    processed_at TIMESTAMPTZ DEFAULT (now() at time zone 'utc'),
    created_at TIMESTAMPTZ DEFAULT (now() at time zone 'utc'),
    UNIQUE(integration_id, webhook_id)
);

CREATE TABLE IF NOT EXISTS public.audit_log (
    id BIGSERIAL PRIMARY KEY,
    company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    details JSONB,
    created_at TIMESTAMPTZ DEFAULT (now() at time zone 'utc')
);

CREATE TABLE IF NOT EXISTS public.export_jobs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    requested_by_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'pending',
    download_url TEXT,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() at time zone 'utc')
);

-- 5. Triggers for `updated_at`

-- Call the dynamic function to apply the trigger to all relevant tables
SELECT public.apply_updated_at_trigger(
    ARRAY['profiles', 'company_settings', 'suppliers', 'products', 'product_variants', 'orders', 'purchase_orders', 'integrations']
);

-- 6. Views

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
    pv.location,
    p.title AS product_title,
    p.status AS product_status,
    p.image_url
FROM
    public.product_variants pv
JOIN
    public.products p ON pv.product_id = p.id;


-- 7. Indexes

CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_company_id_product_id ON public.product_variants(company_id, product_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_sku ON public.product_variants(company_id, sku);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON public.orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_company_id ON public.order_line_items(company_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON public.order_line_items(variant_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_company_variant ON public.inventory_ledger(company_id, variant_id);
CREATE INDEX IF NOT EXISTS idx_conversations_user_id ON public.conversations(user_id);
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id ON public.messages(conversation_id);


-- 8. Row-Level Security (RLS)

ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;

-- 9. RLS Policies

-- Users can see their own profile
DROP POLICY IF EXISTS "Allow individual read access" ON public.profiles;
CREATE POLICY "Allow individual read access" ON public.profiles FOR SELECT USING (auth.uid() = id);

-- Users can update their own profile
DROP POLICY IF EXISTS "Allow individual update access" ON public.profiles;
CREATE POLICY "Allow individual update access" ON public.profiles FOR UPDATE USING (auth.uid() = id);

-- Users can only see their own company's data
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.companies;
CREATE POLICY "Allow full access based on company_id" ON public.companies FOR ALL
    USING (id = public.get_current_company_id());

-- Generic policy for most tables based on company_id
CREATE OR REPLACE FUNCTION public.apply_company_rls(tables TEXT[])
RETURNS VOID AS $$
DECLARE
    tbl TEXT;
BEGIN
    FOREACH tbl IN ARRAY tables
    LOOP
        EXECUTE format(
            'DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.%I;
             CREATE POLICY "Allow full access based on company_id" ON public.%I FOR ALL
             USING (company_id = public.get_current_company_id());',
            tbl, tbl
        );
    END LOOP;
END;
$$ LANGUAGE plpgsql;

SELECT public.apply_company_rls(ARRAY[
    'company_settings', 'products', 'product_variants', 'inventory_ledger', 'customers',
    'orders', 'order_line_items', 'suppliers', 'purchase_orders', 'purchase_order_line_items',
    'conversations', 'messages', 'integrations', 'audit_log', 'export_jobs'
]);

-- Special policy for webhook_events to join through integrations
DROP POLICY IF EXISTS "Allow read access to webhook_events" ON public.webhook_events;
CREATE POLICY "Allow read access to webhook_events" ON public.webhook_events FOR SELECT
    USING (
        EXISTS (
            SELECT 1
            FROM public.integrations i
            WHERE
                i.id = webhook_events.integration_id AND
                i.company_id = public.get_current_company_id()
        )
    );


-- 10. Database Functions & Triggers for New User Signup

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  company_id_new UUID;
  company_name_new TEXT;
BEGIN
  -- Extract company name from metadata, defaulting if not present
  company_name_new := COALESCE(new.raw_app_meta_data->>'company_name', 'My Company');

  -- Create a new company for the user
  INSERT INTO public.companies (name)
  VALUES (company_name_new)
  RETURNING id INTO company_id_new;

  -- Create a profile for the new user, linking them to the new company
  INSERT INTO public.profiles (id, company_id, role, first_name)
  VALUES (new.id, company_id_new, 'Owner', new.raw_app_meta_data->>'first_name');

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop trigger if it exists, then create it
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Stub for data retention cron job
CREATE OR REPLACE FUNCTION public.cleanup_old_data()
RETURNS void AS $$
BEGIN
    -- Example: Delete audit logs older than 90 days
    DELETE FROM public.audit_log WHERE created_at < now() - interval '90 days';

    -- Example: Delete conversations not accessed in 1 year
    DELETE FROM public.conversations WHERE last_accessed_at < now() - interval '1 year';
END;
$$ LANGUAGE plpgsql;


-- Function to record order from platform webhook (Shopify, etc.)
CREATE OR REPLACE FUNCTION public.record_order_from_platform(p_company_id UUID, p_order_payload JSONB, p_platform TEXT)
RETURNS VOID AS $$
DECLARE
    v_customer_id UUID;
    v_order_id UUID;
    v_variant_id UUID;
    v_line_item JSONB;
BEGIN
    -- Find or create customer
    INSERT INTO public.customers (company_id, email, customer_name)
    VALUES (
        p_company_id,
        p_order_payload->>'customer'->>'email',
        COALESCE(
            p_order_payload->>'customer'->>'first_name' || ' ' || p_order_payload->>'customer'->>'last_name',
            p_order_payload->>'customer'->>'email'
        )
    )
    ON CONFLICT (company_id, email) DO UPDATE SET customer_name = EXCLUDED.customer_name
    RETURNING id INTO v_customer_id;

    -- Insert order
    INSERT INTO public.orders (
        company_id, customer_id, external_order_id, order_number,
        financial_status, fulfillment_status, currency, total_amount, source_platform
    )
    VALUES (
        p_company_id, v_customer_id, p_order_payload->>'id', p_order_payload->>'name',
        p_order_payload->>'financial_status', p_order_payload->>'fulfillment_status',
        p_order_payload->>'currency', (p_order_payload->>'total_price')::numeric * 100, p_platform
    )
    ON CONFLICT (company_id, external_order_id) DO NOTHING
    RETURNING id INTO v_order_id;

    -- If order already existed, do nothing further
    IF v_order_id IS NULL THEN
        RETURN;
    END IF;

    -- Insert line items
    FOR v_line_item IN SELECT * FROM jsonb_array_elements(p_order_payload->'line_items')
    LOOP
        -- Lock the variant row to prevent race conditions on inventory updates
        SELECT id INTO v_variant_id
        FROM public.product_variants
        WHERE company_id = p_company_id AND sku = v_line_item->>'sku'
        FOR UPDATE;

        IF v_variant_id IS NOT NULL THEN
            INSERT INTO public.order_line_items (
                order_id, company_id, variant_id, product_name, sku, quantity, price
            )
            VALUES (
                v_order_id, p_company_id, v_variant_id, v_line_item->>'title',
                v_line_item->>'sku', (v_line_item->>'quantity')::int, (v_line_item->>'price')::numeric * 100
            );

            -- Update inventory quantity
            UPDATE public.product_variants
            SET inventory_quantity = inventory_quantity - (v_line_item->>'quantity')::int
            WHERE id = v_variant_id;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;


-- Function to get dashboard metrics
CREATE OR REPLACE FUNCTION public.get_dashboard_metrics(p_company_id UUID, p_days INT)
RETURNS JSONB AS $$
DECLARE
    metrics JSONB;
BEGIN
    SELECT jsonb_build_object(
        'total_revenue', (SELECT COALESCE(SUM(total_amount), 0) FROM public.orders WHERE company_id = p_company_id AND created_at >= now() - (p_days || ' days')::INTERVAL),
        'revenue_change', 0, -- Placeholder
        'total_sales', (SELECT COUNT(*) FROM public.orders WHERE company_id = p_company_id AND created_at >= now() - (p_days || ' days')::INTERVAL),
        'sales_change', 0, -- Placeholder
        'new_customers', (SELECT COUNT(*) FROM public.customers WHERE company_id = p_company_id AND created_at >= now() - (p_days || ' days')::INTERVAL),
        'customers_change', 0, -- Placeholder
        'dead_stock_value', (SELECT COALESCE(SUM(pv.cost * pv.inventory_quantity), 0) FROM public.product_variants pv WHERE pv.company_id = p_company_id), -- Simplified
        'sales_over_time', (
            SELECT jsonb_agg(d) FROM (
                SELECT DATE(gs.day) AS date, COALESCE(SUM(o.total_amount), 0) AS total_sales
                FROM generate_series(now() - (p_days || ' days')::INTERVAL, now(), '1 day'::INTERVAL) gs(day)
                LEFT JOIN public.orders o ON DATE(o.created_at) = DATE(gs.day) AND o.company_id = p_company_id
                GROUP BY gs.day ORDER BY gs.day
            ) d
        ),
        'top_selling_products', (
            SELECT jsonb_agg(p) FROM (
                SELECT p.title AS product_name, SUM(oli.price * oli.quantity) as total_revenue, p.image_url
                FROM public.order_line_items oli
                JOIN public.products p ON oli.product_id = p.id
                WHERE oli.company_id = p_company_id AND oli.order_id IN (SELECT id FROM public.orders WHERE created_at >= now() - (p_days || ' days')::INTERVAL)
                GROUP BY p.id
                ORDER BY total_revenue DESC
                LIMIT 5
            ) p
        ),
        'inventory_summary', (
             SELECT jsonb_build_object(
                'total_value', COALESCE(SUM(cost * inventory_quantity), 0),
                'in_stock_value', COALESCE(SUM(CASE WHEN inventory_quantity > 10 THEN cost * inventory_quantity ELSE 0 END), 0),
                'low_stock_value', COALESCE(SUM(CASE WHEN inventory_quantity BETWEEN 1 AND 10 THEN cost * inventory_quantity ELSE 0 END), 0),
                'dead_stock_value', COALESCE(SUM(CASE WHEN inventory_quantity <= 0 THEN cost * inventory_quantity ELSE 0 END), 0)
             )
             FROM public.product_variants WHERE company_id = p_company_id
        )
    ) INTO metrics;
    RETURN metrics;
END;
$$ LANGUAGE plpgsql;


-- Final sanity check: Ensure extensions are enabled for the current schema
-- This might be redundant but is safe to include.
GRANT USAGE ON SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO postgres, anon, authenticated, service_role;

ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres, anon, authenticated, service_role;
