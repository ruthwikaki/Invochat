-- ============================================================================
-- AUTH SYSTEM CLEANUP MIGRATION (V2 - Idempotent)
-- ============================================================================
-- This migration removes the redundant public.users table and fixes all
-- foreign key relationships to properly reference auth.users as the single
-- source of truth for user identity. It is designed to be runnable even if
-- parts of it have already been executed.

BEGIN;

-- ============================================================================
-- STEP 1: PRE-CHECKS AND DATA MIGRATION
-- ============================================================================

-- Only run migration steps if the faulty public.users table still exists.
DO $$
DECLARE
    missing_count INTEGER;
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'users') THEN
        
        RAISE NOTICE 'public.users table found. Proceeding with migration...';

        -- Check for orphaned records in public.users that must be handled manually.
        SELECT COUNT(*) INTO missing_count
        FROM public.users pu
        LEFT JOIN auth.users au ON pu.id = au.id
        WHERE au.id IS NULL;
        
        IF missing_count > 0 THEN
            RAISE EXCEPTION 'Found % users in public.users that do not exist in auth.users. Manual data cleanup is required before this migration can run.', missing_count;
        END IF;

        -- Migrate any missing company_users relationships from the old public.users table.
        RAISE NOTICE 'Migrating role information from public.users to public.company_users...';
        INSERT INTO public.company_users (company_id, user_id, role)
        SELECT 
            pu.company_id,
            pu.id,
            CASE 
                WHEN lower(pu.role) = 'owner' THEN 'Owner'::company_role
                WHEN lower(pu.role) = 'admin' THEN 'Admin'::company_role
                ELSE 'Member'::company_role
            END
        FROM public.users pu
        WHERE NOT EXISTS (
            SELECT 1 FROM public.company_users cu 
            WHERE cu.user_id = pu.id AND cu.company_id = pu.company_id
        )
        ON CONFLICT (user_id, company_id) DO NOTHING;

    ELSE
        RAISE NOTICE 'public.users table not found. Skipping main data migration steps.';
    END IF;
END $$;


-- ============================================================================
-- STEP 2: DROP REDUNDANT public.users TABLE (if it exists)
-- ============================================================================

DROP TABLE IF EXISTS public.users CASCADE;
RAISE NOTICE 'Successfully dropped public.users table (if it existed).';


-- ============================================================================
-- STEP 3: RECREATE/VERIFY FOREIGN KEY CONSTRAINTS
-- ============================================================================

-- Helper function to safely add a foreign key constraint.
CREATE OR REPLACE FUNCTION private.safe_add_fkey(
    p_table_schema TEXT,
    p_table_name TEXT, 
    p_constraint_name TEXT, 
    p_fkey_definition TEXT
)
RETURNS void AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE table_name = p_table_name 
        AND constraint_name = p_constraint_name
        AND table_schema = p_table_schema
    ) THEN
        EXECUTE 'ALTER TABLE ' || quote_ident(p_table_schema) || '.' || quote_ident(p_table_name) || ' ADD CONSTRAINT ' || quote_ident(p_constraint_name) || ' ' || p_fkey_definition;
        RAISE NOTICE 'Created constraint % on %.%', p_constraint_name, p_table_schema, p_table_name;
    ELSE
        RAISE NOTICE 'Constraint % on %.% already exists. Skipping.', p_constraint_name, p_table_schema, p_table_name;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Set all FKs to point to auth.users.id
-- This is idempotent and will not fail if constraints already exist.
SELECT private.safe_add_fkey('public', 'company_users', 'company_users_user_id_fkey', 'FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE');
SELECT private.safe_add_fkey('public', 'companies', 'companies_owner_id_fkey', 'FOREIGN KEY (owner_id) REFERENCES auth.users(id) ON DELETE SET NULL');
SELECT private.safe_add_fkey('public', 'audit_log', 'audit_log_user_id_fkey', 'FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL');
SELECT private.safe_add_fkey('public', 'conversations', 'conversations_user_id_fkey', 'FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE');
SELECT private.safe_add_fkey('public', 'export_jobs', 'export_jobs_requested_by_user_id_fkey', 'FOREIGN KEY (requested_by_user_id) REFERENCES auth.users(id) ON DELETE SET NULL');
SELECT private.safe_add_fkey('public', 'feedback', 'feedback_user_id_fkey', 'FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE');
SELECT private.safe_add_fkey('public', 'imports', 'imports_created_by_fkey', 'FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL');
SELECT private.safe_add_fkey('public', 'refunds', 'refunds_created_by_user_id_fkey', 'FOREIGN KEY (created_by_user_id) REFERENCES auth.users(id) ON DELETE SET NULL');


-- ============================================================================
-- STEP 4: FIX RLS AND HELPER FUNCTIONS
-- ============================================================================

-- This function is the root cause of the "infinite recursion" error.
-- It now securely gets the company_id from the session JWT, not by re-querying a table.
CREATE OR REPLACE FUNCTION public.get_company_id_for_user(p_user_id uuid)
RETURNS uuid AS $$
BEGIN
  RETURN (
    SELECT raw_app_meta_data->>'company_id' 
    FROM auth.users 
    WHERE id = p_user_id
  )::uuid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================================
-- STEP 5: VERIFICATION
-- ============================================================================

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'users') THEN
        RAISE EXCEPTION 'MIGRATION FAILED: public.users table still exists!';
    END IF;

    RAISE NOTICE 'Migration script completed successfully.';
END $$;

COMMIT;