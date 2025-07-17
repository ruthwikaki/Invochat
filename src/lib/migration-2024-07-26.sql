-- ARVO DATABASE MIGRATION SCRIPT
-- This script updates the database schema to the latest version.
-- It is designed to be run once on an existing database.
-- FIX: 2024-07-26

BEGIN;

-- Step 1: Drop dependent views first to allow underlying table modifications.
DROP VIEW IF EXISTS public.product_variants_with_details;
DROP VIEW IF EXISTS public.orders_view;
DROP VIEW IF EXISTS public.customers_view;

-- Step 2: Drop all RLS policies that depend on the get_company_id() function.
DO $$
DECLARE
    r record;
BEGIN
    FOR r IN (SELECT policyname, tablename FROM pg_policies WHERE schemaname = 'public' AND tablename IN 
        ('companies', 'company_settings', 'users', 'products', 'product_variants', 
        'inventory_ledger', 'orders', 'order_line_items', 'customers', 'suppliers', 
        'purchase_orders', 'purchase_order_line_items', 'integrations', 'conversations', 
        'messages', 'audit_log', 'channel_fees', 'export_jobs', 'discounts', 
        'customer_addresses', 'refunds', 'refund_line_items', 'webhook_events'))
    LOOP
        EXECUTE 'DROP POLICY IF EXISTS ' || quote_ident(r.policyname) || ' ON public.' || quote_ident(r.tablename);
    END LOOP;
END $$;

-- Step 3: Now it's safe to drop and recreate the function.
DROP FUNCTION IF EXISTS public.get_company_id();
CREATE OR REPLACE FUNCTION public.get_company_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT current_setting('app.current_company_id', true)::uuid;
$$;
COMMENT ON FUNCTION public.get_company_id() IS 'A helper function to securely get the company ID from the current session settings.';

-- Step 4: Recreate RLS-enabling procedures
CREATE OR REPLACE PROCEDURE enable_rls_on_table(p_table_name text)
LANGUAGE plpgsql
AS $$
BEGIN
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', p_table_name);
    EXECUTE format('ALTER TABLE public.%I FORCE ROW LEVEL SECURITY', p_table_name);
END;
$$;

CREATE OR REPLACE PROCEDURE apply_rls_policies()
LANGUAGE plpgsql
AS $$
DECLARE
    table_name text;
BEGIN
    -- Loop through all tables that need RLS and apply the policies
    FOR table_name IN 
        SELECT t.table_name
        FROM (VALUES
            ('companies'), ('company_settings'), ('users'), ('products'), ('product_variants'),
            ('inventory_ledger'), ('orders'), ('order_line_items'), ('customers'),
            ('suppliers'), ('purchase_orders'), ('purchase_order_line_items'), ('integrations'), 
            ('conversations'), ('messages'), ('audit_log'), ('channel_fees'), ('export_jobs'), 
            ('discounts'), ('customer_addresses'), ('refunds'), ('refund_line_items'), ('webhook_events')
        ) AS t(table_name)
    LOOP
        -- Enable RLS for the table
        CALL enable_rls_on_table(table_name);

        -- Create the ownership policy
        EXECUTE format(
            'CREATE POLICY "Allow all access to own company data" ON public.%I FOR ALL USING (company_id = get_company_id()) WITH CHECK (company_id = get_company_id())',
            table_name
        );
    END LOOP;

    -- Special case for purchase_order_line_items to allow access based on the parent PO's company_id
    EXECUTE format(
        'CREATE POLICY "Allow all access based on parent PO" ON public.purchase_order_line_items FOR ALL USING (EXISTS (SELECT 1 FROM purchase_orders po WHERE po.id = purchase_order_id AND po.company_id = get_company_id()))'
    );
END;
$$;

-- Step 5: Add missing columns and modify existing ones.
ALTER TABLE public.purchase_orders
    ADD COLUMN IF NOT EXISTS idempotency_key uuid;

ALTER TABLE public.purchase_order_line_items
    ADD COLUMN IF NOT EXISTS company_id uuid;

UPDATE public.purchase_order_line_items poli
SET company_id = po.company_id
FROM public.purchase_orders po
WHERE poli.purchase_order_id = po.id AND poli.company_id IS NULL;

ALTER TABLE public.purchase_order_line_items
    ALTER COLUMN company_id SET NOT NULL;

-- Backfill NULL SKUs on order_line_items before adding NOT NULL constraint
UPDATE public.order_line_items
SET sku = 'UNKNOWN_SKU_' || id::text
WHERE sku IS NULL;

ALTER TABLE public.order_line_items
    ALTER COLUMN sku SET NOT NULL;
    
-- Step 6: Apply the new RLS policies
CALL apply_rls_policies();

-- Step 7: Recreate views
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
    c.*,
    (SELECT COUNT(*) FROM public.orders o WHERE o.customer_id = c.id AND o.company_id = c.company_id) AS total_orders,
    (SELECT SUM(o.total_amount) FROM public.orders o WHERE o.customer_id = c.id AND o.company_id = c.company_id) AS total_spent,
    (SELECT MIN(o.created_at) FROM public.orders o WHERE o.customer_id = c.id AND o.company_id = c.company_id) AS first_order_date
FROM
    public.customers c;

-- Step 8: Clean up old procedures that are no longer needed
DROP PROCEDURE IF EXISTS public.enable_rls_on_all_tables();

COMMIT;