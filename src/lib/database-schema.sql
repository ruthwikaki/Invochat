-- src/lib/database-schema.sql

-- Drop existing policies and functions if they exist
DROP POLICY IF EXISTS "Enable read access for authenticated users" ON public.companies;
DROP POLICY IF EXISTS "Enable all operations for users based on user_id" ON public.company_users;
DROP FUNCTION IF EXISTS public.handle_new_user();

-- Enable Row Level Security
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;

-- Create Policies
CREATE POLICY "Enable read access for authenticated users" ON public.companies
  FOR SELECT USING (auth.uid() IN (SELECT user_id FROM company_users WHERE company_id = id));

CREATE POLICY "Enable all operations for users based on user_id" ON public.company_users
  FOR ALL USING (auth.uid() = user_id);

-- Improved Trigger Function to handle new user creation
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
  -- Use an advisory lock per user to prevent concurrent trigger re-entry, which can happen in tests or rapid signups.
  v_lock_key := ('x' || substr(md5(new.id::text), 1, 16))::bit(64)::bigint;
  PERFORM pg_advisory_xact_lock(v_lock_key);

  -- If the user is already associated with a company, do nothing. This makes the trigger idempotent.
  SELECT cu.company_id INTO v_company_id
  FROM public.company_users cu
  WHERE cu.user_id = new.id
  LIMIT 1;

  IF v_company_id IS NOT NULL THEN
    RETURN new;
  END IF;

  -- Determine the company name from metadata, or create a default.
  v_name := COALESCE(new.raw_user_meta_data->>'company_name', 'Company for ' || COALESCE(new.email, new.id::text));

  -- Create the new company and get its ID
  INSERT INTO public.companies (name, owner_id)
  VALUES (v_name, new.id)
  RETURNING id INTO v_company_id;

  -- Associate the user with the new company
  INSERT INTO public.company_users (user_id, company_id, role)
  VALUES (new.id, v_company_id, 'Owner')
  ON CONFLICT DO NOTHING; -- Safe guard against race conditions

  -- Create default settings for the new company
  INSERT INTO public.company_settings (company_id)
  VALUES (v_company_id)
  ON CONFLICT DO NOTHING;

  -- Update the user's app_metadata with the company_id for quick access in JWT.
  UPDATE auth.users
     SET raw_app_meta_data = COALESCE(raw_app_meta_data, '{}'::jsonb) || jsonb_build_object('company_id', v_company_id)
   WHERE id = new.id;

  RETURN new;
END;
$$;

-- Grant ownership of the function to postgres role for necessary permissions
ALTER FUNCTION public.handle_new_user() OWNER TO postgres;

-- Create the trigger that executes the function on new user creation
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Ensure a user can only be associated with one company
CREATE UNIQUE INDEX IF NOT EXISTS ux_company_users_user ON public.company_users (user_id);
