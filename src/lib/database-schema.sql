
--
-- ARVO FINAL DATABASE MIGRATION SCRIPT
--
-- This script updates the database to the final, secure, and performant schema.
-- It is designed to be idempotent (runnable multiple times) and to correct
-- previous migration errors by dropping and recreating dependent objects
-- in the correct order.
--

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- STEP 1: DROP ALL EXISTING RLS POLICIES & DEPENDENT VIEWS/FUNCTIONS
-- This is necessary to break dependencies before altering tables or dropping functions.

ALTER TABLE public.products DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.refunds DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.users DISABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist.
-- The explicit naming allows for targeted dropping without ambiguity.
DROP POLICY IF EXISTS "Allow company members to read" ON public.products;
DROP POLICY IF EXISTS "Allow company members to read" ON public.product_variants;
DROP POLICY IF EXISTS "Allow company members to read" ON public.orders;
DROP POLICY IF EXISTS "Allow company members to read" ON public.order_line_items;
DROP POLICY IF EXISTS "Allow company members to manage" ON public.customers;
DROP POLICY IF EXISTS "Allow company members to read" ON public.refunds;
DROP POLICY IF EXISTS "Allow company members to manage" ON public.suppliers;
DROP POLICY IF EXISTS "Allow company members to manage" ON public.purchase_orders;
DROP POLICY IF EXISTS "Allow company members to read" ON public.inventory_ledger;
DROP POLICY IF EXISTS "Allow company members to manage" ON public.integrations;
DROP POLICY IF EXISTS "Allow company members to manage" ON public.company_settings;
DROP POLICY IF EXISTS "Allow admins to read audit logs for their company" ON public.audit_log;
DROP POLICY IF EXISTS "Allow user to manage messages in their conversations" ON public.messages;
DROP POLICY IF EXISTS "Allow user to manage their conversations" ON public.conversations;
DROP POLICY IF EXISTS "Allow user to read their own user record" ON public.users;

-- Drop the view that depends on table columns we need to alter.
DROP VIEW IF EXISTS public.product_variants_with_details;

-- Drop the insecure function.
DROP FUNCTION IF EXISTS public.get_my_company_id();


-- STEP 2: ALTER TABLES TO ADD COLUMNS & CONSTRAINTS
-- Add columns if they don't exist, alter types, and set constraints.

ALTER TABLE public.products ADD COLUMN IF NOT EXISTS fts_document tsvector;

ALTER TABLE public.product_variants
  ADD COLUMN IF NOT EXISTS company_id UUID,
  ADD COLUMN IF NOT EXISTS location TEXT,
  ALTER COLUMN sku SET NOT NULL,
  DROP COLUMN IF EXISTS weight,
  DROP COLUMN IF EXISTS weight_unit;

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS company_id UUID;

ALTER TABLE public.order_line_items
  ADD COLUMN IF NOT EXISTS company_id UUID,
  ADD COLUMN IF NOT EXISTS cost_at_time INTEGER;

ALTER TABLE public.audit_log
  ADD COLUMN IF NOT EXISTS company_id UUID,
  ADD COLUMN IF NOT EXISTS user_id UUID;


-- STEP 3: CREATE PERFORMANCE INDEXES
-- Indexes are critical for query performance in a multi-tenant environment.

CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products (company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_sku ON public.product_variants (sku);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants (product_id);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders (company_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items (order_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON public.order_line_items (variant_id);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_company_id ON public.purchase_orders (company_id);
CREATE INDEX IF NOT EXISTS idx_purchase_order_line_items_po_id ON public.purchase_order_line_items (purchase_order_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id ON public.inventory_ledger (variant_id);
CREATE INDEX IF NOT EXISTS idx_users_email ON public.users (email);
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers (company_id);
CREATE INDEX IF NOT EXISTS idx_integrations_company_id ON public.integrations (company_id);

-- GIN index for full-text search on products
CREATE INDEX IF NOT EXISTS products_fts_document_idx ON public.products USING gin (fts_document);


-- STEP 4: CREATE SECURE HELPER FUNCTIONS & RECREATE VIEW
-- These functions are used by the new, secure RLS policies.

CREATE OR REPLACE FUNCTION public.get_company_id_for_user(user_id uuid)
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT company_id FROM public.users WHERE id = user_id;
$$;

-- Recreate the view now that tables are altered.
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.id,
    pv.product_id,
    pv.company_id,
    p.title as product_title,
    p.status as product_status,
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
    pv.external_variant_id,
    pv.location,
    pv.created_at,
    pv.updated_at,
    p.product_type
FROM
    public.product_variants pv
JOIN
    public.products p ON pv.product_id = p.id;


-- STEP 5: SETUP TRIGGERS
-- Create the function and trigger to handle new user sign-ups.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_company_id uuid;
  v_company_name text;
BEGIN
  -- Extract company_name from metadata, falling back to a default
  v_company_name := new.raw_app_meta_data->>'company_name';
  if v_company_name is null or v_company_name = '' then
    v_company_name := new.email || '''s Company';
  end if;

  -- Create a new company for the new user
  INSERT INTO public.companies (name)
  VALUES (v_company_name)
  RETURNING id INTO v_company_id;

  -- Create a corresponding user record in the public.users table
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (new.id, v_company_id, new.email, 'Owner');

  -- Update the user's app_metadata with the new company_id
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', v_company_id, 'role', 'Owner')
  WHERE id = new.id;

  RETURN new;
END;
$$;

-- Create the trigger on the auth.users table
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- STEP 6: RE-ENABLE ROW-LEVEL SECURITY AND CREATE SECURE POLICIES
-- Enable RLS on all tables and create policies using the new secure functions.

-- Products
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow company members to read" ON public.products FOR SELECT
  USING (company_id = public.get_company_id_for_user(auth.uid()));

-- Product Variants
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow company members to read" ON public.product_variants FOR SELECT
  USING (company_id = public.get_company_id_for_user(auth.uid()));

-- Orders & Line Items
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow company members to read" ON public.orders FOR SELECT
  USING (company_id = public.get_company_id_for_user(auth.uid()));

ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow company members to read" ON public.order_line_items FOR SELECT
  USING (company_id = public.get_company_id_for_user(auth.uid()));

-- Customers
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow company members to manage" ON public.customers FOR ALL
  USING (company_id = public.get_company_id_for_user(auth.uid())) WITH CHECK (company_id = public.get_company_id_for_user(auth.uid()));

-- Refunds
ALTER TABLE public.refunds ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow company members to read" ON public.refunds FOR SELECT
  USING (company_id = public.get_company_id_for_user(auth.uid()));

-- Suppliers
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow company members to manage" ON public.suppliers FOR ALL
  USING (company_id = public.get_company_id_for_user(auth.uid())) WITH CHECK (company_id = public.get_company_id_for_user(auth.uid()));

-- Purchase Orders
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow company members to manage" ON public.purchase_orders FOR ALL
  USING (company_id = public.get_company_id_for_user(auth.uid())) WITH CHECK (company_id = public.get_company_id_for_user(auth.uid()));

-- Inventory Ledger
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow company members to read" ON public.inventory_ledger FOR SELECT
  USING (company_id = public.get_company_id_for_user(auth.uid()));

-- Integrations
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow company members to manage" ON public.integrations FOR ALL
  USING (company_id = public.get_company_id_for_user(auth.uid())) WITH CHECK (company_id = public.get_company_id_for_user(auth.uid()));

-- Company Settings
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow company members to manage" ON public.company_settings FOR ALL
  USING (company_id = public.get_company_id_for_user(auth.uid())) WITH CHECK (company_id = public.get_company_id_for_user(auth.uid()));

-- Audit Log
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow admins to read audit logs for their company" ON public.audit_log FOR SELECT
  USING (company_id = public.get_company_id_for_user(auth.uid()));

-- Conversations & Messages
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow user to manage their conversations" ON public.conversations FOR ALL
  USING (user_id = auth.uid());

ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow user to manage messages in their conversations" ON public.messages FOR ALL
  USING (EXISTS (SELECT 1 FROM conversations WHERE id = messages.conversation_id AND user_id = auth.uid()));

-- Users table
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow user to read their own user record" ON public.users FOR SELECT
  USING (id = auth.uid());

-- FINALIZATION
-- Grant usage on the new function to authenticated users.
GRANT EXECUTE ON FUNCTION public.get_company_id_for_user(uuid) TO authenticated;
