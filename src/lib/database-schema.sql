-- =================================================================
-- MINIMAL SIGNUP FIX SCRIPT
-- This script only replaces the faulty user creation function.
-- =================================================================

-- Drop the old, incorrect function if it exists to prevent errors
DROP FUNCTION IF EXISTS public.create_company_and_user(text, text, text);

-- Create the new, corrected function
CREATE OR REPLACE FUNCTION public.create_company_and_user(
    company_name text,
    user_email text,
    user_password text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    new_company_id uuid;
    new_user_id uuid;
    result json;
BEGIN
    -- 1. Create the company first
    INSERT INTO public.companies (name)
    VALUES (company_name)
    RETURNING id INTO new_company_id;

    -- 2. Create the user using auth.signup, passing company_id in metadata.
    -- This is the key change to fix the error.
    SELECT auth.signup(
        json_build_object(
            'email', user_email,
            'password', user_password,
            'options', json_build_object(
                'data', json_build_object(
                    'company_id', new_company_id,
                    'company_name', company_name
                )
            )
        )
    ) INTO new_user_id;

    -- 3. Link the new user to the company with the 'Owner' role
    INSERT INTO public.company_users (user_id, company_id, role)
    VALUES (new_user_id, new_company_id, 'Owner');

    -- 4. Set the owner_id on the companies table
    UPDATE public.companies
    SET owner_id = new_user_id
    WHERE id = new_company_id;

    -- 5. Return a success message
    result := json_build_object(
        'success', true,
        'user_id', new_user_id,
        'company_id', new_company_id
    );
    RETURN result;

EXCEPTION WHEN OTHERS THEN
    -- If any step fails, the transaction will be rolled back.
    -- Return a structured error message.
    RETURN json_build_object(
        'success', false,
        'message', SQLERRM,
        'error_code', SQLSTATE
    );
END;
$$;

-- Grant permissions to the anon role so it can be called from the signup form
GRANT EXECUTE ON FUNCTION public.create_company_and_user(text, text, text) TO anon;
