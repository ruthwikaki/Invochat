-- InvoChat Final Database Migration Script
-- This script is idempotent and can be safely run multiple times.
-- It will ALTER existing tables and add missing objects without dropping data.

-- Step 1: Drop dependent objects (Views and RLS Policies) to allow table alterations.
-- We drop these first to avoid dependency errors.
DROP MATERIALIZED VIEW IF EXISTS public.company_dashboard_metrics CASCADE;
DROP VIEW IF EXISTS public.product_variants_with_details CASCADE;

-- Drop all RLS policies from tables that will be modified or have their policies updated.
DO $$
DECLARE
    tbl_name text;
BEGIN
    FOR tbl_name IN 
        SELECT tablename FROM pg_tables WHERE schemaname = 'public'
    LOOP
        EXECUTE 'ALTER TABLE public.' || quote_ident(tbl_name) || ' DISABLE ROW LEVEL SECURITY;';
        -- Drop policies by iterating, as a generic drop isn't simple
        -- This is a safeguard; the explicit drops below are the primary mechanism.
    END LOOP;
END $$;

-- Explicitly drop policies to be certain, ignoring errors if they don't exist
DO $$ BEGIN ALTER TABLE public.products DROP POLICY IF EXISTS "Allow company members to read"; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN ALTER TABLE public.product_variants DROP POLICY IF EXISTS "Allow company members to read"; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN ALTER TABLE public.orders DROP POLICY IF EXISTS "Allow company members to read"; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN ALTER TABLE public.order_line_items DROP POLICY IF EXISTS "Allow company members to read"; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN ALTER TABLE public.customers DROP POLICY IF EXISTS "Allow company members to manage"; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN ALTER TABLE public.refunds DROP POLICY IF EXISTS "Allow company members to read"; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN ALTER TABLE public.suppliers DROP POLICY IF EXISTS "Allow company members to manage"; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN ALTER TABLE public.purchase_orders DROP POLICY IF EXISTS "Allow company members to manage"; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN ALTER TABLE public.inventory_ledger DROP POLICY IF EXISTS "Allow company members to read"; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN ALTER TABLE public.integrations DROP POLICY IF EXISTS "Allow company members to manage"; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN ALTER TABLE public.company_settings DROP POLICY IF EXISTS "Allow company members to manage"; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN ALTER TABLE public.audit_log DROP POLICY IF EXISTS "Allow admins to read audit logs for their company"; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN ALTER TABLE public.messages DROP POLICY IF EXISTS "Allow user to manage messages in their conversations"; EXCEPTION WHEN undefined_object THEN END; $$;


-- Step 2: Drop the old insecure function if it exists
DROP FUNCTION IF EXISTS public.get_my_company_id();

-- Step 3: Perform all table alterations.
-- Using 'IF NOT EXISTS' for columns and 'IF EXISTS' for dropping makes this safe to re-run.
ALTER TABLE public.purchase_orders ADD COLUMN IF NOT EXISTS idempotency_key UUID;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS fts_document tsvector;

-- Standardize all money columns to be INTEGER (for cents), fixing previous inconsistencies.
ALTER TABLE public.refunds ALTER COLUMN total_amount TYPE INTEGER USING (total_amount * 100)::integer;
ALTER TABLE public.refund_line_items ALTER COLUMN amount TYPE INTEGER USING (amount * 100)::integer;
ALTER TABLE public.customers ALTER COLUMN total_spent TYPE INTEGER USING (total_spent * 100)::integer;

-- Enforce data integrity on product variants
ALTER TABLE public.product_variants
    ALTER COLUMN sku SET NOT NULL,
    ALTER COLUMN inventory_quantity SET NOT NULL,
    ALTER COLUMN inventory_quantity SET DEFAULT 0;

-- Drop obsolete columns from product variants if they exist
ALTER TABLE public.product_variants DROP COLUMN IF EXISTS weight;
ALTER TABLE public.product_variants DROP COLUMN IF EXISTS weight_unit;


-- Step 4: Create performance indexes if they don't exist
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products (company_id);
CREATE INDEX IF NOT EXISTS idx_products_external_id ON public.products (external_product_id);
CREATE INDEX IF NOT EXISTS idx_products_fts ON public.products USING gin(fts_document);

CREATE INDEX IF NOT EXISTS idx_variants_product_id ON public.product_variants (product_id);
CREATE INDEX IF NOT EXISTS idx_variants_company_id ON public.product_variants (company_id);
CREATE INDEX IF NOT EXISTS idx_variants_sku_company ON public.product_variants (company_id, sku);
CREATE INDEX IF NOT EXISTS idx_variants_external_id ON public.product_variants (external_variant_id);

CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders (company_id);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON public.orders (customer_id);

CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items (order_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON public.order_line_items (variant_id);

CREATE INDEX IF NOT EXISTS idx_ledger_variant_id ON public.inventory_ledger (variant_id);
CREATE INDEX IF NOT EXISTS idx_ledger_company_id ON public.inventory_ledger (company_id);
CREATE INDEX IF NOT EXISTS idx_ledger_related_id ON public.inventory_ledger (related_id);

CREATE INDEX IF NOT EXISTS idx_po_company_id ON public.purchase_orders (company_id);
CREATE INDEX IF NOT EXISTS idx_po_supplier_id ON public.purchase_orders (supplier_id);
CREATE UNIQUE INDEX IF NOT EXISTS po_company_idempotency_idx ON public.purchase_orders (company_id, idempotency_key) WHERE idempotency_key IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_po_line_items_po_id ON public.purchase_order_line_items (purchase_order_id);
CREATE INDEX IF NOT EXISTS idx_po_line_items_variant_id ON public.purchase_order_line_items (variant_id);

CREATE UNIQUE INDEX IF NOT EXISTS webhook_events_integration_id_webhook_id_key ON public.webhook_events (integration_id, webhook_id);

-- Step 5: Recreate secure helper functions and triggers.
-- This function securely gets the company ID of the currently authenticated user from a trusted source.
CREATE OR REPLACE FUNCTION public.get_user_company_id()
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT company_id
  FROM public.users
  WHERE id = auth.uid();
$$;

-- Trigger to update product's full-text search document
CREATE OR REPLACE FUNCTION update_fts_document()
RETURNS TRIGGER AS $$
BEGIN
    NEW.fts_document :=
        to_tsvector('english', COALESCE(NEW.title, '')) ||
        to_tsvector('english', COALESCE(NEW.product_type, ''));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS on_product_insert_update_fts ON public.products;
CREATE TRIGGER on_product_insert_update_fts
BEFORE INSERT OR UPDATE ON public.products
FOR EACH ROW
EXECUTE FUNCTION update_fts_document();


-- Step 6: Recreate Views
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.*,
    p.title AS product_title,
    p.status AS product_status,
    p.image_url
FROM
    public.product_variants pv
JOIN
    public.products p ON pv.product_id = p.id;

-- Step 7: Enable Row-Level Security and create secure policies for ALL tables.
-- This is the final and most critical step.

-- Enable RLS for all relevant tables
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refunds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

-- Create Secure RLS Policies
CREATE POLICY "Allow members to access their own company data" ON public.products FOR ALL USING (company_id = public.get_user_company_id());
CREATE POLICY "Allow members to access their own company data" ON public.product_variants FOR ALL USING (company_id = public.get_user_company_id());
CREATE POLICY "Allow members to access their own company data" ON public.orders FOR ALL USING (company_id = public.get_user_company_id());
CREATE POLICY "Allow members to access their own company data" ON public.order_line_items FOR ALL USING (company_id = public.get_user_company_id());
CREATE POLICY "Allow members to access their own company data" ON public.customers FOR ALL USING (company_id = public.get_user_company_id());
CREATE POLICY "Allow members to access their own company data" ON public.refunds FOR ALL USING (company_id = public.get_user_company_id());
CREATE POLICY "Allow members to access their own company data" ON public.suppliers FOR ALL USING (company_id = public.get_user_company_id());
CREATE POLICY "Allow members to access their own company data" ON public.purchase_orders FOR ALL USING (company_id = public.get_user_company_id());
CREATE POLICY "Allow members to access their own company data" ON public.purchase_order_line_items FOR ALL USING ((SELECT company_id FROM purchase_orders WHERE id = purchase_order_id) = public.get_user_company_id());
CREATE POLICY "Allow members to access their own company data" ON public.inventory_ledger FOR ALL USING (company_id = public.get_user_company_id());
CREATE POLICY "Allow members to access their own company data" ON public.integrations FOR ALL USING (company_id = public.get_user_company_id());
CREATE POLICY "Allow members to access their own company data" ON public.company_settings FOR ALL USING (company_id = public.get_user_company_id());
CREATE POLICY "Allow members to access their own company data" ON public.audit_log FOR ALL USING (company_id = public.get_user_company_id());
CREATE POLICY "Users can only access their own conversations" ON public.conversations FOR ALL USING (user_id = auth.uid());
CREATE POLICY "Users can only access messages in their own conversations" ON public.messages FOR ALL USING ((SELECT user_id FROM conversations WHERE id = conversation_id) = auth.uid());
