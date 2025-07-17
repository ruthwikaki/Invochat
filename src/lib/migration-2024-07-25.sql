-- ARVO DATABASE MIGRATION SCRIPT
-- This script applies all necessary changes from the initial schema to the current version.
-- It is designed to be run once on an existing database.
-- It is idempotent and can be re-run, but it's best to run it only once.

BEGIN;

-- =================================================================
-- Step 1: Procedure to drop all RLS policies on a table
-- This allows us to redefine them without conflicts.
-- =================================================================
CREATE OR REPLACE PROCEDURE drop_all_rls_policies(table_name_param regclass)
LANGUAGE plpgsql
AS $$
DECLARE
    r record;
BEGIN
    FOR r IN (SELECT policyname FROM pg_policies WHERE tablename = table_name_param::text AND schemaname = 'public')
    LOOP
        EXECUTE 'DROP POLICY IF EXISTS ' || quote_ident(r.policyname) || ' ON ' || table_name_param;
    END LOOP;
END;
$$;

-- =================================================================
-- Step 2: Procedure to enable RLS on all tables
-- =================================================================
CREATE OR REPLACE PROCEDURE enable_rls_on_table(table_name_param regclass)
LANGUAGE plpgsql
AS $$
BEGIN
    EXECUTE 'ALTER TABLE ' || table_name_param || ' ENABLE ROW LEVEL SECURITY';
    EXECUTE 'ALTER TABLE ' || table_name_param || ' FORCE ROW LEVEL SECURITY';
END;
$$;

-- =================================================================
-- Step 3: Centralized procedure to apply all policies
-- =================================================================
CREATE OR REPLACE PROCEDURE apply_rls_policies()
LANGUAGE plpgsql
AS $$
DECLARE
    table_name text;
BEGIN
    -- Enable RLS on all tables first
    FOR table_name IN
        SELECT t.table_name FROM (VALUES
            ('companies'), ('company_settings'), ('users'), ('products'), ('product_variants'),
            ('inventory_ledger'), ('orders'), ('order_line_items'), ('customers'),
            ('suppliers'), ('purchase_orders'), ('purchase_order_line_items'), ('integrations'), ('conversations'), ('messages'),
            ('audit_log'), ('channel_fees')
        ) AS t(table_name)
    LOOP
        CALL enable_rls_on_table(table_name::regclass);
    END LOOP;

    -- Standard policy for tables with a direct company_id
    FOR table_name IN
        SELECT t.table_name FROM (VALUES
             ('company_settings'), ('users'), ('products'), ('product_variants'),
            ('inventory_ledger'), ('orders'), ('order_line_items'), ('customers'),
            ('suppliers'), ('purchase_orders'), ('integrations'), ('conversations'), ('messages'),
            ('audit_log'), ('channel_fees')
        ) AS t(table_name)
    LOOP
        EXECUTE 'CREATE POLICY "Allow all access to own company data" ON public.' || quote_ident(table_name)
             || ' FOR ALL USING (company_id = public.get_company_id()) WITH CHECK (company_id = public.get_company_id())';
    END LOOP;

    -- Special policy for the 'companies' table itself (checks its own id)
    CREATE POLICY "Allow all access to own company data" ON public.companies
        FOR ALL USING (id = public.get_company_id()) WITH CHECK (id = public.get_company_id());

    -- Special policy for purchase_order_line_items (checks parent PO)
    CREATE POLICY "Allow all access based on parent PO" ON public.purchase_order_line_items
        FOR ALL
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
END;
$$;


-- =================================================================
-- Step 4: Drop dependent objects before redefining the function
-- =================================================================
DROP VIEW IF EXISTS public.product_variants_with_details;
CALL drop_all_rls_policies('companies');
CALL drop_all_rls_policies('company_settings');
CALL drop_all_rls_policies('users');
CALL drop_all_rls_policies('products');
CALL drop_all_rls_policies('product_variants');
CALL drop_all_rls_policies('inventory_ledger');
CALL drop_all_rls_policies('orders');
CALL drop_all_rls_policies('order_line_items');
CALL drop_all_rls_policies('customers');
CALL drop_all_rls_policies('suppliers');
CALL drop_all_rls_policies('purchase_orders');
CALL drop_all_rls_policies('purchase_order_line_items');
CALL drop_all_rls_policies('integrations');
CALL drop_all_rls_policies('conversations');
CALL drop_all_rls_policies('messages');
CALL drop_all_rls_policies('audit_log');
CALL drop_all_rls_policies('channel_fees');

-- =================================================================
-- Step 5: Redefine the company ID helper function correctly
-- =================================================================
CREATE OR REPLACE FUNCTION public.get_company_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT (NULLIF(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid);
$$;

-- =================================================================
-- Step 6: Apply Schema Changes
-- =================================================================
ALTER TABLE public.orders DROP COLUMN IF EXISTS status;
ALTER TABLE public.order_line_items ALTER COLUMN product_id SET NOT NULL;
ALTER TABLE public.order_line_items ALTER COLUMN variant_id SET NOT NULL;

-- Add company_id to purchase_order_line_items if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
        AND table_name = 'purchase_order_line_items'
        AND column_name = 'company_id'
    ) THEN
        ALTER TABLE public.purchase_order_line_items ADD COLUMN company_id uuid;
    END IF;
END;
$$;

-- Populate the new company_id column by joining with purchase_orders
UPDATE public.purchase_order_line_items poli
SET company_id = po.company_id
FROM public.purchase_orders po
WHERE poli.purchase_order_id = po.id AND poli.company_id IS NULL;

-- Now that it's populated, make it non-nullable
ALTER TABLE public.purchase_order_line_items ALTER COLUMN company_id SET NOT NULL;

-- =================================================================
-- Step 7: Recreate Views
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
    public.products p ON pv.product_id = p.id
WHERE
    pv.company_id = public.get_company_id();

-- =================================================================
-- Step 8: Re-apply all RLS policies
-- =================================================================
CALL apply_rls_policies();

-- =================================================================
-- Step 9: Clean up temporary procedures
-- =================================================================
DROP PROCEDURE IF EXISTS drop_all_rls_policies(regclass);
DROP PROCEDURE IF EXISTS enable_rls_on_table(regclass);
DROP PROCEDURE IF EXISTS apply_rls_policies();


COMMIT;
