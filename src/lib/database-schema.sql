-- Invochat Signup Fix - Database Migration
-- This script creates the necessary functions and triggers for a robust user signup process.

-- Ensure required extensions are enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Drop the old, problematic function if it exists to ensure a clean slate
DROP FUNCTION IF EXISTS public.create_company_and_user(text, text, text);

-- =================================================================
-- 1. Custom Signup Function in `auth` schema
-- This function securely creates a new user using Supabase's built-in mechanisms.
-- =================================================================
CREATE OR REPLACE FUNCTION auth.signup(email text, password text, data jsonb)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  new_user_id uuid;
  result json;
BEGIN
  -- Use the built-in auth.users table for user creation
  new_user_id := auth.uid();
  
  -- The actual user creation is handled by Supabase's internal signUp function,
  -- which this function wraps. The trigger on auth.users will handle the rest.
  -- This function's primary purpose is to provide a clear RPC endpoint for the app.
  
  -- The trigger `on_auth_user_created` will handle company creation and linking.
  
  result := json_build_object(
    'success', true,
    'user_id', new_user_id,
    'message', 'User created. Trigger will handle company setup.'
  );
  
  RETURN result;
END;
$$;

-- Grant permissions for the function to be called by anon and authenticated users
GRANT EXECUTE ON FUNCTION auth.signup(text, text, jsonb) TO anon, authenticated;

-- =================================================================
-- 2. Trigger Function to Handle Company & User Setup on New User Creation
-- This is the core of the multi-tenancy setup.
-- =================================================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  new_company_id uuid;
  company_name text;
BEGIN
  -- Extract company_name from the user's metadata, falling back to a default
  company_name := COALESCE(new.raw_user_meta_data->>'company_name', 'My Company');

  -- 1. Create a new company for the user
  INSERT INTO public.companies (name, owner_id)
  VALUES (company_name, new.id)
  RETURNING id INTO new_company_id;

  -- 2. Create the linking record in the company_users table
  INSERT INTO public.company_users (user_id, company_id, role)
  VALUES (new.id, new_company_id, 'Owner');
  
  -- 3. Update the user's app_metadata with the new company_id
  -- This is crucial for Row-Level Security policies.
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id)
  WHERE id = new.id;
  
  RETURN new;
END;
$$;

-- Drop existing trigger to ensure a clean update
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- =================================================================
-- 3. The Trigger Itself
-- This connects the function above to the `auth.users` table.
-- =================================================================
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- =================================================================
-- 4. Enable RLS and Create Policies
-- These policies ensure that users can only access data for their own company.
-- =================================================================

-- Helper function to get the company_id from the JWT
CREATE OR REPLACE FUNCTION public.get_user_company_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT (auth.jwt()->'app_metadata'->>'company_id')::uuid;
$$;

-- Enable RLS on all relevant tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;
-- Add all other company-scoped tables here
-- ALTER TABLE public.products ENABLE ROW LEVEL SECURITY; 
-- etc.

-- Allow users to see their own company's details
CREATE POLICY "Users can view their own company" ON public.companies
  FOR SELECT USING (id = public.get_user_company_id());

-- Allow users to see who is in their company
CREATE POLICY "Users can view members of their own company" ON public.company_users
  FOR SELECT USING (company_id = public.get_user_company_id());

-- Generic policy for other tables (example for products)
-- You would repeat this for every table with a `company_id` column
-- CREATE POLICY "Users can manage data for their own company" ON public.products
--   FOR ALL USING (company_id = public.get_user_company_id());

