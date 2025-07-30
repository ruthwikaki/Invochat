-- Migration: Add User Signup Trigger
-- Version: 20250730_user_signup
-- Description: Creates the trigger function to automatically provision a new company for a new user.

BEGIN;

-- Create the function to be called by the trigger.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
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
$$;

-- Create the trigger that fires after a new user is inserted into auth.users.
CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

COMMIT;

-- Inform the user that the migration is complete.
RAISE NOTICE 'Migration 20250730_user_signup applied successfully.';
