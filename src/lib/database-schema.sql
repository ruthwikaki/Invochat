-- ================================================================================= --
--                             ENUMERATED TYPES
-- ================================================================================= --

-- Using DO...END blocks to create types only if they don't exist, making the script idempotent.
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


-- ================================================================================= --
--                                   TABLES
-- ================================================================================= --

-- Companies Table: Stores company-specific information.
CREATE TABLE IF NOT EXISTS companies (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    name TEXT NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    owner_id uuid REFERENCES auth.users(id) NOT NULL
);
ALTER TABLE companies ENABLE ROW LEVEL SECURITY;

-- Users Table: Maps Supabase auth users to companies and roles.
CREATE TABLE IF NOT EXISTS company_users (
    company_id uuid REFERENCES companies(id) ON DELETE CASCADE NOT NULL,
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    role company_role NOT NULL DEFAULT 'Member',
    PRIMARY KEY (company_id, user_id)
);
ALTER TABLE company_users ENABLE ROW LEVEL SECURITY;


-- Products Table: Core product information.
CREATE TABLE IF NOT EXISTS products (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid REFERENCES companies(id) ON DELETE CASCADE NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    handle TEXT,
    product_type TEXT,
    tags TEXT[],
    status TEXT,
    image_url TEXT,
    external_product_id TEXT,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    deleted_at timestamptz
);
CREATE INDEX IF NOT EXISTS idx_products_company_id ON products(company_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_products_company_id_external_id ON products(company_id, external_product_id) WHERE external_product_id IS NOT NULL;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;

-- Product Variants Table: Specific versions of a product (e.g., size, color).
CREATE TABLE IF NOT EXISTS product_variants (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    product_id uuid REFERENCES products(id) ON DELETE CASCADE NOT NULL,
    company_id uuid REFERENCES companies(id) ON DELETE CASCADE NOT NULL,
    sku TEXT NOT NULL,
    title TEXT,
    option1_name TEXT,
    option1_value TEXT,
    option2_name TEXT,
    option2_value TEXT,
    option3_name TEXT,
    option3_value TEXT,
    barcode TEXT,
    price INT,
    compare_at_price INT,
    cost INT,
    inventory_quantity INT NOT NULL DEFAULT 0,
    location TEXT,
    external_variant_id TEXT,
    supplier_id uuid, -- Foreign key added later
    reorder_point INT,
    reorder_quantity INT,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    deleted_at timestamptz,
    version INT NOT NULL DEFAULT 1
);
CREATE INDEX IF NOT EXISTS idx_variants_company_id ON product_variants(company_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_variants_company_id_sku ON product_variants(company_id, sku);
ALTER TABLE product_variants ENABLE ROW LEVEL SECURITY;

-- Suppliers Table
CREATE TABLE IF NOT EXISTS suppliers (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid REFERENCES companies(id) ON DELETE CASCADE NOT NULL,
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    default_lead_time_days INT,
    notes TEXT,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);
ALTER TABLE suppliers ENABLE ROW LEVEL SECURITY;

-- Add foreign key from product_variants to suppliers
ALTER TABLE product_variants
ADD CONSTRAINT fk_supplier
FOREIGN KEY (supplier_id)
REFERENCES suppliers(id)
ON DELETE SET NULL;

-- Customers Table
CREATE TABLE IF NOT EXISTS customers (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid REFERENCES companies(id) ON DELETE CASCADE NOT NULL,
    name TEXT,
    email TEXT,
    phone TEXT,
    external_customer_id TEXT,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    deleted_at timestamptz
);
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;

-- Orders Table
CREATE TABLE IF NOT EXISTS orders (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid REFERENCES companies(id) ON DELETE CASCADE NOT NULL,
    order_number TEXT NOT NULL,
    external_order_id TEXT,
    customer_id uuid REFERENCES customers(id) ON DELETE SET NULL,
    financial_status TEXT,
    fulfillment_status TEXT,
    currency TEXT,
    subtotal INT NOT NULL DEFAULT 0,
    total_tax INT DEFAULT 0,
    total_shipping INT DEFAULT 0,
    total_discounts INT DEFAULT 0,
    total_amount INT NOT NULL,
    source_platform TEXT,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz
);
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

-- Order Line Items Table
CREATE TABLE IF NOT EXISTS order_line_items (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    order_id uuid REFERENCES orders(id) ON DELETE CASCADE NOT NULL,
    variant_id uuid REFERENCES product_variants(id) ON DELETE SET NULL,
    company_id uuid REFERENCES companies(id) ON DELETE CASCADE NOT NULL,
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

-- Purchase Orders Table
CREATE TABLE IF NOT EXISTS purchase_orders (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid REFERENCES companies(id) ON DELETE CASCADE NOT NULL,
    supplier_id uuid REFERENCES suppliers(id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'Draft',
    po_number TEXT NOT NULL,
    total_cost INT NOT NULL,
    expected_arrival_date DATE,
    notes TEXT,
    idempotency_key uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);
ALTER TABLE purchase_orders ENABLE ROW LEVEL SECURITY;

-- Purchase Order Line Items Table
CREATE TABLE IF NOT EXISTS purchase_order_line_items (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    purchase_order_id uuid REFERENCES purchase_orders(id) ON DELETE CASCADE NOT NULL,
    variant_id uuid REFERENCES product_variants(id) ON DELETE CASCADE NOT NULL,
    company_id uuid REFERENCES companies(id) ON DELETE CASCADE NOT NULL,
    quantity INT NOT NULL,
    cost INT NOT NULL
);
ALTER TABLE purchase_order_line_items ENABLE ROW LEVEL SECURITY;


-- Inventory Ledger Table
CREATE TABLE IF NOT EXISTS inventory_ledger (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid REFERENCES companies(id) ON DELETE CASCADE NOT NULL,
    variant_id uuid REFERENCES product_variants(id) ON DELETE CASCADE NOT NULL,
    change_type TEXT NOT NULL,
    quantity_change INT NOT NULL,
    new_quantity INT NOT NULL,
    related_id uuid,
    notes TEXT,
    created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE inventory_ledger ENABLE ROW LEVEL SECURITY;


-- Integrations Table
CREATE TABLE IF NOT EXISTS integrations (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid REFERENCES companies(id) ON DELETE CASCADE NOT NULL,
    platform integration_platform NOT NULL,
    shop_domain TEXT,
    shop_name TEXT,
    is_active BOOLEAN DEFAULT false,
    last_sync_at timestamptz,
    sync_status TEXT,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, platform)
);
ALTER TABLE integrations ENABLE ROW LEVEL SECURITY;

-- Webhook Events Table
CREATE TABLE IF NOT EXISTS webhook_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id uuid NOT NULL REFERENCES integrations(id) ON DELETE CASCADE,
    webhook_id TEXT NOT NULL,
    created_at timestamptz DEFAULT now(),
    UNIQUE(integration_id, webhook_id)
);
ALTER TABLE webhook_events ENABLE ROW LEVEL SECURITY;

-- Company Settings Table
CREATE TABLE IF NOT EXISTS company_settings (
    company_id uuid PRIMARY KEY REFERENCES companies(id) ON DELETE CASCADE,
    dead_stock_days INT NOT NULL DEFAULT 90,
    fast_moving_days INT NOT NULL DEFAULT 30,
    overstock_multiplier INT NOT NULL DEFAULT 3,
    high_value_threshold INT NOT NULL DEFAULT 100000, -- in cents
    predictive_stock_days INT NOT NULL DEFAULT 7,
    currency TEXT DEFAULT 'USD',
    tax_rate NUMERIC DEFAULT 0,
    timezone TEXT DEFAULT 'UTC',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);
ALTER TABLE company_settings ENABLE ROW LEVEL SECURITY;

-- Channel Fees Table (for profit calculations)
CREATE TABLE IF NOT EXISTS channel_fees (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid REFERENCES companies(id) ON DELETE CASCADE NOT NULL,
    channel_name TEXT NOT NULL,
    percentage_fee NUMERIC,
    fixed_fee INT, -- in cents
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, channel_name)
);
ALTER TABLE channel_fees ENABLE ROW LEVEL SECURITY;

-- AI Conversation History Tables
CREATE TABLE IF NOT EXISTS conversations (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    company_id uuid REFERENCES companies(id) ON DELETE CASCADE NOT NULL,
    title TEXT NOT NULL,
    created_at timestamptz DEFAULT now(),
    last_accessed_at timestamptz DEFAULT now(),
    is_starred BOOLEAN DEFAULT false
);
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS messages (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    conversation_id uuid REFERENCES conversations(id) ON DELETE CASCADE NOT NULL,
    company_id uuid REFERENCES companies(id) ON DELETE CASCADE NOT NULL,
    role message_role NOT NULL,
    content TEXT,
    component TEXT,
    componentProps JSONB,
    visualization JSONB,
    confidence NUMERIC,
    assumptions TEXT[],
    isError BOOLEAN DEFAULT false,
    created_at timestamptz DEFAULT now()
);
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

-- Audit Log Table
CREATE TABLE IF NOT EXISTS audit_log (
    id BIGSERIAL PRIMARY KEY,
    company_id uuid REFERENCES companies(id) ON DELETE CASCADE,
    user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    details JSONB,
    created_at timestamptz DEFAULT now()
);
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;

-- Export Jobs Table
CREATE TABLE IF NOT EXISTS export_jobs (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    requested_by_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'pending', -- pending, processing, completed, failed
    download_url TEXT,
    expires_at timestamptz,
    error_message TEXT,
    created_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz
);
ALTER TABLE export_jobs ENABLE ROW LEVEL SECURITY;

-- Imports Table
CREATE TABLE IF NOT EXISTS imports (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    import_type TEXT NOT NULL,
    file_name TEXT NOT NULL,
    total_rows INT,
    processed_rows INT,
    failed_rows INT,
    status TEXT NOT NULL DEFAULT 'pending', -- pending, processing, completed, completed_with_errors, failed
    errors JSONB,
    summary JSONB,
    created_at timestamptz DEFAULT now(),
    completed_at timestamptz
);
ALTER TABLE imports ENABLE ROW LEVEL SECURITY;


-- ================================================================================= --
--                             FUNCTIONS AND TRIGGERS
-- ================================================================================= --

-- Function to get the company_id for the current user
CREATE OR REPLACE FUNCTION get_company_id_for_user(p_user_id uuid)
RETURNS uuid AS $$
DECLARE
    v_company_id uuid;
BEGIN
    SELECT company_id INTO v_company_id
    FROM company_users
    WHERE user_id = p_user_id;
    RETURN v_company_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Function to create a company and link it to the owner after signup
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    v_company_id uuid;
BEGIN
    -- Create a new company for the user
    INSERT INTO public.companies (name, owner_id)
    VALUES (new.raw_app_meta_data->>'company_name', new.id)
    RETURNING id INTO v_company_id;

    -- Link the user to the new company with the 'Owner' role
    INSERT INTO public.company_users (user_id, company_id, role)
    VALUES (new.id, v_company_id, 'Owner');
    
    -- Update the user's app_metadata with the new company_id
    UPDATE auth.users
    SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', v_company_id)
    WHERE id = new.id;
    
    RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to call the function after a new user is created
CREATE OR REPLACE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION handle_new_user();


-- Function to handle inventory changes from sales
CREATE OR REPLACE FUNCTION handle_inventory_change_on_sale()
RETURNS TRIGGER AS $$
DECLARE
    v_new_quantity int;
BEGIN
    -- Check for sufficient inventory before decrementing
    SELECT inventory_quantity INTO v_new_quantity FROM public.product_variants WHERE id = NEW.variant_id;
    
    IF v_new_quantity < NEW.quantity THEN
        RAISE EXCEPTION 'Insufficient stock for SKU %. Requested: %, Available: %', NEW.sku, NEW.quantity, v_new_quantity;
    END IF;

    -- Decrement inventory
    UPDATE public.product_variants
    SET inventory_quantity = inventory_quantity - NEW.quantity
    WHERE id = NEW.variant_id;
    
    -- Log the change
    INSERT INTO public.inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id)
    SELECT NEW.company_id, NEW.variant_id, 'sale', -NEW.quantity, pv.inventory_quantity, NEW.order_id
    FROM public.product_variants pv
    WHERE pv.id = NEW.variant_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for inventory changes on sales
CREATE OR REPLACE TRIGGER on_order_line_item_insert
    AFTER INSERT ON public.order_line_items
    FOR EACH ROW
    EXECUTE FUNCTION handle_inventory_change_on_sale();

-- Function to handle locking user accounts
CREATE OR REPLACE FUNCTION lock_user_account(p_user_id uuid, p_lockout_duration text)
RETURNS void AS $$
BEGIN
    UPDATE auth.users
    SET banned_until = now() + p_lockout_duration::interval
    WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ================================================================================= --
--                             ROW-LEVEL SECURITY (RLS)
-- ================================================================================= --

-- Helper function to get the current user's company ID
CREATE OR REPLACE FUNCTION get_current_company_id()
RETURNS uuid AS $$
DECLARE
    company_id uuid;
BEGIN
    SELECT raw_app_meta_data->>'company_id' INTO company_id
    FROM auth.users
    WHERE id = auth.uid();
    RETURN company_id;
END;
$$ LANGUAGE plpgsql;

-- RLS Policies
CREATE POLICY "Allow full access to own company data" ON companies
    FOR ALL USING (id = get_current_company_id());

CREATE POLICY "Allow access to users in the same company" ON company_users
    FOR ALL USING (company_id = get_current_company_id());

CREATE POLICY "Allow full access to own company data" ON products
    FOR ALL USING (company_id = get_current_company_id());

CREATE POLICY "Allow full access to own company data" ON product_variants
    FOR ALL USING (company_id = get_current_company_id());

CREATE POLICY "Allow full access to own company data" ON suppliers
    FOR ALL USING (company_id = get_current_company_id());
    
CREATE POLICY "Allow full access to own company data" ON customers
    FOR ALL USING (company_id = get_current_company_id());

CREATE POLICY "Allow full access to own company data" ON orders
    FOR ALL USING (company_id = get_current_company_id());

CREATE POLICY "Allow full access to own company data" ON order_line_items
    FOR ALL USING (company_id = get_current_company_id());

CREATE POLICY "Allow full access to own company data" ON purchase_orders
    FOR ALL USING (company_id = get_current_company_id());
    
CREATE POLICY "Allow full access to own company data" ON purchase_order_line_items
    FOR ALL USING (company_id = get_current_company_id());

CREATE POLICY "Allow full access to own company data" ON inventory_ledger
    FOR ALL USING (company_id = get_current_company_id());

CREATE POLICY "Allow full access to own company data" ON integrations
    FOR ALL USING (company_id = get_current_company_id());

CREATE POLICY "Allow full access to own company data" ON webhook_events
    FOR ALL USING (integration_id IN (SELECT id FROM integrations WHERE company_id = get_current_company_id()));

CREATE POLICY "Allow full access to own company data" ON company_settings
    FOR ALL USING (company_id = get_current_company_id());
    
CREATE POLICY "Allow full access to own company data" ON channel_fees
    FOR ALL USING (company_id = get_current_company_id());

CREATE POLICY "Allow full access to own conversations" ON conversations
    FOR ALL USING (user_id = auth.uid());

CREATE POLICY "Allow full access to own messages" ON messages
    FOR ALL USING (conversation_id IN (SELECT id FROM conversations WHERE user_id = auth.uid()));

CREATE POLICY "Allow full access to own company data" ON audit_log
    FOR ALL USING (company_id = get_current_company_id());
    
CREATE POLICY "Allow full access to own export jobs" ON export_jobs
    FOR ALL USING (company_id = get_current_company_id());

CREATE POLICY "Allow full access to own imports" ON imports
    FOR ALL USING (company_id = get_current_company_id());
