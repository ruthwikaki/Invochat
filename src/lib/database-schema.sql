-- This is a one-time setup script for your Supabase project.
--
-- 1. In your Supabase project dashboard, navigate to the "SQL Editor".
-- 2. Click "+ New query".
-- 3. Paste the entire contents of this file into the editor.
-- 4. Click "Run".
--
-- This script is idempotent, meaning it can be run multiple times without
-- causing errors. It uses `CREATE OR REPLACE` and `IF NOT EXISTS` clauses
-- to ensure that existing objects are updated or left alone.

-- =================================================================
-- Extensions
-- =================================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "vector";


-- =================================================================
-- RLS (Row-Level Security) Helpers
-- =================================================================

-- A helper function to get the company_id from a user's JWT claims.
CREATE OR REPLACE FUNCTION auth.get_company_id()
RETURNS UUID AS $$
BEGIN
    RETURN (auth.jwt()->>'company_id')::UUID;
END;
$$ LANGUAGE plpgsql STABLE;

-- A helper function to get the user's role from their JWT claims.
CREATE OR REPLACE FUNCTION auth.get_user_role()
RETURNS TEXT AS $$
BEGIN
    RETURN (auth.jwt()->>'user_role')::TEXT;
END;
$$ LANGUAGE plpgsql STABLE;

-- =================================================================
-- Tables
-- =================================================================
CREATE TABLE IF NOT EXISTS companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    owner_id UUID REFERENCES auth.users(id) ON DELETE SET NULL
);

ALTER TABLE companies ENABLE ROW LEVEL SECURITY;
CREATE POLICY "companies_owner_access" ON companies FOR ALL
USING (auth.uid() = owner_id);

CREATE TYPE company_role AS ENUM ('Owner', 'Admin', 'Member');

CREATE TABLE IF NOT EXISTS company_users (
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role company_role NOT NULL DEFAULT 'Member',
    PRIMARY KEY (company_id, user_id)
);

ALTER TABLE company_users ENABLE ROW LEVEL SECURITY;
CREATE POLICY "company_users_company_access" ON company_users FOR ALL
USING (auth.get_company_id() = company_id);

CREATE TABLE IF NOT EXISTS suppliers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    notes TEXT,
    default_lead_time_days INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);
ALTER TABLE suppliers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "suppliers_company_access" ON suppliers FOR ALL
USING (auth.get_company_id() = company_id);

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
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ
);
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
CREATE POLICY "products_company_access" ON products FOR ALL
USING (auth.get_company_id() = company_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_products_company_external_id ON products(company_id, external_product_id);


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
    reorder_point INTEGER,
    reorder_quantity INTEGER,
    location TEXT,
    supplier_id UUID REFERENCES suppliers(id) ON DELETE SET NULL,
    external_variant_id TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);
ALTER TABLE product_variants ENABLE ROW LEVEL SECURITY;
CREATE POLICY "product_variants_company_access" ON product_variants FOR ALL
USING (auth.get_company_id() = company_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_variants_company_sku ON product_variants(company_id, sku);
CREATE UNIQUE INDEX IF NOT EXISTS idx_variants_company_external_id ON product_variants(company_id, external_variant_id);

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
CREATE POLICY "customers_company_access" ON customers FOR ALL
USING (auth.get_company_id() = company_id);

CREATE TABLE IF NOT EXISTS orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    order_number TEXT NOT NULL,
    external_order_id TEXT,
    customer_id UUID REFERENCES customers(id) ON DELETE SET NULL,
    financial_status TEXT DEFAULT 'pending',
    fulfillment_status TEXT DEFAULT 'unfulfilled',
    currency TEXT DEFAULT 'USD',
    subtotal INTEGER NOT NULL DEFAULT 0,
    total_tax INTEGER DEFAULT 0,
    total_shipping INTEGER DEFAULT 0,
    total_discounts INTEGER DEFAULT 0,
    total_amount INTEGER NOT NULL,
    source_platform TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "orders_company_access" ON orders FOR ALL
USING (auth.get_company_id() = company_id);

CREATE TABLE IF NOT EXISTS order_line_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    variant_id UUID REFERENCES product_variants(id) ON DELETE SET NULL,
    product_name TEXT,
    variant_title TEXT,
    sku TEXT,
    quantity INTEGER NOT NULL,
    price INTEGER NOT NULL,
    cost_at_time INTEGER,
    total_discount INTEGER DEFAULT 0,
    tax_amount INTEGER DEFAULT 0,
    external_line_item_id TEXT
);
ALTER TABLE order_line_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "order_line_items_company_access" ON order_line_items FOR ALL
USING (auth.get_company_id() = company_id);

CREATE TABLE IF NOT EXISTS purchase_orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    supplier_id UUID REFERENCES suppliers(id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'Draft',
    po_number TEXT NOT NULL,
    total_cost INTEGER NOT NULL,
    expected_arrival_date TIMESTAMPTZ,
    idempotency_key UUID,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);
ALTER TABLE purchase_orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "purchase_orders_company_access" ON purchase_orders FOR ALL
USING (auth.get_company_id() = company_id);


CREATE TABLE IF NOT EXISTS purchase_order_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    purchase_order_id UUID NOT NULL REFERENCES purchase_orders(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES product_variants(id) ON DELETE RESTRICT,
    quantity INTEGER NOT NULL,
    cost INTEGER NOT NULL
);
ALTER TABLE purchase_order_line_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "po_line_items_company_access" ON purchase_order_line_items FOR ALL
USING (auth.get_company_id() = company_id);


CREATE TABLE IF NOT EXISTS company_settings (
    company_id UUID PRIMARY KEY REFERENCES companies(id) ON DELETE CASCADE,
    dead_stock_days INTEGER NOT NULL DEFAULT 90,
    fast_moving_days INTEGER NOT NULL DEFAULT 30,
    overstock_multiplier NUMERIC NOT NULL DEFAULT 3.0,
    high_value_threshold INTEGER NOT NULL DEFAULT 100000,
    predictive_stock_days INTEGER NOT NULL DEFAULT 7,
    currency TEXT DEFAULT 'USD',
    timezone TEXT DEFAULT 'UTC',
    tax_rate NUMERIC DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);
ALTER TABLE company_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "company_settings_access" ON company_settings FOR ALL
USING (auth.get_company_id() = company_id);

CREATE TABLE IF NOT EXISTS inventory_ledger (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
    change_type TEXT NOT NULL,
    quantity_change INTEGER NOT NULL,
    new_quantity INTEGER NOT NULL,
    related_id UUID,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE inventory_ledger ENABLE ROW LEVEL SECURITY;
CREATE POLICY "inventory_ledger_company_access" ON inventory_ledger FOR ALL
USING (auth.get_company_id() = company_id);

CREATE TABLE IF NOT EXISTS integrations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  platform TEXT NOT NULL,
  shop_domain TEXT,
  shop_name TEXT,
  is_active BOOLEAN DEFAULT false,
  last_sync_at TIMESTAMPTZ,
  sync_status TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ
);
ALTER TABLE integrations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "integrations_company_access" ON integrations FOR ALL
USING (auth.get_company_id() = company_id);

CREATE TABLE IF NOT EXISTS audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  action TEXT NOT NULL,
  details JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "audit_log_company_access" ON audit_log FOR ALL
USING (auth.get_company_id() = company_id AND auth.get_user_role() IN ('Admin', 'Owner'));

CREATE TABLE IF NOT EXISTS feedback (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    subject_id TEXT NOT NULL,
    subject_type TEXT NOT NULL,
    feedback TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE feedback ENABLE ROW LEVEL SECURITY;
CREATE POLICY "feedback_company_access" ON feedback FOR ALL
USING (auth.get_company_id() = company_id);

CREATE TABLE IF NOT EXISTS channel_fees (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    channel_name TEXT NOT NULL,
    percentage_fee NUMERIC,
    fixed_fee INTEGER, -- in cents
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE (company_id, channel_name)
);
ALTER TABLE channel_fees ENABLE ROW LEVEL SECURITY;
CREATE POLICY "channel_fees_company_access" ON channel_fees FOR ALL
USING (auth.get_company_id() = company_id);

CREATE TABLE IF NOT EXISTS export_jobs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    requested_by_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'pending',
    download_url TEXT,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    error_message TEXT
);
ALTER TABLE export_jobs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "export_jobs_company_access" ON export_jobs FOR ALL
USING (auth.get_company_id() = company_id);

CREATE TABLE IF NOT EXISTS imports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  created_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  import_type TEXT NOT NULL,
  file_name TEXT NOT NULL,
  total_rows INTEGER,
  processed_rows INTEGER,
  failed_rows INTEGER,
  status TEXT NOT NULL DEFAULT 'pending', -- pending, processing, completed, completed_with_errors, failed
  errors JSONB,
  summary JSONB,
  created_at TIMESTAMPTZ DEFAULT now(),
  completed_at TIMESTAMPTZ
);
ALTER TABLE imports ENABLE ROW LEVEL SECURITY;
CREATE POLICY "imports_company_access" ON imports FOR ALL
USING (auth.get_company_id() = company_id);

CREATE TABLE IF NOT EXISTS webhook_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id UUID NOT NULL REFERENCES integrations(id) ON DELETE CASCADE,
    webhook_id TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_webhook_events_unique ON webhook_events(integration_id, webhook_id);

-- =================================================================
-- Auth Triggers and Functions
-- =================================================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    company_id UUID;
BEGIN
    -- Create a new company for the user
    INSERT INTO public.companies (name, owner_id)
    VALUES (new.raw_user_meta_data->>'company_name', new.id)
    RETURNING id INTO company_id;

    -- Link the user to the new company as an Owner
    INSERT INTO public.company_users (user_id, company_id, role)
    VALUES (new.id, company_id, 'Owner');
    
    -- Update the user's claims in JWT
    UPDATE auth.users
    SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id, 'user_role', 'Owner')
    WHERE id = new.id;
    
    RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
WHEN (new.raw_user_meta_data->>'company_name' IS NOT NULL)
EXECUTE FUNCTION public.handle_new_user();

-- =================================================================
-- Views
-- =================================================================
CREATE OR REPLACE VIEW public.customers_view AS
SELECT 
    c.id,
    c.company_id,
    c.name as customer_name,
    c.email,
    COUNT(o.id) as total_orders,
    SUM(o.total_amount) as total_spent,
    c.created_at
FROM customers c
LEFT JOIN orders o ON c.id = o.customer_id AND o.financial_status = 'paid'
WHERE c.deleted_at IS NULL
GROUP BY c.id;

CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT 
    pv.*,
    p.title as product_title,
    p.status as product_status,
    p.image_url,
    p.product_type
FROM product_variants pv
JOIN products p ON pv.product_id = p.id
WHERE pv.deleted_at IS NULL AND p.deleted_at IS NULL;

CREATE OR REPLACE VIEW public.purchase_orders_view AS
SELECT
    po.*,
    s.name AS supplier_name,
    json_agg(json_build_object(
        'id', poli.id,
        'quantity', poli.quantity,
        'cost', poli.cost,
        'sku', pv.sku,
        'product_name', p.title
    )) AS line_items
FROM purchase_orders po
LEFT JOIN suppliers s ON po.supplier_id = s.id
LEFT JOIN purchase_order_line_items poli ON po.id = poli.purchase_order_id
LEFT JOIN product_variants pv ON poli.variant_id = pv.id
LEFT JOIN products p ON pv.product_id = p.id
GROUP BY po.id, s.name;

CREATE OR REPLACE VIEW public.audit_log_view AS
SELECT
    al.id,
    al.created_at,
    u.email as user_email,
    al.action,
    al.details,
    al.company_id
FROM audit_log al
LEFT JOIN auth.users u ON al.user_id = u.id;

CREATE OR REPLACE VIEW public.feedback_view AS
SELECT 
    f.id,
    f.created_at,
    f.feedback,
    u.email as user_email,
    um.content as user_message_content,
    am.content as assistant_message_content,
    f.company_id
FROM feedback f
LEFT JOIN auth.users u ON f.user_id = u.id
LEFT JOIN messages um ON f.subject_type = 'message' AND f.subject_id = um.id
LEFT JOIN messages am ON f.subject_type = 'message' AND f.subject_id = am.id AND am.role = 'assistant';

CREATE OR REPLACE VIEW public.orders_view AS
SELECT
    o.id,
    o.company_id,
    o.order_number,
    o.external_order_id,
    o.customer_id,
    c.email as customer_email,
    o.financial_status,
    o.fulfillment_status,
    o.currency,
    o.subtotal,
    o.total_tax,
    o.total_shipping,
    o.total_discounts,
    o.total_amount,
    o.source_platform,
    o.created_at,
    o.updated_at
FROM orders o
LEFT JOIN customers c ON o.customer_id = c.id;


-- =================================================================
-- Stored Procedures / RPC Functions
-- =================================================================
CREATE OR REPLACE FUNCTION get_dashboard_metrics(p_company_id UUID, p_days INT)
RETURNS JSON AS $$
DECLARE
    metrics JSON;
BEGIN
    SELECT json_build_object(
        'total_revenue', COALESCE(SUM(CASE WHEN o.created_at >= (NOW() - (p_days || ' day')::INTERVAL) THEN o.total_amount ELSE 0 END), 0),
        'revenue_change', ((SUM(CASE WHEN o.created_at >= (NOW() - (p_days || ' day')::INTERVAL) THEN o.total_amount ELSE 0 END) - SUM(CASE WHEN o.created_at >= (NOW() - (p_days*2 || ' day')::INTERVAL) AND o.created_at < (NOW() - (p_days || ' day')::INTERVAL) THEN o.total_amount ELSE 0 END)) / NULLIF(SUM(CASE WHEN o.created_at >= (NOW() - (p_days*2 || ' day')::INTERVAL) AND o.created_at < (NOW() - (p_days || ' day')::INTERVAL) THEN o.total_amount ELSE 0 END), 0) * 100),
        'total_orders', COUNT(CASE WHEN o.created_at >= (NOW() - (p_days || ' day')::INTERVAL) THEN o.id END),
        'orders_change', ((COUNT(CASE WHEN o.created_at >= (NOW() - (p_days || ' day')::INTERVAL) THEN o.id END)::decimal - COUNT(CASE WHEN o.created_at >= (NOW() - (p_days*2 || ' day')::INTERVAL) AND o.created_at < (NOW() - (p_days || ' day')::INTERVAL) THEN o.id END)::decimal) / NULLIF(COUNT(CASE WHEN o.created_at >= (NOW() - (p_days*2 || ' day')::INTERVAL) AND o.created_at < (NOW() - (p_days || ' day')::INTERVAL) THEN o.id END), 0) * 100),
        'new_customers', COUNT(CASE WHEN c.created_at >= (NOW() - (p_days || ' day')::INTERVAL) THEN c.id END),
        'customers_change', ((COUNT(CASE WHEN c.created_at >= (NOW() - (p_days || ' day')::INTERVAL) THEN c.id END)::decimal - COUNT(CASE WHEN c.created_at >= (NOW() - (p_days*2 || ' day')::INTERVAL) AND c.created_at < (NOW() - (p_days || ' day')::INTERVAL) THEN c.id END)::decimal) / NULLIF(COUNT(CASE WHEN c.created_at >= (NOW() - (p_days*2 || ' day')::INTERVAL) AND c.created_at < (NOW() - (p_days || ' day')::INTERVAL) THEN c.id END), 0) * 100),
        'dead_stock_value', (SELECT COALESCE(SUM(total_value), 0) FROM get_dead_stock_report(p_company_id)),
        'sales_over_time', (
            SELECT json_agg(json_build_object('date', d.day, 'revenue', COALESCE(daily_revenue, 0)))
            FROM (SELECT generate_series(NOW() - (p_days-1 || ' day')::INTERVAL, NOW(), '1 day')::date as day) d
            LEFT JOIN (SELECT created_at::date as order_date, SUM(total_amount) as daily_revenue FROM orders WHERE company_id = p_company_id GROUP BY 1) s ON d.day = s.order_date
        ),
        'top_selling_products', (
            SELECT json_agg(p_agg.*) FROM (
                SELECT 
                    p.title as product_name,
                    p.image_url,
                    SUM(oli.price * oli.quantity) as total_revenue,
                    SUM(oli.quantity) as quantity_sold
                FROM order_line_items oli
                JOIN orders o ON oli.order_id = o.id
                JOIN product_variants pv ON oli.variant_id = pv.id
                JOIN products p ON pv.product_id = p.id
                WHERE o.company_id = p_company_id AND o.created_at >= (NOW() - (p_days || ' day')::INTERVAL)
                GROUP BY p.title, p.image_url
                ORDER BY total_revenue DESC
                LIMIT 5
            ) p_agg
        ),
        'inventory_summary', (SELECT get_inventory_analytics(p_company_id))
    )
    INTO metrics
    FROM orders o
    FULL JOIN customers c ON o.customer_id = c.id AND o.company_id = c.company_id
    WHERE o.company_id = p_company_id OR c.company_id = p_company_id;

    RETURN metrics;
END;
$$ LANGUAGE plpgsql;

-- Grant access to the function
GRANT EXECUTE ON FUNCTION get_dashboard_metrics(UUID, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_dashboard_metrics(UUID, INT) TO service_role;
