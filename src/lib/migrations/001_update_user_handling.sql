-- This script updates the user creation trigger to be more robust
-- and adds a unique index to prevent a user from belonging to multiple companies.

BEGIN;

-- Drop the existing trigger if it exists, to be replaced by the improved version.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Create or replace the function to handle new user setup.
-- This version includes an advisory lock to prevent race conditions
-- and is idempotent, meaning it won't fail if run multiple times for the same user.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_name text;
  v_lock_key bigint;
BEGIN
  -- Use an advisory lock per user to prevent concurrent trigger re-entry.
  -- This is crucial for handling scenarios like fast, repeated sign-up attempts.
  v_lock_key := ('x' || substr(md5(new.id::text), 1, 16))::bit(64)::bigint;
  perform pg_advisory_xact_lock(v_lock_key);

  -- If the user is already associated with a company, do nothing.
  SELECT cu.company_id INTO v_company_id
  FROM public.company_users cu
  WHERE cu.user_id = new.id
  LIMIT 1;

  IF v_company_id IS NOT NULL THEN
    RETURN new;
  END IF;

  -- Determine the company name from user metadata or generate a default.
  v_name := coalesce(new.raw_user_meta_data->>'company_name',
                     'Company for ' || coalesce(new.email, new.id::text));

  -- Create a new company for the user.
  INSERT INTO public.companies (name, owner_id)
  VALUES (v_name, new.id)
  RETURNING id INTO v_company_id;

  -- Create a default settings entry for the new company.
  INSERT INTO public.company_settings (company_id)
  VALUES (v_company_id)
  ON CONFLICT (company_id) DO NOTHING;

  -- Create the association between the user and their new company.
  INSERT INTO public.company_users (user_id, company_id, role)
  VALUES (new.id, v_company_id, 'Owner')
  ON CONFLICT DO NOTHING; -- Safe against concurrent inserts.

  -- Update the user's secure app_metadata with the new company_id.
  UPDATE auth.users
     SET raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb)
                           || jsonb_build_object('company_id', v_company_id)
   WHERE id = new.id;

  RETURN new;
END;
$$;

-- Ensure the function is owned by the postgres role to have sufficient permissions.
ALTER FUNCTION public.handle_new_user() OWNER TO postgres;

-- Recreate the trigger on the auth.users table.
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Add a unique index to enforce that a user can only be associated with one company.
-- This is a critical data integrity constraint.
CREATE UNIQUE INDEX IF NOT EXISTS ux_company_users_user_id
  ON public.company_users (user_id);
  
COMMIT;

-- Inform the user that the script has been run.
SELECT 'User handling trigger and unique index have been successfully updated.';
