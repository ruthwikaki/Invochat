-- InvoChat: Database Migration & Setup Script
-- This script is idempotent and can be safely run multiple times.

-- 1. EXTENSIONS
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 2. HELPER FUNCTIONS
-- Securely get the company_id from the JWT.
CREATE OR REPLACE FUNCTION get_my_company_id()
RETURNS uuid AS $$
  SELECT nullif(current_setting('request.jwt.claims', true)::json->>'company_id', '')::uuid;
$$ LANGUAGE sql STABLE;

-- Securely get the user's role from the JWT.
CREATE OR REPLACE FUNCTION get_my_role()
RETURNS text AS $$
  SELECT nullif(current_setting('request.jwt.claims', true)::json->>'role', '');
$$ LANGUAGE sql STABLE;

-- 3. DROP DEPENDENT OBJECTS
-- Drop dependent views to allow table alterations.
DROP MATERIALIZED VIEW IF EXISTS public.company_dashboard_metrics;

-- 4. DROP EXISTING POLICIES SAFELY
-- Using DO...EXCEPTION blocks to avoid errors if policies don't exist.
DO $$ BEGIN ALTER TABLE public.products DROP POLICY "Allow company members to read"; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN ALTER TABLE public.products DROP POLICY "Allow company members to manage"; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN ALTER TABLE public.product_variants DROP POLICY "Allow company members to read"; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN ALTER TABLE public.product_variants DROP POLICY "Allow company members to manage"; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN ALTER TABLE public.orders DROP POLICY "Allow company members to read"; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN ALTER TABLE public.order_line_items DROP POLICY "Allow company members to read"; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN ALTER TABLE public.customers DROP POLICY "Allow company members to manage"; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN ALTER TABLE public.refunds DROP POLICY "Allow company members to read"; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN ALTER TABLE public.suppliers DROP POLICY "Allow company members to manage"; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN ALTER TABLE public.purchase_orders DROP POLICY "Allow company members to manage"; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN ALTER TABLE public.inventory_ledger DROP POLICY "Allow company members to read"; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN ALTER TABLE public.integrations DROP POLICY "Allow company members to manage"; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN ALTER TABLE public.company_settings DROP POLICY "Allow company members to manage"; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN ALTER TABLE public.audit_log DROP POLICY "Allow admins to read audit logs for their company"; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN ALTER TABLE public.messages DROP POLICY "Allow user to manage messages in their conversations"; EXCEPTION WHEN undefined_object THEN END; $$;

-- 5. TABLE ALTERATIONS
-- Add idempotency key to purchase_orders for preventing duplicates.
ALTER TABLE public.purchase_orders ADD COLUMN IF NOT EXISTS idempotency_key UUID;

-- Standardize financial columns to use INTEGER for cents.
ALTER TABLE public.customers ALTER COLUMN total_spent TYPE INTEGER USING (total_spent * 100)::INTEGER;
ALTER TABLE public.refund_line_items ALTER COLUMN amount TYPE INTEGER USING (amount * 100)::INTEGER;
ALTER TABLE public.refunds ALTER COLUMN total_amount TYPE INTEGER USING (total_amount * 100)::INTEGER;
ALTER TABLE public.discounts ALTER COLUMN value TYPE INTEGER USING (value * 100)::INTEGER;
ALTER TABLE public.discounts ALTER COLUMN minimum_purchase TYPE INTEGER USING (minimum_purchase * 100)::INTEGER;

-- Add full-text search column to products.
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS fts_document TSVECTOR;

-- Enforce data integrity.
ALTER TABLE public.product_variants ALTER COLUMN sku SET NOT NULL;
ALTER TABLE public.product_variants ALTER COLUMN title DROP NOT NULL; -- Title can be null for default variants

-- 6. INDEXES & CONSTRAINTS
-- Drop constraints safely before creating them.
DO $$ BEGIN ALTER TABLE public.webhook_events DROP CONSTRAINT webhook_events_integration_id_webhook_id_key; EXCEPTION WHEN undefined_object THEN END; $$;
ALTER TABLE public.webhook_events ADD CONSTRAINT webhook_events_integration_id_webhook_id_key UNIQUE (integration_id, webhook_id);

-- Add indexes for performance.
CREATE INDEX IF NOT EXISTS products_company_id_fts_document_idx ON public.products USING GIN (company_id, fts_document);
CREATE INDEX IF NOT EXISTS product_variants_sku_company_id_idx ON public.product_variants (sku, company_id);
CREATE UNIQUE INDEX IF NOT EXISTS po_company_idempotency_idx ON public.purchase_orders (company_id, idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS orders_company_id_created_at_idx ON public.orders (company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS inventory_ledger_variant_id_idx ON public.inventory_ledger(variant_id);

-- 7. RECREATE VIEWS AND FUNCTIONS
-- Trigger function to update the full-text search vector.
CREATE OR REPLACE FUNCTION update_products_fts_document()
RETURNS TRIGGER AS $$
BEGIN
  NEW.fts_document := to_tsvector('english', NEW.title || ' ' || coalesce(NEW.description, '') || ' ' || coalesce(array_to_string(NEW.tags, ' '), ''));
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to execute the function on product changes.
DROP TRIGGER IF EXISTS trg_update_products_fts ON public.products;
CREATE TRIGGER trg_update_products_fts
BEFORE INSERT OR UPDATE ON public.products
FOR EACH ROW EXECUTE FUNCTION update_products_fts_document();

-- Materialized View for dashboard performance.
CREATE MATERIALIZED VIEW IF NOT EXISTS public.company_dashboard_metrics AS
SELECT
    c.id AS company_id,
    SUM(oli.price * oli.quantity) AS total_revenue,
    COUNT(DISTINCT o.id) AS total_orders,
    SUM(oli.quantity) AS total_items_sold
FROM
    companies c
JOIN
    orders o ON c.id = o.company_id
JOIN
    order_line_items oli ON o.id = oli.order_id
GROUP BY
    c.id;

-- 8. ROW-LEVEL SECURITY (RLS)
-- Enable RLS on all relevant tables.
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refunds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

-- Create policies using the secure helper functions.
CREATE POLICY "Allow company members to read" ON public.products FOR SELECT USING (company_id = get_my_company_id());
CREATE POLICY "Allow company members to manage" ON public.products FOR ALL USING (company_id = get_my_company_id() AND get_my_role() IN ('Owner', 'Admin'));

CREATE POLICY "Allow company members to read" ON public.product_variants FOR SELECT USING (company_id = get_my_company_id());
CREATE POLICY "Allow company members to manage" ON public.product_variants FOR ALL USING (company_id = get_my_company_id() AND get_my_role() IN ('Owner', 'Admin'));

CREATE POLICY "Allow company members to read" ON public.orders FOR SELECT USING (company_id = get_my_company_id());
CREATE POLICY "Allow company members to read" ON public.order_line_items FOR SELECT USING (company_id = get_my_company_id());
CREATE POLICY "Allow company members to manage" ON public.customers FOR ALL USING (company_id = get_my_company_id());
CREATE POLICY "Allow company members to read" ON public.refunds FOR SELECT USING (company_id = get_my_company_id());
CREATE POLICY "Allow company members to manage" ON public.suppliers FOR ALL USING (company_id = get_my_company_id());
CREATE POLICY "Allow company members to manage" ON public.purchase_orders FOR ALL USING (company_id = get_my_company_id());
CREATE POLICY "Allow company members to read" ON public.inventory_ledger FOR SELECT USING (company_id = get_my_company_id());
CREATE POLICY "Allow company members to manage" ON public.integrations FOR ALL USING (company_id = get_my_company_id());
CREATE POLICY "Allow company members to manage" ON public.company_settings FOR ALL USING (company_id = get_my_company_id());

CREATE POLICY "Allow user to manage their conversations" ON public.conversations FOR ALL
USING (auth.uid() = user_id);

CREATE POLICY "Allow user to manage messages in their conversations" ON public.messages
FOR ALL
USING (
  conversation_id IN (
    SELECT id FROM public.conversations WHERE user_id = auth.uid()
  )
);

CREATE POLICY "Allow admins to read audit logs for their company" ON public.audit_log
FOR SELECT
USING (
  company_id = get_my_company_id() AND get_my_role() IN ('Owner', 'Admin')
);

-- Final check to ensure the public schema is accessible.
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- Function to handle new user setup.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_company_name text;
BEGIN
  -- Extract company name from metadata, fallback to a default name.
  v_company_name := COALESCE(NEW.raw_user_meta_data->>'company_name', 'My Company');

  -- Create a new company for the new user.
  INSERT INTO public.companies (name)
  VALUES (v_company_name)
  RETURNING id INTO v_company_id;

  -- Create a corresponding user entry in the public.users table.
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (NEW.id, v_company_id, NEW.email, 'Owner');
  
  -- Create default settings for the new company.
  INSERT INTO public.company_settings (company_id)
  VALUES (v_company_id);

  -- Update the user's app_metadata with the new company_id and role.
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', v_company_id, 'role', 'Owner')
  WHERE id = NEW.id;
  
  RETURN NEW;
END;
$$;

-- Trigger to execute the function when a new user signs up.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  WHEN (NEW.raw_user_meta_data->>'company_name' IS NOT NULL)
  EXECUTE FUNCTION public.handle_new_user();

-- Log statement to confirm completion.
SELECT 'InvoChat Database Migration & Setup complete.';
