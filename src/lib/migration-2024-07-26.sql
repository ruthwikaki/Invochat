
-- =================================================================
-- MIGRATION SCRIPT - 2024-07-26
--
-- This script applies critical fixes to the database schema.
-- It is designed to be run ONCE on an existing database created
-- with the original database-schema.sql file.
--
-- Key Fixes:
-- 1. Inventory Race Condition: Updates the record_sale_transaction
--    function to use SELECT ... FOR UPDATE to prevent concurrency issues.
-- 2. Data Integrity: Enforces NOT NULL on critical columns.
-- 3. Security: Rebuilds all Row-Level Security (RLS) policies
--    to be more secure and robust.
-- 4. Performance: Adds missing indexes to frequently queried columns.
-- =================================================================

BEGIN;

-- =================================================================
-- Step 1: Define Utility Functions
-- =================================================================

-- Helper function to get the company_id from the JWT.
-- This function is crucial for multi-tenancy and RLS.
CREATE OR REPLACE FUNCTION public.get_company_id()
RETURNS UUID AS $$
DECLARE
    company_id_val UUID;
BEGIN
    company_id_val := (auth.jwt() -> 'app_metadata' ->> 'company_id')::UUID;
    IF company_id_val IS NULL THEN
        RAISE EXCEPTION 'company_id not found in JWT app_metadata';
    END IF;
    RETURN company_id_val;
END;
$$ LANGUAGE plpgsql STABLE;

-- =================================================================
-- Step 2: Drop dependent objects BEFORE modifying functions
-- =================================================================

-- Drop the trigger on auth.users that uses handle_new_user
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Drop dependent views
DROP VIEW IF EXISTS public.product_variants_with_details;
DROP VIEW IF EXISTS public.orders_view;
DROP VIEW IF EXISTS public.customers_view;

-- Drop ALL RLS policies on public tables that depend on get_company_id()
DO $$
DECLARE
    t_name TEXT;
BEGIN
    FOR t_name IN 
        SELECT table_name FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
    LOOP
        EXECUTE format('ALTER TABLE public.%I DISABLE ROW LEVEL SECURITY;', t_name);
        EXECUTE format('DROP POLICY IF EXISTS "Allow all access to own company data" ON public.%I;', t_name);
        EXECUTE format('DROP POLICY IF EXISTS "Allow read access to own company data" ON public.%I;', t_name);
    END LOOP;
END;
$$;


-- =================================================================
-- Step 3: Modify core functions
-- =================================================================

-- Drop old function
DROP FUNCTION IF EXISTS public.handle_new_user();

-- Create the new, corrected handle_new_user function
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  company_id_val UUID;
  user_role TEXT;
BEGIN
  -- Create a new company for the user
  INSERT INTO public.companies (name)
  VALUES (new.raw_app_meta_data->>'company_name')
  RETURNING id INTO company_id_val;

  -- Set the user's role to 'Owner'
  user_role := 'Owner';

  -- Insert into our public users table
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (new.id, company_id_val, new.email, user_role);

  -- Update the user's app_metadata with the new company_id and role
  UPDATE auth.users
  SET raw_app_meta_data = new.raw_app_meta_data || jsonb_build_object('company_id', company_id_val, 'role', user_role)
  WHERE id = new.id;
  
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Modify the record_sale_transaction function to prevent race conditions
CREATE OR REPLACE FUNCTION public.record_sale_transaction(
    p_company_id UUID,
    p_user_id UUID,
    p_customer_name TEXT,
    p_customer_email TEXT,
    p_payment_method TEXT,
    p_notes TEXT,
    p_sale_items JSONB[],
    p_external_id TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_customer_id UUID;
    v_order_id UUID;
    item JSONB;
    v_variant_id UUID;
    v_product_id UUID;
    v_product_name TEXT;
    v_price INT;
    v_cost_at_time INT;
    v_quantity INT;
    current_stock INT;
    v_subtotal INT := 0;
BEGIN
    -- Find or create customer
    SELECT id INTO v_customer_id FROM customers WHERE email = p_customer_email AND company_id = p_company_id;
    IF v_customer_id IS NULL THEN
        INSERT INTO customers (company_id, customer_name, email)
        VALUES (p_company_id, p_customer_name, p_customer_email)
        RETURNING id INTO v_customer_id;
    END IF;

    -- Create order
    INSERT INTO orders (company_id, customer_id, total_amount, subtotal, financial_status, fulfillment_status, external_order_id, order_number)
    VALUES (p_company_id, v_customer_id, 0, 0, 'paid', 'unfulfilled', p_external_id, 'ORD-' || nextval('order_number_seq'))
    RETURNING id INTO v_order_id;
    
    -- Process line items
    FOREACH item IN ARRAY p_sale_items LOOP
        SELECT id, product_id, price, cost INTO v_variant_id, v_product_id, v_price, v_cost_at_time
        FROM product_variants
        WHERE sku = (item->>'sku')::TEXT AND company_id = p_company_id;

        IF v_variant_id IS NULL THEN
            RAISE EXCEPTION 'Variant with SKU % not found', item->>'sku';
        END IF;

        v_quantity := (item->>'quantity')::INT;
        
        -- Lock the variant row to prevent race conditions
        SELECT inventory_quantity INTO current_stock FROM product_variants WHERE id = v_variant_id FOR UPDATE;

        -- Update inventory
        UPDATE product_variants SET inventory_quantity = inventory_quantity - v_quantity WHERE id = v_variant_id;
        
        -- Insert into ledger
        INSERT INTO inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes)
        VALUES (p_company_id, v_variant_id, 'sale', -v_quantity, current_stock - v_quantity, v_order_id, 'Order #' || (SELECT order_number FROM orders WHERE id=v_order_id));
        
        -- Get product name
        SELECT title INTO v_product_name FROM products WHERE id = v_product_id;

        -- Insert line item
        INSERT INTO order_line_items (order_id, company_id, product_id, variant_id, product_name, sku, quantity, price, cost_at_time)
        VALUES (v_order_id, p_company_id, v_product_id, v_variant_id, v_product_name, item->>'sku', v_quantity, v_price, v_cost_at_time);

        v_subtotal := v_subtotal + (v_price * v_quantity);
    END LOOP;

    -- Update order totals
    UPDATE orders SET subtotal = v_subtotal, total_amount = v_subtotal WHERE id = v_order_id;
    
    RETURN v_order_id;
END;
$$ LANGUAGE plpgsql;


-- =================================================================
-- Step 4: Re-create views
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

CREATE OR REPLACE VIEW public.orders_view AS
SELECT 
    o.*,
    c.customer_name,
    c.email AS customer_email
FROM 
    public.orders o
LEFT JOIN 
    public.customers c ON o.customer_id = c.id;

CREATE OR REPLACE VIEW public.customers_view AS
SELECT 
    id,
    company_id,
    customer_name,
    email,
    total_orders,
    total_spent,
    first_order_date,
    deleted_at,
    created_at
FROM 
    public.customers;


-- =================================================================
-- Step 5: Add table constraints
-- =================================================================

ALTER TABLE public.product_variants DROP CONSTRAINT IF EXISTS product_variants_company_id_fkey;
ALTER TABLE public.product_variants ADD CONSTRAINT product_variants_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;

ALTER TABLE public.order_line_items DROP CONSTRAINT IF EXISTS order_line_items_sku_not_empty;
ALTER TABLE public.order_line_items ADD CONSTRAINT order_line_items_sku_not_empty CHECK (sku IS NOT NULL AND sku <> '');


-- =================================================================
-- Step 6: Create performance indexes
-- =================================================================

CREATE INDEX IF NOT EXISTS idx_orders_created_at ON public.orders(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id ON public.inventory_ledger(variant_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_sku_company ON public.product_variants(sku, company_id);


-- =================================================================
-- Step 7: Re-create the trigger and RLS policies
-- =================================================================

-- Recreate trigger
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Function to enable RLS on all public tables
CREATE OR REPLACE FUNCTION enable_rls_for_all_tables() RETURNS void AS $$
DECLARE
    t_name TEXT;
BEGIN
    FOR t_name IN 
        SELECT table_name FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
    LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', t_name);
        EXECUTE format('ALTER TABLE public.%I FORCE ROW LEVEL SECURITY;', t_name);

        -- Specific policy for companies table
        IF t_name = 'companies' THEN
            EXECUTE format('CREATE POLICY "Allow all access to own company data" ON public.%I FOR ALL USING (id = public.get_company_id());', t_name);
        ELSE
            -- Policy for all other tables
            EXECUTE format('CREATE POLICY "Allow all access to own company data" ON public.%I FOR ALL USING (company_id = public.get_company_id());', t_name);
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Execute the function to apply RLS
SELECT enable_rls_for_all_tables();

-- Drop the helper function as it's no longer needed
DROP FUNCTION enable_rls_for_all_tables;


COMMIT;

-- Final message
SELECT 'Migration 2024-07-26 applied successfully.' as result;
