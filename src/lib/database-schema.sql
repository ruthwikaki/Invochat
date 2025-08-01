-- ============================================================================
-- AUTH SYSTEM CLEANUP MIGRATION
-- ============================================================================
-- This migration removes the redundant public.users table and fixes all
-- foreign key relationships to properly reference auth.users as the single
-- source of truth for user identity.

BEGIN;

-- ============================================================================
-- STEP 1: DROP EXISTING CONSTRAINTS FOR IDEMPOTENCY
-- ============================================================================
-- Drop potentially conflicting constraints first to ensure the script is re-runnable.

DO $$
DECLARE
    constraint_name_text TEXT;
BEGIN
    -- Drop constraint on companies table if it exists
    SELECT constraint_name INTO constraint_name_text
    FROM information_schema.table_constraints
    WHERE table_schema = 'public' AND table_name = 'companies' AND constraint_name = 'companies_owner_id_fkey';
    
    IF constraint_name_text IS NOT NULL THEN
        EXECUTE 'ALTER TABLE public.companies DROP CONSTRAINT IF EXISTS ' || quote_ident(constraint_name_text);
        RAISE NOTICE 'Dropped existing constraint: % on public.companies', constraint_name_text;
    END IF;

    -- Drop constraint on company_users table if it exists
    SELECT constraint_name INTO constraint_name_text
    FROM information_schema.table_constraints
    WHERE table_schema = 'public' AND table_name = 'company_users' AND constraint_name = 'company_users_user_id_fkey';
    
    IF constraint_name_text IS NOT NULL THEN
        EXECUTE 'ALTER TABLE public.company_users DROP CONSTRAINT IF EXISTS ' || quote_ident(constraint_name_text);
        RAISE NOTICE 'Dropped existing constraint: % on public.company_users', constraint_name_text;
    END IF;
END $$;


-- ============================================================================
-- STEP 2: AUDIT AND PREPARE DATA
-- ============================================================================

-- If the public.users table exists, migrate its data. If not, this section will be skipped.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'users') THEN
        -- Check for orphaned users in public.users that aren't in auth.users
        IF EXISTS (SELECT 1 FROM public.users pu LEFT JOIN auth.users au ON pu.id = au.id WHERE au.id IS NULL) THEN
            RAISE EXCEPTION 'Found users in public.users that do not exist in auth.users. Manual intervention required to prevent data loss.';
        END IF;

        -- Migrate any missing company_users relationships from the old public.users table
        RAISE NOTICE 'Migrating roles from public.users to public.company_users...';
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
            SELECT 1 FROM public.company_users cu WHERE cu.user_id = pu.id AND cu.company_id = pu.company_id
        )
        ON CONFLICT (company_id, user_id) DO NOTHING;
    ELSE
        RAISE NOTICE 'public.users table not found, skipping data migration.';
    END IF;
END $$;


-- ============================================================================
-- STEP 3: DROP REDUNDANT public.users TABLE
-- ============================================================================

RAISE NOTICE 'Dropping public.users table if it exists...';
DROP TABLE IF EXISTS public.users;

-- ============================================================================
-- STEP 4: RE-CREATE PROPER FOREIGN KEY CONSTRAINTS
-- ============================================================================
-- These now safely execute since we dropped potential conflicts in Step 1.

RAISE NOTICE 'Creating foreign key constraints pointing to auth.users...';

-- companies.owner_id should reference auth.users
ALTER TABLE public.companies 
ADD CONSTRAINT companies_owner_id_fkey 
FOREIGN KEY (owner_id) REFERENCES auth.users(id) ON DELETE SET NULL;

-- company_users should reference auth.users
ALTER TABLE public.company_users 
ADD CONSTRAINT company_users_user_id_fkey 
FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- audit_log should reference auth.users
ALTER TABLE public.audit_log 
ADD CONSTRAINT audit_log_user_id_fkey 
FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL;

-- conversations should reference auth.users
ALTER TABLE public.conversations 
ADD CONSTRAINT conversations_user_id_fkey 
FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- export_jobs should reference auth.users
ALTER TABLE public.export_jobs 
ADD CONSTRAINT export_jobs_requested_by_user_id_fkey 
FOREIGN KEY (requested_by_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;

-- feedback should reference auth.users
ALTER TABLE public.feedback 
ADD CONSTRAINT feedback_user_id_fkey 
FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- imports should reference auth.users
ALTER TABLE public.imports 
ADD CONSTRAINT imports_created_by_fkey 
FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

-- refunds should reference auth.users
ALTER TABLE public.refunds 
ADD CONSTRAINT refunds_created_by_user_id_fkey 
FOREIGN KEY (created_by_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;


-- ============================================================================
-- STEP 5: ADD ESSENTIAL INDEXES
-- ============================================================================
RAISE NOTICE 'Creating indexes for performance...';

-- Add indexes for frequently queried auth fields
CREATE INDEX IF NOT EXISTS auth_users_created_at_idx ON auth.users(created_at);
CREATE INDEX IF NOT EXISTS auth_users_last_sign_in_at_idx ON auth.users(last_sign_in_at);

-- Add indexes for company_users join table
CREATE INDEX IF NOT EXISTS company_users_user_id_idx ON public.company_users(user_id);
CREATE INDEX IF NOT EXISTS company_users_company_id_idx ON public.company_users(company_id);

-- Ensure unique constraint on company_users (user can only have one role per company)
-- First drop if it exists to make it re-runnable
ALTER TABLE public.company_users DROP CONSTRAINT IF EXISTS company_users_unique;
ALTER TABLE public.company_users ADD CONSTRAINT company_users_unique UNIQUE (company_id, user_id);


-- ============================================================================
-- STEP 6: RECREATE HELPER VIEWS AND FUNCTIONS
-- ============================================================================

RAISE NOTICE 'Recreating helper views and functions...';

-- Create a view that makes it easy to query user-company relationships
CREATE OR REPLACE VIEW public.user_companies AS
SELECT 
    au.id as user_id,
    au.email,
    au.created_at as user_created_at,
    au.last_sign_in_at,
    c.id as company_id,
    c.name as company_name,
    cu.role as company_role,
    c.created_at as company_created_at
FROM auth.users au
JOIN public.company_users cu ON au.id = cu.user_id
JOIN public.companies c ON cu.company_id = c.id
WHERE au.deleted_at IS NULL;

-- Create a view for company owners
CREATE OR REPLACE VIEW public.company_owners AS
SELECT 
    c.id as company_id,
    c.name as company_name,
    au.id as owner_id,
    au.email as owner_email,
    c.created_at
FROM public.companies c
JOIN auth.users au ON c.owner_id = au.id
WHERE au.deleted_at IS NULL;

-- Create a helper function to check if user belongs to company for RLS policies
CREATE OR REPLACE FUNCTION public.user_belongs_to_company(user_uuid uuid, company_uuid uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
    SELECT EXISTS(
        SELECT 1 
        FROM public.company_users cu
        WHERE cu.user_id = user_uuid 
        AND cu.company_id = company_uuid
    );
$$;

-- Create a helper function to get user's companies
CREATE OR REPLACE FUNCTION public.get_user_companies(user_uuid uuid)
RETURNS TABLE(company_id uuid, role company_role)
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
    SELECT cu.company_id, cu.role
    FROM public.company_users cu
    WHERE cu.user_id = user_uuid;
$$;


DO $$
BEGIN
    RAISE NOTICE 'Migration script finished.';
END $$;

COMMIT;
