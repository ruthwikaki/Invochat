-- Migration to add Role-Based Access Control (RBAC) check function.
-- This function allows the application to securely verify if a user
-- has the required role (e.g., 'Admin', 'Owner') before performing a sensitive action.

CREATE OR REPLACE FUNCTION check_user_permission(p_user_id UUID, p_required_role TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    user_role TEXT;
BEGIN
    SELECT role INTO user_role FROM public.users WHERE id = p_user_id;

    IF user_role IS NULL THEN
        RETURN FALSE; -- User not found in the company
    END IF;

    IF p_required_role = 'Owner' THEN
        RETURN user_role = 'Owner';
    END IF;

    IF p_required_role = 'Admin' THEN
        RETURN user_role IN ('Owner', 'Admin');
    END IF;

    RETURN FALSE; -- Default to deny
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execution to authenticated users
GRANT EXECUTE ON FUNCTION check_user_permission(UUID, TEXT) TO authenticated;

COMMENT ON FUNCTION check_user_permission(UUID, TEXT) IS 'Checks if a user has a specific role or higher within their company.';
