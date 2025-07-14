
-- =================================================================
-- 1. EXTENSIONS
-- =================================================================
-- Enable pgcrypto for gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;

-- = a new "dead stock report" feature we'll add
-- CREATE EXTENSION IF NOT EXISTS tablefunc;

-- =================================================================
-- 2. HELPER FUNCTIONS
-- =================================================================

-- Function to get the current user's company_id from their profile
-- This is used in all RLS policies to ensure data isolation.
CREATE OR REPLACE FUNCTION public.get_current_company_id()
RETURNS UUID AS $$
DECLARE
    company_id_val UUID;
BEGIN
    SELECT company_id INTO company_id_val
    FROM public.profiles
    WHERE user_id = auth.uid();
    RETURN company_id_val;
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

-- =================================================================
-- 3. TABLE DEFINITIONS
-- =================================================================

-- Companies Table
CREATE TABLE IF NOT EXISTS public.companies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() at time zone 'utc')
);

-- Profiles Table (stores user-specific app data)
CREATE TABLE IF NOT EXISTS public.profiles (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    first_name TEXT,
    last_name TEXT,
    role TEXT NOT NULL DEFAULT 'Member', -- e.g., 'Owner', 'Admin', 'Member'
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() at time zone 'utc'),
    updated_at TIMESTAMPTZ
);

-- Company Settings Table
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id UUID PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days INT NOT NULL DEFAULT 90,
    fast_moving_days INT NOT NULL DEFAULT 30,
    predictive_stock_days INT NOT NULL DEFAULT 7,
    overstock_multiplier INT NOT NULL DEFAULT 3,
    high_value_threshold INT NOT NULL DEFAULT 100000, -- in cents
    promo_sales_lift_multiplier REAL NOT NULL DEFAULT 2.5,
    currency TEXT DEFAULT 'USD',
    timezone TEXT DEFAULT 'UTC',
    tax_rate NUMERIC DEFAULT 0,
    custom_rules JSONB,
    subscription_plan TEXT DEFAULT 'starter',
    subscription_status TEXT DEFAULT 'trial',
    subscription_expires_at TIMESTAMPTZ,
    stripe_customer_id TEXT,
    stripe_subscription_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() at time zone 'utc'),
    updated_at TIMESTAMPTZ
);

-- Locations Table (for warehouses, stores, etc.)
CREATE TABLE IF NOT EXISTS public.locations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    address TEXT,
    is_default BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() at time zone 'utc'),
    updated_at TIMESTAMPTZ
);

-- Products Table
CREATE TABLE IF NOT EXISTS public.products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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

-- Product Variants Table
CREATE TABLE IF NOT EXISTS public.product_variants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    location_id UUID REFERENCES public.locations(id) ON DELETE SET NULL,
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
    external_variant_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() at time zone 'utc'),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, sku),
    UNIQUE(company_id, external_variant_id)
);

-- Customers Table
CREATE TABLE IF NOT EXISTS public.customers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name TEXT,
    email TEXT,
    total_orders INT DEFAULT 0,
    total_spent INT DEFAULT 0, -- in cents
    first_order_date DATE,
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT (now() at time zone 'utc')
);

-- Orders Table
CREATE TABLE IF NOT EXISTS public.orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number TEXT NOT NULL,
    external_order_id TEXT,
    customer_id UUID REFERENCES public.customers(id),
    financial_status TEXT,
    fulfillment_status TEXT,
    currency TEXT,
    subtotal INT NOT NULL, -- in cents
    total_tax INT, -- in cents
    total_shipping INT, -- in cents
    total_discounts INT, -- in cents
    total_amount INT NOT NULL, -- in cents
    source_platform TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() at time zone 'utc'),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, external_order_id)
);

-- Order Line Items Table
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id UUID REFERENCES public.product_variants(id),
    product_name TEXT,
    variant_title TEXT,
    sku TEXT,
    quantity INT NOT NULL,
    price INT NOT NULL, -- in cents
    total_discount INT, -- in cents
    tax_amount INT, -- in cents
    cost_at_time INT, -- in cents
    external_line_item_id TEXT
);

-- Suppliers Table
CREATE TABLE IF NOT EXISTS public.suppliers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    default_lead_time_days INT,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() at time zone 'utc'),
    updated_at TIMESTAMPTZ
);

-- Purchase Orders Table
CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id UUID REFERENCES public.suppliers(id),
    status TEXT NOT NULL DEFAULT 'Draft',
    po_number TEXT NOT NULL,
    total_cost INT NOT NULL, -- in cents
    expected_arrival_date DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() at time zone 'utc')
);

-- Purchase Order Line Items Table
CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    purchase_order_id UUID NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id),
    quantity INT NOT NULL,
    cost INT NOT NULL -- in cents
);

-- Inventory Ledger Table
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    location_id UUID REFERENCES public.locations(id) ON DELETE SET NULL,
    change_type TEXT NOT NULL, -- e.g., 'sale', 'purchase_order', 'reconciliation', 'manual_adjustment'
    quantity_change INT NOT NULL,
    new_quantity INT NOT NULL,
    related_id UUID, -- e.g., order_id, purchase_order_id
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() at time zone 'utc')
);

-- Conversations Table
CREATE TABLE IF NOT EXISTS public.conversations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT (now() at time zone 'utc'),
    last_accessed_at TIMESTAMPTZ DEFAULT (now() at time zone 'utc'),
    is_starred BOOLEAN DEFAULT false
);

-- Messages Table
CREATE TABLE IF NOT EXISTS public.messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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
    created_at TIMESTAMPTZ DEFAULT (now() at time zone 'utc')
);

-- Integrations Table
CREATE TABLE IF NOT EXISTS public.integrations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform TEXT NOT NULL,
    shop_domain TEXT,
    shop_name TEXT,
    is_active BOOLEAN DEFAULT false,
    last_sync_at TIMESTAMPTZ,
    sync_status TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() at time zone 'utc'),
    updated_at TIMESTAMPTZ
);

-- Audit Log Table
CREATE TABLE IF NOT EXISTS public.audit_log (
    id BIGSERIAL PRIMARY KEY,
    company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    details JSONB,
    created_at TIMESTAMPTZ DEFAULT (now() at time zone 'utc')
);

-- Webhook Events Table (for replay protection)
CREATE TABLE IF NOT EXISTS public.webhook_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id UUID NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id TEXT NOT NULL,
    processed_at TIMESTAMPTZ DEFAULT (now() at time zone 'utc'),
    created_at TIMESTAMPTZ DEFAULT (now() at time zone 'utc'),
    UNIQUE(integration_id, webhook_id)
);


-- =================================================================
-- 4. DATABASE TRIGGERS
-- =================================================================

-- Trigger to create a company and profile when a new user signs up
CREATE OR REPLACE FUNCTION public.on_auth_user_created()
RETURNS TRIGGER AS $$
DECLARE
    new_company_id UUID;
    user_company_name TEXT;
BEGIN
    -- Extract company name from metadata, default if not provided
    user_company_name := NEW.raw_user_meta_data->>'company_name';
    IF user_company_name IS NULL OR user_company_name = '' THEN
        user_company_name := NEW.email || '''s Company';
    END IF;

    -- Create a new company for the user
    INSERT INTO public.companies (name)
    VALUES (user_company_name)
    RETURNING id INTO new_company_id;

    -- Create a profile for the new user, linking them to the new company as 'Owner'
    INSERT INTO public.profiles (user_id, company_id, first_name, last_name, role)
    VALUES (NEW.id, new_company_id, NEW.raw_user_meta_data->>'first_name', NEW.raw_user_meta_data->>'last_name', 'Owner');
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop the trigger if it exists before creating it
DROP TRIGGER IF EXISTS on_auth_user_created_trigger ON auth.users;
CREATE TRIGGER on_auth_user_created_trigger
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.on_auth_user_created();


-- Function to apply the set_updated_at trigger to a list of tables
CREATE OR REPLACE FUNCTION public.apply_updated_at_trigger(tables TEXT[])
RETURNS VOID AS $$
DECLARE
    tbl TEXT;
BEGIN
    FOREACH tbl IN ARRAY tables
    LOOP
        -- Drop the trigger if it already exists for the table
        EXECUTE format('DROP TRIGGER IF EXISTS handle_updated_at ON public.%I;', tbl);
        -- Create the trigger
        EXECUTE format('
            CREATE TRIGGER handle_updated_at
            BEFORE UPDATE ON public.%I
            FOR EACH ROW
            EXECUTE FUNCTION public.set_updated_at();
        ', tbl);
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Apply the updated_at trigger to all relevant tables
SELECT public.apply_updated_at_trigger(ARRAY[
    'profiles',
    'company_settings',
    'products',
    'product_variants',
    'orders',
    'suppliers',
    'integrations',
    'locations'
]);

-- =================================================================
-- 5. ROW LEVEL SECURITY (RLS) POLICIES
-- =================================================================

-- Function to apply a standard RLS policy to a list of tables
CREATE OR REPLACE FUNCTION public.apply_rls_policy(tables TEXT[])
RETURNS VOID AS $$
DECLARE
    tbl TEXT;
BEGIN
    FOREACH tbl IN ARRAY tables
    LOOP
        -- Enable RLS for the table
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', tbl);
        -- Drop existing policy to ensure idempotency
        EXECUTE format('DROP POLICY IF EXISTS "Users can only see their own company''s data." ON public.%I;', tbl);
        -- Create the policy
        EXECUTE format('
            CREATE POLICY "Users can only see their own company''s data."
            ON public.%I
            FOR ALL
            USING (company_id = public.get_current_company_id())
            WITH CHECK (company_id = public.get_current_company_id());
        ', tbl);
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Apply the standard RLS policy to all company-isolated tables
SELECT public.apply_rls_policy(ARRAY[
    'company_settings',
    'products',
    'product_variants',
    'customers',
    'orders',
    'order_line_items',
    'suppliers',
    'conversations',
    'messages',
    'integrations',
    'inventory_ledger',
    'purchase_orders',
    'purchase_order_line_items',
    'locations',
    'audit_log',
    'webhook_events'
]);


-- Special RLS Policies

-- For companies table
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can only see their own company." ON public.companies;
CREATE POLICY "Users can only see their own company."
ON public.companies
FOR SELECT
USING (id = public.get_current_company_id());

-- For profiles table
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can see other users in their own company." ON public.profiles;
CREATE POLICY "Users can see other users in their own company."
ON public.profiles
FOR SELECT
USING (company_id = public.get_current_company_id());


-- =================================================================
-- 6. VIEWS
-- =================================================================

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
    pv.external_variant_id,
    pv.created_at,
    pv.updated_at,
    p.title AS product_title,
    p.status AS product_status,
    p.image_url,
    p.product_type,
    p.tags,
    pv.location_id,
    l.name as location_name
FROM
    public.product_variants pv
LEFT JOIN
    public.products p ON pv.product_id = p.id
LEFT JOIN
    public.locations l ON pv.location_id = l.id;

-- =================================================================
-- 7. INDEXES
-- =================================================================

-- Indexes for foreign keys to improve join performance
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_company_id ON public.product_variants(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_location_id ON public.product_variants(location_id);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON public.orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON public.order_line_items(variant_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id ON public.inventory_ledger(variant_id);
CREATE INDEX IF NOT EXISTS idx_profiles_company_id ON public.profiles(company_id);

-- Indexes for frequently filtered columns
CREATE INDEX IF NOT EXISTS idx_product_variants_sku ON public.product_variants(sku);
CREATE INDEX IF NOT EXISTS idx_products_title_trgm ON public.products USING gin (title gin_trgm_ops); -- For faster text search
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON public.orders(created_at DESC);


-- =================================================================
-- 8. RPC FUNCTIONS
-- =================================================================

CREATE OR REPLACE FUNCTION public.record_order_from_platform(p_company_id UUID, p_order_payload JSONB, p_platform TEXT)
RETURNS VOID AS $$
DECLARE
    v_customer_id UUID;
    v_order_id UUID;
    v_variant_id UUID;
    line_item JSONB;
BEGIN
    -- Find or create the customer record
    SELECT id INTO v_customer_id
    FROM public.customers
    WHERE email = p_order_payload->'customer'->>'email' AND company_id = p_company_id;

    IF v_customer_id IS NULL THEN
        INSERT INTO public.customers (company_id, customer_name, email, first_order_date)
        VALUES (
            p_company_id,
            p_order_payload->'customer'->>'first_name' || ' ' || p_order_payload->'customer'->>'last_name',
            p_order_payload->'customer'->>'email',
            (p_order_payload->>'created_at')::DATE
        ) RETURNING id INTO v_customer_id;
    END IF;

    -- Insert or update the order
    INSERT INTO public.orders (
        company_id, order_number, external_order_id, customer_id, financial_status, fulfillment_status,
        currency, subtotal, total_tax, total_shipping, total_discounts, total_amount, source_platform, created_at
    )
    VALUES (
        p_company_id,
        p_order_payload->>'order_number',
        p_order_payload->>'id',
        v_customer_id,
        p_order_payload->>'financial_status',
        p_order_payload->>'fulfillment_status',
        p_order_payload->>'currency',
        (p_order_payload->>'subtotal_price')::NUMERIC * 100,
        (p_order_payload->>'total_tax')::NUMERIC * 100,
        (p_order_payload->'total_shipping_price_set'->'shop_money'->>'amount')::NUMERIC * 100,
        (p_order_payload->>'total_discounts')::NUMERIC * 100,
        (p_order_payload->>'total_price')::NUMERIC * 100,
        p_platform,
        (p_order_payload->>'created_at')::TIMESTAMPTZ
    )
    ON CONFLICT (company_id, external_order_id) DO UPDATE SET
        financial_status = EXCLUDED.financial_status,
        fulfillment_status = EXCLUDED.fulfillment_status,
        updated_at = (now() at time zone 'utc')
    RETURNING id INTO v_order_id;
    
    -- Insert line items
    FOR line_item IN SELECT * FROM jsonb_array_elements(p_order_payload->'line_items')
    LOOP
        -- Find the corresponding product variant using external ID
        SELECT id INTO v_variant_id
        FROM public.product_variants
        WHERE external_variant_id = line_item->>'variant_id' AND company_id = p_company_id;

        -- Insert line item
        INSERT INTO public.order_line_items (
            order_id, company_id, variant_id, product_name, variant_title, sku, quantity, price, total_discount
        )
        VALUES (
            v_order_id,
            p_company_id,
            v_variant_id,
            line_item->>'title',
            line_item->>'variant_title',
            line_item->>'sku',
            (line_item->>'quantity')::INT,
            (line_item->>'price')::NUMERIC * 100,
            (line_item->>'total_discount')::NUMERIC * 100
        );

        -- Decrement inventory (if variant was found)
        IF v_variant_id IS NOT NULL THEN
            UPDATE public.product_variants
            SET inventory_quantity = inventory_quantity - (line_item->>'quantity')::INT
            WHERE id = v_variant_id;
        END IF;
    END LOOP;

END;
$$ LANGUAGE plpgsql;

-- Final cleanup of old/incorrect function names just in case they exist
DROP FUNCTION IF EXISTS public.handle_new_user();

