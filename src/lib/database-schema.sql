
-- Drop all data from application tables for a fresh start.
-- This script will remove all transactional data but preserve table structures.
-- NOTE: It also deletes users from auth.users. Run with caution.
CREATE OR REPLACE PROCEDURE reset_all_data()
LANGUAGE plpgsql
AS $$
BEGIN
  -- Disable triggers to avoid foreign key constraint issues during truncation
  SET session_replication_role = 'replica';

  -- Truncate all transactional and user-related tables
  TRUNCATE TABLE
    public.order_line_items,
    public.orders,
    public.purchase_order_line_items,
    public.purchase_orders,
    public.inventory_ledger,
    public.customers,
    public.product_variants,
    public.products,
    public.suppliers,
    public.company_users,
    public.companies,
    public.integrations,
    public.channel_fees,
    public.feedback,
    public.conversations,
    public.messages,
    public.audit_log,
    public.imports,
    public.export_jobs,
    public.webhook_events
  RESTART IDENTITY CASCADE;

  -- Delete all users from the auth schema
  DELETE FROM auth.users;
  
  -- Re-enable triggers
  SET session_replication_role = 'origin';
  
  RAISE NOTICE 'All application data has been reset.';
END;
$$;


-- RLS Policies
-- 1. Enable RLS on all tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.imports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;


-- 2. Create a function to get the company_id from the user's claims
CREATE OR REPLACE FUNCTION get_company_id_for_user(user_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT company_id
  FROM public.company_users
  WHERE public.company_users.user_id = user_id
  LIMIT 1;
$$;

-- 3. Create policies
-- Generic policy for tables with a direct company_id column
CREATE OR REPLACE PROCEDURE create_company_based_rls_policy(table_name text)
LANGUAGE plpgsql
AS $$
BEGIN
  EXECUTE format(
    'DROP POLICY IF EXISTS "User can access their own company''s data" ON public.%I; ' ||
    'CREATE POLICY "User can access their own company''s data" ' ||
    'ON public.%I FOR ALL ' ||
    'USING (company_id = get_company_id_for_user(auth.uid())) ' ||
    'WITH CHECK (company_id = get_company_id_for_user(auth.uid()));',
    table_name, table_name
  );
END;
$$;

-- Apply the generic policy to all relevant tables
DO $$
DECLARE
  t text;
BEGIN
  FOR t IN
    SELECT tablename FROM pg_tables
    WHERE schemaname = 'public' AND 'company_id' = ANY(
      SELECT column_name FROM information_schema.columns 
      WHERE table_schema = 'public' AND table_name = tablename
    )
  LOOP
    EXECUTE 'SELECT create_company_based_rls_policy(''' || t || ''')';
  END LOOP;
END;
$$;

-- Special policy for company_users table
DROP POLICY IF EXISTS "Users can view other users in their own company" ON public.company_users;
CREATE POLICY "Users can view other users in their own company"
ON public.company_users FOR SELECT
USING (company_id = get_company_id_for_user(auth.uid()));

DROP POLICY IF EXISTS "Owners and Admins can manage users in their company" ON public.company_users;
CREATE POLICY "Owners and Admins can manage users in their company"
ON public.company_users FOR ALL
USING (company_id = get_company_id_for_user(auth.uid()))
WITH CHECK (
    company_id = get_company_id_for_user(auth.uid()) AND
    (
        SELECT role FROM public.company_users WHERE user_id = auth.uid()
    ) IN ('Owner', 'Admin')
);


--
-- This function is called by a trigger when a new user signs up.
-- It creates a new company, links the user to it, and sets default settings.
--
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  new_company_id uuid;
BEGIN
  -- Generate new company ID
  new_company_id := gen_random_uuid();
  
  -- Create company
  INSERT INTO public.companies (id, name, owner_id, created_at)
  VALUES (
    new_company_id,
    COALESCE(NEW.raw_user_meta_data->>'company_name', NEW.email || '''s Company'),
    NEW.id,
    now()
  );

  -- Create user record
  INSERT INTO public.company_users (user_id, company_id, role)
  VALUES (
    NEW.id,
    new_company_id,
    'Owner'
  );

  -- Create company settings with defaults
  INSERT INTO public.company_settings (
    company_id
  )
  VALUES (
    new_company_id
  );

  RETURN NEW;
END;
$$;


--
-- This trigger automatically calls the handle_new_user function
-- when a new user is created in the auth.users table.
--
CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();



--
-- This function allows checking a user's role within their company.
--
CREATE OR REPLACE FUNCTION public.check_user_permission(p_user_id uuid, p_required_role company_role)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM public.company_users cu
    WHERE cu.user_id = p_user_id
      AND (
        CASE p_required_role
          WHEN 'Member' THEN cu.role IN ('Member', 'Admin', 'Owner')
          WHEN 'Admin' THEN cu.role IN ('Admin', 'Owner')
          WHEN 'Owner' THEN cu.role = 'Owner'
          ELSE FALSE
        END
      )
  );
END;
$$;


--
-- This procedure safely removes a user from a company.
--
CREATE OR REPLACE PROCEDURE public.remove_user_from_company(p_user_id uuid, p_company_id uuid)
LANGUAGE plpgsql
AS $$
BEGIN
    DELETE FROM public.company_users
    WHERE user_id = p_user_id AND company_id = p_company_id;
END;
$$;

--
-- This procedure updates a user's role within a company.
--
CREATE OR REPLACE PROCEDURE public.update_user_role_in_company(p_user_id uuid, p_company_id uuid, p_new_role company_role)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE public.company_users
    SET role = p_new_role
    WHERE user_id = p_user_id AND company_id = p_company_id;
END;
$$;
