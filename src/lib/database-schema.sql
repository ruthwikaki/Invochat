-- This function is called by a trigger when a new user signs up.
-- It creates a new company for the user and assigns them as the owner.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  new_company_id uuid;
BEGIN
  -- Generate new company ID
  new_company_id := gen_random_uuid();
  
  -- Create company
  INSERT INTO public.companies (id, name, owner_id, created_at)
  VALUES (
    new_company_id,
    COALESCE(NEW.raw_user_meta_data->>'company_name', NEW.email || '''s Company'),
    NEW.id,
    now()
  );

  -- Create user record
  INSERT INTO public.company_users (user_id, company_id, role)
  VALUES (
    NEW.id,
    new_company_id,
    'Owner'
  );

  -- Create company settings with defaults
  INSERT INTO public.company_settings (
    company_id
  )
  VALUES (
    new_company_id
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Log the error but don't fail the user creation
  RAISE LOG 'Error in handle_new_user for user %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to call the function when a new user is created in the auth.users table
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Other database objects...
-- (The rest of your original schema would be here, but is omitted as requested)
