
-- Migration script to safely apply schema changes from July 26, 2024.

-- Step 1: Drop dependent views that use the 'get_company_id' function or rely on tables we will alter.
DROP VIEW IF EXISTS public.orders_view;
DROP VIEW IF EXISTS public.product_variants_with_details;

-- Step 2: Drop all existing RLS policies on public tables.
-- We must do this before dropping the function they depend on.

DO $$
DECLARE
    r record;
BEGIN
    -- Drop policies from tables that exist in the original schema
    FOR r IN (SELECT policyname, tablename FROM pg_policies WHERE schemaname = 'public' AND tablename IN 
        ('companies', 'company_settings', 'users', 'products', 'product_variants', 
         'inventory_ledger', 'orders', 'order_line_items', 'customers', 'suppliers', 
         'purchase_orders', 'integrations', 'conversations', 'messages', 'audit_log', 
         'channel_fees', 'purchase_order_line_items')) 
    LOOP
        EXECUTE 'DROP POLICY IF EXISTS ' || quote_ident(r.policyname) || ' ON public.' || quote_ident(r.tablename);
    END LOOP;
END $$;


-- Step 3: Drop and recreate the 'get_company_id' function to ensure it's up-to-date.
DROP FUNCTION IF EXISTS public.get_company_id();
CREATE OR REPLACE FUNCTION public.get_company_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT COALESCE(
    NULLIF(current_setting('app.current_company_id', true), ''),
    (SELECT raw_app_meta_data->>'company_id' FROM auth.users WHERE id = auth.uid())
  )::uuid;
$$;


-- Step 4: Apply all table alterations.

-- Add company_id to purchase_order_line_items for RLS.
ALTER TABLE public.purchase_order_line_items ADD COLUMN IF NOT EXISTS company_id uuid;

-- Backfill company_id in purchase_order_line_items from the parent purchase_order.
UPDATE public.purchase_order_line_items poli
SET company_id = po.company_id
FROM public.purchase_orders po
WHERE poli.purchase_order_id = po.id AND poli.company_id IS NULL;

-- Now that it's backfilled, enforce NOT NULL.
ALTER TABLE public.purchase_order_line_items ALTER COLUMN company_id SET NOT NULL;


-- Backfill any NULL SKUs in order_line_items before making it NOT NULL.
-- This prevents the migration from failing on existing data.
UPDATE public.order_line_items
SET sku = 'UNKNOWN-' || id::text
WHERE sku IS NULL;

-- Enforce NOT NULL on order_line_items columns.
ALTER TABLE public.order_line_items ALTER COLUMN product_id SET NOT NULL;
ALTER TABLE public.order_line_items ALTER COLUMN variant_id SET NOT NULL;
ALTER TABLE public.order_line_items ALTER COLUMN sku SET NOT NULL;


-- Drop the redundant 'status' column from the orders table.
ALTER TABLE public.orders DROP COLUMN IF EXISTS status;

-- Add missing indexes for performance.
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON public.orders(company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_product_variants_sku ON public.product_variants(company_id, sku);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id ON public.inventory_ledger(company_id, variant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_related_id ON public.inventory_ledger(company_id, related_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_external_id ON public.product_variants(company_id, external_variant_id);
CREATE INDEX IF NOT EXISTS idx_products_external_id ON public.products(company_id, external_product_id);


-- Step 5: Recreate views with the updated table structures.

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
    o.id,
    o.company_id,
    o.order_number,
    o.external_order_id,
    o.customer_id,
    o.financial_status,
    o.fulfillment_status,
    o.total_amount,
    o.source_platform,
    o.created_at,
    c.customer_name,
    c.email AS customer_email
FROM
    public.orders o
LEFT JOIN
    public.customers c ON o.customer_id = c.id;


-- Step 6: Create and apply a procedure to re-enable RLS on all tables.
CREATE OR REPLACE PROCEDURE enable_rls_on_table(p_table_name TEXT)
LANGUAGE plpgsql
AS $$
BEGIN
    EXECUTE 'ALTER TABLE public.' || quote_ident(p_table_name) || ' ENABLE ROW LEVEL SECURITY';
    EXECUTE 'ALTER TABLE public.' || quote_ident(p_table_name) || ' FORCE ROW LEVEL SECURITY';
END;
$$;


-- Step 7: Re-apply all RLS policies.

CREATE OR REPLACE PROCEDURE apply_rls_policies()
LANGUAGE plpgsql
AS $$
DECLARE
    table_name TEXT;
BEGIN
    -- Enable RLS for all tables
    PERFORM enable_rls_on_table(t.tbl)
    FROM (VALUES
        ('companies'), ('company_settings'), ('users'), ('products'), ('product_variants'),
        ('inventory_ledger'), ('orders'), ('order_line_items'), ('customers'),
        ('suppliers'), ('purchase_orders'), ('integrations'), ('conversations'), ('messages'),
        ('audit_log'), ('channel_fees'), ('purchase_order_line_items')
    ) AS t(tbl);

    -- Policy: Allow all access to a user's own company data
    CREATE POLICY "Allow all access to own company data" ON public.companies
    FOR ALL USING (id = public.get_company_id());

    -- Repeat for all other tables with a direct company_id column...
    CREATE POLICY "Allow all access to own company data" ON public.company_settings
    FOR ALL USING (company_id = public.get_company_id());

    CREATE POLICY "Allow all access to own company data" ON public.users
    FOR ALL USING (company_id = public.get_company_id());

    CREATE POLICY "Allow all access to own company data" ON public.products
    FOR ALL USING (company_id = public.get_company_id());

    CREATE POLICY "Allow all access to own company data" ON public.product_variants
    FOR ALL USING (company_id = public.get_company_id());

    CREATE POLICY "Allow all access to own company data" ON public.inventory_ledger
    FOR ALL USING (company_id = public.get_company_id());

    CREATE POLICY "Allow all access to own company data" ON public.orders
    FOR ALL USING (company_id = public.get_company_id());
    
    CREATE POLICY "Allow all access to own company data" ON public.order_line_items
    FOR ALL USING (company_id = public.get_company_id());

    CREATE POLICY "Allow all access to own company data" ON public.customers
    FOR ALL USING (company_id = public.get_company_id());

    CREATE POLICY "Allow all access to own company data" ON public.suppliers
    FOR ALL USING (company_id = public.get_company_id());

    CREATE POLICY "Allow all access to own company data" ON public.purchase_orders
    FOR ALL USING (company_id = public.get_company_id());

    CREATE POLICY "Allow all access to own company data" ON public.integrations
    FOR ALL USING (company_id = public.get_company_id());

    CREATE POLICY "Allow all access to own company data" ON public.conversations
    FOR ALL USING (company_id = public.get_company_id());

    CREATE POLICY "Allow all access to own company data" ON public.messages
    FOR ALL USING (company_id = public.get_company_id());

    CREATE POLICY "Allow all access to own company data" ON public.audit_log
    FOR ALL USING (company_id = public.get_company_id());

    CREATE POLICY "Allow all access to own company data" ON public.channel_fees
    FOR ALL USING (company_id = public.get_company_id());
    
    CREATE POLICY "Allow all access to own company data" ON public.purchase_order_line_items
    FOR ALL USING (company_id = public.get_company_id());

END;
$$;

-- Execute the procedure to apply all policies
CALL apply_rls_policies();
