
-- -----------------------------------------------------------------------------
-- InvoChat - Database Schema
--
-- This script is designed to be run once in the Supabase SQL Editor to set up
-- all necessary tables, roles, functions, and security policies.
--
-- For existing users, a separate migration script should be used.
-- -----------------------------------------------------------------------------

-- ----------------------------
-- Extensions
-- ----------------------------
-- These extensions provide additional functionality used by the application.
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";
CREATE EXTENSION IF NOT EXISTS "pg_trgm" WITH SCHEMA "extensions";


-- ----------------------------
-- Tables
-- ----------------------------

-- Manages company information. Each user belongs to a single company.
CREATE TABLE IF NOT EXISTS public.companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Stores user profiles, linking Supabase auth users to companies and roles.
CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email TEXT,
    role TEXT DEFAULT 'member'::text,
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Stores company-specific settings for business logic.
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id UUID PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days INTEGER NOT NULL DEFAULT 90,
    fast_moving_days INTEGER NOT NULL DEFAULT 30,
    predictive_stock_days INTEGER NOT NULL DEFAULT 7,
    currency TEXT DEFAULT 'USD',
    timezone TEXT DEFAULT 'UTC',
    tax_rate NUMERIC DEFAULT 0,
    custom_rules JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    subscription_status TEXT DEFAULT 'trial',
    subscription_plan TEXT DEFAULT 'starter',
    subscription_expires_at TIMESTAMPTZ,
    stripe_customer_id TEXT,
    stripe_subscription_id TEXT,
    promo_sales_lift_multiplier REAL NOT NULL DEFAULT 2.5,
    overstock_multiplier INTEGER NOT NULL DEFAULT 3,
    high_value_threshold INTEGER NOT NULL DEFAULT 1000
);

-- Stores product master data.
CREATE TABLE IF NOT EXISTS public.products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
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
    fts_document TSVECTOR,
    UNIQUE(company_id, external_product_id)
);

-- Stores individual product variations (SKUs).
CREATE TABLE IF NOT EXISTS public.product_variants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
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
    location TEXT,
    external_variant_id TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(company_id, sku),
    UNIQUE(company_id, external_variant_id)
);

-- Tracks every change to inventory quantity for a full audit trail.
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type TEXT NOT NULL,
    quantity_change INTEGER NOT NULL,
    new_quantity INTEGER NOT NULL,
    related_id UUID,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Stores customer information.
CREATE TABLE IF NOT EXISTS public.customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name TEXT NOT NULL,
    email TEXT,
    total_orders INTEGER DEFAULT 0,
    total_spent INTEGER DEFAULT 0,
    first_order_date DATE,
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Stores customer addresses.
CREATE TABLE IF NOT EXISTS public.customer_addresses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
    address_type TEXT NOT NULL DEFAULT 'shipping',
    first_name TEXT,
    last_name TEXT,
    company TEXT,
    address1 TEXT,
    address2 TEXT,
    city TEXT,
    province_code TEXT,
    country_code TEXT,
    zip TEXT,
    phone TEXT,
    is_default BOOLEAN DEFAULT false
);

-- Stores sales order headers.
CREATE TABLE IF NOT EXISTS public.orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number TEXT NOT NULL,
    external_order_id TEXT,
    customer_id UUID REFERENCES public.customers(id),
    financial_status TEXT DEFAULT 'pending',
    fulfillment_status TEXT DEFAULT 'unfulfilled',
    currency TEXT DEFAULT 'USD',
    subtotal INTEGER NOT NULL DEFAULT 0,
    total_tax INTEGER DEFAULT 0,
    total_shipping INTEGER DEFAULT 0,
    total_discounts INTEGER DEFAULT 0,
    total_amount INTEGER NOT NULL,
    source_platform TEXT,
    source_name TEXT,
    tags TEXT[],
    notes TEXT,
    cancelled_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(company_id, external_order_id)
);

-- Stores line items for each sales order.
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id) ON DELETE RESTRICT,
    product_name TEXT NOT NULL,
    variant_title TEXT,
    sku TEXT NOT NULL,
    quantity INTEGER NOT NULL,
    price INTEGER NOT NULL,
    total_discount INTEGER DEFAULT 0,
    tax_amount INTEGER DEFAULT 0,
    cost_at_time INTEGER,
    fulfillment_status TEXT DEFAULT 'unfulfilled',
    requires_shipping BOOLEAN DEFAULT true,
    external_line_item_id TEXT
);

-- Stores supplier information.
CREATE TABLE IF NOT EXISTS public.suppliers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    default_lead_time_days INTEGER,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Stores purchase order headers.
CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id UUID REFERENCES public.suppliers(id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'Draft',
    po_number TEXT NOT NULL,
    total_cost INTEGER NOT NULL,
    expected_arrival_date DATE,
    idempotency_key UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(company_id, po_number)
);

-- Stores line items for each purchase order.
CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    purchase_order_id UUID NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    quantity INTEGER NOT NULL,
    cost INTEGER NOT NULL
);

-- Stores details about connected e-commerce platforms.
CREATE TABLE IF NOT EXISTS public.integrations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform TEXT NOT NULL,
    shop_domain TEXT,
    shop_name TEXT,
    is_active BOOLEAN DEFAULT false,
    last_sync_at TIMESTAMPTZ,
    sync_status TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, platform)
);

-- Stores AI chat conversation metadata.
CREATE TABLE IF NOT EXISTS public.conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    last_accessed_at TIMESTAMPTZ DEFAULT now(),
    is_starred BOOLEAN DEFAULT false
);

-- Stores individual chat messages.
CREATE TABLE IF NOT EXISTS public.messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role TEXT NOT NULL,
    content TEXT,
    component TEXT,
    component_props JSONB,
    visualization JSONB,
    confidence NUMERIC,
    assumptions TEXT[],
    created_at TIMESTAMPTZ DEFAULT now(),
    is_error BOOLEAN DEFAULT false
);

-- Stores audit log entries for important actions.
CREATE TABLE IF NOT EXISTS public.audit_log (
    id BIGSERIAL PRIMARY KEY,
    company_id UUID REFERENCES public.companies(id) ON DELETE SET NULL,
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    details JSONB,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Stores channel-specific fees for profitability calculations.
CREATE TABLE IF NOT EXISTS public.channel_fees (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    channel_name TEXT NOT NULL,
    percentage_fee NUMERIC NOT NULL,
    fixed_fee NUMERIC NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, channel_name)
);

-- Tracks processed webhook events to prevent replays.
CREATE TABLE IF NOT EXISTS public.webhook_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id UUID NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id TEXT NOT NULL,
    processed_at TIMESTAMPTZ DEFAULT now(),
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(integration_id, webhook_id)
);

-- Stores data export job details.
CREATE TABLE IF NOT EXISTS public.export_jobs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    requested_by_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'pending', -- pending, processing, completed, failed
    download_url TEXT,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Stores sales discounts.
CREATE TABLE IF NOT EXISTS public.discounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    code TEXT NOT NULL,
    type TEXT NOT NULL, -- 'percentage' or 'fixed_amount'
    value INTEGER NOT NULL, -- in cents for fixed, basis points for percentage
    minimum_purchase INTEGER,
    usage_limit INTEGER,
    usage_count INTEGER DEFAULT 0,
    applies_to TEXT DEFAULT 'all', -- 'all', 'products', 'collections'
    starts_at TIMESTAMPTZ,
    ends_at TIMESTAMPTZ,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Stores order refunds.
CREATE TABLE IF NOT EXISTS public.refunds (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    refund_number TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    reason TEXT,
    note TEXT,
    total_amount INTEGER NOT NULL,
    created_by_user_id UUID REFERENCES auth.users(id),
    external_refund_id TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Stores line items for each refund.
CREATE TABLE IF NOT EXISTS public.refund_line_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    refund_id UUID NOT NULL REFERENCES public.refunds(id) ON DELETE CASCADE,
    order_line_item_id UUID NOT NULL REFERENCES public.order_line_items(id) ON DELETE CASCADE,
    quantity INTEGER NOT NULL,
    amount INTEGER NOT NULL,
    restock BOOLEAN DEFAULT true
);

-- ADD SOFT DELETE COLUMNS BEFORE CREATING VIEWS
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
ALTER TABLE public.product_variants ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

-- ----------------------------
-- Views
-- ----------------------------

-- A unified view of all inventory items, combining product and variant details.
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.id,
    p.id as product_id,
    p.title as product_title,
    p.status as product_status,
    p.image_url,
    p.product_type,
    pv.company_id,
    pv.sku,
    pv.title as title, -- This is the variant's own title (e.g., "Large")
    pv.option1_name,
    pv.option1_value,
    pv.option2_name,
    pv.option2_value,
    pv.option3_name,
    pv.option3_value,
    pv.barcode,
    pv.price,
    pv.cost,
    pv.inventory_quantity,
    pv.location,
    pv.external_variant_id
FROM
    public.product_variants pv
JOIN
    public.products p ON pv.product_id = p.id
WHERE p.deleted_at IS NULL AND pv.deleted_at IS NULL;


-- A unified view of sales orders with customer and company details.
CREATE OR REPLACE VIEW public.orders_view AS
SELECT
    o.id,
    o.company_id,
    o.order_number,
    o.created_at,
    o.total_amount,
    o.financial_status,
    o.fulfillment_status,
    o.source_platform,
    c.email as customer_email
FROM
    public.orders o
LEFT JOIN
    public.customers c ON o.customer_id = c.id
WHERE c.deleted_at IS NULL;

-- A view to see customer details with aggregated sales data.
CREATE OR REPLACE VIEW public.customers_view AS
SELECT
    c.id,
    c.company_id,
    c.customer_name,
    c.email,
    c.created_at,
    COALESCE(s.total_orders, 0) as total_orders,
    COALESCE(s.total_spent, 0) as total_spent
FROM
    public.customers c
LEFT JOIN (
    SELECT
        customer_id,
        COUNT(id) as total_orders,
        SUM(total_amount) as total_spent
    FROM
        public.orders
    GROUP BY
        customer_id
) s ON c.id = s.customer_id
WHERE c.deleted_at IS NULL;


-- ----------------------------
-- Performance Indexes
-- ----------------------------
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_sku_company ON public.product_variants(sku, company_id);
CREATE INDEX IF NOT EXISTS idx_orders_company_id_created_at ON public.orders(company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON public.order_line_items(variant_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id_created_at ON public.inventory_ledger(variant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON public.suppliers(company_id);
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers(company_id);
CREATE INDEX IF NOT EXISTS idx_integrations_company_id ON public.integrations(company_id);
CREATE INDEX IF NOT EXISTS idx_conversations_user_id ON public.conversations(user_id);

-- Composite indexes for common query patterns
CREATE INDEX IF NOT EXISTS idx_orders_company_created_status ON public.orders(company_id, created_at DESC, financial_status);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_order ON public.order_line_items(variant_id, order_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_created ON public.inventory_ledger(variant_id, created_at DESC);

-- Index for full-text search
CREATE INDEX IF NOT EXISTS products_fts_document_idx ON public.products USING GIN (fts_document);


-- ----------------------------
-- Security & Roles
-- ----------------------------

-- Helper function to get the company ID from a user's JWT.
CREATE OR REPLACE FUNCTION public.get_company_id()
RETURNS UUID AS $$
BEGIN
    RETURN (current_setting('request.jwt.claims', true)::jsonb ->> 'company_id')::UUID;
END;
$$ LANGUAGE plpgsql STABLE;

-- Function to check user permissions.
CREATE OR REPLACE FUNCTION public.check_user_permission(p_user_id UUID, p_required_role TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    user_role TEXT;
BEGIN
    SELECT role INTO user_role FROM public.users WHERE id = p_user_id;
    IF p_required_role = 'Owner' AND user_role = 'Owner' THEN
        RETURN TRUE;
    ELSIF p_required_role = 'Admin' AND (user_role = 'Owner' OR user_role = 'Admin') THEN
        RETURN TRUE;
    ELSE
        RETURN FALSE;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ----------------------------
-- Row-Level Security (RLS)
-- ----------------------------

-- This function dynamically enables RLS and applies a standard company-based policy
-- to all tables in the public schema that have a 'company_id' column.
-- It also handles special cases for tables without a direct company_id.
CREATE OR REPLACE FUNCTION enable_rls_for_all_tables()
RETURNS void AS $$
DECLARE
    tbl_name TEXT;
BEGIN
    FOR tbl_name IN
        SELECT tablename FROM pg_tables WHERE schemaname = 'public'
    LOOP
        EXECUTE 'ALTER TABLE public.' || quote_ident(tbl_name) || ' ENABLE ROW LEVEL SECURITY';
        -- Default policy for tables with a company_id
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = tbl_name AND column_name = 'company_id') THEN
            EXECUTE 'CREATE POLICY "Allow all access to own company data" ON public.' || quote_ident(tbl_name) || ' FOR ALL USING (company_id = public.get_company_id());';
        -- Special cases for tables without a direct company_id
        ELSIF tbl_name = 'users' THEN
             EXECUTE 'CREATE POLICY "Allow users to see other users in their company" ON public.users FOR SELECT USING (company_id = public.get_company_id());';
             EXECUTE 'CREATE POLICY "Allow users to update their own profile" ON public.users FOR UPDATE USING (id = auth.uid());';
        ELSIF tbl_name = 'webhook_events' THEN
            EXECUTE 'CREATE POLICY "Allow access to own company webhook events" ON public.webhook_events FOR ALL USING (EXISTS (SELECT 1 FROM integrations i WHERE i.id = integration_id AND i.company_id = public.get_company_id()));';
        ELSIF tbl_name = 'customer_addresses' THEN
            EXECUTE 'CREATE POLICY "Allow access to own company customer addresses" ON public.customer_addresses FOR ALL USING (EXISTS (SELECT 1 FROM customers c WHERE c.id = customer_id AND c.company_id = public.get_company_id()));';
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Execute the function to apply RLS policies.
SELECT enable_rls_for_all_tables();

-- A specific policy for the users table to allow users to view others in their company.
ALTER TABLE public.users DROP POLICY IF EXISTS "Allow all access to own company data";
CREATE POLICY "Allow users to see other users in their company" ON public.users FOR SELECT USING (company_id = public.get_company_id());
CREATE POLICY "Allow users to update their own profile" ON public.users FOR UPDATE USING (id = auth.uid());


-- ----------------------------
-- Functions & Triggers
-- ----------------------------

-- Function to handle new user sign-ups.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    new_company_id UUID;
    user_company_name TEXT;
BEGIN
    -- Extract company name from auth metadata
    user_company_name := new.raw_app_meta_data->>'company_name';

    -- Create a new company for the user
    INSERT INTO public.companies (name) VALUES (user_company_name) RETURNING id INTO new_company_id;

    -- Create a user profile linked to the new company
    INSERT INTO public.users (id, company_id, email, role)
    VALUES (new.id, new_company_id, new.email, 'Owner');

    -- Create default settings for the new company
    INSERT INTO public.company_settings (company_id) VALUES (new_company_id);
    
    -- Update the user's app_metadata with the new company_id and role
    UPDATE auth.users
    SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'role', 'Owner')
    WHERE id = new.id;
    
    RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to execute handle_new_user on new user creation.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- Trigger function to update product fts_document
CREATE OR REPLACE FUNCTION update_fts_document()
RETURNS TRIGGER AS $$
BEGIN
    new.fts_document := to_tsvector('english',
        coalesce(new.title, '') || ' ' ||
        coalesce(new.description, '') || ' ' ||
        coalesce(new.product_type, '') || ' ' ||
        coalesce(array_to_string(new.tags, ' '), '')
    );
    RETURN new;
END;
$$ LANGUAGE plpgsql;

-- Trigger to execute fts update on product insert/update
DROP TRIGGER IF EXISTS products_fts_update_trigger ON public.products;
CREATE TRIGGER products_fts_update_trigger
BEFORE INSERT OR UPDATE ON public.products
FOR EACH ROW
EXECUTE FUNCTION update_fts_document();


-- Trigger function to create an inventory ledger entry on quantity change.
CREATE OR REPLACE FUNCTION log_inventory_change()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND OLD.inventory_quantity <> NEW.inventory_quantity THEN
        INSERT INTO public.inventory_ledger(company_id, variant_id, change_type, quantity_change, new_quantity, notes)
        VALUES (NEW.company_id, NEW.id, 'manual_adjustment', NEW.inventory_quantity - OLD.inventory_quantity, NEW.inventory_quantity, 'Manual adjustment in inventory UI.');
    ELSIF TG_OP = 'INSERT' THEN
         INSERT INTO public.inventory_ledger(company_id, variant_id, change_type, quantity_change, new_quantity, notes)
        VALUES (NEW.company_id, NEW.id, 'initial_stock', NEW.inventory_quantity, NEW.inventory_quantity, 'Initial stock level set.');
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for inventory changes
DROP TRIGGER IF EXISTS on_variant_quantity_change ON public.product_variants;
CREATE TRIGGER on_variant_quantity_change
AFTER INSERT OR UPDATE OF inventory_quantity ON public.product_variants
FOR EACH ROW
EXECUTE FUNCTION log_inventory_change();


-- Function to decrement stock when an order is placed.
CREATE OR REPLACE FUNCTION decrement_stock_on_sale()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.product_variants
    SET inventory_quantity = inventory_quantity - NEW.quantity
    WHERE id = NEW.variant_id;
    
    INSERT INTO public.inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id)
    SELECT NEW.company_id, NEW.variant_id, 'sale', -NEW.quantity, pv.inventory_quantity, NEW.order_id
    FROM public.product_variants pv
    WHERE pv.id = NEW.variant_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for new sales
DROP TRIGGER IF EXISTS on_new_order_line_item ON public.order_line_items;
CREATE TRIGGER on_new_order_line_item
AFTER INSERT ON public.order_line_items
FOR EACH ROW
EXECUTE FUNCTION decrement_stock_on_sale();


-- Function to increment stock when a PO is received.
CREATE OR REPLACE FUNCTION increment_stock_on_po_receipt()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND OLD.status <> 'Received' AND NEW.status = 'Received' THEN
        -- Loop through line items and update inventory
        FOR r IN (SELECT * FROM public.purchase_order_line_items WHERE purchase_order_id = NEW.id) LOOP
            UPDATE public.product_variants
            SET inventory_quantity = inventory_quantity + r.quantity
            WHERE id = r.variant_id;
            
            INSERT INTO public.inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id)
            SELECT NEW.company_id, r.variant_id, 'purchase_order', r.quantity, pv.inventory_quantity, NEW.id
            FROM public.product_variants pv
            WHERE pv.id = r.variant_id;
        END LOOP;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for PO status change
DROP TRIGGER IF EXISTS on_po_received ON public.purchase_orders;
CREATE TRIGGER on_po_received
AFTER UPDATE OF status ON public.purchase_orders
FOR EACH ROW
EXECUTE FUNCTION increment_stock_on_po_receipt();


-- Transactional function to create POs and update inventory atomically
CREATE OR REPLACE FUNCTION public.create_purchase_orders_from_suggestions(
    p_company_id UUID,
    p_user_id UUID,
    p_suggestions JSONB,
    p_idempotency_key UUID DEFAULT NULL
)
RETURNS INTEGER AS $$
DECLARE
    suggestion JSONB;
    supplier_map JSONB;
    supplier_id UUID;
    supplier_name TEXT;
    po_id UUID;
    total_cost INTEGER;
    created_po_count INTEGER := 0;
    po_number TEXT;
BEGIN
    -- Check for idempotency
    IF p_idempotency_key IS NOT NULL THEN
        IF EXISTS (SELECT 1 FROM purchase_orders WHERE idempotency_key = p_idempotency_key) THEN
            RETURN 0; -- Request already processed
        END IF;
    END IF;

    -- Group suggestions by supplier
    SELECT jsonb_object_agg(s.supplier_name, s.suggestions)
    INTO supplier_map
    FROM (
        SELECT
            COALESCE(d.value->>'supplier_name', 'Unknown Supplier') as supplier_name,
            jsonb_agg(d.value) as suggestions
        FROM jsonb_array_elements(p_suggestions) d
        GROUP BY supplier_name
    ) s;

    -- Loop through each supplier group
    FOR supplier_name, suggestion IN SELECT * FROM jsonb_each(supplier_map)
    LOOP
        -- Get supplier ID
        SELECT id INTO supplier_id FROM suppliers WHERE name = supplier_name AND company_id = p_company_id;

        -- Calculate total cost for the PO
        SELECT SUM((item->>'suggested_reorder_quantity')::INTEGER * (item->>'unit_cost')::INTEGER)
        INTO total_cost
        FROM jsonb_array_elements(suggestion) as item;

        -- Create PO number
        po_number := 'PO-' || to_char(now(), 'YYYYMMDD') || '-' || (SELECT COUNT(*) + 1 FROM purchase_orders WHERE created_at >= current_date);

        -- Create the purchase order
        INSERT INTO purchase_orders (company_id, supplier_id, status, po_number, total_cost, idempotency_key)
        VALUES (p_company_id, supplier_id, 'Ordered', po_number, COALESCE(total_cost, 0), p_idempotency_key)
        RETURNING id INTO po_id;
        created_po_count := created_po_count + 1;

        -- Insert line items
        INSERT INTO purchase_order_line_items (purchase_order_id, company_id, variant_id, quantity, cost)
        SELECT
            po_id,
            p_company_id,
            (item->>'variant_id')::UUID,
            (item->>'suggested_reorder_quantity')::INTEGER,
            (item->>'unit_cost')::INTEGER
        FROM jsonb_array_elements(suggestion) as item;

    END LOOP;

    RETURN created_po_count;
END;
$$ LANGUAGE plpgsql;


-- Final check: Ensure RLS is enforced on all tables. This is a safeguard.
DO $$
DECLARE
    tbl_name TEXT;
BEGIN
    FOR tbl_name IN
        SELECT tablename FROM pg_tables WHERE schemaname = 'public'
    LOOP
        EXECUTE 'ALTER TABLE public.' || quote_ident(tbl_name) || ' FORCE ROW LEVEL SECURITY';
    END LOOP;
END;
$$;

-- Grant usage on the public schema to the authenticated role
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO authenticated;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO authenticated;

-- Grant usage for anon role on specific functions
GRANT EXECUTE ON FUNCTION public.get_company_id() TO anon;

-- Note: The service_role key bypasses RLS. The anon and authenticated roles do not.
-- Test your RLS policies thoroughly after running this script.

-- That's it! Your database is now ready.

