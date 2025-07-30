-- Add the owner_id column to the companies table
ALTER TABLE public.companies
ADD COLUMN IF NOT EXISTS owner_id UUID REFERENCES auth.users(id);

-- Drop the old function if it exists to avoid conflicts
DROP FUNCTION IF EXISTS public.handle_new_user();

-- Create a trigger function to populate the new user's profile and company
CREATE OR REPLACE FUNCTION public.create_company_and_user()
RETURNS TRIGGER AS $$
DECLARE
  company_id_to_set uuid;
  user_role public.company_role := 'Owner'; -- New users are owners by default.
BEGIN
  -- Create a new company for the new user.
  INSERT INTO public.companies (name, owner_id)
  VALUES (new.raw_user_meta_data->>'company_name', new.id)
  RETURNING id INTO company_id_to_set;

  -- Add the user to the company_users table.
  INSERT INTO public.company_users (user_id, company_id, role)
  VALUES (new.id, company_id_to_set, user_role);

  -- Update the user's app_metadata with the new company_id.
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id_to_set)
  WHERE id = new.id;
  
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create the trigger to fire the function after a new user is created in auth.users
CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.create_company_and_user();
