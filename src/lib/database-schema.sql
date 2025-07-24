--
-- Enums
--
CREATE TYPE company_role AS ENUM ('Owner', 'Admin', 'Member');
CREATE TYPE integration_platform AS ENUM ('shopify', 'woocommerce', 'amazon_fba');
CREATE TYPE message_role AS ENUM ('user', 'assistant', 'tool');
CREATE TYPE feedback_type AS ENUM ('helpful', 'unhelpful');

--
-- Companies
--
CREATE TABLE companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE
);

--
-- Users in companies
--
CREATE TABLE company_users (
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    role company_role NOT NULL DEFAULT 'Member',
    PRIMARY KEY (user_id, company_id)
);

--
-- Row Level Security for companies
--
ALTER TABLE companies ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own company"
ON companies
FOR SELECT
USING (auth.uid() IN (SELECT user_id FROM company_users WHERE company_id = id));

--
-- Row Level Security for company_users
--
ALTER TABLE company_users ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own membership"
ON company_users
FOR SELECT
USING (auth.uid() = user_id);

--
-- Company Settings
--
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
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ
);

ALTER TABLE company_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can access settings for their own company"
ON company_settings
FOR ALL
USING (auth.uid() IN (SELECT user_id FROM company_users WHERE company_id = company_settings.company_id));


--
-- Trigger to create a company for a new user
--
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  new_company_id UUID;
  company_name TEXT;
BEGIN
  -- Extract company name from metadata, default to "My Company"
  company_name := NEW.raw_app_meta_data->>'company_name';
  IF company_name IS NULL OR company_name = '' THEN
    company_name := 'My Company';
  END IF;

  -- Create a new company for the user
  INSERT INTO public.companies (name, owner_id)
  VALUES (company_name, NEW.id)
  RETURNING id INTO new_company_id;

  -- Add the user to the company_users table as Owner
  INSERT INTO public.company_users (user_id, company_id, role)
  VALUES (NEW.id, new_company_id, 'Owner');
  
  -- Create default settings for the new company
  INSERT INTO public.company_settings (company_id)
  VALUES (new_company_id);

  -- Update the user's app_metadata with the company_id
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id)
  WHERE id = NEW.id;
  
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION handle_new_user();


--
-- Integrations Table
--
CREATE TABLE integrations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    platform integration_platform NOT NULL,
    shop_domain TEXT,
    shop_name TEXT,
    is_active BOOLEAN DEFAULT false,
    last_sync_at TIMESTAMPTZ,
    sync_status TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, platform)
);

ALTER TABLE integrations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can access integrations for their own company"
ON integrations
FOR ALL
USING (auth.uid() IN (SELECT user_id FROM company_users WHERE company_id = integrations.company_id));

--
-- Products and Variants
--
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
    deleted_at TIMESTAMPTZ
);
CREATE UNIQUE INDEX idx_unique_external_product ON products (company_id, external_product_id) WHERE external_product_id IS NOT NULL;

CREATE TABLE product_variants (
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
    reorder_point INT,
    reorder_quantity INT,
    supplier_id UUID REFERENCES suppliers(id) ON DELETE SET NULL,
    external_variant_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ,
    version INT NOT NULL DEFAULT 1
);
CREATE UNIQUE INDEX idx_unique_external_variant ON product_variants (company_id, external_variant_id) WHERE external_variant_id IS NOT NULL;
CREATE UNIQUE INDEX idx_unique_sku ON product_variants (company_id, sku);

ALTER TABLE products ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can access products for their own company"
ON products
FOR ALL
USING (auth.uid() IN (SELECT user_id FROM company_users WHERE company_id = products.company_id));

ALTER TABLE product_variants ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can access variants for their own company"
ON product_variants
FOR ALL
USING (auth.uid() IN (SELECT user_id FROM company_users WHERE company_id = product_variants.company_id));

--
-- Customers
--
CREATE TABLE customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    name TEXT,
    email TEXT,
    phone TEXT,
    external_customer_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ
);
CREATE UNIQUE INDEX idx_unique_external_customer ON customers (company_id, external_customer_id) WHERE external_customer_id IS NOT NULL;
CREATE INDEX idx_customer_email ON customers (company_id, email);

ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can access customers for their own company"
ON customers
FOR ALL
USING (auth.uid() IN (SELECT user_id FROM company_users WHERE company_id = customers.company_id));


--
-- Orders
--
CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    order_number TEXT NOT NULL,
    external_order_id TEXT,
    customer_id UUID REFERENCES customers(id) ON DELETE SET NULL,
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
    updated_at TIMESTAMPTZ
);
CREATE UNIQUE INDEX idx_unique_external_order ON orders (company_id, external_order_id) WHERE external_order_id IS NOT NULL;

CREATE TABLE order_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    variant_id UUID REFERENCES product_variants(id) ON DELETE SET NULL,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    product_name TEXT,
    variant_title TEXT,
    sku TEXT,
    quantity INT NOT NULL,
    price INT NOT NULL, -- in cents
    total_discount INT,
    tax_amount INT,
    cost_at_time INT,
    external_line_item_id TEXT
);

ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can access orders for their own company"
ON orders
FOR ALL
USING (auth.uid() IN (SELECT user_id FROM company_users WHERE company_id = orders.company_id));

ALTER TABLE order_line_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can access order line items for their own company"
ON order_line_items
FOR ALL
USING (auth.uid() IN (SELECT user_id FROM company_users WHERE company_id = order_line_items.company_id));


--
-- Suppliers
--
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
ALTER TABLE suppliers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can access suppliers for their own company"
ON suppliers
FOR ALL
USING (auth.uid() IN (SELECT user_id FROM company_users WHERE company_id = suppliers.company_id));

--
-- Purchase Orders
--
CREATE TABLE purchase_orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    supplier_id UUID REFERENCES suppliers(id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'Draft',
    po_number TEXT NOT NULL,
    total_cost INT NOT NULL,
    expected_arrival_date DATE,
    idempotency_key UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    notes TEXT
);

CREATE TABLE purchase_order_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    purchase_order_id UUID NOT NULL REFERENCES purchase_orders(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    quantity INT NOT NULL,
    cost INT NOT NULL -- in cents
);

ALTER TABLE purchase_orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can access purchase orders for their own company"
ON purchase_orders
FOR ALL
USING (auth.uid() IN (SELECT user_id FROM company_users WHERE company_id = purchase_orders.company_id));

ALTER TABLE purchase_order_line_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can access PO line items for their own company"
ON purchase_order_line_items
FOR ALL
USING (auth.uid() IN (SELECT user_id FROM company_users WHERE company_id = purchase_order_line_items.company_id));


--
-- Inventory Ledger
--
CREATE TABLE inventory_ledger (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
    change_type TEXT NOT NULL,
    quantity_change INT NOT NULL,
    new_quantity INT NOT NULL,
    related_id UUID,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE inventory_ledger ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can access ledger entries for their own company"
ON inventory_ledger
FOR ALL
USING (auth.uid() IN (SELECT user_id FROM company_users WHERE company_id = inventory_ledger.company_id));


-- Trigger to update inventory on sale
CREATE OR REPLACE FUNCTION handle_inventory_change_on_sale()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE product_variants
    SET inventory_quantity = inventory_quantity - NEW.quantity
    WHERE id = NEW.variant_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER on_order_line_item_created
AFTER INSERT ON order_line_items
FOR EACH ROW
EXECUTE FUNCTION handle_inventory_change_on_sale();

--
-- Audit Log
--
CREATE TABLE audit_log (
    id BIGSERIAL PRIMARY KEY,
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    details JSONB,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- RLS for audit log
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins can access audit logs for their own company"
ON audit_log
FOR ALL
USING (
    company_id IN (
        SELECT company_id FROM company_users
        WHERE user_id = auth.uid() AND role IN ('Admin', 'Owner')
    )
);

-- Trigger to audit inventory changes
CREATE OR REPLACE FUNCTION log_inventory_changes()
RETURNS TRIGGER AS $$
DECLARE
  audit_details JSONB;
BEGIN
  audit_details := jsonb_build_object(
    'variant_id', NEW.id,
    'sku', NEW.sku,
    'old_quantity', OLD.inventory_quantity,
    'new_quantity', NEW.inventory_quantity,
    'change', NEW.inventory_quantity - OLD.inventory_quantity
  );

  INSERT INTO public.audit_log(company_id, user_id, action, details)
  VALUES (NEW.company_id, auth.uid(), 'inventory_updated', audit_details);
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER inventory_update_trigger
AFTER UPDATE OF inventory_quantity ON product_variants
FOR EACH ROW
WHEN (OLD.inventory_quantity IS DISTINCT FROM NEW.inventory_quantity)
EXECUTE FUNCTION log_inventory_changes();


--
-- AI-related tables
--
CREATE TABLE conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    last_accessed_at TIMESTAMPTZ DEFAULT now(),
    is_starred BOOLEAN DEFAULT false
);

CREATE TABLE messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    role message_role NOT NULL,
    content TEXT,
    component TEXT,
    component_props JSONB,
    visualization JSONB,
    confidence NUMERIC,
    assumptions TEXT[],
    is_error BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can access their own conversations"
ON conversations
FOR ALL
USING (auth.uid() = user_id);

ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can access messages in their own conversations"
ON messages
FOR ALL
USING (auth.uid() = (SELECT user_id FROM conversations WHERE id = conversation_id));

--
-- Webhook Events
--
CREATE TABLE webhook_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id UUID NOT NULL REFERENCES integrations(id) ON DELETE CASCADE,
    webhook_id TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(integration_id, webhook_id)
);
ALTER TABLE webhook_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins can access webhooks for their company"
ON webhook_events
FOR ALL
USING (
    EXISTS (
        SELECT 1 FROM integrations i
        JOIN company_users cu ON i.company_id = cu.company_id
        WHERE i.id = webhook_events.integration_id
        AND cu.user_id = auth.uid()
        AND cu.role IN ('Admin', 'Owner')
    )
);

--
-- Channel Fees
--
CREATE TABLE channel_fees (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    channel_name TEXT NOT NULL,
    percentage_fee NUMERIC,
    fixed_fee INT, -- in cents
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, channel_name)
);
ALTER TABLE channel_fees ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can access channel fees for their company"
ON channel_fees
FOR ALL
USING (
    company_id IN (
        SELECT company_id FROM company_users
        WHERE user_id = auth.uid()
    )
);

--
-- Export Jobs
--
CREATE TABLE export_jobs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    requested_by_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'pending',
    download_url TEXT,
    expires_at TIMESTAMPTZ,
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ
);
ALTER TABLE export_jobs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can access their own export jobs"
ON export_jobs
FOR ALL
USING (auth.uid() = requested_by_user_id);


--
-- Database Functions
--

-- Function to lock a user account
CREATE OR REPLACE FUNCTION lock_user_account(p_user_id UUID, p_lockout_duration INTERVAL)
RETURNS VOID AS $$
BEGIN
    UPDATE auth.users
    SET banned_until = now() + p_lockout_duration
    WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


--
-- VIEWS for simplified data access
--
CREATE OR REPLACE VIEW public.customers_view AS
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

CREATE OR REPLACE VIEW public.orders_view AS
SELECT * FROM orders;

-- Materialized view for faster variant lookups
CREATE MATERIALIZED VIEW public.product_variants_with_details_mat AS
SELECT
    pv.*,
    p.title as product_title,
    p.status as product_status,
    p.image_url,
    p.product_type
FROM product_variants pv
JOIN products p ON pv.product_id = p.id
WHERE pv.deleted_at IS NULL AND p.deleted_at IS NULL;

-- Function to refresh all materialized views for a company.
CREATE OR REPLACE FUNCTION refresh_all_matviews(p_company_id UUID)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY product_variants_with_details_mat;
END;
$$;
