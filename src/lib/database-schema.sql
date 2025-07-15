
-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Drop dependent views and functions first
DROP VIEW IF EXISTS public.product_variants_with_details;
DROP FUNCTION IF EXISTS public.get_my_company_id();

-- =================================================================
-- 1. Table Alterations & Additions
-- Add columns, change types, and add constraints first.
-- =================================================================

-- Add company_id and user_id to audit_log
ALTER TABLE public.audit_log ADD COLUMN IF NOT EXISTS company_id UUID;
ALTER TABLE public.audit_log ADD COLUMN IF NOT EXISTS user_id UUID;

-- Add idempotency key to purchase_orders for safe retries
ALTER TABLE public.purchase_orders ADD COLUMN IF NOT EXISTS idempotency_key UUID;

-- Add tsvector for full-text search on products
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS fts_document tsvector;

-- Standardize monetary values to integers (cents)
ALTER TABLE public.product_variants ALTER COLUMN price TYPE integer USING (price * 100)::integer;
ALTER TABLE public.product_variants ALTER COLUMN cost TYPE integer USING (cost * 100)::integer;
ALTER TABLE public.product_variants ALTER COLUMN compare_at_price TYPE integer USING (compare_at_price * 100)::integer;
ALTER TABLE public.order_line_items ALTER COLUMN price TYPE integer USING (price * 100)::integer;
ALTER TABLE public.order_line_items ALTER COLUMN total_discount TYPE integer USING (total_discount * 100)::integer;
ALTER TABLE public.order_line_items ALTER COLUMN tax_amount TYPE integer USING (tax_amount * 100)::integer;
ALTER TABLE public.orders ALTER COLUMN subtotal TYPE integer USING (subtotal * 100)::integer;
ALTER TABLE public.orders ALTER COLUMN total_tax TYPE integer USING (total_tax * 100)::integer;
ALTER TABLE public.orders ALTER COLUMN total_shipping TYPE integer USING (total_shipping * 100)::integer;
ALTER TABLE public.orders ALTER COLUMN total_discounts TYPE integer USING (total_discounts * 100)::integer;
ALTER TABLE public.orders ALTER COLUMN total_amount TYPE integer USING (total_amount * 100)::integer;
ALTER TABLE public.customers ALTER COLUMN total_spent TYPE integer USING (total_spent * 100)::integer;

-- Remove obsolete columns from product_variants
ALTER TABLE public.product_variants DROP COLUMN IF EXISTS weight;
ALTER TABLE public.product_variants DROP COLUMN IF EXISTS weight_unit;

-- Enforce NOT NULL constraints for data integrity
ALTER TABLE public.product_variants ALTER COLUMN sku SET NOT NULL;
ALTER TABLE public.product_variants ALTER COLUMN inventory_quantity SET NOT NULL;

-- =================================================================
-- 2. Index Creation
-- Create indexes after all columns are in place.
-- =================================================================

-- Add missing performance indexes
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON public.order_line_items(variant_id);
CREATE INDEX IF NOT EXISTS idx_purchase_order_line_items_purchase_order_id ON public.purchase_order_line_items(purchase_order_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id ON public.inventory_ledger(variant_id);
CREATE INDEX IF NOT EXISTS idx_customers_email ON public.customers(email);
CREATE INDEX IF NOT EXISTS idx_product_variants_sku_company ON public.product_variants(sku, company_id);

-- Index for full-text search
CREATE INDEX IF NOT EXISTS products_fts_document_idx ON public.products USING GIN (fts_document);

-- Index for idempotency on purchase orders
CREATE UNIQUE INDEX IF NOT EXISTS po_company_idempotency_idx ON public.purchase_orders (company_id, idempotency_key) WHERE idempotency_key IS NOT NULL;

-- Index for webhook deduplication
CREATE UNIQUE INDEX IF NOT EXISTS webhook_events_unique_idx ON public.webhook_events (integration_id, webhook_id);

-- =================================================================
-- 3. Functions & Triggers
-- Define functions needed by views, policies, or triggers.
-- =================================================================

-- Function to get company_id from a user's JWT claims securely
CREATE OR REPLACE FUNCTION public.get_company_id_from_user()
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'app_metadata', '')::jsonb ->> 'company_id' INTO company_id;
  IF company_id IS NULL THEN
    -- Fallback for user_metadata if app_metadata is not present
    SELECT nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'user_metadata', '')::jsonb ->> 'company_id' INTO company_id;
  END IF;
  RETURN company_id::uuid;
$$;

-- Function to update the fts_document column on product changes
CREATE OR REPLACE FUNCTION public.update_fts_document()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.fts_document := to_tsvector('english',
        coalesce(NEW.title, '') || ' ' ||
        coalesce(NEW.description, '') || ' ' ||
        coalesce(NEW.product_type, '') || ' ' ||
        coalesce(array_to_string(NEW.tags, ' '), '')
    );
    RETURN NEW;
END;
$$;

-- Trigger to automatically update the fts_document
CREATE OR REPLACE TRIGGER update_products_fts_trigger
BEFORE INSERT OR UPDATE ON public.products
FOR EACH ROW
EXECUTE FUNCTION public.update_fts_document();


-- Function to handle new user signup and company creation
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  company_id uuid;
BEGIN
  -- Create a new company for the user
  INSERT INTO public.companies (name)
  VALUES (new.raw_app_meta_data->>'company_name')
  RETURNING id INTO company_id;

  -- Create a corresponding entry in the public.users table
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (new.id, company_id, new.email, 'Owner');

  -- Update the user's app_metadata with the new company_id
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id, 'role', 'Owner')
  WHERE id = new.id;
  
  RETURN new;
END;
$$;

-- Trigger for new user creation
CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  WHEN (new.raw_app_meta_data->>'company_name' IS NOT NULL)
  EXECUTE FUNCTION public.handle_new_user();


-- =================================================================
-- 4. Views
-- Recreate views after tables are modified.
-- =================================================================

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

-- =================================================================
-- 5. Row Level Security (RLS)
-- Drop old policies, enable RLS, and create new, secure policies.
-- =================================================================

-- Drop existing policies that might depend on the old function
DO $$
DECLARE
    policy_record RECORD;
BEGIN
    FOR policy_record IN SELECT policyname, tablename FROM pg_policies WHERE schemaname = 'public'
    LOOP
        EXECUTE 'DROP POLICY IF EXISTS "' || policy_record.policyname || '" ON public."' || policy_record.tablename || '";';
    END LOOP;
END;
$$;


-- A function to get the current user's company ID from the users table.
CREATE OR REPLACE FUNCTION get_current_user_company_id()
RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT company_id
  FROM public.users
  WHERE id = auth.uid();
$$;

-- Enable RLS and create new policies for each table
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only manage their own company's products" ON public.products
FOR ALL USING (company_id = get_current_user_company_id());

ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only manage their own company's variants" ON public.product_variants
FOR ALL USING (company_id = get_current_user_company_id());

ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only manage their own company's orders" ON public.orders
FOR ALL USING (company_id = get_current_user_company_id());

ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only manage their own company's order line items" ON public.order_line_items
FOR ALL USING (company_id = get_current_user_company_id());

ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only manage their own company's customers" ON public.customers
FOR ALL USING (company_id = get_current_user_company_id());

ALTER TABLE public.refunds ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only manage their own company's refunds" ON public.refunds
FOR ALL USING (company_id = get_current_user_company_id());

ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only manage their own company's suppliers" ON public.suppliers
FOR ALL USING (company_id = get_current_user_company_id());

ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only manage their own company's purchase orders" ON public.purchase_orders
FOR ALL USING (company_id = get_current_user_company_id());

ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only manage their own company's PO line items" ON public.purchase_order_line_items
FOR ALL USING (purchase_order_id IN (SELECT id FROM purchase_orders WHERE company_id = get_current_user_company_id()));

ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only manage their own company's inventory ledger" ON public.inventory_ledger
FOR ALL USING (company_id = get_current_user_company_id());

ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only manage their own company's integrations" ON public.integrations
FOR ALL USING (company_id = get_current_user_company_id());

ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only manage their own company's settings" ON public.company_settings
FOR ALL USING (company_id = get_current_user_company_id());

ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins can read audit logs for their own company" ON public.audit_log
FOR SELECT USING (company_id = get_current_user_company_id());

ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage messages in their own company's conversations" ON public.messages
FOR ALL USING (company_id = get_current_user_company_id());

ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage their own conversations" ON public.conversations
FOR ALL USING (user_id = auth.uid());
