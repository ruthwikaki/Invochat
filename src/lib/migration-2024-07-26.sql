
-- =================================================================
-- MIGRATION SCRIPT from old schema to the new, more robust schema
--
-- This script is designed to be idempotent and can be re-run if it
-- fails midway. It handles dropping and recreating objects to ensure
-- a clean state.
--
-- Key changes in this migration:
-- 1.  Strengthens Row-Level Security (RLS) policies.
-- 2.  Adds transaction-safe functions for inventory updates.
-- 3.  Adds missing foreign key constraints and indexes.
-- 4.  Cleans up unused columns and views.
-- =================================================================


-- Step 1: Drop dependent views before altering tables
-- -----------------------------------------------------------------
DROP VIEW IF EXISTS public.orders_view;
DROP VIEW IF EXISTS public.customers_view;


-- Step 2: Drop dependent triggers before altering functions
-- -----------------------------------------------------------------
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();


-- Step 3: Create the new handle_new_user function
-- This function is responsible for setting up a new company and user profile
-- when a new user signs up.
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  company_id uuid;
  user_email text;
  user_company_name text;
BEGIN
  -- Extract user email and company name from the JWT
  user_email := new.email;
  user_company_name := new.raw_app_meta_data->>'company_name';

  -- Create a new company for the user
  INSERT INTO public.companies (name)
  VALUES (user_company_name)
  RETURNING id INTO company_id;

  -- Create a corresponding user profile in the public.users table
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (new.id, company_id, user_email, 'Owner');

  -- Update the user's app_metadata in auth.users to include the new company_id and role
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id, 'role', 'Owner')
  WHERE id = new.id;

  RETURN new;
END;
$$;

-- Recreate the trigger to call the new function on user creation
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();


-- Step 4: Drop the old get_company_id() function and recreate it.
-- This function is used by RLS policies to get the current user's company_id.
-- -----------------------------------------------------------------
DROP VIEW IF EXISTS public.product_variants_with_details; -- Drop dependent view
DROP FUNCTION IF EXISTS public.get_company_id();

CREATE OR REPLACE FUNCTION public.get_company_id()
RETURNS UUID
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    current_setting('request.jwt.claims', true)::jsonb->>'company_id',
    (SELECT company_id FROM public.users WHERE id = auth.uid())
  )::uuid;
$$;


-- Step 5: Clean up and add constraints to the products and variants tables
-- -----------------------------------------------------------------
ALTER TABLE public.product_variants DROP CONSTRAINT IF EXISTS product_variants_product_id_fkey;
ALTER TABLE public.product_variants ADD CONSTRAINT product_variants_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;

ALTER TABLE public.product_variants DROP CONSTRAINT IF EXISTS product_variants_company_id_fkey;
ALTER TABLE public.product_variants ADD CONSTRAINT product_variants_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


-- Step 6: Clean up the orders and order_line_items tables
-- -----------------------------------------------------------------
ALTER TABLE public.orders DROP COLUMN IF EXISTS status;

ALTER TABLE public.order_line_items DROP CONSTRAINT IF EXISTS order_line_items_company_id_fkey;
ALTER TABLE public.order_line_items ADD CONSTRAINT order_line_items_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;

ALTER TABLE public.order_line_items DROP CONSTRAINT IF EXISTS order_line_items_order_id_fkey;
ALTER TABLE public.order_line_items ADD CONSTRAINT order_line_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;

-- Ensure SKU is never null on a line item
ALTER TABLE public.order_line_items ALTER COLUMN sku SET NOT NULL;


-- Step 7: Create the RLS helper procedures
-- These functions dynamically enable RLS on all tables in the public schema.
-- -----------------------------------------------------------------
DROP PROCEDURE IF EXISTS enable_rls_on_table(text);
CREATE OR REPLACE PROCEDURE enable_rls_on_table(p_table_name TEXT)
LANGUAGE plpgsql
AS $$
BEGIN
  EXECUTE 'ALTER TABLE public.' || quote_ident(p_table_name) || ' ENABLE ROW LEVEL SECURITY';
  EXECUTE 'ALTER TABLE public.' || quote_ident(p_table_name) || ' FORCE ROW LEVEL SECURITY';
  
  -- Drop old policies if they exist, then create the new, correct one
  EXECUTE 'DROP POLICY IF EXISTS "Allow all access to own company data" ON public.' || quote_ident(p_table_name);

  -- Correctly handle the 'companies' table, which has 'id' instead of 'company_id'
  IF p_table_name = 'companies' THEN
    EXECUTE 'CREATE POLICY "Allow all access to own company data" ON public.companies FOR ALL USING (id = public.get_company_id())';
  ELSE
    EXECUTE 'CREATE POLICY "Allow all access to own company data" ON public.' || quote_ident(p_table_name) || ' FOR ALL USING (company_id = public.get_company_id())';
  END IF;

END;
$$;

CREATE OR REPLACE PROCEDURE enable_rls_for_all_tables()
LANGUAGE plpgsql
AS $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public') LOOP
    CALL enable_rls_on_table(r.tablename);
  END LOOP;
END;
$$;

-- Execute the procedure to apply RLS to all tables
CALL enable_rls_for_all_tables();


-- Step 8: Recreate the views with the new schema
-- -----------------------------------------------------------------
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

CREATE OR REPLACE VIEW public.customers_view AS
SELECT
    c.id,
    c.company_id,
    c.customer_name,
    c.email,
    c.total_orders,
    c.total_spent,
    c.first_order_date,
    c.created_at
FROM
    public.customers c;

CREATE OR REPLACE VIEW public.orders_view AS
SELECT
    o.*,
    c.customer_name,
    c.email AS customer_email
FROM
    public.orders o
LEFT JOIN
    public.customers c ON o.customer_id = c.id;


-- Step 9: Create the record_sale_transaction function with locking
-- This is a critical function to prevent race conditions during inventory updates.
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_sale_transaction(
    p_company_id uuid,
    p_user_id uuid,
    p_customer_name text,
    p_customer_email text,
    p_payment_method text,
    p_notes text,
    p_sale_items jsonb[],
    p_external_id text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
    v_customer_id uuid;
    v_order_id uuid;
    v_total_amount integer := 0;
    v_item jsonb;
    v_variant_id uuid;
    v_quantity integer;
    v_unit_price integer;
    v_cost_at_time integer;
    v_current_stock integer;
BEGIN
    -- Find or create the customer
    SELECT id INTO v_customer_id FROM public.customers
    WHERE company_id = p_company_id AND email = p_customer_email;

    IF v_customer_id IS NULL THEN
        INSERT INTO public.customers (company_id, customer_name, email)
        VALUES (p_company_id, p_customer_name, p_customer_email)
        RETURNING id INTO v_customer_id;
    END IF;

    -- Create the order
    INSERT INTO public.orders (company_id, customer_id, total_amount, notes, external_order_id)
    VALUES (p_company_id, v_customer_id, 0, p_notes, p_external_id)
    RETURNING id INTO v_order_id;

    -- Process each line item
    FOREACH v_item IN ARRAY p_sale_items LOOP
        SELECT id, cost INTO v_variant_id, v_cost_at_time FROM public.product_variants
        WHERE company_id = p_company_id AND sku = (v_item->>'sku');

        v_quantity := (v_item->>'quantity')::integer;
        v_unit_price := (v_item->>'unit_price')::integer;
        v_total_amount := v_total_amount + (v_quantity * v_unit_price);

        IF v_variant_id IS NOT NULL THEN
            -- CRITICAL: Lock the variant row to prevent race conditions
            SELECT inventory_quantity INTO v_current_stock FROM public.product_variants
            WHERE id = v_variant_id FOR UPDATE;

            -- Update the inventory quantity
            UPDATE public.product_variants SET inventory_quantity = v_current_stock - v_quantity
            WHERE id = v_variant_id;

            -- Create an inventory ledger entry
            INSERT INTO public.inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id)
            VALUES (p_company_id, v_variant_id, 'sale', -v_quantity, v_current_stock - v_quantity, v_order_id);

            -- Insert the order line item
            INSERT INTO public.order_line_items (order_id, company_id, variant_id, quantity, price, cost_at_time)
            VALUES (v_order_id, p_company_id, v_variant_id, v_quantity, v_unit_price, v_cost_at_time);
        END IF;
    END LOOP;

    -- Update the final total on the order
    UPDATE public.orders SET total_amount = v_total_amount WHERE id = v_order_id;

    -- Log the audit event
    INSERT INTO public.audit_log (company_id, user_id, action, details)
    VALUES (p_company_id, p_user_id, 'sale_recorded', jsonb_build_object('order_id', v_order_id, 'total', v_total_amount));

    RETURN v_order_id;
END;
$$;


-- Step 10: Create final indexes for performance
-- -----------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_sku_company ON public.product_variants(sku, company_id);
CREATE INDEX IF NOT EXISTS idx_orders_company_id_created_at ON public.orders(company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers(company_id);
CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON public.suppliers(company_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id ON public.inventory_ledger(variant_id);


-- Step 11: Set a comment on the schema to mark completion
-- -----------------------------------------------------------------
COMMENT ON SCHEMA public IS 'Migration to schema version 2024-07-26 completed successfully.';

-- End of migration script
