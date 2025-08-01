-- =============================================
-- Invochat Database Schema
-- Version: 2.0
-- Description: Full schema with tables, RLS, functions, and triggers.
-- =============================================

-- Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_cron";

-- =============================================
-- ENUMS
-- =============================================
DO $$ BEGIN
    CREATE TYPE company_role AS ENUM ('Owner', 'Admin', 'Member');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE integration_platform AS ENUM ('shopify', 'woocommerce', 'amazon_fba');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE message_role AS ENUM ('user', 'assistant', 'tool');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE feedback_type AS ENUM ('helpful', 'unhelpful');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- =============================================
-- TABLES
-- =============================================

-- Companies Table
CREATE TABLE IF NOT EXISTS companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    owner_id UUID NOT NULL REFERENCES auth.users(id),
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Company Users Join Table
CREATE TABLE IF NOT EXISTS company_users (
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    role company_role NOT NULL DEFAULT 'Member',
    PRIMARY KEY (user_id, company_id)
);

-- Products Table
CREATE TABLE IF NOT EXISTS products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    external_product_id TEXT,
    title TEXT NOT NULL,
    description TEXT,
    handle TEXT,
    product_type TEXT,
    status TEXT,
    tags TEXT[],
    image_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ,
    UNIQUE (company_id, external_product_id)
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
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

-- Product Variants Table
CREATE TABLE IF NOT EXISTS product_variants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    external_variant_id TEXT,
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
    supplier_id UUID REFERENCES suppliers(id),
    reorder_point INT,
    reorder_quantity INT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ,
    UNIQUE (company_id, sku)
);

-- Orders Table
CREATE TABLE IF NOT EXISTS orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    external_order_id TEXT,
    order_number TEXT NOT NULL,
    customer_id UUID, -- Can be null for guest checkouts
    financial_status TEXT,
    fulfillment_status TEXT,
    subtotal INT NOT NULL, -- in cents
    total_tax INT,
    total_shipping INT,
    total_discounts INT,
    total_amount INT NOT NULL,
    currency TEXT,
    source_platform TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

-- Order Line Items Table
CREATE TABLE IF NOT EXISTS order_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    variant_id UUID REFERENCES product_variants(id) ON DELETE SET NULL,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    external_line_item_id TEXT,
    product_name TEXT,
    variant_title TEXT,
    sku TEXT,
    quantity INT NOT NULL,
    price INT NOT NULL, -- in cents
    total_discount INT,
    tax_amount INT,
    cost_at_time INT
);

-- Customers Table
CREATE TABLE IF NOT EXISTS customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    external_customer_id TEXT,
    name TEXT,
    email TEXT,
    phone TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ
);
ALTER TABLE orders ADD CONSTRAINT fk_customer_id FOREIGN KEY (customer_id) REFERENCES customers(id);

-- Purchase Orders Table
CREATE TABLE IF NOT EXISTS purchase_orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    supplier_id UUID REFERENCES suppliers(id),
    po_number TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'Draft',
    total_cost INT NOT NULL,
    expected_arrival_date DATE,
    notes TEXT,
    idempotency_key UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

-- Purchase Order Line Items Table
CREATE TABLE IF NOT EXISTS purchase_order_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    purchase_order_id UUID NOT NULL REFERENCES purchase_orders(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES product_variants(id),
    quantity INT NOT NULL,
    cost INT NOT NULL -- in cents
);

-- Inventory Ledger Table
CREATE TABLE IF NOT EXISTS inventory_ledger (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES product_variants(id),
    change_type TEXT NOT NULL, -- e.g., 'sale', 'purchase_order', 'manual_adjustment', 'reconciliation'
    quantity_change INT NOT NULL,
    new_quantity INT NOT NULL,
    related_id UUID, -- Can link to order_id, po_id, etc.
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Integrations Table
CREATE TABLE IF NOT EXISTS integrations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    platform integration_platform NOT NULL,
    shop_domain TEXT,
    shop_name TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    sync_status TEXT,
    last_sync_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (company_id, platform)
);

-- Company Settings Table
CREATE TABLE IF NOT EXISTS company_settings (
    company_id UUID PRIMARY KEY REFERENCES companies(id) ON DELETE CASCADE,
    dead_stock_days INT NOT NULL DEFAULT 90,
    fast_moving_days INT NOT NULL DEFAULT 30,
    overstock_multiplier NUMERIC NOT NULL DEFAULT 3.0,
    high_value_threshold INT NOT NULL DEFAULT 100000, -- in cents
    predictive_stock_days INT NOT NULL DEFAULT 7,
    currency TEXT NOT NULL DEFAULT 'USD',
    timezone TEXT NOT NULL DEFAULT 'UTC',
    tax_rate NUMERIC NOT NULL DEFAULT 0,
    alert_settings JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

-- Audit Log Table
CREATE TABLE IF NOT EXISTS audit_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id),
    action TEXT NOT NULL,
    details JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Conversations Table (for AI Chat)
CREATE TABLE IF NOT EXISTS conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    is_starred BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_accessed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Messages Table (for AI Chat)
CREATE TABLE IF NOT EXISTS messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    role message_role NOT NULL,
    content TEXT NOT NULL,
    visualization JSONB,
    component TEXT,
    componentProps JSONB,
    confidence NUMERIC,
    assumptions TEXT[],
    isError BOOLEAN,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Feedback Table
CREATE TABLE IF NOT EXISTS feedback (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id),
    company_id UUID NOT NULL REFERENCES companies(id),
    subject_id TEXT NOT NULL,
    subject_type TEXT NOT NULL,
    feedback feedback_type NOT NULL,
    created_at TIMESTAMTz NOT NULL DEFAULT NOW()
);

-- Alert History Table
CREATE TABLE IF NOT EXISTS alert_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    alert_id TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'unread' CHECK (status IN ('unread', 'read', 'dismissed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    read_at TIMESTAMPTZ,
    dismissed_at TIMESTAMPTZ,
    metadata JSONB DEFAULT '{}',
    UNIQUE(company_id, alert_id)
);


-- =============================================
-- TRIGGERS & FUNCTIONS
-- =============================================

-- Function to handle new user signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
  new_company_id uuid;
BEGIN
  -- Create company first
  INSERT INTO public.companies (name, owner_id)
  VALUES (
    COALESCE(NEW.raw_user_meta_data->>'company_name', 'My Company'),
    NEW.id
  )
  RETURNING id INTO new_company_id;
  
  -- Create company_users association with proper role
  INSERT INTO public.company_users (company_id, user_id, role)
  VALUES (new_company_id, NEW.id, 'Owner');
  
  -- CRITICAL: Update JWT metadata immediately to prevent race conditions
  UPDATE auth.users 
  SET raw_app_meta_data = COALESCE(raw_app_meta_data, '{}'::jsonb) || 
    jsonb_build_object('company_id', new_company_id)
  WHERE id = NEW.id;
  
  RAISE NOTICE 'Created company % for new user %', new_company_id, NEW.id;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger for new user signup
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();
  
-- Function to update inventory on new order
CREATE OR REPLACE FUNCTION public.update_inventory_on_order()
RETURNS trigger AS $$
BEGIN
    UPDATE product_variants
    SET inventory_quantity = inventory_quantity - NEW.quantity
    WHERE id = NEW.variant_id
      AND company_id = NEW.company_id;
      
    INSERT INTO inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes)
    SELECT 
        NEW.company_id,
        NEW.variant_id,
        'sale',
        -NEW.quantity,
        v.inventory_quantity,
        NEW.order_id,
        'Order #' || o.order_number
    FROM product_variants v
    JOIN orders o ON o.id = NEW.order_id
    WHERE v.id = NEW.variant_id;
        
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger for new order line items
DROP TRIGGER IF EXISTS on_new_order_line_item ON order_line_items;
CREATE TRIGGER on_new_order_line_item
  AFTER INSERT ON order_line_items
  FOR EACH ROW EXECUTE PROCEDURE public.update_inventory_on_order();


-- =============================================
-- RLS (ROW LEVEL SECURITY)
-- =============================================
ALTER TABLE companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE company_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE alert_history ENABLE ROW LEVEL SECURITY;

-- Policies
CREATE POLICY "Users can manage their own company data" ON companies
    FOR ALL USING (id = (auth.jwt() ->> 'company_id')::uuid);

CREATE POLICY "Users can only see their own user-company association" ON company_users
    FOR SELECT USING (user_id = auth.uid());
    
CREATE POLICY "Users can only access data within their own company" ON products FOR ALL USING (company_id = (auth.jwt() ->> 'company_id')::uuid);
CREATE POLICY "Users can only access data within their own company" ON product_variants FOR ALL USING (company_id = (auth.jwt() ->> 'company_id')::uuid);
CREATE POLICY "Users can only access data within their own company" ON suppliers FOR ALL USING (company_id = (auth.jwt() ->> 'company_id')::uuid);
CREATE POLICY "Users can only access data within their own company" ON orders FOR ALL USING (company_id = (auth.jwt() ->> 'company_id')::uuid);
CREATE POLICY "Users can only access data within their own company" ON order_line_items FOR ALL USING (company_id = (auth.jwt() ->> 'company_id')::uuid);
CREATE POLICY "Users can only access data within their own company" ON customers FOR ALL USING (company_id = (auth.jwt() ->> 'company_id')::uuid);
CREATE POLICY "Users can only access data within their own company" ON purchase_orders FOR ALL USING (company_id = (auth.jwt() ->> 'company_id')::uuid);
CREATE POLICY "Users can only access data within their own company" ON purchase_order_line_items FOR ALL USING (company_id = (auth.jwt() ->> 'company_id')::uuid);
CREATE POLICY "Users can only access data within their own company" ON inventory_ledger FOR ALL USING (company_id = (auth.jwt() ->> 'company_id')::uuid);
CREATE POLICY "Users can only access data within their own company" ON integrations FOR ALL USING (company_id = (auth.jwt() ->> 'company_id')::uuid);
CREATE POLICY "Users can only access data within their own company" ON company_settings FOR ALL USING (company_id = (auth.jwt() ->> 'company_id')::uuid);
CREATE POLICY "Users can only access data within their own company" ON audit_log FOR ALL USING (company_id = (auth.jwt() ->> 'company_id')::uuid);
CREATE POLICY "Users can only access data within their own company" ON conversations FOR ALL USING (company_id = (auth.jwt() ->> 'company_id')::uuid);
CREATE POLICY "Users can only access data within their own company" ON messages FOR ALL USING (company_id = (auth.jwt() ->> 'company_id')::uuid);
CREATE POLICY "Users can only access data within their own company" ON feedback FOR ALL USING (company_id = (auth.jwt() ->> 'company_id')::uuid);
CREATE POLICY "Users can only access data within their own company" ON alert_history FOR ALL USING (company_id = (auth.jwt() ->> 'company_id')::uuid);


-- =============================================
-- DATABASE FUNCTIONS
-- =============================================

-- Function to check user permission level
CREATE OR REPLACE FUNCTION check_user_permission(p_user_id UUID, p_required_role company_role)
RETURNS BOOLEAN AS $$
DECLARE
    user_role company_role;
BEGIN
    SELECT role INTO user_role FROM company_users WHERE user_id = p_user_id;
    IF user_role = 'Owner' THEN
        RETURN TRUE;
    ELSIF user_role = 'Admin' AND (p_required_role = 'Admin' OR p_required_role = 'Member') THEN
        RETURN TRUE;
    ELSIF user_role = 'Member' AND p_required_role = 'Member' THEN
        RETURN TRUE;
    END IF;
    RETURN FALSE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Function for Dashboard Metrics
CREATE OR REPLACE FUNCTION get_dashboard_metrics(p_company_id UUID, p_days INTEGER)
RETURNS JSON AS $$
DECLARE
    result JSON;
    current_revenue NUMERIC := 0;
    prev_revenue NUMERIC := 0;
    current_orders INTEGER := 0;
    prev_orders INTEGER := 0;
    current_customers INTEGER := 0;
    prev_customers INTEGER := 0;
    dead_stock_val NUMERIC := 0;
    inventory_total NUMERIC := 0;
    inventory_in_stock NUMERIC := 0;
    inventory_low_stock NUMERIC := 0;
    start_date DATE;
    prev_start_date DATE;
    prev_end_date DATE;
BEGIN
    -- Calculate date ranges
    start_date := CURRENT_DATE - (p_days || ' days')::INTERVAL;
    prev_end_date := start_date - INTERVAL '1 day';
    prev_start_date := prev_end_date - (p_days || ' days')::INTERVAL;

    -- Current period metrics
    SELECT 
        COALESCE(SUM(total_amount), 0),
        COUNT(*),
        COUNT(DISTINCT customer_id)
    INTO current_revenue, current_orders, current_customers
    FROM orders 
    WHERE company_id = p_company_id 
      AND created_at >= start_date
      AND financial_status = 'paid';

    -- Previous period metrics
    SELECT 
        COALESCE(SUM(total_amount), 0),
        COUNT(*),
        COUNT(DISTINCT customer_id)
    INTO prev_revenue, prev_orders, prev_customers
    FROM orders 
    WHERE company_id = p_company_id 
      AND created_at >= prev_start_date 
      AND created_at <= prev_end_date
      AND financial_status = 'paid';

    -- Calculate inventory values
    SELECT 
        COALESCE(SUM(inventory_quantity * COALESCE(cost, 0)), 0),
        COALESCE(SUM(CASE WHEN inventory_quantity > 0 THEN inventory_quantity * COALESCE(cost, 0) ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN inventory_quantity <= COALESCE(reorder_point, 0) AND reorder_point > 0 THEN inventory_quantity * COALESCE(cost, 0) ELSE 0 END), 0)
    INTO inventory_total, inventory_in_stock, inventory_low_stock
    FROM product_variants 
    WHERE company_id = p_company_id
      AND deleted_at IS NULL;

    -- Calculate dead stock value (simplified - items not sold in the period)
    SELECT COALESCE(SUM(pv.inventory_quantity * COALESCE(pv.cost, 0)), 0)
    INTO dead_stock_val
    FROM product_variants pv
    WHERE pv.company_id = p_company_id
      AND pv.deleted_at IS NULL
      AND pv.inventory_quantity > 0
      AND NOT EXISTS (
          SELECT 1 FROM order_line_items oli
          JOIN orders o ON oli.order_id = o.id
          WHERE oli.variant_id = pv.id
            AND o.financial_status = 'paid'
            AND o.created_at >= start_date
      );

    -- Build result matching DashboardMetricsSchema
    result := json_build_object(
        'total_revenue', current_revenue,
        'revenue_change', CASE 
            WHEN prev_revenue > 0 THEN ((current_revenue - prev_revenue) / prev_revenue * 100)
            WHEN current_revenue > 0 THEN 100
            ELSE 0
        END,
        'total_orders', current_orders,
        'orders_change', CASE 
            WHEN prev_orders > 0 THEN ((current_orders - prev_orders)::numeric / prev_orders * 100)
            WHEN current_orders > 0 THEN 100
            ELSE 0
        END,
        'new_customers', current_customers,
        'customers_change', CASE 
            WHEN prev_customers > 0 THEN ((current_customers - prev_customers)::numeric / prev_customers * 100)
            WHEN current_customers > 0 THEN 100
            ELSE 0
        END,
        'dead_stock_value', dead_stock_val,
        'sales_over_time', COALESCE(
            (SELECT json_agg(
                json_build_object(
                    'date', sale_date::text,
                    'revenue', daily_revenue,
                    'orders', daily_orders
                )
            ) FROM (
                SELECT 
                    DATE(o.created_at) as sale_date,
                    SUM(o.total_amount) as daily_revenue,
                    COUNT(*) as daily_orders
                FROM orders o
                WHERE o.company_id = p_company_id 
                  AND o.created_at >= start_date
                  AND o.financial_status = 'paid'
                GROUP BY DATE(o.created_at)
                ORDER BY sale_date
            ) daily_sales),
            '[]'::json
        ),
        'top_selling_products', COALESCE(
            (SELECT json_agg(
                json_build_object(
                    'product_name', product_name,
                    'total_revenue', total_revenue,
                    'image_url', image_url
                )
            ) FROM (
                SELECT 
                    p.title as product_name,
                    SUM(oli.price * oli.quantity) as total_revenue,
                    p.image_url
                FROM order_line_items oli
                JOIN orders o ON oli.order_id = o.id
                JOIN product_variants pv ON oli.variant_id = pv.id
                JOIN products p ON pv.product_id = p.id
                WHERE oli.company_id = p_company_id
                  AND o.created_at >= start_date
                  AND o.financial_status = 'paid'
                GROUP BY p.id, p.title, p.image_url
                ORDER BY total_revenue DESC
                LIMIT 5
            ) top_products),
            '[]'::json
        ),
        'inventory_summary', json_build_object(
            'total_value', inventory_total,
            'in_stock_value', inventory_in_stock,
            'low_stock_value', inventory_low_stock,
            'dead_stock_value', dead_stock_val
        )
    );

    RETURN result;

EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Error in get_dashboard_metrics: %', SQLERRM;
    RETURN json_build_object(
        'total_revenue', 0, 'revenue_change', 0, 'total_orders', 0, 'orders_change', 0,
        'new_customers', 0, 'customers_change', 0, 'dead_stock_value', 0,
        'sales_over_time', '[]'::json, 'top_selling_products', '[]'::json,
        'inventory_summary', json_build_object('total_value', 0, 'in_stock_value', 0, 'low_stock_value', 0, 'dead_stock_value', 0)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Function for Alert System
CREATE OR REPLACE FUNCTION get_alerts(p_company_id UUID)
RETURNS JSON[] AS $$
DECLARE
    alerts JSON[];
    r RECORD;
    settings record;
BEGIN
    SELECT * INTO settings FROM company_settings WHERE company_id = p_company_id;
    
    alerts := ARRAY[]::JSON[];

    IF settings IS NULL THEN
        INSERT INTO company_settings (company_id) VALUES (p_company_id) ON CONFLICT (company_id) DO NOTHING;
        SELECT * INTO settings FROM company_settings WHERE company_id = p_company_id;
    END IF;

    -- Low Stock Alerts
    FOR r IN (
        SELECT 
            v.id, v.sku, p.title as product_name, v.inventory_quantity,
            COALESCE(v.reorder_point, 10) as reorder_point
        FROM product_variants v
        JOIN products p ON v.product_id = p.id
        WHERE v.company_id = p_company_id AND v.inventory_quantity <= COALESCE(v.reorder_point, 10) AND v.inventory_quantity > 0 LIMIT 50
    ) LOOP
        alerts := array_append(alerts, json_build_object(
            'id', 'low_stock_' || r.id, 'type', 'low_stock', 'title', 'Low Stock Warning',
            'message', r.product_name || ' (' || r.sku || ') is running low.',
            'severity', 'warning', 'timestamp', now(),
            'metadata', json_build_object('productId', r.id, 'productName', r.product_name, 'sku', r.sku, 'currentStock', r.inventory_quantity, 'reorderPoint', r.reorder_point)
        ));
    END LOOP;

    RETURN alerts;

EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Error in get_alerts: %', SQLERRM;
    RETURN ARRAY[]::JSON[];
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get alerts with status
CREATE OR REPLACE FUNCTION get_alerts_with_status(p_company_id UUID)
RETURNS JSON[] AS $$
DECLARE
    base_alerts JSON[];
    alerts_with_status JSON[] := ARRAY[]::JSON[];
    alert_json JSON;
    alert_id TEXT;
    alert_status RECORD;
    i INTEGER;
BEGIN
    SELECT get_alerts(p_company_id) INTO base_alerts;
    
    IF base_alerts IS NULL OR array_length(base_alerts, 1) IS NULL THEN
        RETURN alerts_with_status;
    END IF;
    
    FOR i IN 1..array_length(base_alerts, 1) LOOP
        alert_json := base_alerts[i];
        alert_id := alert_json->>'id';
        
        SELECT status, read_at, dismissed_at INTO alert_status FROM alert_history 
        WHERE company_id = p_company_id AND alert_history.alert_id = alert_json->>'id';
        
        alert_json := alert_json || jsonb_build_object(
            'read', COALESCE((alert_status.status = 'read' OR alert_status.status = 'dismissed'), FALSE),
            'dismissed', COALESCE(alert_status.status = 'dismissed', FALSE)
        );
        
        alerts_with_status := array_append(alerts_with_status, alert_json);
    END LOOP;
    
    RETURN alerts_with_status;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- =============================================
-- FINAL GRANTS
-- =============================================
GRANT EXECUTE ON FUNCTION get_dashboard_metrics(UUID, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION get_alerts(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_alerts_with_status(UUID) TO authenticated;

-- Grant usage on all sequences to authenticated users
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;
