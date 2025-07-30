
-- This is the definitive schema for AIventory.
-- It establishes all tables, relationships, and essential functions.
-- Last Updated: 2024-07-30

-- =============================================
-- SECTION 1: EXTENSIONS & INITIAL SETUP
-- =============================================
-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =============================================
-- SECTION 2: ENUMERATED TYPES
-- =============================================
-- Using ENUMs ensures data integrity for status fields.

CREATE TYPE public.company_role AS ENUM ('Owner', 'Admin', 'Member');
CREATE TYPE public.feedback_type AS ENUM ('helpful', 'unhelpful');
CREATE TYPE public.integration_platform AS ENUM ('shopify', 'woocommerce', 'amazon_fba');
CREATE TYPE public.message_role AS ENUM ('user', 'assistant', 'tool');

-- =============================================
-- SECTION 3: CORE TABLES
-- =============================================

CREATE TABLE IF NOT EXISTS public.companies (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    name text NOT NULL UNIQUE,
    owner_id uuid, -- Foreign key added later
    created_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.companies IS 'Stores company/organization information.';

CREATE TABLE IF NOT EXISTS public.company_users (
    company_id uuid NOT NULL,
    user_id uuid NOT NULL,
    role public.company_role NOT NULL DEFAULT 'Member',
    PRIMARY KEY (company_id, user_id)
);
COMMENT ON TABLE public.company_users IS 'Pivot table linking users from auth.users to companies.';

CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY,
    dead_stock_days integer NOT NULL DEFAULT 90,
    fast_moving_days integer NOT NULL DEFAULT 30,
    predictive_stock_days integer NOT NULL DEFAULT 7,
    currency text DEFAULT 'USD',
    timezone text DEFAULT 'UTC',
    tax_rate numeric DEFAULT 0,
    overstock_multiplier integer NOT NULL DEFAULT 3,
    high_value_threshold integer NOT NULL DEFAULT 100000, -- Stored in cents
    alert_settings jsonb DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);
COMMENT ON TABLE public.company_settings IS 'Stores business logic and settings for each company.';

-- =============================================
-- SECTION 4: SIGNUP AND AUTH LOGIC
-- =============================================

-- Drop the old, flawed function if it exists
DROP FUNCTION IF EXISTS public.create_company_and_user(text, text, text);

-- This function handles the creation of a new company and its owner in a single transaction.
CREATE OR REPLACE FUNCTION public.create_company_and_user(
    p_company_name text,
    p_user_email text,
    p_user_password text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    new_company_id uuid;
    new_user_id uuid;
BEGIN
    -- 1. Create the company
    INSERT INTO public.companies (name)
    VALUES (p_company_name)
    RETURNING id INTO new_company_id;

    -- 2. Create the user using auth.signup, which is the correct Supabase function.
    --    The company_id is passed in the metadata.
    SELECT raw_app_meta_data ->> 'id' INTO new_user_id FROM auth.signup(
        p_user_email,
        p_user_password,
        jsonb_build_object('company_id', new_company_id)
    );
    
    -- This trigger is expected to handle the rest:
    -- - Inserting into public.company_users
    -- - Updating public.companies.owner_id
    -- - Creating default settings

    RETURN json_build_object(
        'success', true,
        'user_id', new_user_id,
        'company_id', new_company_id
    );
EXCEPTION WHEN OTHERS THEN
    -- In case of any error, log it and return a failure message
    RAISE WARNING 'Error in create_company_and_user: %', SQLERRM;
    RETURN json_build_object('success', false, 'message', SQLERRM);
END;
$$;

-- Grant execute permissions to the authenticated role, which is what Supabase uses for RLS.
GRANT EXECUTE ON FUNCTION public.create_company_and_user(text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_company_and_user(text, text, text) TO anon;

-- This trigger function is crucial for multi-tenancy.
-- It populates the company_users table and sets the company owner.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    company_id_from_meta uuid;
BEGIN
    -- Extract company_id from the user's metadata
    company_id_from_meta := (new.raw_app_meta_data->>'company_id')::uuid;

    -- If a company_id was provided, link the user to the company
    IF company_id_from_meta IS NOT NULL THEN
        -- Link the user to the company with the 'Owner' role
        INSERT INTO public.company_users (user_id, company_id, role)
        VALUES (new.id, company_id_from_meta, 'Owner');
        
        -- Set the owner_id on the company record
        UPDATE public.companies
        SET owner_id = new.id
        WHERE id = company_id_from_meta;

        -- Create default settings for the new company
        INSERT INTO public.company_settings (company_id)
        VALUES (company_id_from_meta);
    END IF;

    RETURN new;
END;
$$;

-- Create the trigger on the auth.users table
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();


-- =============================================
-- SECTION 5: FOREIGN KEY CONSTRAINTS AND RLS
-- =============================================

-- Add foreign key from companies.owner_id to auth.users.id
ALTER TABLE public.companies
    ADD CONSTRAINT fk_companies_owner_id
    FOREIGN KEY (owner_id) REFERENCES auth.users (id) ON DELETE SET NULL;

-- Enable RLS on all relevant tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
-- Add other tables as they are created and need RLS

-- RLS Policies
CREATE POLICY "Users can view their own company data" ON public.companies
    FOR SELECT USING (id = (auth.jwt() -> 'app_metadata' ->> 'company_id')::uuid);

CREATE POLICY "Users can view members of their own company" ON public.company_users
    FOR SELECT USING (company_id = (auth.jwt() -> 'app_metadata' ->> 'company_id')::uuid);

CREATE POLICY "Users can manage settings for their own company" ON public.company_settings
    FOR ALL USING (company_id = (auth.jwt() -> 'app_metadata' ->> 'company_id')::uuid);


-- Grant usage on the public schema to Supabase roles
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO postgres, anon, authenticated, service_role;
