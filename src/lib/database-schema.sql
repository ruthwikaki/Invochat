-- InvoChat Schema v1.4
-- Last updated: 2024-07-25
-- This script is idempotent and can be run multiple times safely.

-- 1. Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "vector"; -- For potential future vector similarity searches

-- 2. Helper Functions
-- Function to get the company_id from the currently authenticated user's JWT claims
CREATE OR REPLACE FUNCTION get_company_id()
RETURNS UUID AS $$
DECLARE
    company_id_claim UUID;
BEGIN
    SELECT current_setting('request.jwt.claims', true)::jsonb->'app_metadata'->>'company_id'
    INTO company_id_claim;
    RETURN company_id_claim;
END;
$$ LANGUAGE plpgsql STABLE;

-- 3. Table Definitions
CREATE TABLE IF NOT EXISTS companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS company_settings (
    company_id UUID PRIMARY KEY REFERENCES companies(id) ON DELETE CASCADE,
    dead_stock_days INTEGER NOT NULL DEFAULT 90,
    fast_moving_days INTEGER NOT NULL DEFAULT 30,
    predictive_stock_days INTEGER NOT NULL DEFAULT 7,
    currency TEXT DEFAULT 'USD',
    timezone TEXT DEFAULT 'UTC',
    tax_rate NUMERIC DEFAULT 0,
    custom_rules JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    subscription_status TEXT DEFAULT 'trial',
    subscription_plan TEXT DEFAULT 'starter',
    subscription_expires_at TIMESTAMPTZ,
    stripe_customer_id TEXT,
    stripe_subscription_id TEXT,
    promo_sales_lift_multiplier REAL NOT NULL DEFAULT 2.5,
    overstock_multiplier INTEGER NOT NULL DEFAULT 3,
    high_value_threshold INTEGER NOT NULL DEFAULT 1000
);

-- This table links Supabase auth users to our multi-tenant system
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    email TEXT,
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now(),
    role TEXT DEFAULT 'member'
);

CREATE TABLE IF NOT EXISTS products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
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
    fts_document TSVECTOR,
    UNIQUE(company_id, external_product_id)
);

CREATE TABLE IF NOT EXISTS product_variants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    sku TEXT NOT NULL,
    title TEXT,
    option1_name TEXT,
    option1_value TEXT,
    option2_name TEXT,
    option2_value TEXT,
    option3_name TEXT,
    option3_value TEXT,
    barcode TEXT,
    price INTEGER,
    compare_at_price INTEGER,
    cost INTEGER,
    inventory_quantity INTEGER NOT NULL DEFAULT 0,
    external_variant_id TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    location TEXT,
    UNIQUE(company_id, sku),
    UNIQUE(company_id, external_variant_id)
);

CREATE TABLE IF NOT EXISTS inventory_ledger (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
    change_type TEXT NOT NULL,
    quantity_change INTEGER NOT NULL,
    new_quantity INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    related_id UUID,
    notes TEXT
);

CREATE TABLE IF NOT EXISTS orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    order_number TEXT NOT NULL,
    external_order_id TEXT,
    customer_id UUID, -- Does not reference customers table to allow anonymous orders
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
    updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS order_line_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id UUID REFERENCES products(id) ON DELETE SET NULL,
    variant_id UUID NOT NULL REFERENCES product_variants(id) ON DELETE RESTRICT,
    product_name TEXT NOT NULL,
    variant_title TEXT,
    sku TEXT NOT NULL,
    quantity INTEGER NOT NULL,
    price INTEGER NOT NULL,
    total_discount INTEGER DEFAULT 0,
    tax_amount INTEGER DEFAULT 0,
    fulfillment_status TEXT DEFAULT 'unfulfilled',
    requires_shipping BOOLEAN DEFAULT true,
    external_line_item_id TEXT,
    cost_at_time INTEGER
);

CREATE TABLE IF NOT EXISTS customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    customer_name TEXT NOT NULL,
    email TEXT,
    total_orders INTEGER DEFAULT 0,
    total_spent INTEGER DEFAULT 0,
    first_order_date DATE,
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS suppliers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    default_lead_time_days INTEGER,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS purchase_orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    supplier_id UUID REFERENCES suppliers(id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'Draft',
    po_number TEXT NOT NULL,
    total_cost INTEGER NOT NULL,
    expected_arrival_date DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    idempotency_key UUID UNIQUE
);

CREATE TABLE IF NOT EXISTS purchase_order_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    purchase_order_id UUID NOT NULL REFERENCES purchase_orders(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
    quantity INTEGER NOT NULL,
    cost INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS integrations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    platform TEXT NOT NULL,
    shop_domain TEXT,
    shop_name TEXT,
    is_active BOOLEAN DEFAULT false,
    last_sync_at TIMESTAMPTZ,
    sync_status TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    last_accessed_at TIMESTAMPTZ DEFAULT now(),
    is_starred BOOLEAN DEFAULT false
);

CREATE TABLE IF NOT EXISTS messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
    content TEXT,
    component TEXT,
    component_props JSONB,
    visualization JSONB,
    confidence NUMERIC,
    assumptions TEXT[],
    created_at TIMESTAMPTZ DEFAULT now(),
    is_error BOOLEAN DEFAULT false
);

CREATE TABLE IF NOT EXISTS audit_log (
    id BIGSERIAL PRIMARY KEY,
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    details JSONB,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS channel_fees (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    channel_name TEXT NOT NULL,
    percentage_fee NUMERIC NOT NULL,
    fixed_fee NUMERIC NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, channel_name)
);

CREATE TABLE IF NOT EXISTS webhook_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id UUID NOT NULL REFERENCES integrations(id) ON DELETE CASCADE,
    webhook_id TEXT NOT NULL,
    processed_at TIMESTAMPTZ DEFAULT now(),
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(integration_id, webhook_id)
);

-- 4. Indexes for Performance
CREATE INDEX IF NOT EXISTS idx_products_company_id ON products(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_company_id_sku ON product_variants(company_id, sku);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_orders_company_id_created_at ON orders(company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON order_line_items(variant_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id_created_at ON inventory_ledger(variant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON customers(company_id);
CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON suppliers(company_id);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_company_id ON purchase_orders(company_id);

-- 5. Row-Level Security (RLS)
-- This procedure safely enables RLS on a table if it exists.
CREATE OR REPLACE PROCEDURE enable_rls_on_table(table_name TEXT)
LANGUAGE plpgsql
AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = table_name) THEN
        EXECUTE 'ALTER TABLE public.' || quote_ident(table_name) || ' ENABLE ROW LEVEL SECURITY';
        EXECUTE 'ALTER TABLE public.' || quote_ident(table_name) || ' FORCE ROW LEVEL SECURITY';
    END IF;
END;
$$;

-- This procedure drops all existing policies on a table before creating new ones.
CREATE OR REPLACE PROCEDURE safe_drop_policies(table_name TEXT)
LANGUAGE plpgsql
AS $$
DECLARE
    r record;
BEGIN
    FOR r IN (SELECT policyname FROM pg_policies WHERE tablename = table_name AND schemaname = 'public')
    LOOP
        EXECUTE 'DROP POLICY IF EXISTS ' || quote_ident(r.policyname) || ' ON public.' || quote_ident(table_name);
    END LOOP;
END;
$$;

-- Apply RLS to all relevant tables
CREATE OR REPLACE PROCEDURE apply_rls_policies()
LANGUAGE plpgsql
AS $$
BEGIN
    -- List of all tables that need RLS
    DECLARE
        tables_to_secure TEXT[] := ARRAY[
            'companies', 'company_settings', 'users', 'products', 'product_variants',
            'inventory_ledger', 'orders', 'order_line_items', 'customers',
            'suppliers', 'purchase_orders', 'purchase_order_line_items', 'integrations', 'conversations', 'messages',
            'audit_log', 'channel_fees', 'webhook_events'
        ];
        table_name TEXT;
    BEGIN
        FOREACH table_name IN ARRAY tables_to_secure
        LOOP
            CALL enable_rls_on_table(table_name);
            CALL safe_drop_policies(table_name);
        END LOOP;
    END;
END;
$$;

CALL apply_rls_policies();

-- RLS Policies
-- Users can manage records for their own company.
CREATE POLICY "Allow all access to own company data" ON companies
    FOR ALL USING (id = get_company_id()) WITH CHECK (id = get_company_id());
CREATE POLICY "Allow all access to own company data" ON company_settings
    FOR ALL USING (company_id = get_company_id()) WITH CHECK (company_id = get_company_id());
CREATE POLICY "Allow all access to own company data" ON users
    FOR ALL USING (company_id = get_company_id()) WITH CHECK (company_id = get_company_id());
CREATE POLICY "Allow all access to own company data" ON products
    FOR ALL USING (company_id = get_company_id()) WITH CHECK (company_id = get_company_id());
CREATE POLICY "Allow all access to own company data" ON product_variants
    FOR ALL USING (company_id = get_company_id()) WITH CHECK (company_id = get_company_id());
CREATE POLICY "Allow all access to own company data" ON inventory_ledger
    FOR ALL USING (company_id = get_company_id()) WITH CHECK (company_id = get_company_id());
CREATE POLICY "Allow all access to own company data" ON orders
    FOR ALL USING (company_id = get_company_id()) WITH CHECK (company_id = get_company_id());
CREATE POLICY "Allow all access to own company data" ON order_line_items
    FOR ALL USING (company_id = get_company_id()) WITH CHECK (company_id = get_company_id());
CREATE POLICY "Allow all access to own company data" ON customers
    FOR ALL USING (company_id = get_company_id()) WITH CHECK (company_id = get_company_id());
CREATE POLICY "Allow all access to own company data" ON suppliers
    FOR ALL USING (company_id = get_company_id()) WITH CHECK (company_id = get_company_id());
CREATE POLICY "Allow all access to own company data" ON purchase_orders
    FOR ALL USING (company_id = get_company_id()) WITH CHECK (company_id = get_company_id());
CREATE POLICY "Allow all access to own company data" ON purchase_order_line_items
    FOR ALL USING (company_id = get_company_id()) WITH CHECK (company_id = get_company_id());
CREATE POLICY "Allow all access to own company data" ON integrations
    FOR ALL USING (company_id = get_company_id()) WITH CHECK (company_id = get_company_id());
CREATE POLICY "Allow all access to own company data" ON conversations
    FOR ALL USING (company_id = get_company_id()) WITH CHECK (company_id = get_company_id());
CREATE POLICY "Allow all access to own company data" ON messages
    FOR ALL USING (company_id = get_company_id()) WITH CHECK (company_id = get_company_id());
CREATE POLICY "Allow all access to own company data" ON audit_log
    FOR ALL USING (company_id = get_company_id()) WITH CHECK (company_id = get_company_id());
CREATE POLICY "Allow all access to own company data" ON channel_fees
    FOR ALL USING (company_id = get_company_id()) WITH CHECK (company_id = get_company_id());
CREATE POLICY "Allow all access to own company data" ON webhook_events
    FOR ALL USING (integration_id IN (SELECT id FROM integrations WHERE company_id = get_company_id()))
    WITH CHECK (integration_id IN (SELECT id FROM integrations WHERE company_id = get_company_id()));


-- 6. Database Functions & Triggers
-- This function runs when a new user signs up. It creates their company and links them to it.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    new_company_id UUID;
    user_company_name TEXT;
BEGIN
    -- Extract company name from metadata, falling back to a default name
    user_company_name := new.raw_app_meta_data->>'company_name';
    IF user_company_name IS NULL OR user_company_name = '' THEN
        user_company_name := new.email || '''s Company';
    END IF;

    -- Create a new company for the new user
    INSERT INTO public.companies (name)
    VALUES (user_company_name)
    RETURNING id INTO new_company_id;

    -- Create a corresponding entry in the public.users table
    INSERT INTO public.users (id, company_id, email, role)
    VALUES (new.id, new_company_id, new.email, 'Owner');

    -- Update the user's app_metadata with the new company_id and role
    -- This makes the company_id accessible in RLS policies via get_company_id()
    UPDATE auth.users
    SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'role', 'Owner')
    WHERE id = new.id;
    
    RETURN new;
END;
$$;

-- Drop the trigger if it exists to ensure idempotency
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Create the trigger to fire the handle_new_user function after a new user is created
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- This function updates the FTS document for products to enable full-text search
CREATE OR REPLACE FUNCTION update_fts_document()
RETURNS TRIGGER AS $$
BEGIN
    NEW.fts_document := to_tsvector('english', COALESCE(NEW.title, '') || ' ' || COALESCE(NEW.description, '') || ' ' || COALESCE(NEW.product_type, ''));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS fts_product_update ON products;

CREATE TRIGGER fts_product_update
BEFORE INSERT OR UPDATE ON products
FOR EACH ROW EXECUTE PROCEDURE update_fts_document();


-- Function to update inventory and log the change
CREATE OR REPLACE FUNCTION update_inventory(
    p_company_id UUID,
    p_variant_id UUID,
    p_quantity_change INT,
    p_change_type TEXT,
    p_related_id UUID DEFAULT NULL,
    p_notes TEXT DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
    new_quantity_val INT;
BEGIN
    UPDATE product_variants
    SET inventory_quantity = inventory_quantity + p_quantity_change
    WHERE id = p_variant_id AND company_id = p_company_id
    RETURNING inventory_quantity INTO new_quantity_val;

    INSERT INTO inventory_ledger(company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes)
    VALUES (p_company_id, p_variant_id, p_change_type, p_quantity_change, new_quantity_val, p_related_id, p_notes);
END;
$$ LANGUAGE plpgsql;

-- Transactional function to record a sale and update inventory atomically
CREATE OR REPLACE FUNCTION record_sale_transaction(
    p_company_id UUID,
    p_customer_name TEXT,
    p_customer_email TEXT,
    p_payment_method TEXT,
    p_notes TEXT,
    p_sale_items JSONB[],
    p_user_id UUID DEFAULT NULL,
    p_external_id TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_customer_id UUID;
    v_order_id UUID;
    item JSONB;
    v_variant RECORD;
    v_total_amount INT := 0;
BEGIN
    -- Use a CTE to find or create the customer record
    WITH customer_cte AS (
        INSERT INTO customers (company_id, customer_name, email, first_order_date, total_orders, total_spent)
        VALUES (p_company_id, p_customer_name, p_customer_email, now(), 1, 0)
        ON CONFLICT (company_id, email) DO UPDATE SET
            total_orders = customers.total_orders + 1
        RETURNING id
    )
    SELECT id INTO v_customer_id FROM customer_cte;

    -- Create the order record
    INSERT INTO orders(company_id, order_number, customer_id, total_amount, notes, external_order_id)
    VALUES (p_company_id, 'ORD-' || to_char(now(), 'YYYYMMDD-HH24MISS'), v_customer_id, 0, p_notes, p_external_id)
    RETURNING id INTO v_order_id;

    -- Loop through sale items, lock the variant row, update inventory, and create line items
    FOR item IN SELECT * FROM unnest(p_sale_items)
    LOOP
        -- Find the variant and lock the row to prevent race conditions
        SELECT id, inventory_quantity, cost INTO v_variant
        FROM product_variants
        WHERE company_id = p_company_id AND sku = item->>'sku'
        FOR UPDATE;

        IF v_variant.id IS NULL THEN
            RAISE EXCEPTION 'Product with SKU % not found.', item->>'sku';
        END IF;

        -- Create the order line item
        INSERT INTO order_line_items (company_id, order_id, variant_id, product_name, sku, quantity, price, cost_at_time)
        VALUES (
            p_company_id, v_order_id, v_variant.id, item->>'product_name',
            item->>'sku', (item->>'quantity')::INT, (item->>'unit_price')::INT, v_variant.cost
        );
        
        -- Update inventory using the dedicated function
        PERFORM update_inventory(p_company_id, v_variant.id, -(item->>'quantity')::INT, 'sale', v_order_id);

        v_total_amount := v_total_amount + ((item->>'unit_price')::INT * (item->>'quantity')::INT);
    END LOOP;

    -- Update the final total on the order and customer record
    UPDATE orders SET total_amount = v_total_amount WHERE id = v_order_id;
    UPDATE customers SET total_spent = total_spent + v_total_amount WHERE id = v_customer_id;

    RETURN v_order_id;
END;
$$ LANGUAGE plpgsql;

-- Grant usage on schema and all functions/tables to authenticated users
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO authenticated;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
