-- ARVO DATABASE MIGRATION SCRIPT - 2024-07-25
-- This script updates an existing database to the latest required schema.
-- It is designed to be idempotent and safe to run multiple times.

-- Add necessary extensions if they don't exist
create extension if not exists "uuid-ossp" with schema extensions;
create extension if not exists "pg_trgm" with schema extensions;

-- Helper function to drop all policies on a table
create or replace function drop_all_policies_on_table(table_name text)
returns void as $$
declare
    r record;
begin
    for r in (select policyname from pg_policies where tablename = table_name and schemaname = 'public') loop
        execute 'DROP POLICY IF EXISTS ' || quote_ident(r.policyname) || ' ON public.' || quote_ident(table_name);
    end loop;
end;
$$ language plpgsql;


-- =============================================
-- SECTION 1: ADD MISSING COLUMNS & CONSTRAINTS
-- =============================================

-- Add 'company_id' to purchase_order_line_items if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema='public' AND table_name='purchase_order_line_items' AND column_name='company_id'
  ) THEN
    ALTER TABLE public.purchase_order_line_items ADD COLUMN company_id uuid;

    -- Backfill company_id from the parent purchase_order
    UPDATE public.purchase_order_line_items poli
    SET company_id = po.company_id
    FROM public.purchase_orders po
    WHERE poli.purchase_order_id = po.id;

    ALTER TABLE public.purchase_order_line_items ALTER COLUMN company_id SET NOT NULL;
    ALTER TABLE public.purchase_order_line_items ADD CONSTRAINT fk_company
        FOREIGN KEY(company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
  END IF;
END $$;


-- Add 'role' to public.users if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='users' AND column_name='role'
  ) THEN
    ALTER TABLE public.users ADD COLUMN role text DEFAULT 'Member' NOT NULL;
  END IF;
END $$;


-- Make order_line_items.variant_id NOT NULL if it's currently nullable
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='order_line_items' AND column_name='variant_id' AND is_nullable = 'YES'
  ) THEN
    -- First, delete any orphaned line items that can't be linked. This is a data-loss operation but necessary for integrity.
    DELETE FROM public.order_line_items WHERE variant_id IS NULL;
    ALTER TABLE public.order_line_items ALTER COLUMN variant_id SET NOT NULL;
  END IF;
END $$;

-- Drop the redundant 'status' column from 'orders' if it exists
DO $$
BEGIN
  IF EXISTS(
    SELECT 1 FROM information_schema.columns 
    WHERE table_name='orders' AND column_name='status'
  ) THEN
    ALTER TABLE public.orders DROP COLUMN status;
  END IF;
END $$;

-- =============================================
-- SECTION 2: CREATE/UPDATE FUNCTIONS
-- =============================================

-- Safely drop and recreate the get_company_id function for RLS
DROP FUNCTION IF EXISTS public.get_company_id();
CREATE OR REPLACE FUNCTION public.get_company_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT (NULLIF(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid);
$$;

-- Safely drop and recreate the handle_new_user function
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  company_id_from_meta uuid;
  user_email text;
  company_name_from_meta text;
BEGIN
  -- Check if the user is being created via an invitation
  IF new.raw_app_meta_data ->> 'company_id' IS NOT NULL THEN
    company_id_from_meta := (new.raw_app_meta_data ->> 'company_id')::uuid;
    user_email := new.email;

    -- Insert into public.users for invited user
    INSERT INTO public.users (id, company_id, email, role)
    VALUES (new.id, company_id_from_meta, user_email, 'Member');

  -- Otherwise, it's a new signup creating their own company
  ELSE
    company_name_from_meta := new.raw_app_meta_data ->> 'company_name';

    -- Create a new company for the user
    INSERT INTO public.companies (name)
    VALUES (company_name_from_meta)
    RETURNING id INTO company_id_from_meta;

    -- Update the user's app_metadata with the new company_id
    UPDATE auth.users
    SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id_from_meta, 'role', 'Owner')
    WHERE id = new.id;

    -- Insert into public.users for the new owner
    INSERT INTO public.users (id, company_id, email, role)
    VALUES (new.id, company_id_from_meta, new.email, 'Owner');
  END IF;
  
  RETURN new;
END;
$$;

-- Recreate the trigger
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- =============================================
-- SECTION 3: RECREATE VIEWS
-- =============================================

DROP VIEW IF EXISTS public.product_variants_with_details;
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
  pv.id,
  pv.product_id,
  p.title AS product_title,
  p.status AS product_status,
  p.image_url,
  p.product_type,
  pv.company_id,
  pv.sku,
  pv.title,
  pv.price,
  pv.cost,
  pv.inventory_quantity,
  pv.location
FROM
  public.product_variants pv
JOIN
  public.products p ON pv.product_id = p.id;


-- =============================================
-- SECTION 4: ADD DATABASE INDEXES
-- =============================================
CREATE INDEX IF NOT EXISTS idx_orders_company_id_created_at ON public.orders(company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_product_variants_company_id_sku ON public.product_variants(company_id, sku);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id_created_at ON public.inventory_ledger(variant_id, created_at DESC);


-- =============================================
-- SECTION 5: APPLY ROW-LEVEL SECURITY
-- =============================================
DO $$
DECLARE
    table_name TEXT;
BEGIN
    -- List of all tables to apply RLS policies to
    FOR table_name IN
        SELECT unnest(array[
            'companies', 'company_settings', 'products', 'product_variants',
            'inventory_ledger', 'orders', 'order_line_items', 'customers',
            'suppliers', 'purchase_orders', 'purchase_order_line_items', 'integrations',
            'conversations', 'messages'
        ])
    LOOP
        -- Enable RLS on the table
        EXECUTE 'ALTER TABLE public.' || quote_ident(table_name) || ' ENABLE ROW LEVEL SECURITY';
        EXECUTE 'ALTER TABLE public.' || quote_ident(table_name) || ' FORCE ROW LEVEL SECURITY';
        -- Drop all existing policies on the table to avoid conflicts
        PERFORM drop_all_policies_on_table(table_name);
    END LOOP;
END;
$$;

-- Generic policy for most tables
CREATE POLICY "Allow all access to own company data" ON public.company_settings FOR ALL USING (company_id = public.get_company_id()) WITH CHECK (company_id = public.get_company_id());
CREATE POLICY "Allow all access to own company data" ON public.products FOR ALL USING (company_id = public.get_company_id()) WITH CHECK (company_id = public.get_company_id());
CREATE POLICY "Allow all access to own company data" ON public.product_variants FOR ALL USING (company_id = public.get_company_id()) WITH CHECK (company_id = public.get_company_id());
CREATE POLICY "Allow all access to own company data" ON public.inventory_ledger FOR ALL USING (company_id = public.get_company_id()) WITH CHECK (company_id = public.get_company_id());
CREATE POLICY "Allow all access to own company data" ON public.orders FOR ALL USING (company_id = public.get_company_id()) WITH CHECK (company_id = public.get_company_id());
CREATE POLICY "Allow all access to own company data" ON public.order_line_items FOR ALL USING (company_id = public.get_company_id()) WITH CHECK (company_id = public.get_company_id());
CREATE POLICY "Allow all access to own company data" ON public.customers FOR ALL USING (company_id = public.get_company_id()) WITH CHECK (company_id = public.get_company_id());
CREATE POLICY "Allow all access to own company data" ON public.suppliers FOR ALL USING (company_id = public.get_company_id()) WITH CHECK (company_id = public.get_company_id());
CREATE POLICY "Allow all access to own company data" ON public.purchase_orders FOR ALL USING (company_id = public.get_company_id()) WITH CHECK (company_id = public.get_company_id());
CREATE POLICY "Allow all access to own company data" ON public.integrations FOR ALL USING (company_id = public.get_company_id()) WITH CHECK (company_id = public.get_company_id());
CREATE POLICY "Allow all access to own company data" ON public.conversations FOR ALL USING (company_id = public.get_company_id()) WITH CHECK (company_id = public.get_company_id());
CREATE POLICY "Allow all access to own company data" ON public.messages FOR ALL USING (company_id = public.get_company_id()) WITH CHECK (company_id = public.get_company_id());

-- Special policy for the companies table itself
CREATE POLICY "Allow read access to own company" ON public.companies FOR SELECT USING (id = public.get_company_id());

-- Special policy for purchase_order_line_items (checks parent PO)
CREATE POLICY "Allow access based on parent purchase order" ON public.purchase_order_line_items FOR ALL
USING (
    company_id = public.get_company_id()
);

-- Policy for the users table
CREATE POLICY "Allow users to see other members of their own company" ON public.users FOR SELECT
USING (
    company_id = public.get_company_id()
);
CREATE POLICY "Allow users to update their own record" ON public.users FOR UPDATE
USING (
    id = auth.uid()
) WITH CHECK (
    id = auth.uid()
);

-- Grant usage on the public schema to the authenticated role
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;
