-- This script fixes the user creation flow and cleans up the companies table.

-- Drop the existing function if it exists
DROP FUNCTION IF EXISTS public.handle_new_user();

-- Recreate the function with the correct logic
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  company_id_var uuid;
  user_company_name text;
BEGIN
  -- Extract company_name from the new user's metadata
  user_company_name := new.raw_app_meta_data->>'company_name';

  -- Create a new company for the user
  INSERT INTO public.companies (name)
  VALUES (user_company_name)
  RETURNING id INTO company_id_var;

  -- Associate the user with the new company as 'Owner'
  INSERT INTO public.company_users (user_id, company_id, role)
  VALUES (new.id, company_id_var, 'Owner');

  -- Update the user's app_metadata with the new company_id
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id_var)
  WHERE id = new.id;
  
  RETURN new;
END;
$$;

-- Drop the redundant owner_id column from the companies table if it exists
DO $$
BEGIN
  IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'companies' AND column_name = 'owner_id') THEN
    ALTER TABLE public.companies DROP COLUMN owner_id;
  END IF;
END $$;

-- Re-create the trigger to call the new function
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

