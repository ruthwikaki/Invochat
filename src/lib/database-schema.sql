-- ============================================================================
-- AUTH SYSTEM CLEANUP MIGRATION
-- ============================================================================
-- This migration removes the redundant public.users table and fixes all
-- foreign key relationships to properly reference auth.users as the single
-- source of truth for user identity.

BEGIN;

-- ============================================================================
-- STEP 1: AUDIT CURRENT STATE
-- ============================================================================
-- First, let's see what data we're working with

-- Check for any data in public.users that might need to be preserved
SELECT 
    pu.id as public_user_id,
    pu.company_id,
    pu.email as public_email,
    pu.role as public_role,
    pu.created_at as public_created,
    au.id as auth_user_id,
    au.email as auth_email,
    au.created_at as auth_created,
    cu.role as company_role
FROM public.users pu
LEFT JOIN auth.users au ON pu.id = au.id
LEFT JOIN public.company_users cu ON pu.id = cu.user_id AND pu.company_id = cu.company_id;

-- Check for orphaned records in company_users
SELECT cu.*, au.email 
FROM public.company_users cu
LEFT JOIN auth.users au ON cu.user_id = au.id
WHERE au.id IS NULL;

-- ============================================================================
-- STEP 2: DATA MIGRATION & CLEANUP
-- ============================================================================

-- Ensure all users in public.users exist in auth.users
-- If there are missing auth.users records, this needs manual intervention
DO $$
DECLARE
    missing_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO missing_count
    FROM public.users pu
    LEFT JOIN auth.users au ON pu.id = au.id
    WHERE au.id IS NULL;
    
    IF missing_count > 0 THEN
        RAISE EXCEPTION 'Found % users in public.users that do not exist in auth.users. Manual intervention required.', missing_count;
    END IF;
END $$;

-- Migrate any missing company_users relationships
-- This ensures every user in public.users has a corresponding company_users record
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
LEFT JOIN public.company_users cu ON pu.id = cu.user_id AND pu.company_id = cu.company_id
WHERE cu.user_id IS NULL
ON CONFLICT (company_id, user_id) DO NOTHING;

-- ============================================================================
-- STEP 3: UPDATE FOREIGN KEY REFERENCES
-- ============================================================================

-- Update all tables that currently reference public.users to reference auth.users
-- Most should already be correct, but let's ensure consistency

-- Fix any foreign key constraints that might be pointing to public.users
-- (Note: We'll drop and recreate proper constraints later)

-- Update audit_log table to ensure user_id references auth.users
-- (This should already be correct, but let's verify)
UPDATE public.audit_log 
SET user_id = NULL 
WHERE user_id IS NOT NULL 
AND user_id NOT IN (SELECT id FROM auth.users);

-- Update conversations table
UPDATE public.conversations 
SET user_id = NULL 
WHERE user_id IS NOT NULL 
AND user_id NOT IN (SELECT id FROM auth.users);

-- Update export_jobs table
UPDATE public.export_jobs 
SET requested_by_user_id = NULL 
WHERE requested_by_user_id IS NOT NULL 
AND requested_by_user_id NOT IN (SELECT id FROM auth.users);

-- Update feedback table
UPDATE public.feedback 
SET user_id = NULL 
WHERE user_id IS NOT NULL 
AND user_id NOT IN (SELECT id FROM auth.users);

-- Update imports table
UPDATE public.imports 
SET created_by = NULL 
WHERE created_by IS NOT NULL 
AND created_by NOT IN (SELECT id FROM auth.users);

-- Update refunds table
UPDATE public.refunds 
SET created_by_user_id = NULL 
WHERE created_by_user_id IS NOT NULL 
AND created_by_user_id NOT IN (SELECT id FROM auth.users);

-- ============================================================================
-- STEP 4: DROP REDUNDANT public.users TABLE
-- ============================================================================

-- First, drop any foreign key constraints that reference public.users
-- (We'll check if any exist)
DO $$
DECLARE
    constraint_record RECORD;
BEGIN
    FOR constraint_record IN
        SELECT tc.constraint_name, tc.table_name, tc.table_schema
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu 
            ON tc.constraint_name = kcu.constraint_name
        JOIN information_schema.constraint_column_usage ccu 
            ON tc.constraint_name = ccu.constraint_name
        WHERE ccu.table_name = 'users' 
        AND ccu.table_schema = 'public'
        AND tc.constraint_type = 'FOREIGN KEY'
    LOOP
        EXECUTE format('ALTER TABLE %I.%I DROP CONSTRAINT %I',
            constraint_record.table_schema,
            constraint_record.table_name,
            constraint_record.constraint_name);
        RAISE NOTICE 'Dropped constraint % from %.%', 
            constraint_record.constraint_name,
            constraint_record.table_schema,
            constraint_record.table_name;
    END LOOP;
END $$;

-- Now we can safely drop the public.users table
DROP TABLE IF EXISTS public.users CASCADE;

-- ============================================================================
-- STEP 5: CREATE PROPER FOREIGN KEY CONSTRAINTS
-- ============================================================================

-- Add proper foreign key constraints pointing to auth.users

-- company_users should reference auth.users
ALTER TABLE public.company_users 
ADD CONSTRAINT company_users_user_id_fkey 
FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- companies.owner_id should reference auth.users
ALTER TABLE public.companies 
ADD CONSTRAINT companies_owner_id_fkey 
FOREIGN KEY (owner_id) REFERENCES auth.users(id) ON DELETE SET NULL;

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
-- STEP 6: ADD ESSENTIAL INDEXES AND CONSTRAINTS
-- ============================================================================

-- Ensure email uniqueness in auth.users (should already exist, but let's be sure)
CREATE UNIQUE INDEX IF NOT EXISTS auth_users_email_unique 
ON auth.users(email) WHERE email IS NOT NULL;

-- Add indexes for frequently queried auth fields
CREATE INDEX IF NOT EXISTS auth_users_created_at_idx ON auth.users(created_at);
CREATE INDEX IF NOT EXISTS auth_users_last_sign_in_at_idx ON auth.users(last_sign_in_at);

-- Add indexes for company_users join table
CREATE INDEX IF NOT EXISTS company_users_user_id_idx ON public.company_users(user_id);
CREATE INDEX IF NOT EXISTS company_users_company_id_idx ON public.company_users(company_id);

-- Ensure unique constraint on company_users (user can only have one role per company)
CREATE UNIQUE INDEX IF NOT EXISTS company_users_unique 
ON public.company_users(company_id, user_id);

-- ============================================================================
-- STEP 7: CREATE HELPFUL VIEWS FOR USER-COMPANY RELATIONSHIPS
-- ============================================================================

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

-- ============================================================================
-- STEP 8: ADD ROW LEVEL SECURITY HELPERS
-- ============================================================================

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

-- Create a helper function to check if user belongs to company
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

-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================

-- Verify the migration was successful
DO $$
BEGIN
    -- Check that public.users table no longer exists
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'users') THEN
        RAISE EXCEPTION 'public.users table still exists!';
    END IF;
    
    -- Check that all foreign keys are properly set up
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE table_name = 'company_users' 
        AND constraint_name = 'company_users_user_id_fkey'
    ) THEN
        RAISE EXCEPTION 'company_users foreign key constraint missing!';
    END IF;
    
    RAISE NOTICE 'Migration completed successfully!';
END $$;

COMMIT;

-- ============================================================================
-- POST-MIGRATION VERIFICATION QUERIES
-- ============================================================================

-- Run these after the migration to verify everything is working:

-- 1. Check all users have proper company relationships
SELECT 'Users without company relationships' as check_type, COUNT(*) as count
FROM auth.users au
LEFT JOIN public.company_users cu ON au.id = cu.user_id
WHERE cu.user_id IS NULL AND au.deleted_at IS NULL;

-- 2. Check all company_users reference valid auth.users
SELECT 'Invalid company_users references' as check_type, COUNT(*) as count
FROM public.company_users cu
LEFT JOIN auth.users au ON cu.user_id = au.id
WHERE au.id IS NULL;

-- 3. Test the new views
SELECT 'Total user-company relationships' as check_type, COUNT(*) as count
FROM public.user_companies;

-- 4. Check foreign key constraints
SELECT 
    tc.table_name,
    tc.constraint_name,
    ccu.table_name AS foreign_table_name,
    ccu.column_name AS foreign_column_name
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu 
    ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage ccu 
    ON tc.constraint_name = ccu.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY'
AND (ccu.table_name = 'users' AND ccu.table_schema = 'auth')
ORDER BY tc.table_name;
