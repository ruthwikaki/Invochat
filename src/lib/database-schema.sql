
-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Enable cryptographic functions
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Create custom types for roles and platforms
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


-- #################################################################
--    TABLES
-- #################################################################

-- Stores company information
CREATE TABLE IF NOT EXISTS companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    owner_id UUID NOT NULL REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Junction table for users and companies
CREATE TABLE IF NOT EXISTS company_users (
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role company_role NOT NULL DEFAULT 'Member',
    PRIMARY KEY (company_id, user_id)
);

-- Stores company-specific settings for business logic
CREATE TABLE IF NOT EXISTS company_settings (
    company_id UUID PRIMARY KEY REFERENCES companies(id) ON DELETE CASCADE,
    dead_stock_days INT NOT NULL DEFAULT 90,
    fast_moving_days INT NOT NULL DEFAULT 30,
    overstock_multiplier NUMERIC NOT NULL DEFAULT 3,
    high_value_threshold INT NOT NULL DEFAULT 100000, -- in cents
    predictive_stock_days INT NOT NULL DEFAULT 7,
    currency TEXT DEFAULT 'USD',
    timezone TEXT DEFAULT 'UTC',
    tax_rate NUMERIC DEFAULT 0.0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ
);


-- Stores information about connected integrations
CREATE TABLE IF NOT EXISTS integrations (
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
    UNIQUE (company_id, platform)
);

-- Stores products, which act as parents for variants
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
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE (company_id, external_product_id)
);

-- Stores suppliers/vendors
CREATE TABLE IF NOT EXISTS suppliers (
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


-- Stores individual product variants (SKUs)
CREATE TABLE IF NOT EXISTS product_variants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    supplier_id UUID REFERENCES suppliers(id) ON DELETE SET NULL,
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
    reorder_point INT,
    reorder_quantity INT,
    location TEXT,
    external_variant_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    CONSTRAINT inventory_quantity_not_negative CHECK (inventory_quantity >= 0),
    UNIQUE (company_id, sku),
    UNIQUE (company_id, external_variant_id)
);


-- Stores customer information
CREATE TABLE IF NOT EXISTS customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    name TEXT,
    email TEXT,
    phone TEXT,
    external_customer_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ,
    UNIQUE (company_id, email),
    UNIQUE (company_id, external_customer_id)
);


-- Stores sales orders
CREATE TABLE IF NOT EXISTS orders (
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
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, external_order_id)
);

-- Stores line items for each sales order
CREATE TABLE IF NOT EXISTS order_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    variant_id UUID REFERENCES product_variants(id) ON DELETE SET NULL,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    product_name TEXT,
    variant_title TEXT,
    sku TEXT,
    quantity INT NOT NULL,
    price INT NOT NULL, -- in cents
    total_discount INT, -- in cents
    tax_amount INT, -- in cents
    cost_at_time INT, -- in cents
    external_line_item_id TEXT
);

-- Tracks every change to inventory quantity for auditing
CREATE TABLE IF NOT EXISTS inventory_ledger (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
    change_type TEXT NOT NULL, -- e.g., 'sale', 'purchase_order_received', 'manual_adjustment'
    quantity_change INT NOT NULL,
    new_quantity INT NOT NULL,
    related_id UUID, -- e.g., order_id, purchase_order_id
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Stores purchase orders
CREATE TABLE IF NOT EXISTS purchase_orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    supplier_id UUID REFERENCES suppliers(id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'Draft',
    po_number TEXT NOT NULL,
    total_cost INT NOT NULL, -- in cents
    expected_arrival_date DATE,
    idempotency_key UUID UNIQUE,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE (company_id, po_number)
);

-- Stores line items for each purchase order
CREATE TABLE IF NOT EXISTS purchase_order_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    purchase_order_id UUID NOT NULL REFERENCES purchase_orders(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    quantity INT NOT NULL,
    cost INT NOT NULL -- in cents
);

-- Stores chat conversations
CREATE TABLE IF NOT EXISTS conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    last_accessed_at TIMESTAMPTZ DEFAULT now(),
    is_starred BOOLEAN DEFAULT false
);

-- Stores individual chat messages
CREATE TABLE IF NOT EXISTS messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    role message_role NOT NULL,
    content TEXT NOT NULL,
    component TEXT,
    component_props JSONB,
    visualization JSONB,
    confidence NUMERIC,
    assumptions TEXT[],
    created_at TIMESTAMPTZ DEFAULT now(),
    isError BOOLEAN DEFAULT false
);

-- Stores audit logs for important events
CREATE TABLE IF NOT EXISTS audit_log (
  id BIGSERIAL PRIMARY KEY,
  company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  action TEXT NOT NULL,
  details JSONB,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Stores user feedback on AI responses
CREATE TABLE IF NOT EXISTS feedback (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    subject_id TEXT NOT NULL, -- can be message_id, alert_id, etc.
    subject_type TEXT NOT NULL, -- e.g., 'message', 'alert'
    feedback feedback_type NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);


-- Stores fees for sales channels to improve profit calculations
CREATE TABLE IF NOT EXISTS channel_fees (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    channel_name TEXT NOT NULL,
    percentage_fee NUMERIC,
    fixed_fee INT, -- in cents
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE (company_id, channel_name)
);

-- Stores jobs for asynchronous data exports
CREATE TABLE IF NOT EXISTS export_jobs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    requested_by_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'pending', -- pending, processing, completed, failed
    download_url TEXT,
    expires_at TIMESTAMPTZ,
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ
);

-- Stores import job history
CREATE TABLE IF NOT EXISTS imports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    created_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    import_type TEXT NOT NULL,
    file_name TEXT NOT NULL,
    total_rows INT,
    processed_rows INT,
    failed_rows INT,
    status TEXT NOT NULL DEFAULT 'pending',
    errors JSONB,
    summary JSONB,
    created_at TIMESTAMPTZ DEFAULT now(),
    completed_at TIMESTAMPTZ
);

-- Stores webhook events to prevent replay attacks
CREATE TABLE IF NOT EXISTS webhook_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id UUID NOT NULL REFERENCES integrations(id) ON DELETE CASCADE,
    webhook_id TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE (integration_id, webhook_id)
);


-- #################################################################
--    TRIGGERS & FUNCTIONS
-- #################################################################

-- Trigger function to automatically create a company for a new user
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  v_company_id UUID;
  v_company_name TEXT;
BEGIN
  -- Extract company name from metadata, default to a standard name
  v_company_name := NEW.raw_app_meta_data->>'company_name';
  IF v_company_name IS NULL OR v_company_name = '' THEN
    v_company_name := NEW.email || '''s Company';
  END IF;

  -- Create a new company for the user
  INSERT INTO public.companies (name, owner_id)
  VALUES (v_company_name, NEW.id)
  RETURNING id INTO v_company_id;

  -- Link the user to the new company as 'Owner'
  INSERT INTO public.company_users (company_id, user_id, role)
  VALUES (v_company_id, NEW.id, 'Owner');

  -- Update the user's app_metadata with the new company_id
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', v_company_id)
  WHERE id = NEW.id;

  -- Create default settings for the new company
  INSERT INTO public.company_settings(company_id)
  VALUES(v_company_id);

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop existing trigger if it exists to avoid conflicts
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Create the trigger on the users table
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();


-- Function to get company_id for a user
CREATE OR REPLACE FUNCTION get_company_id_for_user(p_user_id UUID)
RETURNS UUID AS $$
DECLARE
  v_company_id UUID;
BEGIN
  SELECT company_id INTO v_company_id
  FROM public.company_users
  WHERE user_id = p_user_id;
  RETURN v_company_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Function to check inventory quantity
CREATE OR REPLACE FUNCTION check_inventory_not_negative()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.inventory_quantity < 0 THEN
        RAISE EXCEPTION 'Inventory quantity for SKU % cannot be negative.', NEW.sku;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop trigger if it exists
DROP TRIGGER IF EXISTS before_update_inventory_quantity ON product_variants;

-- Create trigger to enforce inventory constraint
CREATE TRIGGER before_update_inventory_quantity
BEFORE UPDATE OF inventory_quantity ON product_variants
FOR EACH ROW
EXECUTE FUNCTION check_inventory_not_negative();


-- Function to log inventory changes
CREATE OR REPLACE FUNCTION log_inventory_change()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, notes)
    VALUES (NEW.company_id, NEW.id, 'manual_adjustment', NEW.inventory_quantity - OLD.inventory_quantity, NEW.inventory_quantity, 'Manual adjustment in dashboard');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop trigger if it exists
DROP TRIGGER IF EXISTS on_inventory_quantity_change ON product_variants;

-- Trigger for manual inventory changes
CREATE TRIGGER on_inventory_quantity_change
AFTER UPDATE OF inventory_quantity ON product_variants
FOR EACH ROW
WHEN (OLD.inventory_quantity IS DISTINCT FROM NEW.inventory_quantity)
EXECUTE FUNCTION log_inventory_change();


-- Function to update inventory from a sale
CREATE OR REPLACE FUNCTION update_inventory_for_sale(
  p_company_id UUID,
  p_variant_id UUID,
  p_quantity_sold INT,
  p_order_id UUID
)
RETURNS void AS $$
DECLARE
    v_current_quantity INT;
BEGIN
    -- Get current quantity
    SELECT inventory_quantity INTO v_current_quantity
    FROM public.product_variants
    WHERE id = p_variant_id AND company_id = p_company_id;

    -- Update inventory and log the change
    UPDATE public.product_variants
    SET inventory_quantity = inventory_quantity - p_quantity_sold
    WHERE id = p_variant_id;

    INSERT INTO public.inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id)
    VALUES (p_company_id, p_variant_id, 'sale', -p_quantity_sold, v_current_quantity - p_quantity_sold, p_order_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to create an audit log entry
CREATE OR REPLACE FUNCTION create_audit_log(
    p_company_id UUID,
    p_user_id UUID,
    p_action TEXT,
    p_details JSONB
) RETURNS VOID AS $$
BEGIN
    INSERT INTO public.audit_log(company_id, user_id, action, details)
    VALUES (p_company_id, p_user_id, p_action, p_details);
END;
$$ LANGUAGE plpgsql;

-- Main function to record an order from a platform
CREATE OR REPLACE FUNCTION record_order_from_platform(
    p_company_id UUID,
    p_order_payload JSONB,
    p_platform TEXT
)
RETURNS UUID AS $$
DECLARE
    v_customer_id UUID;
    v_order_id UUID;
    v_variant_id UUID;
    v_line_item JSONB;
    v_sku TEXT;
    v_quantity INT;
    v_current_stock INT;
BEGIN
    -- Upsert customer
    INSERT INTO public.customers (company_id, email, name, external_customer_id)
    VALUES (
        p_company_id,
        p_order_payload->'customer'->>'email',
        (p_order_payload->'customer'->>'first_name') || ' ' || (p_order_payload->'customer'->>'last_name'),
        p_order_payload->'customer'->>'id'
    )
    ON CONFLICT (company_id, email) DO UPDATE SET
        name = EXCLUDED.name,
        external_customer_id = EXCLUDED.external_customer_id
    RETURNING id INTO v_customer_id;

    -- Upsert order
    INSERT INTO public.orders (company_id, order_number, external_order_id, customer_id, financial_status, fulfillment_status, currency, subtotal, total_tax, total_shipping, total_discounts, total_amount, source_platform, created_at)
    VALUES (
        p_company_id,
        p_order_payload->>'order_number',
        p_order_payload->>'id',
        v_customer_id,
        p_order_payload->>'financial_status',
        p_order_payload->>'fulfillment_status',
        p_order_payload->>'currency',
        (p_order_payload->>'subtotal_price')::numeric * 100,
        (p_order_payload->>'total_tax')::numeric * 100,
        (p_order_payload->>'total_shipping_price')::numeric * 100,
        (p_order_payload->>'total_discounts')::numeric * 100,
        (p_order_payload->>'total_price')::numeric * 100,
        p_platform,
        (p_order_payload->>'created_at')::TIMESTAMPTZ
    )
    ON CONFLICT (company_id, external_order_id) DO UPDATE SET
        financial_status = EXCLUDED.financial_status,
        fulfillment_status = EXCLUDED.fulfillment_status,
        updated_at = now()
    RETURNING id INTO v_order_id;

    -- Process line items
    FOR v_line_item IN SELECT * FROM jsonb_array_elements(p_order_payload->'line_items')
    LOOP
        v_sku := v_line_item->>'sku';
        v_quantity := (v_line_item->>'quantity')::INT;

        -- Find the variant by SKU
        SELECT id, inventory_quantity INTO v_variant_id, v_current_stock
        FROM public.product_variants
        WHERE sku = v_sku AND company_id = p_company_id;

        -- If variant exists, insert line item and update inventory
        IF v_variant_id IS NOT NULL THEN
            INSERT INTO public.order_line_items (order_id, variant_id, company_id, product_name, variant_title, sku, quantity, price, external_line_item_id)
            VALUES (
                v_order_id,
                v_variant_id,
                p_company_id,
                v_line_item->>'title',
                v_line_item->>'variant_title',
                v_sku,
                v_quantity,
                (v_line_item->>'price')::numeric * 100,
                v_line_item->>'id'
            );

            -- Check for sufficient stock before updating
            IF v_current_stock >= v_quantity THEN
                -- This will call the ledger trigger automatically
                UPDATE public.product_variants
                SET inventory_quantity = inventory_quantity - v_quantity
                WHERE id = v_variant_id;
            ELSE
                -- Not enough stock, log an audit event instead of failing the transaction
                PERFORM create_audit_log(
                    p_company_id,
                    null,
                    'insufficient_stock_for_sale',
                    jsonb_build_object(
                        'order_id', v_order_id,
                        'order_number', p_order_payload->>'order_number',
                        'sku', v_sku,
                        'requested_quantity', v_quantity,
                        'available_quantity', v_current_stock
                    )
                );
            END IF;
        ELSE
             PERFORM create_audit_log(
                    p_company_id,
                    null,
                    'unknown_sku_in_order',
                    jsonb_build_object(
                        'order_id', v_order_id,
                        'order_number', p_order_payload->>'order_number',
                        'sku', v_sku
                    )
                );
        END IF;
    END LOOP;

    RETURN v_order_id;
END;
$$ LANGUAGE plpgsql;


-- Function to lock a user account
CREATE OR REPLACE FUNCTION lock_user_account(
    p_user_id UUID,
    p_lockout_duration INTERVAL
)
RETURNS void AS $$
BEGIN
    UPDATE auth.users
    SET banned_until = now() + p_lockout_duration
    WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- #################################################################
--    VIEWS
-- #################################################################
CREATE OR REPLACE VIEW public.customers_view AS
SELECT 
    c.id,
    c.company_id,
    c.name as customer_name,
    c.email,
    COUNT(o.id) as total_orders,
    SUM(o.total_amount) as total_spent,
    MIN(o.created_at) as first_order_date,
    c.created_at
FROM 
    public.customers c
LEFT JOIN 
    public.orders o ON c.id = o.customer_id
GROUP BY 
    c.id;


-- #################################################################
--    MATERIALIZED VIEWS & REFRESH LOGIC
-- #################################################################

-- Create materialized view for product variants with details
CREATE MATERIALIZED VIEW IF NOT EXISTS product_variants_with_details_mat AS
SELECT
    pv.*,
    p.title AS product_title,
    p.status as product_status,
    p.image_url,
    p.product_type
FROM
    product_variants pv
JOIN
    products p ON pv.product_id = p.id;

CREATE UNIQUE INDEX IF NOT EXISTS idx_product_variants_with_details_mat_id ON product_variants_with_details_mat (id);


-- Create materialized view for daily sales
CREATE MATERIALIZED VIEW IF NOT EXISTS daily_sales_mat AS
SELECT
    company_id,
    date_trunc('day', created_at) AS sale_date,
    SUM(total_amount) AS total_revenue,
    COUNT(id) AS total_orders
FROM
    orders
GROUP BY
    company_id,
    date_trunc('day', created_at);

CREATE UNIQUE INDEX IF NOT EXISTS idx_daily_sales_mat_company_date ON daily_sales_mat (company_id, sale_date);


-- Function to refresh all materialized views for a company
-- This is designed to be called after data syncs or major updates.
CREATE OR REPLACE FUNCTION refresh_all_matviews(p_company_id UUID)
RETURNS void AS $$
BEGIN
    -- A true implementation would filter refreshes by company_id if the views supported it.
    -- For now, we refresh concurrently for performance.
    REFRESH MATERIALIZED VIEW CONCURRENTLY product_variants_with_details_mat;
    REFRESH MATERIALIZED VIEW CONCURRENTLY daily_sales_mat;
END;
$$ LANGUAGE plpgsql;



-- #################################################################
--    SECURITY POLICIES (RLS)
-- #################################################################
ALTER TABLE companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE company_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE channel_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE export_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE imports ENABLE ROW LEVEL SECURITY;


-- Policies for 'companies' table
DROP POLICY IF EXISTS "Allow owner to read their own company" ON companies;
CREATE POLICY "Allow owner to read their own company" ON companies FOR SELECT
USING (auth.uid() = owner_id);

-- Policies for 'company_users' table
DROP POLICY IF EXISTS "Allow users to see who is in their company" ON company_users;
CREATE POLICY "Allow users to see who is in their company" ON company_users FOR SELECT
USING (company_id IN (SELECT get_company_id_for_user(auth.uid())));

DROP POLICY IF EXISTS "Allow owners to manage their company users" ON company_users;
CREATE POLICY "Allow owners to manage their company users" ON company_users FOR ALL
USING (company_id IN (SELECT get_company_id_for_user(auth.uid())))
WITH CHECK (
    company_id IN (SELECT get_company_id_for_user(auth.uid())) AND
    (SELECT role FROM company_users WHERE user_id = auth.uid() AND company_id = company_users.company_id) = 'Owner'
);


-- Generic policy for most tables based on company_id
CREATE OR REPLACE FUNCTION create_company_based_policy(table_name TEXT)
RETURNS void AS $$
BEGIN
    EXECUTE format('DROP POLICY IF EXISTS "Allow full access based on company" ON %I;', table_name);
    EXECUTE format(
        'CREATE POLICY "Allow full access based on company" ON %I FOR ALL ' ||
        'USING (company_id IN (SELECT get_company_id_for_user(auth.uid()))) ' ||
        'WITH CHECK (company_id IN (SELECT get_company_id_for_user(auth.uid())));',
        table_name
    );
END;
$$ LANGUAGE plpgsql;

-- Apply the generic policy to all relevant tables
SELECT create_company_based_policy('company_settings');
SELECT create_company_based_policy('integrations');
SELECT create_company_based_policy('products');
SELECT create_company_based_policy('product_variants');
SELECT create_company_based_policy('suppliers');
SELECT create_company_based_policy('customers');
SELECT create_company_based_policy('orders');
SELECT create_company_based_policy('order_line_items');
SELECT create_company_based_policy('inventory_ledger');
SELECT create_company_based_policy('purchase_orders');
SELECT create_company_based_policy('purchase_order_line_items');
SELECT create_company_based_policy('conversations');
SELECT create_company_based_policy('messages');
SELECT create_company_based_policy('audit_log');
SELECT create_company_based_policy('feedback');
SELECT create_company_based_policy('channel_fees');
SELECT create_company_based_policy('export_jobs');
SELECT create_company_based_policy('imports');


-- #################################################################
--    ANALYTICAL & BUSINESS LOGIC FUNCTIONS
-- #################################################################

-- Function to get supplier performance report
CREATE OR REPLACE FUNCTION get_supplier_performance_report(p_company_id UUID)
RETURNS TABLE (
    supplier_name TEXT,
    total_profit BIGINT,
    total_sales_count BIGINT,
    distinct_products_sold BIGINT,
    average_margin NUMERIC,
    sell_through_rate NUMERIC,
    on_time_delivery_rate NUMERIC,
    average_lead_time_days NUMERIC,
    total_completed_orders BIGINT
) AS $$
BEGIN
    RETURN QUERY
    WITH supplier_sales AS (
        SELECT
            s.id AS supplier_id,
            s.name,
            oli.quantity,
            oli.price,
            oli.cost_at_time
        FROM suppliers s
        JOIN product_variants pv ON s.id = pv.supplier_id
        JOIN order_line_items oli ON pv.id = oli.variant_id
        WHERE s.company_id = p_company_id AND oli.cost_at_time IS NOT NULL
    )
    SELECT
        s.name AS supplier_name,
        COALESCE(SUM(ss.quantity * (ss.price - ss.cost_at_time)), 0)::BIGINT AS total_profit,
        COALESCE(COUNT(ss.quantity), 0)::BIGINT AS total_sales_count,
        COALESCE(COUNT(DISTINCT pv.id), 0)::BIGINT AS distinct_products_sold,
        COALESCE(AVG((ss.price - ss.cost_at_time)::float / ss.price) * 100, 0)::NUMERIC(10,2) as average_margin,
        (
            SUM(CASE WHEN o.created_at > (now() - interval '90 days') THEN oli.quantity ELSE 0 END)::decimal /
            NULLIF(SUM(pv.inventory_quantity + CASE WHEN o.created_at > (now() - interval '90 days') THEN oli.quantity ELSE 0 END), 0)
        )::NUMERIC(10,2) AS sell_through_rate,
        (
            SUM(CASE WHEN po.status = 'Received' AND po.updated_at <= po.expected_arrival_date THEN 1 ELSE 0 END)::decimal /
            NULLIF(COUNT(CASE WHEN po.status = 'Received' THEN 1 END), 0) * 100
        )::NUMERIC(10,1) AS on_time_delivery_rate,
        AVG(po.updated_at - po.created_at)::NUMERIC(10,1) AS average_lead_time_days,
        COALESCE(COUNT(DISTINCT po.id), 0)::BIGINT AS total_completed_orders
    FROM suppliers s
    LEFT JOIN product_variants pv ON s.id = pv.supplier_id
    LEFT JOIN order_line_items oli ON pv.id = oli.variant_id
    LEFT JOIN orders o ON oli.order_id = o.id
    LEFT JOIN supplier_sales ss ON s.id = ss.supplier_id
    LEFT JOIN purchase_orders po ON s.id = po.supplier_id
    WHERE s.company_id = p_company_id
    GROUP BY s.id;
END;
$$ LANGUAGE plpgsql;


-- Function to get dead stock report
CREATE OR REPLACE FUNCTION get_dead_stock_report(p_company_id UUID)
RETURNS TABLE (
    sku TEXT,
    product_name TEXT,
    quantity INT,
    total_value INT,
    last_sale_date TIMESTAMPTZ
) AS $$
DECLARE
    v_dead_stock_days INT;
BEGIN
    SELECT dead_stock_days INTO v_dead_stock_days
    FROM company_settings
    WHERE company_id = p_company_id;

    RETURN QUERY
    WITH last_sale AS (
        SELECT
            oli.variant_id,
            MAX(o.created_at) AS last_sale
        FROM order_line_items oli
        JOIN orders o ON oli.order_id = o.id
        WHERE o.company_id = p_company_id
        GROUP BY oli.variant_id
    )
    SELECT
        pv.sku,
        p.title AS product_name,
        pv.inventory_quantity AS quantity,
        (pv.inventory_quantity * pv.cost)::INT AS total_value,
        ls.last_sale AS last_sale_date
    FROM product_variants pv
    JOIN products p ON pv.product_id = p.id
    LEFT JOIN last_sale ls ON pv.id = ls.variant_id
    WHERE pv.company_id = p_company_id
      AND pv.inventory_quantity > 0
      AND (ls.last_sale IS NULL OR ls.last_sale < now() - (v_dead_stock_days || ' days')::interval);
END;
$$ LANGUAGE plpgsql;


-- Function to get reorder suggestions
CREATE OR REPLACE FUNCTION get_reorder_suggestions(p_company_id UUID)
RETURNS TABLE (
    variant_id UUID,
    product_id UUID,
    sku TEXT,
    product_name TEXT,
    supplier_name TEXT,
    supplier_id UUID,
    current_quantity INT,
    suggested_reorder_quantity INT,
    unit_cost INT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        pv.id AS variant_id,
        p.id AS product_id,
        pv.sku,
        p.title AS product_name,
        s.name AS supplier_name,
        s.id AS supplier_id,
        pv.inventory_quantity AS current_quantity,
        GREATEST(pv.reorder_quantity, 10) AS suggested_reorder_quantity, -- Use reorder_quantity or a default
        pv.cost AS unit_cost
    FROM product_variants pv
    JOIN products p ON pv.product_id = p.id
    LEFT JOIN suppliers s ON pv.supplier_id = s.id
    WHERE pv.company_id = p_company_id
      AND pv.inventory_quantity <= pv.reorder_point;
END;
$$ LANGUAGE plpgsql;

-- Final functions for batch processing
CREATE OR REPLACE FUNCTION batch_upsert_costs(p_records JSONB, p_company_id UUID, p_user_id UUID)
RETURNS void AS $$
DECLARE
    v_rec RECORD;
    v_supplier_id UUID;
BEGIN
    FOR v_rec IN SELECT * FROM jsonb_to_recordset(p_records) AS x(
        sku TEXT,
        cost INT,
        supplier_name TEXT,
        reorder_point INT,
        reorder_quantity INT
    )
    LOOP
        -- Find supplier by name
        IF v_rec.supplier_name IS NOT NULL THEN
            SELECT id INTO v_supplier_id FROM suppliers WHERE name = v_rec.supplier_name AND company_id = p_company_id;
        ELSE
            v_supplier_id := NULL;
        END IF;

        -- Upsert costs and reorder points
        UPDATE product_variants
        SET
            cost = v_rec.cost,
            reorder_point = v_rec.reorder_point,
            reorder_quantity = v_rec.reorder_quantity,
            supplier_id = v_supplier_id,
            updated_at = now()
        WHERE sku = v_rec.sku AND company_id = p_company_id;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION batch_upsert_suppliers(p_records JSONB, p_company_id UUID, p_user_id UUID)
RETURNS void AS $$
DECLARE
    v_rec RECORD;
BEGIN
    FOR v_rec IN SELECT * FROM jsonb_to_recordset(p_records) AS x(
        name TEXT,
        email TEXT,
        phone TEXT,
        default_lead_time_days INT,
        notes TEXT
    )
    LOOP
        INSERT INTO suppliers (company_id, name, email, phone, default_lead_time_days, notes)
        VALUES (p_company_id, v_rec.name, v_rec.email, v_rec.phone, v_rec.default_lead_time_days, v_rec.notes)
        ON CONFLICT (company_id, name) DO UPDATE SET
            email = EXCLUDED.email,
            phone = EXCLUDED.phone,
            default_lead_time_days = EXCLUDED.default_lead_time_days,
            notes = EXCLUDED.notes,
            updated_at = now();
    END LOOP;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION batch_import_sales(p_records JSONB, p_company_id UUID, p_user_id UUID)
RETURNS void AS $$
DECLARE
    v_order RECORD;
BEGIN
    FOR v_order IN SELECT * FROM jsonb_to_recordset(p_records) AS x(
        order_date TIMESTAMPTZ,
        sku TEXT,
        quantity INT,
        unit_price INT,
        customer_email TEXT,
        order_id TEXT
    )
    LOOP
        -- This simplified version calls the single-order function.
        -- A more optimized version might handle batching within the PL/pgSQL function itself.
        PERFORM record_order_from_platform(
            p_company_id,
            jsonb_build_object(
                'id', v_order.order_id,
                'order_number', v_order.order_id,
                'customer', jsonb_build_object('email', v_order.customer_email),
                'total_price', (v_order.quantity * v_order.unit_price)::float / 100,
                'created_at', v_order.order_date,
                'line_items', jsonb_build_array(
                    jsonb_build_object(
                        'sku', v_order.sku,
                        'quantity', v_order.quantity,
                        'price', v_order.unit_price::float / 100
                    )
                )
            ),
            'historical_import'
        );
    END LOOP;
END;
$$ LANGUAGE plpgsql;
