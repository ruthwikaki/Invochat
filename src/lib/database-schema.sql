--
-- This script only contains the necessary function update to fix the infinite recursion error.
-- It will not alter your existing tables or other database objects.
--
-- Name: get_company_id_for_user(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.get_company_id_for_user(p_user_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- This function now safely retrieves the company_id directly from the
  -- user's authentication token (JWT), which avoids the infinite recursion
  -- issue caused by querying the company_users table within a policy that
  -- also uses this function.
  RETURN (auth.jwt() -> 'app_metadata' ->> 'company_id')::uuid;
END;
$$;


ALTER FUNCTION public.get_company_id_for_user(p_user_id uuid) OWNER TO postgres;

-- Re-apply the security policy for the company_users table to ensure it uses the updated function.
-- This ensures that users can only see their own company's user list.
DROP POLICY IF EXISTS "Enable read access for company members" ON public.company_users;
CREATE POLICY "Enable read access for company members"
ON public.company_users
FOR SELECT
USING (
  (public.get_company_id_for_user(auth.uid()) = company_id)
);