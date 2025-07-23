-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Enable the pg_stat_statements extension for monitoring query performance
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Enable the btree_gist extension for advanced indexing capabilities
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- Enum Types for structured data
CREATE TYPE company_role AS ENUM ('Owner', 'Admin', 'Member');
CREATE TYPE integration_platform AS ENUM ('shopify', 'woocommerce', 'amazon_fba');
CREATE TYPE message_role AS ENUM ('user', 'assistant', 'tool');
CREATE TYPE feedback_type AS ENUM ('helpful', 'unhelpful');

-- ##############################
-- ### Main Application Tables ###
-- ##############################

-- Companies Table: Stores information about each tenant company
CREATE TABLE companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    owner_id UUID NOT NULL REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Company Users Table: Links users to companies with specific roles (Multi-tenancy)
CREATE TABLE company_users (
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    role company_role NOT NULL DEFAULT 'Member',
    PRIMARY KEY (user_id, company_id)
);

-- Company Settings Table: Configurable business logic parameters per company
CREATE TABLE company_settings (
    company_id UUID PRIMARY KEY REFERENCES companies(id) ON DELETE CASCADE,
    dead_stock_days INT NOT NULL DEFAULT 90,
    fast_moving_days INT NOT NULL DEFAULT 30,
    overstock_multiplier NUMERIC NOT NULL DEFAULT 3.0,
    high_value_threshold INT NOT NULL DEFAULT 100000, -- in cents
    predictive_stock_days INT NOT NULL DEFAULT 7,
    currency TEXT NOT NULL DEFAULT 'USD',
    tax_rate NUMERIC NOT NULL DEFAULT 0.0,
    timezone TEXT NOT NULL DEFAULT 'UTC',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ
);

-- Products Table: Core product information
CREATE TABLE products (
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
    UNIQUE(company_id, external_product_id)
);

-- Suppliers Table: Vendor information
CREATE TABLE suppliers (
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

-- Product Variants Table: Specific versions of a product (e.g., by size or color)
CREATE TABLE product_variants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
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
    supplier_id UUID REFERENCES suppliers(id),
    reorder_point INT,
    reorder_quantity INT,
    external_variant_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, sku),
    UNIQUE(company_id, external_variant_id)
);

-- Customers Table: Customer information
CREATE TABLE customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    name TEXT,
    email TEXT,
    phone TEXT,
    external_customer_id TEXT,
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ
);

-- Orders Table: Sales order information
CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
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
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, external_order_id)
);

-- Order Line Items Table: Items within a sales order
CREATE TABLE order_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
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
    external_line_item_id TEXT,
    UNIQUE(order_id, external_line_item_id)
);

-- Purchase Orders Table
CREATE TABLE purchase_orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    supplier_id UUID REFERENCES suppliers(id),
    status TEXT NOT NULL DEFAULT 'Draft',
    po_number TEXT NOT NULL,
    total_cost INT NOT NULL,
    expected_arrival_date DATE,
    notes TEXT,
    idempotency_key UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ
);

-- Purchase Order Line Items Table
CREATE TABLE purchase_order_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    purchase_order_id UUID NOT NULL REFERENCES purchase_orders(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES product_variants(id),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    quantity INT NOT NULL,
    cost INT NOT NULL
);

-- Refunds Table
CREATE TABLE refunds (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    refund_number TEXT NOT NULL,
    status TEXT NOT NULL,
    reason TEXT,
    note TEXT,
    total_amount INT NOT NULL,
    created_by_user_id UUID REFERENCES auth.users(id),
    external_refund_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- #################################
-- ### Supporting System Tables  ###
-- #################################

-- Integrations Table
CREATE TABLE integrations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    platform integration_platform NOT NULL,
    shop_domain TEXT,
    shop_name TEXT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    last_sync_at TIMESTAMPTZ,
    sync_status TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, platform)
);

-- Channel Fees Table
CREATE TABLE channel_fees (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    channel_name TEXT NOT NULL,
    fixed_fee NUMERIC,
    percentage_fee NUMERIC,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, channel_name)
);

-- Webhook Events Table
CREATE TABLE webhook_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    integration_id UUID NOT NULL REFERENCES integrations(id) ON DELETE CASCADE,
    webhook_id TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(integration_id, webhook_id)
);

-- Inventory Ledger Table
CREATE TABLE inventory_ledger (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
    change_type TEXT NOT NULL,
    quantity_change INT NOT NULL,
    new_quantity INT NOT NULL,
    related_id UUID,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Audit Log Table
CREATE TABLE audit_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    details JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Conversations Table
CREATE TABLE conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    is_starred BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_accessed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Messages Table
CREATE TABLE messages (
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
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Feedback Table
CREATE TABLE feedback (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    subject_id UUID NOT NULL,
    subject_type TEXT NOT NULL,
    feedback feedback_type NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Export Jobs Table
CREATE TABLE export_jobs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    requested_by_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'queued',
    download_url TEXT,
    expires_at TIMESTAMPTZ,
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ
);

-- Imports Table
CREATE TABLE imports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    created_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    import_type TEXT NOT NULL,
    file_name TEXT NOT NULL,
    total_rows INT,
    processed_rows INT,
    error_count INT,
    status TEXT NOT NULL DEFAULT 'pending',
    errors JSONB,
    summary JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ
);

-- #########################
-- ### Indexes and Views ###
-- #########################

-- Indexes for performance
CREATE INDEX idx_products_company_id ON products(company_id);
CREATE INDEX idx_variants_company_id_sku ON product_variants(company_id, sku);
CREATE INDEX idx_orders_company_id_created_at ON orders(company_id, created_at DESC);
CREATE INDEX idx_line_items_order_id ON order_line_items(order_id);
CREATE INDEX idx_line_items_variant_id ON order_line_items(variant_id);
CREATE INDEX idx_ledger_variant_id ON inventory_ledger(variant_id);
CREATE INDEX idx_ledger_company_id_created_at ON inventory_ledger(company_id, created_at);

-- Performance-optimized Materialized View for Inventory
CREATE MATERIALIZED VIEW product_variants_with_details_mat AS
SELECT 
    pv.*,
    p.title as product_title,
    p.status as product_status,
    p.image_url,
    p.product_type
FROM product_variants pv
JOIN products p ON pv.product_id = p.id;

CREATE UNIQUE INDEX idx_product_variants_with_details_mat_id ON product_variants_with_details_mat(id);
CREATE INDEX idx_product_variants_with_details_mat_company_id ON product_variants_with_details_mat(company_id);


-- View for sales data with customer details
CREATE OR REPLACE VIEW orders_view AS
SELECT
    o.*,
    c.email AS customer_email
FROM orders o
LEFT JOIN customers c ON o.customer_id = c.id;

-- View for customer analytics
CREATE OR REPLACE VIEW customers_view AS
SELECT 
    c.id,
    c.company_id,
    c.name as customer_name,
    c.email,
    c.created_at,
    COUNT(o.id) as total_orders,
    SUM(o.total_amount) as total_spent,
    MIN(o.created_at) as first_order_date
FROM customers c
LEFT JOIN orders o ON c.id = o.customer_id
WHERE c.deleted_at IS NULL
GROUP BY c.id;

-- ####################################
-- ### Row Level Security (RLS) ###
-- ####################################

-- Enable RLS for all tables
ALTER TABLE companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE company_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE refunds ENABLE ROW LEVEL SECURITY;
ALTER TABLE integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE channel_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE webhook_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE export_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE imports ENABLE ROW LEVEL SECURITY;

-- Function to get company_id from user's app_metadata
CREATE OR REPLACE FUNCTION get_my_company_id()
RETURNS UUID AS $$
BEGIN
  RETURN (current_setting('request.jwt.claims', true)::jsonb -> 'app_metadata' ->> 'company_id')::UUID;
END;
$$ LANGUAGE plpgsql STABLE;

-- RLS Policies
CREATE POLICY "Allow users to see their own company" ON companies FOR SELECT USING (id = get_my_company_id());
CREATE POLICY "Allow users to see their own company_users" ON company_users FOR SELECT USING (company_id = get_my_company_id());
CREATE POLICY "Allow users to manage data in their own company" ON company_settings FOR ALL USING (company_id = get_my_company_id());
CREATE POLICY "Allow users to manage data in their own company" ON products FOR ALL USING (company_id = get_my_company_id());
CREATE POLICY "Allow users to manage data in their own company" ON product_variants FOR ALL USING (company_id = get_my_company_id());
CREATE POLICY "Allow users to manage data in their own company" ON suppliers FOR ALL USING (company_id = get_my_company_id());
CREATE POLICY "Allow users to manage data in their own company" ON customers FOR ALL USING (company_id = get_my_company_id());
CREATE POLICY "Allow users to manage data in their own company" ON orders FOR ALL USING (company_id = get_my_company_id());
CREATE POLICY "Allow users to manage data in their own company" ON order_line_items FOR ALL USING (company_id = get_my_company_id());
CREATE POLICY "Allow users to manage data in their own company" ON purchase_orders FOR ALL USING (company_id = get_my_company_id());
CREATE POLICY "Allow users to manage data in their own company" ON purchase_order_line_items FOR ALL USING (company_id = get_my_company_id());
CREATE POLICY "Allow users to manage data in their own company" ON refunds FOR ALL USING (company_id = get_my_company_id());
CREATE POLICY "Allow users to manage data in their own company" ON integrations FOR ALL USING (company_id = get_my_company_id());
CREATE POLICY "Allow users to manage data in their own company" ON channel_fees FOR ALL USING (company_id = get_my_company_id());
CREATE POLICY "Allow users to see their own webhook events" ON webhook_events FOR SELECT USING (integration_id IN (SELECT id FROM integrations WHERE company_id = get_my_company_id()));
CREATE POLICY "Allow users to manage data in their own company" ON inventory_ledger FOR ALL USING (company_id = get_my_company_id());
CREATE POLICY "Allow users to see their own audit log" ON audit_log FOR SELECT USING (company_id = get_my_company_id());
CREATE POLICY "Allow users to manage their own conversations" ON conversations FOR ALL USING (user_id = auth.uid());
CREATE POLICY "Allow users to manage messages in their own conversations" ON messages FOR ALL USING (conversation_id IN (SELECT id FROM conversations WHERE user_id = auth.uid()));
CREATE POLICY "Allow users to manage their own feedback" ON feedback FOR ALL USING (user_id = auth.uid());
CREATE POLICY "Allow users to manage their own export jobs" ON export_jobs FOR ALL USING (company_id = get_my_company_id() AND requested_by_user_id = auth.uid());
CREATE POLICY "Allow admins/owners to manage company imports" ON imports FOR ALL USING (company_id = get_my_company_id());

-- #################################
-- ### Database Functions & Triggers ###
-- #################################

-- Function to handle new user signup
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    v_company_name TEXT;
    v_company_id UUID;
BEGIN
    -- Extract company name from user metadata, default if not provided
    v_company_name := NEW.raw_user_meta_data ->> 'company_name';
    IF v_company_name IS NULL OR v_company_name = '' THEN
        v_company_name := NEW.email || '''s Company';
    END IF;

    -- Create a new company for the new user
    INSERT INTO public.companies (name, owner_id)
    VALUES (v_company_name, NEW.id)
    RETURNING id INTO v_company_id;

    -- Link the user to the new company as 'Owner'
    INSERT INTO public.company_users (user_id, company_id, role)
    VALUES (NEW.id, v_company_id, 'Owner');

    -- Update the user's app_metadata with the company_id
    UPDATE auth.users
    SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', v_company_id, 'company_name', v_company_name)
    WHERE id = NEW.id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to execute the function on new user creation
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_user();

-- Function to check user permissions
CREATE OR REPLACE FUNCTION check_user_permission(p_user_id UUID, p_required_role company_role)
RETURNS BOOLEAN AS $$
DECLARE
    user_role company_role;
BEGIN
    SELECT role INTO user_role FROM company_users WHERE user_id = p_user_id;
    IF user_role IS NULL THEN
        RETURN FALSE;
    END IF;
    IF p_required_role = 'Owner' AND user_role = 'Owner' THEN
        RETURN TRUE;
    END IF;
    IF p_required_role = 'Admin' AND (user_role = 'Owner' OR user_role = 'Admin') THEN
        RETURN TRUE;
    END IF;
    RETURN FALSE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to refresh the materialized view
CREATE OR REPLACE FUNCTION refresh_product_variants_view(p_company_id UUID)
RETURNS VOID AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY product_variants_with_details_mat;
END;
$$ LANGUAGE plpgsql;

-- Grant execution rights on functions to the authenticated user role
GRANT EXECUTE ON FUNCTION public.get_my_company_id() TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_user_permission(UUID, company_role) TO authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_product_variants_view(UUID) to authenticated;
-- Grant RLS-bypassing rights to the service role for internal operations if needed
-- Note: Be cautious with this. Typically not needed if functions are SECURITY DEFINER.
ALTER FUNCTION handle_new_user() OWNER TO postgres;

-- Final setup: Set search_path for the supabase_admin user to ensure functions work correctly
-- This is often done in the Supabase dashboard settings but is good to be aware of.
-- ALTER ROLE supabase_admin SET search_path = public, extensions;
