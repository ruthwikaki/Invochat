-- This script corrects the user creation trigger and function to properly associate a new user with a company.

-- First, drop the dependent trigger on the auth.users table.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Now it's safe to drop the function.
DROP FUNCTION IF EXISTS public.handle_new_user();

-- Recreate the function with the correct logic.
-- This version correctly inserts into company_users and sets the role to 'Owner'.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  new_company_id uuid;
BEGIN
  -- Create a new company for the new user.
  INSERT INTO public.companies (name)
  VALUES (new.raw_app_meta_data->>'company_name')
  RETURNING id INTO new_company_id;

  -- Link the new user to the new company as 'Owner'.
  INSERT INTO public.company_users (user_id, company_id, role)
  VALUES (new.id, new_company_id, 'Owner');
  
  -- Update the user's app_metadata with the new company_id.
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id)
  WHERE id = new.id;
  
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recreate the trigger to call the new function.
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Finally, remove the redundant owner_id column from the companies table.
ALTER TABLE public.companies DROP COLUMN IF EXISTS owner_id;
