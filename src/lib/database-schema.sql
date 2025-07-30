
-- =================================================================
-- Final Signup Function
-- This script replaces the user and company creation function
-- with a corrected version that uses the proper Supabase auth method
-- and correct parameter names to match the application's RPC call.
-- =================================================================

-- Drop the old, flawed function if it exists to ensure a clean slate.
DROP FUNCTION IF EXISTS public.create_company_and_user(text, text, text);

-- Create the corrected function
CREATE OR REPLACE FUNCTION public.create_company_and_user(
    p_company_name text,
    p_user_email text,
    p_user_password text
)
RETURNS json
LANGUAGE plpgsql
-- SECURITY DEFINER is crucial for allowing this function to create users in the 'auth' schema.
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    new_company_id uuid;
    new_user_id uuid;
    result json;
BEGIN
    -- This transactional block ensures that if any step fails, all previous steps are rolled back.
    BEGIN
        -- 1. Create the company first.
        INSERT INTO public.companies (name)
        VALUES (p_company_name)
        RETURNING id INTO new_company_id;

        -- 2. Create the user in auth.users via auth.signup, passing company_id in metadata.
        -- This is the correct, modern way to create users in Supabase from SQL.
        SELECT auth.signup(
            p_user_email,
            p_user_password,
            jsonb_build_object('company_id', new_company_id)
        ) INTO new_user_id;

        -- 3. Link the user and company in the pivot table with the 'Owner' role.
        INSERT INTO public.company_users (company_id, user_id, role)
        VALUES (new_company_id, new_user_id, 'Owner');
        
        -- 4. Update the company's owner_id field.
        UPDATE public.companies
        SET owner_id = new_user_id
        WHERE id = new_company_id;

        -- 5. Create a default settings entry for the new company.
        INSERT INTO public.company_settings (company_id)
        VALUES (new_company_id);

        -- Build a success response.
        result := json_build_object(
            'success', true,
            'company_id', new_company_id,
            'user_id', new_user_id,
            'message', 'Company and user created successfully.'
        );

        RETURN result;

    EXCEPTION WHEN OTHERS THEN
        -- If any error occurs, log it and return a failure message.
        RAISE WARNING 'Error creating company/user: %', SQLERRM;
        RETURN json_build_object(
            'success', false,
            'message', SQLERRM,
            'error_code', SQLSTATE
        );
    END;
END;
$$;

-- Grant execute permissions to the anon and authenticated roles so it can be called from the app.
GRANT EXECUTE ON FUNCTION public.create_company_and_user(text, text, text) TO anon, authenticated;

-- Call this function to ensure Supabase recognizes the changes immediately.
NOTIFY pgrst, 'reload schema';
