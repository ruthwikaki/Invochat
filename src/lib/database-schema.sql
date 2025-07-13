
-- =================================================================
-- 1. Enable UUID extension for unique identifiers
-- =================================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;

-- =================================================================
-- 2. Define Helper Functions
-- =================================================================

-- Get the company ID from the current user's JWT claims.
CREATE OR REPLACE FUNCTION public.get_current_company_id()
RETURNS UUID AS $$
DECLARE
    company_id_claim UUID;
BEGIN
    SELECT current_setting('request.jwt.claims', true)::jsonb ->> 'company_id' INTO company_id_claim;
    RETURN company_id_claim;
END;
$$ LANGUAGE plpgsql STABLE;

-- Get the user role from the JWT claims.
CREATE OR REPLACE FUNCTION public.get_current_user_role()
RETURNS TEXT AS $$
DECLARE
    user_role_claim TEXT;
BEGIN
    SELECT current_setting('request.jwt.claims', true)::jsonb ->> 'role' INTO user_role_claim;
    RETURN user_role_claim;
END;
$$ LANGUAGE plpgsql STABLE;


-- =================================================================
-- 3. Create Core Tables
-- =================================================================

-- Companies Table
CREATE TABLE IF NOT EXISTS public.companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Users Table (bridges auth.users with app data)
CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email TEXT,
    role TEXT NOT NULL DEFAULT 'Member', -- 'Owner', 'Admin', or 'Member'
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Company-specific Settings
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id UUID PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days INT NOT NULL DEFAULT 90,
    overstock_multiplier INT NOT NULL DEFAULT 3,
    high_value_threshold INT NOT NULL DEFAULT 1000,
    fast_moving_days INT NOT NULL DEFAULT 30,
    predictive_stock_days INT NOT NULL DEFAULT 7,
    currency TEXT DEFAULT 'USD',
    timezone TEXT DEFAULT 'UTC',
    tax_rate NUMERIC DEFAULT 0,
    promo_sales_lift_multiplier REAL NOT NULL DEFAULT 2.5,
    custom_rules JSONB,
    subscription_status TEXT DEFAULT 'trial',
    subscription_plan TEXT DEFAULT 'starter',
    subscription_expires_at TIMESTAMPTZ,
    stripe_customer_id TEXT,
    stripe_subscription_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ
);

-- Integrations Table
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

-- Webhook Events (for security)
CREATE TABLE IF NOT EXISTS public.webhook_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id UUID NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id TEXT NOT NULL,
    processed_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE (integration_id, webhook_id)
);


-- =================================================================
-- 4. Product & Inventory Tables
-- =================================================================

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
    price INT, -- in cents
    compare_at_price INT, -- in cents
    cost INT, -- in cents
    inventory_quantity INT DEFAULT 0,
    weight REAL,
    weight_unit TEXT,
    external_variant_id TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, sku)
);

CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type TEXT NOT NULL, -- e.g., 'sale', 'restock', 'adjustment'
    quantity_change INT NOT NULL,
    new_quantity INT NOT NULL,
    related_id UUID, -- e.g., order_id, purchase_order_id
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- =================================================================
-- 5. Sales & Customer Tables
-- =================================================================

CREATE TABLE IF NOT EXISTS public.customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name TEXT NOT NULL,
    email TEXT,
    total_orders INT DEFAULT 0,
    total_spent INT DEFAULT 0,
    first_order_date DATE,
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE (company_id, email)
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
    subtotal INT DEFAULT 0,
    total_tax INT DEFAULT 0,
    total_shipping INT DEFAULT 0,
    total_discounts INT DEFAULT 0,
    total_amount INT NOT NULL,
    source_platform TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, external_order_id)
);

CREATE TABLE IF NOT EXISTS public.order_line_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id UUID REFERENCES public.product_variants(id),
    product_name TEXT,
    variant_title TEXT,
    sku TEXT,
    quantity INT NOT NULL,
    price INT NOT NULL,
    total_discount INT DEFAULT 0,
    cost_at_time INT,
    external_line_item_id TEXT
);


-- =================================================================
-- 6. Supplier & Purchasing Tables
-- =================================================================
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


-- =================================================================
-- 7. User Data & App State Tables
-- =================================================================

CREATE TABLE IF NOT EXISTS public.conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    last_accessed_at TIMESTAMPTZ DEFAULT now(),
    is_starred BOOLEAN DEFAULT false
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
    is_error BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now()
);


-- =================================================================
-- 8. Automation & User Management Triggers
-- =================================================================

-- Drop existing routines to prevent conflicts
DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;
DROP TRIGGER IF EXISTS on_new_user_created ON auth.users;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    new_company_id UUID;
    user_company_name TEXT;
BEGIN
    -- Extract company_name from metadata
    user_company_name := NEW.raw_app_meta_data->>'company_name';

    -- Create a new company for the user
    INSERT INTO public.companies (name)
    VALUES (COALESCE(user_company_name, 'My Company'))
    RETURNING id INTO new_company_id;

    -- Insert a corresponding entry into public.users
    INSERT INTO public.users (id, company_id, email, role)
    VALUES (NEW.id, new_company_id, NEW.email, 'Owner');

    -- Update the user's app_metadata with the new company_id and role
    UPDATE auth.users
    SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'role', 'Owner')
    WHERE id = NEW.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to call the function when a new user signs up
CREATE TRIGGER on_new_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_user();


-- =================================================================
-- 9. Row-Level Security (RLS) Policies
-- =================================================================

-- Helper procedure to create policies idempotently
DROP PROCEDURE IF EXISTS create_rls_policy(TEXT) CASCADE;
CREATE OR REPLACE PROCEDURE create_rls_policy(table_name_param TEXT)
LANGUAGE plpgsql AS $$
DECLARE
    policy_name TEXT;
BEGIN
    -- Enable RLS on the table if it's not already enabled
    IF NOT (SELECT relrowsecurity FROM pg_class WHERE relname = table_name_param) THEN
        EXECUTE 'ALTER TABLE ' || table_name_param || ' ENABLE ROW LEVEL SECURITY';
    END IF;

    -- Drop and create the policy
    policy_name := 'rls_user_company_policy';
    EXECUTE 'DROP POLICY IF EXISTS ' || policy_name || ' ON ' || table_name_param;
    EXECUTE 'CREATE POLICY ' || policy_name || ' ON ' || table_name_param || ' FOR ALL USING (company_id = get_current_company_id()) WITH CHECK (company_id = get_current_company_id())';
END;
$$;


-- Apply RLS to all company-scoped tables
CALL create_rls_policy('companies');
CALL create_rls_policy('users');
CALL create_rls_policy('company_settings');
CALL create_rls_policy('integrations');
CALL create_rls_policy('products');
CALL create_rls_policy('product_variants');
CALL create_rls_policy('inventory_ledger');
CALL create_rls_policy('customers');
CALL create_rls_policy('orders');
CALL create_rls_policy('order_line_items');
CALL create_rls_policy('suppliers');
CALL create_rls_policy('conversations');
CALL create_rls_policy('messages');


-- Special RLS for webhook_events (checks via integrations table)
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS rls_webhook_events_policy ON public.webhook_events;
CREATE POLICY rls_webhook_events_policy ON public.webhook_events
FOR ALL
USING ((SELECT company_id FROM public.integrations WHERE id = webhook_events.integration_id) = get_current_company_id());


-- Special RLS for customer_addresses (checks via customers table)
ALTER TABLE public.customer_addresses ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS rls_customer_addresses_policy ON public.customer_addresses;
CREATE POLICY rls_customer_addresses_policy ON public.customer_addresses
FOR ALL
USING (
    (SELECT company_id FROM public.customers WHERE id = customer_addresses.customer_id) = get_current_company_id()
);


-- =================================================================
-- 10. Performance Indexes
-- =================================================================

CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_company_id ON public.product_variants(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON public.orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers(company_id);
CREATE INDEX IF NOT EXISTS idx_ledger_variant_id ON public.inventory_ledger(variant_id);

-- Final script completion message
SELECT 'InvoChat Database Schema setup complete.';
