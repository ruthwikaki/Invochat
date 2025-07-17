
-- InvoChat Migration: 2024-07-26
-- This migration script addresses critical security, performance, and data integrity issues.

-- Step 0: Set a timeout for the transaction to prevent it from hanging.
SET statement_timeout = '300s';

BEGIN;

-- Step 1: Drop dependent views before altering underlying tables.
-- The orders_view depends on the 'status' column we will drop from 'orders'.
DROP VIEW IF EXISTS public.orders_view;
DROP VIEW IF EXISTS public.customers_view;

-- Step 2: Drop existing RLS policies on all tables.
-- This is necessary before we can modify the helper functions they depend on.
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT tablename, policyname FROM pg_policies WHERE schemaname = 'public') LOOP
        EXECUTE 'DROP POLICY IF EXISTS ' || quote_ident(r.policyname) || ' ON public.' || quote_ident(r.tablename);
    END LOOP;
END$$;


-- Step 3: Drop and recreate the company ID helper function with SECURITY DEFINER.
-- This is a critical security fix.
DROP FUNCTION IF EXISTS public.get_company_id();
CREATE OR REPLACE FUNCTION public.get_company_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT COALESCE(current_setting('app.current_company_id', true), auth.uid())::uuid;
$$;
REVOKE ALL ON FUNCTION public.get_company_id() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_company_id() TO authenticated;


-- Step 4: Drop the old procedure before recreating it with a corrected parameter name.
-- Fixes "cannot change name of input parameter" error.
DROP PROCEDURE IF EXISTS enable_rls_on_table(text);
CREATE OR REPLACE PROCEDURE enable_rls_on_table(p_table_name TEXT)
LANGUAGE plpgsql
AS $$
BEGIN
  EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', p_table_name);
  EXECUTE format('
    CREATE POLICY "Allow all access to own company data"
    ON public.%I
    FOR ALL
    USING (company_id = get_company_id())
    WITH CHECK (company_id = get_company_id());
  ', p_table_name);
END;
$$;


-- Step 5: Re-enable RLS on all tables with the new, more secure policies.
DO $$
DECLARE
  tbl_name TEXT;
BEGIN
  FOR tbl_name IN
    SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename NOT LIKE 'pg_%' AND tablename NOT LIKE 'sql_%'
  LOOP
    -- Check if the table has a 'company_id' column before applying the policy
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = tbl_name AND column_name = 'company_id'
    ) THEN
      -- RAISE NOTICE 'Enabling RLS for table: %', tbl_name;
      CALL enable_rls_on_table(tbl_name);
    END IF;
  END LOOP;
END$$;


-- Step 6: Alter the 'orders' table.
-- This was a source of previous errors. We can now safely drop the column.
ALTER TABLE public.orders
DROP COLUMN IF EXISTS status;

-- Step 7: Recreate the views that were dropped in Step 1.
CREATE OR REPLACE VIEW public.orders_view AS
SELECT
    o.id,
    o.company_id,
    o.order_number,
    o.external_order_id,
    o.customer_id,
    o.financial_status,
    o.fulfillment_status,
    o.currency,
    o.subtotal,
    o.total_tax,
    o.total_shipping,
    o.total_discounts,
    o.total_amount,
    o.source_platform,
    o.created_at,
    o.updated_at,
    c.email AS customer_email
FROM
    public.orders o
LEFT JOIN
    public.customers c ON o.customer_id = c.id;

CREATE OR REPLACE VIEW public.customers_view AS
SELECT
    c.id,
    c.company_id,
    c.customer_name,
    c.email,
    c.total_orders, -- Use the maintained column
    c.total_spent,
    c.first_order_date,
    c.deleted_at,
    c.created_at
FROM
    public.customers c;


-- Step 8: Update the record_sale_transaction function to prevent race conditions.
CREATE OR REPLACE FUNCTION public.record_sale_transaction(
    p_company_id uuid,
    p_user_id uuid,
    p_customer_name text,
    p_customer_email text,
    p_payment_method text,
    p_notes text,
    p_sale_items jsonb[],
    p_external_id text
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
    v_customer_id uuid;
    v_order_id uuid;
    v_variant_id uuid;
    item jsonb;
    v_sku text;
    v_quantity int;
    v_unit_price int;
    v_cost_at_time int;
    v_product_name text;
    v_current_stock int;
BEGIN
    -- Step 1: Find or create the customer
    SELECT id INTO v_customer_id
    FROM public.customers
    WHERE email = p_customer_email AND company_id = p_company_id;

    IF v_customer_id IS NULL THEN
        INSERT INTO public.customers (company_id, customer_name, email)
        VALUES (p_company_id, p_customer_name, p_customer_email)
        RETURNING id INTO v_customer_id;
    END IF;

    -- Step 2: Create the order
    INSERT INTO public.orders (company_id, customer_id, total_amount, order_number, external_order_id)
    VALUES (
        p_company_id,
        v_customer_id,
        (SELECT sum((i->>'unit_price')::int * (i->>'quantity')::int) FROM unnest(p_sale_items) i),
        'ORD-' || upper(substr(md5(random()::text), 0, 8)),
        p_external_id
    )
    RETURNING id INTO v_order_id;

    -- Step 3: Process line items and update inventory
    FOREACH item IN ARRAY p_sale_items
    LOOP
        v_sku := item->>'sku';
        v_quantity := (item->>'quantity')::int;
        v_unit_price := (item->>'unit_price')::int;
        v_cost_at_time := (item->>'cost_at_time')::int;
        v_product_name := item->>'product_name';

        -- Find the corresponding product variant
        SELECT id INTO v_variant_id
        FROM public.product_variants
        WHERE sku = v_sku AND company_id = p_company_id;

        IF v_variant_id IS NULL THEN
            RAISE EXCEPTION 'Product with SKU % not found.', v_sku;
        END IF;

        -- ** CRITICAL FIX: Lock the row and check for sufficient stock **
        SELECT inventory_quantity INTO v_current_stock
        FROM public.product_variants
        WHERE id = v_variant_id FOR UPDATE;

        IF v_current_stock < v_quantity THEN
            RAISE EXCEPTION 'Insufficient stock for SKU %: requested %, available %', v_sku, v_quantity, v_current_stock;
        END IF;

        -- Update inventory quantity
        UPDATE public.product_variants
        SET inventory_quantity = inventory_quantity - v_quantity
        WHERE id = v_variant_id;

        -- Insert into order_line_items
        INSERT INTO public.order_line_items (order_id, variant_id, company_id, product_name, sku, quantity, price, cost_at_time)
        VALUES (v_order_id, v_variant_id, p_company_id, v_product_name, v_sku, v_quantity, v_unit_price, v_cost_at_time);

        -- Insert into inventory_ledger
        INSERT INTO public.inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes)
        VALUES (p_company_id, v_variant_id, 'sale', -v_quantity, v_current_stock - v_quantity, v_order_id, 'Order ' || p_external_id);

    END LOOP;

    -- Update customer stats
    UPDATE public.customers
    SET
        total_orders = total_orders + 1,
        total_spent = total_spent + (SELECT total_amount FROM public.orders WHERE id = v_order_id),
        first_order_date = LEAST(first_order_date, (SELECT created_at::date FROM public.orders WHERE id = v_order_id))
    WHERE id = v_customer_id;

    RETURN v_order_id;

EXCEPTION
    WHEN OTHERS THEN
        RAISE;
END;
$$;

COMMIT;
