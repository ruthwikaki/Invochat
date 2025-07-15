-- ### Extensions ###
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ### Schemas ###
-- Schemas are created by Supabase automatically. We just enable RLS.

-- ### Custom Types ###
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE user_role AS ENUM ('Owner', 'Admin', 'Member');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'integration_platform') THEN
        CREATE TYPE integration_platform AS ENUM ('shopify', 'woocommerce', 'amazon_fba');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'sync_status_type') THEN
        CREATE TYPE sync_status_type AS ENUM ('idle', 'syncing', 'success', 'failed');
    END IF;
END$$;


-- ### Tables ###

-- Company & User Management
CREATE TABLE IF NOT EXISTS public.companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email TEXT,
    role user_role NOT NULL DEFAULT 'Member',
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id UUID PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days INT NOT NULL DEFAULT 90,
    fast_moving_days INT NOT NULL DEFAULT 30,
    overstock_multiplier INT NOT NULL DEFAULT 3,
    high_value_threshold INT NOT NULL DEFAULT 1000, -- in cents
    predictive_stock_days INT NOT NULL DEFAULT 7,
    currency TEXT DEFAULT 'USD',
    timezone TEXT DEFAULT 'UTC',
    tax_rate NUMERIC DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ
);
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;


-- Core Inventory Tables
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
    external_variant_id TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, sku),
    UNIQUE(company_id, external_variant_id)
);
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;


-- Orders, Customers, and Sales
CREATE TABLE IF NOT EXISTS public.customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name TEXT,
    email TEXT,
    total_orders INT DEFAULT 0,
    total_spent INT DEFAULT 0, -- in cents
    first_order_date DATE,
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number TEXT NOT NULL,
    external_order_id TEXT,
    customer_id UUID REFERENCES public.customers(id),
    financial_status TEXT,
    fulfillment_status TEXT,
    currency TEXT,
    subtotal INT NOT NULL DEFAULT 0, -- in cents
    total_tax INT DEFAULT 0, -- in cents
    total_shipping INT DEFAULT 0, -- in cents
    total_discounts INT DEFAULT 0, -- in cents
    total_amount INT NOT NULL, -- in cents
    source_platform TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ
);
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

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
    total_discount INT, -- in cents
    tax_amount INT, -- in cents
    cost_at_time INT, -- in cents
    external_line_item_id TEXT
);
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;


-- Suppliers & Purchasing
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

CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id UUID REFERENCES public.suppliers(id),
    status TEXT NOT NULL DEFAULT 'Draft',
    po_number TEXT NOT NULL,
    total_cost INT NOT NULL, -- in cents
    expected_arrival_date DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    idempotency_key UUID UNIQUE
);
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    purchase_order_id UUID NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id),
    quantity INT NOT NULL,
    cost INT NOT NULL -- in cents
);
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;


-- History & Logging
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    variant_id UUID NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    change_type TEXT NOT NULL,
    quantity_change INT NOT NULL,
    new_quantity INT NOT NULL,
    related_id UUID,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.audit_log (
    id BIGSERIAL PRIMARY KEY,
    company_id UUID REFERENCES public.companies(id),
    user_id UUID REFERENCES auth.users(id),
    action TEXT NOT NULL,
    details JSONB,
    created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;


-- Integrations & Chat
CREATE TABLE IF NOT EXISTS public.integrations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform integration_platform NOT NULL,
    shop_domain TEXT,
    shop_name TEXT,
    is_active BOOLEAN DEFAULT false,
    last_sync_at TIMESTAMPTZ,
    sync_status sync_status_type,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ
);
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    last_accessed_at TIMESTAMPTZ DEFAULT now(),
    is_starred BOOLEAN DEFAULT false
);
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role TEXT NOT NULL,
    content TEXT,
    visualization JSONB,
    component TEXT,
    component_props JSONB,
    confidence NUMERIC,
    assumptions TEXT[],
    is_error BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.webhook_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id UUID NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id TEXT NOT NULL,
    processed_at TIMESTAMPTZ DEFAULT now(),
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(integration_id, webhook_id) -- Prevents replay attacks
);
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;


-- ### Helper Functions (Security-focused) ###

-- Securely get the user's company ID from the users table, not the JWT
CREATE OR REPLACE FUNCTION get_my_company_id()
RETURNS UUID AS $$
BEGIN
    RETURN (SELECT company_id FROM public.users WHERE id = auth.uid());
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get user's role securely
CREATE OR REPLACE FUNCTION get_my_role()
RETURNS TEXT AS $$
DECLARE
    user_role TEXT;
BEGIN
    SELECT role INTO user_role FROM public.users WHERE id = auth.uid();
    RETURN user_role;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ### Row-Level Security (RLS) Policies ###

-- Policies for tables with a direct company_id column
CREATE OR REPLACE PROCEDURE create_rls_policy_for_table(table_name TEXT)
LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE format('DROP POLICY IF EXISTS "Users can only access their own company data" ON public.%I;', table_name);
    EXECUTE format('CREATE POLICY "Users can only access their own company data" ON public.%I FOR ALL USING (company_id = get_my_company_id());', table_name);
END;
$$;

CALL create_rls_policy_for_table('companies');
CALL create_rls_policy_for_table('users');
CALL create_rls_policy_for_table('company_settings');
CALL create_rls_policy_for_table('products');
CALL create_rls_policy_for_table('product_variants');
CALL create_rls_policy_for_table('customers');
CALL create_rls_policy_for_table('orders');
CALL create_rls_policy_for_table('order_line_items');
CALL create_rls_policy_for_table('suppliers');
CALL create_rls_policy_for_table('purchase_orders');
CALL create_rls_policy_for_table('purchase_order_line_items');
CALL create_rls_policy_for_table('inventory_ledger');
CALL create_rls_policy_for_table('audit_log');
CALL create_rls_policy_for_table('integrations');
CALL create_rls_policy_for_table('conversations');
CALL create_rls_policy_for_table('messages');
CALL create_rls_policy_for_table('webhook_events');


-- ### Views ###

-- Drop view if it exists to allow table modifications, then recreate it.
DROP VIEW IF EXISTS public.product_variants_with_details;

CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.*,
    p.title as product_title,
    p.status as product_status,
    p.image_url as image_url,
    p.product_type
FROM public.product_variants pv
JOIN public.products p ON pv.product_id = p.id;


-- ### Indexes ###

-- Create indexes if they don't exist for performance
CREATE INDEX IF NOT EXISTS idx_users_company_id ON public.users(company_id);
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_company_id ON public.product_variants(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_sku ON public.product_variants(sku);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON public.orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON public.order_line_items(variant_id);
CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON public.suppliers(company_id);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_company_id ON public.purchase_orders(company_id);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_supplier_id ON public.purchase_orders(supplier_id);
CREATE INDEX IF NOT EXISTS idx_po_line_items_po_id ON public.purchase_order_line_items(purchase_order_id);
CREATE INDEX IF NOT EXISTS idx_po_line_items_variant_id ON public.purchase_order_line_items(variant_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id ON public.inventory_ledger(variant_id);
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers(company_id);
CREATE INDEX IF NOT EXISTS idx_customers_email ON public.customers(email);


-- ### Functions for Business Logic ###

-- Function to create a new company and associate the creating user as 'Owner'
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    v_company_id UUID;
BEGIN
    -- Create a new company
    INSERT INTO public.companies (name)
    VALUES (new.raw_user_meta_data->>'company_name')
    RETURNING id INTO v_company_id;

    -- Create a corresponding user entry
    INSERT INTO public.users (id, company_id, email, role)
    VALUES (new.id, v_company_id, new.email, 'Owner');
    
    -- Update the user's app_metadata with the company_id and role
    -- This is the only place we should be writing to app_metadata
    UPDATE auth.users
    SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', v_company_id, 'role', 'Owner')
    WHERE id = new.id;

    RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ### Triggers ###

-- Drop trigger if it exists to prevent errors on re-run
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Trigger to create a company for a new user upon signup
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Record sale and update inventory atomically
CREATE OR REPLACE FUNCTION public.record_sale_transaction(
    p_company_id UUID,
    p_user_id UUID,
    p_customer_name TEXT,
    p_customer_email TEXT,
    p_payment_method TEXT,
    p_notes TEXT,
    p_sale_items JSONB[],
    p_external_id TEXT DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    v_customer_id UUID;
    v_order_id UUID;
    v_total_amount INT := 0;
    item JSONB;
    v_variant_id UUID;
    v_current_stock INT;
BEGIN
    -- Find or create customer
    SELECT id INTO v_customer_id FROM public.customers WHERE email = p_customer_email AND company_id = p_company_id;
    IF v_customer_id IS NULL THEN
        INSERT INTO public.customers (company_id, customer_name, email)
        VALUES (p_company_id, p_customer_name, p_customer_email)
        RETURNING id INTO v_customer_id;
    END IF;

    -- Calculate total order amount
    FOREACH item IN ARRAY p_sale_items
    LOOP
        v_total_amount := v_total_amount + (item->>'quantity')::INT * (item->>'unit_price')::INT;
    END LOOP;

    -- Create the order
    INSERT INTO public.orders (company_id, order_number, customer_id, total_amount, source_platform, external_order_id, notes)
    VALUES (p_company_id, 'ORD-' || nextval('orders_order_number_seq'), v_customer_id, v_total_amount, p_payment_method, p_external_id, p_notes)
    RETURNING id INTO v_order_id;

    -- Process line items and update inventory
    FOREACH item IN ARRAY p_sale_items
    LOOP
        -- Find variant by SKU
        SELECT id INTO v_variant_id FROM public.product_variants WHERE sku = (item->>'sku') AND company_id = p_company_id;

        IF v_variant_id IS NULL THEN
            RAISE EXCEPTION 'Variant with SKU % not found', item->>'sku';
        END IF;

        -- Lock the variant row to prevent race conditions
        SELECT inventory_quantity INTO v_current_stock FROM public.product_variants WHERE id = v_variant_id FOR UPDATE;

        -- Update inventory quantity
        UPDATE public.product_variants
        SET inventory_quantity = inventory_quantity - (item->>'quantity')::INT
        WHERE id = v_variant_id;

        -- Insert order line item
        INSERT INTO public.order_line_items (order_id, variant_id, company_id, product_name, quantity, price, cost_at_time)
        VALUES (v_order_id, v_variant_id, p_company_id, item->>'product_name', (item->>'quantity')::INT, (item->>'unit_price')::INT, (item->>'cost_at_time')::INT);

        -- Log the inventory change
        INSERT INTO public.inventory_ledger (variant_id, company_id, change_type, quantity_change, new_quantity, related_id, notes)
        VALUES (v_variant_id, p_company_id, 'sale', -(item->>'quantity')::INT, v_current_stock - (item->>'quantity')::INT, v_order_id, 'Order ' || p_external_id);
    END LOOP;

    RETURN v_order_id;
END;
$$ LANGUAGE plpgsql;

-- Final check to ensure RLS is enabled on all tables in public schema
DO $$
DECLARE
    t_name TEXT;
BEGIN
    FOR t_name IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public')
    LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', t_name);
    END LOOP;
END;
$$;
