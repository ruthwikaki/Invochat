
-- ### InvoChat Database Schema Migration ###
-- This script is designed to be idempotent and can be safely run multiple times.
-- It will alter the existing database to match the final, secure schema.

-- ====================================================================
-- 1. DROP DEPENDENT OBJECTS
-- Drop views and policies that depend on tables/columns we need to change.
-- ====================================================================

-- Drop materialized views first as they depend on tables.
DROP MATERIALIZED VIEW IF EXISTS public.company_dashboard_metrics;
DROP MATERIALIZED VIEW IF EXISTS public.inventory_sales_velocity;
DROP VIEW IF EXISTS public.product_variants_with_details;
DROP VIEW IF EXISTS public.dead_stock_view;

-- Drop all RLS policies using a safe, idempotent method.
DO $$ BEGIN DROP POLICY "Allow company members to read" ON public.products; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY "Allow company members to read" ON public.product_variants; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY "Allow company members to read" ON public.orders; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY "Allow company members to read" ON public.order_line_items; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY "Allow company members to manage" ON public.customers; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY "Allow company members to read" ON public.refunds; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY "Allow company members to manage" ON public.suppliers; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY "Allow company members to manage" ON public.purchase_orders; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY "Allow company members to read" ON public.inventory_ledger; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY "Allow company members to manage" ON public.integrations; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY "Allow company members to manage" ON public.company_settings; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY "Allow admins to read audit logs for their company" ON public.audit_log; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY "Allow user to manage messages in their conversations" ON public.messages; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY "Users can only read their own conversations" ON public.conversations; EXCEPTION WHEN undefined_object THEN END; $$;

-- Drop the insecure function AFTER policies are dropped.
DROP FUNCTION IF EXISTS get_my_company_id();


-- ====================================================================
-- 2. ALTER TABLES
-- Add new columns, change data types, and enforce constraints.
-- ====================================================================

-- Add idempotency key to purchase orders for safe retries.
ALTER TABLE public.purchase_orders ADD COLUMN IF NOT EXISTS idempotency_key UUID;

-- Standardize financial columns to use INTEGER for cents.
ALTER TABLE public.customers ALTER COLUMN total_spent TYPE INTEGER USING (total_spent::integer);
ALTER TABLE public.refunds ALTER COLUMN total_amount TYPE INTEGER USING (total_amount::integer);
ALTER TABLE public.refund_line_items ALTER COLUMN amount TYPE INTEGER USING (amount::integer);
ALTER TABLE public.discounts ALTER COLUMN value TYPE INTEGER USING (value::integer);
ALTER TABLE public.discounts ALTER COLUMN minimum_purchase TYPE INTEGER USING (minimum_purchase::integer);
ALTER TABLE public.channel_fees ALTER COLUMN fixed_fee TYPE INTEGER USING (fixed_fee::integer);

-- Enforce data integrity on product variants
ALTER TABLE public.product_variants ALTER COLUMN sku SET NOT NULL;
ALTER TABLE public.product_variants ALTER COLUMN title SET DEFAULT 'Default';

-- Add full-text search vector column
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS fts_document tsvector;


-- ====================================================================
-- 3. CREATE INDEXES AND CONSTRAINTS
-- Improve performance and data integrity.
-- ====================================================================

-- Drop potentially existing indexes/constraints before creating them
DROP INDEX IF EXISTS po_company_idempotency_idx;
DROP INDEX IF EXISTS idx_order_line_items_order_id;
DROP INDEX IF EXISTS idx_purchase_order_line_items_po_id;
DROP INDEX IF EXISTS idx_inventory_ledger_variant_id;
ALTER TABLE public.webhook_events DROP CONSTRAINT IF EXISTS webhook_events_integration_id_webhook_id_key;

-- Create missing performance indexes
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_purchase_order_line_items_po_id ON public.purchase_order_line_items(purchase_order_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id ON public.inventory_ledger(variant_id);
CREATE INDEX IF NOT EXISTS products_fts_document_idx ON public.products USING GIN (fts_document);

-- Add unique constraint for webhook deduplication
ALTER TABLE public.webhook_events ADD CONSTRAINT webhook_events_integration_id_webhook_id_key UNIQUE (integration_id, webhook_id);

-- Create a partial index for idempotency keys
CREATE UNIQUE INDEX IF NOT EXISTS po_company_idempotency_idx ON public.purchase_orders (company_id, idempotency_key) WHERE idempotency_key IS NOT NULL;


-- ====================================================================
-- 4. RECREATE FUNCTIONS AND VIEWS
-- Create secure helper functions and recreate the views.
-- ====================================================================

-- Securely get the user's company ID from the users table.
CREATE OR REPLACE FUNCTION get_user_company_id(p_user_id UUID)
RETURNS UUID AS $$
DECLARE
    v_company_id UUID;
BEGIN
    SELECT company_id INTO v_company_id FROM public.users WHERE id = p_user_id;
    RETURN v_company_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Function to link a new user to a company upon signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    v_company_id UUID;
BEGIN
    -- Create a new company for the new user
    INSERT INTO public.companies (name)
    VALUES (new.raw_app_meta_data->>'company_name')
    RETURNING id INTO v_company_id;

    -- Insert a corresponding entry into the public users table
    INSERT INTO public.users (id, company_id, email, role)
    VALUES (new.id, v_company_id, new.email, 'Owner');
    
    -- Insert default settings for the new company
    INSERT INTO public.company_settings(company_id)
    VALUES (v_company_id);

    -- Update the user's app_metadata with the new company_id
    UPDATE auth.users
    SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', v_company_id, 'role', 'Owner')
    WHERE id = new.id;
    
    RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to execute the handle_new_user function
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- Function to update the full-text search document for a product
CREATE OR REPLACE FUNCTION public.update_product_fts_document()
RETURNS TRIGGER AS $$
BEGIN
    NEW.fts_document := to_tsvector('english',
        COALESCE(NEW.title, '') || ' ' ||
        COALESCE(NEW.product_type, '') || ' ' ||
        COALESCE(array_to_string(NEW.tags, ' '), '')
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tsvectorupdate BEFORE INSERT OR UPDATE ON public.products;
CREATE TRIGGER tsvectorupdate
BEFORE INSERT OR UPDATE ON public.products
FOR EACH ROW EXECUTE FUNCTION public.update_product_fts_document();


-- Recreate the main view for inventory
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


-- ====================================================================
-- 5. RE-APPLY ROW-LEVEL SECURITY (RLS) POLICIES
-- ====================================================================

-- Helper function to check user role within their company
CREATE OR REPLACE FUNCTION is_user_in_company(p_company_id UUID, p_user_id UUID)
RETURNS BOOLEAN AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.users WHERE id = p_user_id AND company_id = p_company_id
    );
$$ LANGUAGE sql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION get_user_role(p_user_id UUID)
RETURNS TEXT AS $$
    SELECT role FROM public.users WHERE id = p_user_id;
$$ LANGUAGE sql SECURITY DEFINER;

-- Products Table
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow company members to read" ON public.products FOR SELECT
USING (is_user_in_company(company_id, auth.uid()));

-- Product Variants Table
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow company members to read" ON public.product_variants FOR SELECT
USING (is_user_in_company(company_id, auth.uid()));

-- Orders & Order Line Items
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow company members to read" ON public.orders FOR SELECT
USING (is_user_in_company(company_id, auth.uid()));

ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow company members to read" ON public.order_line_items FOR SELECT
USING (is_user_in_company(company_id, auth.uid()));

-- Customers
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow company members to manage" ON public.customers FOR ALL
USING (is_user_in_company(company_id, auth.uid()));

-- Refunds
ALTER TABLE public.refunds ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow company members to read" ON public.refunds FOR SELECT
USING (is_user_in_company(company_id, auth.uid()));

-- Suppliers
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow company members to manage" ON public.suppliers FOR ALL
USING (is_user_in_company(company_id, auth.uid()));

-- Purchase Orders
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow company members to manage" ON public.purchase_orders FOR ALL
USING (is_user_in_company(company_id, auth.uid()));

-- Inventory Ledger
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow company members to read" ON public.inventory_ledger FOR SELECT
USING (is_user_in_company(company_id, auth.uid()));

-- Integrations
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow company members to manage" ON public.integrations FOR ALL
USING (is_user_in_company(company_id, auth.uid()));

-- Company Settings
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow company members to manage" ON public.company_settings FOR ALL
USING (is_user_in_company(company_id, auth.uid()));

-- Audit Log
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow admins to read audit logs for their company" ON public.audit_log FOR SELECT
USING (is_user_in_company(company_id, auth.uid()) AND get_user_role(auth.uid()) = 'Admin');

-- Chat: Conversations & Messages
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only read their own conversations" ON public.conversations FOR SELECT
USING (user_id = auth.uid());

ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow user to manage messages in their conversations" ON public.messages FOR ALL
USING (
    EXISTS (
        SELECT 1 FROM conversations
        WHERE id = messages.conversation_id AND user_id = auth.uid()
    )
);
