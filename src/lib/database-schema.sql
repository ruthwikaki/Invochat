
-- ============================================================================
-- Step 1: Drop dependent policies before dropping the function
-- ============================================================================
-- We use a DO block to dynamically drop policies from all tables that depend
-- on the get_company_id_for_user function. This avoids "dependency" errors.
DO $$
DECLARE
    policy_record RECORD;
BEGIN
    FOR policy_record IN
        SELECT
            'ALTER TABLE ' || quote_ident(schemaname) || '.' || quote_ident(tablename) ||
            ' DROP POLICY IF EXISTS ' || quote_ident(policyname) || ';' AS drop_command
        FROM
            pg_policies
        WHERE
            -- This condition finds policies that use our specific function in their definitions
            (definition ILIKE '%get_company_id_for_user(auth.uid())%' OR
             qual ILIKE '%get_company_id_for_user(auth.uid())%')
    LOOP
        RAISE NOTICE 'Executing: %', policy_record.drop_command;
        EXECUTE policy_record.drop_command;
    END LOOP;
END $$;


-- ============================================================================
-- Step 2: Drop the old function
-- ============================================================================
DROP FUNCTION IF EXISTS public.get_company_id_for_user(user_uuid uuid);


-- ============================================================================
-- Step 3: Create the new, correct function
-- This version securely gets the company_id from the session JWT,
-- which avoids the recursive loop and is more performant.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_company_id_for_user()
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
BEGIN
  -- We use coalesce to handle cases where the app_metadata or company_id might be null,
  -- returning a NULL uuid instead of an error, which RLS policies can handle gracefully.
  RETURN (SELECT nullif(auth.jwt()->'app_metadata'->>'company_id', '')::uuid);
END;
$$;

-- Grant execution rights to authenticated users
GRANT EXECUTE ON FUNCTION public.get_company_id_for_user() TO authenticated;


-- ============================================================================
-- Step 4: Recreate all Row Level Security (RLS) policies
-- Now that the function is corrected, we re-apply all security policies.
-- These policies ensure that a user can only interact with data from their
-- own company, which is the cornerstone of a multi-tenant application.
-- ============================================================================

-- Enable RLS on all relevant tables
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refunds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;

-- Create policies for each table
CREATE POLICY "User can access their own company data" ON public.products FOR ALL USING (company_id = get_company_id_for_user());
CREATE POLICY "User can access their own company data" ON public.product_variants FOR ALL USING (company_id = get_company_id_for_user());
CREATE POLICY "User can access their own company data" ON public.orders FOR ALL USING (company_id = get_company_id_for_user());
CREATE POLICY "User can access their own company data" ON public.order_line_items FOR ALL USING (company_id = get_company_id_for_user());
CREATE POLICY "User can access their own company data" ON public.customers FOR ALL USING (company_id = get_company_id_for_user());
CREATE POLICY "User can access their own company data" ON public.suppliers FOR ALL USING (company_id = get_company_id_for_user());
CREATE POLICY "User can access their own company data" ON public.purchase_orders FOR ALL USING (company_id = get_company_id_for_user());
CREATE POLICY "User can access their own company data" ON public.purchase_order_line_items FOR ALL USING (company_id = get_company_id_for_user());
CREATE POLICY "User can access their own company data" ON public.integrations FOR ALL USING (company_id = get_company_id_for_user());
CREATE POLICY "User can access their own company data" ON public.webhook_events FOR ALL USING (company_id = get_company_id_for_user());
CREATE POLICY "User can access their own company data" ON public.inventory_ledger FOR ALL USING (company_id = get_company_id_for_user());
CREATE POLICY "User can access their own company data" ON public.messages FOR ALL USING (company_id = get_company_id_for_user());
CREATE POLICY "User can access their own company data" ON public.audit_log FOR ALL USING (company_id = get_company_id_for_user());
CREATE POLICY "User can access their own company settings" ON public.company_settings FOR ALL USING (company_id = get_company_id_for_user());
CREATE POLICY "User can access their own company data" ON public.refunds FOR ALL USING (company_id = get_company_id_for_user());
CREATE POLICY "User can access their own company data" ON public.feedback FOR ALL USING (company_id = get_company_id_for_user());
CREATE POLICY "User can access their own company data" ON public.export_jobs FOR ALL USING (company_id = get_company_id_for_user());
CREATE POLICY "User can access their own company data" ON public.channel_fees FOR ALL USING (company_id = get_company_id_for_user());

-- company_users has a slightly different policy, allowing users to see other members of their own company
CREATE POLICY "Enable read access for company members" ON public.company_users FOR SELECT USING (company_id = get_company_id_for_user());

-- ============================================================================
-- Step 5: Make New User Trigger More Robust
-- ============================================================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
  company_id_to_set uuid;
  sanitized_company_name text;
BEGIN
  -- Sanitize and validate the company name from the user metadata
  sanitized_company_name := BTRIM(new.raw_user_meta_data->>'company_name');
  
  -- If the sanitized name is empty or null, provide a fallback name
  IF sanitized_company_name IS NULL OR sanitized_company_name = '' THEN
    sanitized_company_name := new.email || '''s Company';
  END IF;

  -- Limit the length to prevent errors
  sanitized_company_name := LEFT(sanitized_company_name, 255);

  -- Create the company and capture the new company's ID
  INSERT INTO public.companies (name, owner_id)
  VALUES (sanitized_company_name, new.id)
  RETURNING id INTO company_id_to_set;

  -- Update the user's app_metadata with the new company_id
  -- This is the critical step for making the company_id available in the JWT
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id_to_set)
  WHERE id = new.id;
  
  -- Also add the user to the company_users table as Owner
  INSERT INTO public.company_users (user_id, company_id, role)
  VALUES (new.id, company_id_to_set, 'Owner');

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop the existing trigger if it exists, then recreate it.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

