
-- This function is triggered when a new user signs up.
-- It handles creating a new company for the user and linking them together.
-- This version corrects a race condition where the user was created in `public.users`
-- by Supabase's mirror before a company_id was available, causing a NOT NULL violation.
-- This is achieved by creating the user record in `public.users` manually within this function,
-- which now takes precedence over the default Supabase behavior.

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_company_id uuid;
  user_company_name TEXT := new.raw_app_meta_data->>'company_name';
  user_email TEXT := new.email;
  user_role TEXT := 'Owner'; -- New users signing up are the owners of their company
BEGIN
  -- Create a new company for the user
  INSERT INTO public.companies (name, owner_id)
  VALUES (user_company_name, new.id)
  RETURNING id INTO new_company_id;

  -- Create a corresponding entry in the public.users table
  -- This is the key change: we now manually create the public user record,
  -- ensuring the `company_id` is set correctly from the start.
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (new.id, new_company_id, user_email, user_role);

  -- Link the user to the company in the company_users table
  INSERT INTO public.company_users (user_id, company_id, role)
  VALUES (new.id, new_company_id, user_role::company_role);

  -- Update the user's custom claims in the auth table
  UPDATE auth.users
  SET raw_app_meta_data = jsonb_set(
    raw_app_meta_data,
    '{company_id}',
    to_jsonb(new_company_id)
  )
  WHERE id = new.id;

  RETURN new;
END;
$$;

-- Ensure the trigger is still in place
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Grant usage on the sequence for the po_number generation
GRANT USAGE, SELECT ON SEQUENCE public.purchase_orders_po_number_seq TO service_role;
