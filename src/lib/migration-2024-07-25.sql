-- ARVO DATABASE MIGRATION SCRIPT
-- This script is designed to be idempotent and safely updates an existing database
-- from its initial state to the required state for the latest application version.

DO $$
BEGIN
    RAISE NOTICE 'Starting ARVO database migration...';
END $$;

-- STEP 1: Define helper procedures for RLS management.
-- Using procedures to handle dynamic SQL execution.

-- Procedure to enable RLS on a table if it's not already enabled.
CREATE OR REPLACE PROCEDURE enable_rls_on_table(table_name TEXT)
LANGUAGE plpgsql
AS $$
BEGIN
    EXECUTE 'ALTER TABLE public.' || quote_ident(table_name) || ' ENABLE ROW LEVEL SECURITY';
    RAISE NOTICE 'Enabled RLS on table: %', table_name;
EXCEPTION
    WHEN duplicate_object THEN
        RAISE NOTICE 'RLS is already enabled on table: %', table_name;
END;
$$;

-- Procedure to drop all existing policies on a table to ensure a clean slate.
CREATE OR REPLACE PROCEDURE drop_all_policies_on_table(table_name TEXT)
LANGUAGE plpgsql
AS $$
DECLARE
    r record;
BEGIN
    FOR r IN (SELECT policyname FROM pg_policies WHERE tablename = table_name AND schemaname = 'public')
    LOOP
        EXECUTE 'DROP POLICY IF EXISTS ' || quote_ident(r.policyname) || ' ON public.' || quote_ident(table_name);
    END LOOP;
    RAISE NOTICE 'Dropped all existing policies on table: %', table_name;
END;
$$;


-- STEP 2: Drop dependent objects (Views and Policies) before altering the function they use.

DO $$
DECLARE
    table_name TEXT;
BEGIN
    RAISE NOTICE 'Dropping all existing RLS policies...';
    FOR table_name IN
        SELECT t.tablename FROM pg_tables t
        WHERE t.schemaname = 'public' AND t.tableowner = 'postgres'
    LOOP
        CALL drop_all_policies_on_table(table_name);
    END LOOP;
END $$;

RAISE NOTICE 'Dropping dependent views...';
DROP VIEW IF EXISTS public.product_variants_with_details;

-- STEP 3: Recreate the core helper function `get_company_id`.
-- This ensures the function definition is always up-to-date.

RAISE NOTICE 'Recreating helper function: get_company_id()';
CREATE OR REPLACE FUNCTION public.get_company_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT (NULLIF(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid);
$$;

-- STEP 4: Add new columns if they don't exist.
DO $$
BEGIN
    RAISE NOTICE 'Adding new columns to tables if they do not exist...';

    -- Add 'role' to public.users table
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'role') THEN
        ALTER TABLE public.users ADD COLUMN role TEXT DEFAULT 'member';
        RAISE NOTICE 'Added column "role" to public.users';
    END IF;

    -- Add 'company_id' to purchase_order_line_items
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'purchase_order_line_items' AND column_name = 'company_id') THEN
        ALTER TABLE public.purchase_order_line_items ADD COLUMN company_id UUID;
        RAISE NOTICE 'Added column "company_id" to public.purchase_order_line_items';
    END IF;
END $$;


-- STEP 5: Create a master procedure to apply all RLS policies.
CREATE OR REPLACE PROCEDURE apply_rls_policies()
LANGUAGE plpgsql
AS $$
DECLARE
    table_name TEXT;
BEGIN
    RAISE NOTICE 'Applying RLS policies to all tables...';
    -- Iterate over all tables in the public schema and enable RLS
    FOR table_name IN
        SELECT t.tablename FROM pg_tables t
        WHERE t.schemaname = 'public' AND t.tableowner = 'postgres'
    LOOP
        -- This is the corrected line: using CALL instead of PERFORM
        CALL enable_rls_on_table(table_name);
    END LOOP;

    -- Policy for 'companies'
    CALL drop_all_policies_on_table('companies');
    CREATE POLICY "Allow all access to own company data" ON public.companies FOR ALL
        USING (id = public.get_company_id())
        WITH CHECK (id = public.get_company_id());

    -- Policy for 'users'
    CALL drop_all_policies_on_table('users');
    CREATE POLICY "Allow all access to own company data" ON public.users FOR ALL
        USING (company_id = public.get_company_id())
        WITH CHECK (company_id = public.get_company_id());
        
    -- Policy for all other tables with a 'company_id' column
    FOR table_name IN
        SELECT t.table_name FROM information_schema.columns t
        WHERE t.table_schema = 'public' AND t.column_name = 'company_id' AND t.table_name NOT IN ('companies', 'users')
    LOOP
        CALL drop_all_policies_on_table(table_name);
        EXECUTE format('CREATE POLICY "Allow all access to own company data" ON public.%I FOR ALL USING (company_id = public.get_company_id()) WITH CHECK (company_id = public.get_company_id())', table_name);
    END LOOP;

    -- Special policy for 'purchase_order_line_items' which does not have a company_id
    CALL drop_all_policies_on_table('purchase_order_line_items');
    CREATE POLICY "Allow all access based on parent PO" ON public.purchase_order_line_items FOR ALL
        USING (
            (
                SELECT po.company_id
                FROM public.purchase_orders po
                WHERE po.id = purchase_order_id
            ) = public.get_company_id()
        )
        WITH CHECK (
            (
                SELECT po.company_id
                FROM public.purchase_orders po
                WHERE po.id = purchase_order_id
            ) = public.get_company_id()
        );

    RAISE NOTICE 'Finished applying RLS policies.';
END;
$$;

-- Execute the master policy procedure
CALL apply_rls_policies();


-- STEP 6: Recreate Views
RAISE NOTICE 'Recreating views...';

-- View for product variants with essential product details
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
    p.title as product_title,
    p.status as product_status,
    p.image_url
FROM
    public.product_variants pv
JOIN
    public.products p ON pv.product_id = p.id
WHERE
    pv.company_id = public.get_company_id();


DO $$
BEGIN
    RAISE NOTICE 'Migration script finished successfully.';
END $$;
