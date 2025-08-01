
-- Drop functions if they exist
DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;
DROP FUNCTION IF EXISTS public.get_company_id_for_user(uuid) CASCADE;

-- Drop dependent policies before dropping the function they use
-- This section dynamically finds and drops policies that depend on the old function signature.
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
            (qual ILIKE '%get_company_id_for_user(auth.uid())%')
    LOOP
        EXECUTE policy_record.drop_command;
    END LOOP;
END;
$$;


-- Create a function to securely get company_id from JWT
CREATE OR REPLACE FUNCTION public.get_my_company_id()
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- This function extracts the company_id from the session's JWT claims.
  -- It's a secure way to get the company ID without causing recursive queries.
  RETURN (current_setting('request.jwt.claims', true)::jsonb -> 'app_metadata' ->> 'company_id')::uuid;
EXCEPTION
  WHEN OTHERS THEN
    -- If the claim doesn't exist or is invalid, return NULL safely.
    RETURN NULL;
END;
$$;

-- Create a robust function to handle new user sign-ups
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    company_id_to_set uuid;
    v_company_name text;
BEGIN
    -- Sanitize and validate the company name from the user's metadata
    v_company_name := BTRIM(NEW.raw_user_meta_data->>'company_name');
    
    -- If the company name is empty or just whitespace after trimming, use a fallback name.
    -- This prevents errors from empty company names during signup.
    IF v_company_name IS NULL OR v_company_name = '' THEN
        v_company_name := (NEW.raw_user_meta_data->>'email') || '''s Company';
    END IF;

    -- Insert a new company for the new user, using the validated company name
    INSERT INTO public.companies (name, owner_id)
    VALUES (v_company_name, NEW.id)
    RETURNING id INTO company_id_to_set;

    -- Link the new user to the new company with the 'Owner' role
    INSERT INTO public.company_users (user_id, company_id, role)
    VALUES (NEW.id, company_id_to_set, 'Owner');
    
    -- Update the user's app_metadata in the auth schema to include their new company_id
    -- This is crucial for the JWT to contain the company_id claim.
    UPDATE auth.users
    SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id_to_set)
    WHERE id = NEW.id;

    RETURN NEW;
END;
$$;

-- Create the trigger on the auth.users table to fire the handle_new_user function
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_user();

-- Recreate all Row-Level Security (RLS) policies using the new, secure function

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
ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refunds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;

-- Policy creation for each table
-- Using "CREATE POLICY ... AS PERMISSIVE FOR ALL USING (...)" is a concise way to handle read/write/delete
CREATE POLICY "Allow full access to own company data" ON public.products
FOR ALL USING (company_id = public.get_my_company_id());

CREATE POLICY "Allow full access to own company data" ON public.product_variants
FOR ALL USING (company_id = public.get_my_company_id());

CREATE POLICY "Allow full access to own company data" ON public.orders
FOR ALL USING (company_id = public.get_my_company_id());

CREATE POLICY "Allow full access to own company data" ON public.order_line_items
FOR ALL USING (company_id = public.get_my_company_id());

CREATE POLICY "Allow full access to own company data" ON public.customers
FOR ALL USING (company_id = public.get_my_company_id());

CREATE POLICY "Allow full access to own company data" ON public.suppliers
FOR ALL USING (company_id = public.get_my_company_id());

CREATE POLICY "Allow full access to own company data" ON public.purchase_orders
FOR ALL USING (company_id = public.get_my_company_id());

CREATE POLICY "Allow full access to own company data" ON public.purchase_order_line_items
FOR ALL USING (company_id = public.get_my_company_id());

CREATE POLICY "Allow full access to own company data" ON public.integrations
FOR ALL USING (company_id = public.get_my_company_id());

CREATE POLICY "Allow full access to own company data" ON public.webhook_events
FOR ALL USING (company_id = public.get_my_company_id());

CREATE POLICY "Allow full access to own company data" ON public.inventory_ledger
FOR ALL USING (company_id = public.get_my_company_id());

CREATE POLICY "Allow access to own messages" ON public.messages
FOR ALL USING (company_id = public.get_my_company_id());

CREATE POLICY "Allow access to own company audit log" ON public.audit_log
FOR ALL USING (company_id = public.get_my_company_id());

CREATE POLICY "Allow full access to own company settings" ON public.company_settings
FOR ALL USING (company_id = public.get_my_company_id());

CREATE POLICY "Enable read access for company members" ON public.company_users
FOR SELECT USING (company_id = public.get_my_company_id());

CREATE POLICY "Allow full access to own company channel fees" ON public.channel_fees
FOR ALL USING (company_id = public.get_my_company_id());

CREATE POLICY "Allow full access to own company data" ON public.refunds
FOR ALL USING (company_id = public.get_my_company_id());

CREATE POLICY "Allow access to own company feedback" ON public.feedback
FOR ALL USING (company_id = public.get_my_company_id());

CREATE POLICY "Allow access to own company export jobs" ON public.export_jobs
FOR ALL USING (company_id = public.get_my_company_id());

