
-- Drop the existing function if it exists, to avoid "cannot change return type" errors.
DROP FUNCTION IF EXISTS public.create_company_and_user(text, text, text);

-- Create the new, corrected function for handling user signup.
CREATE OR REPLACE FUNCTION public.create_company_and_user(
    p_company_name TEXT,
    p_user_email TEXT,
    p_user_password TEXT
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER -- <<< This is critical for allowing the function to create users in the auth schema.
SET search_path = public
AS $$
DECLARE
    new_company_id uuid;
    new_user_id uuid;
BEGIN
    -- Step 1: Create the company first.
    INSERT INTO public.companies (name)
    VALUES (p_company_name)
    RETURNING id INTO new_company_id;

    -- Step 2: Create the user in the auth schema, embedding the company_id in the metadata.
    -- This ensures the trigger `on_auth_user_created` has the company_id when it runs.
    SELECT auth.admin_create_user(
        p_user_email,
        p_user_password,
        jsonb_build_object(
            'company_id', new_company_id,
            'company_name', p_company_name,
            'role', 'Owner'
        )
    ) INTO new_user_id;

    -- The trigger `on_auth_user_created` will handle inserting into `public.users` and `public.company_users`.

    -- Step 3: Update the company with the owner's ID.
    UPDATE public.companies
    SET owner_id = new_user_id
    WHERE id = new_company_id;
    
    RETURN new_user_id;
END;
$$;
