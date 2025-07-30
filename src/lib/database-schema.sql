
-- This script sets up the database schema for the application.
-- It is designed to be idempotent, meaning it can be run multiple times
-- without causing errors or creating duplicate data.

-- 1. Create custom types (enums) for standardized values across the database.
-- These types ensure data consistency for things like user roles and integration platforms.

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'company_role') THEN
        CREATE TYPE public.company_role AS ENUM ('Owner', 'Admin', 'Member');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'integration_platform') THEN
        CREATE TYPE public.integration_platform AS ENUM ('shopify', 'woocommerce', 'amazon_fba');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'message_role') THEN
        CREATE TYPE public.message_role AS ENUM ('user', 'assistant', 'tool');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'feedback_type') THEN
        CREATE TYPE public.feedback_type AS ENUM ('helpful', 'unhelpful');
    END IF;
END$$;


-- 2. Create tables for core application data.
-- Each table includes security features like row-level security (RLS)
-- and references to other tables to maintain data integrity.

-- Table to store companies (tenants)
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    name text NOT NULL,
    owner_id uuid NOT NULL REFERENCES auth.users(id),
    created_at timestamptz DEFAULT now() NOT NULL
);
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;

-- Table to link users to companies and define their roles
CREATE TABLE IF NOT EXISTS public.company_users (
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role public.company_role DEFAULT 'Member'::public.company_role NOT NULL,
    PRIMARY KEY (user_id, company_id)
);
ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;

-- Table to store company-specific settings for business logic
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days int DEFAULT 90 NOT NULL,
    fast_moving_days int DEFAULT 30 NOT NULL,
    overstock_multiplier real DEFAULT 3 NOT NULL,
    high_value_threshold int DEFAULT 100000 NOT NULL,
    predictive_stock_days int DEFAULT 7 NOT NULL,
    currency text DEFAULT 'USD'::text NOT NULL,
    tax_rate real DEFAULT 0 NOT NULL,
    timezone text DEFAULT 'UTC'::text NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz
);
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;


-- 3. Create a function to automatically handle new user signups.
-- This function is called by a trigger when a new user is created in Supabase's auth system.
-- It creates a new company for the user and assigns them as the owner.
-- This is a critical piece of the multi-tenant architecture.

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
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


-- 4. Create a trigger to call the handle_new_user function.
-- This ensures that the multi-tenancy setup is automated and secure.

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- 5. Define policies for Row-Level Security (RLS).
-- These policies are the core of the security model, ensuring that users
-- can only access data belonging to their own company.

-- Policy for companies table
DROP POLICY IF EXISTS "Users can view their own company" ON public.companies;
CREATE POLICY "Users can view their own company" ON public.companies
FOR SELECT USING (id = (
    SELECT company_id FROM public.company_users WHERE user_id = auth.uid()
));

-- Policy for company_users table
DROP POLICY IF EXISTS "Users can view other members of their own company" ON public.company_users;
CREATE POLICY "Users can view other members of their own company" ON public.company_users
FOR SELECT USING (company_id = (
    SELECT company_id FROM public.company_users WHERE user_id = auth.uid()
));

-- Policy for company_settings table
DROP POLICY IF EXISTS "Users can manage settings for their own company" ON public.company_settings;
CREATE POLICY "Users can manage settings for their own company" ON public.company_settings
FOR ALL USING (company_id = (
    SELECT company_id FROM public.company_users WHERE user_id = auth.uid()
))
WITH CHECK (company_id = (
    SELECT company_id FROM public.company_users WHERE user_id = auth.uid()
));


-- 6. Grant usage permissions on the public schema to authenticated users.
-- This allows logged-in users to interact with the database according to the RLS policies.
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;
