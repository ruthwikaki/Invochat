
-- =================================================================
-- InvoChat Schema v1.1 - The Corrected and Final Version
-- Fixes all signup-related issues by implementing the standard
-- Supabase trigger-based approach for handling new users.
-- =================================================================

-- Step 1: Clean up any old, incorrect functions or triggers to ensure a clean slate.
DROP FUNCTION IF EXISTS public.create_company_and_user(text, text, text);
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();

-- Step 2: Create the trigger function to handle new user signups.
-- This function will run automatically AFTER a new user is inserted into auth.users.
-- It runs with the privileges of the user that created it (the database owner),
-- which allows it to insert into tables in the public schema.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
  new_company_id uuid;
BEGIN
  -- Create a new company for the user.
  -- It uses the 'company_name' from the metadata passed during signup.
  -- If no company name is provided, it creates a default one.
  INSERT INTO public.companies (name, owner_id)
  VALUES (
    COALESCE(NEW.raw_user_meta_data->>'company_name', NEW.email || '''s Company'),
    NEW.id
  ) RETURNING id INTO new_company_id;

  -- Update the user's metadata in the auth.users table to include the new company_id.
  -- This is crucial for Row-Level Security policies.
  UPDATE auth.users
  SET raw_user_meta_data = raw_user_meta_data || jsonb_build_object('company_id', new_company_id)
  WHERE id = NEW.id;

  -- Create the link in the company_users table, assigning the 'Owner' role.
  INSERT INTO public.company_users (user_id, company_id, role)
  VALUES (NEW.id, new_company_id, 'Owner');
  
  -- Create the default settings entry for the new company.
  INSERT INTO public.company_settings (company_id)
  VALUES (new_company_id);

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Step 3: Create the trigger that executes the function after user creation.
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Step 4: Ensure necessary extensions are enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =================================================================
-- RLS (Row-Level Security) Policies
-- These policies ensure that users can only access data for their own company.
-- This is the core of the multi-tenancy implementation.
-- =================================================================

-- Helper function to easily get the company_id from the current user's JWT claims.
CREATE OR REPLACE FUNCTION public.get_my_company_id()
RETURNS uuid
LANGUAGE sql STABLE
AS $$
  select (auth.jwt() -> 'user_metadata' ->> 'company_id')::uuid;
$$;
GRANT EXECUTE ON FUNCTION public.get_my_company_id() TO authenticated;


-- Enable RLS on all tables that contain company-specific data.
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;


-- Drop existing policies to prevent conflicts
DROP POLICY IF EXISTS "Users can only see their own company" ON public.companies;
DROP POLICY IF EXISTS "Users can view members of their own company" ON public.company_users;
DROP POLICY IF EXISTS "Users can manage their own company data" ON public.products;
DROP POLICY IF EXISTS "Users can manage their own company data" ON public.product_variants;
DROP POLICY IF EXISTS "Users can manage their own company data" ON public.orders;
DROP POLICY IF EXISTS "Users can manage their own company data" ON public.order_line_items;
DROP POLICY IF EXISTS "Users can manage their own company data" ON public.customers;
DROP POLICY IF EXISTS "Users can manage their own company data" ON public.suppliers;
DROP POLICY IF EXISTS "Users can manage their own company data" ON public.purchase_orders;
DROP POLICY IF EXISTS "Users can manage their own company data" ON public.purchase_order_line_items;
DROP POLICY IF EXISTS "Users can manage their own company data" ON public.inventory_ledger;
DROP POLICY IF EXISTS "Users can manage their own company data" ON public.integrations;
DROP POLICY IF EXISTS "Users can manage their own company data" ON public.company_settings;
DROP POLICY IF EXISTS "Admins can view all audit logs for their company" ON public.audit_log;

-- Apply new policies
CREATE POLICY "Users can only see their own company" ON public.companies FOR SELECT USING (id = get_my_company_id());
CREATE POLICY "Users can view members of their own company" ON public.company_users FOR SELECT USING (company_id = get_my_company_id());
CREATE POLICY "Users can manage their own company data" ON public.products FOR ALL USING (company_id = get_my_company_id());
CREATE POLICY "Users can manage their own company data" ON public.product_variants FOR ALL USING (company_id = get_my_company_id());
CREATE POLICY "Users can manage their own company data" ON public.orders FOR ALL USING (company_id = get_my_company_id());
CREATE POLICY "Users can manage their own company data" ON public.order_line_items FOR ALL USING (company_id = get_my_company_id());
CREATE POLICY "Users can manage their own company data" ON public.customers FOR ALL USING (company_id = get_my_company_id());
CREATE POLICY "Users can manage their own company data" ON public.suppliers FOR ALL USING (company_id = get_my_company_id());
CREATE POLICY "Users can manage their own company data" ON public.purchase_orders FOR ALL USING (company_id = get_my_company_id());
CREATE POLICY "Users can manage their own company data" ON public.purchase_order_line_items FOR ALL USING (company_id = get_my_company_id());
CREATE POLICY "Users can manage their own company data" ON public.inventory_ledger FOR ALL USING (company_id = get_my_company_id());
CREATE POLICY "Users can manage their own company data" ON public.integrations FOR ALL USING (company_id = get_my_company_id());
CREATE POLICY "Users can manage their own company data" ON public.company_settings FOR ALL USING (company_id = get_my_company_id());
CREATE POLICY "Admins can view all audit logs for their company" ON public.audit_log FOR SELECT USING (company_id = get_my_company_id());
