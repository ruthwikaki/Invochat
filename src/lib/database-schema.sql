-- ============================================================================
-- TARGETED FUNCTION FIX: Resolve "infinite recursion" error
-- ============================================================================
-- This script replaces ONLY the function causing the error. It does not
-- alter any tables or other parts of the database schema.

BEGIN;

-- Drop the existing function if it exists to ensure a clean slate.
DROP FUNCTION IF EXISTS public.get_company_id_for_user(uuid);

-- Recreate the function with the corrected logic.
-- This version gets the company_id directly from the user's JWT session data,
-- which avoids the recursive query on the company_users table.
CREATE OR REPLACE FUNCTION public.get_company_id_for_user(p_user_id uuid)
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT (auth.jwt()->'app_metadata'->>'company_id')::uuid;
$$;


-- Grant execution rights to the authenticated role
GRANT EXECUTE ON FUNCTION public.get_company_id_for_user(uuid) TO authenticated;

COMMIT;

-- After running this script, the infinite recursion error will be resolved.
-- No user data will be affected.
