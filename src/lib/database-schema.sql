
-- =================================================================
--  SETUP & HELPER FUNCTIONS
-- =================================================================

-- Enable the "plpgsql" language if not already enabled.
CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;

-- Enable UUID generation if not already enabled.
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;

-- Function to get the current user's company ID from their JWT claims.
-- This is a security-critical function for RLS.
DROP FUNCTION IF EXISTS public.get_current_company_id();
CREATE OR REPLACE FUNCTION public.get_current_company_id()
RETURNS UUID AS $$
BEGIN
  -- We use coalesce to handle cases where the claim might be missing,
  -- returning a NULL UUID which will not match any company_id.
  RETURN coalesce((current_setting('request.jwt.claims', true)::jsonb ->> 'company_id')::uuid, NULL);
END;
$$ LANGUAGE plpgsql STABLE;

-- =================================================================
--  COMPANY & USER MANAGEMENT
-- =================================================================

-- Companies table stores information about each business using the app.
CREATE TABLE IF NOT EXISTS public.companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Associate users with their company and role.
ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS company_id UUID;
ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS role TEXT;

-- Create a foreign key constraint to link users to companies.
-- This ensures data integrity.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'users_company_id_fkey' AND conrelid = 'auth.users'::regclass
  ) THEN
    ALTER TABLE auth.users 
    ADD CONSTRAINT users_company_id_fkey 
    FOREIGN KEY (company_id) 
    REFERENCES public.companies(id) 
    ON DELETE SET NULL;
  END IF;
END;
$$;


-- Function to create a new company and associate it with a new user.
-- This is called by the trigger when a new user signs up.
DROP FUNCTION IF EXISTS public.handle_new_user();
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  new_company_id UUID;
  company_name TEXT;
BEGIN
  -- Extract company_name from the user's metadata at signup.
  company_name := NEW.raw_user_meta_data ->> 'company_name';
  
  -- Create a new company for the user.
  INSERT INTO public.companies (name)
  VALUES (coalesce(company_name, 'My Company'))
  RETURNING id INTO new_company_id;

  -- Update the new user's record with the new company_id and default role.
  UPDATE auth.users
  SET
    company_id = new_company_id,
    role = 'Owner' -- All new signups are Owners by default.
  WHERE id = NEW.id;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to automatically call handle_new_user on new user creation.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();


-- =================================================================
--  ROW-LEVEL SECURITY (RLS) POLICIES
-- =================================================================
-- RLS is a critical security feature that ensures users can only access
-- data belonging to their own company.

-- Function to dynamically create an RLS policy on a given table.
-- This simplifies the process of applying consistent security rules.
DROP FUNCTION IF EXISTS public.create_company_rls_policy(TEXT);
CREATE OR REPLACE FUNCTION public.create_company_rls_policy(table_name TEXT)
RETURNS void AS $$
BEGIN
  -- First, enable RLS on the table if it's not already enabled.
  EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', table_name);
  
  -- Drop any existing policy with this name on the table to ensure idempotency.
  EXECUTE format('DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.%I', table_name);

  -- Create the policy. This policy allows all actions (SELECT, INSERT, UPDATE, DELETE)
  -- if the record's company_id matches the one from the user's JWT.
  EXECUTE format(
    'CREATE POLICY "Allow full access based on company_id" ON public.%I FOR ALL USING (company_id = get_current_company_id()) WITH CHECK (company_id = get_current_company_id())',
    table_name
  );
END;
$$ LANGUAGE plpgsql;

-- Special RLS policy for the companies table, as it's the root.
-- It uses the 'id' column instead of 'company_id'.
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.companies;
CREATE POLICY "Allow full access based on company_id"
    ON public.companies
    FOR ALL
    USING (id = get_current_company_id())
    WITH CHECK (id = get_current_company_id());

-- Apply the standard RLS policy to all other company-specific tables.
SELECT public.create_company_rls_policy('products');
SELECT public.create_company_rls_policy('product_variants');
SELECT public.create_company_rls_policy('orders');
SELECT public.create_company_rls_policy('order_line_items');
SELECT public.create_company_rls_policy('customers');
SELECT public.create_company_rls_policy('suppliers');
SELECT public.create_company_rls_policy('inventory_ledger');
SELECT public.create_company_rls_policy('company_settings');
SELECT public.create_company_rls_policy('purchase_orders');
SELECT public.create_company_rls_policy('purchase_order_line_items');
SELECT public.create_company_rls_policy('user_feedback');

-- =================================================================
--  APPLICATION TABLES
-- =================================================================

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
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, external_product_id)
);

CREATE TABLE IF NOT EXISTS public.product_variants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku TEXT,
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
    external_variant_id TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, sku),
    UNIQUE(company_id, external_variant_id)
);

CREATE TABLE IF NOT EXISTS public.customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name TEXT,
    email TEXT,
    total_orders INTEGER DEFAULT 0,
    total_spent INTEGER DEFAULT 0,
    first_order_date DATE,
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(company_id, email)
);

CREATE TABLE IF NOT EXISTS public.orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number TEXT NOT NULL,
    external_order_id TEXT,
    customer_id UUID REFERENCES public.customers(id) ON DELETE SET NULL,
    financial_status TEXT,
    fulfillment_status TEXT,
    currency TEXT,
    subtotal INTEGER,
    total_tax INTEGER,
    total_shipping INTEGER,
    total_discounts INTEGER,
    total_amount INTEGER,
    source_platform TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, external_order_id)
);

CREATE TABLE IF NOT EXISTS public.order_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id UUID REFERENCES public.product_variants(id) ON DELETE SET NULL,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_name TEXT,
    variant_title TEXT,
    sku TEXT,
    quantity INTEGER NOT NULL,
    price INTEGER NOT NULL CHECK (price >= 0),
    total_discount INTEGER CHECK (total_discount >= 0),
    tax_amount INTEGER CHECK (tax_amount >= 0),
    cost_at_time INTEGER CHECK (cost_at_time >= 0),
    external_line_item_id TEXT
);

CREATE TABLE IF NOT EXISTS public.suppliers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    default_lead_time_days INTEGER,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type TEXT NOT NULL, -- e.g., 'sale', 'purchase_order', 'reconciliation', 'manual_adjustment'
    quantity_change INTEGER NOT NULL,
    new_quantity INTEGER NOT NULL,
    related_id UUID, -- e.g., order_id, purchase_order_id
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id UUID PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days INTEGER DEFAULT 90,
    fast_moving_days INTEGER DEFAULT 30,
    overstock_multiplier NUMERIC DEFAULT 3,
    high_value_threshold INTEGER DEFAULT 1000,
    predictive_stock_days INTEGER DEFAULT 7,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ
);

-- Table to store conversation history for the chat feature
CREATE TABLE IF NOT EXISTS public.conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    last_accessed_at TIMESTAMPTZ DEFAULT now(),
    is_starred BOOLEAN DEFAULT false
);

-- Table to store individual messages within conversations
CREATE TABLE IF NOT EXISTS public.messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
    content TEXT NOT NULL,
    visualization JSONB,
    confidence REAL,
    assumptions TEXT[],
    component TEXT,
    "componentProps" JSONB,
    isError BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Table to store integration connection details
CREATE TABLE IF NOT EXISTS public.integrations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  platform TEXT NOT NULL, -- e.g., 'shopify', 'woocommerce'
  shop_domain TEXT,
  shop_name TEXT,
  is_active BOOLEAN DEFAULT true,
  last_sync_at TIMESTAMPTZ,
  sync_status TEXT, -- e.g., 'syncing', 'success', 'failed', 'idle'
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ,
  UNIQUE(company_id, platform)
);

-- Table to log webhook events to prevent replay attacks
CREATE TABLE IF NOT EXISTS public.webhook_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    integration_id UUID NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id TEXT NOT NULL,
    received_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(integration_id, webhook_id)
);

-- Table for Purchase Orders
CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id UUID REFERENCES public.suppliers(id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'draft', -- e.g., draft, ordered, partially_received, received, cancelled
    po_number TEXT NOT NULL,
    total_cost INTEGER, -- in cents
    expected_arrival_date DATE,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ
);

-- Table for Purchase Order Line Items
CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    purchase_order_id UUID NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    cost INTEGER NOT NULL CHECK (cost >= 0) -- cost per unit in cents
);

-- Table for User Feedback
CREATE TABLE IF NOT EXISTS public.user_feedback (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    subject_id TEXT NOT NULL,
    subject_type TEXT NOT NULL, -- e.g., 'ai_response', 'alert'
    feedback TEXT NOT NULL CHECK (feedback IN ('helpful', 'unhelpful')),
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Table for Audit Log
CREATE TABLE IF NOT EXISTS public.audit_log (
    id BIGSERIAL PRIMARY KEY,
    company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    details JSONB,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- =================================================================
--  DATABASE FUNCTIONS & TRIGGERS
-- =================================================================

-- Trigger function to update the 'updated_at' timestamp on any table.
DROP FUNCTION IF EXISTS public.update_updated_at_column();
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
   NEW.updated_at = now(); 
   RETURN NEW;
END;
$$ language 'plpgsql';

-- A generic function to apply the `update_updated_at_column` trigger to a table.
DROP FUNCTION IF EXISTS public.apply_updated_at_trigger(TEXT);
CREATE OR REPLACE FUNCTION public.apply_updated_at_trigger(table_name TEXT)
RETURNS void AS $$
BEGIN
  EXECUTE format('CREATE TRIGGER update_%s_updated_at BEFORE UPDATE ON public.%I FOR EACH ROW EXECUTE PROCEDURE public.update_updated_at_column()', table_name, table_name);
END;
$$ LANGUAGE plpgsql;

-- Apply the update timestamp trigger to relevant tables.
SELECT public.apply_updated_at_trigger('products');
SELECT public.apply_updated_at_trigger('product_variants');
SELECT public.apply_updated_at_trigger('orders');
SELECT public.apply_updated_at_trigger('integrations');
SELECT public.apply_updated_at_trigger('purchase_orders');

-- Function to handle recording a sale, updating inventory, and creating customer records.
-- This function is designed to be called from the sync services.
DROP FUNCTION IF EXISTS public.record_order_from_platform(uuid, jsonb, text);
CREATE OR REPLACE FUNCTION public.record_order_from_platform(
    p_company_id UUID,
    p_order_payload JSONB,
    p_platform TEXT
)
RETURNS void AS $$
DECLARE
    v_customer_id UUID;
    v_order_id UUID;
    v_customer_email TEXT;
    v_customer_name TEXT;
    item RECORD;
    v_variant_id UUID;
BEGIN
    -- Extract customer info
    IF p_platform = 'shopify' THEN
        v_customer_email := p_order_payload -> 'customer' ->> 'email';
        v_customer_name := COALESCE(
            p_order_payload -> 'customer' ->> 'first_name' || ' ' || p_order_payload -> 'customer' ->> 'last_name',
            v_customer_email
        );
    ELSIF p_platform = 'woocommerce' THEN
        v_customer_email := p_order_payload -> 'billing' ->> 'email';
        v_customer_name := COALESCE(
            p_order_payload -> 'billing' ->> 'first_name' || ' ' || p_order_payload -> 'billing' ->> 'last_name',
            v_customer_email
        );
    ELSE
        -- Default for Amazon FBA or others
        v_customer_email := p_order_payload -> 'customer' ->> 'email';
        v_customer_name := p_order_payload -> 'customer' ->> 'name';
    END IF;

    -- Upsert customer record
    IF v_customer_email IS NOT NULL THEN
        INSERT INTO public.customers (company_id, email, customer_name)
        VALUES (p_company_id, v_customer_email, v_customer_name)
        ON CONFLICT (company_id, email) DO UPDATE SET customer_name = v_customer_name
        RETURNING id INTO v_customer_id;
    END IF;

    -- Insert the order
    INSERT INTO public.orders (
        company_id, customer_id, external_order_id, order_number, 
        financial_status, fulfillment_status, total_amount, source_platform, created_at
    )
    SELECT
        p_company_id, v_customer_id,
        p_order_payload ->> 'id',
        COALESCE(p_order_payload ->> 'name', p_order_payload ->> 'number'),
        p_order_payload ->> 'financial_status',
        p_order_payload ->> 'fulfillment_status',
        (REPLACE(p_order_payload ->> 'total_price', '.', ''))::INTEGER,
        p_platform,
        (p_order_payload ->> 'created_at')::TIMESTAMPTZ
    ON CONFLICT (company_id, external_order_id) DO NOTHING
    RETURNING id INTO v_order_id;

    -- If the order was inserted (not a conflict), process line items
    IF v_order_id IS NOT NULL THEN
        FOR item IN SELECT * FROM jsonb_to_recordset(p_order_payload -> 'line_items') AS x(sku TEXT, quantity INTEGER, price TEXT, id TEXT)
        LOOP
            -- Find the corresponding variant_id
            SELECT id INTO v_variant_id FROM public.product_variants
            WHERE company_id = p_company_id AND sku = item.sku;

            -- Only proceed if the variant exists in our system
            IF v_variant_id IS NOT NULL THEN
                INSERT INTO public.order_line_items (
                    order_id, variant_id, company_id, sku, quantity, price
                )
                VALUES (
                    v_order_id, v_variant_id, p_company_id, item.sku, item.quantity, (REPLACE(item.price, '.', ''))::INTEGER
                );

                -- Decrement inventory and create ledger entry
                UPDATE public.product_variants
                SET inventory_quantity = inventory_quantity - item.quantity
                WHERE id = v_variant_id;

                INSERT INTO public.inventory_ledger (
                    company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes
                )
                SELECT
                    p_company_id, v_variant_id, 'sale', -item.quantity, pv.inventory_quantity, v_order_id, 'Order #' || (p_order_payload ->> 'name')
                FROM public.product_variants pv WHERE pv.id = v_variant_id;
            END IF;
        END LOOP;
        
        -- Update customer aggregates
        IF v_customer_id IS NOT NULL THEN
            UPDATE public.customers
            SET
                total_orders = total_orders + 1,
                total_spent = total_spent + (REPLACE(p_order_payload ->> 'total_price', '.', ''))::INTEGER,
                first_order_date = LEAST(first_order_date, (p_order_payload ->> 'created_at')::DATE)
            WHERE id = v_customer_id;
        END IF;

    END IF;
END;
$$ LANGUAGE plpgsql;


-- =================================================================
-- RPC FUNCTIONS FOR SECURE DATA ACCESS
-- =================================================================

-- Function to create multiple purchase orders from a set of suggestions.
-- This function is designed to be called from a server action.
DROP FUNCTION IF EXISTS public.create_purchase_orders_from_suggestions(uuid, uuid, jsonb);
CREATE OR REPLACE FUNCTION public.create_purchase_orders_from_suggestions(
    p_company_id UUID,
    p_user_id UUID,
    p_suggestions JSONB
)
RETURNS INTEGER AS $$
DECLARE
    suggestion JSONB;
    v_supplier_id UUID;
    v_po_id UUID;
    v_po_number TEXT;
    v_created_po_count INTEGER := 0;
BEGIN
    FOR suggestion IN SELECT * FROM jsonb_array_elements(p_suggestions)
    LOOP
        v_supplier_id := (suggestion ->> 'supplier_id')::UUID;

        -- Create a new PO if one doesn't exist for this supplier in this batch
        -- (This part is simplified; a real app might group all items for one PO)
        v_po_number := 'PO-' || to_char(now(), 'YYYYMMDD') || '-' || (
            SELECT COUNT(*) + 1 FROM public.purchase_orders WHERE company_id = p_company_id AND created_at::DATE = current_date
        );

        INSERT INTO public.purchase_orders (company_id, supplier_id, po_number, status)
        VALUES (p_company_id, v_supplier_id, v_po_number, 'draft')
        RETURNING id INTO v_po_id;

        -- Add line item to the new PO
        INSERT INTO public.purchase_order_line_items (purchase_order_id, variant_id, company_id, quantity, cost)
        VALUES (
            v_po_id,
            (suggestion ->> 'variant_id')::UUID,
            p_company_id,
            (suggestion ->> 'suggested_reorder_quantity')::INTEGER,
            (suggestion ->> 'unit_cost')::INTEGER
        );

        -- Create an audit log entry for the PO creation
        INSERT INTO public.audit_log (company_id, user_id, action, details)
        VALUES (
            p_company_id,
            p_user_id,
            'purchase_order_created',
            jsonb_build_object(
                'po_id', v_po_id,
                'po_number', v_po_number,
                'supplier_id', v_supplier_id,
                'item_count', 1
            )
        );

        v_created_po_count := v_created_po_count + 1;
    END LOOP;

    RETURN v_created_po_count;
END;
$$ LANGUAGE plpgsql;

-- =================================================================
--  VIEWS
-- =================================================================

-- A view to provide a unified list of inventory items with key details.
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT 
    pv.*,
    p.title as product_title,
    p.status as product_status,
    p.image_url as image_url,
    p.product_type,
    NULL::uuid as location_id, -- Placeholder for multi-location
    'Default' as location_name -- Placeholder for multi-location
FROM public.product_variants pv
JOIN public.products p ON pv.product_id = p.id;


-- =================================================================
--  INDEXES FOR PERFORMANCE
-- =================================================================

-- Create indexes on foreign keys and frequently queried columns to improve read performance.
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_variants_company_id ON public.product_variants(company_id);
CREATE INDEX IF NOT EXISTS idx_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON public.order_line_items(variant_id);
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers(company_id);
CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON public.suppliers(company_id);
CREATE INDEX IF NOT EXISTS idx_ledger_variant_id ON public.inventory_ledger(variant_id);
CREATE INDEX IF NOT EXISTS idx_conversations_user_id ON public.conversations(user_id);
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id ON public.messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_integrations_company_id ON public.integrations(company_id);

-- Create a GIN index on the 'tags' array column in the products table for fast array operations.
CREATE INDEX IF NOT EXISTS idx_products_tags_gin ON public.products USING GIN(tags);

-- Grant usage on the new schema and tables to the authenticated role
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO anon, authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated;
