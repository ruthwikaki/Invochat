-- InvoChat Production-Ready Database Schema
-- Version: 2.0
-- Description: This script sets up all tables, types, functions, and security policies
-- required for the application. It is designed to be idempotent and can be run safely
-- on a new or existing database.

-- 1. Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 2. Custom Types
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE user_role AS ENUM ('Owner', 'Admin', 'Member');
    END IF;
END$$;

-- 3. Helper & Security Functions
-- Helper function to get company_id from a user's JWT claims.
CREATE OR REPLACE FUNCTION get_my_company_id()
RETURNS uuid
LANGUAGE sql STABLE
AS $$
  SELECT COALESCE(
    current_setting('request.jwt.claims', true)::jsonb ->> 'company_id',
    (auth.jwt() -> 'app_metadata' ->> 'company_id')
  )::uuid;
$$;

-- Helper function to check if a user is a member of a given company.
CREATE OR REPLACE FUNCTION is_member_of_company(p_company_id uuid)
RETURNS boolean
LANGUAGE plpgsql STABLE
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM public.users
    WHERE id = auth.uid() AND company_id = p_company_id
  );
END;
$$;


-- 4. Core Tables
CREATE TABLE IF NOT EXISTS companies (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS users (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  email text,
  role user_role NOT NULL DEFAULT 'Member',
  deleted_at timestamptz,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS company_settings (
    company_id uuid PRIMARY KEY REFERENCES companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    fast_moving_days integer NOT NULL DEFAULT 30,
    overstock_multiplier numeric NOT NULL DEFAULT 3,
    high_value_threshold numeric NOT NULL DEFAULT 1000,
    predictive_stock_days integer NOT NULL DEFAULT 7,
    promo_sales_lift_multiplier real NOT NULL DEFAULT 2.5,
    currency text DEFAULT 'USD',
    timezone text DEFAULT 'UTC',
    updated_at timestamptz
);

-- 5. Product Catalog Tables
CREATE TABLE IF NOT EXISTS products (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES companies(id),
    title text NOT NULL,
    description text,
    handle text,
    product_type text,
    status text NOT NULL DEFAULT 'active', -- e.g., active, draft, archived
    image_url text,
    tags text[],
    external_product_id text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    CONSTRAINT unique_external_product_id UNIQUE (company_id, external_product_id)
);

CREATE TABLE IF NOT EXISTS product_variants (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id uuid NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES companies(id),
    sku text NOT NULL,
    title text,
    option1_name text,
    option1_value text,
    option2_name text,
    option2_value text,
    option3_name text,
    option3_value text,
    barcode text,
    price integer, -- in cents
    compare_at_price integer, -- in cents
    cost integer, -- in cents
    inventory_quantity integer NOT NULL DEFAULT 0,
    external_variant_id text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    CONSTRAINT unique_sku_per_company UNIQUE (company_id, sku),
    CONSTRAINT unique_external_variant_id UNIQUE (company_id, external_variant_id)
);

CREATE TABLE IF NOT EXISTS product_collections (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES companies(id),
    title text NOT NULL,
    handle text,
    description text,
    image_url text,
    external_collection_id text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS product_collection_items (
    product_id uuid NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    collection_id uuid NOT NULL REFERENCES product_collections(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES companies(id),
    position integer,
    PRIMARY KEY (product_id, collection_id)
);


-- 6. Sales & Customer Tables
CREATE TABLE IF NOT EXISTS customers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES companies(id),
    customer_name text,
    email text,
    total_orders integer DEFAULT 0,
    total_spent integer DEFAULT 0, -- in cents
    created_at timestamptz DEFAULT now(),
    deleted_at timestamptz,
    CONSTRAINT unique_customer_email UNIQUE (company_id, email)
);

CREATE TABLE IF NOT EXISTS orders (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES companies(id),
    order_number text NOT NULL,
    external_order_id text,
    customer_id uuid REFERENCES customers(id),
    financial_status text,
    fulfillment_status text,
    currency text,
    subtotal integer,
    total_tax integer,
    total_shipping integer,
    total_discounts integer,
    total_amount integer NOT NULL,
    source_platform text,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT unique_external_order_id UNIQUE (company_id, external_order_id)
);

CREATE TABLE IF NOT EXISTS order_line_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES product_variants(id),
    company_id uuid NOT NULL REFERENCES companies(id),
    product_name text,
    variant_title text,
    sku text,
    quantity integer NOT NULL,
    price integer NOT NULL, -- in cents
    total_discount integer,
    tax_amount integer,
    cost_at_time integer,
    external_line_item_id text
);

CREATE TABLE IF NOT EXISTS refunds (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES companies(id),
    order_id uuid NOT NULL REFERENCES orders(id),
    status text,
    reason text,
    note text,
    total_amount integer NOT NULL,
    created_by_user_id uuid,
    external_refund_id text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS refund_line_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    refund_id uuid NOT NULL REFERENCES refunds(id),
    order_line_item_id uuid NOT NULL REFERENCES order_line_items(id),
    quantity integer NOT NULL,
    amount integer NOT NULL,
    restock boolean NOT NULL DEFAULT false
);

-- 7. Inventory & Supplier Tables
CREATE TABLE IF NOT EXISTS suppliers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES companies(id),
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE product_variants ADD COLUMN IF NOT EXISTS supplier_id uuid REFERENCES suppliers(id);

CREATE TABLE IF NOT EXISTS inventory_adjustments (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES companies(id),
    variant_id uuid NOT NULL REFERENCES product_variants(id),
    adjustment_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    reason text,
    cost_adjustment integer,
    adjusted_by_user_id uuid REFERENCES users(id),
    created_at timestamptz NOT NULL DEFAULT now()
);


-- 8. App-Specific Tables
CREATE TABLE IF NOT EXISTS conversations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL REFERENCES users(id),
    company_id uuid NOT NULL REFERENCES companies(id),
    title text NOT NULL,
    created_at timestamptz DEFAULT now(),
    last_accessed_at timestamptz DEFAULT now(),
    is_starred boolean DEFAULT false
);

CREATE TABLE IF NOT EXISTS messages (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id uuid NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL,
    role text NOT NULL,
    content text,
    component text,
    component_props jsonb,
    visualization jsonb,
    confidence numeric,
    assumptions text[],
    is_error boolean DEFAULT false,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS integrations (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  platform text NOT NULL,
  shop_domain text,
  shop_name text,
  is_active boolean DEFAULT false,
  last_sync_at timestamptz,
  sync_status text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz
);

CREATE TABLE IF NOT EXISTS platform_webhooks (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    integration_id uuid NOT NULL REFERENCES integrations(id) ON DELETE CASCADE,
    webhook_id text NOT NULL,
    topic text NOT NULL,
    status text NOT NULL DEFAULT 'active',
    last_error text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    CONSTRAINT unique_webhook_id_for_integration UNIQUE (integration_id, webhook_id)
);


-- 9. Setup Triggers & Core Functions
-- This function handles creating a new company and user profile when a new user signs up.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_company_name text := new.raw_app_meta_data ->> 'company_name';
BEGIN
  -- Create a new company for the user
  INSERT INTO public.companies (name)
  VALUES (v_company_name)
  RETURNING id INTO v_company_id;

  -- Create a corresponding public user profile
  INSERT INTO public.users (id, email, company_id, role)
  VALUES (new.id, new.email, v_company_id, 'Owner');
  
  -- Create default settings for the new company
  INSERT INTO public.company_settings (company_id)
  VALUES (v_company_id);

  -- Update the user's app_metadata with the new company_id
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', v_company_id)
  WHERE id = new.id;

  RETURN new;
END;
$$;

-- Drop the trigger if it exists before creating it
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
-- Create the trigger to run the function after a new user is created in auth.users
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Trigger to update inventory_quantity on inventory_adjustments insert
CREATE OR REPLACE FUNCTION update_variant_quantity()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE product_variants
    SET inventory_quantity = NEW.new_quantity,
        updated_at = NOW()
    WHERE id = NEW.variant_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS on_inventory_adjustment ON inventory_adjustments;
CREATE TRIGGER on_inventory_adjustment
    AFTER INSERT ON inventory_adjustments
    FOR EACH ROW
    EXECUTE FUNCTION update_variant_quantity();


-- 10. Row Level Security (RLS)
-- Enable RLS on all relevant tables
ALTER TABLE companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_collections ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_collection_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE refunds ENABLE ROW LEVEL SECURITY;
ALTER TABLE refund_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_adjustments ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE platform_webhooks ENABLE ROW LEVEL SECURITY;

-- RLS Policies
-- Users can see their own company and their own user record.
DROP POLICY IF EXISTS "Allow owner access" ON companies;
CREATE POLICY "Allow owner access" ON companies FOR SELECT USING (is_member_of_company(id));

DROP POLICY IF EXISTS "Allow user to see their own profile" ON users;
CREATE POLICY "Allow user to see their own profile" ON users FOR SELECT USING (id = auth.uid());

-- General policy for most tables: allow access if the user is part of the company.
CREATE OR REPLACE FUNCTION create_company_based_policy(table_name text)
RETURNS void AS $$
BEGIN
    EXECUTE format('DROP POLICY IF EXISTS "Allow access to own company data" ON %I;', table_name);
    EXECUTE format('CREATE POLICY "Allow access to own company data" ON %I FOR ALL USING (company_id = get_my_company_id());', table_name);
END;
$$ LANGUAGE plpgsql;

SELECT create_company_based_policy(table_name)
FROM (VALUES
    ('company_settings'), ('products'), ('product_variants'), ('product_collections'),
    ('product_collection_items'), ('customers'), ('orders'), ('order_line_items'),
    ('refunds'), ('refund_line_items'), ('suppliers'), ('inventory_adjustments'),
    ('conversations'), ('messages'), ('integrations')
) AS t(table_name);

-- Special policy for webhooks table
DROP POLICY IF EXISTS "Allow access based on integration" ON platform_webhooks;
CREATE POLICY "Allow access based on integration" ON platform_webhooks
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM integrations
            WHERE id = platform_webhooks.integration_id
            AND company_id = get_my_company_id()
        )
    );

-- 11. Indexes for Performance
CREATE INDEX IF NOT EXISTS idx_products_company_id ON products(company_id);
CREATE INDEX IF NOT EXISTS idx_variants_product_id ON product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_variants_company_sku ON product_variants(company_id, sku);
CREATE INDEX IF NOT EXISTS idx_orders_company_date ON orders(company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_line_items_order_id ON order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_line_items_variant_id ON order_line_items(variant_id);
CREATE INDEX IF NOT EXISTS idx_customers_company_email ON customers(company_id, email);
CREATE INDEX IF NOT EXISTS idx_adjustments_variant_id ON inventory_adjustments(variant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_conversations_user_id ON conversations(user_id, last_accessed_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id ON messages(conversation_id, created_at ASC);


-- 12. Final Grants
GRANT USAGE ON SCHEMA public TO authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated, service_role;

-- Log success
DO $$
BEGIN
    RAISE NOTICE 'Database schema setup complete.';
END $$;
