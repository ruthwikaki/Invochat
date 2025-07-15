-- This script is idempotent and can be run safely multiple times.
-- It is designed to be applied to a database that is in the final state from the previous migration.
-- It adds new functions and capabilities without altering existing tables.

-- Drop dependent views if they exist to allow function recreation.
DROP VIEW IF EXISTS public.product_variants_with_details;

-- Function: get_historical_sales_for_sku
-- Description: Retrieves the daily sales quantity for a single product SKU.
-- This is used by the demand forecasting AI flow.
CREATE OR REPLACE FUNCTION public.get_historical_sales_for_sku(
    p_company_id uuid,
    p_sku text
)
RETURNS TABLE(sale_date date, total_quantity bigint)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Ensure the user is a member of the company. This is a security best practice for all functions.
    IF NOT public.is_company_member(p_company_id, auth.uid()) THEN
        RAISE EXCEPTION 'User is not a member of the specified company.';
    END IF;

    RETURN QUERY
    SELECT
        DATE(o.created_at) as sale_date,
        SUM(oli.quantity) as total_quantity
    FROM
        public.orders o
    JOIN
        public.order_line_items oli ON o.id = oli.order_id
    WHERE
        o.company_id = p_company_id
        AND oli.sku = p_sku
    GROUP BY
        DATE(o.created_at)
    ORDER BY
        sale_date;
END;
$$;

-- Recreate the view that was dropped.
CREATE OR REPLACE VIEW public.product_variants_with_details
AS SELECT pv.id,
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
    pv.external_variant_id,
    pv.created_at,
    pv.updated_at,
    pv.location,
    p.title AS product_title,
    p.status AS product_status,
    p.image_url
   FROM public.product_variants pv
     LEFT JOIN public.products p ON pv.product_id = p.id
  WHERE pv.company_id = public.get_current_company_id();


-- Grant usage on new function to authenticated users
GRANT EXECUTE ON FUNCTION public.get_historical_sales_for_sku(uuid, text) TO authenticated;

-- Final check on RLS policies to ensure they are correct.
-- This is idempotent because the policies are dropped and recreated if they exist.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'Allow company members to read' AND polrelid = 'public.product_variants_with_details'::regclass) THEN
    DROP POLICY "Allow company members to read" ON public.product_variants_with_details;
  END IF;
END $$;
CREATE POLICY "Allow company members to read" ON public.product_variants_with_details FOR SELECT
TO authenticated
USING (company_id = public.get_current_company_id());

-- Grant select on the view to authenticated users
GRANT SELECT ON public.product_variants_with_details TO authenticated;

-- Ensure all tables still have the correct RLS policies.
-- This part is for ensuring idempotency and correctness.
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;

-- Recreate policies with the correct, safe definitions.
DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to manage" ON public.companies; EXCEPTION WHEN undefined_object THEN END; $$;
CREATE POLICY "Allow company members to manage" ON public.companies FOR ALL USING (id = public.get_current_company_id()) WITH CHECK (id = public.get_current_company_id());

DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to manage settings" ON public.company_settings; EXCEPTION WHEN undefined_object THEN END; $$;
CREATE POLICY "Allow company members to manage settings" ON public.company_settings FOR ALL USING (company_id = public.get_current_company_id()) WITH CHECK (company_id = public.get_current_company_id());

DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to manage products" ON public.products; EXCEPTION WHEN undefined_object THEN END; $$;
CREATE POLICY "Allow company members to manage products" ON public.products FOR ALL USING (company_id = public.get_current_company_id()) WITH CHECK (company_id = public.get_current_company_id());

DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to manage variants" ON public.product_variants; EXCEPTION WHEN undefined_object THEN END; $$;
CREATE POLICY "Allow company members to manage variants" ON public.product_variants FOR ALL USING (company_id = public.get_current_company_id()) WITH CHECK (company_id = public.get_current_company_id());

DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to manage suppliers" ON public.suppliers; EXCEPTION WHEN undefined_object THEN END; $$;
CREATE POLICY "Allow company members to manage suppliers" ON public.suppliers FOR ALL USING (company_id = public.get_current_company_id()) WITH CHECK (company_id = public.get_current_company_id());

DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to manage orders" ON public.orders; EXCEPTION WHEN undefined_object THEN END; $$;
CREATE POLICY "Allow company members to manage orders" ON public.orders FOR ALL USING (company_id = public.get_current_company_id()) WITH CHECK (company_id = public.get_current_company_id());

DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to manage line items" ON public.order_line_items; EXCEPTION WHEN undefined_object THEN END; $$;
CREATE POLICY "Allow company members to manage line items" ON public.order_line_items FOR ALL USING (company_id = public.get_current_company_id()) WITH CHECK (company_id = public.get_current_company_id());

DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to manage customers" ON public.customers; EXCEPTION WHEN undefined_object THEN END; $$;
CREATE POLICY "Allow company members to manage customers" ON public.customers FOR ALL USING (company_id = public.get_current_company_id()) WITH CHECK (company_id = public.get_current_company_id());

DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to manage ledger" ON public.inventory_ledger; EXCEPTION WHEN undefined_object THEN END; $$;
CREATE POLICY "Allow company members to manage ledger" ON public.inventory_ledger FOR ALL USING (company_id = public.get_current_company_id()) WITH CHECK (company_id = public.get_current_company_id());

DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to manage POs" ON public.purchase_orders; EXCEPTION WHEN undefined_object THEN END; $$;
CREATE POLICY "Allow company members to manage POs" ON public.purchase_orders FOR ALL USING (company_id = public.get_current_company_id()) WITH CHECK (company_id = public.get_current_company_id());

DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to manage PO line items" ON public.purchase_order_line_items; EXCEPTION WHEN undefined_object THEN END; $$;
CREATE POLICY "Allow company members to manage PO line items" ON public.purchase_order_line_items FOR ALL USING (purchase_order_id IN (SELECT id FROM public.purchase_orders WHERE company_id = public.get_current_company_id()));

DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to manage conversations" ON public.conversations; EXCEPTION WHEN undefined_object THEN END; $$;
CREATE POLICY "Allow company members to manage conversations" ON public.conversations FOR ALL USING (company_id = public.get_current_company_id() AND user_id = auth.uid());

DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to manage messages" ON public.messages; EXCEPTION WHEN undefined_object THEN END; $$;
CREATE POLICY "Allow company members to manage messages" ON public.messages FOR ALL USING (company_id = public.get_current_company_id());

DO $$ BEGIN DROP POLICY IF EXISTS "Allow company members to manage integrations" ON public.integrations; EXCEPTION WHEN undefined_object THEN END; $$;
CREATE POLICY "Allow company members to manage integrations" ON public.integrations FOR ALL USING (company_id = public.get_current_company_id()) WITH CHECK (company_id = public.get_current_company_id());
