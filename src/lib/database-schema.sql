-- Alter the function to use auth.jwt() to prevent recursion
CREATE OR REPLACE FUNCTION get_company_id_for_user(p_user_id uuid)
RETURNS uuid AS $$
DECLARE
    company_id_from_jwt uuid;
BEGIN
    -- This is the most reliable way to get the company_id in RLS policies
    -- as it doesn't query other tables, thus avoiding recursion.
    company_id_from_jwt := (auth.jwt() -> 'app_metadata' ->> 'company_id')::uuid;

    IF company_id_from_jwt IS NOT NULL THEN
        RETURN company_id_from_jwt;
    END IF;

    -- Fallback for scenarios where the JWT might not be populated yet,
    -- but this is less ideal for RLS and should be avoided in policies.
    -- The primary fix is relying on the JWT.
    RETURN (SELECT company_id FROM public.company_users WHERE user_id = p_user_id LIMIT 1);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
