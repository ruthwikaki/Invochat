-- Precise Migration Script to Update Existing Database
-- This script is designed to be run on an existing database to bring it up to the final schema.
-- It is idempotent and can be run multiple times without causing errors.

BEGIN;

-- 1. Drop the dependent view before altering the table
DROP VIEW IF EXISTS public.product_variants_with_details;

-- 2. Alter Tables: Add columns, drop obsolete ones, and modify constraints.

-- Table: product_variants
ALTER TABLE public.product_variants
  ALTER COLUMN sku SET NOT NULL,
  ALTER COLUMN title DROP NOT NULL, -- To allow for 'Default Title' from Shopify to be null
  ALTER COLUMN inventory_quantity SET NOT NULL,
  ALTER COLUMN inventory_quantity SET DEFAULT 0;

-- Drop obsolete columns from product_variants if they exist
DO $$
BEGIN
  IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'product_variants' AND column_name = 'weight') THEN
    ALTER TABLE public.product_variants DROP COLUMN weight;
  END IF;
  IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'product_variants' AND column_name = 'weight_unit') THEN
    ALTER TABLE public.product_variants DROP COLUMN weight_unit;
  END IF;
END $$;

-- Table: products
-- Drop obsolete FTS column if it exists
DO $$
BEGIN
  IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'products' AND column_name = 'fts_document') THEN
    ALTER TABLE public.products DROP COLUMN fts_document;
  END IF;
END $$;


-- Table: audit_log
-- Add missing user_id column if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'audit_log' AND column_name = 'user_id') THEN
    ALTER TABLE public.audit_log ADD COLUMN user_id UUID REFERENCES auth.users(id);
  END IF;
END $$;


-- 3. Create Indexes for Performance
-- Using "IF NOT EXISTS" makes this section idempotent.

CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_products_external_product_id ON public.products(external_product_id);
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
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers(company_id);
CREATE INDEX IF NOT EXISTS idx_customers_email ON public.customers(email);
CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON public.suppliers(company_id);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_company_id ON public.purchase_orders(company_id);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_supplier_id ON public.purchase_orders(supplier_id);
CREATE INDEX IF NOT EXISTS idx_purchase_order_line_items_po_id ON public.purchase_order_line_items(purchase_order_id);
CREATE INDEX IF NOT EXISTS idx_purchase_order_line_items_variant_id ON public.purchase_order_line_items(variant_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_company_id ON public.inventory_ledger(company_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id ON public.inventory_ledger(variant_id);
CREATE INDEX IF NOT EXISTS idx_integrations_company_id ON public.integrations(company_id);
CREATE INDEX IF NOT EXISTS idx_company_settings_company_id ON public.company_settings(company_id);
CREATE INDEX IF NOT EXISTS idx_users_company_id ON public.users(company_id);
CREATE INDEX IF NOT EXISTS idx_conversations_user_id ON public.conversations(user_id);
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id ON public.messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_company_id ON public.audit_log(company_id);


-- 4. Recreate the View
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
  pv.external_variant_id,
  pv.created_at,
  pv.updated_at,
  pv.location,
  p.title AS product_title,
  p.status AS product_status,
  p.image_url,
  p.product_type
FROM
  public.product_variants pv
  JOIN public.products p ON pv.product_id = p.id;


-- 5. Enable Row-Level Security (RLS) on all relevant tables
-- This is a critical security step.

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;


-- 6. Create RLS Policies
-- These policies ensure users can only access data for their own company.

DROP POLICY IF EXISTS "Allow all access to own company data" ON public.products;
CREATE POLICY "Allow all access to own company data" ON public.products
FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "Allow all access to own company data" ON public.product_variants;
CREATE POLICY "Allow all access to own company data" ON public.product_variants
FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "Allow all access to own company data" ON public.orders;
CREATE POLICY "Allow all access to own company data" ON public.orders
FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "Allow all access to own company data" ON public.order_line_items;
CREATE POLICY "Allow all access to own company data" ON public.order_line_items
FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "Allow all access to own company data" ON public.customers;
CREATE POLICY "Allow all access to own company data" ON public.customers
FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "Allow all access to own company data" ON public.suppliers;
CREATE POLICY "Allow all access to own company data" ON public.suppliers
FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "Allow all access to own company data" ON public.purchase_orders;
CREATE POLICY "Allow all access to own company data" ON public.purchase_orders
FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "Allow all access to own company data" ON public.purchase_order_line_items;
CREATE POLICY "Allow all access to own company data" ON public.purchase_order_line_items
FOR ALL USING (purchase_order_id IN (SELECT id FROM public.purchase_orders WHERE company_id = (SELECT company_id FROM public.users WHERE id = auth.uid())));

DROP POLICY IF EXISTS "Allow all access to own company data" ON public.inventory_ledger;
CREATE POLICY "Allow all access to own company data" ON public.inventory_ledger
FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "Allow all access to own company data" ON public.company_settings;
CREATE POLICY "Allow all access to own company data" ON public.company_settings
FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "Allow all access to own company data" ON public.integrations;
CREATE POLICY "Allow all access to own company data" ON public.integrations
FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "Allow all access to own user conversations" ON public.conversations;
CREATE POLICY "Allow all access to own user conversations" ON public.conversations
FOR ALL USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Allow all access to own user messages" ON public.messages;
CREATE POLICY "Allow all access to own user messages" ON public.messages
FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "Allow all access to own company audit logs" ON public.audit_log;
CREATE POLICY "Allow all access to own company audit logs" ON public.audit_log
FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));


COMMIT;
