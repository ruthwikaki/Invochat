-- Drop the function if it exists to avoid conflicts
DROP FUNCTION IF EXISTS public.create_company_and_user(text, text, text);

-- Create the function to handle new user and company creation in a single transaction
CREATE OR REPLACE FUNCTION public.create_company_and_user(
    company_name text,
    user_email text,
    user_password text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  new_user_id uuid;
  new_company_id uuid;
BEGIN
  -- 1. Create the company
  INSERT INTO public.companies (name)
  VALUES (company_name)
  RETURNING id INTO new_company_id;

  -- 2. Create the user in auth.users, passing company_id in metadata
  new_user_id := auth.uid() FROM auth.users WHERE email = user_email;
  IF new_user_id IS NULL THEN
    INSERT INTO auth.users (email, password, raw_app_meta_data)
    VALUES (user_email, crypt(user_password, gen_salt('bf')), jsonb_build_object('provider', 'email', 'providers', ARRAY['email'], 'company_id', new_company_id))
    RETURNING id INTO new_user_id;
  END IF;

  -- 3. Update the company with the owner_id
  UPDATE public.companies
  SET owner_id = new_user_id
  WHERE id = new_company_id;

  -- 4. Link the user to the company with 'Owner' role
  INSERT INTO public.company_users (user_id, company_id, role)
  VALUES (new_user_id, new_company_id, 'Owner');
  
  RETURN new_user_id;
END;
$$;
