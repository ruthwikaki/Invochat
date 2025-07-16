-- This migration script is designed to be run on an existing database
-- that was set up with older versions of the schema. It is idempotent,
-- meaning it can be run multiple times without causing errors.

-- Drop the old, problematic trigger and function if they exist from previous failed attempts.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();

-- Helper function to get the company_id from a user's JWT claims.
-- This is used in the RLS policies below.
-- The explicit cast to uuid is CRITICAL to prevent type mismatch errors.
CREATE OR REPLACE FUNCTION public.get_company_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT (auth.jwt()->>'company_id')::uuid;
$$;


-- =================================================================
-- Step 1: Create or Update Tables
-- Uses `IF NOT EXISTS` to avoid errors on existing tables.
-- =================================================================

CREATE TABLE IF NOT EXISTS public.users (
    id uuid NOT NULL PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email text,
    role text DEFAULT 'member',
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now()
);

-- =================================================================
-- Step 2: Add new columns if they don't exist
-- =================================================================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'public.products'::regclass AND attname = 'fts_document') THEN
    ALTER TABLE public.products ADD COLUMN fts_document tsvector;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'public.company_settings'::regclass AND attname = 'overstock_multiplier') THEN
    ALTER TABLE public.company_settings ADD COLUMN overstock_multiplier integer NOT NULL DEFAULT 3;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'public.company_settings'::regclass AND attname = 'high_value_threshold') THEN
    ALTER TABLE public.company_settings ADD COLUMN high_value_threshold integer NOT NULL DEFAULT 1000;
  END IF;
END;
$$;


-- =================================================================
-- Step 3: Create or Replace all Views
-- Replaces all views to ensure they have the correct columns and definitions.
-- This is the correct fix for the 'cannot drop columns from view' error.
-- =================================================================

DROP VIEW IF EXISTS public.product_variants_with_details;
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
-- Step 4: Create or Replace all Functions and Triggers
-- =================================================================

-- Function to handle creating a user profile when a new user signs up in Supabase Auth.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  company_id_from_meta uuid;
  company_name_from_meta text;
BEGIN
  -- Check for company_id in the metadata. If it exists, the user is being invited.
  company_id_from_meta := (new.raw_app_meta_data->>'company_id')::uuid;
  
  -- If company_id is present, insert into public.users.
  IF company_id_from_meta IS NOT NULL THEN
    INSERT INTO public.users (id, company_id, email, role)
    VALUES (new.id, company_id_from_meta, new.email, 'member');
  
  -- Otherwise, a new company and user profile must be created.
  ELSE
    company_name_from_meta := new.raw_app_meta_data->>'company_name';
    -- Create the new company
    INSERT INTO public.companies (name)
    VALUES (company_name_from_meta)
    RETURNING id INTO company_id_from_meta;
    
    -- Create the user profile and assign them as the owner
    INSERT INTO public.users (id, company_id, email, role)
    VALUES (new.id, company_id_from_meta, new.email, 'Owner');
    
    -- Update the user's app_metadata in auth.users to include the new company_id
    UPDATE auth.users
    SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id_from_meta)
    WHERE id = new.id;
  END IF;
  
  RETURN new;
END;
$$;

-- Trigger that calls handle_new_user when a user is created in auth.users
CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- =================================================================
-- Step 5: Enable Row-Level Security and Define Policies
-- Drops old policies and creates the new, correct ones.
-- =================================================================

-- Function to drop a policy if it exists, regardless of its definition
CREATE OR REPLACE PROCEDURE drop_policy_if_exists(table_name_param text, policy_name_param text)
LANGUAGE plpgsql
AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE tablename = table_name_param AND policyname = policy_name_param) THEN
    EXECUTE 'DROP POLICY "' || policy_name_param || '" ON ' || table_name_param;
  END IF;
END;
$$;

-- Helper to enable RLS and apply standard policies
CREATE OR REPLACE PROCEDURE apply_rls_policies(table_name_param text)
LANGUAGE plpgsql
AS $$
BEGIN
    EXECUTE 'ALTER TABLE ' || table_name_param || ' ENABLE ROW LEVEL SECURITY';
    EXECUTE 'ALTER TABLE ' || table_name_param || ' FORCE ROW LEVEL SECURITY';
    
    CALL drop_policy_if_exists(table_name_param, 'Allow all access to own company data');
    EXECUTE 'CREATE POLICY "Allow all access to own company data" ON ' || table_name_param ||
            ' FOR ALL USING (company_id = public.get_company_id()) WITH CHECK (company_id = public.get_company_id())';
END;
$$;

-- Apply policies to all relevant tables
DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'companies', 'company_settings', 'products', 'product_variants', 'suppliers',
    'purchase_orders', 'purchase_order_line_items', 'orders', 'order_line_items',
    'customers', 'customer_addresses', 'refunds', 'refund_line_items', 'discounts',
    'integrations', 'inventory_ledger', 'webhook_events', 'audit_log', 'users',
    'conversations', 'messages', 'export_jobs'
  ]
  LOOP
    CALL apply_rls_policies(t);
  END LOOP;
END;
$$;

-- Clean up helper procedures
DROP PROCEDURE IF EXISTS apply_rls_policies(text);
DROP PROCEDURE IF EXISTS drop_policy_if_exists(text, text);

-- Final check on the 'users' table specifically for self-read access
CALL drop_policy_if_exists('public.users', 'Allow user to read their own profile');
CREATE POLICY "Allow user to read their own profile" ON public.users
FOR SELECT USING (id = auth.uid());

-- Grant usage on the public schema to the authenticated role
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;

GRANT USAGE ON SCHEMA public TO service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO service_role;
