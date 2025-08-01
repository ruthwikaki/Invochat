-- ============================================================================
-- AUTH SYSTEM CLEANUP MIGRATION (IDEMPOTENT)
-- ============================================================================
-- This migration removes the redundant public.users table and fixes all
-- foreign key relationships to properly reference auth.users as the single
-- source of truth for user identity. It is designed to be run safely even
-- if parts of the migration have already been completed.

BEGIN;

-- ============================================================================
-- STEP 1: DEFINE HELPER FUNCTION TO DROP CONSTRAINTS IF THEY EXIST
-- ============================================================================
CREATE OR REPLACE FUNCTION public.drop_constraint_if_exists(
    p_schema_name TEXT,
    p_table_name TEXT,
    p_constraint_name TEXT
)
RETURNS VOID AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.table_constraints
        WHERE table_schema = p_schema_name
          AND table_name = p_table_name
          AND constraint_name = p_constraint_name
    ) THEN
        EXECUTE 'ALTER TABLE ' || quote_ident(p_schema_name) || '.' || quote_ident(p_table_name) ||
                ' DROP CONSTRAINT ' || quote_ident(p_constraint_name);
        RAISE NOTICE 'Dropped constraint "%" from "%.%"', p_constraint_name, p_schema_name, p_table_name;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- STEP 2: DATA MIGRATION & CLEANUP
-- ============================================================================
-- Ensure all users in public.users exist in auth.users
DO $$
DECLARE
    missing_count INTEGER;
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'users') THEN
        SELECT COUNT(*) INTO missing_count
        FROM public.users pu
        LEFT JOIN auth.users au ON pu.id = au.id
        WHERE au.id IS NULL;

        IF missing_count > 0 THEN
            RAISE EXCEPTION 'Found % users in public.users that do not exist in auth.users. Manual intervention required.', missing_count;
        END IF;

        -- Migrate any missing company_users relationships
        INSERT INTO public.company_users (company_id, user_id, role)
        SELECT
            pu.company_id,
            pu.id,
            CASE
                WHEN pu.role = 'owner' THEN 'Owner'::company_role
                WHEN pu.role = 'admin' THEN 'Admin'::company_role
                ELSE 'Member'::company_role
            END
        FROM public.users pu
        WHERE NOT EXISTS (
            SELECT 1 FROM public.company_users cu
            WHERE cu.user_id = pu.id AND cu.company_id = pu.company_id
        )
        ON CONFLICT (company_id, user_id) DO NOTHING;
    END IF;
END $$;


-- ============================================================================
-- STEP 3: DROP REDUNDANT public.users TABLE
-- ============================================================================
-- Drop the user-defined type 'company_user_role' if it exists, as it's not standard
DROP TYPE IF EXISTS public.company_user_role;
DROP TABLE IF EXISTS public.users CASCADE;

-- ============================================================================
-- STEP 4: CREATE PROPER FOREIGN KEY CONSTRAINTS
-- ============================================================================

-- Drop constraints first to avoid "already exists" errors, then re-create them.
SELECT public.drop_constraint_if_exists('public', 'company_users', 'company_users_user_id_fkey');
ALTER TABLE public.company_users ADD CONSTRAINT company_users_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

SELECT public.drop_constraint_if_exists('public', 'companies', 'companies_owner_id_fkey');
ALTER TABLE public.companies ADD CONSTRAINT companies_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES auth.users(id) ON DELETE SET NULL;

SELECT public.drop_constraint_if_exists('public', 'audit_log', 'audit_log_user_id_fkey');
ALTER TABLE public.audit_log ADD CONSTRAINT audit_log_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL;

SELECT public.drop_constraint_if_exists('public', 'conversations', 'conversations_user_id_fkey');
ALTER TABLE public.conversations ADD CONSTRAINT conversations_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

SELECT public.drop_constraint_if_exists('public', 'export_jobs', 'export_jobs_requested_by_user_id_fkey');
ALTER TABLE public.export_jobs ADD CONSTRAINT export_jobs_requested_by_user_id_fkey FOREIGN KEY (requested_by_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;

SELECT public.drop_constraint_if_exists('public', 'feedback', 'feedback_user_id_fkey');
ALTER TABLE public.feedback ADD CONSTRAINT feedback_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

SELECT public.drop_constraint_if_exists('public', 'imports', 'imports_created_by_fkey');
ALTER TABLE public.imports ADD CONSTRAINT imports_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

SELECT public.drop_constraint_if_exists('public', 'refunds', 'refunds_created_by_user_id_fkey');
ALTER TABLE public.refunds ADD CONSTRAINT refunds_created_by_user_id_fkey FOREIGN KEY (created_by_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;


-- ============================================================================
-- STEP 5: ADD ESSENTIAL INDEXES AND CONSTRAINTS
-- ============================================================================
CREATE UNIQUE INDEX IF NOT EXISTS auth_users_email_unique ON auth.users(email) WHERE email IS NOT NULL;
CREATE INDEX IF NOT EXISTS company_users_user_id_idx ON public.company_users(user_id);
CREATE INDEX IF NOT EXISTS company_users_company_id_idx ON public.company_users(company_id);

-- Ensure unique constraint on company_users
SELECT public.drop_constraint_if_exists('public', 'company_users', 'company_users_unique');
ALTER TABLE public.company_users ADD CONSTRAINT company_users_unique UNIQUE (company_id, user_id);

-- ============================================================================
-- STEP 6: FIX RLS SECURITY FUNCTIONS (The root of the recursion error)
-- ============================================================================
-- Gets the company_id from the user's JWT, avoiding table queries.
CREATE OR REPLACE FUNCTION public.get_company_id_for_user()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT (auth.jwt()->>'app_metadata')::jsonb->>'company_id'
$$;

-- All other RLS policies will now use this safe function.
ALTER POLICY "Enable read access for company members" ON public.companies
USING (
  id = public.get_company_id_for_user()
);

ALTER POLICY "Enable access for company members" ON public.company_users
USING (
  company_id = public.get_company_id_for_user()
);


-- ============================================================================
-- VERIFICATION
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE 'Migration completed successfully!';
END $$;

COMMIT;
