
-- This script migrates an existing database to the latest schema.
-- It is designed to be idempotent and safe to run multiple times.

DO $$
BEGIN

-- Drop the old trigger from the auth schema if it exists.
-- This is necessary to resolve dependency issues from previous broken scripts.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Drop the old function if it exists.
DROP FUNCTION IF EXISTS handle_new_user();

-- Create the helper function to get the company_id from the JWT.
-- This function is used by the RLS policies.
CREATE OR REPLACE FUNCTION public.get_company_id()
RETURNS uuid
LANGUAGE sql STABLE
AS $$
  SELECT NULLIF(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid;
$$;

-- Create the public.users table if it doesn't exist. This table will mirror
-- essential data from auth.users and include the user's role.
CREATE TABLE IF NOT EXISTS public.users (
    id uuid NOT NULL PRIMARY KEY,
    company_id uuid NOT NULL,
    email text,
    role text default 'Member',
    deleted_at timestamptz,
    created_at timestamptz
);

-- Add 'role' column to public.users if it doesn't exist
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS role text DEFAULT 'Member';

-- This function is called by the application after a new user signs up.
-- It creates a company, a user profile, and associates them.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_user_id uuid := auth.uid();
  v_user_email text;
  v_company_name text;
BEGIN
  -- Get user details from auth.users
  SELECT email, raw_app_meta_data->>'company_name' INTO v_user_email, v_company_name
  FROM auth.users WHERE id = v_user_id;

  -- Create a new company for the user
  INSERT INTO companies (name) VALUES (v_company_name)
  RETURNING id INTO v_company_id;

  -- Create a profile for the user in the public.users table
  INSERT INTO users (id, company_id, email, role)
  VALUES (v_user_id, v_company_id, v_user_email, 'Owner');
  
  -- Update the user's app_metadata with the new company_id and role
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', v_company_id, 'role', 'Owner')
  WHERE id = v_user_id;

  RETURN v_company_id;
END;
$$;


-- Helper procedure to apply consistent RLS policies to tables.
CREATE OR REPLACE PROCEDURE apply_rls_policies(table_name text)
LANGUAGE plpgsql
AS $$
BEGIN
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', table_name);
    
    -- Drop old policies if they exist by name
    EXECUTE format('DROP POLICY IF EXISTS "Allow all access to own company data" ON public.%I;', table_name);
    EXECUTE format('DROP POLICY IF EXISTS "Allow read access to own company" ON public.%I;', table_name);
    
    -- Correctly apply policy based on the table
    IF table_name = 'companies' THEN
        -- The 'companies' table's company_id is its own 'id' column
        EXECUTE format('CREATE POLICY "Allow read access to own company" ON public.companies FOR SELECT USING (id = public.get_company_id());', table_name);
    ELSE
        -- All other tables use a 'company_id' foreign key
        EXECUTE format('CREATE POLICY "Allow all access to own company data" ON public.%I FOR ALL USING (company_id = public.get_company_id()) WITH CHECK (company_id = public.get_company_id());', table_name);
    END IF;
END;
$$;


-- Apply RLS to all relevant tables
DO $$
DECLARE
    t text;
    tables_to_secure text[] := ARRAY[
        'companies', 'users', 'company_settings', 'products', 'product_variants',
        'suppliers', 'customers', 'orders', 'order_line_items', 'refunds',
        'refund_line_items', 'purchase_orders', 'purchase_order_line_items',
        'inventory_ledger', 'integrations', 'conversations', 'messages', 'audit_log',
        'export_jobs', 'webhook_events', 'channel_fees', 'discounts'
    ];
BEGIN
    FOREACH t IN ARRAY tables_to_secure
    LOOP
        CALL apply_rls_policies(t);
    END LOOP;
END;
$$;


-- Update VIEW definitions to be safe and replacable
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.id,
    pv.product_id,
    pv.company_id,
    pv.sku,
    pv.title,
    pv.option1_name,
    pv.option1_value,
    pv.option2_name,
    pv.option2_value,
    pv.option3_name,
    pv.option3_value,
    pv.barcode,
    pv.price,
    pv.compare_at_price,
    pv.cost,
    pv.inventory_quantity,
    pv.location,
    pv.external_variant_id,
    p.title AS product_title,
    p.product_type,
    p.status AS product_status,
    p.image_url
FROM
    public.product_variants pv
JOIN
    public.products p ON pv.product_id = p.id;


-- Recreate indexes if they don't exist
CREATE INDEX IF NOT EXISTS idx_users_company_id ON public.users(company_id);
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_company_id ON public.product_variants(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_sku ON public.product_variants(sku);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers(company_id);
CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON public.suppliers(company_id);

END $$;
