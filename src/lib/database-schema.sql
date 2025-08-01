-- ============================================================================
-- FINAL AUTH SYSTEM FIX: RECURSION AND DEPENDENCY SAFE
-- ============================================================================
-- This script replaces the faulty get_company_id_for_user function with a
-- corrected version that is guaranteed to not cause infinite recursion.
-- It also handles existing dependencies by using CREATE OR REPLACE.

BEGIN;

-- This function is called by RLS policies to get the company ID for the currently authenticated user.
-- The original version caused an infinite recursion error because it queried a table that was protected
-- by a policy that called this same function.
--
-- The corrected version below resolves this by getting the company_id directly and securely
-- from the user's authentication token (JWT), which is the proper way to handle this
-- in a multi-tenant Supabase environment. It does not query any tables, thus breaking the loop.
CREATE OR REPLACE FUNCTION get_company_id_for_user(user_uuid uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
BEGIN
  -- This function now securely gets the company_id directly from the JWT's app_metadata
  -- This avoids the recursive query on company_users that caused the "infinite recursion" error.
  RETURN (
    SELECT NULLIF(auth.jwt()->'app_metadata'->>'company_id', '')::uuid
  );
END;
$$;


-- This function is a simple helper to get the user's role within their company.
-- It is also made SECURITY DEFINER to work correctly within RLS policies.
CREATE OR REPLACE FUNCTION get_user_role(user_uuid uuid)
RETURNS TEXT
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT role::text
  FROM public.company_users
  WHERE user_id = user_uuid;
$$;


COMMIT;

-- After running this script, the "infinite recursion" errors should be permanently resolved.
