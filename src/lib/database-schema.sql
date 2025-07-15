--
-- Universal SQL Script for InvoChat
-- This script is designed to be idempotent and can be run safely multiple times.
-- It creates all necessary tables, functions, views, and security policies.
--

-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =================================================================
-- 1. Table Definitions
-- =================================================================

-- Stores company information
CREATE TABLE IF NOT EXISTS public.companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Stores user information and their role within a company
CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY,
    company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE,
    email TEXT,
    role TEXT DEFAULT 'Member' CHECK (role IN ('Owner', 'Admin', 'Member')),
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Stores company-specific settings for business logic
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id UUID PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days INT NOT NULL DEFAULT 90,
    fast_moving_days INT NOT NULL DEFAULT 30,
    predictive_stock_days INT NOT NULL DEFAULT 7,
    overstock_multiplier INT NOT NULL DEFAULT 3,
    high_value_threshold INT NOT NULL DEFAULT 1000,
    currency TEXT DEFAULT 'USD',
    timezone TEXT DEFAULT 'UTC',
    tax_rate NUMERIC DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ
);

-- Stores supplier/vendor information
CREATE TABLE IF NOT EXISTS public.suppliers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    default_lead_time_days INT,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Stores core product information (parent products)
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
    fts_document TSVECTOR
);

-- Stores product variants (SKUs)
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
    price INT, -- in cents
    compare_at_price INT, -- in cents
    cost INT, -- in cents
    inventory_quantity INT NOT NULL DEFAULT 0,
    external_variant_id TEXT,
    location TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ
);

-- Stores customer information
CREATE TABLE IF NOT EXISTS public.customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name TEXT NOT NULL,
    email TEXT,
    total_orders INT DEFAULT 0,
    total_spent INT DEFAULT 0, -- in cents
    first_order_date DATE,
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Stores order headers
CREATE TABLE IF NOT EXISTS public.orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number TEXT NOT NULL,
    external_order_id TEXT,
    customer_id UUID REFERENCES public.customers(id),
    financial_status TEXT,
    fulfillment_status TEXT,
    currency TEXT,
    subtotal INT NOT NULL DEFAULT 0,
    total_tax INT,
    total_shipping INT,
    total_discounts INT,
    total_amount INT NOT NULL,
    source_platform TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ
);

-- Stores order line items
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id UUID REFERENCES public.product_variants(id),
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

-- Stores purchase order headers
CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id UUID REFERENCES public.suppliers(id),
    status TEXT NOT NULL DEFAULT 'Draft',
    po_number TEXT NOT NULL,
    total_cost INT NOT NULL,
    expected_arrival_date DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Stores purchase order line items
CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    purchase_order_id UUID NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id),
    quantity INT NOT NULL,
    cost INT NOT NULL -- in cents
);

-- Stores a ledger of all inventory movements
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id),
    change_type TEXT NOT NULL, -- e.g., 'sale', 'purchase_order', 'reconciliation'
    quantity_change INT NOT NULL,
    new_quantity INT NOT NULL,
    related_id UUID,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Stores integration information
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
    updated_at TIMESTAMPTZ
);

-- Stores chat conversation metadata
CREATE TABLE IF NOT EXISTS public.conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    last_accessed_at TIMESTAMPTZ DEFAULT now(),
    is_starred BOOLEAN DEFAULT false
);

-- Stores individual chat messages
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

-- Stores audit log entries
CREATE TABLE IF NOT EXISTS public.audit_log (
    id BIGSERIAL PRIMARY KEY,
    company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id UUID,
    action TEXT NOT NULL,
    details JSONB,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Stores webhook event IDs to prevent replay attacks
CREATE TABLE IF NOT EXISTS public.webhook_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id UUID NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id TEXT NOT NULL,
    processed_at TIMESTAMPTZ DEFAULT now(),
    created_at TIMESTAMPTZ DEFAULT now()
);

-- =================================================================
-- 2. Drop legacy columns if they exist
-- =================================================================
-- These are no longer needed and can be safely removed.
ALTER TABLE public.product_variants DROP COLUMN IF EXISTS weight;
ALTER TABLE public.product_variants DROP COLUMN IF EXISTS weight_unit;

-- =================================================================
-- 3. Views
-- =================================================================

-- Drop the view if it exists before creating it to ensure it's up to date
DROP VIEW IF EXISTS public.product_variants_with_details;

-- A helper view to get all variant details along with parent product info
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.id,
    pv.product_id,
    pv.company_id,
    pv.sku,
    pv.title,
    pv.option1_name,
    pv.option1_value,
    pv.option2_name,
    pv.option2_value,
    pv.option3_name,
    pv.option3_value,
    pv.barcode,
    pv.price,
    pv.compare_at_price,
    pv.cost,
    pv.inventory_quantity,
    pv.location,
    pv.external_variant_id,
    pv.created_at,
    pv.updated_at,
    p.title AS product_title,
    p.status AS product_status,
    p.image_url,
    p.product_type
FROM
    public.product_variants pv
JOIN
    public.products p ON pv.product_id = p.id;

-- =================================================================
-- 4. Indexes for Performance
-- =================================================================
-- These indexes are crucial for query performance, especially on tables
-- that will grow large.

CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_products_external_product_id ON public.products(external_product_id);
CREATE INDEX IF NOT EXISTS idx_products_fts_document ON public.products USING GIN (fts_document);

CREATE INDEX IF NOT EXISTS idx_product_variants_company_id ON public.product_variants(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_sku ON public.product_variants(sku);
CREATE INDEX IF NOT EXISTS idx_product_variants_external_variant_id ON public.product_variants(external_variant_id);

CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON public.orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_orders_external_order_id ON public.orders(external_order_id);

CREATE INDEX IF NOT EXISTS idx_order_line_items_company_id ON public.order_line_items(company_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON public.order_line_items(variant_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_sku ON public.order_line_items(sku);

CREATE INDEX IF NOT EXISTS idx_inventory_ledger_company_id ON public.inventory_ledger(company_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id ON public.inventory_ledger(variant_id);

CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers(company_id);
CREATE INDEX IF NOT EXISTS idx_customers_email ON public.customers(email);

CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON public.suppliers(company_id);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_company_id ON public.purchase_orders(company_id);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_supplier_id ON public.purchase_orders(supplier_id);

CREATE INDEX IF NOT EXISTS idx_users_company_id ON public.users(company_id);

CREATE INDEX IF NOT EXISTS idx_conversations_user_id ON public.conversations(user_id);
CREATE INDEX IF NOT EXISTS idx_conversations_company_id ON public.conversations(company_id);
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id ON public.messages(conversation_id);

CREATE INDEX IF NOT EXISTS idx_integrations_company_id ON public.integrations(company_id);

-- Unique index to prevent duplicate webhook processing
CREATE UNIQUE INDEX IF NOT EXISTS uidx_webhook_events_integration_webhook ON public.webhook_events(integration_id, webhook_id);

-- =================================================================
-- 5. Helper Functions
-- =================================================================

-- Function to get the company_id from the JWT claims
CREATE OR REPLACE FUNCTION get_my_company_id()
RETURNS UUID AS $$
BEGIN
  RETURN (current_setting('request.jwt.claims', true)::jsonb ->> 'company_id')::UUID;
END;
$$ LANGUAGE plpgsql STABLE;

-- =================================================================
-- 6. Row-Level Security (RLS)
-- =================================================================
-- This is the most critical security feature for a multi-tenant app.
-- It ensures that users from one company can NEVER see data from another.

-- Helper function to enable RLS on a table if it's not already enabled
CREATE OR REPLACE FUNCTION enable_rls_if_not_enabled(table_name TEXT)
RETURNS VOID AS $$
BEGIN
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE relname = table_name) THEN
    EXECUTE 'ALTER TABLE public.' || table_name || ' ENABLE ROW LEVEL SECURITY';
    RAISE NOTICE 'RLS enabled for table %', table_name;
  END IF;
END;
$$ LANGUAGE plpgsql;

-- Apply RLS to all company-specific tables
SELECT enable_rls_if_not_enabled('products');
SELECT enable_rls_if_not_enabled('product_variants');
SELECT enable_rls_if_not_enabled('orders');
SELECT enable_rls_if_not_enabled('order_line_items');
SELECT enable_rls_if_not_enabled('customers');
SELECT enable_rls_if_not_enabled('suppliers');
SELECT enable_rls_if_not_enabled('purchase_orders');
SELECT enable_rls_if_not_enabled('purchase_order_line_items');
SELECT enable_rls_if_not_enabled('inventory_ledger');
SELECT enable_rls_if_not_enabled('integrations');
SELECT enable_rls_if_not_enabled('company_settings');
SELECT enable_rls_if_not_enabled('conversations');
SELECT enable_rls_if_not_enabled('messages');
SELECT enable_rls_if_not_enabled('audit_log');
SELECT enable_rls_if_not_enabled('export_jobs');

-- Create generic RLS policies
DROP POLICY IF EXISTS "Users can only access their own company data" ON public.products;
CREATE POLICY "Users can only access their own company data" ON public.products FOR ALL USING (company_id = get_my_company_id());

DROP POLICY IF EXISTS "Users can only access their own company data" ON public.product_variants;
CREATE POLICY "Users can only access their own company data" ON public.product_variants FOR ALL USING (company_id = get_my_company_id());

DROP POLICY IF EXISTS "Users can only access their own company data" ON public.orders;
CREATE POLICY "Users can only access their own company data" ON public.orders FOR ALL USING (company_id = get_my_company_id());

DROP POLICY IF EXISTS "Users can only access their own company data" ON public.order_line_items;
CREATE POLICY "Users can only access their own company data" ON public.order_line_items FOR ALL USING (company_id = get_my_company_id());

DROP POLICY IF EXISTS "Users can only access their own company data" ON public.customers;
CREATE POLICY "Users can only access their own company data" ON public.customers FOR ALL USING (company_id = get_my_company_id());

DROP POLICY IF EXISTS "Users can only access their own company data" ON public.suppliers;
CREATE POLICY "Users can only access their own company data" ON public.suppliers FOR ALL USING (company_id = get_my_company_id());

DROP POLICY IF EXISTS "Users can only access their own company data" ON public.purchase_orders;
CREATE POLICY "Users can only access their own company data" ON public.purchase_orders FOR ALL USING (company_id = get_my_company_id());

DROP POLICY IF EXISTS "Users can only access their own company data" ON public.purchase_order_line_items;
CREATE POLICY "Users can only access their own company data" ON public.purchase_order_line_items FOR ALL USING (purchase_order_id IN (SELECT id FROM public.purchase_orders));

DROP POLICY IF EXISTS "Users can only access their own company data" ON public.inventory_ledger;
CREATE POLICY "Users can only access their own company data" ON public.inventory_ledger FOR ALL USING (company_id = get_my_company_id());

DROP POLICY IF EXISTS "Users can only access their own company data" ON public.integrations;
CREATE POLICY "Users can only access their own company data" ON public.integrations FOR ALL USING (company_id = get_my_company_id());

DROP POLICY IF EXISTS "Users can only access their own company data" ON public.company_settings;
CREATE POLICY "Users can only access their own company data" ON public.company_settings FOR ALL USING (company_id = get_my_company_id());

DROP POLICY IF EXISTS "Users can only access their own company data" ON public.conversations;
CREATE POLICY "Users can only access their own company data" ON public.conversations FOR ALL USING (company_id = get_my_company_id());

DROP POLICY IF EXISTS "Users can only access their own company data" ON public.messages;
CREATE POLICY "Users can only access their own company data" ON public.messages FOR ALL USING (company_id = get_my_company_id());

DROP POLICY IF EXISTS "Users can only access their own company data" ON public.audit_log;
CREATE POLICY "Users can only access their own company data" ON public.audit_log FOR ALL USING (company_id = get_my_company_id());

DROP POLICY IF EXISTS "Users can only access their own company data" ON public.export_jobs;
CREATE POLICY "Users can only access their own company data" ON public.export_jobs FOR ALL USING (company_id = get_my_company_id());

-- =================================================================
-- 7. Triggers and Functions for Data Automation
-- =================================================================

-- Function to handle new user sign-ups
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  new_company_id UUID;
  user_company_name TEXT;
BEGIN
  -- Check if company_name is provided in metadata
  user_company_name := new.raw_user_meta_data->>'company_name';

  IF user_company_name IS NULL OR user_company_name = '' THEN
    RAISE EXCEPTION 'Company name is required for new sign-ups.';
  END IF;

  -- Create a new company for the user
  INSERT INTO public.companies (name) VALUES (user_company_name) RETURNING id INTO new_company_id;

  -- Insert into our public.users table
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (new.id, new_company_id, new.email, 'Owner');

  -- Update the user's app_metadata with the new company_id
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id)
  WHERE id = new.id;

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger for new user sign-ups
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- Full-text search trigger function
CREATE OR REPLACE FUNCTION update_fts_document()
RETURNS TRIGGER AS $$
BEGIN
  NEW.fts_document := to_tsvector('english',
    COALESCE(NEW.title, '') || ' ' ||
    COALESCE(NEW.description, '') || ' ' ||
    COALESCE(NEW.product_type, '')
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS products_fts_update_trigger ON public.products;
CREATE TRIGGER products_fts_update_trigger
BEFORE INSERT OR UPDATE ON public.products
FOR EACH ROW
EXECUTE FUNCTION update_fts_document();


-- =================================================================
-- 8. Stored Procedures for Business Logic (RPC)
-- =================================================================

CREATE OR REPLACE FUNCTION public.create_purchase_orders_from_suggestions(
    p_company_id UUID,
    p_user_id UUID,
    p_suggestions JSONB
)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    suggestion JSONB;
    supplier_id_val UUID;
    supplier_name_val TEXT;
    po_id UUID;
    total_cost_val INT;
    po_number_val TEXT;
    created_po_count INT := 0;
    line_items_for_supplier JSONB[];
    grouped_suggestions HSTORE;
    supplier_key TEXT;
    line_item JSONB;
BEGIN
    -- Group suggestions by supplier
    SELECT hstore(array_agg(key), array_agg(value)) INTO grouped_suggestions
    FROM (
        SELECT
            COALESCE(s->>'supplier_id', 'UNKNOWN') as key,
            jsonb_agg(s) as value
        FROM jsonb_array_elements(p_suggestions) s
        GROUP BY COALESCE(s->>'supplier_id', 'UNKNOWN')
    ) as grouped;

    -- Iterate over each supplier group
    FOR supplier_key IN SELECT key FROM each(grouped_suggestions)
    LOOP
        line_items_for_supplier := ARRAY(SELECT jsonb_array_elements((grouped_suggestions -> supplier_key)::jsonb));
        
        -- Get supplier details
        IF supplier_key = 'UNKNOWN' THEN
            supplier_id_val := NULL;
            supplier_name_val := 'Unknown Supplier';
        ELSE
            supplier_id_val := supplier_key::UUID;
            SELECT name INTO supplier_name_val FROM public.suppliers WHERE id = supplier_id_val;
        END IF;

        -- Calculate total cost for the PO
        SELECT SUM((li->>'suggested_reorder_quantity')::INT * (li->>'unit_cost')::INT)
        INTO total_cost_val
        FROM unnest(line_items_for_supplier) AS li;
        
        -- Generate PO Number
        po_number_val := 'PO-' || to_char(now(), 'YYMMDD') || '-' || (created_po_count + 1);

        -- Create Purchase Order
        INSERT INTO public.purchase_orders (company_id, supplier_id, status, po_number, total_cost)
        VALUES (p_company_id, supplier_id_val, 'Draft', po_number_val, total_cost_val)
        RETURNING id INTO po_id;
        
        -- Create Line Items
        FOR line_item IN SELECT * FROM unnest(line_items_for_supplier)
        LOOP
            INSERT INTO public.purchase_order_line_items (purchase_order_id, variant_id, quantity, cost)
            VALUES (
                po_id,
                (line_item->>'variant_id')::UUID,
                (line_item->>'suggested_reorder_quantity')::INT,
                (line_item->>'unit_cost')::INT
            );
        END LOOP;
        
        created_po_count := created_po_count + 1;
        
    END LOOP;

    RETURN created_po_count;
END;
$$;
