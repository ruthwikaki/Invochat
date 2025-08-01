-- ============================================================================
-- BASELINE SCHEMA FOR ARVO
-- ============================================================================
-- This script contains the core database schema, including tables, views,
-- functions, and row-level security policies required for the application
-- to function correctly.
--
-- It is designed to be idempotent, meaning it can be run multiple times
-- without causing errors.
--
-- Last Updated: 2024-07-30
-- ============================================================================

-- ============================================================================
-- EXTENSIONS
-- ============================================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- ENUMS
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
-- CORE TABLES
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.companies (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    name text NOT NULL,
    owner_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.companies IS 'Stores company/organization information.';

CREATE TABLE IF NOT EXISTS public.company_users (
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role company_role NOT NULL DEFAULT 'Member',
    PRIMARY KEY (company_id, user_id)
);
COMMENT ON TABLE public.company_users IS 'Join table for users and companies, defining roles.';


-- ============================================================================
-- RLS HELPER FUNCTIONS
-- ============================================================================

-- This function is the root of the fix. It now correctly uses plpgsql syntax
-- and gets the company_id from the JWT, avoiding recursive table lookups.
CREATE OR REPLACE FUNCTION public.get_company_id_for_user()
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
BEGIN
  -- Safely extract the company_id from the JWT's app_metadata.
  -- The `true` in current_setting makes it not throw an error if the setting is missing.
  RETURN (current_setting('request.jwt.claims', true)::jsonb->'app_metadata'->>'company_id')::uuid;
EXCEPTION
  -- Handle cases where the claim is missing or not a valid UUID, returning NULL.
  WHEN others THEN
    RETURN NULL;
END;
$$;


-- ============================================================================
-- RLS POLICIES
-- ============================================================================

-- Companies: Users can only see their own company.
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "User can access their own company" ON public.companies;
CREATE POLICY "User can access their own company"
    ON public.companies FOR SELECT
    USING (id = get_company_id_for_user());

-- Company Users: Users can see who is in their own company.
ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Enable read access for company members" ON public.company_users;
CREATE POLICY "Enable read access for company members"
    ON public.company_users FOR SELECT
    USING (company_id = get_company_id_for_user());

-- Add similar policies for all other company-specific tables
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "User can access their own company data" ON public.products;
CREATE POLICY "User can access their own company data" ON public.products FOR ALL USING (company_id = get_company_id_for_user()) WITH CHECK (company_id = get_company_id_for_user());

ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "User can access their own company data" ON public.product_variants;
CREATE POLICY "User can access their own company data" ON public.product_variants FOR ALL USING (company_id = get_company_id_for_user()) WITH CHECK (company_id = get_company_id_for_user());

ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "User can access their own company data" ON public.orders;
CREATE POLICY "User can access their own company data" ON public.orders FOR ALL USING (company_id = get_company_id_for_user()) WITH CHECK (company_id = get_company_id_for_user());

ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "User can access their own company data" ON public.order_line_items;
CREATE POLICY "User can access their own company data" ON public.order_line_items FOR ALL USING (company_id = get_company_id_for_user()) WITH CHECK (company_id = get_company_id_for_user());

ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "User can access their own company data" ON public.customers;
CREATE POLICY "User can access their own company data" ON public.customers FOR ALL USING (company_id = get_company_id_for_user()) WITH CHECK (company_id = get_company_id_for_user());

ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "User can access their own company data" ON public.suppliers;
CREATE POLICY "User can access their own company data" ON public.suppliers FOR ALL USING (company_id = get_company_id_for_user()) WITH CHECK (company_id = get_company_id_for_user());

ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "User can access their own company data" ON public.purchase_orders;
CREATE POLICY "User can access their own company data" ON public.purchase_orders FOR ALL USING (company_id = get_company_id_for_user()) WITH CHECK (company_id = get_company_id_for_user());

ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "User can access their own company data" ON public.purchase_order_line_items;
CREATE POLICY "User can access their own company data" ON public.purchase_order_line_items FOR ALL USING (company_id = get_company_id_for_user()) WITH CHECK (company_id = get_company_id_for_user());

ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "User can access their own company data" ON public.integrations;
CREATE POLICY "User can access their own company data" ON public.integrations FOR ALL USING (company_id = get_company_id_for_user()) WITH CHECK (company_id = get_company_id_for_user());

ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "User can access their own company data" ON public.webhook_events;
CREATE POLICY "User can access their own company data" ON public.webhook_events FOR ALL USING (company_id = (SELECT company_id FROM public.integrations WHERE id = integration_id AND company_id = get_company_id_for_user())) WITH CHECK (company_id = (SELECT company_id FROM public.integrations WHERE id = integration_id AND company_id = get_company_id_for_user()));

ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "User can access their own company data" ON public.inventory_ledger;
CREATE POLICY "User can access their own company data" ON public.inventory_ledger FOR ALL USING (company_id = get_company_id_for_user()) WITH CHECK (company_id = get_company_id_for_user());

ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "User can access their own company data" ON public.messages;
CREATE POLICY "User can access their own company data" ON public.messages FOR ALL USING (company_id = get_company_id_for_user()) WITH CHECK (company_id = get_company_id_for_user());

ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "User can access their own company data" ON public.audit_log;
CREATE POLICY "User can access their own company data" ON public.audit_log FOR ALL USING (company_id = get_company_id_for_user()) WITH CHECK (company_id = get_company_id_for_user());

ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "User can access their own company settings" ON public.company_settings;
CREATE POLICY "User can access their own company settings" ON public.company_settings FOR ALL USING (company_id = get_company_id_for_user()) WITH CHECK (company_id = get_company_id_for_user());

-- ============================================================================
-- DATABASE TRIGGERS
-- ============================================================================

-- Function to create a company and link it to the new user
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
  company_id_to_set uuid;
  user_company_name text;
BEGIN
  -- Sanitize and validate the company name
  user_company_name := BTRIM(new.raw_user_meta_data->>'company_name');
  IF user_company_name IS NULL OR user_company_name = '' THEN
      user_company_name := (new.raw_user_meta_data->>'email') || '''s Company';
  END IF;

  -- Create the company
  INSERT INTO public.companies (name, owner_id)
  VALUES (user_company_name, new.id)
  RETURNING id INTO company_id_to_set;

  -- Link the user to the new company
  INSERT INTO public.company_users (company_id, user_id, role)
  VALUES (company_id_to_set, new.id, 'Owner');

  -- Update the user's app_metadata with the new company_id
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id_to_set)
  WHERE id = new.id;
  
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to call the function when a new user is created in auth.users
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();


-- ============================================================================
-- VIEWS and INDEXES
-- ============================================================================
-- These are created after tables and functions to ensure dependencies are met.

CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.*,
    p.title as product_title,
    p.status as product_status,
    p.image_url,
    p.product_type
FROM public.product_variants pv
JOIN public.products p ON pv.product_id = p.id;

CREATE INDEX IF NOT EXISTS idx_product_variants_sku ON public.product_variants(sku);
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers(company_id);
CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON public.suppliers(company_id);


-- Final check to ensure RLS is enabled on all company-specific tables
DO $$
DECLARE
    t_name TEXT;
BEGIN
    FOR t_name IN
        SELECT table_name FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name NOT LIKE 'pg_%' AND table_name NOT LIKE 'sql_%'
          AND table_name <> 'schema_migrations'
    LOOP
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = t_name AND column_name = 'company_id') THEN
            EXECUTE 'ALTER TABLE public.' || quote_ident(t_name) || ' ENABLE ROW LEVEL SECURITY;';
        END IF;
    END LOOP;
END $$;
