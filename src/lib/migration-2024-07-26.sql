
-- InvoChat Migration Script
-- Date: 2024-07-26
--
-- This script migrates the database schema from its initial version to a more robust,
-- secure, and performant state. It addresses several critical issues including:
-- - Security: Overhauls Row-Level Security (RLS) for all tables.
-- - Data Integrity: Adds foreign keys and NOT NULL constraints.
-- - Performance: Adds numerous indexes for faster queries.
-- - Race Conditions: Updates the sale recording function to be atomic.
-- - Schema Cleanup: Removes unused columns and standardizes naming.

BEGIN;

-- =================================================================
-- Step 1: Drop dependent objects before making breaking changes
-- =================================================================
-- Drop views that depend on columns/functions we are about to change.
DROP VIEW IF EXISTS public.customers_view;
DROP VIEW IF EXISTS public.orders_view;
DROP VIEW IF EXISTS public.product_variants_with_details;


-- Drop old RLS policies from all relevant tables.
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT tablename, policyname FROM pg_policies WHERE schemaname = 'public') LOOP
        EXECUTE 'DROP POLICY IF EXISTS "' || r.policyname || '" ON public."' || r.tablename || '"';
    END LOOP;
END $$;

-- Drop old functions that will be recreated
DROP PROCEDURE IF EXISTS enable_rls_on_table(text);


-- =================================================================
-- Step 2: Modify helper functions
-- =================================================================
-- Update the helper function for getting the company ID from the session.
-- This is a critical function for all RLS policies.
DROP FUNCTION IF EXISTS public.get_company_id();
CREATE OR REPLACE FUNCTION public.get_company_id()
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
BEGIN
  -- This function is now STABLE and SECURITY DEFINER for performance and security.
  -- It safely retrieves the company_id set by the middleware.
  return nullif(current_setting('app.current_company_id', true), '')::uuid;
END;
$$;


-- =================================================================
-- Step 3: Alter tables (add/remove columns, constraints, indexes)
-- =================================================================

-- Add idempotency key to purchase_orders to prevent duplicates
ALTER TABLE public.purchase_orders ADD COLUMN IF NOT EXISTS idempotency_key UUID;
ALTER TABLE public.purchase_order_line_items ADD COLUMN IF NOT EXISTS company_id UUID;

-- Add required columns and constraints to product_variants
ALTER TABLE public.product_variants
  ADD COLUMN IF NOT EXISTS company_id UUID NOT NULL,
  ADD CONSTRAINT product_variants_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;

-- Add cost_at_time to order_line_items
ALTER TABLE public.order_line_items ADD COLUMN IF NOT EXISTS cost_at_time INTEGER;

-- Make SKU not nullable on order line items
ALTER TABLE public.order_line_items ALTER COLUMN sku SET NOT NULL;

-- Remove unused/problematic columns from the orders table
ALTER TABLE public.orders DROP COLUMN IF EXISTS status;
ALTER TABLE public.orders DROP COLUMN IF EXISTS items;

-- Add missing foreign key constraints for data integrity
ALTER TABLE public.company_settings ADD CONSTRAINT company_settings_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.customers ADD CONSTRAINT customers_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.integrations ADD CONSTRAINT integrations_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.products ADD CONSTRAINT products_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.suppliers ADD CONSTRAINT suppliers_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.users ADD CONSTRAINT users_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.orders ADD CONSTRAINT orders_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.order_line_items ADD CONSTRAINT order_line_items_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.purchase_orders ADD CONSTRAINT purchase_orders_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_sku_company ON public.product_variants(sku, company_id);
CREATE INDEX IF NOT EXISTS idx_orders_company_id_created_at ON public.orders(company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON public.order_line_items(variant_id);
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers(company_id);
CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON public.suppliers(company_id);
CREATE INDEX IF NOT EXISTS idx_integrations_company_id ON public.integrations(company_id);


-- =================================================================
-- Step 4: Recreate views with correct structure
-- =================================================================

-- Recreate orders_view
CREATE OR REPLACE VIEW public.orders_view AS
SELECT
  o.id,
  o.company_id,
  o.order_number,
  o.created_at,
  o.total_amount,
  o.fulfillment_status,
  o.financial_status,
  o.source_platform,
  c.email as customer_email
FROM public.orders o
LEFT JOIN public.customers c ON o.customer_id = c.id;

-- Recreate customers_view
CREATE OR REPLACE VIEW public.customers_view AS
SELECT
  id,
  company_id,
  customer_name,
  email,
  total_orders,
  total_spent,
  first_order_date,
  created_at
FROM public.customers
WHERE deleted_at IS NULL;

-- Recreate product_variants_with_details view
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
  pv.id,
  pv.product_id,
  pv.company_id,
  pv.sku,
  pv.title,
  pv.price,
  pv.cost,
  pv.inventory_quantity,
  pv.external_variant_id,
  pv.location,
  p.title AS product_title,
  p.status AS product_status,
  p.image_url,
  p.product_type
FROM public.product_variants pv
JOIN public.products p ON pv.product_id = p.id;


-- =================================================================
-- Step 5: Recreate stored procedures and functions
-- =================================================================

-- Updated procedure to enable RLS on a table with a standard company_id check
CREATE OR REPLACE PROCEDURE public.enable_rls_on_table(p_table_name text)
LANGUAGE plpgsql
AS $$
BEGIN
  EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', p_table_name);
  EXECUTE format('CREATE POLICY "Allow all access to own company data" ON public.%I FOR ALL USING (company_id = get_company_id());', p_table_name);
END;
$$;

-- Updated function for recording sales to be atomic and prevent race conditions
DROP FUNCTION IF EXISTS public.record_sale_transaction(uuid,uuid,text,text,text,text,jsonb,text,uuid);
CREATE OR REPLACE FUNCTION public.record_sale_transaction(
    p_company_id uuid,
    p_user_id uuid,
    p_customer_name text,
    p_customer_email text,
    p_payment_method text,
    p_notes text,
    p_sale_items jsonb,
    p_external_id text DEFAULT NULL,
    p_order_id_override uuid DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_customer_id uuid;
    v_order_id uuid;
    v_order_number text;
    item record;
    v_variant_id uuid;
    v_product_id uuid;
    v_product_name text;
    v_variant_title text;
    v_total_amount integer := 0;
    v_current_stock integer;
BEGIN
    -- Find or create customer
    IF p_customer_email IS NOT NULL THEN
        SELECT id INTO v_customer_id FROM public.customers WHERE company_id = p_company_id AND email = p_customer_email;
        IF v_customer_id IS NULL THEN
            INSERT INTO public.customers (company_id, customer_name, email)
            VALUES (p_company_id, p_customer_name, p_customer_email)
            RETURNING id INTO v_customer_id;
        END IF;
    END IF;

    -- Create order
    v_order_number := 'ORD-' || (SELECT to_hex(nextval('orders_id_seq')));
    INSERT INTO public.orders (id, company_id, order_number, customer_id, total_amount, source_platform, notes, financial_status, fulfillment_status)
    VALUES (COALESCE(p_order_id_override, gen_random_uuid()), p_company_id, v_order_number, v_customer_id, 0, 'manual', p_notes, 'paid', 'unfulfilled')
    RETURNING id INTO v_order_id;

    -- Process line items
    FOR item IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(sku text, product_name text, quantity integer, unit_price integer, cost_at_time integer)
    LOOP
        -- Find variant and product IDs
        SELECT pv.id, pv.product_id, p.title, pv.title INTO v_variant_id, v_product_id, v_product_name, v_variant_title
        FROM public.product_variants pv
        JOIN public.products p ON pv.product_id = p.id
        WHERE pv.sku = item.sku AND pv.company_id = p_company_id;

        IF v_variant_id IS NULL THEN
            RAISE EXCEPTION 'Product with SKU % not found', item.sku;
        END IF;

        -- THIS IS THE CRITICAL LOCK TO PREVENT RACE CONDITIONS
        SELECT inventory_quantity INTO v_current_stock FROM public.product_variants WHERE id = v_variant_id FOR UPDATE;

        IF v_current_stock < item.quantity THEN
             RAISE EXCEPTION 'Insufficient stock for SKU %: Tried to sell %, but only % available.', item.sku, item.quantity, v_current_stock;
        END IF;

        -- Insert line item
        INSERT INTO public.order_line_items (order_id, company_id, product_id, variant_id, product_name, variant_title, sku, quantity, price, cost_at_time)
        VALUES (v_order_id, p_company_id, v_product_id, v_variant_id, v_product_name, v_variant_title, item.sku, item.quantity, item.unit_price, item.cost_at_time);

        v_total_amount := v_total_amount + (item.quantity * item.unit_price);
    END LOOP;

    -- Update order total
    UPDATE public.orders SET total_amount = v_total_amount WHERE id = v_order_id;

    -- Log audit event
    INSERT INTO public.audit_log (company_id, user_id, action, details)
    VALUES (p_company_id, p_user_id, 'sale_recorded', jsonb_build_object('order_id', v_order_id, 'total', v_total_amount));

    RETURN v_order_id;
END;
$$;

-- =================================================================
-- Step 6: Re-apply RLS policies
-- =================================================================
-- Loop through all tables and apply the new, standardized RLS policy.
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (
        SELECT table_name
        FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name NOT LIKE 'pg_%' AND table_name NOT LIKE 'sql_%'
          AND 'company_id' IN (SELECT column_name FROM information_schema.columns WHERE table_name = r.table_name)
    ) LOOP
        -- Skip tables that should not have RLS or have custom RLS
        IF r.table_name NOT IN ('users') THEN
             CALL public.enable_rls_on_table(r.table_name);
        END IF;
    END LOOP;
END $$;

-- Apply specific RLS policy for the 'users' table
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow users to see other members of their own company" ON public.users
  FOR SELECT
  USING (company_id = get_company_id());

COMMIT;

    