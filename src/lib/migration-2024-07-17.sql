-- This migration script is designed to be run on an existing database.
-- It is idempotent, meaning it can be run multiple times without causing errors.

-- Step 1: Drop the old, problematic trigger from the protected `auth` schema if it exists.
-- This is the root cause of many previous permission errors.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Step 2: Drop the old function if it exists to avoid dependency conflicts.
DROP FUNCTION IF EXISTS public.handle_new_user();

-- Step 3: Define helper functions for RLS policies.
-- These functions make it easier to get user information securely.

-- Gets the company_id from the currently authenticated user's JWT claims.
-- FIX: Wrapped the expression in parentheses to resolve the syntax error.
CREATE OR REPLACE FUNCTION public.get_company_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT (NULLIF(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid);
$$;

-- Gets the role of the currently authenticated user.
CREATE OR REPLACE FUNCTION public.get_user_role()
RETURNS text
LANGUAGE sql
STABLE
AS $$
  SELECT (NULLIF(current_setting('request.jwt.claims', true)::jsonb ->> 'role', '')::text);
$$;

-- Step 4: Create the public `users` table if it doesn't exist.
-- This table stores a public reference to users and their company association.
CREATE TABLE IF NOT EXISTS public.users (
    id uuid NOT NULL PRIMARY KEY REFERENCES auth.users(id),
    company_id uuid NOT NULL,
    email text,
    role text,
    deleted_at timestamptz,
    created_at timestamptz
);

-- Step 5: Define the function to handle new user creation.
-- This function is called by the application's signup action.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  company_name text := new.raw_app_meta_data ->> 'company_name';
  company_id_from_meta uuid := (new.raw_app_meta_data ->> 'company_id')::uuid;
  new_company_id uuid;
BEGIN
  -- If a company_id is provided in the metadata (for invites), use it.
  -- Otherwise, create a new company for the user.
  IF company_id_from_meta IS NOT NULL THEN
    new_company_id := company_id_from_meta;
  ELSE
    INSERT INTO public.companies (name) VALUES (company_name) RETURNING id INTO new_company_id;
  END IF;

  -- Insert the new user into our public `users` table.
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (new.id, new_company_id, new.email, 'Owner');
  
  -- Update the user's app_metadata in the auth schema with the new company_id and role.
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'role', 'Owner')
  WHERE id = new.id;
  
  RETURN new;
END;
$$;


-- Step 6: Create the trigger that calls the handle_new_user function.
-- This trigger runs *after* a new user is inserted into auth.users.
CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();


-- Step 7: Define a procedure to safely apply RLS policies.
-- This makes the script idempotent by dropping policies before creating them.
CREATE OR REPLACE PROCEDURE apply_rls_policies(t regclass)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Drop existing policies for the table
    EXECUTE 'DROP POLICY IF EXISTS "Allow all access to own company data" ON ' || t;
    EXECUTE 'DROP POLICY IF EXISTS "Allow read access to own company data" ON ' || t;
    EXECUTE 'DROP POLICY IF EXISTS "Allow insert access to own company data" ON ' || t;
    EXECUTE 'DROP POLICY IF EXISTS "Allow update access to own company data" ON ' || t;
    EXECUTE 'DROP POLICY IF EXISTS "Allow delete access to own company data" ON ' || t;
    EXECUTE 'DROP POLICY IF EXISTS "Enable read access for all authenticated users" ON ' || t;

    -- Apply policies based on table name
    IF t = 'public.companies'::regclass THEN
        EXECUTE 'CREATE POLICY "Allow all access to own company data" ON companies FOR ALL USING (id = public.get_company_id()) WITH CHECK (id = public.get_company_id())';
    ELSIF t = 'public.users'::regclass THEN
         EXECUTE 'CREATE POLICY "Allow all access to own company data" ON users FOR ALL USING (company_id = public.get_company_id()) WITH CHECK (company_id = public.get_company_id())';
    ELSE
        EXECUTE 'CREATE POLICY "Allow all access to own company data" ON ' || t || ' FOR ALL USING (company_id = public.get_company_id()) WITH CHECK (company_id = public.get_company_id())';
    END IF;
    
    -- Enable RLS for the table
    EXECUTE 'ALTER TABLE ' || t || ' ENABLE ROW LEVEL SECURITY';
EXCEPTION
    WHEN undefined_table THEN
        RAISE NOTICE 'Table % does not exist, skipping RLS policy application.', t;
END;
$$;


DO $$
DECLARE
    table_name text;
BEGIN
    -- List of tables to apply RLS to
    FOREACH table_name IN ARRAY ARRAY[
        'companies', 'users', 'company_settings', 'products', 'product_variants', 
        'suppliers', 'purchase_orders', 'purchase_order_line_items', 
        'orders', 'order_line_items', 'customers', 'integrations', 'conversations', 
        'messages', 'discounts', 'refunds', 'refund_line_items',
        'inventory_ledger', 'channel_fees', 'export_jobs', 'webhook_events', 'audit_log'
    ]
    LOOP
        CALL apply_rls_policies(table_name::regclass);
    END LOOP;
END $$;


-- Step 8: Update all views to use CREATE OR REPLACE VIEW for idempotency.
CREATE OR REPLACE VIEW public.product_variants_with_details AS
 SELECT pv.id,
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
   FROM (public.product_variants pv
     LEFT JOIN public.products p ON ((pv.product_id = p.id)));

-- Add any other CREATE OR REPLACE VIEW statements here as needed.

-- Step 9: Re-create indexes that might have been dropped or need updating.
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_company_sku ON public.product_variants(company_id, sku);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);


-- Add any column additions here, using IF NOT EXISTS syntax
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS role text;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS fts_document tsvector;


-- Final log message
SELECT 'Migration script completed successfully.' as status;
