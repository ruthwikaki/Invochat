
-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Custom Types
CREATE TYPE user_role AS ENUM ('Owner', 'Admin', 'Member');

-- Tables
CREATE TABLE IF NOT EXISTS companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id),
    email TEXT,
    role user_role NOT NULL DEFAULT 'Member',
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS company_settings (
    company_id UUID PRIMARY KEY REFERENCES companies(id) ON DELETE CASCADE,
    dead_stock_days INT NOT NULL DEFAULT 90,
    fast_moving_days INT NOT NULL DEFAULT 30,
    overstock_multiplier NUMERIC NOT NULL DEFAULT 3,
    high_value_threshold NUMERIC NOT NULL DEFAULT 1000,
    predictive_stock_days INT NOT NULL DEFAULT 7,
    currency TEXT DEFAULT 'USD',
    timezone TEXT DEFAULT 'UTC',
    promo_sales_lift_multiplier REAL NOT NULL DEFAULT 2.5,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id),
    title TEXT NOT NULL,
    description TEXT,
    handle TEXT,
    product_type TEXT,
    tags TEXT[],
    status TEXT NOT NULL DEFAULT 'active', -- active, draft, archived
    image_url TEXT,
    external_product_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_products_company_id ON products(company_id);

CREATE TABLE IF NOT EXISTS product_variants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id),
    sku TEXT NOT NULL,
    title TEXT,
    option1_name TEXT,
    option1_value TEXT,
    option2_name TEXT,
    option2_value TEXT,
    option3_name TEXT,
    option3_value TEXT,
    barcode TEXT,
    price NUMERIC NOT NULL DEFAULT 0,
    compare_at_price NUMERIC,
    cost NUMERIC,
    inventory_quantity INT NOT NULL DEFAULT 0,
    external_variant_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, sku),
    UNIQUE(company_id, external_variant_id)
);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_company_id ON product_variants(company_id);

CREATE TABLE IF NOT EXISTS customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id),
    first_name TEXT,
    last_name TEXT,
    email TEXT,
    phone TEXT,
    total_orders INT DEFAULT 0,
    total_spent NUMERIC DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(company_id, email)
);
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON customers(company_id);

CREATE TABLE IF NOT EXISTS orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id),
    order_number TEXT NOT NULL,
    external_order_id TEXT,
    customer_id UUID REFERENCES customers(id),
    status TEXT NOT NULL,
    financial_status TEXT,
    fulfillment_status TEXT,
    currency TEXT,
    subtotal NUMERIC,
    total_tax NUMERIC,
    total_shipping NUMERIC,
    total_discounts NUMERIC,
    total_amount NUMERIC NOT NULL,
    source_platform TEXT,
    source_name TEXT,
    tags TEXT[],
    notes TEXT,
    cancelled_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, external_order_id)
);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON orders(company_id);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON orders(customer_id);

CREATE TABLE IF NOT EXISTS order_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id),
    variant_id UUID NOT NULL REFERENCES product_variants(id),
    product_name TEXT,
    variant_title TEXT,
    sku TEXT,
    quantity INT NOT NULL,
    price NUMERIC NOT NULL,
    total_discount NUMERIC,
    tax_amount NUMERIC,
    fulfillment_status TEXT,
    requires_shipping BOOLEAN,
    external_line_item_id TEXT
);
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON order_line_items(variant_id);

CREATE TABLE IF NOT EXISTS inventory_adjustments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id),
    product_id UUID NOT NULL REFERENCES products(id),
    variant_id UUID NOT NULL REFERENCES product_variants(id),
    adjustment_type TEXT NOT NULL,
    quantity_change INT NOT NULL,
    new_quantity INT NOT NULL,
    reason TEXT,
    cost_adjustment NUMERIC,
    adjusted_by_user_id UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_inventory_adjustments_variant_id ON inventory_adjustments(variant_id);

CREATE TABLE IF NOT EXISTS conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id),
    company_id UUID REFERENCES companies(id),
    title TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    last_accessed_at TIMESTAMPTZ DEFAULT NOW(),
    is_starred BOOLEAN DEFAULT FALSE
);

CREATE TABLE IF NOT EXISTS messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id),
    role TEXT NOT NULL,
    content TEXT,
    component TEXT,
    component_props JSONB,
    visualization JSONB,
    confidence NUMERIC,
    assumptions TEXT[],
    created_at TIMESTAMPTZ DEFAULT NOW(),
    is_error BOOLEAN DEFAULT FALSE
);

CREATE TABLE IF NOT EXISTS integrations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id),
    platform TEXT NOT NULL,
    shop_domain TEXT,
    shop_name TEXT,
    is_active BOOLEAN DEFAULT FALSE,
    last_sync_at TIMESTAMPTZ,
    sync_status TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, platform)
);

CREATE TABLE IF NOT EXISTS sync_state (
    integration_id UUID NOT NULL REFERENCES integrations(id) ON DELETE CASCADE,
    sync_type TEXT NOT NULL,
    last_processed_cursor TEXT,
    last_update TIMESTAMPTZ,
    PRIMARY KEY (integration_id, sync_type)
);

CREATE TABLE IF NOT EXISTS audit_log (
    id BIGSERIAL PRIMARY KEY,
    company_id UUID REFERENCES companies(id),
    user_id UUID REFERENCES auth.users(id),
    action TEXT NOT NULL,
    details JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS Policies
ALTER TABLE companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_adjustments ENABLE ROW LEVEL SECURITY;
ALTER TABLE integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION is_member_of_company(p_company_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1
        FROM users
        WHERE users.id = auth.uid() AND users.company_id = p_company_id
    );
END;
$$;

DROP POLICY IF EXISTS "allow all for service role" ON companies;
CREATE POLICY "allow all for service role" ON companies FOR ALL USING (TRUE);

DROP POLICY IF EXISTS "allow read for company members" ON companies;
CREATE POLICY "allow read for company members" ON companies FOR SELECT USING (is_member_of_company(id));

-- Add similar policies for other tables
-- Example for products:
DROP POLICY IF EXISTS "allow all for service role" ON products;
CREATE POLICY "allow all for service role" ON products FOR ALL USING (TRUE);

DROP POLICY IF EXISTS "allow access for company members" ON products;
CREATE POLICY "allow access for company members" ON products FOR ALL USING (is_member_of_company(company_id));

-- Apply policies to all other new tables
-- ... (Repeat for product_variants, orders, etc.)

-- Functions
-- Function to handle new user setup
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID;
  v_company_name TEXT;
  v_user_role user_role := 'Owner';
BEGIN
  -- Extract company name from metadata
  v_company_name := NEW.raw_app_meta_data->>'company_name';

  -- Create a new company for the user
  INSERT INTO companies (name)
  VALUES (COALESCE(v_company_name, 'My Company'))
  RETURNING id INTO v_company_id;

  -- Insert into our public users table
  INSERT INTO users (id, company_id, email, role)
  VALUES (NEW.id, v_company_id, NEW.email, v_user_role);
  
  -- Update the user's app_metadata with the new company_id and role
  NEW.raw_app_meta_data := NEW.raw_app_meta_data || jsonb_build_object('company_id', v_company_id, 'role', v_user_role);

  RETURN NEW;
END;
$$;

-- Trigger for new user setup
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  WHEN (NEW.raw_app_meta_data->>'company_name' IS NOT NULL)
  EXECUTE FUNCTION handle_new_user();

-- Function for inventory adjustments
CREATE OR REPLACE FUNCTION adjust_inventory(
    p_variant_id UUID,
    p_company_id UUID,
    p_quantity_change INT,
    p_adjustment_type TEXT,
    p_reason TEXT,
    p_user_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_new_quantity INT;
    v_product_id UUID;
BEGIN
    -- Update inventory quantity and get new quantity
    UPDATE product_variants
    SET inventory_quantity = inventory_quantity + p_quantity_change
    WHERE id = p_variant_id AND company_id = p_company_id
    RETURNING inventory_quantity, product_id INTO v_new_quantity, v_product_id;

    -- Log the adjustment
    INSERT INTO inventory_adjustments (company_id, product_id, variant_id, adjustment_type, quantity_change, new_quantity, reason, adjusted_by_user_id)
    VALUES (p_company_id, v_product_id, p_variant_id, p_adjustment_type, p_quantity_change, v_new_quantity, p_reason, p_user_id);
END;
$$;
