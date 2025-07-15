
-- This script is designed to be idempotent and can be run multiple times.

-- Drop dependent views first to allow table modifications.
DROP VIEW IF EXISTS public.product_variants_with_details;

-- Add company_id columns where they are missing.
ALTER TABLE public.product_variants
ADD COLUMN IF NOT EXISTS company_id UUID;

ALTER TABLE public.order_line_items
ADD COLUMN IF NOT EXISTS company_id UUID;

ALTER TABLE public.refund_line_items
ADD COLUMN IF NOT EXISTS company_id UUID;

ALTER TABLE public.audit_log
ADD COLUMN IF NOT EXISTS company_id UUID;

ALTER TABLE public.audit_log
ADD COLUMN IF NOT EXISTS user_id UUID;

-- Add foreign key constraints for company_id.
-- We add them with validation disabled initially to handle existing data, then validate.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'product_variants_company_id_fkey' AND conrelid = 'public.product_variants'::regclass
  ) THEN
    ALTER TABLE public.product_variants ADD CONSTRAINT product_variants_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE NOT VALID;
    ALTER TABLE public.product_variants VALIDATE CONSTRAINT product_variants_company_id_fkey;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'order_line_items_company_id_fkey' AND conrelid = 'public.order_line_items'::regclass
  ) THEN
    ALTER TABLE public.order_line_items ADD CONSTRAINT order_line_items_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE NOT VALID;
    ALTER TABLE public.order_line_items VALIDATE CONSTRAINT order_line_items_company_id_fkey;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'refund_line_items_company_id_fkey' AND conrelid = 'public.refund_line_items'::regclass
  ) THEN
    ALTER TABLE public.refund_line_items ADD CONSTRAINT refund_line_items_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE NOT VALID;
    ALTER TABLE public.refund_line_items VALIDATE CONSTRAINT refund_line_items_company_id_fkey;
  END IF;
  
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'audit_log_company_id_fkey' AND conrelid = 'public.audit_log'::regclass
  ) THEN
    ALTER TABLE public.audit_log ADD CONSTRAINT audit_log_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE NOT VALID;
    ALTER TABLE public.audit_log VALIDATE CONSTRAINT audit_log_company_id_fkey;
  END IF;

END $$;

-- Clean up obsolete columns from product_variants table.
ALTER TABLE public.product_variants
DROP COLUMN IF EXISTS weight,
DROP COLUMN IF EXISTS weight_unit;

-- Make SKU nullable as it might not exist for all variants initially.
ALTER TABLE public.product_variants
ALTER COLUMN sku DROP NOT NULL;

-- Make variant title nullable as it might be a default/simple product.
ALTER TABLE public.product_variants
ALTER COLUMN title DROP NOT NULL,
ALTER COLUMN title SET DEFAULT NULL;


-- Recreate the product_variants_with_details view with the correct structure.
CREATE OR REPLACE VIEW public.product_variants_with_details
AS
SELECT
  pv.id,
  pv.product_id,
  pv.company_id,
  p.title AS product_title,
  p.status AS product_status,
  p.product_type,
  p.image_url,
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
  pv.updated_at
FROM
  public.product_variants pv
  LEFT JOIN public.products p ON pv.product_id = p.id;


-- Helper function to get company_id from user's claims.
CREATE OR REPLACE FUNCTION public.get_my_company_id()
RETURNS UUID
LANGUAGE sql
STABLE
AS $$
  SELECT (auth.jwt()->'app_metadata'->>'company_id')::uuid
$$;

-- Enable Row-Level Security on all company-specific tables.
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_addresses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refunds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refund_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;


-- Drop existing policies before creating new ones to avoid conflicts.
DROP POLICY IF EXISTS "Allow ALL for service_role" ON public.products;
DROP POLICY IF EXISTS "Allow company members to read" ON public.products;

DROP POLICY IF EXISTS "Allow ALL for service_role" ON public.product_variants;
DROP POLICY IF EXISTS "Allow company members to read" ON public.product_variants;

DROP POLICY IF EXISTS "Allow ALL for service_role" ON public.orders;
DROP POLICY IF EXISTS "Allow company members to read" ON public.orders;

-- Create policies for all tables.
CREATE POLICY "Allow ALL for service_role" ON public.products FOR ALL TO service_role;
CREATE POLICY "Allow company members to read" ON public.products FOR SELECT USING (company_id = public.get_my_company_id());

CREATE POLICY "Allow ALL for service_role" ON public.product_variants FOR ALL TO service_role;
CREATE POLICY "Allow company members to read" ON public.product_variants FOR SELECT USING (company_id = public.get_my_company_id());

CREATE POLICY "Allow ALL for service_role" ON public.orders FOR ALL TO service_role;
CREATE POLICY "Allow company members to read" ON public.orders FOR SELECT USING (company_id = public.get_my_company_id());

CREATE POLICY "Allow ALL for service_role" ON public.order_line_items FOR ALL TO service_role;
CREATE POLICY "Allow company members to read" ON public.order_line_items FOR SELECT USING (company_id = public.get_my_company_id());

CREATE POLICY "Allow ALL for service_role" ON public.customers FOR ALL TO service_role;
CREATE POLICY "Allow company members to manage" ON public.customers FOR ALL USING (company_id = public.get_my_company_id());

CREATE POLICY "Allow ALL for service_role" ON public.customer_addresses FOR ALL TO service_role;

CREATE POLICY "Allow ALL for service_role" ON public.refunds FOR ALL TO service_role;
CREATE POLICY "Allow company members to read" ON public.refunds FOR SELECT USING (company_id = public.get_my_company_id());

CREATE POLICY "Allow ALL for service_role" ON public.refund_line_items FOR ALL TO service_role;

CREATE POLICY "Allow ALL for service_role" ON public.suppliers FOR ALL TO service_role;
CREATE POLICY "Allow company members to manage" ON public.suppliers FOR ALL USING (company_id = public.get_my_company_id());

CREATE POLICY "Allow ALL for service_role" ON public.purchase_orders FOR ALL TO service_role;
CREATE POLICY "Allow company members to manage" ON public.purchase_orders FOR ALL USING (company_id = public.get_my_company_id());

CREATE POLICY "Allow ALL for service_role" ON public.purchase_order_line_items FOR ALL TO service_role;

CREATE POLICY "Allow ALL for service_role" ON public.inventory_ledger FOR ALL TO service_role;
CREATE POLICY "Allow company members to read" ON public.inventory_ledger FOR SELECT USING (company_id = public.get_my_company_id());

CREATE POLICY "Allow ALL for service_role" ON public.integrations FOR ALL TO service_role;
CREATE POLICY "Allow company members to manage" ON public.integrations FOR ALL USING (company_id = public.get_my_company_id());

CREATE POLICY "Allow ALL for service_role" ON public.company_settings FOR ALL TO service_role;
CREATE POLICY "Allow company members to manage" ON public.company_settings FOR ALL USING (company_id = public.get_my_company_id());

CREATE POLICY "Allow ALL for service_role" ON public.channel_fees FOR ALL TO service_role;

CREATE POLICY "Allow ALL for service_role" ON public.export_jobs FOR ALL TO service_role;
CREATE POLICY "Allow users to manage their own export jobs" ON public.export_jobs FOR ALL USING (requested_by_user_id = auth.uid());

CREATE POLICY "Allow ALL for service_role" ON public.webhook_events FOR ALL TO service_role;

CREATE POLICY "Allow ALL for service_role" ON public.audit_log FOR ALL TO service_role;
CREATE POLICY "Allow admins to read audit logs for their company" ON public.audit_log FOR SELECT USING (company_id = public.get_my_company_id());

CREATE POLICY "Allow ALL for service_role" ON public.conversations FOR ALL TO service_role;
CREATE POLICY "Allow user to manage their own conversations" ON public.conversations FOR ALL USING (user_id = auth.uid());

CREATE POLICY "Allow ALL for service_role" ON public.messages FOR ALL TO service_role;
CREATE POLICY "Allow user to manage messages in their conversations" ON public.messages FOR ALL USING (company_id = public.get_my_company_id());

-- Add Indexes for Performance
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_company_id ON public.product_variants(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_sku ON public.product_variants(sku);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_orders_external_order_id ON public.orders(external_order_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON public.order_line_items(variant_id);
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers(company_id);
CREATE INDEX IF NOT EXISTS idx_customers_email ON public.customers(email);
CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON public.suppliers(company_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id ON public.inventory_ledger(variant_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_company_id_created_at ON public.inventory_ledger(company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_conversations_user_id ON public.conversations(user_id);


-- Create the secure full-text search function
CREATE OR REPLACE FUNCTION public.search_products(
    p_company_id UUID,
    p_search_term TEXT
)
RETURNS TABLE (
    id UUID,
    company_id UUID,
    title TEXT,
    description TEXT,
    product_type TEXT,
    image_url TEXT,
    relevance REAL
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.id,
        p.company_id,
        p.title,
        p.description,
        p.product_type,
        p.image_url,
        ts_rank_cd(p.fts_document, websearch_to_tsquery('english', p_search_term)) AS relevance
    FROM
        public.products AS p
    WHERE
        p.company_id = p_company_id
        AND p.fts_document @@ websearch_to_tsquery('english', p_search_term)
    ORDER BY
        relevance DESC;
END;
$$;


-- Add the full-text search document column
ALTER TABLE public.products
ADD COLUMN IF NOT EXISTS fts_document tsvector;

-- Create the index on that column
CREATE INDEX IF NOT EXISTS products_fts_document_idx ON public.products USING GIN (fts_document);

-- Create a trigger to automatically update the fts_document column
CREATE OR REPLACE FUNCTION update_products_fts_document()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.fts_document := to_tsvector('english',
        coalesce(NEW.title, '') || ' ' ||
        coalesce(NEW.description, '') || ' ' ||
        coalesce(NEW.product_type, '')
    );
    RETURN NEW;
END;
$$;

-- Drop trigger if it exists before creating it
DROP TRIGGER IF EXISTS tsvectorupdate ON public.products;

CREATE TRIGGER tsvectorupdate
BEFORE INSERT OR UPDATE ON public.products
FOR EACH ROW
EXECUTE FUNCTION update_products_fts_document();
