-- InvoChat Enterprise Database Schema
-- Version: 1.3
-- Description: This script refines the database schema for enterprise-grade security, performance, and data integrity.

-- Section 1: Extensions
-- Ensure required extensions are enabled.
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Section 2: Drop Existing Objects (Idempotency)
-- Drop views and functions in reverse order of dependency.
DROP VIEW IF EXISTS public.product_variants_with_details;

-- Drop RLS policies safely before altering tables.
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to read" ON public.products; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to manage" ON public.products; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to read" ON public.product_variants; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to manage" ON public.product_variants; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to read" ON public.suppliers; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to manage" ON public.suppliers; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to read" ON public.purchase_orders; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to manage" ON public.purchase_orders; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to read" ON public.purchase_order_line_items; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to manage" ON public.purchase_order_line_items; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to read" ON public.orders; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to manage" ON public.orders; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to read" ON public.order_line_items; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to manage" ON public.order_line_items; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to read" ON public.customers; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to manage" ON public.customers; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to read" ON public.company_settings; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to manage" ON public.company_settings; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to read" ON public.integrations; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to manage" ON public.integrations; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow user to read their own conversations" ON public.conversations; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow user to manage their own conversations" ON public.conversations; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow user to read messages in their conversations" ON public.messages; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow user to create messages in their conversations" ON public.messages; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to read" ON public.audit_log; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to read" ON public.inventory_ledger; EXCEPTION WHEN undefined_object THEN END; $$;


-- Section 3: Table Schema Refinements

-- Add idempotency key to purchase_orders to prevent duplicate submissions.
ALTER TABLE public.purchase_orders ADD COLUMN IF NOT EXISTS idempotency_key UUID;
CREATE INDEX IF NOT EXISTS po_idempotency_key_idx ON public.purchase_orders (company_id, idempotency_key);

-- Standardize financial columns to use INTEGER for cents to avoid floating point issues.
ALTER TABLE public.customers ALTER COLUMN total_spent TYPE INTEGER USING (total_spent * 100)::INTEGER;
ALTER TABLE public.refund_line_items ALTER COLUMN amount TYPE INTEGER USING (amount * 100)::INTEGER;
ALTER TABLE public.refunds ALTER COLUMN total_amount TYPE INTEGER USING (total_amount * 100)::INTEGER;
ALTER TABLE public.discounts ALTER COLUMN value TYPE INTEGER USING (value * 100)::INTEGER;
ALTER TABLE public.discounts ALTER COLUMN minimum_purchase TYPE INTEGER USING (minimum_purchase * 100)::INTEGER;

-- Add NOT NULL constraints for data integrity
ALTER TABLE public.product_variants ALTER COLUMN sku SET NOT NULL;
ALTER TABLE public.product_variants ALTER COLUMN title SET NOT NULL;

-- Add a tsvector column for full-text search capabilities.
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS fts_document tsvector;

-- Section 4: Functions & Triggers

-- Function to get company_id from the current user's claims
CREATE OR REPLACE FUNCTION public.get_my_company_id()
RETURNS UUID
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    (auth.jwt() -> 'app_metadata' ->> 'company_id')::uuid,
    (auth.jwt() -> 'user_metadata' ->> 'company_id')::uuid
  );
$$;

-- Trigger to update the fts_document column whenever product data changes.
CREATE OR REPLACE FUNCTION public.update_fts_document()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.fts_document := to_tsvector('english',
    COALESCE(NEW.title, '') || ' ' ||
    COALESCE(NEW.description, '') || ' ' ||
    COALESCE(NEW.product_type, '') || ' ' ||
    COALESCE(array_to_string(NEW.tags, ' '), '')
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_update_fts_document ON public.products;
CREATE TRIGGER trg_update_fts_document
BEFORE INSERT OR UPDATE ON public.products
FOR EACH ROW
EXECUTE FUNCTION public.update_fts_document();

-- Function to get historical sales for a single SKU
CREATE OR REPLACE FUNCTION public.get_historical_sales_for_sku(
    p_company_id UUID,
    p_sku TEXT
)
RETURNS TABLE (
    sale_date DATE,
    total_quantity BIGINT
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        o.created_at::DATE AS sale_date,
        SUM(oli.quantity)::BIGINT AS total_quantity
    FROM
        public.orders o
    JOIN
        public.order_line_items oli ON o.id = oli.order_id
    WHERE
        o.company_id = p_company_id
        AND oli.sku = p_sku
    GROUP BY
        o.created_at::DATE
    ORDER BY
        sale_date;
$$;


-- Section 5: Views

-- A comprehensive view combining product and variant details.
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.id,
    pv.product_id,
    pv.company_id,
    p.title AS product_title,
    p.status AS product_status,
    p.image_url,
    p.product_type,
    pv.sku,
    pv.title,
    pv.price,
    pv.cost,
    pv.inventory_quantity,
    pv.location,
    pv.created_at,
    pv.updated_at
FROM
    public.product_variants pv
JOIN
    public.products p ON pv.product_id = p.id;

-- Section 6: Indexes for Performance

CREATE INDEX IF NOT EXISTS idx_products_fts_document ON public.products USING GIN (fts_document);
CREATE INDEX IF NOT EXISTS idx_product_variants_sku ON public.product_variants (company_id, sku);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON public.orders (company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_order_line_items_sku ON public.order_line_items (company_id, sku);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id ON public.inventory_ledger (variant_id, created_at DESC);

-- Section 7: Row-Level Security (RLS) Policies

-- Enable RLS on all tables
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;

-- Define RLS policies
CREATE POLICY "Allow company members to read" ON public.products FOR SELECT USING (company_id = public.get_my_company_id());
CREATE POLICY "Allow company members to manage" ON public.products FOR ALL USING (company_id = public.get_my_company_id());

CREATE POLICY "Allow company members to read" ON public.product_variants FOR SELECT USING (company_id = public.get_my_company_id());
CREATE POLICY "Allow company members to manage" ON public.product_variants FOR ALL USING (company_id = public.get_my_company_id());

CREATE POLICY "Allow company members to read" ON public.suppliers FOR SELECT USING (company_id = public.get_my_company_id());
CREATE POLICY "Allow company members to manage" ON public.suppliers FOR ALL USING (company_id = public.get_my_company_id());

CREATE POLICY "Allow company members to read" ON public.purchase_orders FOR SELECT USING (company_id = public.get_my_company_id());
CREATE POLICY "Allow company members to manage" ON public.purchase_orders FOR ALL USING (company_id = public.get_my_company_id());

CREATE POLICY "Allow company members to read" ON public.purchase_order_line_items FOR SELECT USING (EXISTS (SELECT 1 FROM purchase_orders po WHERE po.id = purchase_order_id AND po.company_id = public.get_my_company_id()));
CREATE POLICY "Allow company members to manage" ON public.purchase_order_line_items FOR ALL USING (EXISTS (SELECT 1 FROM purchase_orders po WHERE po.id = purchase_order_id AND po.company_id = public.get_my_company_id()));

CREATE POLICY "Allow company members to read" ON public.orders FOR SELECT USING (company_id = public.get_my_company_id());
CREATE POLICY "Allow company members to manage" ON public.orders FOR ALL USING (company_id = public.get_my_company_id());

CREATE POLICY "Allow company members to read" ON public.order_line_items FOR SELECT USING (company_id = public.get_my_company_id());
CREATE POLICY "Allow company members to manage" ON public.order_line_items FOR ALL USING (company_id = public.get_my_company_id());

CREATE POLICY "Allow company members to read" ON public.customers FOR SELECT USING (company_id = public.get_my_company_id());
CREATE POLICY "Allow company members to manage" ON public.customers FOR ALL USING (company_id = public.get_my_company_id());

CREATE POLICY "Allow company members to read" ON public.company_settings FOR SELECT USING (company_id = public.get_my_company_id());
CREATE POLICY "Allow company members to manage" ON public.company_settings FOR ALL USING (company_id = public.get_my_company_id());

CREATE POLICY "Allow company members to read" ON public.integrations FOR SELECT USING (company_id = public.get_my_company_id());
CREATE POLICY "Allow company members to manage" ON public.integrations FOR ALL USING (company_id = public.get_my_company_id());

CREATE POLICY "Allow user to read their own conversations" ON public.conversations FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "Allow user to manage their own conversations" ON public.conversations FOR ALL USING (user_id = auth.uid());

CREATE POLICY "Allow user to read messages in their conversations" ON public.messages FOR SELECT USING (EXISTS (SELECT 1 FROM conversations c WHERE c.id = conversation_id AND c.user_id = auth.uid()));
CREATE POLICY "Allow user to create messages in their conversations" ON public.messages FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM conversations c WHERE c.id = conversation_id AND c.user_id = auth.uid()));

CREATE POLICY "Allow company members to read" ON public.audit_log FOR SELECT USING (company_id = public.get_my_company_id());
CREATE POLICY "Allow company members to read" ON public.inventory_ledger FOR SELECT USING (company_id = public.get_my_company_id());

-- Section 8: Grant Usage
-- Grant necessary permissions for authenticated users.
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT ON public.product_variants_with_details TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_company_id() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_historical_sales_for_sku(UUID, TEXT) TO authenticated;
