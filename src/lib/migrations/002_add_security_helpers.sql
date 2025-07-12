-- This migration adds the required security helper functions to the database.
-- It is idempotent and can be safely run multiple times.

-- Helper function to check if the current user is a member of a given company.
CREATE OR REPLACE FUNCTION is_member_of_company(p_company_id uuid)
RETURNS boolean AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND company_id = p_company_id AND deleted_at IS NULL
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
ALTER FUNCTION public.is_member_of_company(uuid) SET search_path = 'public';


-- Helper function to get the role of the current user for their company.
CREATE OR REPLACE FUNCTION get_my_role(p_company_id uuid)
RETURNS public.user_role AS $$
DECLARE
    v_role public.user_role;
BEGIN
    SELECT role INTO v_role FROM public.users
    WHERE id = auth.uid() AND company_id = p_company_id AND deleted_at IS NULL;
    RETURN v_role;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
ALTER FUNCTION public.get_my_role(uuid) SET search_path = 'public';
