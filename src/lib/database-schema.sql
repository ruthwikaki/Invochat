
-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Enable pgcrypto for cryptographic functions
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Set timezone to UTC
SET TIME ZONE 'UTC';

-- =================================================================
-- Helper function to get the current user's ID
-- =================================================================
CREATE OR REPLACE FUNCTION auth.get_current_user_id()
RETURNS uuid
LANGUAGE sql STABLE
AS $$
  SELECT nullif(current_setting('request.jwt.claims', true)::json->>'sub', '')::uuid;
$$;

-- =================================================================
-- Schemas, Tables, and Types
-- =================================================================

-- Custom types
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE user_role AS ENUM ('Owner', 'Admin', 'Member');
    END IF;
END$$;


-- Companies Table
CREATE TABLE IF NOT EXISTS companies (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Users Table (bridges auth.users and our public data)
CREATE TABLE IF NOT EXISTS users (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    role user_role NOT NULL DEFAULT 'Member',
    email text,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now()
);

-- Company Settings Table
CREATE TABLE IF NOT EXISTS company_settings (
    company_id uuid PRIMARY KEY REFERENCES companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    fast_moving_days integer NOT NULL DEFAULT 30,
    overstock_multiplier integer NOT NULL DEFAULT 3,
    high_value_threshold integer NOT NULL DEFAULT 100000, -- in cents
    predictive_stock_days integer NOT NULL DEFAULT 7,
    currency text DEFAULT 'USD',
    timezone text DEFAULT 'UTC',
    tax_rate numeric DEFAULT 0,
    custom_rules jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);

-- Products Table
CREATE TABLE IF NOT EXISTS products (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    description text,
    handle text,
    product_type text,
    tags text[],
    status text,
    image_url text,
    external_product_id text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    fts_document tsvector GENERATED ALWAYS AS (to_tsvector('english', title || ' ' || coalesce(description, ''))) STORED
);
CREATE INDEX IF NOT EXISTS idx_products_company_id ON products(company_id);
CREATE INDEX IF NOT EXISTS idx_products_external_id ON products(external_product_id);
CREATE INDEX IF NOT EXISTS idx_fts_document ON products USING GIN (fts_document);

-- Product Variants Table
CREATE TABLE IF NOT EXISTS product_variants (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id uuid NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
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
    location text,
    external_variant_id text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz
);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_sku_company_id ON product_variants(sku, company_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_product_variants_company_external_id ON product_variants(company_id, external_variant_id);


-- Suppliers Table
CREATE TABLE IF NOT EXISTS suppliers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON suppliers(company_id);

-- Customers Table
CREATE TABLE IF NOT EXISTS customers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    customer_name text NOT NULL,
    email text,
    total_orders integer DEFAULT 0,
    total_spent integer DEFAULT 0,
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON customers(company_id);
CREATE INDEX IF NOT EXISTS idx_customers_email ON customers(email);

-- Orders Table
CREATE TABLE IF NOT EXISTS orders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    order_number text NOT NULL,
    external_order_id text,
    customer_id uuid REFERENCES customers(id),
    status text NOT NULL DEFAULT 'pending',
    financial_status text DEFAULT 'pending',
    fulfillment_status text DEFAULT 'unfulfilled',
    currency text DEFAULT 'USD',
    subtotal integer NOT NULL DEFAULT 0,
    total_tax integer DEFAULT 0,
    total_shipping integer DEFAULT 0,
    total_discounts integer DEFAULT 0,
    total_amount integer NOT NULL,
    source_platform text,
    source_name text,
    tags text[],
    notes text,
    cancelled_at timestamptz,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz
);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON orders(company_id);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON orders(created_at);

-- Order Line Items Table
CREATE TABLE IF NOT EXISTS order_line_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    variant_id uuid REFERENCES product_variants(id),
    product_id uuid REFERENCES products(id),
    product_name text NOT NULL,
    variant_title text,
    sku text,
    quantity integer NOT NULL,
    price integer NOT NULL,
    total_discount integer DEFAULT 0,
    tax_amount integer DEFAULT 0,
    cost_at_time integer,
    fulfillment_status text DEFAULT 'unfulfilled',
    requires_shipping boolean DEFAULT true,
    external_line_item_id text
);
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON order_line_items(variant_id);


-- Inventory Ledger Table
CREATE TABLE IF NOT EXISTS inventory_ledger (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
    change_type text NOT NULL, -- e.g., 'sale', 'purchase_order', 'manual_adjustment'
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid, -- e.g., order_id, purchase_order_id
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id ON inventory_ledger(variant_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_created_at ON inventory_ledger(created_at);

-- Purchase Orders Table
CREATE TABLE IF NOT EXISTS purchase_orders (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES suppliers(id),
    status text NOT NULL DEFAULT 'Draft',
    po_number text NOT NULL,
    total_cost integer NOT NULL,
    expected_arrival_date date,
    idempotency_key uuid,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_company_id ON purchase_orders(company_id);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_supplier_id ON purchase_orders(supplier_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_purchase_orders_idempotency ON purchase_orders(idempotency_key);

-- Purchase Order Line Items Table
CREATE TABLE IF NOT EXISTS purchase_order_line_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    purchase_order_id uuid NOT NULL REFERENCES purchase_orders(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES product_variants(id),
    quantity integer NOT NULL,
    cost integer NOT NULL -- Cost per unit in cents
);
CREATE INDEX IF NOT EXISTS idx_po_line_items_po_id ON purchase_order_line_items(purchase_order_id);

-- Integrations Table
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
CREATE UNIQUE INDEX IF NOT EXISTS uq_integrations_company_platform ON integrations(company_id, platform);

-- Conversations Table (for AI Chat)
CREATE TABLE IF NOT EXISTS conversations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    is_starred boolean DEFAULT false,
    created_at timestamptz DEFAULT now(),
    last_accessed_at timestamptz DEFAULT now()
);

-- Messages Table (for AI Chat)
CREATE TABLE IF NOT EXISTS messages (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id uuid NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    role text NOT NULL, -- 'user' or 'assistant'
    content text,
    component text,
    component_props jsonb,
    visualization jsonb,
    confidence numeric,
    assumptions text[],
    is_error boolean DEFAULT false,
    created_at timestamptz DEFAULT now()
);

-- Audit Log Table
CREATE TABLE IF NOT EXISTS audit_log (
    id bigserial PRIMARY KEY,
    company_id uuid REFERENCES companies(id),
    user_id uuid REFERENCES auth.users(id),
    action text NOT NULL,
    details jsonb,
    created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_audit_log_company_id ON audit_log(company_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_user_id ON audit_log(user_id);

-- Webhook Events Table (for replay protection)
CREATE TABLE IF NOT EXISTS webhook_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id uuid NOT NULL REFERENCES integrations(id) ON DELETE CASCADE,
    webhook_id text NOT NULL,
    processed_at timestamptz DEFAULT now(),
    created_at timestamptz DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_webhook_events ON webhook_events(integration_id, webhook_id);

-- =================================================================
-- Views for simplified data access
-- =================================================================

-- Create or replace the view for product variants with their details
CREATE OR REPLACE VIEW product_variants_with_details AS
SELECT
    pv.*,
    p.title as product_title,
    p.status as product_status,
    p.image_url as image_url,
    p.product_type
FROM
    product_variants pv
JOIN
    products p ON pv.product_id = p.id;


-- =================================================================
-- Row Level Security (RLS) Policies
-- =================================================================

-- Enable RLS for all relevant tables
ALTER TABLE companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;

-- Drop existing policies before creating new ones to prevent conflicts
DROP POLICY IF EXISTS "Allow all for authenticated users" ON companies;
DROP POLICY IF EXISTS "Allow user to view their own company" ON users;
DROP POLICY IF EXISTS "Allow user to view their own settings" ON company_settings;
DROP POLICY IF EXISTS "Admins can update settings" ON company_settings;
DROP POLICY IF EXISTS "Allow read access to company members" ON products;
DROP POLICY IF EXISTS "Allow admin access" ON products;
DROP POLICY IF EXISTS "Allow read access to company members" ON product_variants;
DROP POLICY IF EXISTS "Allow admin access" ON product_variants;
DROP POLICY IF EXISTS "Allow read access to company members" ON suppliers;
DROP POLICY IF EXISTS "Allow admin access" ON suppliers;
DROP POLICY IF EXISTS "Allow read access to company members" ON customers;
DROP POLICY IF EXISTS "Allow admin access" ON customers;
DROP POLICY IF EXISTS "Allow read access to company members" ON orders;
DROP POLICY IF EXISTS "Allow read access to company members" ON order_line_items;
DROP POLICY IF EXISTS "Allow read access to company members" ON inventory_ledger;
DROP POLICY IF EXISTS "Allow read access to company members" ON purchase_orders;
DROP POLICY IF EXISTS "Allow admin access" ON purchase_orders;
DROP POLICY IF EXISTS "Allow read access to company members" ON purchase_order_line_items;
DROP POLICY IF EXISTS "Allow admin access" ON purchase_order_line_items;
DROP POLICY IF EXISTS "Allow read access to company members" ON integrations;
DROP POLICY IF EXISTS "Allow admin access" ON integrations;
DROP POLICY IF EXISTS "Allow access to own conversations" ON conversations;
DROP POLICY IF EXISTS "Allow access to own messages" ON messages;
DROP POLICY IF EXISTS "Allow read access to company members" ON audit_log;


-- RLS Policies
CREATE POLICY "Allow all for authenticated users" ON companies FOR ALL
    USING (auth.role() = 'authenticated');

CREATE POLICY "Allow user to view their own company" ON users FOR SELECT
    USING (id = auth.uid());

CREATE POLICY "Allow user to view their own settings" ON company_settings FOR SELECT
    USING (company_id = (SELECT company_id FROM users WHERE id = auth.uid()));

CREATE POLICY "Admins can update settings" ON company_settings FOR UPDATE
    USING (company_id = (SELECT company_id FROM users WHERE id = auth.uid()) AND (SELECT role FROM users WHERE id = auth.uid()) = 'Admin')
    WITH CHECK (company_id = (SELECT company_id FROM users WHERE id = auth.uid()) AND (SELECT role FROM users WHERE id = auth.uid()) = 'Admin');

CREATE POLICY "Allow read access to company members" ON products FOR SELECT
    USING (company_id = (SELECT company_id FROM users WHERE id = auth.uid()));
CREATE POLICY "Allow admin access" ON products FOR ALL
    USING (company_id = (SELECT company_id FROM users WHERE id = auth.uid()) AND (SELECT role FROM users WHERE id = auth.uid()) IN ('Admin', 'Owner'));

CREATE POLICY "Allow read access to company members" ON product_variants FOR SELECT
    USING (company_id = (SELECT company_id FROM users WHERE id = auth.uid()));
CREATE POLICY "Allow admin access" ON product_variants FOR ALL
    USING (company_id = (SELECT company_id FROM users WHERE id = auth.uid()) AND (SELECT role FROM users WHERE id = auth.uid()) IN ('Admin', 'Owner'));

CREATE POLICY "Allow read access to company members" ON suppliers FOR SELECT
    USING (company_id = (SELECT company_id FROM users WHERE id = auth.uid()));
CREATE POLICY "Allow admin access" ON suppliers FOR ALL
    USING (company_id = (SELECT company_id FROM users WHERE id = auth.uid()) AND (SELECT role FROM users WHERE id = auth.uid()) IN ('Admin', 'Owner'));

CREATE POLICY "Allow read access to company members" ON customers FOR SELECT
    USING (company_id = (SELECT company_id FROM users WHERE id = auth.uid()));
CREATE POLICY "Allow admin access" ON customers FOR ALL
    USING (company_id = (SELECT company_id FROM users WHERE id = auth.uid()) AND (SELECT role FROM users WHERE id = auth.uid()) IN ('Admin', 'Owner'));

CREATE POLICY "Allow read access to company members" ON orders FOR SELECT
    USING (company_id = (SELECT company_id FROM users WHERE id = auth.uid()));

CREATE POLICY "Allow read access to company members" ON order_line_items FOR SELECT
    USING (company_id = (SELECT company_id FROM users WHERE id = auth.uid()));

CREATE POLICY "Allow read access to company members" ON inventory_ledger FOR SELECT
    USING (company_id = (SELECT company_id FROM users WHERE id = auth.uid()));

CREATE POLICY "Allow read access to company members" ON purchase_orders FOR SELECT
    USING (company_id = (SELECT company_id FROM users WHERE id = auth.uid()));
CREATE POLICY "Allow admin access" ON purchase_orders FOR ALL
    USING (company_id = (SELECT company_id FROM users WHERE id = auth.uid()) AND (SELECT role FROM users WHERE id = auth.uid()) IN ('Admin', 'Owner'));

CREATE POLICY "Allow read access to company members" ON purchase_order_line_items FOR SELECT
    USING (purchase_order_id IN (SELECT id FROM purchase_orders WHERE company_id = (SELECT company_id FROM users WHERE id = auth.uid())));
CREATE POLICY "Allow admin access" ON purchase_order_line_items FOR ALL
    USING (purchase_order_id IN (SELECT id FROM purchase_orders WHERE company_id = (SELECT company_id FROM users WHERE id = auth.uid())) AND (SELECT role FROM users WHERE id = auth.uid()) IN ('Admin', 'Owner'));

CREATE POLICY "Allow read access to company members" ON integrations FOR SELECT
    USING (company_id = (SELECT company_id FROM users WHERE id = auth.uid()));
CREATE POLICY "Allow admin access" ON integrations FOR ALL
    USING (company_id = (SELECT company_id FROM users WHERE id = auth.uid()) AND (SELECT role FROM users WHERE id = auth.uid()) IN ('Admin', 'Owner'));

CREATE POLICY "Allow access to own conversations" ON conversations FOR ALL
    USING (user_id = auth.uid());

CREATE POLICY "Allow access to own messages" ON messages FOR ALL
    USING (company_id = (SELECT company_id FROM users WHERE id = auth.uid()));

CREATE POLICY "Allow read access to company members" ON audit_log FOR SELECT
    USING (company_id = (SELECT company_id FROM users WHERE id = auth.uid()));


-- =================================================================
-- Functions and Triggers
-- =================================================================

-- Trigger function to create a public user and company on new auth.users signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_company_name text := new.raw_app_meta_data->>'company_name';
BEGIN
  -- Create a new company for the user
  INSERT INTO public.companies (name)
  VALUES (v_company_name)
  RETURNING id INTO v_company_id;

  -- Create a corresponding public user entry
  INSERT INTO public.users (id, company_id, role, email)
  VALUES (new.id, v_company_id, 'Owner', new.email);
  
  -- Update the user's app_metadata with the new company_id and role
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', v_company_id, 'role', 'Owner')
  WHERE id = new.id;
  
  RETURN new;
END;
$$;

-- Drop trigger if it exists
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Create the trigger
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- Trigger function to update inventory on new order line item
CREATE OR REPLACE FUNCTION public.update_inventory_on_sale()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE public.product_variants
  SET inventory_quantity = inventory_quantity - NEW.quantity
  WHERE id = NEW.variant_id;

  INSERT INTO public.inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes)
  VALUES (NEW.company_id, NEW.variant_id, 'sale', -NEW.quantity, (SELECT inventory_quantity FROM public.product_variants WHERE id = NEW.variant_id), NEW.order_id, 'Sale recorded');

  RETURN NEW;
END;
$$;

-- Drop trigger if it exists
DROP TRIGGER IF EXISTS on_new_order_line_item ON public.order_line_items;

-- Create the trigger
CREATE TRIGGER on_new_order_line_item
  AFTER INSERT ON public.order_line_items
  FOR EACH ROW
  EXECUTE FUNCTION public.update_inventory_on_sale();
  
-- Function to get a user's role
CREATE OR REPLACE FUNCTION get_user_role(p_user_id uuid)
RETURNS text AS $$
DECLARE
    v_role text;
BEGIN
    SELECT role INTO v_role FROM public.users WHERE id = p_user_id;
    RETURN v_role;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Function to record order from platform
CREATE OR REPLACE FUNCTION public.record_order_from_platform(p_company_id uuid, p_order_payload jsonb, p_platform text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_customer_id uuid;
    v_order_id uuid;
    v_variant_id uuid;
    line_item jsonb;
    v_sku text;
    v_product_name text;
    v_customer_email text;
BEGIN
    -- Extract customer email
    v_customer_email := p_order_payload->'customer'->>'email';
    
    -- Find or create customer
    SELECT id INTO v_customer_id FROM public.customers WHERE email = v_customer_email AND company_id = p_company_id;
    
    IF v_customer_id IS NULL THEN
        INSERT INTO public.customers (company_id, customer_name, email)
        VALUES (p_company_id, p_order_payload->'customer'->>'first_name' || ' ' || p_order_payload->'customer'->>'last_name', v_customer_email)
        RETURNING id INTO v_customer_id;
    END IF;
    
    -- Insert order
    INSERT INTO public.orders (company_id, order_number, external_order_id, customer_id, total_amount, source_platform, created_at)
    VALUES (
        p_company_id,
        p_order_payload->>'id',
        p_order_payload->>'id',
        v_customer_id,
        (p_order_payload->>'total_price')::numeric * 100,
        p_platform,
        (p_order_payload->>'created_at')::timestamptz
    )
    RETURNING id INTO v_order_id;

    -- Insert line items
    FOR line_item IN SELECT * FROM jsonb_array_elements(p_order_payload->'line_items')
    LOOP
        v_sku := line_item->>'sku';
        v_product_name := line_item->>'name';
        
        -- Find variant by SKU
        SELECT id INTO v_variant_id FROM public.product_variants WHERE sku = v_sku AND company_id = p_company_id;
        
        -- If variant not found, we still log the line item but without a variant_id link
        INSERT INTO public.order_line_items (order_id, company_id, variant_id, sku, product_name, quantity, price)
        VALUES (
            v_order_id,
            p_company_id,
            v_variant_id,
            v_sku,
            v_product_name,
            (line_item->>'quantity')::integer,
            (line_item->>'price')::numeric * 100
        );
    END LOOP;
END;
$$;


-- Function to get reorder suggestions
CREATE OR REPLACE FUNCTION get_reorder_suggestions(p_company_id uuid)
RETURNS TABLE(
    variant_id uuid,
    product_id uuid,
    sku text,
    product_name text,
    supplier_name text,
    supplier_id uuid,
    current_quantity integer,
    suggested_reorder_quantity integer,
    unit_cost integer
)
LANGUAGE plpgsql
AS $$
BEGIN
    -- This is a simplified stub. A real implementation would involve complex calculations
    -- based on sales velocity, lead times, safety stock, etc.
    RETURN QUERY
    SELECT
        pv.id as variant_id,
        pv.product_id,
        pv.sku,
        p.title as product_name,
        NULL::text as supplier_name,
        NULL::uuid as supplier_id,
        pv.inventory_quantity as current_quantity,
        10 as suggested_reorder_quantity, -- Stub value
        pv.cost as unit_cost
    FROM product_variants pv
    JOIN products p ON pv.product_id = p.id
    WHERE pv.company_id = p_company_id
    AND pv.inventory_quantity < 20 -- Simple reorder point
    LIMIT 10;
END;
$$;

-- Function to create purchase orders from suggestions
CREATE OR REPLACE FUNCTION create_purchase_orders_from_suggestions(
    p_company_id uuid,
    p_user_id uuid,
    p_suggestions jsonb,
    p_idempotency_key uuid DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
    suggestion jsonb;
    v_supplier_id uuid;
    v_po_id uuid;
    v_po_map jsonb := '{}'::jsonb;
    v_total_cost integer;
    created_po_count integer := 0;
BEGIN
    IF p_idempotency_key IS NOT NULL AND EXISTS (SELECT 1 FROM purchase_orders WHERE idempotency_key = p_idempotency_key) THEN
        RETURN 0;
    END IF;

    FOR suggestion IN SELECT * FROM jsonb_array_elements(p_suggestions)
    LOOP
        v_supplier_id := (suggestion->>'supplier_id')::uuid;
        
        IF v_supplier_id IS NULL THEN
            -- Handle items with no supplier - create a generic PO
            v_supplier_id := '00000000-0000-0000-0000-000000000000'::uuid; 
        END IF;

        IF NOT v_po_map ? v_supplier_id::text THEN
            INSERT INTO purchase_orders (company_id, supplier_id, po_number, total_cost, idempotency_key)
            VALUES (p_company_id, CASE WHEN v_supplier_id = '00000000-0000-0000-0000-000000000000'::uuid THEN NULL ELSE v_supplier_id END, 'PO-' || (nextval('purchase_orders_po_number_seq')::text), 0, p_idempotency_key)
            RETURNING id INTO v_po_id;
            
            v_po_map := jsonb_set(v_po_map, ARRAY[v_supplier_id::text], to_jsonb(v_po_id));
            created_po_count := created_po_count + 1;
        ELSE
            v_po_id := (v_po_map->>v_supplier_id::text)::uuid;
        END IF;

        INSERT INTO purchase_order_line_items (purchase_order_id, variant_id, quantity, cost)
        VALUES (
            v_po_id,
            (suggestion->>'variant_id')::uuid,
            (suggestion->>'suggested_reorder_quantity')::integer,
            (suggestion->>'unit_cost')::integer
        );
    END LOOP;

    -- Update total costs for all created POs
    FOR v_po_id IN SELECT (jsonb_each_text(v_po_map)).value::uuid
    LOOP
        SELECT SUM(li.quantity * li.cost)
        INTO v_total_cost
        FROM purchase_order_line_items li
        WHERE li.purchase_order_id = v_po_id;

        UPDATE purchase_orders SET total_cost = v_total_cost WHERE id = v_po_id;
    END LOOP;

    RETURN created_po_count;
END;
$$;

-- Sequence for PO numbers
CREATE SEQUENCE IF NOT EXISTS purchase_orders_po_number_seq;

-- Grant usage on the sequence to authenticated users
GRANT USAGE, SELECT ON SEQUENCE purchase_orders_po_number_seq TO authenticated;


-- Final command to ensure script completes successfully
SELECT 'Database schema setup complete.';
