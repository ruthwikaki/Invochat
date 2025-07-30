
-- =================================================================
-- The only approved way to create a company and its initial user.
-- This function ensures atomic operations and proper permissions.
-- It will completely replace any previous, faulty versions.
-- =================================================================

-- Drop the old function if it exists, to prevent signature mismatch errors.
DROP FUNCTION IF EXISTS public.create_company_and_user(text, text, text);

-- Create the new, corrected function
CREATE OR REPLACE FUNCTION public.create_company_and_user(
    p_company_name text,
    p_user_email text,
    p_user_password text
)
RETURNS json
LANGUAGE plpgsql
-- SECURITY DEFINER is essential for this function to have the necessary permissions.
SECURITY DEFINER
-- Set a secure search path to prevent hijacking.
SET search_path = public, auth, extensions
AS $$
DECLARE
    new_company_id uuid;
    new_user_id uuid;
    result_json json;
BEGIN
    -- 1. Create the new company record.
    INSERT INTO public.companies (name)
    VALUES (p_company_name)
    RETURNING id INTO new_company_id;

    -- 2. Create the user in the auth.users table using the admin function.
    --    The company_id is passed in the metadata to be available for the trigger.
    SELECT auth.admin_create_user(
        json_build_object(
            'email', p_user_email,
            'password', p_user_password,
            'email_confirm', true, -- Auto-confirm the user for immediate login.
            'user_metadata', json_build_object(
                'company_id', new_company_id
            )
        )
    ) INTO new_user_id;

    -- 3. Link the new user to the company in the company_users table as 'Owner'.
    INSERT INTO public.company_users (company_id, user_id, role)
    VALUES (new_company_id, new_user_id, 'Owner');
    
    -- 4. Set the owner_id on the new company record.
    UPDATE public.companies
    SET owner_id = new_user_id
    WHERE id = new_company_id;

    -- 5. Create default settings for the new company.
    INSERT INTO public.company_settings (company_id)
    VALUES (new_company_id);

    -- 6. Build a success response to return.
    result_json := json_build_object(
      'success', true,
      'user_id', new_user_id,
      'company_id', new_company_id
    );

    RETURN result_json;

EXCEPTION
    WHEN OTHERS THEN
        -- If any step fails, the transaction is rolled back automatically.
        -- Log the error and return a detailed failure message.
        RAISE WARNING 'Error in create_company_and_user: %', SQLERRM;
        RETURN json_build_object(
          'success', false,
          'message', SQLERRM,
          'error_code', SQLSTATE
        );
END;
$$;

-- Grant execution permission to the 'anon' role, which is used for signup.
GRANT EXECUTE ON FUNCTION public.create_company_and_user(text, text, text) TO anon;

