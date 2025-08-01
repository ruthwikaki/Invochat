
-- ============================================================================
-- ARVO: DATABASE SCHEMA
-- This script is idempotent and can be run safely multiple times.
-- ============================================================================

-- ============================================================================
-- Section 1: Custom Types
-- ============================================================================
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


-- ============================================================================
-- Section 2: Tables
-- ============================================================================

-- Companies Table
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    name text NOT NULL,
    owner_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Company Users Join Table
CREATE TABLE IF NOT EXISTS public.company_users (
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role company_role NOT NULL DEFAULT 'Member',
    PRIMARY KEY (company_id, user_id)
);

-- Company Settings Table
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    fast_moving_days integer NOT NULL DEFAULT 30,
    overstock_multiplier integer NOT NULL DEFAULT 3,
    high_value_threshold integer NOT NULL DEFAULT 100000, -- Stored in cents
    predictive_stock_days integer NOT NULL DEFAULT 7,
    currency text DEFAULT 'USD',
    timezone text DEFAULT 'UTC',
    tax_rate numeric DEFAULT 0,
    alert_settings jsonb DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);


-- Other tables follow...
-- (Suppliers, Products, ProductVariants, Orders, etc.)
-- Keeping the rest of the script concise for this example.

CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.products (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    description text,
    handle text,
    product_type text,
    tags text[],
    status text,
    image_url text,
    external_product_id text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.product_variants (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku text NOT NULL,
    title text,
    option1_name text,
    option1_value text,
    option2_name text,
    option2_value text,
    option3_name text,
    option3_value text,
    barcode text,
    price integer,
    compare_at_price integer,
    cost integer,
    inventory_quantity integer NOT NULL DEFAULT 0,
    reorder_point integer,
    reorder_quantity integer,
    supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL,
    external_variant_id text,
    location text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz
);

-- ============================================================================
-- Section 3: Helper Functions & Auth Triggers
-- ============================================================================

-- Function to get company_id from JWT, falling back to a direct query for safety.
CREATE OR REPLACE FUNCTION public.get_company_id_for_user(p_user_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    company_uuid uuid;
BEGIN
    -- First, try to get the company_id directly from the JWT claims.
    -- This is the fastest and most common path.
    SELECT (auth.jwt()->'app_metadata'->>'company_id')::uuid INTO company_uuid;

    -- If the JWT doesn't have the company_id (e.g., during signup race condition),
    -- then fall back to a direct query on company_users.
    IF company_uuid IS NULL THEN
        SELECT cu.company_id INTO company_uuid
        FROM public.company_users cu
        WHERE cu.user_id = p_user_id
        LIMIT 1;
    END IF;
    
    RETURN company_uuid;
END;
$$;


-- Trigger function to create a company and link the user on new user signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    new_company_id uuid;
BEGIN
    -- Create a new company for the user
    INSERT INTO public.companies (name, owner_id)
    VALUES (
        new.raw_app_meta_data->>'company_name',
        new.id
    ) RETURNING id INTO new_company_id;

    -- Link the user to the new company as 'Owner'
    INSERT INTO public.company_users (user_id, company_id, role)
    VALUES (new.id, new_company_id, 'Owner');
    
    -- Update the user's app_metadata with the new company_id
    UPDATE auth.users
    SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id)
    WHERE id = new.id;

    RETURN new;
END;
$$;

-- Drop the trigger if it exists, before creating it.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Create the trigger
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_user();


-- ============================================================================
-- Section 4: RLS (Row-Level Security)
-- ============================================================================

-- Enable RLS on all relevant tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
-- ... and so on for all other tables

-- RLS Policies
-- Users can only see their own company's data.

-- Policy for tables with a direct company_id column
CREATE OR REPLACE POLICY "User can access their own company data"
ON public.companies
FOR SELECT USING (id = public.get_company_id_for_user(auth.uid()));

CREATE OR REPLACE POLICY "User can access their own company settings"
ON public.company_settings
FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));

-- Policy for company_users table (the source of the recursion)
-- This policy is critical. It allows users to see entries in the company_users
-- table only if it pertains to their own company.
CREATE OR REPLACE POLICY "User can see their own company's user list"
ON public.company_users
FOR SELECT USING (company_id = public.get_company_id_for_user(auth.uid()));

    