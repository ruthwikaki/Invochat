-- This script is designed to be idempotent.
-- It creates extensions, tables, and functions if they don't exist.

-- Create extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pgroonga;

-- Grant usage on the new schema to the postgres user and anon, authenticated roles
GRANT USAGE ON SCHEMA public TO postgres;
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;

-- Set default privileges for tables in the public schema
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO service_role;

-- Enums
CREATE TYPE public.company_role AS ENUM ('Owner', 'Admin', 'Member');
CREATE TYPE public.integration_platform AS ENUM ('shopify', 'woocommerce', 'amazon_fba');
CREATE TYPE public.message_role AS ENUM ('user', 'assistant', 'tool');
CREATE TYPE public.feedback_type AS ENUM ('helpful', 'unhelpful');

-- Drop the old, problematic trigger and function if they exist
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();

-- Create the new, correct function to handle company and user creation
CREATE OR REPLACE FUNCTION public.create_company_and_user(
    p_company_name TEXT,
    p_user_email TEXT,
    p_user_password TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    new_company_id UUID;
    new_user_id UUID;
    encrypted_password TEXT;
BEGIN
    -- 1. Create the company first
    INSERT INTO public.companies (name)
    VALUES (p_company_name)
    RETURNING id INTO new_company_id;

    -- 2. Create the user in auth.users with the new company_id in metadata
    INSERT INTO auth.users (
        instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, recovery_token, recovery_sent_at, last_sign_in_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, phone, phone_confirmed_at, email_change, email_change_token_new, email_change_sent_at
    ) VALUES (
        '00000000-0000-0000-0000-000000000000', uuid_generate_v4(), 'authenticated', 'authenticated', p_user_email, crypt(p_user_password, gen_salt('bf')), now(), '', now(), now(), jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email'), 'company_id', new_company_id), '{}'::jsonb, now(), now(), '', now(), '', '', now()
    ) RETURNING id INTO new_user_id;

    -- 3. Link the user to the company in the junction table
    INSERT INTO public.company_users (user_id, company_id, role)
    VALUES (new_user_id, new_company_id, 'Owner');
    
    -- 4. Update the company's owner_id
    UPDATE public.companies SET owner_id = new_user_id WHERE id = new_company_id;

    RETURN jsonb_build_object('user_id', new_user_id, 'company_id', new_company_id);
EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'A user with this email already exists.';
    WHEN others THEN
        RAISE EXCEPTION 'An unexpected error occurred: %', SQLERRM;
END;
$$;


-- Grant execution rights on the new function
GRANT EXECUTE ON FUNCTION public.create_company_and_user(TEXT, TEXT, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.create_company_and_user(TEXT, TEXT, TEXT) TO authenticated;
