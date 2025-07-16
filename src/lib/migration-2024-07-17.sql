-- ARVO DATABASE MIGRATION SCRIPT
-- This script is designed to be run on an existing database to apply necessary updates.
-- It is idempotent, meaning it can be run multiple times without causing errors or data loss.

BEGIN;

-- =================================================================
-- Step 1: Clean up old, problematic objects from previous scripts
-- =================================================================
-- Drop the faulty trigger on the protected auth.users table if it exists.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Drop the old handle_new_user function if it exists.
DROP FUNCTION IF EXISTS public.handle_new_user();


-- =================================================================
-- Step 2: Ensure core tables exist and have the correct columns
-- This section uses ALTER TABLE with "IF NOT EXISTS" checks to avoid errors.
-- =================================================================

-- Create companies table if it doesn't exist.
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Create a public 'users' table to safely store user-company relationships.
CREATE TABLE IF NOT EXISTS public.users (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email text,
    role text DEFAULT 'member'::text,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now()
);

-- Add 'role' column to public.users if it's missing.
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS role text DEFAULT 'member'::text;

-- =================================================================
-- Step 3: Define the new, safe function to handle new user setup.
-- This function will be called by the application, not a trigger on auth.users.
-- =================================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS void AS $$
DECLARE
    v_company_id uuid;
    v_user_id uuid := auth.uid();
    v_user_email text := (SELECT email FROM auth.users WHERE id = v_user_id);
    v_company_name text := (SELECT raw_app_meta_data->>'company_name' FROM auth.users WHERE id = v_user_id);
BEGIN
    -- Check if the user is already associated with a company
    IF EXISTS (SELECT 1 FROM public.users WHERE id = v_user_id) THEN
        RAISE NOTICE 'User % already has a profile.', v_user_id;
        RETURN;
    END IF;

    -- Create a new company for the user
    INSERT INTO public.companies (name)
    VALUES (v_company_name)
    RETURNING id INTO v_company_id;

    -- Create a public user profile linked to the new company
    INSERT INTO public.users (id, company_id, email, role)
    VALUES (v_user_id, v_company_id, v_user_email, 'Owner');

    -- Update the user's app_metadata with the new company_id
    UPDATE auth.users
    SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', v_company_id, 'role', 'Owner')
    WHERE id = v_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- =================================================================
-- Step 4: Re-apply Row-Level Security (RLS) policies.
-- Dropping and recreating policies is the correct idempotent pattern.
-- =================================================================

-- Enable RLS for all relevant tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
-- ... add for all other application tables ...
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;

-- Drop old policies if they exist, then create the new, correct ones.

-- Policy for 'companies' table
DROP POLICY IF EXISTS "Allow read access to own company" ON public.companies;
CREATE POLICY "Allow read access to own company" ON public.companies FOR SELECT
USING (id = (current_setting('request.jwt.claims', true)::jsonb ->> 'app_metadata')::jsonb ->> 'company_id');

-- Policies for 'users' table
DROP POLICY IF EXISTS "Allow users to see other members of their own company" ON public.users;
CREATE POLICY "Allow users to see other members of their own company" ON public.users FOR SELECT
USING (company_id = (current_setting('request.jwt.claims', true)::jsonb ->> 'app_metadata')::jsonb ->> 'company_id');

-- Policies for 'products' table
DROP POLICY IF EXISTS "Allow full access to own company data" ON public.products;
CREATE POLICY "Allow full access to own company data" ON public.products FOR ALL
USING (company_id = (current_setting('request.jwt.claims', true)::jsonb ->> 'app_metadata')::jsonb ->> 'company_id');

-- Universal policy for other tables
CREATE OR REPLACE FUNCTION public.create_rls_policy_if_not_exists(
    p_table_name text
)
RETURNS void AS $$
BEGIN
    -- Drop the old policy if it exists
    EXECUTE format('DROP POLICY IF EXISTS "Allow full access to own company data" ON public.%I;', p_table_name);
    
    -- Create the new policy
    EXECUTE format('
        CREATE POLICY "Allow full access to own company data"
        ON public.%I
        FOR ALL
        USING (company_id = ((current_setting(''request.jwt.claims'', true)::jsonb ->> ''app_metadata'')::jsonb ->> ''company_id'')::uuid)
        WITH CHECK (company_id = ((current_setting(''request.jwt.claims'', true)::jsonb ->> ''app_metadata'')::jsonb ->> ''company_id'')::uuid);
    ', p_table_name);
END;
$$ LANGUAGE plpgsql;

-- Apply the universal policy to all other tables
SELECT public.create_rls_policy_if_not_exists('product_variants');
SELECT public.create_rls_policy_if_not_exists('suppliers');
SELECT public.create_rls_policy_if_not_exists('orders');
SELECT public.create_rls_policy_if_not_exists('order_line_items');
SELECT public.create_rls_policy_if_not_exists('purchase_orders');
SELECT public.create_rls_policy_if_not_exists('purchase_order_line_items');
SELECT public.create_rls_policy_if_not_exists('inventory_ledger');
SELECT public.create_rls_policy_if_not_exists('company_settings');
SELECT public.create_rls_policy_if_not_exists('conversations');
SELECT public.create_rls_policy_if_not_exists('messages');
SELECT public.create_rls_policy_if_not_exists('integrations');

DROP FUNCTION public.create_rls_policy_if_not_exists(text);


-- =================================================================
-- Step 5: Update views using CREATE OR REPLACE to prevent errors.
-- =================================================================

CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.*,
    p.title AS product_title,
    p.status AS product_status,
    p.image_url
FROM
    public.product_variants pv
JOIN
    public.products p ON pv.product_id = p.id;


COMMIT;
