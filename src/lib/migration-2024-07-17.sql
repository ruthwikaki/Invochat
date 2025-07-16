
-- This script is designed to be idempotent and can be run multiple times safely.
-- It will bring your database schema up-to-date with the latest application requirements.

DO $$
DECLARE
  table_name regclass;
BEGIN
  -- Drop the old, problematic trigger and function if they exist from previous failed attempts.
  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'on_auth_user_created') THEN
    DROP TRIGGER on_auth_user_created ON auth.users;
  END IF;

  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'handle_new_user') THEN
    DROP FUNCTION handle_new_user();
  END IF;
END $$;


-- Helper function to get the company_id from the JWT claims.
-- This is used in RLS policies to ensure users can only access their own company's data.
CREATE OR REPLACE FUNCTION public.get_company_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT (NULLIF(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', ''))::uuid;
$$;


-- Function to apply Row-Level Security (RLS) policies to tables.
-- It ensures that policies are only applied if the table exists and has a company_id column.
CREATE OR REPLACE PROCEDURE apply_rls_policies(p_table_name regclass)
LANGUAGE plpgsql
AS $$
DECLARE
    policy_name_all text := 'Allow all access to own company data';
    policy_name_read text := 'Allow read access to own company data';
BEGIN
    -- Enable RLS on the table
    EXECUTE 'ALTER TABLE ' || p_table_name || ' ENABLE ROW LEVEL SECURITY';

    -- Drop existing policies to prevent conflicts
    EXECUTE 'DROP POLICY IF EXISTS "' || policy_name_all || '" ON ' || p_table_name;
    EXECUTE 'DROP POLICY IF EXISTS "' || policy_name_read || '" ON ' || p_table_name;

    -- Create policies based on the table's structure
    IF p_table_name = 'public.companies'::regclass THEN
      -- Special case for the companies table itself
      EXECUTE 'CREATE POLICY "' || policy_name_all || '" ON ' || p_table_name || ' FOR ALL USING (id = public.get_company_id()) WITH CHECK (id = public.get_company_id())';
    ELSIF p_table_name = 'public.purchase_order_line_items'::regclass THEN
      -- Special case for line items, checking the parent PO's company_id
      EXECUTE 'CREATE POLICY "' || policy_name_all || '" ON ' || p_table_name || ' FOR ALL USING ((SELECT po.company_id FROM public.purchase_orders po WHERE po.id = purchase_order_id) = public.get_company_id())';
    ELSIF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = p_table_name::text AND column_name = 'company_id') THEN
      -- Generic policy for tables with a company_id column
      EXECUTE 'CREATE POLICY "' || policy_name_all || '" ON ' || p_table_name || ' FOR ALL USING (company_id = public.get_company_id()) WITH CHECK (company_id = public.get_company_id())';
    ELSE
      RAISE WARNING 'Table % does not have a company_id column, skipping RLS policy.', p_table_name;
    END IF;
END;
$$;

DO $$
DECLARE
    table_name text;
BEGIN
    -- Apply RLS policies to all relevant tables in the public schema.
    FOR table_name IN
        SELECT tablename FROM pg_tables WHERE schemaname = 'public'
    LOOP
        -- The users table is a special case handled by a different security model.
        IF table_name <> 'users' THEN
            BEGIN
                CALL apply_rls_policies(table_name::regclass);
            EXCEPTION WHEN OTHERS THEN
                RAISE WARNING 'Could not apply RLS policy to table %: %', table_name, SQLERRM;
            END;
        END IF;
    END LOOP;
END $$;


-- Function to handle new user setup. This function is called by the application's
-- signup logic and runs with the permissions of the newly signed-up user.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_company_id uuid;
    v_user_id uuid := auth.uid();
    v_user_email text := (SELECT email FROM auth.users WHERE id = v_user_id);
    v_company_name text := (SELECT raw_app_meta_data->>'company_name' FROM auth.users WHERE id = v_user_id);
BEGIN
    -- Create a new company for the user.
    INSERT INTO public.companies (name)
    VALUES (v_company_name)
    RETURNING id INTO v_company_id;

    -- Create a corresponding entry in the public.users table.
    INSERT INTO public.users (id, company_id, email, role)
    VALUES (v_user_id, v_company_id, v_user_email, 'Owner');

    -- Update the user's app_metadata in the auth schema to include the new company_id and role.
    -- This makes the company_id available in the JWT for RLS policies.
    UPDATE auth.users
    SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', v_company_id, 'role', 'Owner')
    WHERE id = v_user_id;
END;
$$;


-- Create or replace views to provide aggregated data and simplify queries.
-- These views are essential for the dashboard and analytics features.
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
    pv.external_variant_id,
    pv.created_at,
    pv.updated_at,
    pv.location,
    p.title AS product_title,
    p.status AS product_status,
    p.image_url,
    p.product_type
   FROM (public.product_variants pv
     JOIN public.products p ON ((pv.product_id = p.id)));

-- Add any new columns safely.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='role') THEN
    ALTER TABLE public.users ADD COLUMN role text DEFAULT 'Member'::text;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='purchase_orders' AND column_name='idempotency_key') THEN
    ALTER TABLE public.purchase_orders ADD COLUMN idempotency_key uuid;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='company_settings' AND column_name='overstock_multiplier') THEN
    ALTER TABLE public.company_settings ADD COLUMN overstock_multiplier integer NOT NULL DEFAULT 3;
    ALTER TABLE public.company_settings ADD COLUMN high_value_threshold integer NOT NULL DEFAULT 1000;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='messages' AND column_name='is_error') THEN
    ALTER TABLE public.messages ADD COLUMN is_error boolean DEFAULT false;
  END IF;
END;
$$;
