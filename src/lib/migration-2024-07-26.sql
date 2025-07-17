
-- Migration Script - 2024-07-26
-- Fixes various schema inconsistencies, adds missing indexes, and strengthens RLS policies.

-- Start a transaction
BEGIN;

-- =================================================================
-- Step 1: Drop dependent objects (Views and Policies)
-- =================================================================

-- Drop views that depend on functions or columns we need to change.
DROP VIEW IF EXISTS public.product_variants_with_details CASCADE;
DROP VIEW IF EXISTS public.orders_view CASCADE;
DROP VIEW IF EXISTS public.customers_view CASCADE;

-- Create a procedure to drop all policies on a table.
-- This is necessary because we need to modify the get_company_id() function they depend on.
CREATE OR REPLACE PROCEDURE drop_all_policies_on_table(p_schema_name TEXT, p_table_name TEXT) AS $$
DECLARE
    r record;
BEGIN
    FOR r IN (SELECT policyname FROM pg_policies WHERE schemaname = p_schema_name AND tablename = p_table_name)
    LOOP
        EXECUTE 'DROP POLICY IF EXISTS ' || quote_ident(r.policyname) || ' ON ' || quote_ident(p_schema_name) || '.' || quote_ident(p_table_name);
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Drop all existing policies on all relevant tables
CALL drop_all_policies_on_table('public', 'companies');
CALL drop_all_policies_on_table('public', 'company_settings');
CALL drop_all_policies_on_table('public', 'users');
CALL drop_all_policies_on_table('public', 'products');
CALL drop_all_policies_on_table('public', 'product_variants');
CALL drop_all_policies_on_table('public', 'inventory_ledger');
CALL drop_all_policies_on_table('public', 'orders');
CALL drop_all_policies_on_table('public', 'order_line_items');
CALL drop_all_policies_on_table('public', 'customers');
CALL drop_all_policies_on_table('public', 'suppliers');
CALL drop_all_policies_on_table('public', 'purchase_orders');
CALL drop_all_policies_on_table('public', 'purchase_order_line_items');
CALL drop_all_policies_on_table('public', 'integrations');
CALL drop_all_policies_on_table('public', 'conversations');
CALL drop_all_policies_on_table('public', 'messages');
CALL drop_all_policies_on_table('public', 'audit_log');
CALL drop_all_policies_on_table('public', 'channel_fees');
CALL drop_all_policies_on_table('public', 'webhook_events');


-- =================================================================
-- Step 2: Modify Functions
-- =================================================================

-- Drop the old get_company_id function and recreate it with improved security and stability.
DROP FUNCTION IF EXISTS public.get_company_id();
CREATE OR REPLACE FUNCTION public.get_company_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT COALESCE(
    current_setting('app.current_company_id', true)::uuid,
    (SELECT company_id FROM public.users WHERE id = auth.uid())
  );
$$;


-- =================================================================
-- Step 3: Apply Table Schema Changes
-- =================================================================

-- Add company_id to purchase_order_line_items if it doesn't exist
ALTER TABLE public.purchase_order_line_items
ADD COLUMN IF NOT EXISTS company_id uuid;

-- Backfill company_id in purchase_order_line_items from the parent purchase_order
UPDATE public.purchase_order_line_items poli
SET company_id = po.company_id
FROM public.purchase_orders po
WHERE poli.purchase_order_id = po.id AND poli.company_id IS NULL;

-- Now that it's backfilled, enforce NOT NULL
ALTER TABLE public.purchase_order_line_items
ALTER COLUMN company_id SET NOT NULL;


-- Backfill NULL SKUs in order_line_items before making it NOT NULL.
-- This is a safety measure to prevent data integrity errors on existing records.
UPDATE public.order_line_items
SET sku = 'UNKNOWN-' || id::text
WHERE sku IS NULL;

-- Enforce SKU being required on order line items for data integrity.
ALTER TABLE public.order_line_items
ALTER COLUMN sku SET NOT NULL;

-- Standardize all money columns to INTEGER (for cents)
ALTER TABLE public.channel_fees
  ALTER COLUMN percentage_fee TYPE INTEGER USING (percentage_fee * 100)::integer,
  ALTER COLUMN fixed_fee TYPE INTEGER USING (fixed_fee * 100)::integer;

-- This column was removed in a previous step, but we ensure it's gone.
ALTER TABLE public.orders DROP COLUMN IF EXISTS status;

-- =================================================================
-- Step 4: Add Performance Indexes
-- =================================================================

-- Indexes for common query patterns
CREATE INDEX IF NOT EXISTS idx_orders_company_id_created_at ON public.orders(company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_product_variants_company_id_sku ON public.product_variants(company_id, sku);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_company_variant ON public.inventory_ledger(company_id, variant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_poli_company_id_fkey ON public.purchase_order_line_items(company_id);


-- =================================================================
-- Step 5: Recreate Views
-- =================================================================

-- Recreate views with correct joins and structure
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.id,
    pv.product_id,
    p.title AS product_title,
    p.status AS product_status,
    p.image_url,
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
    pv.created_at,
    pv.updated_at
FROM
    public.product_variants pv
JOIN
    public.products p ON pv.product_id = p.id;


CREATE OR REPLACE VIEW public.orders_view AS
SELECT
    o.id,
    o.company_id,
    o.order_number,
    o.external_order_id,
    o.customer_id,
    c.customer_name,
    c.email as customer_email,
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
    o.updated_at
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
    COALESCE(s.total_orders, 0) as total_orders,
    COALESCE(s.total_spent, 0) as total_spent,
    s.first_order_date,
    c.created_at
FROM
    public.customers c
LEFT JOIN (
    SELECT
        customer_id,
        count(*) as total_orders,
        sum(total_amount) as total_spent,
        min(created_at) as first_order_date
    FROM public.orders
    GROUP BY customer_id
) s ON c.id = s.customer_id
WHERE c.deleted_at IS NULL;


-- =================================================================
-- Step 6: Recreate RLS Policies
-- =================================================================

-- Drop the procedure helper to avoid leaving it in the schema
DROP PROCEDURE IF EXISTS drop_all_policies_on_table(TEXT, TEXT);

-- Procedure to enable RLS and apply a standard policy to a table
-- This must be dropped first before being recreated with parameter name change.
DROP PROCEDURE IF EXISTS public.enable_rls_on_table(text);
CREATE OR REPLACE PROCEDURE public.enable_rls_on_table(p_table_name TEXT) AS $$
BEGIN
    EXECUTE 'ALTER TABLE public.' || quote_ident(p_table_name) || ' ENABLE ROW LEVEL SECURITY';
    EXECUTE 'CREATE POLICY "Allow all access to own company data" ON public.' || quote_ident(p_table_name) ||
            ' FOR ALL USING (company_id = get_company_id()) WITH CHECK (company_id = get_company_id())';
END;
$$ LANGUAGE plpgsql;

-- A procedure to apply all policies.
CREATE OR REPLACE PROCEDURE apply_rls_policies() AS $$
DECLARE
    r record;
BEGIN
    -- Apply standard policy to all company-scoped tables
    FOR r IN (
        SELECT table_name FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name IN (
            'companies', 'company_settings', 'users', 'products', 'product_variants',
            'inventory_ledger', 'orders', 'order_line_items', 'customers',
            'suppliers', 'purchase_orders', 'integrations', 'conversations', 'messages',
            'audit_log', 'channel_fees', 'webhook_events'
        )
    )
    LOOP
        CALL enable_rls_on_table(r.table_name);
    END LOOP;

    -- Apply special policy for purchase_order_line_items
    ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
    CREATE POLICY "Allow all access based on parent PO" ON public.purchase_order_line_items
        FOR ALL
        USING (company_id = get_company_id())
        WITH CHECK (company_id = get_company_id());

END;
$$ LANGUAGE plpgsql;

-- Execute the procedure to apply all policies
CALL apply_rls_policies();

-- Clean up the helper procedure
DROP PROCEDURE IF EXISTS apply_rls_policies();

-- Commit the transaction
COMMIT;
