-- ARVO DATABASE MIGRATION SCRIPT
-- This script updates an existing ARVO database to the latest schema.
-- It is designed to be idempotent and safe to run multiple times.

BEGIN;

-- Helper function to drop all policies on a table
CREATE OR REPLACE PROCEDURE drop_all_policies_on_table(table_name text)
LANGUAGE plpgsql
AS $$
DECLARE
    r record;
BEGIN
    FOR r IN (SELECT policyname FROM pg_policies WHERE tablename = table_name AND schemaname = 'public') LOOP
        EXECUTE 'DROP POLICY IF EXISTS ' || quote_ident(r.policyname) || ' ON public.' || quote_ident(table_name);
    END LOOP;
END;
$$;


-- ====================================================================
--  STEP 1: DROP DEPENDENT OBJECTS
--  Drop all RLS policies and views that depend on the function we need to modify.
-- ====================================================================

-- Drop all existing RLS policies on all tables
DO $$
DECLARE
    table_rec record;
BEGIN
    FOR table_rec IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public') LOOP
        CALL drop_all_policies_on_table(table_rec.tablename);
    END LOOP;
END;
$$;

-- Drop dependent views
DROP VIEW IF EXISTS public.product_variants_with_details;

-- ====================================================================
--  STEP 2: ADD/MODIFY COLUMNS
-- ====================================================================

-- Add company_id to purchase_order_line_items if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM information_schema.columns WHERE table_name='purchase_order_line_items' AND column_name='company_id') THEN
        ALTER TABLE public.purchase_order_line_items ADD COLUMN company_id uuid;
    END IF;
END;
$$;

-- Make variant/product links non-nullable on order_line_items
ALTER TABLE public.order_line_items ALTER COLUMN variant_id SET NOT NULL;
ALTER TABLE public.order_line_items ALTER COLUMN product_id SET NOT NULL;

-- Remove redundant 'status' column from orders
DO $$
BEGIN
    IF EXISTS (SELECT FROM information_schema.columns WHERE table_name='orders' AND column_name='status') THEN
        ALTER TABLE public.orders DROP COLUMN status;
    END IF;
END;
$$;


-- ====================================================================
--  STEP 3: DROP & RECREATE FUNCTIONS
-- ====================================================================

-- Drop the old version of the function
DROP FUNCTION IF EXISTS public.get_company_id();

-- Recreate the get_company_id() helper function with correct casting
CREATE OR REPLACE FUNCTION public.get_company_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT (NULLIF(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', ''))::uuid;
$$;

-- Recreate handle_new_user function
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  company_id_from_meta uuid;
  company_name_from_meta text;
  new_company_id uuid;
  user_email text;
BEGIN
  -- Get user email
  user_email := new.email;

  -- First, check if the user is being created via an invitation.
  company_id_from_meta := (new.raw_app_meta_data->>'company_id')::uuid;

  IF company_id_from_meta IS NOT NULL THEN
    -- If company_id is in metadata, this user was invited.
    -- Insert them into the public.users table with the existing company_id.
    INSERT INTO public.users (id, company_id, email, role)
    VALUES (new.id, company_id_from_meta, user_email, 'Member');

    -- Update the user's metadata to remove temporary invite data and add final role.
    UPDATE auth.users
    SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('role', 'Member', 'company_name', NULL)
    WHERE id = new.id;
  ELSE
    -- If company_id is not in metadata, this is a new signup.
    -- Create a new company for them.
    company_name_from_meta := new.raw_app_meta_data->>'company_name';
    
    INSERT INTO public.companies (name)
    VALUES (company_name_from_meta)
    RETURNING id INTO new_company_id;

    -- Insert the user as the Owner of the new company.
    INSERT INTO public.users (id, company_id, email, role)
    VALUES (new.id, new_company_id, user_email, 'Owner');
    
    -- Now, update the user's app_metadata in the auth.users table
    -- to include their new company_id and role.
    UPDATE auth.users
    SET raw_app_meta_data = jsonb_build_object('company_id', new_company_id, 'role', 'Owner')
    WHERE id = new.id;
  END IF;
  
  RETURN new;
END;
$$;


-- ====================================================================
--  STEP 4: RECREATE VIEWS AND POLICIES
-- ====================================================================

-- Recreate the product_variants_with_details view
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


-- Helper procedure to re-apply all policies
CREATE OR REPLACE PROCEDURE apply_rls_policies()
LANGUAGE plpgsql
AS $$
BEGIN
    -- Apply policies to tables with a direct company_id column
    PERFORM enable_rls_on_table(table_name)
    FROM (VALUES
        ('companies'), ('company_settings'), ('users'), ('products'), ('product_variants'),
        ('inventory_ledger'), ('orders'), ('order_line_items'), ('customers'),
        ('suppliers'), ('purchase_orders'), ('integrations'), ('conversations'), ('messages'),
        ('audit_log'), ('channel_fees')
    ) AS t(table_name);
    
    -- Apply special policy for purchase_order_line_items
    CREATE POLICY "Allow access based on parent PO"
    ON public.purchase_order_line_items
    FOR ALL
    USING (
        company_id = public.get_company_id() AND
        EXISTS (
            SELECT 1
            FROM public.purchase_orders po
            WHERE po.id = purchase_order_line_items.purchase_order_id
            AND po.company_id = public.get_company_id()
        )
    )
    WITH CHECK (company_id = public.get_company_id());
END;
$$;

-- Helper procedure to enable RLS and create standard policies
CREATE OR REPLACE PROCEDURE enable_rls_on_table(table_name TEXT)
LANGUAGE plpgsql
AS $$
BEGIN
    EXECUTE 'ALTER TABLE public.' || quote_ident(table_name) || ' ENABLE ROW LEVEL SECURITY';
    EXECUTE 'ALTER TABLE public.' || quote_ident(table_name) || ' FORCE ROW LEVEL SECURITY';
    
    -- Special case for the 'companies' table which uses 'id' instead of 'company_id'
    IF table_name = 'companies' THEN
        EXECUTE 'CREATE POLICY "Allow all access to own company data" ON public.companies FOR ALL USING (id = public.get_company_id()) WITH CHECK (id = public.get_company_id())';
    ELSE
        EXECUTE 'CREATE POLICY "Allow all access to own company data" ON public.' || quote_ident(table_name) || ' FOR ALL USING (company_id = public.get_company_id()) WITH CHECK (company_id = public.get_company_id())';
    END IF;
END;
$$;

-- Execute the procedure to apply all policies
CALL apply_rls_policies();

-- Clean up helper procedures
DROP PROCEDURE IF EXISTS drop_all_policies_on_table(text);
DROP PROCEDURE IF EXISTS apply_rls_policies();
DROP PROCEDURE IF EXISTS enable_rls_on_table(text);

COMMIT;
