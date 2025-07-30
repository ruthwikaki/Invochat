-- This script is designed to be idempotent. 
-- You can run it multiple times without causing errors.

-- Drop the old, problematic function and its trigger if they exist.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();

-- Creates a new company and a new user, then links them as the owner.
-- This is called from the signup server action.
CREATE OR REPLACE FUNCTION public.create_company_and_user(
    p_company_name text,
    p_user_email text,
    p_user_password text
)
RETURNS uuid AS $$
DECLARE
    new_company_id uuid;
    new_user_id uuid;
BEGIN
    -- 1. Create the company first.
    INSERT INTO public.companies (name)
    VALUES (p_company_name)
    RETURNING id INTO new_company_id;

    -- 2. Create the user in auth.users, passing the new company_id in the metadata.
    --    The security definer allows this function to create users in the auth schema.
    INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, recovery_token, recovery_sent_at, last_sign_in_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, phone)
    VALUES (
        '00000000-0000-0000-0000-000000000000',
        uuid_generate_v4(),
        'authenticated',
        'authenticated',
        p_user_email,
        crypt(p_user_password, gen_salt('bf')),
        now(),
        '',
        now(),
        now(),
        jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email'), 'company_id', new_company_id),
        '{}'::jsonb,
        now(),
        now(),
        ''
    )
    RETURNING id INTO new_user_id;

    -- 3. Link the new user to the new company as 'Owner'.
    INSERT INTO public.company_users (user_id, company_id, role)
    VALUES (new_user_id, new_company_id, 'Owner');
    
    -- 4. Update the company with the owner's ID
    UPDATE public.companies SET owner_id = new_user_id WHERE id = new_company_id;

    -- Return the new user's ID
    RETURN new_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
