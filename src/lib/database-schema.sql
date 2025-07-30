
-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Define custom types
CREATE TYPE company_role AS ENUM ('Owner', 'Admin', 'Member');
CREATE TYPE integration_platform AS ENUM ('shopify', 'woocommerce', 'amazon_fba');
CREATE TYPE message_role AS ENUM ('user', 'assistant', 'tool');
CREATE TYPE feedback_type AS ENUM ('helpful', 'unhelpful');

-- Companies Table
CREATE TABLE IF NOT EXISTS companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    owner_id UUID REFERENCES auth.users(id)
);
ALTER TABLE companies ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view their own company" ON companies FOR SELECT USING (id = (SELECT raw_app_meta_data->>'company_id' FROM auth.users WHERE id = auth.uid())::UUID);

-- Company Users Table
CREATE TABLE IF NOT EXISTS company_users (
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role company_role NOT NULL DEFAULT 'Member',
    PRIMARY KEY (company_id, user_id)
);
ALTER TABLE company_users ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view their own company members" ON company_users FOR SELECT USING (company_id = (SELECT raw_app_meta_data->>'company_id' FROM auth.users WHERE id = auth.uid())::UUID);

-- Handle New User: Creates a company and links the user.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    company_id_var UUID;
    user_company_name TEXT;
BEGIN
    -- Extract company name from user's app metadata
    user_company_name := NEW.raw_app_meta_data->>'company_name';

    -- Create a new company for the user
    INSERT INTO public.companies (name, owner_id)
    VALUES (user_company_name, NEW.id)
    RETURNING id INTO company_id_var;

    -- Link the user to the new company as 'Owner'
    INSERT INTO public.company_users (company_id, user_id, role)
    VALUES (company_id_var, NEW.id, 'Owner');

    -- Update the user's app_metadata with the new company_id
    UPDATE auth.users
    SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id_var)
    WHERE id = NEW.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger for new user signup
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Function to get company ID for a user
CREATE OR REPLACE FUNCTION get_company_id_for_user(p_user_id UUID)
RETURNS UUID AS $$
DECLARE
    company_id_val UUID;
BEGIN
    SELECT company_id INTO company_id_val FROM company_users WHERE user_id = p_user_id;
    RETURN company_id_val;
END;
$$ LANGUAGE plpgsql;

-- All other application tables follow...
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
    deleted_at TIMESTAMPTZ,
    UNIQUE (company_id, external_product_id)
);
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage products in their company" ON products FOR ALL USING (company_id = (SELECT raw_app_meta_data->>'company_id' FROM auth.users WHERE id = auth.uid())::UUID);

-- Product Variants Table
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
    updated_at TIMESTAMPTZ,
    reorder_point INT,
    reorder_quantity INT,
    UNIQUE (company_id, sku)
);
ALTER TABLE product_variants ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage variants in their company" ON product_variants FOR ALL USING (company_id = (SELECT raw_app_meta_data->>'company_id' FROM auth.users WHERE id = auth.uid())::UUID);

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
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage customers in their company" ON customers FOR ALL USING (company_id = (SELECT raw_app_meta_data->>'company_id' FROM auth.users WHERE id = auth.uid())::UUID);

-- Orders Table
CREATE TABLE IF NOT EXISTS orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    order_number TEXT NOT NULL,
    external_order_id TEXT,
    customer_id UUID REFERENCES customers(id),
    financial_status TEXT,
    fulfillment_status TEXT,
    currency TEXT,
    subtotal INT NOT NULL,
    total_tax INT,
    total_shipping INT,
    total_discounts INT,
    total_amount INT NOT NULL,
    source_platform TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ
);
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage orders in their company" ON orders FOR ALL USING (company_id = (SELECT raw_app_meta_data->>'company_id' FROM auth.users WHERE id = auth.uid())::UUID);

-- Order Line Items Table
CREATE TABLE IF NOT EXISTS order_line_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    variant_id UUID REFERENCES product_variants(id),
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
ALTER TABLE order_line_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage line items in their company" ON order_line_items FOR ALL USING (company_id = (SELECT raw_app_meta_data->>'company_id' FROM auth.users WHERE id = auth.uid())::UUID);

-- Inventory Ledger Table
CREATE TABLE IF NOT EXISTS inventory_ledger (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
    change_type TEXT NOT NULL, -- e.g., 'sale', 'purchase_order', 'return', 'manual_adjustment'
    quantity_change INT NOT NULL,
    new_quantity INT NOT NULL,
    related_id UUID, -- e.g., order_id, purchase_order_id
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE inventory_ledger ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage ledger entries in their company" ON inventory_ledger FOR ALL USING (company_id = (SELECT raw_app_meta_data->>'company_id' FROM auth.users WHERE id = auth.uid())::UUID);

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
ALTER TABLE suppliers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage suppliers in their company" ON suppliers FOR ALL USING (company_id = (SELECT raw_app_meta_data->>'company_id' FROM auth.users WHERE id = auth.uid())::UUID);

-- Purchase Orders Table
CREATE TABLE IF NOT EXISTS purchase_orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    supplier_id UUID REFERENCES suppliers(id),
    status TEXT NOT NULL DEFAULT 'Draft',
    po_number TEXT NOT NULL,
    total_cost INT NOT NULL,
    expected_arrival_date DATE,
    idempotency_key UUID,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ
);
ALTER TABLE purchase_orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage purchase orders in their company" ON purchase_orders FOR ALL USING (company_id = (SELECT raw_app_meta_data->>'company_id' FROM auth.users WHERE id = auth.uid())::UUID);

-- Purchase Order Line Items Table
CREATE TABLE IF NOT EXISTS purchase_order_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    purchase_order_id UUID NOT NULL REFERENCES purchase_orders(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    quantity INT NOT NULL,
    cost INT NOT NULL -- cost per unit in cents
);
ALTER TABLE purchase_order_line_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage PO line items in their company" ON purchase_order_line_items FOR ALL USING (company_id = (SELECT raw_app_meta_data->>'company_id' FROM auth.users WHERE id = auth.uid())::UUID);

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
ALTER TABLE integrations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage integrations in their company" ON integrations FOR ALL USING (company_id = (SELECT raw_app_meta_data->>'company_id' FROM auth.users WHERE id = auth.uid())::UUID);

-- Company Settings Table
CREATE TABLE IF NOT EXISTS company_settings (
    company_id UUID PRIMARY KEY REFERENCES companies(id) ON DELETE CASCADE,
    dead_stock_days INT NOT NULL DEFAULT 90,
    fast_moving_days INT NOT NULL DEFAULT 30,
    overstock_multiplier INT NOT NULL DEFAULT 3,
    high_value_threshold INT NOT NULL DEFAULT 100000, -- in cents
    predictive_stock_days INT NOT NULL DEFAULT 7,
    currency TEXT DEFAULT 'USD',
    tax_rate NUMERIC DEFAULT 0,
    timezone TEXT DEFAULT 'UTC',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    alert_settings JSONB DEFAULT '{"email_notifications": true, "morning_briefing_enabled": true, "morning_briefing_time": "09:00", "low_stock_threshold": 10, "critical_stock_threshold": 5}'::jsonb
);
ALTER TABLE company_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage settings for their company" ON company_settings FOR ALL USING (company_id = (SELECT raw_app_meta_data->>'company_id' FROM auth.users WHERE id = auth.uid())::UUID);

-- Alert History Table
CREATE TABLE IF NOT EXISTS alert_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    alert_id TEXT NOT NULL,
    alert_type TEXT,
    alert_data JSONB,
    status TEXT DEFAULT 'unread' CHECK (status IN ('unread', 'read', 'dismissed')),
    created_at TIMESTAMPTZ DEFAULT now(),
    read_at TIMESTAMPTZ,
    dismissed_at TIMESTAMPTZ,
    UNIQUE(company_id, alert_id)
);
ALTER TABLE alert_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage alert history in their company" ON alert_history FOR ALL USING (company_id = (SELECT raw_app_meta_data->>'company_id' FROM auth.users WHERE id = auth.uid())::UUID);

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_alert_history_company_id ON alert_history(company_id);
CREATE INDEX IF NOT EXISTS idx_alert_history_status ON alert_history(status);
CREATE INDEX IF NOT EXISTS idx_alert_history_created_at ON alert_history(created_at);
CREATE INDEX IF NOT EXISTS orders_analytics_idx ON orders(company_id, created_at, financial_status);
CREATE INDEX IF NOT EXISTS inventory_ledger_history_idx ON inventory_ledger(variant_id, created_at);
CREATE INDEX IF NOT EXISTS messages_conversation_idx ON messages(conversation_id, created_at);

-- Enhanced get_alerts function
CREATE OR REPLACE FUNCTION get_alerts_with_status(p_company_id UUID)
RETURNS JSON[] AS $$
DECLARE
    alerts JSON[];
    r RECORD;
    settings RECORD;
BEGIN
    -- Get company-specific settings
    SELECT alert_settings INTO settings FROM company_settings WHERE company_id = p_company_id;
    
    IF settings.alert_settings IS NULL THEN
        settings.alert_settings := '{"low_stock_threshold": 10, "critical_stock_threshold": 5}';
    END IF;

    -- Low Stock Alerts
    FOR r IN (
        SELECT 
            v.id,
            v.sku,
            p.title as product_name,
            v.inventory_quantity,
            v.reorder_point,
            ah.status as alert_status
        FROM product_variants v
        JOIN products p ON v.product_id = p.id
        LEFT JOIN alert_history ah ON ah.company_id = v.company_id AND ah.alert_id = 'low_stock_' || v.id
        WHERE v.company_id = p_company_id
          AND v.inventory_quantity <= COALESCE((settings.alert_settings->>'low_stock_threshold')::int, 10)
          AND v.inventory_quantity > 0
          AND (ah.status IS NULL OR ah.status != 'dismissed' OR ah.dismissed_at < (now() - interval '24 hours'))
    ) LOOP
        alerts := array_append(alerts, json_build_object(
            'id', 'low_stock_' || r.id,
            'type', 'low_stock',
            'title', 'Low Stock Warning',
            'message', r.product_name || ' is running low on stock (' || r.inventory_quantity || ' left).',
            'severity', CASE 
                WHEN r.inventory_quantity <= COALESCE((settings.alert_settings->>'critical_stock_threshold')::int, 5) 
                THEN 'critical' 
                ELSE 'warning' 
            END,
            'timestamp', now(),
            'read', r.alert_status = 'read',
            'metadata', json_build_object(
                'productId', r.id,
                'productName', r.product_name,
                'sku', r.sku,
                'currentStock', r.inventory_quantity,
                'reorderPoint', r.reorder_point
            )
        ));
    END LOOP;

    RETURN alerts;
END;
$$ LANGUAGE plpgsql;
