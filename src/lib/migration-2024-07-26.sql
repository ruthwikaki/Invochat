-- InvoChat - Migration Script
--
-- This script updates the database schema to the latest version,
-- addressing critical performance, security, and data integrity issues.
--
-- It is designed to be idempotent and can be re-run safely if it fails.

BEGIN;

-- =================================================================
-- Step 1: Drop dependent views and policies that will be rebuilt.
-- We must drop these first to avoid dependency errors.
-- =================================================================

-- Drop the view that depends on the 'status' column we are about to remove.
DROP VIEW IF EXISTS public.orders_view;
DROP VIEW IF EXISTS public.product_variants_with_details;

-- Drop all existing RLS policies on tables. We will re-create them with a more secure model.
-- This loop-based approach is robust and handles all user-defined policies.
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT policyname, tablename FROM pg_policies WHERE schemaname = 'public') LOOP
        EXECUTE 'DROP POLICY IF EXISTS ' || quote_ident(r.policyname) || ' ON public.' || quote_ident(r.tablename);
    END LOOP;
END $$;


-- =================================================================
-- Step 2: Drop and recreate functions with updated definitions.
-- =================================================================

-- The get_company_id() function is being updated to be more secure.
-- We must drop it first because its signature is changing.
DROP FUNCTION IF EXISTS public.get_company_id();
CREATE OR REPLACE FUNCTION public.get_company_id(p_user_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_company_id uuid;
BEGIN
    SELECT company_id INTO v_company_id FROM users WHERE id = p_user_id;
    RETURN v_company_id;
END;
$$;
REVOKE ALL ON FUNCTION public.get_company_id(p_user_id uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_company_id(p_user_id uuid) TO authenticated;

-- This procedure enables RLS and is updated for clarity.
-- It must be dropped first because the parameter name is changing.
DROP PROCEDURE IF EXISTS enable_rls_on_table(text);
CREATE OR REPLACE PROCEDURE enable_rls_on_table(p_table_name text)
LANGUAGE plpgsql
AS $$
BEGIN
    EXECUTE 'ALTER TABLE public.' || quote_ident(p_table_name) || ' ENABLE ROW LEVEL SECURITY';
    EXECUTE 'ALTER TABLE public.' || quote_ident(p_table_name) || ' FORCE ROW LEVEL SECURITY';
END;
$$;


-- =================================================================
-- Step 3: Modify table structures
-- =================================================================

-- Add the 'cost_at_time' column to order_line_items to accurately track historical profit.
ALTER TABLE public.order_line_items ADD COLUMN IF NOT EXISTS cost_at_time integer;

-- Remove the now-unused 'status' column from the orders table.
ALTER TABLE public.orders DROP COLUMN IF EXISTS status;

-- Add an idempotency key to purchase_orders to prevent duplicate PO creation on retries.
ALTER TABLE public.purchase_orders ADD COLUMN IF NOT EXISTS idempotency_key UUID;
CREATE INDEX IF NOT EXISTS po_idempotency_key_idx ON public.purchase_orders(idempotency_key);

-- Add a location column to product_variants.
ALTER TABLE public.product_variants ADD COLUMN IF NOT EXISTS location TEXT;

-- =================================================================
-- Step 4: Add Foreign Key Constraints for data integrity
-- These are dropped first (IF EXISTS) to make the script re-runnable.
-- =================================================================

ALTER TABLE public.product_variants DROP CONSTRAINT IF EXISTS product_variants_company_id_fkey;
ALTER TABLE public.product_variants ADD CONSTRAINT product_variants_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;

ALTER TABLE public.product_variants DROP CONSTRAINT IF EXISTS product_variants_product_id_fkey;
ALTER TABLE public.product_variants ADD CONSTRAINT product_variants_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;

ALTER TABLE public.order_line_items DROP CONSTRAINT IF EXISTS order_line_items_variant_id_fkey;
ALTER TABLE public.order_line_items ADD CONSTRAINT order_line_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE SET NULL;

ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_customer_id_fkey;
ALTER TABLE public.orders ADD CONSTRAINT orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE SET NULL;

ALTER TABLE public.purchase_orders DROP CONSTRAINT IF EXISTS purchase_orders_supplier_id_fkey;
ALTER TABLE public.purchase_orders ADD CONSTRAINT purchase_orders_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) ON DELETE SET NULL;

ALTER TABLE public.purchase_order_line_items DROP CONSTRAINT IF EXISTS purchase_order_line_items_purchase_order_id_fkey;
ALTER TABLE public.purchase_order_line_items ADD CONSTRAINT purchase_order_line_items_purchase_order_id_fkey FOREIGN KEY (purchase_order_id) REFERENCES public.purchase_orders(id) ON DELETE CASCADE;

ALTER TABLE public.purchase_order_line_items DROP CONSTRAINT IF EXISTS purchase_order_line_items_variant_id_fkey;
ALTER TABLE public.purchase_order_line_items ADD CONSTRAINT purchase_order_line_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE CASCADE;


-- =================================================================
-- Step 5: Recreate views with the new schema.
-- =================================================================

-- Recreate the product variants view to include new details.
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

-- Recreate the orders view without the removed 'status' column.
CREATE OR REPLACE VIEW public.orders_view AS
SELECT
    o.*,
    c.email AS customer_email,
    i.shop_name AS source_platform
FROM
    public.orders o
LEFT JOIN
    public.customers c ON o.customer_id = c.id
LEFT JOIN
    public.integrations i ON o.source_platform = i.platform AND o.company_id = i.company_id;

-- =================================================================
-- Step 6: Recreate and apply secure Row-Level Security policies.
-- =================================================================

-- Helper array of all tables that need RLS.
DO $$
DECLARE
    tables text[] := array[
        'companies', 'company_settings', 'users', 'products', 'product_variants',
        'orders', 'order_line_items', 'customers', 'suppliers',
        'integrations', 'conversations', 'messages', 'inventory_ledger',
        'purchase_orders', 'purchase_order_line_items', 'webhook_events',
        'audit_log', 'export_jobs', 'channel_fees'
    ];
    tbl text;
BEGIN
    FOREACH tbl IN ARRAY tables LOOP
        -- Create the policy
        EXECUTE format('CREATE POLICY "Allow all access to own company data" ON public.%I FOR ALL USING (company_id = public.get_company_id(auth.uid())) WITH CHECK (company_id = public.get_company_id(auth.uid()));', tbl);
        -- Enable RLS on the table
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', tbl);
        EXECUTE format('ALTER TABLE public.%I FORCE ROW LEVEL SECURITY;', tbl);
    END LOOP;
END $$;


-- Special policy for the users table to allow users to see others in their own company.
CREATE POLICY "Allow users to see other users in their company" ON public.users FOR SELECT
USING (
  company_id = public.get_company_id(auth.uid())
);


-- =================================================================
-- Step 7: Update core functions for transactional integrity.
-- =================================================================

-- This function is now safe from race conditions.
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
    v_total_amount integer := 0;
    v_item jsonb;
    v_variant_id uuid;
    v_current_stock integer;
BEGIN
    -- Upsert customer and get ID
    INSERT INTO public.customers (company_id, customer_name, email)
    VALUES (p_company_id, p_customer_name, p_customer_email)
    ON CONFLICT (company_id, email) DO UPDATE SET customer_name = EXCLUDED.customer_name
    RETURNING id INTO v_customer_id;

    -- Create the order
    INSERT INTO public.orders (company_id, customer_id, financial_status, fulfillment_status, total_amount, notes, external_order_id, order_number)
    VALUES (p_company_id, v_customer_id, 'paid', 'unfulfilled', 0, p_notes, p_external_id, 'ORD-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))
    RETURNING id INTO v_order_id;

    -- Loop through items to create line items and update stock
    FOREACH v_item IN ARRAY p_sale_items
    LOOP
        -- Find the variant_id based on SKU
        SELECT id INTO v_variant_id FROM public.product_variants
        WHERE company_id = p_company_id AND sku = (v_item->>'sku');

        -- If variant exists, lock the row, update stock, and create line item
        IF v_variant_id IS NOT NULL THEN
            -- CRITICAL: Lock the variant row to prevent race conditions
            SELECT inventory_quantity INTO v_current_stock FROM public.product_variants WHERE id = v_variant_id FOR UPDATE;

            -- Create the order line item
            INSERT INTO public.order_line_items (order_id, company_id, variant_id, product_name, sku, quantity, price, cost_at_time)
            VALUES (
                v_order_id,
                p_company_id,
                v_variant_id,
                v_item->>'product_name',
                v_item->>'sku',
                (v_item->>'quantity')::integer,
                (v_item->>'unit_price')::integer,
                (v_item->>'cost_at_time')::integer
            );

            v_total_amount := v_total_amount + ((v_item->>'quantity')::integer * (v_item->>'unit_price')::integer);

            -- Record in the ledger
            INSERT INTO public.inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes)
            VALUES (
                p_company_id,
                v_variant_id,
                'sale',
                -1 * (v_item->>'quantity')::integer,
                v_current_stock - (v_item->>'quantity')::integer,
                v_order_id,
                'Order ' || (SELECT order_number FROM public.orders WHERE id = v_order_id)
            );
        ELSE
            RAISE WARNING 'SKU % not found for company %, skipping line item.', v_item->>'sku', p_company_id;
        END IF;
    END LOOP;

    -- Final update to the order with the calculated total amount
    UPDATE public.orders SET total_amount = v_total_amount WHERE id = v_order_id;

    RETURN v_order_id;
END;
$$;


-- =================================================================
-- Final: Commit the transaction
-- =================================================================

COMMIT;

-- Provide feedback
SELECT 'Migration script completed successfully.';
