
-- This migration script is designed to be run on an existing database
-- that may have been created with older, incorrect versions of the schema.
-- It is idempotent and can be run multiple times without causing errors.

-- Clean up the old, faulty trigger on the protected auth schema if it exists.
-- This is the root cause of many previous permission errors.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgname = 'on_auth_user_created' AND tgrelid = 'auth.users'::regclass
  ) THEN
    EXECUTE 'DROP TRIGGER on_auth_user_created ON auth.users';
  END IF;
END $$;


-- Drop and recreate the user-defined function to ensure it's up-to-date.
DROP FUNCTION IF EXISTS public.handle_new_user();
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Create a public user profile
  INSERT INTO public.users (id, email)
  VALUES (new.id, new.email);
  
  -- Create a company for the new user
  INSERT INTO public.companies (name, created_by)
  VALUES (new.raw_app_meta_data->>'company_name', new.id);

  RETURN new;
END;
$$;


-- A helper function to get the company_id from the JWT claims.
CREATE OR REPLACE FUNCTION public.get_company_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT (NULLIF(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', ''))::uuid;
$$;


-- Drop all RLS policies on a table before recreating them.
CREATE OR REPLACE PROCEDURE apply_rls_policies(table_name regclass)
LANGUAGE plpgsql
AS $$
DECLARE
  policy_record record;
BEGIN
  FOR policy_record IN
    SELECT policyname FROM pg_policies WHERE tablename = table_name::text AND schemaname = 'public'
  LOOP
    EXECUTE 'DROP POLICY IF EXISTS "' || policy_record.policyname || '" ON ' || table_name;
  END LOOP;

  -- Apply company-based policies
  IF table_name = 'public.companies'::regclass THEN
    EXECUTE 'CREATE POLICY "Allow all access to own company data" ON public.companies FOR ALL USING (id = public.get_company_id()) WITH CHECK (id = public.get_company_id())';
  ELSIF table_name = 'public.purchase_order_line_items'::regclass THEN
     EXECUTE 'CREATE POLICY "Allow all access based on parent PO" ON public.purchase_order_line_items FOR ALL USING (( SELECT company_id FROM purchase_orders WHERE id = purchase_order_id ) = public.get_company_id())';
  ELSE
    EXECUTE 'CREATE POLICY "Allow all access to own company data" ON ' || table_name || ' FOR ALL USING (company_id = public.get_company_id()) WITH CHECK (company_id = public.get_company_id())';
  END IF;
  
  EXECUTE 'ALTER TABLE ' || table_name || ' ENABLE ROW LEVEL SECURITY';
END;
$$;


DO $$
DECLARE
  t text;
BEGIN
  -- List of all tables that need RLS policies applied.
  -- This ensures we can re-run this script safely.
  FOREACH t IN ARRAY ARRAY[
    'companies', 'company_settings', 'users', 'products', 'product_variants', 
    'inventory_ledger', 'orders', 'order_line_items', 'customers', 
    'suppliers', 'purchase_orders', 'purchase_order_line_items', 
    'integrations', 'conversations', 'messages', 'audit_log', 'channel_fees'
  ]
  LOOP
    -- Check if the table exists before trying to apply policies
    IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = t) THEN
       CALL apply_rls_policies(t::regclass);
    END IF;
  END LOOP;
END;
$$;


-- Add the 'role' column to public.users if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'role'
  ) THEN
    ALTER TABLE public.users ADD COLUMN role TEXT DEFAULT 'member';
  END IF;
END $$;


-- Safely update the product_variants_with_details VIEW.
-- This is the direct fix for the "cannot change name of view column" error.
DROP VIEW IF EXISTS public.product_variants_with_details;

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
    public.products p ON pv.product_id = p.id
WHERE 
    pv.company_id = public.get_company_id();
