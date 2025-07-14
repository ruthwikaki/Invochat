
-- Enable the UUID extension if it's not already enabled.
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Function to get the current user's ID from the JWT.
-- Returns NULL if no user is authenticated.
CREATE OR REPLACE FUNCTION get_current_user_id()
RETURNS UUID AS $$
BEGIN
  RETURN (auth.jwt()->>'sub')::UUID;
EXCEPTION
  WHEN OTHERS THEN
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Function to get the company_id from the user's custom claims.
-- This is set by a trigger when a new user signs up.
CREATE OR REPLACE FUNCTION get_current_company_id()
RETURNS UUID AS $$
DECLARE
    company_id_claim UUID;
BEGIN
    company_id_claim := (auth.jwt()->'app_metadata'->>'company_id')::UUID;
    RETURN company_id_claim;
EXCEPTION
    WHEN OTHERS THEN
        -- This will happen for anonymous users or if the claim is missing.
        RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- =================================================================
-- 1. COMPANIES Table
-- Stores information about each company tenant.
-- =================================================================
CREATE TABLE IF NOT EXISTS public.companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- =================================================================
-- 2. USERS Table
-- Extends Supabase's auth.users table with profile information.
-- =================================================================
CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE NOT NULL,
    role TEXT NOT NULL DEFAULT 'Member' CHECK (role IN ('Owner', 'Admin', 'Member')),
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- =================================================================
-- 3. COMPANY SETTINGS Table
-- Stores business logic settings for each company.
-- =================================================================
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id UUID PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days INTEGER DEFAULT 90 NOT NULL,
    fast_moving_days INTEGER DEFAULT 30 NOT NULL,
    overstock_multiplier NUMERIC DEFAULT 3.0 NOT NULL,
    high_value_threshold INTEGER DEFAULT 100000 NOT NULL, -- in cents
    predictive_stock_days INTEGER DEFAULT 7 NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ
);

-- =================================================================
-- 4. SUPPLIERS Table
-- =================================================================
CREATE TABLE IF NOT EXISTS public.suppliers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE NOT NULL,
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    default_lead_time_days INTEGER,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- =================================================================
-- 5. PRODUCTS and VARIANTS Tables
-- =================================================================
CREATE TABLE IF NOT EXISTS public.products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    handle TEXT,
    product_type TEXT,
    tags TEXT[],
    status TEXT,
    image_url TEXT,
    external_product_id TEXT,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, external_product_id)
);
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_products_tags ON public.products USING GIN(tags);

CREATE TABLE IF NOT EXISTS public.product_variants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID REFERENCES public.products(id) ON DELETE CASCADE NOT NULL,
    company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE NOT NULL,
    sku TEXT,
    title TEXT,
    option1_name TEXT,
    option1_value TEXT,
    option2_name TEXT,
    option2_value TEXT,
    option3_name TEXT,
    option3_value TEXT,
    barcode TEXT,
    price INTEGER, -- in cents
    compare_at_price INTEGER,
    cost INTEGER,
    inventory_quantity INTEGER NOT NULL DEFAULT 0 CHECK (inventory_quantity >= 0),
    external_variant_id TEXT,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, external_variant_id),
    UNIQUE(company_id, sku)
);
CREATE INDEX IF NOT EXISTS idx_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_variants_company_id ON public.product_variants(company_id);
CREATE INDEX IF NOT EXISTS idx_variants_sku ON public.product_variants(sku);


-- =================================================================
-- 6. CUSTOMERS Table
-- =================================================================
CREATE TABLE IF NOT EXISTS public.customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE NOT NULL,
    customer_name TEXT,
    email TEXT,
    total_orders INTEGER DEFAULT 0,
    total_spent INTEGER DEFAULT 0,
    first_order_date TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    deleted_at TIMESTAMPTZ,
    UNIQUE(company_id, email)
);

-- =================================================================
-- 7. ORDERS and LINE ITEMS Tables
-- =================================================================
CREATE TABLE IF NOT EXISTS public.orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE NOT NULL,
    customer_id UUID REFERENCES public.customers(id) ON DELETE SET NULL,
    order_number TEXT NOT NULL,
    external_order_id TEXT,
    financial_status TEXT,
    fulfillment_status TEXT,
    currency TEXT,
    subtotal INTEGER NOT NULL,
    total_tax INTEGER,
    total_shipping INTEGER,
    total_discounts INTEGER,
    total_amount INTEGER NOT NULL CHECK (total_amount >= 0),
    source_platform TEXT,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, external_order_id)
);

CREATE TABLE IF NOT EXISTS public.order_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID REFERENCES public.orders(id) ON DELETE CASCADE NOT NULL,
    variant_id UUID REFERENCES public.product_variants(id) ON DELETE SET NULL,
    company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE NOT NULL,
    product_name TEXT,
    variant_title TEXT,
    sku TEXT,
    quantity INTEGER NOT NULL,
    price INTEGER NOT NULL CHECK (price >= 0),
    total_discount INTEGER,
    tax_amount INTEGER,
    cost_at_time INTEGER CHECK (cost_at_time >= 0),
    external_line_item_id TEXT
);
CREATE INDEX IF NOT EXISTS idx_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_line_items_variant_id ON public.order_line_items(variant_id);

-- =================================================================
-- 8. PURCHASE ORDERS Tables
-- =================================================================
CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE NOT NULL,
    supplier_id UUID REFERENCES public.suppliers(id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'Draft',
    po_number TEXT NOT NULL,
    total_cost INTEGER NOT NULL CHECK (total_cost >= 0),
    expected_arrival_date DATE,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    purchase_order_id UUID REFERENCES public.purchase_orders(id) ON DELETE CASCADE NOT NULL,
    variant_id UUID REFERENCES public.product_variants(id) ON DELETE CASCADE NOT NULL,
    quantity INTEGER NOT NULL,
    cost INTEGER NOT NULL CHECK (cost >= 0)
);

-- =================================================================
-- 9. INVENTORY and AUDITING Tables
-- =================================================================
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id BIGSERIAL PRIMARY KEY,
    company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE NOT NULL,
    variant_id UUID REFERENCES public.product_variants(id) ON DELETE CASCADE NOT NULL,
    change_type TEXT NOT NULL, -- e.g., 'sale', 'purchase_order', 'reconciliation'
    quantity_change INTEGER NOT NULL,
    new_quantity INTEGER NOT NULL,
    related_id UUID,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.audit_log (
    id BIGSERIAL PRIMARY KEY,
    company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE NOT NULL,
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    details JSONB,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- =================================================================
-- 10. INTEGRATIONS and WEBHOOKS Tables
-- =================================================================
CREATE TABLE IF NOT EXISTS public.integrations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE NOT NULL,
    platform TEXT NOT NULL,
    shop_domain TEXT,
    shop_name TEXT,
    is_active BOOLEAN DEFAULT TRUE NOT NULL,
    last_sync_at TIMESTAMPTZ,
    sync_status TEXT,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, platform)
);

CREATE TABLE IF NOT EXISTS public.webhook_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    integration_id UUID REFERENCES public.integrations(id) ON DELETE CASCADE NOT NULL,
    webhook_id TEXT NOT NULL,
    processed_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    UNIQUE(integration_id, webhook_id)
);

-- =================================================================
-- 11. CHAT and MESSAGES Tables
-- =================================================================
CREATE TABLE IF NOT EXISTS public.conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE NOT NULL,
    title TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    last_accessed_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    is_starred BOOLEAN DEFAULT FALSE NOT NULL
);

CREATE TABLE IF NOT EXISTS public.messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID REFERENCES public.conversations(id) ON DELETE CASCADE NOT NULL,
    company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
    content TEXT NOT NULL,
    visualization JSONB,
    confidence REAL,
    assumptions TEXT[],
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- =================================================================
-- 12. TRIGGERS and FUNCTIONS
-- =================================================================

-- Drop existing triggers and functions if they exist to ensure idempotency.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.create_company_and_associate_user(uuid, text, text);

-- This function creates a new company and links it to the new user.
CREATE OR REPLACE FUNCTION public.create_company_and_associate_user(
    user_id UUID,
    company_name TEXT,
    user_role TEXT DEFAULT 'Owner'
) RETURNS VOID AS $$
DECLARE
    new_company_id UUID;
BEGIN
    -- Create a new company
    INSERT INTO public.companies (name)
    VALUES (company_name)
    RETURNING id INTO new_company_id;

    -- Insert a profile for the new user, linking them to the new company
    INSERT INTO public.users (id, company_id, role)
    VALUES (user_id, new_company_id, user_role);

    -- Update the user's app_metadata in Supabase Auth with the company_id
    UPDATE auth.users
    SET app_metadata = app_metadata || jsonb_build_object('company_id', new_company_id, 'role', user_role)
    WHERE id = user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- This function handles the creation of a new user.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    company_name_from_meta TEXT;
BEGIN
    company_name_from_meta := new.raw_app_meta_data->>'company_name';
    
    -- If company_name is provided, create a new company for this user.
    IF company_name_from_meta IS NOT NULL THEN
        PERFORM public.create_company_and_associate_user(new.id, company_name_from_meta, 'Owner');
    END IF;
    
    RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- The trigger that executes the handle_new_user function when a new user signs up.
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_user();

-- Drop existing policies before creating new ones
-- Note: Dropping policies might require adjusting the order or using CASCADE
-- if there are complex dependencies. For this schema, direct drops should work if ordered correctly.
DO $$
DECLARE
    policy_name TEXT;
    table_name TEXT;
BEGIN
    FOR table_name IN SELECT tablename FROM pg_tables WHERE schemaname = 'public'
    LOOP
        FOR policy_name IN SELECT policyname FROM pg_policies WHERE tablename = table_name AND schemaname = 'public'
        LOOP
            EXECUTE 'DROP POLICY IF EXISTS "' || policy_name || '" ON public.' || table_name || ';';
        END LOOP;
    END LOOP;
END;
$$;


-- =================================================================
-- 13. ROW-LEVEL SECURITY (RLS) POLICIES
-- =================================================================

-- Enable RLS for all tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
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
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;


-- POLICIES
CREATE POLICY "Allow individual user read access"
ON public.users FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Allow individual user to update their own profile"
ON public.users FOR UPDATE USING (auth.uid() = id) WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can see other users in their own company."
ON public.users FOR SELECT USING (company_id = get_current_company_id());

CREATE POLICY "Users can only see their own company."
ON public.companies FOR SELECT USING (id = get_current_company_id());

CREATE POLICY "Allow full access based on company_id"
ON public.companies FOR ALL USING (id = get_current_company_id());

CREATE POLICY "Allow read access to other users in same company"
ON public.users FOR SELECT USING (company_id = get_current_company_id());

CREATE POLICY "Allow full access based on company_id"
ON public.company_settings FOR ALL USING (company_id = get_current_company_id());

CREATE POLICY "Allow full access based on company_id"
ON public.products FOR ALL USING (company_id = get_current_company_id());

CREATE POLICY "Allow full access based on company_id"
ON public.product_variants FOR ALL USING (company_id = get_current_company_id());

CREATE POLICY "Allow full access based on company_id"
ON public.inventory_ledger FOR ALL USING (company_id = get_current_company_id());

CREATE POLICY "Allow full access based on company_id"
ON public.customers FOR ALL USING (company_id = get_current_company_id());

CREATE POLICY "Allow full access based on company_id"
ON public.orders FOR ALL USING (company_id = get_current_company_id());

CREATE POLICY "Allow full access based on company_id"
ON public.order_line_items FOR ALL USING (company_id = get_current_company_id());

CREATE POLICY "Allow full access based on company_id"
ON public.suppliers FOR ALL USING (company_id = get_current_company_id());

CREATE POLICY "Allow full access to own conversations"
ON public.conversations FOR ALL USING (user_id = auth.uid());

CREATE POLICY "Allow full access to messages in own conversations"
ON public.messages FOR ALL USING (conversation_id IN (SELECT id FROM conversations WHERE user_id = auth.uid()));

CREATE POLICY "Allow full access based on company_id"
ON public.integrations FOR ALL USING (company_id = get_current_company_id());

CREATE POLICY "Allow read access to company audit log"
ON public.audit_log FOR SELECT USING (company_id = get_current_company_id());

CREATE POLICY "Allow read access to webhook_events"
ON public.webhook_events FOR SELECT USING (integration_id IN (SELECT id FROM integrations WHERE company_id = get_current_company_id()));


-- =================================================================
-- 14. VIEWS AND MATERIALIZED VIEWS (For performance)
-- =================================================================

-- A view to easily get product variants with their parent product's title and image
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


-- Placeholder for materialized views, which are snapshots of data for fast reads.
-- These would be refreshed periodically by a background job.
CREATE MATERIALIZED VIEW IF NOT EXISTS public.company_dashboard_metrics AS
SELECT
    p.company_id,
    COUNT(DISTINCT p.id) as total_products,
    COUNT(DISTINCT pv.sku) as total_variants,
    SUM(pv.inventory_quantity) as total_units,
    SUM(pv.inventory_quantity * pv.cost) as total_inventory_value
FROM
    public.products p
JOIN
    public.product_variants pv ON p.id = pv.product_id
GROUP BY
    p.company_id;

CREATE UNIQUE INDEX IF NOT EXISTS idx_company_dashboard_metrics_company_id ON public.company_dashboard_metrics(company_id);

REFRESH MATERIALIZED VIEW CONCURRENTLY public.company_dashboard_metrics;

-- =================================================================
-- 15. ADVANCED DATABASE FUNCTIONS (For business logic)
-- =================================================================

-- Function to record a sale and automatically update inventory
CREATE OR REPLACE FUNCTION public.record_order_from_platform(p_company_id uuid, p_order_payload jsonb, p_platform text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_customer_id uuid;
    v_order_id uuid;
    v_line_item jsonb;
    v_variant_id uuid;
    v_current_quantity int;
BEGIN
    -- Find or create the customer
    SELECT id INTO v_customer_id FROM customers
    WHERE company_id = p_company_id AND email = p_order_payload->'billing'->>'email';

    IF v_customer_id IS NULL THEN
        INSERT INTO customers (company_id, customer_name, email)
        VALUES (p_company_id, p_order_payload->'billing'->>'first_name' || ' ' || p_order_payload->'billing'->>'last_name', p_order_payload->'billing'->>'email')
        RETURNING id INTO v_customer_id;
    END IF;

    -- Insert the order
    INSERT INTO orders (company_id, customer_id, order_number, external_order_id, financial_status, fulfillment_status, currency, subtotal, total_tax, total_shipping, total_discounts, total_amount, source_platform, created_at)
    VALUES (
        p_company_id,
        v_customer_id,
        p_order_payload->>'number',
        p_order_payload->>'id',
        p_order_payload->>'financial_status',
        p_order_payload->>'fulfillment_status',
        p_order_payload->>'currency',
        (p_order_payload->>'subtotal_price')::numeric * 100,
        (p_order_payload->>'total_tax')::numeric * 100,
        (p_order_payload->>'total_shipping_price')::numeric * 100,
        (p_order_payload->>'total_discounts')::numeric * 100,
        (p_order_payload->>'total_price')::numeric * 100,
        p_platform,
        (p_order_payload->>'created_at')::timestamptz
    )
    ON CONFLICT (company_id, external_order_id) DO NOTHING
    RETURNING id INTO v_order_id;

    -- If the order already existed, we're done.
    IF v_order_id IS NULL THEN
        RETURN;
    END IF;

    -- Process line items
    FOR v_line_item IN SELECT * FROM jsonb_array_elements(p_order_payload->'line_items')
    LOOP
        -- Find the corresponding variant
        SELECT id INTO v_variant_id FROM product_variants
        WHERE company_id = p_company_id AND external_variant_id = v_line_item->>'variant_id';

        -- If variant exists, update inventory and insert line item
        IF v_variant_id IS NOT NULL THEN
            -- Use SELECT FOR UPDATE to lock the row
            SELECT inventory_quantity INTO v_current_quantity FROM product_variants WHERE id = v_variant_id FOR UPDATE;

            UPDATE product_variants
            SET inventory_quantity = v_current_quantity - (v_line_item->>'quantity')::int
            WHERE id = v_variant_id;
            
            INSERT INTO inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes)
            VALUES (p_company_id, v_variant_id, 'sale', -(v_line_item->>'quantity')::int, v_current_quantity - (v_line_item->>'quantity')::int, v_order_id, 'Order #' || (p_order_payload->>'number'));

        END IF;

        INSERT INTO order_line_items (order_id, variant_id, company_id, product_name, variant_title, sku, quantity, price, total_discount, external_line_item_id)
        VALUES (
            v_order_id,
            v_variant_id,
            p_company_id,
            v_line_item->>'title',
            v_line_item->>'variant_title',
            v_line_item->>'sku',
            (v_line_item->>'quantity')::int,
            (v_line_item->>'price')::numeric * 100,
            (v_line_item->>'total_discount')::numeric * 100,
            v_line_item->>'id'
        );
    END LOOP;
END;
$$;

-- Function to create purchase orders from reorder suggestions
CREATE OR REPLACE FUNCTION create_purchase_orders_from_suggestions(
    p_company_id UUID,
    p_user_id UUID,
    p_suggestions JSONB
) RETURNS INT AS $$
DECLARE
    suggestion JSONB;
    supplier_id_val UUID;
    po_id UUID;
    total_cost_val INT;
    po_number_val TEXT;
    created_po_count INT := 0;
    supplier_map JSONB := '{}'::JSONB;
BEGIN
    -- Group suggestions by supplier
    FOR suggestion IN SELECT * FROM jsonb_array_elements(p_suggestions)
    LOOP
        supplier_id_val := (suggestion->>'supplier_id')::UUID;
        IF supplier_id_val IS NULL THEN
            CONTINUE; -- Skip items with no supplier
        END IF;

        IF NOT (supplier_map ? supplier_id_val::TEXT) THEN
            supplier_map := jsonb_set(supplier_map, ARRAY[supplier_id_val::TEXT], '[]'::JSONB);
        END IF;

        supplier_map := jsonb_set(
            supplier_map,
            ARRAY[supplier_id_val::TEXT],
            (supplier_map->supplier_id_val::TEXT) || suggestion
        );
    END LOOP;

    -- Create one PO per supplier
    FOR supplier_id_val IN SELECT * FROM jsonb_object_keys(supplier_map)
    LOOP
        total_cost_val := 0;
        po_number_val := 'PO-' || to_char(now(), 'YYYYMMDD') || '-' || (created_po_count + 1);

        -- Calculate total cost first
        FOR suggestion IN SELECT * FROM jsonb_array_elements(supplier_map->supplier_id_val::TEXT)
        LOOP
            total_cost_val := total_cost_val + (suggestion->>'suggested_reorder_quantity')::INT * (suggestion->>'unit_cost')::INT;
        END LOOP;

        -- Create the purchase order
        INSERT INTO purchase_orders (company_id, supplier_id, status, po_number, total_cost)
        VALUES (p_company_id, supplier_id_val, 'Draft', po_number_val, total_cost_val)
        RETURNING id INTO po_id;

        -- Create line items for the PO
        FOR suggestion IN SELECT * FROM jsonb_array_elements(supplier_map->supplier_id_val::TEXT)
        LOOP
            INSERT INTO purchase_order_line_items (purchase_order_id, variant_id, quantity, cost)
            VALUES (po_id, (suggestion->>'variant_id')::UUID, (suggestion->>'suggested_reorder_quantity')::INT, (suggestion->>'unit_cost')::INT);
        END LOOP;
        
        -- Create audit log entry
        INSERT INTO audit_log(company_id, user_id, action, details)
        VALUES (p_company_id, p_user_id, 'purchase_order_created', jsonb_build_object(
            'purchase_order_id', po_id,
            'supplier_id', supplier_id_val,
            'total_cost', total_cost_val
        ));

        created_po_count := created_po_count + 1;
    END LOOP;

    RETURN created_po_count;
END;
$$ LANGUAGE plpgsql;
