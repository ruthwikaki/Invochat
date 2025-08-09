
-- =================================================================
--
-- AI-VCo-Inventory - Database Schema
--
-- This script is designed to be idempotent and can be run multiple
-- times without causing errors. It sets up tables, RLS policies,
-- and database functions required for the application to run.
--
-- =================================================================

-- -----------------------------------------------------------------
-- Extensions
-- -----------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "vector";


-- -----------------------------------------------------------------
-- Custom Types
-- -----------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'company_role') THEN
        CREATE TYPE company_role AS ENUM ('Owner', 'Admin', 'Member');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'integration_platform') THEN
        CREATE TYPE integration_platform AS ENUM ('shopify', 'woocommerce', 'amazon_fba');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'message_role') THEN
        CREATE TYPE message_role AS ENUM ('user', 'assistant', 'tool');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'feedback_type') THEN
        CREATE TYPE feedback_type AS ENUM ('helpful', 'unhelpful');
    END IF;
END$$;


-- =================================================================
-- Tables
-- =================================================================

-- Companies Table
CREATE TABLE IF NOT EXISTS companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    owner_id UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Company Users Join Table (for roles)
CREATE TABLE IF NOT EXISTS company_users (
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role company_role NOT NULL DEFAULT 'Member',
    PRIMARY KEY (company_id, user_id)
);

-- Company Settings Table
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
    alert_settings JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ
);

-- Suppliers Table
CREATE TABLE IF NOT EXISTS suppliers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    default_lead_time_days INT,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ
);

-- Products Table
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
    deleted_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS products_company_id_idx ON products(company_id);
CREATE UNIQUE INDEX IF NOT EXISTS products_company_external_id_unique ON products(company_id, external_product_id) WHERE external_product_id IS NOT NULL;


-- Product Variants Table
CREATE TABLE IF NOT EXISTS product_variants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    supplier_id UUID REFERENCES suppliers(id) ON DELETE SET NULL,
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
    reorder_point INT,
    reorder_quantity INT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ,
    version INT NOT NULL DEFAULT 1
);
CREATE INDEX IF NOT EXISTS variants_product_id_idx ON product_variants(product_id);
CREATE INDEX IF NOT EXISTS variants_company_id_idx ON product_variants(company_id);
CREATE UNIQUE INDEX IF NOT EXISTS variants_company_sku_unique ON product_variants(company_id, sku) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS variants_company_external_id_unique ON product_variants(company_id, external_variant_id) WHERE external_variant_id IS NOT NULL;


-- Customers Table
CREATE TABLE IF NOT EXISTS customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    name TEXT,
    email TEXT,
    phone TEXT,
    external_customer_id TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS customers_company_id_idx ON customers(company_id);


-- Orders Table
CREATE TABLE IF NOT EXISTS orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    customer_id UUID REFERENCES customers(id) ON DELETE SET NULL,
    order_number TEXT NOT NULL,
    external_order_id TEXT,
    financial_status TEXT,
    fulfillment_status TEXT,
    currency TEXT,
    subtotal INT NOT NULL DEFAULT 0,
    total_tax INT DEFAULT 0,
    total_shipping INT DEFAULT 0,
    total_discounts INT DEFAULT 0,
    total_amount INT NOT NULL,
    source_platform TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS orders_company_id_idx ON orders(company_id);
CREATE INDEX IF NOT EXISTS orders_customer_id_idx ON orders(customer_id);

-- Order Line Items Table
CREATE TABLE IF NOT EXISTS order_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    variant_id UUID REFERENCES product_variants(id) ON DELETE SET NULL,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    product_name TEXT,
    variant_title TEXT,
    sku TEXT,
    quantity INT NOT NULL,
    price INT NOT NULL,
    total_discount INT,
    tax_amount INT,
    cost_at_time INT,
    external_line_item_id TEXT
);
CREATE INDEX IF NOT EXISTS order_line_items_order_id_idx ON order_line_items(order_id);
CREATE INDEX IF NOT EXISTS order_line_items_variant_id_idx ON order_line_items(variant_id);

-- Purchase Orders Table
CREATE TABLE IF NOT EXISTS purchase_orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    supplier_id UUID REFERENCES suppliers(id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'Draft',
    po_number TEXT NOT NULL,
    total_cost INT NOT NULL,
    expected_arrival_date DATE,
    notes TEXT,
    idempotency_key UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS purchase_orders_company_id_idx ON purchase_orders(company_id);


-- Purchase Order Line Items Table
CREATE TABLE IF NOT EXISTS purchase_order_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    purchase_order_id UUID NOT NULL REFERENCES purchase_orders(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES product_variants(id) ON DELETE RESTRICT,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    quantity INT NOT NULL,
    cost INT NOT NULL
);
CREATE INDEX IF NOT EXISTS po_line_items_po_id_idx ON purchase_order_line_items(purchase_order_id);


-- Inventory Ledger Table
CREATE TABLE IF NOT EXISTS inventory_ledger (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    variant_id UUID NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    change_type TEXT NOT NULL,
    quantity_change INT NOT NULL,
    new_quantity INT NOT NULL,
    related_id UUID,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS inventory_ledger_variant_id_idx ON inventory_ledger(variant_id);

-- Integrations Table
CREATE TABLE IF NOT EXISTS integrations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    platform integration_platform NOT NULL,
    shop_domain TEXT,
    shop_name TEXT,
    is_active BOOLEAN DEFAULT false,
    last_sync_at TIMESTAMPTZ,
    sync_status TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ
);
CREATE UNIQUE INDEX IF NOT EXISTS integrations_company_platform_unique ON integrations(company_id, platform);

-- Channel Fees Table
CREATE TABLE IF NOT EXISTS channel_fees (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    channel_name TEXT NOT NULL,
    percentage_fee NUMERIC,
    fixed_fee NUMERIC,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ
);
CREATE UNIQUE INDEX IF NOT EXISTS channel_fees_company_channel_unique ON channel_fees(company_id, channel_name);

-- AI Conversations Table
CREATE TABLE IF NOT EXISTS conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    last_accessed_at TIMESTAMPTZ DEFAULT now(),
    is_starred BOOLEAN DEFAULT false
);

-- AI Messages Table
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
    created_at TIMESTAMPTZ DEFAULT now(),
    is_error BOOLEAN DEFAULT false
);

-- Audit Log Table
CREATE TABLE IF NOT EXISTS audit_log (
    id BIGSERIAL PRIMARY KEY,
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    details JSONB,
    created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS audit_log_company_action_idx ON audit_log(company_id, action, created_at);

-- Feedback Table
CREATE TABLE IF NOT EXISTS feedback (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    subject_id TEXT NOT NULL,
    subject_type TEXT NOT NULL,
    feedback feedback_type NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS feedback_subject_idx ON feedback(subject_id, subject_type);

-- Imports Table
CREATE TABLE IF NOT EXISTS imports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    created_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    import_type TEXT NOT NULL,
    file_name TEXT NOT NULL,
    total_rows INT,
    processed_rows INT,
    failed_rows INT,
    status TEXT NOT NULL DEFAULT 'pending', -- pending, processing, completed, completed_with_errors, failed
    errors JSONB,
    summary JSONB,
    created_at TIMESTAMPTZ DEFAULT now(),
    completed_at TIMESTAMPTZ
);

-- Export Jobs Table
CREATE TABLE IF NOT EXISTS export_jobs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    requested_by_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'pending',
    download_url TEXT,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ,
    error_message TEXT
);

-- Webhook Events Table (for idempotency)
CREATE TABLE IF NOT EXISTS webhook_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    integration_id UUID NOT NULL REFERENCES integrations(id) ON DELETE CASCADE,
    webhook_id TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS webhook_events_idempotency_idx ON webhook_events(integration_id, webhook_id);

-- =================================================================
-- RLS (Row-Level Security) Policies
-- =================================================================

-- First, create the helper function to get the company_id from the JWT
CREATE OR REPLACE FUNCTION auth.company_id()
RETURNS UUID AS $$
DECLARE
    company_id_val UUID;
BEGIN
    -- Get company_id from JWT token's app_metadata claim
    company_id_val := (auth.jwt() -> 'app_metadata' ->> 'company_id')::UUID;
    RETURN company_id_val;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;


-- Function to check a user's role within their company
CREATE OR REPLACE FUNCTION auth.check_user_role(p_role company_role)
RETURNS BOOLEAN AS $$
DECLARE
    user_role company_role;
BEGIN
    SELECT role INTO user_role FROM company_users
    WHERE user_id = auth.uid() AND company_id = auth.company_id();

    IF p_role = 'Owner' THEN
        RETURN user_role = 'Owner';
    ELSIF p_role = 'Admin' THEN
        RETURN user_role IN ('Owner', 'Admin');
    ELSE
        RETURN user_role IN ('Owner', 'Admin', 'Member');
    END IF;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;


-- Enable RLS on all tables
ALTER TABLE companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE company_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE channel_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE imports ENABLE ROW LEVEL SECURITY;
ALTER TABLE export_jobs ENABLE ROW LEVEL SECURITY;

-- Drop existing policies to ensure a clean slate
DROP POLICY IF EXISTS "Users can only access their own company data" ON companies;
DROP POLICY IF EXISTS "Users can manage their own company members" ON company_users;
DROP POLICY IF EXISTS "Users can manage their own company settings" ON company_settings;
DROP POLICY IF EXISTS "Users can access their own company data" ON suppliers;
DROP POLICY IF EXISTS "Users can access their own company data" ON products;
DROP POLICY IF EXISTS "Users can access their own company data" ON product_variants;
DROP POLICY IF EXISTS "Users can access their own company data" ON customers;
DROP POLICY IF EXISTS "Users can access their own company data" ON orders;
DROP POLICY IF EXISTS "Users can access their own company data" ON order_line_items;
DROP POLICY IF EXISTS "Users can access their own company data" ON purchase_orders;
DROP POLICY IF EXISTS "Users can access their own company data" ON purchase_order_line_items;
DROP POLICY IF EXISTS "Users can access their own company data" ON inventory_ledger;
DROP POLICY IF EXISTS "Users can access their own company data" ON integrations;
DROP POLICY IF EXISTS "Users can access their own company data" ON channel_fees;
DROP POLICY IF EXISTS "Users can access their own company data" ON conversations;
DROP POLICY IF EXISTS "Users can access their own company data" ON messages;
DROP POLICY IF EXISTS "Users can access their own company data" ON audit_log;
DROP POLICY IF EXISTS "Users can access their own company data" ON feedback;
DROP POLICY IF EXISTS "Users can access their own company data" ON imports;
DROP POLICY IF EXISTS "Users can access their own company data" ON export_jobs;


-- Define RLS Policies
CREATE POLICY "Users can only access their own company data"
ON companies FOR ALL
USING (id = auth.company_id());

CREATE POLICY "Users can manage their own company members"
ON company_users FOR ALL
USING (company_id = auth.company_id());

CREATE POLICY "Users can manage their own company settings"
ON company_settings FOR ALL
USING (company_id = auth.company_id());

CREATE POLICY "Users can access their own company data"
ON suppliers FOR ALL
USING (company_id = auth.company_id());

CREATE POLICY "Users can access their own company data"
ON products FOR ALL
USING (company_id = auth.company_id());

CREATE POLICY "Users can access their own company data"
ON product_variants FOR ALL
USING (company_id = auth.company_id());

CREATE POLICY "Users can access their own company data"
ON customers FOR ALL
USING (company_id = auth.company_id());

CREATE POLICY "Users can access their own company data"
ON orders FOR ALL
USING (company_id = auth.company_id());

CREATE POLICY "Users can access their own company data"
ON order_line_items FOR ALL
USING (company_id = auth.company_id());

CREATE POLICY "Users can access their own company data"
ON purchase_orders FOR ALL
USING (company_id = auth.company_id());

CREATE POLICY "Users can access their own company data"
ON purchase_order_line_items FOR ALL
USING (company_id = auth.company_id());

CREATE POLICY "Users can access their own company data"
ON inventory_ledger FOR ALL
USING (company_id = auth.company_id());

CREATE POLICY "Users can access their own company data"
ON integrations FOR ALL
USING (company_id = auth.company_id());

CREATE POLICY "Users can access their own company data"
ON channel_fees FOR ALL
USING (company_id = auth.company_id());

CREATE POLICY "Users can access their own company data"
ON conversations FOR ALL
USING (user_id = auth.uid()); -- Conversations are per-user

CREATE POLICY "Users can access their own company data"
ON messages FOR ALL
USING (company_id = auth.company_id() AND conversation_id IN (SELECT id FROM conversations WHERE user_id = auth.uid()));

CREATE POLICY "Users can access their own company data"
ON audit_log FOR ALL
USING (company_id = auth.company_id());

CREATE POLICY "Users can access their own company data"
ON feedback FOR ALL
USING (company_id = auth.company_id());

CREATE POLICY "Users can access their own company data"
ON imports FOR ALL
USING (company_id = auth.company_id());

CREATE POLICY "Users can access their own company data"
ON export_jobs FOR ALL
USING (company_id = auth.company_id());


-- =================================================================
-- Triggers and Functions
-- =================================================================

-- Trigger to create a new company for a new user
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    new_company_id UUID;
    company_name TEXT;
BEGIN
    -- Extract company name from metadata, default to 'My Company'
    company_name := new.raw_app_meta_data ->> 'company_name';
    IF company_name IS NULL OR company_name = '' THEN
        company_name := 'My Company';
    END IF;

    -- Create a new company for the user
    INSERT INTO public.companies (name, owner_id)
    VALUES (company_name, new.id)
    RETURNING id INTO new_company_id;

    -- Add user to the company with 'Owner' role
    INSERT INTO public.company_users (company_id, user_id, role)
    VALUES (new_company_id, new.id, 'Owner');

    -- Update the user's app_metadata with the new company_id
    UPDATE auth.users
    SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id)
    WHERE id = new.id;

    RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop trigger if it exists
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Create the trigger
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();


-- Trigger to update 'updated_at' timestamps
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply the update trigger to relevant tables
DROP TRIGGER IF EXISTS handle_updated_at ON suppliers;
CREATE TRIGGER handle_updated_at BEFORE UPDATE ON suppliers FOR EACH ROW EXECUTE PROCEDURE public.update_updated_at_column();

DROP TRIGGER IF EXISTS handle_updated_at ON products;
CREATE TRIGGER handle_updated_at BEFORE UPDATE ON products FOR EACH ROW EXECUTE PROCEDURE public.update_updated_at_column();

DROP TRIGGER IF EXISTS handle_updated_at ON product_variants;
CREATE TRIGGER handle_updated_at BEFORE UPDATE ON product_variants FOR EACH ROW EXECUTE PROCEDURE public.update_updated_at_column();

DROP TRIGGER IF EXISTS handle_updated_at ON orders;
CREATE TRIGGER handle_updated_at BEFORE UPDATE ON orders FOR EACH ROW EXECUTE PROCEDURE public.update_updated_at_column();

DROP TRIGGER IF EXISTS handle_updated_at ON purchase_orders;
CREATE TRIGGER handle_updated_at BEFORE UPDATE ON purchase_orders FOR EACH ROW EXECUTE PROCEDURE public.update_updated_at_column();


-- =================================================================
-- Materialized Views
-- =================================================================

-- Sales by day (for charting)
CREATE MATERIALIZED VIEW IF NOT EXISTS daily_sales AS
SELECT
    company_id,
    date_trunc('day', created_at) AS sale_date,
    SUM(total_amount) AS total_revenue,
    COUNT(id) AS total_orders
FROM orders
WHERE financial_status = 'paid'
GROUP BY company_id, date_trunc('day', created_at);

-- Create a unique index for concurrent refreshes
CREATE UNIQUE INDEX IF NOT EXISTS daily_sales_unique_idx ON daily_sales(company_id, sale_date);

-- Inventory value by product
CREATE MATERIALIZED VIEW IF NOT EXISTS product_inventory_value AS
SELECT
    v.product_id,
    v.company_id,
    p.title as product_title,
    SUM(v.inventory_quantity * v.cost) AS total_inventory_value,
    SUM(v.inventory_quantity) as total_quantity
FROM product_variants v
JOIN products p ON v.product_id = p.id
WHERE v.cost IS NOT NULL AND v.inventory_quantity > 0
GROUP BY v.product_id, v.company_id, p.title;

-- Create a unique index for concurrent refreshes
CREATE UNIQUE INDEX IF NOT EXISTS product_inventory_value_unique_idx ON product_inventory_value(company_id, product_id);


-- =================================================================
-- Helper Functions for Refreshing Views
-- =================================================================

CREATE OR REPLACE FUNCTION refresh_all_matviews(p_company_id UUID)
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY daily_sales;
    REFRESH MATERIALIZED VIEW CONCURRENTLY product_inventory_value;
EXCEPTION WHEN OTHERS THEN
    -- Log errors if needed, but don't fail the transaction
    RAISE NOTICE 'Failed to refresh materialized views: %', SQLERRM;
END;
$$ LANGUAGE plpgsql;

-- =================================================================
-- Stored Procedures for Business Logic
-- =================================================================

-- This will be expanded with more complex business logic functions
-- to ensure data consistency and performance.

-- Placeholder for get_dashboard_metrics
CREATE OR REPLACE FUNCTION get_dashboard_metrics(p_company_id UUID, p_days INT)
RETURNS jsonb AS $$
BEGIN
  -- This function is a placeholder. The full implementation will be added
  -- in a subsequent step to calculate all dashboard metrics.
  RETURN jsonb_build_object(
      'total_revenue', 0,
      'revenue_change', 0,
      'total_orders', 0,
      'orders_change', 0,
      'new_customers', 0,
      'customers_change', 0,
      'dead_stock_value', 0,
      'sales_over_time', '[]'::jsonb,
      'top_selling_products', '[]'::jsonb,
      'inventory_summary', jsonb_build_object(
          'total_value', 0,
          'in_stock_value', 0,
          'low_stock_value', 0,
          'dead_stock_value', 0
      )
  );
END;
$$ LANGUAGE plpgsql;

-- Function to handle full purchase order creation
CREATE OR REPLACE FUNCTION create_full_purchase_order(
    p_company_id UUID,
    p_user_id UUID,
    p_supplier_id UUID,
    p_status TEXT,
    p_notes TEXT,
    p_expected_arrival DATE,
    p_line_items JSONB
) RETURNS UUID AS $$
DECLARE
    new_po_id UUID;
    total_cost INT;
    item JSONB;
BEGIN
    -- Calculate total cost from line items
    SELECT SUM((li->>'quantity')::INT * (li->>'cost')::INT)
    INTO total_cost
    FROM jsonb_array_elements(p_line_items) li;

    -- Create the purchase order
    INSERT INTO purchase_orders (company_id, supplier_id, status, notes, expected_arrival_date, total_cost, po_number)
    VALUES (p_company_id, p_supplier_id, p_status, p_notes, p_expected_arrival, total_cost, 'PO-' || (SELECT COUNT(*) + 1001 FROM purchase_orders WHERE company_id = p_company_id))
    RETURNING id INTO new_po_id;

    -- Insert line items
    FOR item IN SELECT * FROM jsonb_array_elements(p_line_items)
    LOOP
        INSERT INTO purchase_order_line_items (purchase_order_id, variant_id, quantity, cost, company_id)
        VALUES (new_po_id, (item->>'variant_id')::UUID, (item->>'quantity')::INT, (item->>'cost')::INT, p_company_id);
    END LOOP;

    -- Create audit log
    INSERT INTO audit_log (company_id, user_id, action, details)
    VALUES (p_company_id, p_user_id, 'purchase_order_created', jsonb_build_object('po_id', new_po_id, 'supplier_id', p_supplier_id));

    RETURN new_po_id;
END;
$$ LANGUAGE plpgsql;

-- Function to handle full purchase order updates
CREATE OR REPLACE FUNCTION update_full_purchase_order(
    p_po_id UUID,
    p_company_id UUID,
    p_user_id UUID,
    p_supplier_id UUID,
    p_status TEXT,
    p_notes TEXT,
    p_expected_arrival DATE,
    p_line_items JSONB
) RETURNS void AS $$
DECLARE
    new_total_cost INT;
    item JSONB;
BEGIN
    -- Calculate new total cost
    SELECT SUM((li->>'quantity')::INT * (li->>'cost')::INT)
    INTO new_total_cost
    FROM jsonb_array_elements(p_line_items) li;

    -- Update the purchase order
    UPDATE purchase_orders
    SET
        supplier_id = p_supplier_id,
        status = p_status,
        notes = p_notes,
        expected_arrival_date = p_expected_arrival,
        total_cost = new_total_cost,
        updated_at = now()
    WHERE id = p_po_id AND company_id = p_company_id;

    -- Remove existing line items for simplicity and re-add them
    DELETE FROM purchase_order_line_items WHERE purchase_order_id = p_po_id;

    -- Insert new line items
    FOR item IN SELECT * FROM jsonb_array_elements(p_line_items)
    LOOP
        INSERT INTO purchase_order_line_items (purchase_order_id, variant_id, quantity, cost, company_id)
        VALUES (p_po_id, (item->>'variant_id')::UUID, (item->>'quantity')::INT, (item->>'cost')::INT, p_company_id);
    END LOOP;
    
    -- Create audit log
    INSERT INTO audit_log (company_id, user_id, action, details)
    VALUES (p_company_id, p_user_id, 'purchase_order_updated', jsonb_build_object('po_id', p_po_id));
END;
$$ LANGUAGE plpgsql;

-- =================================================================
-- Grant Permissions
-- =================================================================

-- Grant usage on schema to authenticated users
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;

-- Grant select on all tables to authenticated users
GRANT SELECT ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;

-- Grant execute on all functions to authenticated users
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO service_role;

-- Grant permissions for sequence usage if any
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO service_role;

-- Special permissions for auth admin to manage users
GRANT ALL ON TABLE public.companies TO service_role;
GRANT ALL ON TABLE public.company_users TO service_role;


-- Final command to ensure permissions are set
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO authenticated;

-- Ensure the 'authenticated' role can use the auth.company_id function
GRANT EXECUTE ON FUNCTION auth.company_id() TO authenticated;
GRANT EXECUTE ON FUNCTION auth.check_user_role(p_role company_role) TO authenticated;
