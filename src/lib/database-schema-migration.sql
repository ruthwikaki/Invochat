-- InvoChat Precise Database Migration Script
-- This script updates an existing database to the final schema version.
-- It is designed to be idempotent and safe to run on your current database.

-- Step 1: Add missing columns to tables IF THEY DON'T EXIST.
ALTER TABLE public.product_variants
    ADD COLUMN IF NOT EXISTS reorder_point integer,
    ADD COLUMN IF NOT EXISTS reorder_quantity integer;

ALTER TABLE public.audit_log
    ADD COLUMN IF NOT EXISTS company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL;

-- Step 2: Drop obsolete columns IF THEY EXIST.
ALTER TABLE public.product_variants
    DROP COLUMN IF EXISTS weight,
    DROP COLUMN IF EXISTS weight_unit;

-- Step 3: Alter column constraints to enforce data integrity.
-- Note: Making a column NOT NULL will fail if there is existing NULL data.
-- This assumes that for new setups or during migration, these will be populated.
-- For production migrations, a data backfill step would be needed first.
ALTER TABLE public.product_variants ALTER COLUMN sku SET NOT NULL;

-- The 'title' column on variants can be nullable, as it often is for products with no distinct options.
-- So we will not make it NOT NULL.

-- Step 4: Drop the old, insecure helper function IF IT EXISTS.
DROP FUNCTION IF EXISTS public.get_my_company_id();

-- Step 5: Add a new, secure helper function to get the company ID for the currently authenticated user.
CREATE OR REPLACE FUNCTION public.get_user_company_id()
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    company_id_val uuid;
BEGIN
    SELECT id
    INTO company_id_val
    FROM public.users
    WHERE users.id = auth.uid();

    RETURN company_id_val;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        -- This case can happen, for example, during user signup before the user record is in public.users
        RETURN NULL;
END;
$$;

-- Step 6: Create performance indexes IF THEY DON'T EXIST.
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_company_sku ON public.product_variants(company_id, sku);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_customers_company_email ON public.customers(company_id, email);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id ON public.inventory_ledger(variant_id);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_company_id ON public.purchase_orders(company_id);
CREATE INDEX IF NOT EXISTS idx_purchase_order_line_items_po_id ON public.purchase_order_line_items(purchase_order_id);

-- Step 7: Enable Row-Level Security (RLS) on all relevant tables.
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- Step 8: Drop existing policies before creating new ones to avoid conflicts.
DROP POLICY IF EXISTS "Users can only access their own company data" ON public.products;
DROP POLICY IF EXISTS "Users can only access their own company data" ON public.product_variants;
DROP POLICY IF EXISTS "Users can only access their own company data" ON public.orders;
DROP POLICY IF EXISTS "Users can only access their own company data" ON public.order_line_items;
DROP POLICY IF EXISTS "Users can only access their own company data" ON public.customers;
DROP POLICY IF EXISTS "Users can only access their own company data" ON public.suppliers;
DROP POLICY IF EXISTS "Users can only access their own company data" ON public.purchase_orders;
DROP POLICY IF EXISTS "Users can only access their own company data" ON public.purchase_order_line_items;
DROP POLICY IF EXISTS "Users can only access their own company data" ON public.inventory_ledger;
DROP POLICY IF EXISTS "Users can only access their own company data" ON public.company_settings;
DROP POLICY IF EXISTS "Users can only access their own company data" ON public.integrations;
DROP POLICY IF EXISTS "Users can only access their own company data" ON public.conversations;
DROP POLICY IF EXISTS "Users can only access their own company data" ON public.messages;
DROP POLICY IF EXISTS "Users can only access their own company data" ON public.audit_log;
DROP POLICY IF EXISTS "Users can only access their own data" ON public.users;


-- Step 9: Create new, secure RLS policies for multi-tenancy.
CREATE POLICY "Users can only access their own company data" ON public.products FOR ALL
    USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()))
    WITH CHECK (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

CREATE POLICY "Users can only access their own company data" ON public.product_variants FOR ALL
    USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()))
    WITH CHECK (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

CREATE POLICY "Users can only access their own company data" ON public.orders FOR ALL
    USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()))
    WITH CHECK (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

CREATE POLICY "Users can only access their own company data" ON public.order_line_items FOR ALL
    USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()))
    WITH CHECK (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

CREATE POLICY "Users can only access their own company data" ON public.customers FOR ALL
    USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()))
    WITH CHECK (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

CREATE POLICY "Users can only access their own company data" ON public.suppliers FOR ALL
    USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()))
    WITH CHECK (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

CREATE POLICY "Users can only access their own company data" ON public.purchase_orders FOR ALL
    USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()))
    WITH CHECK (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

CREATE POLICY "Users can only access their own company data" ON public.purchase_order_line_items FOR ALL
    USING (purchase_order_id IN (SELECT id FROM purchase_orders WHERE company_id = (SELECT company_id FROM public.users WHERE id = auth.uid())));

CREATE POLICY "Users can only access their own company data" ON public.inventory_ledger FOR ALL
    USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()))
    WITH CHECK (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

CREATE POLICY "Users can only access their own company data" ON public.company_settings FOR ALL
    USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()))
    WITH CHECK (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

CREATE POLICY "Users can only access their own company data" ON public.integrations FOR ALL
    USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()))
    WITH CHECK (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

CREATE POLICY "Users can only access their own company data" ON public.conversations FOR ALL
    USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()))
    WITH CHECK (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

CREATE POLICY "Users can only access their own company data" ON public.messages FOR ALL
    USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()))
    WITH CHECK (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

CREATE POLICY "Users can only access their own company data" ON public.audit_log FOR ALL
    USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()))
    WITH CHECK (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

CREATE POLICY "Users can only access their own data" ON public.users FOR ALL
    USING (id = auth.uid())
    WITH CHECK (id = auth.uid());

-- Final step: Recreate the product_variants_with_details view to reflect any changes.
DROP VIEW IF EXISTS public.product_variants_with_details;
CREATE OR REPLACE VIEW public.product_variants_with_details AS
 SELECT pv.id,
    pv.product_id,
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
    pv.updated_at,
    p.title AS product_title,
    p.status AS product_status,
    p.image_url
   FROM (public.product_variants pv
     LEFT JOIN public.products p ON ((pv.product_id = p.id)));

-- Grant usage on the new view
GRANT SELECT ON public.product_variants_with_details TO authenticated, service_role;

