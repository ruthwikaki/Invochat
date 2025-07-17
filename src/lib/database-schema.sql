-- InvoChat Base Schema
-- This schema is designed for a multi-tenant inventory management system.

-- === Extensions ===
-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
-- Enable pgcrypto for cryptographic functions
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- === Helper Functions ===

-- Function to get the company_id from the current user's JWT claims.
-- This is the cornerstone of our Row-Level Security (RLS) policy.
-- SECURITY DEFINER allows this function to be used in policies securely.
-- STABLE ensures the function's result is consistent within a query.
CREATE OR REPLACE FUNCTION get_company_id()
RETURNS UUID
LANGUAGE plpgsql
STABLE -- Marking as STABLE is a performance optimization for RLS
SECURITY DEFINER
AS $$
BEGIN
  -- We use current_setting with 'app.current_company_id' which is set
  -- by the 'set_company_id' function upon user authentication.
  -- This is more secure than directly accessing JWT claims in every policy.
  -- We add a fallback for cases where the setting might not be available.
  RETURN COALESCE(
    NULLIF(current_setting('app.current_company_id', true), '')::UUID,
    (auth.jwt() -> 'app_metadata' ->> 'company_id')::UUID
  );
END;
$$;

-- Function to set a transaction-local variable for the company_id.
-- This is called after a user authenticates.
CREATE OR REPLACE FUNCTION set_company_id(company_id UUID)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  -- Sets a transaction-level configuration parameter.
  -- This is more efficient than calling auth.jwt() repeatedly in RLS policies.
  PERFORM set_config('app.current_company_id', company_id::text, true);
END;
$$;


-- === Tables ===

-- Stores company information
CREATE TABLE IF NOT EXISTS companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Stores user information and their link to a company
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    email TEXT,
    role TEXT CHECK (role IN ('owner', 'admin', 'member')) DEFAULT 'member',
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Stores company-specific settings for business logic
CREATE TABLE IF NOT EXISTS company_settings (
    company_id UUID PRIMARY KEY REFERENCES companies(id) ON DELETE CASCADE,
    dead_stock_days INT NOT NULL DEFAULT 90,
    fast_moving_days INT NOT NULL DEFAULT 30,
    overstock_multiplier INT NOT NULL DEFAULT 3,
    high_value_threshold INT NOT NULL DEFAULT 100000, -- in cents
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

-- Stores product master data
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
    fts_document TSVECTOR,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, external_product_id)
);

-- Stores product variants (SKUs)
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
    price INT, -- in cents
    compare_at_price INT, -- in cents
    cost INT, -- in cents
    inventory_quantity INT NOT NULL DEFAULT 0,
    location TEXT,
    external_variant_id TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(company_id, sku),
    UNIQUE(company_id, external_variant_id)
);

-- Stores every single inventory movement for auditing
CREATE TABLE IF NOT EXISTS inventory_ledger (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
    change_type TEXT NOT NULL, -- e.g., 'sale', 'purchase_order', 'reconciliation', 'manual_adjustment'
    quantity_change INT NOT NULL,
    new_quantity INT NOT NULL,
    related_id UUID, -- Can link to order_id, purchase_order_id, etc.
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Stores customer data
CREATE TABLE IF NOT EXISTS customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    customer_name TEXT NOT NULL,
    email TEXT,
    total_orders INT DEFAULT 0,
    total_spent INT DEFAULT 0, -- in cents
    first_order_date DATE,
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(company_id, email)
);

-- Stores order master data
CREATE TABLE IF NOT EXISTS orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    order_number TEXT NOT NULL,
    external_order_id TEXT,
    customer_id UUID REFERENCES customers(id),
    financial_status TEXT DEFAULT 'pending', -- e.g., 'paid', 'pending', 'refunded'
    fulfillment_status TEXT DEFAULT 'unfulfilled', -- e.g., 'fulfilled', 'partial', 'unfulfilled'
    currency TEXT DEFAULT 'USD',
    subtotal INT NOT NULL DEFAULT 0, -- in cents
    total_tax INT DEFAULT 0, -- in cents
    total_shipping INT DEFAULT 0, -- in cents
    total_discounts INT DEFAULT 0, -- in cents
    total_amount INT NOT NULL, -- in cents
    source_platform TEXT,
    source_name TEXT,
    tags TEXT[],
    notes TEXT,
    cancelled_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(company_id, external_order_id)
);

-- Stores individual line items for each order
CREATE TABLE IF NOT EXISTS order_line_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    variant_id UUID NOT NULL REFERENCES product_variants(id) ON DELETE RESTRICT,
    product_name TEXT NOT NULL,
    variant_title TEXT,
    sku TEXT NOT NULL,
    quantity INT NOT NULL,
    price INT NOT NULL, -- in cents
    total_discount INT DEFAULT 0, -- in cents
    tax_amount INT DEFAULT 0, -- in cents
    cost_at_time INT, -- in cents, captures historical COGS
    fulfillment_status TEXT DEFAULT 'unfulfilled',
    requires_shipping BOOLEAN DEFAULT true,
    external_line_item_id TEXT
);

-- Stores supplier information
CREATE TABLE IF NOT EXISTS suppliers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    default_lead_time_days INT,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Stores purchase order master data
CREATE TABLE IF NOT EXISTS purchase_orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    supplier_id UUID REFERENCES suppliers(id),
    status TEXT NOT NULL DEFAULT 'Draft',
    po_number TEXT NOT NULL,
    total_cost INT NOT NULL, -- in cents
    expected_arrival_date DATE,
    idempotency_key UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(company_id, po_number)
);

-- Stores individual line items for each purchase order
CREATE TABLE IF NOT EXISTS purchase_order_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    purchase_order_id UUID NOT NULL REFERENCES purchase_orders(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
    quantity INT NOT NULL,
    cost INT NOT NULL -- in cents
);

-- Stores integration settings
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

-- Stores chat conversation metadata
CREATE TABLE IF NOT EXISTS conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    last_accessed_at TIMESTAMPTZ DEFAULT now(),
    is_starred BOOLEAN DEFAULT false
);

-- Stores individual chat messages
CREATE TABLE IF NOT EXISTS messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
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

-- Stores audit trail information
CREATE TABLE IF NOT EXISTS audit_log (
    id BIGSERIAL PRIMARY KEY,
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    details JSONB,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Stores channel-specific fees for profitability analysis
CREATE TABLE IF NOT EXISTS channel_fees (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    channel_name TEXT NOT NULL,
    percentage_fee NUMERIC NOT NULL,
    fixed_fee NUMERIC NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE (company_id, channel_name)
);

-- Stores webhook events to prevent replays
CREATE TABLE IF NOT EXISTS webhook_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id UUID NOT NULL REFERENCES integrations(id) ON DELETE CASCADE,
    webhook_id TEXT NOT NULL,
    processed_at TIMESTAMPTZ DEFAULT now(),
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(integration_id, webhook_id)
);


-- === Views ===

-- A unified view for product variants with essential parent product data
CREATE OR REPLACE VIEW product_variants_with_details AS
SELECT
    pv.id,
    pv.product_id,
    pv.company_id,
    p.title AS product_title,
    p.status AS product_status,
    p.image_url,
    pv.sku,
    pv.title,
    pv.option1_name,
    pv.option1_value,
    pv.option2_name,
    pv.option2_value,
    pv.option3_name,
    pv.option3_value,
    pv.price,
    pv.cost,
    pv.inventory_quantity,
    pv.location,
    p.product_type,
    p.tags
FROM product_variants pv
JOIN products p ON pv.product_id = p.id
WHERE p.company_id = get_company_id();


-- === Database Functions ===

-- Function to handle new user signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    new_company_id UUID;
    v_user_role TEXT;
BEGIN
    -- Create a new company for the new user
    INSERT INTO public.companies (name)
    VALUES (new.raw_app_meta_data->>'company_name')
    RETURNING id INTO new_company_id;

    -- Insert a corresponding entry into the public.users table
    INSERT INTO public.users (id, company_id, email, role)
    VALUES (new.id, new_company_id, new.email, 'owner');

    -- Insert default settings for the new company
    INSERT INTO public.company_settings (company_id)
    VALUES (new_company_id);

    -- Update the user's app_metadata with the new company_id and role
    UPDATE auth.users
    SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'role', 'owner')
    WHERE id = new.id;
    
    RETURN new;
END;
$$;


-- Trigger to call handle_new_user on new user signup in auth.users
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgname = 'on_auth_user_created'
    ) THEN
        CREATE TRIGGER on_auth_user_created
        AFTER INSERT ON auth.users
        FOR EACH ROW
        EXECUTE FUNCTION public.handle_new_user();
    END IF;
END;
$$;


-- Function to decrement inventory upon sale
-- Includes row-level locking to prevent race conditions
CREATE OR REPLACE FUNCTION public.record_sale_transaction(
    p_company_id UUID,
    p_user_id UUID,
    p_customer_name TEXT,
    p_customer_email TEXT,
    p_payment_method TEXT,
    p_notes TEXT,
    p_sale_items JSONB[],
    p_external_id TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_customer_id UUID;
    v_order_id UUID;
    v_total_amount INT := 0;
    sale_item JSONB;
    v_sku TEXT;
    v_quantity INT;
    v_unit_price INT;
    v_cost_at_time INT;
    v_product_id UUID;
    v_variant_id UUID;
    v_current_stock INT;
    v_product_name TEXT;
BEGIN
    -- Find or create customer
    IF p_customer_email IS NOT NULL THEN
        SELECT id INTO v_customer_id FROM customers WHERE email = p_customer_email AND company_id = p_company_id;
        IF v_customer_id IS NULL THEN
            INSERT INTO customers (company_id, customer_name, email)
            VALUES (p_company_id, p_customer_name, p_customer_email)
            RETURNING id INTO v_customer_id;
        END IF;
    END IF;

    -- Create order
    INSERT INTO orders (company_id, customer_id, total_amount, notes, external_order_id)
    VALUES (p_company_id, v_customer_id, 0, p_notes, p_external_id)
    RETURNING id INTO v_order_id;

    -- Process line items
    FOREACH sale_item IN ARRAY p_sale_items
    LOOP
        v_sku := sale_item->>'sku';
        v_quantity := (sale_item->>'quantity')::INT;
        v_unit_price := (sale_item->>'unit_price')::INT;
        v_cost_at_time := (sale_item->>'cost_at_time')::INT;
        v_product_name := sale_item->>'product_name';

        -- Get variant and product info, and lock the row to prevent race conditions
        SELECT pv.id, pv.product_id, pv.inventory_quantity
        INTO v_variant_id, v_product_id, v_current_stock
        FROM product_variants pv
        WHERE pv.sku = v_sku AND pv.company_id = p_company_id
        FOR UPDATE;
        
        IF v_variant_id IS NULL THEN
            RAISE EXCEPTION 'Product with SKU % not found', v_sku;
        END IF;

        -- Check for sufficient stock
        IF v_current_stock < v_quantity THEN
            RAISE EXCEPTION 'Insufficient stock for SKU %: requested %, available %', v_sku, v_quantity, v_current_stock;
        END IF;

        -- Insert line item
        INSERT INTO order_line_items (company_id, order_id, product_id, variant_id, sku, product_name, quantity, price, cost_at_time)
        VALUES (p_company_id, v_order_id, v_product_id, v_variant_id, v_sku, v_product_name, v_quantity, v_unit_price, v_cost_at_time);
        
        -- Update inventory quantity
        UPDATE product_variants
        SET inventory_quantity = inventory_quantity - v_quantity
        WHERE id = v_variant_id;

        -- Insert into inventory ledger
        INSERT INTO inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id)
        VALUES (p_company_id, v_variant_id, 'sale', -v_quantity, v_current_stock - v_quantity, v_order_id);

        v_total_amount := v_total_amount + (v_quantity * v_unit_price);
    END LOOP;

    -- Update order total
    UPDATE orders SET total_amount = v_total_amount WHERE id = v_order_id;
    
    RETURN v_order_id;
END;
$$ LANGUAGE plpgsql;



-- === Indexes for Performance ===
CREATE INDEX IF NOT EXISTS idx_orders_company_created ON orders(company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_product_variants_sku ON product_variants(company_id, sku);
CREATE INDEX IF NOT EXISTS idx_products_company_id ON products(company_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_created ON inventory_ledger(variant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_customers_company_email ON customers(company_id, email);
CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON suppliers(company_id);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_company_id ON purchase_orders(company_id);


-- === Row-Level Security (RLS) ===

-- A procedure to dynamically enable RLS and create policies for a table.
-- This reduces code duplication.
CREATE OR REPLACE PROCEDURE enable_rls_on_table(p_table_name TEXT)
LANGUAGE plpgsql
AS $$
DECLARE
    policy_name TEXT;
BEGIN
    -- Enable RLS on the specified table
    EXECUTE 'ALTER TABLE public.' || quote_ident(p_table_name) || ' ENABLE ROW LEVEL SECURITY';
    EXECUTE 'ALTER TABLE public.' || quote_ident(p_table_name) || ' FORCE ROW LEVEL SECURITY';

    -- Create a standard policy for the table
    policy_name := 'Allow all access to own company data';
    EXECUTE 'CREATE POLICY "' || policy_name || '" ON public.' || quote_ident(p_table_name)
         || ' FOR ALL USING (company_id = get_company_id()) WITH CHECK (company_id = get_company_id())';
END;
$$;


-- A procedure to apply RLS to all relevant tables.
-- This makes the schema setup idempotent and easy to manage.
CREATE OR REPLACE PROCEDURE apply_rls_policies()
LANGUAGE plpgsql
AS $$
DECLARE
    r RECORD;
BEGIN
    -- Drop all existing policies on our tables before reapplying them
    FOR r IN (
        SELECT policyname, tablename
        FROM pg_policies
        WHERE schemaname = 'public' AND tablename IN (
            'companies', 'company_settings', 'users', 'products', 'product_variants',
            'inventory_ledger', 'orders', 'order_line_items', 'customers',
            'suppliers', 'purchase_orders', 'purchase_order_line_items', 'integrations', 'conversations', 'messages',
            'audit_log', 'channel_fees'
        )
    )
    LOOP
        EXECUTE 'DROP POLICY IF EXISTS ' || quote_ident(r.policyname) || ' ON public.' || quote_ident(r.tablename);
    END LOOP;

    -- Enable RLS and create policies for each table
    CALL enable_rls_on_table('companies');
    CALL enable_rls_on_table('company_settings');
    CALL enable_rls_on_table('users');
    CALL enable_rls_on_table('products');
    CALL enable_rls_on_table('product_variants');
    CALL enable_rls_on_table('inventory_ledger');
    CALL enable_rls_on_table('orders');
    CALL enable_rls_on_table('order_line_items');
    CALL enable_rls_on_table('customers');
    CALL enable_rls_on_table('suppliers');
    CALL enable_rls_on_table('purchase_orders');
    CALL enable_rls_on_table('purchase_order_line_items');
    CALL enable_rls_on_table('integrations');
    CALL enable_rls_on_table('conversations');
    CALL enable_rls_on_table('messages');
    CALL enable_rls_on_table('audit_log');
    CALL enable_rls_on_table('channel_fees');

END;
$$;

-- Execute the procedure to apply all RLS policies
CALL apply_rls_policies();

