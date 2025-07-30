
-- This script is idempotent and can be run multiple times.
-- It will drop and recreate functions and types, ensuring the latest version is used.

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Drop existing types and functions to avoid conflicts
DROP FUNCTION IF EXISTS public.create_company_and_user(text, text, text);
DROP TYPE IF EXISTS public.company_role;
DROP TYPE IF EXISTS public.feedback_type;
DROP TYPE IF EXISTS public.integration_platform;
DROP TYPE IF EXISTS public.message_role;
DROP TYPE IF EXISTS public.po_status;
DROP TYPE IF EXISTS public.order_status;
DROP TYPE IF EXISTS public.fulfillment_status;

-- Create ENUM types for status fields to ensure data integrity
CREATE TYPE public.company_role AS ENUM ('Owner', 'Admin', 'Member');
CREATE TYPE public.feedback_type AS ENUM ('helpful', 'unhelpful');
CREATE TYPE public.integration_platform AS ENUM ('shopify', 'woocommerce', 'amazon_fba');
CREATE TYPE public.message_role AS ENUM ('user', 'assistant', 'tool');
CREATE TYPE public.po_status AS ENUM ('Draft', 'Ordered', 'Partially Received', 'Received', 'Cancelled');
CREATE TYPE public.order_status AS ENUM ('pending', 'paid', 'refunded', 'failed');
CREATE TYPE public.fulfillment_status AS ENUM ('fulfilled', 'unfulfilled', 'partially_fulfilled', 'cancelled');


-- COMPANIES
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid DEFAULT uuid_generate_v4() NOT NULL PRIMARY KEY,
    name text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    owner_id uuid REFERENCES auth.users(id)
);
-- RLS for companies
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow read access to company members" ON public.companies FOR SELECT USING (id IN (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));
CREATE POLICY "Allow owners to update their company" ON public.companies FOR UPDATE USING (id IN (SELECT company_id FROM public.company_users WHERE user_id = auth.uid() AND role = 'Owner'));


-- COMPANY_USERS (Pivot table for many-to-many relationship)
CREATE TABLE IF NOT EXISTS public.company_users (
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role public.company_role DEFAULT 'Member'::public.company_role NOT NULL,
    PRIMARY KEY (company_id, user_id)
);
-- RLS for company_users
ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow company members to see other members" ON public.company_users FOR SELECT USING (company_id IN (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));
CREATE POLICY "Allow owners and admins to manage team" ON public.company_users FOR ALL USING (company_id IN (SELECT company_id FROM public.company_users WHERE user_id = auth.uid() AND role IN ('Owner', 'Admin')));


-- =================================================================
-- Function to create a new company and user atomically
-- =================================================================
CREATE OR REPLACE FUNCTION public.create_company_and_user(
    p_company_name text,
    p_user_email text,
    p_user_password text
)
RETURNS uuid
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

    -- 2. Create the user in auth.users with company_id in metadata
    INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, recovery_token, recovery_sent_at, email_change_token_new, email_change, email_change_sent_at, last_sign_in_at, raw_app_meta_data, raw_user_meta_data, is_super_admin, created_at, updated_at)
    VALUES (
        '00000000-0000-0000-0000-000000000000',
        uuid_generate_v4(),
        'authenticated',
        'authenticated',
        p_user_email,
        crypt(p_user_password, gen_salt('bf')),
        now(),
        '',
        now(),
        '',
        '',
        now(),
        now(),
        jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email'), 'company_id', new_company_id),
        '{}'::jsonb,
        false,
        now(),
        now()
    )
    RETURNING id INTO new_user_id;

    -- 3. Link user to company as Owner
    INSERT INTO public.company_users (user_id, company_id, role)
    VALUES (new_user_id, new_company_id, 'Owner');

    -- 4. Update the company with the owner_id
    UPDATE public.companies
    SET owner_id = new_user_id
    WHERE id = new_company_id;

    RETURN new_user_id;
END;
$$;


-- Grant execution to authenticated users
GRANT EXECUTE ON FUNCTION public.create_company_and_user(text, text, text) TO authenticated;

-- Ensure supabase_auth_admin can execute this function
GRANT EXECUTE ON FUNCTION public.create_company_and_user(text, text, text) TO supabase_auth_admin;

