-- Drop the old, problematic trigger and function
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();

-- Create a new, reliable RPC function to handle company and user creation in one transaction.
CREATE OR REPLACE FUNCTION public.create_company_and_user(
    p_company_name TEXT,
    p_user_email TEXT,
    p_user_password TEXT,
    p_email_redirect_to TEXT
)
RETURNS uuid AS $$
DECLARE
    new_user_id uuid;
    new_company_id uuid;
BEGIN
    -- 1. Create the user in auth.users and get the new user's ID
    new_user_id := auth.signup(
        p_user_email,
        p_user_password,
        p_email_redirect_to
    );

    -- 2. Create the company, owned by the new user
    INSERT INTO public.companies (name, owner_id)
    VALUES (p_company_name, new_user_id)
    RETURNING id INTO new_company_id;

    -- 3. Update the user's app_metadata with the new company_id
    -- This ensures the company_id is available for RLS and other logic.
    UPDATE auth.users
    SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id)
    WHERE id = new_user_id;

    RETURN new_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
