-- Fix Database Function Overloading Issues
-- Run this script in your Supabase SQL Editor to resolve the check_user_permission function conflicts

-- 1. Drop the old function with company_role parameter type to resolve overloading
DROP FUNCTION IF EXISTS public.check_user_permission(uuid, public.company_role);

-- 2. Create/Replace the function with TEXT parameter to avoid overloading conflicts
CREATE OR REPLACE FUNCTION public.check_user_permission(p_user_id uuid, p_required_role text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    user_role company_role;
    role_hierarchy_map jsonb := '{
        "Member": 1,
        "Admin": 2,
        "Owner": 3
    }';
    user_level int;
    required_level int;
BEGIN
    -- Get the user's role from company_users table
    SELECT "role" INTO user_role FROM company_users WHERE user_id = p_user_id;

    -- If user not found in company_users, return false
    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    -- Get numeric levels for comparison
    user_level := (role_hierarchy_map->>user_role::text)::int;
    required_level := (role_hierarchy_map->>p_required_role)::int;

    -- Return true if user has required level or higher
    RETURN user_level >= required_level;
END;
$$;

-- 3. Grant execute permissions
GRANT EXECUTE ON FUNCTION public.check_user_permission(uuid, text) TO "authenticated";

-- 4. Add comment for documentation
COMMENT ON FUNCTION public.check_user_permission(uuid, text) IS 'Checks if a user has a specific role or higher within their company. Uses text parameter to avoid function overloading conflicts.';

-- 5. Verify the function exists and works
SELECT 'Function check_user_permission created successfully' as status;
