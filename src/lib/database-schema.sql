-- This is the single source of truth for the database schema.
-- It is idempotent and can be run multiple times.

-- 1. Create custom types
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


-- 2. Create tables

-- Companies Table
CREATE TABLE IF NOT EXISTS companies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    owner_id UUID NOT NULL REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Company Users Join Table
CREATE TABLE IF NOT EXISTS company_users (
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role company_role NOT NULL DEFAULT 'Member',
    PRIMARY KEY (company_id, user_id)
);

-- Company Settings Table
CREATE TABLE IF NOT EXISTS company_settings (
  company_id UUID PRIMARY KEY REFERENCES companies(id) ON DELETE CASCADE,
  dead_stock_days INTEGER NOT NULL DEFAULT 90,
  fast_moving_days INTEGER NOT NULL DEFAULT 30,
  overstock_multiplier NUMERIC NOT NULL DEFAULT 3.0,
  high_value_threshold INTEGER NOT NULL DEFAULT 100000, -- in cents
  predictive_stock_days INTEGER NOT NULL DEFAULT 7,
  currency TEXT NOT NULL DEFAULT 'USD',
  tax_rate NUMERIC NOT NULL DEFAULT 0.0,
  timezone TEXT NOT NULL DEFAULT 'UTC',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ
);


-- Products Table
CREATE TABLE IF NOT EXISTS products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    external_product_id TEXT,
    title TEXT NOT NULL,
    description TEXT,
    handle TEXT,
    product_type TEXT,
    tags TEXT[],
    status TEXT DEFAULT 'active',
    image_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (company_id, external_product_id)
);

-- Suppliers Table
CREATE TABLE IF NOT EXISTS suppliers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    default_lead_time_days INTEGER,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

-- Product Variants Table
CREATE TABLE IF NOT EXISTS product_variants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    external_variant_id TEXT,
    title TEXT,
    sku TEXT NOT NULL,
    barcode TEXT,
    price INTEGER, -- in cents
    compare_at_price INTEGER, -- in cents
    cost INTEGER, -- in cents
    inventory_quantity INTEGER NOT NULL DEFAULT 0,
    location TEXT,
    supplier_id UUID REFERENCES suppliers(id) ON DELETE SET NULL,
    reorder_point INTEGER,
    reorder_quantity INTEGER,
    option1_name TEXT,
    option1_value TEXT,
    option2_name TEXT,
    option2_value TEXT,
    option3_name TEXT,
    option3_value TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (company_id, sku),
    UNIQUE (company_id, external_variant_id)
);

-- Customers Table
CREATE TABLE IF NOT EXISTS customers (
    id UUID PRIMARY KEY DEFAULT gen-random_uuid(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    external_customer_id TEXT,
    name TEXT,
    email TEXT,
    phone TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ,
    UNIQUE (company_id, external_customer_id),
    UNIQUE (company_id, email)
);

-- Orders Table
CREATE TABLE IF NOT EXISTS orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    external_order_id TEXT,
    order_number TEXT NOT NULL,
    customer_id UUID REFERENCES customers(id) ON DELETE SET NULL,
    financial_status TEXT,
    fulfillment_status TEXT,
    currency TEXT,
    subtotal INTEGER NOT NULL, -- in cents
    total_shipping INTEGER, -- in cents
    total_tax INTEGER, -- in cents
    total_discounts INTEGER, -- in cents
    total_amount INTEGER NOT NULL, -- in cents
    source_platform TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, external_order_id)
);

-- Order Line Items Table
CREATE TABLE IF NOT EXISTS order_line_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    variant_id UUID REFERENCES product_variants(id) ON DELETE SET NULL,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    external_line_item_id TEXT,
    product_name TEXT,
    variant_title TEXT,
    sku TEXT,
    quantity INTEGER NOT NULL,
    price INTEGER NOT NULL, -- in cents
    total_discount INTEGER, -- in cents
    tax_amount INTEGER, -- in cents
    cost_at_time INTEGER -- in cents
);

-- Inventory Ledger Table
CREATE TABLE IF NOT EXISTS inventory_ledger (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
    change_type TEXT NOT NULL, -- e.g., 'sale', 'purchase_order_received', 'manual_adjustment', 'reconciliation'
    quantity_change INTEGER NOT NULL,
    new_quantity INTEGER NOT NULL,
    related_id UUID, -- Optional ID of the related order, PO, etc.
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Purchase Orders Table
CREATE TABLE IF NOT EXISTS purchase_orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    supplier_id UUID REFERENCES suppliers(id) ON DELETE SET NULL,
    po_number TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'Draft',
    total_cost INTEGER NOT NULL,
    expected_arrival_date DATE,
    notes TEXT,
    idempotency_key UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_po_company_supplier ON purchase_orders (company_id, supplier_id);

-- Purchase Order Line Items Table
CREATE TABLE IF NOT EXISTS purchase_order_line_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    purchase_order_id UUID NOT NULL REFERENCES purchase_orders(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
    quantity INTEGER NOT NULL,
    cost INTEGER NOT NULL -- cost per unit in cents
);

-- Integrations Table
CREATE TABLE IF NOT EXISTS integrations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    platform integration_platform NOT NULL,
    shop_domain TEXT,
    shop_name TEXT,
    is_active BOOLEAN NOT NULL DEFAULT FALSE,
    last_sync_at TIMESTAMPTZ,
    sync_status TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (company_id, platform)
);

-- Conversations Table (for AI Chat)
CREATE TABLE IF NOT EXISTS conversations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_accessed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_starred BOOLEAN NOT NULL DEFAULT FALSE
);

-- Messages Table (for AI Chat)
CREATE TABLE IF NOT EXISTS messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id),
    company_id UUID NOT NULL REFERENCES companies(id),
    subject_id TEXT NOT NULL, -- Can be message ID, alert ID, etc.
    subject_type TEXT NOT NULL, -- e.g., 'message', 'alert'
    feedback feedback_type NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Audit Log Table
CREATE TABLE IF NOT EXISTS audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id),
    action TEXT NOT NULL,
    details JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Channel Fees Table
CREATE TABLE IF NOT EXISTS channel_fees (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    channel_name TEXT NOT NULL,
    fixed_fee INTEGER, -- in cents
    percentage_fee NUMERIC, -- e.g., 2.9 for 2.9%
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (company_id, channel_name)
);

-- Data Export Jobs Table
CREATE TABLE IF NOT EXISTS export_jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    requested_by_user_id UUID NOT NULL REFERENCES auth.users(id),
    status TEXT NOT NULL DEFAULT 'pending', -- pending, processing, completed, failed
    download_url TEXT,
    expires_at TIMESTAMPTZ,
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ
);

-- 3. Create database functions

-- Function to handle new user sign-up and company creation
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  new_company_id UUID;
  company_name_from_meta TEXT;
BEGIN
  -- Extract company name from metadata, defaulting to 'My Company'
  company_name_from_meta := NEW.raw_user_meta_data->>'company_name';
  IF company_name_from_meta IS NULL OR company_name_from_meta = '' THEN
    company_name_from_meta := 'My Company';
  END IF;

  -- Create a new company for the new user
  INSERT INTO public.companies (name, owner_id)
  VALUES (company_name_from_meta, NEW.id)
  RETURNING id INTO new_company_id;

  -- Link the new user to the new company as 'Owner'
  INSERT INTO public.company_users (company_id, user_id, role)
  VALUES (new_company_id, NEW.id, 'Owner');

  -- Update the user's app_metadata with the new company_id
  UPDATE auth.users
  SET app_metadata = jsonb_set(
    COALESCE(app_metadata, '{}'::jsonb),
    '{company_id}',
    to_jsonb(new_company_id)
  )
  WHERE id = NEW.id;

  RETURN NEW;
END;
$$;

-- Trigger to execute the function on new user creation
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Corrected get_dashboard_metrics function
DROP FUNCTION IF EXISTS get_dashboard_metrics(p_company_id UUID, p_days INTEGER);
CREATE OR REPLACE FUNCTION get_dashboard_metrics(p_company_id UUID, p_days INTEGER)
RETURNS JSON AS $$
DECLARE
    result JSON;
BEGIN
    -- This function now directly builds the JSON object and relies on COALESCE
    -- to handle cases with no data, preventing null errors.
    SELECT json_build_object(
        'total_revenue', COALESCE((SELECT SUM(o.total_amount) FROM orders o WHERE o.company_id = p_company_id AND o.created_at >= (CURRENT_DATE - میکروفونp_days * INTERVAL '1 day') AND o.financial_status = 'paid'), 0)::INT,
        'revenue_change', COALESCE(
            (
                (
                    (SELECT SUM(total_amount) FROM orders WHERE company_id = p_company_id AND created_at >= (CURRENT_DATE - p_days * INTERVAL '1 day')) -
                    (SELECT SUM(total_amount) FROM orders WHERE company_id = p_company_id AND created_at >= (CURRENT_DATE - 2 * p_days * INTERVAL '1 day') AND created_at < (CURRENT_DATE - p_days * INTERVAL '1 day'))
                ) / NULLIF((SELECT SUM(total_amount) FROM orders WHERE company_id = p_company_id AND created_at >= (CURRENT_DATE - 2 * p_days * INTERVAL '1 day') AND created_at < (CURRENT_DATE - p_days * INTERVAL '1 day')), 0) * 100
            ), 0.0)::NUMERIC(10, 2),
        'total_orders', COALESCE((SELECT COUNT(*) FROM orders o WHERE o.company_id = p_company_id AND o.created_at >= (CURRENT_DATE - p_days * INTERVAL '1 day')), 0)::INT,
        'orders_change', COALESCE(
            (
                (
                    (SELECT COUNT(*) FROM orders WHERE company_id = p_company_id AND created_at >= (CURRENT_DATE - p_days * INTERVAL '1 day'))::NUMERIC -
                    (SELECT COUNT(*) FROM orders WHERE company_id = p_company_id AND created_at >= (CURRENT_DATE - 2 * p_days * INTERVAL '1 day') AND created_at < (CURRENT_DATE - p_days * INTERVAL '1 day'))::NUMERIC
                ) / NULLIF((SELECT COUNT(*) FROM orders WHERE company_id = p_company_id AND created_at >= (CURRENT_DATE - 2 * p_days * INTERVAL '1 day') AND created_at < (CURRENT_DATE - p_days * INTERVAL '1 day')), 0) * 100
            ), 0.0)::NUMERIC(10, 2),
        'new_customers', COALESCE((SELECT COUNT(*) FROM customers c WHERE c.company_id = p_company_id AND c.created_at >= (CURRENT_DATE - p_days * INTERVAL '1 day')), 0)::INT,
        'customers_change', COALESCE(
             (
                (
                    (SELECT COUNT(*) FROM customers WHERE company_id = p_company_id AND created_at >= (CURRENT_DATE - p_days * INTERVAL '1 day'))::NUMERIC -
                    (SELECT COUNT(*) FROM customers WHERE company_id = p_company_id AND created_at >= (CURRENT_DATE - 2 * p_days * INTERVAL '1 day') AND created_at < (CURRENT_DATE - p_days * INTERVAL '1 day'))::NUMERIC
                ) / NULLIF((SELECT COUNT(*) FROM customers WHERE company_id = p_company_id AND created_at >= (CURRENT_DATE - 2 * p_days * INTERVAL '1 day') AND created_at < (CURRENT_DATE - p_days * INTERVAL '1 day')), 0) * 100
            ), 0.0)::NUMERIC(10, 2),
        'dead_stock_value', COALESCE((SELECT SUM(pv.inventory_quantity * COALESCE(pv.cost, 0)) FROM product_variants pv WHERE pv.company_id = p_company_id AND pv.inventory_quantity > 0 AND NOT EXISTS (SELECT 1 FROM order_line_items oli JOIN orders o ON oli.order_id = o.id WHERE oli.variant_id = pv.id AND o.created_at >= (CURRENT_DATE - (SELECT cs.dead_stock_days FROM company_settings cs WHERE cs.company_id = p_company_id) * INTERVAL '1 day'))), 0)::INT,
        'sales_over_time', COALESCE((SELECT json_agg(json_build_object('date', d.sale_date, 'orders', d.daily_orders, 'revenue', d.daily_revenue)) FROM (SELECT DATE(o.created_at) AS sale_date, COUNT(*) as daily_orders, SUM(o.total_amount) AS daily_revenue FROM orders o WHERE o.company_id = p_company_id AND o.created_at >= (CURRENT_DATE - p_days * INTERVAL '1 day') GROUP BY DATE(o.created_at) ORDER BY sale_date) d), '[]'::json),
        'top_selling_products', COALESCE((SELECT json_agg(p) FROM (SELECT p.title AS product_name, p.image_url, SUM(oli.price * oli.quantity) AS total_revenue FROM order_line_items oli JOIN orders o ON oli.order_id = o.id JOIN product_variants pv ON oli.variant_id = pv.id JOIN products p ON pv.product_id = p.id WHERE oli.company_id = p_company_id AND o.created_at >= (CURRENT_DATE - p_days * INTERVAL '1 day') GROUP BY p.id, p.title, p.image_url ORDER BY total_revenue DESC LIMIT 5) p), '[]'::json),
        'inventory_summary', COALESCE((SELECT json_build_object('total_value', SUM(v.inventory_quantity * COALESCE(v.cost, 0)), 'in_stock_value', SUM(CASE WHEN v.inventory_quantity > 0 THEN v.inventory_quantity * COALESCE(v.cost, 0) ELSE 0 END), 'low_stock_value', SUM(CASE WHEN v.inventory_quantity > 0 AND v.inventory_quantity <= v.reorder_point THEN v.inventory_quantity * COALESCE(v.cost, 0) ELSE 0 END), 'dead_stock_value', (SELECT SUM(pv.inventory_quantity * COALESCE(pv.cost, 0)) FROM product_variants pv WHERE pv.company_id = p_company_id AND pv.inventory_quantity > 0 AND NOT EXISTS (SELECT 1 FROM order_line_items oli JOIN orders o ON oli.order_id = o.id WHERE oli.variant_id = pv.id AND o.created_at >= (CURRENT_DATE - (SELECT cs.dead_stock_days FROM company_settings cs WHERE cs.company_id = p_company_id) * INTERVAL '1 day')))) FROM product_variants v WHERE v.company_id = p_company_id), json_build_object('total_value', 0, 'in_stock_value', 0, 'low_stock_value', 0, 'dead_stock_value', 0))
    )
    INTO result;
    
    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- 4. Enable RLS and create policies
ALTER TABLE companies ENABLE ROW LEVEL SECURITY;
CREATE POLICY "companies_owner_access" ON companies FOR ALL USING ((auth.jwt() ->> 'company_id')::uuid = id);

ALTER TABLE company_users ENABLE ROW LEVEL SECURITY;
CREATE POLICY "company_users_access" ON company_users FOR ALL USING ((auth.jwt() ->> 'company_id')::uuid = company_id);

ALTER TABLE products ENABLE ROW LEVEL SECURITY;
CREATE POLICY "products_company_access" ON products FOR ALL USING ((auth.jwt() ->> 'company_id')::uuid = company_id);

ALTER TABLE product_variants ENABLE ROW LEVEL SECURITY;
CREATE POLICY "product_variants_company_access" ON product_variants FOR ALL USING ((auth.jwt() ->> 'company_id')::uuid = company_id);

ALTER TABLE suppliers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "suppliers_company_access" ON suppliers FOR ALL USING ((auth.jwt() ->> 'company_id')::uuid = company_id);

ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "customers_company_access" ON customers FOR ALL USING ((auth.jwt() ->> 'company_id')::uuid = company_id);

ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "orders_company_access" ON orders FOR ALL USING ((auth.jwt() ->> 'company_id')::uuid = company_id);

ALTER TABLE order_line_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "order_line_items_company_access" ON order_line_items FOR ALL USING ((auth.jwt() ->> 'company_id')::uuid = company_id);

ALTER TABLE inventory_ledger ENABLE ROW LEVEL SECURITY;
CREATE POLICY "inventory_ledger_company_access" ON inventory_ledger FOR ALL USING ((auth.jwt() ->> 'company_id')::uuid = company_id);

ALTER TABLE purchase_orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "purchase_orders_company_access" ON purchase_orders FOR ALL USING ((auth.jwt() ->> 'company_id')::uuid = company_id);

ALTER TABLE purchase_order_line_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "purchase_order_line_items_company_access" ON purchase_order_line_items FOR ALL USING ((auth.jwt() ->> 'company_id')::uuid = company_id);

ALTER TABLE integrations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "integrations_company_access" ON integrations FOR ALL USING ((auth.jwt() ->> 'company_id')::uuid = company_id);

ALTER TABLE company_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "company_settings_access" ON company_settings FOR ALL USING ((auth.jwt() ->> 'company_id')::uuid = company_id);

ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "conversations_access" ON conversations FOR ALL USING ((auth.jwt() ->> 'uid')::uuid = user_id);

ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "messages_access" ON messages FOR ALL USING ((auth.jwt() ->> 'company_id')::uuid = company_id);

ALTER TABLE feedback ENABLE ROW LEVEL SECURITY;
CREATE POLICY "feedback_access" ON feedback FOR ALL USING ((auth.jwt() ->> 'company_id')::uuid = company_id);

ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "audit_log_access" ON audit_log FOR ALL USING ((auth.jwt() ->> 'company_id')::uuid = company_id);

ALTER TABLE channel_fees ENABLE ROW LEVEL SECURITY;
CREATE POLICY "channel_fees_access" ON channel_fees FOR ALL USING ((auth.jwt() ->> 'company_id')::uuid = company_id);

ALTER TABLE export_jobs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "export_jobs_access" ON export_jobs FOR ALL USING ((auth.jwt() ->> 'company_id')::uuid = company_id);
