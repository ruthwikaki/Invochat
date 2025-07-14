-- InvoChat Database Schema
-- Version: 1.5
-- Description: This script sets up the entire database schema for InvoChat,
-- including tables, roles, functions, RLS policies, and triggers.
-- It is designed to be idempotent and can be run multiple times safely.

--
-- ==== 1. Extensions ====
--
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "moddatetime"; -- For the moddatetime_updated_at trigger function

--
-- ==== 2. Helper Functions ====
-- These functions are used by RLS policies to get the current user's context.
--

-- Get the company ID of the currently authenticated user
CREATE OR REPLACE FUNCTION get_current_company_id()
RETURNS uuid AS $$
DECLARE
    company_id_val uuid;
BEGIN
    company_id_val := current_setting('request.jwt.claims', true)::jsonb ->> 'company_id';
    IF company_id_val IS NULL THEN
        -- Fallback for service roles or other scenarios where company_id isn't in the JWT
        -- This part might need adjustment based on your specific non-user session handling
        -- For now, returning NULL will deny access for policies that use this function.
        RETURN NULL;
    END IF;
    RETURN company_id_val;
EXCEPTION
    -- Catch exceptions if the setting is not available, returning NULL.
    WHEN others THEN
        RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get the user ID of the currently authenticated user
CREATE OR REPLACE FUNCTION get_current_user_id()
RETURNS uuid AS $$
BEGIN
    return auth.uid();
EXCEPTION
    WHEN others THEN
        return null;
END;
$$ LANGUAGE plpgsql;


--
-- ==== 3. Table Definitions ====
--

-- Companies Table
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    name TEXT NOT NULL,
    created_at timestamptz DEFAULT (now() at time zone 'utc')
);
COMMENT ON TABLE public.companies IS 'Stores information about each company or organization using the app.';

-- Users Table
-- Supabase handles this via auth.users, but we add a public view for RLS.
-- Add custom user attributes to the auth.users table
ALTER TABLE auth.users
  ADD COLUMN IF NOT EXISTS company_id uuid REFERENCES public.companies(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS role TEXT;

-- We create a view for easier querying within RLS policies.
CREATE OR REPLACE VIEW public.users AS
SELECT id, aud, role, email, last_sign_in_at, company_id
FROM auth.users;

-- Company Settings Table
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days INT NOT NULL DEFAULT 90,
    fast_moving_days INT NOT NULL DEFAULT 30,
    overstock_multiplier NUMERIC NOT NULL DEFAULT 3.0,
    high_value_threshold INT NOT NULL DEFAULT 100000, -- in cents
    predictive_stock_days INT NOT NULL DEFAULT 7,
    created_at timestamptz DEFAULT (now() at time zone 'utc'),
    updated_at timestamptz
);
COMMENT ON TABLE public.company_settings IS 'Stores business logic parameters for each company.';

-- Products Table
CREATE TABLE IF NOT EXISTS public.products (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    handle TEXT,
    product_type TEXT,
    tags TEXT[],
    status TEXT,
    image_url TEXT,
    external_product_id TEXT, -- The ID from the external platform (e.g., Shopify)
    created_at timestamptz DEFAULT (now() at time zone 'utc'),
    updated_at timestamptz,
    UNIQUE(company_id, external_product_id)
);
COMMENT ON TABLE public.products IS 'Stores core product information.';

-- Product Variants Table
CREATE TABLE IF NOT EXISTS public.product_variants (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
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
    location_id uuid, -- Foreign key will be added after locations table
    created_at timestamptz DEFAULT (now() at time zone 'utc'),
    updated_at timestamptz,
    UNIQUE(company_id, external_variant_id),
    UNIQUE(company_id, sku)
);
COMMENT ON TABLE public.product_variants IS 'Stores individual product variants (SKUs).';

-- Locations Table
CREATE TABLE IF NOT EXISTS public.locations (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    is_default BOOLEAN DEFAULT FALSE,
    created_at timestamptz DEFAULT (now() at time zone 'utc'),
    updated_at timestamptz,
    UNIQUE(company_id, name)
);
COMMENT ON TABLE public.locations IS 'Stores warehouse or stock locations.';

-- Add the foreign key constraint now that the locations table exists
ALTER TABLE public.product_variants
    ADD CONSTRAINT fk_location
    FOREIGN KEY (location_id)
    REFERENCES public.locations(id)
    ON DELETE SET NULL;

-- Inventory Ledger Table
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    location_id uuid REFERENCES public.locations(id) ON DELETE SET NULL,
    change_type TEXT NOT NULL, -- e.g., 'sale', 'purchase_order', 'reconciliation', 'transfer_in', 'transfer_out'
    quantity_change INT NOT NULL,
    new_quantity INT NOT NULL,
    related_id uuid, -- ID of the related order, PO, etc.
    notes TEXT,
    created_at timestamptz DEFAULT (now() at time zone 'utc')
);
COMMENT ON TABLE public.inventory_ledger IS 'Records every stock movement for full auditability.';

-- Customers Table
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name TEXT,
    email TEXT,
    total_orders INT DEFAULT 0,
    total_spent INT DEFAULT 0, -- in cents
    first_order_date DATE,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT (now() at time zone 'utc'),
    updated_at timestamptz,
    UNIQUE(company_id, email)
);
COMMENT ON TABLE public.customers IS 'Stores customer information.';

-- Orders Table
CREATE TABLE IF NOT EXISTS public.orders (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number TEXT NOT NULL,
    external_order_id TEXT,
    customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
    financial_status TEXT,
    fulfillment_status TEXT,
    currency TEXT,
    subtotal INT NOT NULL, -- in cents
    total_tax INT, -- in cents
    total_shipping INT, -- in cents
    total_discounts INT, -- in cents
    total_amount INT NOT NULL, -- in cents
    source_platform TEXT,
    created_at timestamptz DEFAULT (now() at time zone 'utc'),
    updated_at timestamptz,
    UNIQUE(company_id, external_order_id)
);
COMMENT ON TABLE public.orders IS 'Stores sales order information.';

-- Order Line Items Table
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id uuid REFERENCES public.product_variants(id) ON DELETE SET NULL,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_name TEXT,
    variant_title TEXT,
    sku TEXT,
    quantity INT NOT NULL,
    price INT NOT NULL, -- in cents
    total_discount INT, -- in cents
    tax_amount INT, -- in cents
    cost_at_time INT, -- cost of goods at the time of sale, in cents
    external_line_item_id TEXT
);
COMMENT ON TABLE public.order_line_items IS 'Stores individual items within a sales order.';

-- Suppliers Table
CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    default_lead_time_days INT,
    notes TEXT,
    created_at timestamptz DEFAULT (now() at time zone 'utc'),
    updated_at timestamptz,
    UNIQUE(company_id, name)
);
COMMENT ON TABLE public.suppliers IS 'Stores supplier/vendor information.';

-- Integrations Table
CREATE TABLE IF NOT EXISTS public.integrations (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform TEXT NOT NULL, -- 'shopify', 'woocommerce', etc.
    shop_domain TEXT,
    shop_name TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    last_sync_at timestamptz,
    sync_status TEXT,
    created_at timestamptz DEFAULT (now() at time zone 'utc'),
    updated_at timestamptz,
    UNIQUE(company_id, platform)
);
COMMENT ON TABLE public.integrations IS 'Stores configuration for third-party integrations.';

-- Webhook Events Table
CREATE TABLE IF NOT EXISTS public.webhook_events (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id TEXT NOT NULL,
    received_at timestamptz DEFAULT (now() at time zone 'utc'),
    UNIQUE(integration_id, webhook_id)
);
COMMENT ON TABLE public.webhook_events IS 'Stores webhook IDs to prevent replay attacks.';

-- Audit Log Table
CREATE TABLE IF NOT EXISTS public.audit_log (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id uuid, -- Can be null for system actions
    action TEXT NOT NULL, -- e.g., 'user_login', 'po_created'
    details jsonb,
    created_at timestamptz DEFAULT (now() at time zone 'utc')
);
COMMENT ON TABLE public.audit_log IS 'Records important actions for security and compliance.';


-- AI-related tables
-- Conversations Table
CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    created_at timestamptz DEFAULT (now() at time zone 'utc'),
    last_accessed_at timestamptz DEFAULT (now() at time zone 'utc'),
    is_starred BOOLEAN DEFAULT FALSE
);
COMMENT ON TABLE public.conversations IS 'Stores AI chat conversation threads.';

-- Messages Table
CREATE TABLE IF NOT EXISTS public.messages (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
    content TEXT NOT NULL,
    visualization jsonb,
    confidence REAL,
    assumptions TEXT[],
    component TEXT,
    componentProps jsonb,
    isError BOOLEAN DEFAULT FALSE,
    created_at timestamptz DEFAULT (now() at time zone 'utc')
);
COMMENT ON TABLE public.messages IS 'Stores individual messages within a conversation.';


--
-- ==== 4. Indexes ====
-- Create indexes for frequently queried columns to improve performance.
--

CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_sku ON public.product_variants(sku);
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers(company_id);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON public.orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON public.order_line_items(variant_id);
CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON public.suppliers(company_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id ON public.inventory_ledger(variant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_company_id ON public.audit_log(company_id);
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id ON public.messages(conversation_id);


--
-- ==== 5. Row-Level Security (RLS) ====
--

-- Enable RLS for all tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;


-- Policies
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.companies;
CREATE POLICY "Allow full access based on company_id"
    ON public.companies FOR ALL
    USING (id = get_current_company_id())
    WITH CHECK (id = get_current_company_id());

DROP POLICY IF EXISTS "Allow read access to other users in same company" ON public.users;
CREATE POLICY "Allow read access to other users in same company"
    ON public.users FOR SELECT
    USING (company_id = get_current_company_id());

DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.company_settings;
CREATE POLICY "Allow full access based on company_id"
    ON public.company_settings FOR ALL
    USING (company_id = get_current_company_id())
    WITH CHECK (company_id = get_current_company_id());

DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.products;
CREATE POLICY "Allow full access based on company_id"
    ON public.products FOR ALL
    USING (company_id = get_current_company_id())
    WITH CHECK (company_id = get_current_company_id());

DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.product_variants;
CREATE POLICY "Allow full access based on company_id"
    ON public.product_variants FOR ALL
    USING (company_id = get_current_company_id())
    WITH CHECK (company_id = get_current_company_id());

DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.locations;
CREATE POLICY "Allow full access based on company_id"
    ON public.locations FOR ALL
    USING (company_id = get_current_company_id())
    WITH CHECK (company_id = get_current_company_id());

DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.inventory_ledger;
CREATE POLICY "Allow full access based on company_id"
    ON public.inventory_ledger FOR ALL
    USING (company_id = get_current_company_id())
    WITH CHECK (company_id = get_current_company_id());

DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.customers;
CREATE POLICY "Allow full access based on company_id"
    ON public.customers FOR ALL
    USING (company_id = get_current_company_id())
    WITH CHECK (company_id = get_current_company_id());

DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.orders;
CREATE POLICY "Allow full access based on company_id"
    ON public.orders FOR ALL
    USING (company_id = get_current_company_id())
    WITH CHECK (company_id = get_current_company_id());

DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.order_line_items;
CREATE POLICY "Allow full access based on company_id"
    ON public.order_line_items FOR ALL
    USING (company_id = get_current_company_id())
    WITH CHECK (company_id = get_current_company_id());

DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.suppliers;
CREATE POLICY "Allow full access based on company_id"
    ON public.suppliers FOR ALL
    USING (company_id = get_current_company_id())
    WITH CHECK (company_id = get_current_company_id());

DROP POLICY IF EXISTS "Allow full access to own conversations" ON public.conversations;
CREATE POLICY "Allow full access to own conversations"
    ON public.conversations FOR ALL
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Allow full access to messages in own conversations" ON public.messages;
CREATE POLICY "Allow full access to messages in own conversations"
    ON public.messages FOR ALL
    USING (conversation_id IN (SELECT id FROM public.conversations WHERE user_id = auth.uid()))
    WITH CHECK (conversation_id IN (SELECT id FROM public.conversations WHERE user_id = auth.uid()));

DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.integrations;
CREATE POLICY "Allow full access based on company_id"
    ON public.integrations FOR ALL
    USING (company_id = get_current_company_id())
    WITH CHECK (company_id = get_current_company_id());

DROP POLICY IF EXISTS "Allow read access to company audit log" ON public.audit_log;
CREATE POLICY "Allow read access to company audit log"
    ON public.audit_log FOR SELECT
    USING (company_id = get_current_company_id());

DROP POLICY IF EXISTS "Allow read access to webhook_events" ON public.webhook_events;
CREATE POLICY "Allow read access to webhook_events"
    ON public.webhook_events FOR SELECT
    USING (integration_id IN (SELECT id FROM public.integrations WHERE company_id = get_current_company_id()));


--
-- ==== 6. Database Functions & Triggers ====
--

-- Function to set updated_at timestamp on record update
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = (now() at time zone 'utc');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Helper function to apply the trigger to multiple tables
CREATE OR REPLACE FUNCTION public.apply_updated_at_trigger(table_name TEXT)
RETURNS void AS $$
BEGIN
    EXECUTE format('
        DROP TRIGGER IF EXISTS handle_updated_at ON public.%I;
        CREATE TRIGGER handle_updated_at
        BEFORE UPDATE ON public.%I
        FOR EACH ROW
        EXECUTE FUNCTION public.set_updated_at();
    ', table_name, table_name);
END;
$$ LANGUAGE plpgsql;

-- Apply the trigger to all tables with an updated_at column
SELECT public.apply_updated_at_trigger(table_name)
FROM information_schema.columns
WHERE table_schema = 'public' AND column_name = 'updated_at'
  AND table_name NOT IN ('product_variants_with_details'); -- Exclude views


-- Function to be called on new user signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  new_company_id uuid;
  user_company_name TEXT;
BEGIN
  -- Extract company name from metadata
  user_company_name := NEW.raw_user_meta_data ->> 'company_name';
  
  -- Create a new company for the user
  INSERT INTO public.companies (name)
  VALUES (user_company_name)
  RETURNING id INTO new_company_id;
  
  -- Update the user's app_metadata with the new company_id and role
  UPDATE auth.users
  SET raw_app_meta_data = jsonb_set(
    jsonb_set(
      COALESCE(raw_app_meta_data, '{}'::jsonb),
      '{company_id}', to_jsonb(new_company_id)
    ),
    '{role}', to_jsonb('Owner'::text)
  )
  WHERE id = NEW.id;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to call handle_new_user on new user creation
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- Data retention cron job
CREATE OR REPLACE FUNCTION cleanup_old_data()
RETURNS void AS $$
BEGIN
    -- Delete audit logs older than 90 days
    DELETE FROM public.audit_log WHERE created_at < now() - interval '90 days';
    -- Delete messages older than 180 days
    DELETE FROM public.messages WHERE created_at < now() - interval '180 days';
END;
$$ LANGUAGE plpgsql;

--
-- ==== 7. Materialized Views ====
--

-- A view to simplify querying for product and variant information together.
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.*,
    p.title AS product_title,
    p.description AS product_description,
    p.handle AS product_handle,
    p.product_type AS product_type,
    p.tags AS product_tags,
    p.status AS product_status,
    p.image_url AS image_url,
    l.name AS location_name
FROM
    public.product_variants pv
LEFT JOIN public.products p ON pv.product_id = p.id
LEFT JOIN public.locations l ON pv.location_id = l.id;


--
-- ==== 8. Stored Procedures (RPCs) ====
--

-- Procedure to record a sale and update inventory atomically
CREATE OR REPLACE FUNCTION record_order_from_platform(p_company_id uuid, p_order_payload jsonb, p_platform TEXT)
RETURNS void AS $$
DECLARE
    v_customer_id uuid;
    v_order_id uuid;
    v_variant_id uuid;
    line_item jsonb;
    v_sku TEXT;
    v_quantity INT;
BEGIN
    -- Find or create customer
    SELECT id INTO v_customer_id FROM customers WHERE email = (p_order_payload->'customer'->>'email') AND company_id = p_company_id;
    IF v_customer_id IS NULL THEN
        INSERT INTO customers (company_id, customer_name, email)
        VALUES (p_company_id, p_order_payload->'customer'->>'first_name' || ' ' || p_order_payload->'customer'->>'last_name', p_order_payload->'customer'->>'email')
        RETURNING id INTO v_customer_id;
    END IF;

    -- Create order
    INSERT INTO orders (company_id, order_number, external_order_id, customer_id, financial_status, fulfillment_status, currency, subtotal, total_tax, total_shipping, total_discounts, total_amount, source_platform, created_at)
    VALUES (
        p_company_id,
        p_order_payload->>'order_number',
        p_order_payload->>'id',
        v_customer_id,
        p_order_payload->>'financial_status',
        p_order_payload->>'fulfillment_status',
        p_order_payload->>'currency',
        (p_order_payload->>'subtotal_price')::numeric * 100,
        (p_order_payload->>'total_tax')::numeric * 100,
        (p_order_payload->>'total_shipping_price_set'->'shop_money'->>'amount')::numeric * 100,
        (p_order_payload->>'total_discounts')::numeric * 100,
        (p_order_payload->>'total_price')::numeric * 100,
        p_platform,
        (p_order_payload->>'created_at')::timestamptz
    ) RETURNING id INTO v_order_id;

    -- Create line items and update inventory
    FOR line_item IN SELECT * FROM jsonb_array_elements(p_order_payload->'line_items')
    LOOP
        v_sku := line_item->>'sku';
        v_quantity := (line_item->>'quantity')::INT;

        -- Find the corresponding variant and lock the row
        SELECT id INTO v_variant_id FROM product_variants WHERE sku = v_sku AND company_id = p_company_id FOR UPDATE;

        IF v_variant_id IS NOT NULL THEN
            -- Update inventory
            UPDATE product_variants SET inventory_quantity = inventory_quantity - v_quantity WHERE id = v_variant_id;

            -- Insert line item
            INSERT INTO order_line_items (order_id, variant_id, company_id, product_name, variant_title, sku, quantity, price, total_discount, cost_at_time, external_line_item_id)
            VALUES (
                v_order_id,
                v_variant_id,
                p_company_id,
                line_item->>'name',
                line_item->>'variant_title',
                v_sku,
                v_quantity,
                (line_item->>'price')::numeric * 100,
                (line_item->>'total_discount')::numeric * 100,
                (SELECT cost FROM product_variants WHERE id = v_variant_id),
                line_item->>'id'
            );
            
            -- Insert into ledger
            INSERT INTO inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes)
            SELECT p_company_id, v_variant_id, 'sale', -v_quantity, inventory_quantity, v_order_id, 'Order #' || (p_order_payload->>'order_number')
            FROM product_variants WHERE id = v_variant_id;

        END IF;
    END LOOP;

    -- Update customer aggregates
    UPDATE customers
    SET total_orders = total_orders + 1, total_spent = total_spent + ((p_order_payload->>'total_price')::numeric * 100)
    WHERE id = v_customer_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.reconcile_inventory_from_integration(p_company_id uuid, p_integration_id uuid, p_user_id uuid)
RETURNS void AS $$
-- Placeholder for reconciliation logic
BEGIN
    -- This function would fetch current inventory from the external platform
    -- and create inventory_ledger entries of type 'reconciliation' to match quantities.
    -- For now, it's a placeholder.
    PERFORM 1;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION public.get_dashboard_metrics(p_company_id uuid, p_days integer)
RETURNS jsonb AS $$
-- Placeholder for complex dashboard query.
-- In a real app, this would be a much more complex query, likely on a materialized view.
BEGIN
    RETURN jsonb_build_object(
        'total_revenue', 100000,
        'revenue_change', 10.5,
        'total_sales', 500,
        'sales_change', 5.2,
        'new_customers', 50,
        'customers_change', -2.0,
        'dead_stock_value', 5000,
        'sales_over_time', '[]'::jsonb,
        'top_selling_products', '[]'::jsonb,
        'inventory_summary', jsonb_build_object(
            'total_value', 200000,
            'in_stock_value', 150000,
            'low_stock_value', 45000,
            'dead_stock_value', 5000
        )
    );
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.get_inventory_analytics(p_company_id uuid) RETURNS jsonb AS $$
BEGIN RETURN '{}'::jsonb; END;
$$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION public.get_sales_analytics(p_company_id uuid) RETURNS jsonb AS $$
BEGIN RETURN '{}'::jsonb; END;
$$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION public.get_customer_analytics(p_company_id uuid) RETURNS jsonb AS $$
BEGIN RETURN '{}'::jsonb; END;
$$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION public.get_dead_stock_report(p_company_id uuid) RETURNS jsonb AS $$
BEGIN RETURN '[]'::jsonb; END;
$$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION public.get_reorder_suggestions(p_company_id uuid) RETURNS jsonb AS $$
BEGIN RETURN '[]'::jsonb; END;
$$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION public.detect_anomalies(p_company_id uuid) RETURNS jsonb AS $$
BEGIN RETURN '[]'::jsonb; END;
$$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION public.get_alerts(p_company_id uuid) RETURNS jsonb AS $$
BEGIN RETURN '[]'::jsonb; END;
$$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION public.get_inventory_aging_report(p_company_id uuid) RETURNS jsonb AS $$
BEGIN RETURN '[]'::jsonb; END;
$$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION public.get_product_lifecycle_analysis(p_company_id uuid) RETURNS jsonb AS $$
BEGIN RETURN '{}'::jsonb; END;
$$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION public.get_inventory_risk_report(p_company_id uuid) RETURNS jsonb AS $$
BEGIN RETURN '[]'::jsonb; END;
$$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION public.get_customer_segment_analysis(p_company_id uuid) RETURNS jsonb AS $$
BEGIN RETURN '[]'::jsonb; END;
$$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION public.get_cash_flow_insights(p_company_id uuid) RETURNS jsonb AS $$
BEGIN RETURN '{}'::jsonb; END;
$$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION public.get_supplier_performance_report(p_company_id uuid) RETURNS jsonb AS $$
BEGIN RETURN '[]'::jsonb; END;
$$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION public.get_inventory_turnover(p_company_id uuid, p_days integer) RETURNS jsonb AS $$
BEGIN RETURN '{}'::jsonb; END;
$$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION public.get_users_for_company(p_company_id uuid) RETURNS jsonb AS $$
BEGIN RETURN '[]'::jsonb; END;
$$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION public.update_user_role_in_company(p_user_id uuid, p_company_id uuid, p_new_role TEXT) RETURNS void AS $$
BEGIN PERFORM 1; END;
$$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION public.remove_user_from_company(p_user_id uuid, p_company_id uuid, p_performing_user_id uuid) RETURNS void AS $$
BEGIN PERFORM 1; END;
$$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION create_purchase_orders_from_suggestions(p_company_id uuid, p_user_id uuid, p_suggestions jsonb) RETURNS int AS $$
BEGIN RETURN 1; END;
$$ LANGUAGE plpgsql;


--
-- ==== 9. Final Grants ====
--
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO service_role;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO service_role;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO service_role;

-- Grant authenticated users access to the public schema
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- Allow anon users to call RLS helper functions, which are defined with SECURITY DEFINER
GRANT EXECUTE ON FUNCTION public.get_current_company_id() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_current_user_id() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.handle_new_user() to anon, authenticated;

-- Grant anon role limited access for signup/login
GRANT USAGE ON SCHEMA auth TO anon, authenticated;
GRANT ALL ON TABLE auth.users TO service_role;
GRANT ALL ON TABLE auth.sessions TO service_role;
GRANT EXECUTE ON FUNCTION auth.uid() TO authenticated;
GRANT EXECUTE ON FUNCTION auth.jwt() TO authenticated;

-- Set the search path for the service_role to ensure it can find functions.
ALTER ROLE service_role SET search_path = 'public,auth';

-- Give anon role permission to use the handle_new_user trigger
ALTER USER supabase_auth_admin SET search_path = 'auth,public';

-- Final script confirmation
SELECT 'InvoChat DB Schema V1.5 Installed Successfully' AS status;
