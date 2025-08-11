-- Comprehensive Schema Correction and View Creation Script
-- This script should be run once to align the database with the application code.

BEGIN;

-- ========= Step 1: Add Missing Columns =========

-- Add 'supplier_id' to product_variants table.
-- This is critical for reorder suggestions and supplier performance analysis.
ALTER TABLE public.product_variants ADD COLUMN IF NOT EXISTS supplier_id UUID;

-- Add a foreign key constraint to the new supplier_id column.
-- This is wrapped in a DO block to prevent errors if the constraint already exists.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'product_variants_supplier_id_fkey' AND conrelid = 'public.product_variants'::regclass
  ) THEN
    ALTER TABLE public.product_variants
      ADD CONSTRAINT product_variants_supplier_id_fkey
      FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id)
      ON DELETE SET NULL;
  END IF;
END$$;

-- Add 'payment_method' to orders table, as it was missing from the original schema
-- and is expected by some analytics views.
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS payment_method TEXT;


-- ========= Step 2: Create Missing Views =========

-- The application's data actions rely on these views for unified data access.
-- We drop them first to ensure a clean re-creation.

DROP VIEW IF EXISTS public.customers_view;
CREATE OR REPLACE VIEW public.customers_view AS
 SELECT c.id,
    c.company_id,
    c.customer_name,
    c.email,
    c.created_at,
    (SELECT count(*) FROM public.orders o WHERE o.customer_id = c.id) AS total_orders,
    (SELECT sum(o.total_amount) FROM public.orders o WHERE o.customer_id = c.id) AS total_spent,
    (SELECT min(o.created_at) FROM public.orders o WHERE o.customer_id = c.id) AS first_order_date
   FROM public.customers c
  WHERE c.deleted_at IS NULL;


DROP VIEW IF EXISTS public.orders_view;
CREATE OR REPLACE VIEW public.orders_view AS
 SELECT o.id,
    o.company_id,
    o.order_number,
    o.external_order_id,
    o.customer_id,
    c.email AS customer_email,
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
   FROM public.orders o
     LEFT JOIN public.customers c ON o.customer_id = c.id;


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
    pv.reorder_point,
    pv.reorder_quantity,
    pv.supplier_id,
    pv.external_variant_id,
    pv.created_at,
    pv.updated_at,
    p.title AS product_title,
    p.status AS product_status,
    p.image_url,
    p.product_type
   FROM public.product_variants pv
     JOIN public.products p ON pv.product_id = p.id
  WHERE pv.deleted_at IS NULL;


-- ========= Step 3: Update Database Functions =========

-- This section updates key RPC functions to use the correct columns and views.

-- get_inventory_analytics
DROP FUNCTION IF EXISTS public.get_inventory_analytics(p_company_id uuid);
CREATE OR REPLACE FUNCTION public.get_inventory_analytics(p_company_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $function$
  SELECT jsonb_build_object(
    'total_inventory_value', (SELECT COALESCE(SUM(v.cost * v.inventory_quantity), 0) FROM public.product_variants v WHERE v.company_id = p_company_id),
    'total_products', (SELECT COUNT(DISTINCT p.id) FROM public.products p WHERE p.company_id = p_company_id),
    'total_variants', (SELECT COUNT(*) FROM public.product_variants v WHERE v.company_id = p_company_id),
    'low_stock_items', (SELECT COUNT(*) FROM public.product_variants v WHERE v.company_id = p_company_id AND v.inventory_quantity <= v.reorder_point)
  )
$function$;

-- get_sales_analytics
DROP FUNCTION IF EXISTS public.get_sales_analytics(p_company_id uuid);
CREATE OR REPLACE FUNCTION public.get_sales_analytics(p_company_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $function$
  WITH sales_data AS (
    SELECT total_amount FROM public.orders WHERE company_id = p_company_id AND financial_status = 'paid'
  )
  SELECT jsonb_build_object(
    'total_revenue', (SELECT COALESCE(SUM(total_amount), 0) FROM sales_data),
    'total_orders', (SELECT COUNT(*) FROM sales_data),
    'average_order_value', (SELECT COALESCE(AVG(total_amount), 0) FROM sales_data)
  )
$function$;

-- get_customer_analytics
DROP FUNCTION IF EXISTS public.get_customer_analytics(p_company_id uuid);
CREATE OR REPLACE FUNCTION public.get_customer_analytics(p_company_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $function$
  SELECT jsonb_build_object(
    'total_customers', (SELECT COUNT(*) FROM public.customers WHERE company_id = p_company_id),
    'new_customers_last_30_days', (SELECT COUNT(*) FROM public.customers WHERE company_id = p_company_id AND created_at >= now() - interval '30 days'),
    'repeat_customer_rate', (SELECT COALESCE(SUM(CASE WHEN total_orders > 1 THEN 1 ELSE 0 END)::decimal / NULLIF(COUNT(*), 0), 0) FROM public.customers_view WHERE company_id = p_company_id),
    'average_lifetime_value', (SELECT COALESCE(AVG(total_spent), 0) FROM public.customers_view WHERE company_id = p_company_id),
    'top_customers_by_spend', (SELECT jsonb_agg(t) FROM (SELECT customer_name as name, total_spent as value FROM public.customers_view WHERE company_id = p_company_id ORDER BY total_spent DESC NULLS LAST LIMIT 5) t),
    'top_customers_by_sales', (SELECT jsonb_agg(t) FROM (SELECT customer_name as name, total_orders as value FROM public.customers_view WHERE company_id = p_company_id ORDER BY total_orders DESC NULLS LAST LIMIT 5) t)
  )
$function$;


COMMIT;
