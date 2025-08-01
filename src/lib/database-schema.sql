-- ============================================================================
-- IDEMPOTENT FUNCTION REPLACEMENT SCRIPT
-- ============================================================================
-- This script safely replaces the get_company_id_for_user function to fix
-- an "infinite recursion" error in RLS policies. It temporarily disables
-- RLS on affected tables, replaces the function, and then re-enables RLS.

DO $$
DECLARE
    -- Array of all tables that have RLS policies depending on the function
    tables_with_rls TEXT[] := ARRAY[
        'products', 'product_variants', 'orders', 'order_line_items', 'customers',
        'suppliers', 'purchase_orders', 'purchase_order_line_items', 'integrations',
        'webhook_events', 'inventory_ledger', 'messages', 'audit_log',
        'company_settings', 'refunds', 'feedback', 'export_jobs',
        'channel_fees', 'company_users', 'imports'
    ];
    table_name TEXT;
BEGIN
    RAISE NOTICE 'Starting safe function replacement...';

    -- STEP 1: Temporarily disable RLS on all dependent tables
    RAISE NOTICE 'Disabling RLS on dependent tables...';
    FOREACH table_name IN ARRAY tables_with_rls
    LOOP
        -- Using format() to safely quote the table name
        EXECUTE format('ALTER TABLE public.%I DISABLE ROW LEVEL SECURITY;', table_name);
        RAISE NOTICE '  -> RLS disabled on %', table_name;
    END LOOP;

    -- STEP 2: Replace the faulty function with the corrected version
    -- The new version gets the company_id from the JWT claims instead of a recursive query.
    RAISE NOTICE 'Replacing the get_company_id_for_user function...';
    CREATE OR REPLACE FUNCTION public.get_company_id_for_user(p_user_id uuid)
    RETURNS uuid
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    AS $$
        -- This is the primary and secure way to get the company ID for RLS.
        -- It avoids table queries, preventing infinite recursion in policies.
        SELECT NULLIF(auth.jwt()->'app_metadata'->>'company_id', '')::uuid;
    $$;
    RAISE NOTICE '  -> Function get_company_id_for_user has been updated.';


    -- STEP 3: Re-enable RLS on all tables
    RAISE NOTICE 'Re-enabling RLS on all tables...';
    FOREACH table_name IN ARRAY tables_with_rls
    LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', table_name);
        -- Force RLS for table owners as well, which is a security best practice
        EXECUTE format('ALTER TABLE public.%I FORCE ROW LEVEL SECURITY;', table_name);
        RAISE NOTICE '  -> RLS re-enabled and forced on %', table_name;
    END LOOP;

    RAISE NOTICE 'Function replacement script completed successfully!';
END;
$$;
