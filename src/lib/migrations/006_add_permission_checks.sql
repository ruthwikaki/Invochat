-- This function checks if a user has a specific role within their company.
-- It's a security-critical function to prevent privilege escalation.
CREATE OR REPLACE FUNCTION check_user_permission(p_user_id UUID, p_required_role company_role)
RETURNS BOOLEAN AS $$
DECLARE
    user_role company_role;
BEGIN
    SELECT role INTO user_role
    FROM company_users cu
    WHERE cu.user_id = p_user_id;

    IF user_role IS NULL THEN
        RETURN FALSE; -- User not found in any company
    END IF;

    -- Owners can do anything Admins can do.
    IF p_required_role = 'Admin' AND (user_role = 'Owner' OR user_role = 'Admin') THEN
        RETURN TRUE;
    END IF;

    RETURN user_role = p_required_role;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;