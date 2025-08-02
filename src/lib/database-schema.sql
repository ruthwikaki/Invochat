-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
-- Enable pgcrypto for password hashing
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- =================================================================
-- ENUMS - Define custom types for consistency
-- =================================================================

-- Role definitions for users within a company
CREATE TYPE company_role AS ENUM ('Owner', 'Admin', 'Member');
-- Platform definitions for integrations
CREATE TYPE integration_platform AS ENUM ('shopify', 'woocommerce', 'amazon_fba');
-- Role definitions for chat messages
CREATE TYPE message_role AS ENUM ('user', 'assistant', 'tool');
-- Feedback type definitions
CREATE TYPE feedback_type AS ENUM ('helpful', 'unhelpful');


-- =================================================================
-- CORE TABLES - Base data structures for the application
-- =================================================================

-- Companies Table: Stores information about each business using the app
CREATE TABLE companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    owner_id UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- Enable RLS for company data isolation
ALTER TABLE companies ENABLE ROW LEVEL SECURITY;

-- Company Users Table: Manages user roles within a company (many-to-many)
CREATE TABLE company_users (
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role company_role NOT NULL DEFAULT 'Member',
    PRIMARY KEY (company_id, user_id)
);
-- Enable RLS for role-based access control
ALTER TABLE company_users ENABLE ROW LEVEL SECURITY;


-- =================================================================
-- SETTINGS TABLES - Configuration for each company
-- =================================================================

-- Company Settings Table: Stores business logic parameters for AI and reporting
CREATE TABLE company_settings (
    company_id UUID PRIMARY KEY REFERENCES companies(id) ON DELETE CASCADE,
    dead_stock_days INT NOT NULL DEFAULT 90,
    fast_moving_days INT NOT NULL DEFAULT 30,
    overstock_multiplier INT NOT NULL DEFAULT 3,
    high_value_threshold INT NOT NULL DEFAULT 100000, -- in cents
    predictive_stock_days INT NOT NULL DEFAULT 7,
    currency TEXT DEFAULT 'USD',
    timezone TEXT DEFAULT 'UTC',
    tax_rate NUMERIC DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    subscription_status TEXT DEFAULT 'trial',
    subscription_plan TEXT DEFAULT 'starter',
    subscription_expires_at TIMESTAMPTZ,
    stripe_customer_id TEXT,
    stripe_subscription_id TEXT,
    promo_sales_lift_multiplier REAL NOT NULL DEFAULT 2.5,
    alert_settings JSONB DEFAULT '{"dismissal_hours": 24, "email_notifications": true, "enabled_alert_types": ["low_stock", "out_of_stock", "overstock"], "low_stock_threshold": 10, "morning_briefing_time": "09:00", "critical_stock_threshold": 5, "morning_briefing_enabled": true}'::jsonb,
    CONSTRAINT dead_stock_days_positive CHECK (dead_stock_days > 0)
);
-- Enable RLS for settings
ALTER TABLE company_settings ENABLE ROW LEVEL SECURITY;

-- Channel Fees Table: Stores fees for different sales channels for accurate profit calculation
CREATE TABLE channel_fees (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    channel_name TEXT NOT NULL,
    percentage_fee NUMERIC NOT NULL,
    fixed_fee NUMERIC NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, channel_name)
);
-- Enable RLS
ALTER TABLE channel_fees ENABLE ROW LEVEL SECURITY;


-- =================================================================
-- INVENTORY TABLES - Core product and stock management
-- =================================================================

-- Products Table: Central repository for product information
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
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ
);
-- Add index for faster lookups
CREATE INDEX idx_products_company_id ON products(company_id);
CREATE UNIQUE INDEX idx_products_company_id_external_id ON products(company_id, external_product_id) WHERE external_product_id IS NOT NULL;
-- Enable RLS
ALTER TABLE products ENABLE ROW LEVEL SECURITY;

-- Product Variants Table: Stores individual SKUs for each product
CREATE TABLE product_variants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    sku TEXT NOT NULL,
    title TEXT,
    option1_name TEXT, option1_value TEXT,
    option2_name TEXT, option2_value TEXT,
    option3_name TEXT, option3_value TEXT,
    barcode TEXT,
    price INT, -- in cents
    compare_at_price INT, -- in cents
    cost INT, -- in cents
    inventory_quantity INT NOT NULL DEFAULT 0,
    reserved_quantity INT NOT NULL DEFAULT 0,
    in_transit_quantity INT NOT NULL DEFAULT 0,
    reorder_point INT,
    reorder_quantity INT,
    supplier_id UUID REFERENCES suppliers(id) ON DELETE SET NULL,
    location TEXT,
    external_variant_id TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    version INT NOT NULL DEFAULT 1,
    CONSTRAINT inventory_quantity_non_negative CHECK (inventory_quantity >= 0)
);
-- Add indexes for performance
CREATE INDEX idx_product_variants_product_id ON product_variants(product_id);
CREATE INDEX idx_product_variants_company_id ON product_variants(company_id);
CREATE UNIQUE INDEX idx_product_variants_company_id_sku ON product_variants(company_id, sku);
-- Enable RLS
ALTER TABLE product_variants ENABLE ROW LEVEL SECURITY;


-- =================================================================
-- SALES & CUSTOMER TABLES
-- =================================================================

-- Customers Table
CREATE TABLE customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    name TEXT,
    email TEXT,
    phone TEXT,
    external_customer_id TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ
);
-- Enable RLS
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;


-- Orders Table
CREATE TABLE orders (
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
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    CONSTRAINT total_amount_positive CHECK (total_amount >= 0)
);
-- Enable RLS
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

-- Order Line Items Table
CREATE TABLE order_line_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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
-- Enable RLS
ALTER TABLE order_line_items ENABLE ROW LEVEL SECURITY;


-- =================================================================
-- PURCHASING & SUPPLIER TABLES
-- =================================================================

-- Suppliers Table
CREATE TABLE suppliers (
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
-- Enable RLS
ALTER TABLE suppliers ENABLE ROW LEVEL SECURITY;

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
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);
-- Enable RLS
ALTER TABLE purchase_orders ENABLE ROW LEVEL SECURITY;

-- Purchase Order Line Items Table
CREATE TABLE purchase_order_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    purchase_order_id UUID NOT NULL REFERENCES purchase_orders(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    quantity INT NOT NULL,
    cost INT NOT NULL
);
-- Enable RLS
ALTER TABLE purchase_order_line_items ENABLE ROW LEVEL SECURITY;


-- =================================================================
-- LOGGING & HISTORY TABLES
-- =================================================================

-- Inventory Ledger Table: Tracks every stock movement
CREATE TABLE inventory_ledger (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    variant_id UUID NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    change_type TEXT NOT NULL,
    quantity_change INT NOT NULL,
    new_quantity INT NOT NULL,
    related_id UUID,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- Enable RLS
ALTER TABLE inventory_ledger ENABLE ROW LEVEL SECURITY;

-- Audit Log Table: Tracks significant user actions
CREATE TABLE audit_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id),
    action TEXT NOT NULL,
    details JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- Enable RLS
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;

-- =================================================================
-- AI & INTEGRATION TABLES
-- =================================================================

-- Conversations Table: Stores chat conversation metadata
CREATE TABLE conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_accessed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_starred BOOLEAN NOT NULL DEFAULT FALSE
);
-- Enable RLS
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;

-- Messages Table: Stores individual chat messages
CREATE TABLE messages (
    id TEXT PRIMARY KEY,
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    role message_role NOT NULL,
    content TEXT NOT NULL,
    visualization JSONB,
    component TEXT,
    componentProps JSONB,
    confidence NUMERIC(2,1),
    assumptions TEXT[],
    isError BOOLEAN,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- Enable RLS
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

-- Integrations Table
CREATE TABLE integrations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    platform integration_platform NOT NULL,
    shop_domain TEXT,
    shop_name TEXT,
    is_active BOOLEAN DEFAULT FALSE,
    last_sync_at TIMESTAMPTZ,
    sync_status TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, platform)
);
-- Enable RLS
ALTER TABLE integrations ENABLE ROW LEVEL SECURITY;

-- =================================================================
-- VIEWS
-- =================================================================

-- Customer view to match application expectations
CREATE OR REPLACE VIEW customers_view AS
SELECT 
    c.id,
    c.company_id,
    c.name as customer_name,
    c.email,
    COALESCE(order_stats.total_orders, 0) as total_orders,
    COALESCE(order_stats.total_spent, 0) as total_spent,
    c.created_at
FROM customers c
LEFT JOIN (
    SELECT 
        customer_id,
        COUNT(id) as total_orders,
        SUM(total_amount) as total_spent
    FROM orders 
    WHERE customer_id IS NOT NULL
    GROUP BY customer_id
) order_stats ON c.id = order_stats.customer_id
WHERE c.deleted_at IS NULL;

-- Orders view with customer email
CREATE OR REPLACE VIEW orders_view AS
SELECT 
    o.*,
    c.email as customer_email
FROM orders o
LEFT JOIN customers c ON o.customer_id = c.id;

-- Audit log view with user email
CREATE OR REPLACE VIEW audit_log_view AS
SELECT 
    al.*,
    au.email as user_email
FROM audit_log al
LEFT JOIN auth.users au ON al.user_id = au.id;

-- Purchase orders view with supplier and line items
CREATE OR REPLACE VIEW purchase_orders_view AS
SELECT 
    po.*,
    s.name as supplier_name,
    COALESCE(
        json_agg(
            json_build_object(
                'id', poli.id,
                'quantity', poli.quantity,
                'cost', poli.cost,
                'sku', pv.sku,
                'product_name', p.title
            )
        ) FILTER (WHERE poli.id IS NOT NULL), 
        '[]'::json
    ) as line_items
FROM purchase_orders po
LEFT JOIN suppliers s ON po.supplier_id = s.id
LEFT JOIN purchase_order_line_items poli ON po.id = poli.purchase_order_id
LEFT JOIN product_variants pv ON poli.variant_id = pv.id
LEFT JOIN products p ON pv.product_id = p.id
GROUP BY po.id, s.name;

-- Feedback view with user messages
CREATE OR REPLACE VIEW feedback_view AS
SELECT
    f.id,
    f.created_at,
    f.feedback,
    u.email as user_email,
    m.content as user_message_content,
    a.content as assistant_message_content
FROM feedback f
JOIN users u ON f.user_id = u.id
JOIN messages m ON f.subject_id = m.id AND m.role = 'user'
JOIN messages a ON m.conversation_id = a.conversation_id AND a.role = 'assistant' AND a.created_at > m.created_at
ORDER BY a.created_at ASC
LIMIT 1;

-- Product variants view with product details
CREATE OR REPLACE VIEW product_variants_with_details AS
SELECT 
    pv.*,
    p.title as product_title,
    p.status as product_status,
    p.image_url,
    p.product_type
FROM product_variants pv
JOIN products p ON pv.product_id = p.id;

-- =================================================================
-- FUNCTIONS
-- =================================================================

-- Refresh materialized views function
CREATE OR REPLACE FUNCTION refresh_all_matviews(p_company_id UUID)
RETURNS void AS $$
BEGIN
    -- This is a placeholder. Add REFRESH MATERIALIZED VIEW commands here if you create any.
    RAISE NOTICE 'Refreshing materialized views for company %', p_company_id;
END;
$$ LANGUAGE plpgsql;

-- Create full purchase order function
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
    v_po_id UUID;
    v_po_number TEXT;
    v_total_cost INT;
    v_line_item JSONB;
BEGIN
    -- Generate PO number
    v_po_number := 'PO-' || TO_CHAR(NOW(), 'YYYYMMDD') || '-' || 
                   LPAD((EXTRACT(EPOCH FROM NOW()) % 86400)::TEXT, 5, '0');
    
    -- Calculate total cost
    SELECT SUM((item->>'quantity')::INT * (item->>'cost')::INT)
    INTO v_total_cost
    FROM jsonb_array_elements(p_line_items) item;
    
    -- Insert purchase order
    INSERT INTO purchase_orders (
        company_id, supplier_id, status, po_number, 
        total_cost, expected_arrival_date, notes
    ) VALUES (
        p_company_id, p_supplier_id, p_status, v_po_number,
        v_total_cost, p_expected_arrival, p_notes
    ) RETURNING id INTO v_po_id;
    
    -- Insert line items
    FOR v_line_item IN SELECT * FROM jsonb_array_elements(p_line_items)
    LOOP
        INSERT INTO purchase_order_line_items (
            purchase_order_id, company_id, variant_id, quantity, cost
        ) VALUES (
            v_po_id, p_company_id,
            (v_line_item->>'variant_id')::UUID,
            (v_line_item->>'quantity')::INT,
            (v_line_item->>'cost')::INT
        );
    END LOOP;
    
    RETURN v_po_id;
END;
$$ LANGUAGE plpgsql;

-- =================================================================
-- RLS POLICIES
-- =================================================================

-- Helper function to get company_id from user's app_metadata
CREATE OR REPLACE FUNCTION auth.company_id()
RETURNS UUID AS $$
DECLARE
    company_id_val UUID;
BEGIN
    SELECT NULLIF(current_setting('request.jwt.claims', true)::JSONB ->> 'app_metadata', '')::JSONB ->> 'company_id' INTO company_id_val;
    RETURN company_id_val;
END;
$$ LANGUAGE plpgsql STABLE;

-- Policies for companies table
CREATE POLICY "Users can only see their own company" ON companies
FOR SELECT USING (id = auth.company_id());

-- Policies for company_users table
CREATE POLICY "Users can see other members of their own company" ON company_users
FOR SELECT USING (company_id = auth.company_id());

-- Generic policy for all other tables with a company_id
DO $$
DECLARE
    t TEXT;
BEGIN
    FOR t IN 
        SELECT table_name FROM information_schema.columns WHERE column_name = 'company_id' AND table_name NOT IN ('companies', 'company_users')
    LOOP
        EXECUTE format('CREATE POLICY "Users can only access their own company data" ON %I FOR ALL USING (company_id = auth.company_id());', t);
    END LOOP;
END;
$$;


-- =================================================================
-- TRIGGERS
-- =================================================================

-- Function to create a company for a new user and assign them as Owner
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  company_id_var UUID;
  company_name_var TEXT;
BEGIN
  -- Extract company name from metadata, default to "My Company"
  company_name_var := NEW.raw_app_meta_data ->> 'company_name';
  IF company_name_var IS NULL OR company_name_var = '' THEN
      company_name_var := 'My Company';
  END IF;

  -- Create a new company for the user
  INSERT INTO public.companies (name, owner_id)
  VALUES (company_name_var, NEW.id)
  RETURNING id INTO company_id_var;
  
  -- Link the user to the new company as 'Owner'
  INSERT INTO public.company_users (user_id, company_id, role)
  VALUES (NEW.id, company_id_var, 'Owner');

  -- Update the user's app_metadata with the new company_id
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id_var)
  WHERE id = NEW.id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to execute the function after a new user is created
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Trigger to update 'updated_at' timestamps automatically
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE
    t TEXT;
BEGIN
    FOR t IN 
        SELECT table_name FROM information_schema.columns WHERE column_name = 'updated_at'
    LOOP
        EXECUTE format('CREATE TRIGGER set_timestamp
                        BEFORE UPDATE ON %I
                        FOR EACH ROW
                        EXECUTE FUNCTION public.set_updated_at();', t);
    END LOOP;
END;
$$;
