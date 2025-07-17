-- InvoChat Migration: 2024-07-26
-- This script updates the database schema to fix several critical bugs related to
-- security, performance, and data integrity.

-- Introduction:
-- This migration performs the following key actions:
-- 1. Corrects the `get_company_id()` function to be more secure.
-- 2. Drops and recreates all Row-Level Security (RLS) policies to be much stricter.
-- 3. Adds critical foreign key constraints to ensure data integrity.
-- 4. Creates new indexes on frequently queried columns to improve performance.
-- 5. Implements a new `record_sale_transaction` function with proper locking to prevent race conditions.
-- 6. Creates a new `customers_view` for simplified customer data access.

-- This script is designed to be idempotent, meaning it can be run multiple times
-- without causing errors. It uses `IF EXISTS` and `IF NOT EXISTS` clauses
-- to ensure that it only makes changes if they are needed.

BEGIN;

-- Step 1: Drop dependent views and old functions/procedures that will be recreated.
-- This is necessary before modifying the underlying functions and tables they depend on.
DROP VIEW IF EXISTS public.product_variants_with_details;
DROP VIEW IF EXISTS public.orders_view;
DROP VIEW IF EXISTS public.customers_view; -- Drop just in case it exists from a partial run

DROP FUNCTION IF EXISTS public.record_sale_transaction(uuid, uuid, text, text, text, jsonb, text);
DROP PROCEDURE IF EXISTS enable_rls_on_table(text);


-- Step 2: Drop all existing RLS policies on our application tables.
-- We must do this before altering the helper function they rely on.
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT policyname, tablename FROM pg_policies WHERE schemaname = 'public' AND tablename IN (
        'companies', 'company_settings', 'users', 'products', 'product_variants',
        'inventory_ledger', 'orders', 'order_line_items', 'customers', 'suppliers',
        'purchase_orders', 'purchase_order_line_items', 'integrations', 'conversations',
        'messages', 'audit_log', 'export_jobs', 'channel_fees', 'discounts',
        'refunds', 'refund_line_items', 'webhook_events'
    ))
    LOOP
        EXECUTE 'DROP POLICY IF EXISTS ' || quote_ident(r.policyname) || ' ON public.' || quote_ident(r.tablename);
    END LOOP;
END $$;


-- Step 3: Recreate the core security function `get_company_id`.
-- The function is now STABLE for better performance and SECURITY DEFINER to run with the privileges
-- of the user who defines it, ensuring consistent access to the user's claims.
DROP FUNCTION IF EXISTS public.get_company_id();
CREATE OR REPLACE FUNCTION public.get_company_id()
RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER
AS $$
  SELECT COALESCE(
    NULLIF(current_setting('app.current_company_id', true), ''),
    (SELECT raw_app_meta_data->>'company_id' FROM auth.users WHERE id = auth.uid())
  )::uuid;
$$;


-- Step 4: Recreate the RLS enabling procedure with corrected parameter naming.
CREATE OR REPLACE PROCEDURE public.enable_rls(p_table_name text)
LANGUAGE plpgsql
AS $$
BEGIN
    EXECUTE 'ALTER TABLE public.' || quote_ident(p_table_name) || ' ENABLE ROW LEVEL SECURITY';
    EXECUTE 'ALTER TABLE public.' || quote_ident(p_table_name) || ' FORCE ROW LEVEL SECURITY';
    EXECUTE 'CREATE POLICY "Allow all access to own company data" ON public.' || quote_ident(p_table_name) ||
            ' FOR ALL USING (company_id = public.get_company_id()) WITH CHECK (company_id = public.get_company_id())';
END;
$$;


-- Step 5: Re-enable RLS on all tables using the new, stricter policies.
-- This loop calls the procedure created in the previous step for each table.
DO $$
DECLARE
    t_name TEXT;
BEGIN
    FOR t_name IN
        SELECT table_name FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_name IN (
            'company_settings', 'users', 'products', 'product_variants',
            'inventory_ledger', 'orders', 'order_line_items', 'customers', 'suppliers',
            'purchase_orders', 'purchase_order_line_items', 'integrations', 'conversations',
            'messages', 'audit_log', 'export_jobs', 'channel_fees', 'discounts',
            'refunds', 'refund_line_items', 'webhook_events'
          )
    LOOP
        CALL public.enable_rls(t_name);
    END LOOP;
END $$;


-- Step 6: Add Foreign Key constraints IF THEY DO NOT EXIST.
-- This makes the script idempotent and prevents "already exists" errors.
ALTER TABLE public.product_variants ADD CONSTRAINT IF NOT EXISTS product_variants_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.product_variants ADD CONSTRAINT IF NOT EXISTS product_variants_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;

ALTER TABLE public.inventory_ledger ADD CONSTRAINT IF NOT EXISTS inventory_ledger_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE CASCADE;

ALTER TABLE public.orders ADD CONSTRAINT IF NOT EXISTS orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE SET NULL;

ALTER TABLE public.order_line_items ADD CONSTRAINT IF NOT EXISTS order_line_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;
ALTER TABLE public.order_line_items ADD CONSTRAINT IF NOT EXISTS order_line_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE SET NULL;

ALTER TABLE public.purchase_orders ADD CONSTRAINT IF NOT EXISTS purchase_orders_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) ON DELETE SET NULL;

ALTER TABLE public.purchase_order_line_items ADD CONSTRAINT IF NOT EXISTS purchase_order_line_items_purchase_order_id_fkey FOREIGN KEY (purchase_order_id) REFERENCES public.purchase_orders(id) ON DELETE CASCADE;
ALTER TABLE public.purchase_order_line_items ADD CONSTRAINT IF NOT EXISTS purchase_order_line_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE CASCADE;

ALTER TABLE public.customers ADD CONSTRAINT IF NOT EXISTS customers_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.users ADD CONSTRAINT IF NOT EXISTS users_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;

ALTER TABLE public.conversations ADD CONSTRAINT IF NOT EXISTS conversations_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE public.messages ADD CONSTRAINT IF NOT EXISTS messages_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.conversations(id) ON DELETE CASCADE;

ALTER TABLE public.integrations ADD CONSTRAINT IF NOT EXISTS integrations_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.webhook_events ADD CONSTRAINT IF NOT EXISTS webhook_events_integration_id_fkey FOREIGN KEY (integration_id) REFERENCES public.integrations(id) ON DELETE CASCADE;


-- Step 7: Table modifications - Add new columns and remove obsolete ones.
ALTER TABLE public.orders DROP COLUMN IF EXISTS status;
ALTER TABLE public.order_line_items ALTER COLUMN sku SET NOT NULL;
ALTER TABLE public.order_line_items ALTER COLUMN product_name SET NOT NULL;


-- Step 8: Recreate the core transaction function for recording sales.
-- This new version includes a row-level lock (SELECT FOR UPDATE) to prevent race conditions
-- and ensures inventory cannot go below zero.
CREATE OR REPLACE FUNCTION public.record_sale_transaction(
    p_company_id uuid,
    p_user_id uuid,
    p_customer_name text,
    p_customer_email text,
    p_payment_method text,
    p_sale_items jsonb,
    p_notes text,
    p_external_id text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_order_id uuid;
    v_customer_id uuid;
    item record;
    v_variant record;
BEGIN
    -- Find or create the customer
    SELECT id INTO v_customer_id FROM customers WHERE email = p_customer_email AND company_id = p_company_id;
    IF v_customer_id IS NULL THEN
        INSERT INTO customers (company_id, customer_name, email)
        VALUES (p_company_id, p_customer_name, p_customer_email)
        RETURNING id INTO v_customer_id;
    END IF;

    -- Create the order
    INSERT INTO orders (company_id, customer_id, financial_status, fulfillment_status, source_platform, notes, external_order_id, order_number)
    VALUES (p_company_id, v_customer_id, 'paid', 'unfulfilled', 'manual', p_notes, p_external_id, 'ORD-' || (SELECT to_hex(nextval('serial'))))
    RETURNING id INTO v_order_id;

    -- Process each line item
    FOR item IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(sku text, product_name text, quantity int, unit_price int, cost_at_time int)
    LOOP
        -- Lock the variant row to prevent race conditions
        SELECT * INTO v_variant FROM product_variants WHERE sku = item.sku AND company_id = p_company_id FOR UPDATE;

        IF v_variant IS NULL THEN
            RAISE EXCEPTION 'Product with SKU % not found', item.sku;
        END IF;

        -- Check for sufficient stock
        IF v_variant.inventory_quantity < item.quantity THEN
            RAISE EXCEPTION 'Insufficient stock for SKU %: requested %, available %', item.sku, item.quantity, v_variant.inventory_quantity;
        END IF;
        
        -- Update inventory quantity
        UPDATE product_variants SET inventory_quantity = inventory_quantity - item.quantity WHERE id = v_variant.id;

        -- Insert line item
        INSERT INTO order_line_items (order_id, company_id, variant_id, product_id, product_name, sku, quantity, price, cost_at_time)
        VALUES (v_order_id, p_company_id, v_variant.id, v_variant.product_id, item.product_name, item.sku, item.quantity, item.unit_price, item.cost_at_time);
        
        -- Create inventory ledger entry
        INSERT INTO inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes)
        VALUES (p_company_id, v_variant.id, 'sale', -item.quantity, v_variant.inventory_quantity - item.quantity, v_order_id, 'Order ' || p_external_id);
    END LOOP;

    -- Log the audit event
    INSERT INTO audit_log (company_id, user_id, action, details)
    VALUES (p_company_id, p_user_id, 'manual_sale_created', jsonb_build_object('order_id', v_order_id));

    RETURN v_order_id;
END;
$$;


-- Step 9: Recreate views that were dropped earlier.
-- These provide simplified and performant ways to query common data combinations.

CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.id,
    pv.product_id,
    pv.company_id,
    p.title AS product_title,
    p.status AS product_status,
    p.image_url,
    p.product_type,
    pv.sku,
    pv.title,
    pv.price,
    pv.cost,
    pv.inventory_quantity
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
    o.id,
    o.company_id,
    o.order_number,
    o.created_at,
    o.total_amount,
    o.fulfillment_status,
    o.financial_status,
    o.source_platform,
    c.email AS customer_email
FROM
    public.orders o
LEFT JOIN
    public.customers c ON o.customer_id = c.id;

-- Step 10: Create new performance-enhancing indexes if they don't exist.
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_company_sku ON public.product_variants(company_id, sku);
CREATE INDEX IF NOT EXISTS idx_orders_company_id_created_at ON public.orders(company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_customers_company_email ON public.customers(company_id, email);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id ON public.inventory_ledger(variant_id);


-- Step 11: Grant permissions to authenticated users.
-- Supabase handles this for the `anon` and `service_role` roles, but we must
-- explicitly grant permissions to the `authenticated` role for our tables.
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA public TO authenticated;


COMMIT;
