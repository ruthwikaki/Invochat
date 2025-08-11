-- Migration: Core Views and Functions
-- Description: This script creates essential views and functions for inventory and sales analytics.

BEGIN;

-- 1. Add supplier_id to product_variants if it doesn't exist
ALTER TABLE public.product_variants
ADD COLUMN IF NOT EXISTS supplier_id uuid NULL;

-- 2. Add foreign key constraint for supplier_id
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'product_variants_supplier_id_fkey'
  ) THEN
    ALTER TABLE public.product_variants
      ADD CONSTRAINT product_variants_supplier_id_fkey
      FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id)
      ON DELETE SET NULL;
  END IF;
END$$;

-- 3. Create the inventory view
CREATE OR REPLACE VIEW public.inventory AS
SELECT
  pv.id AS variant_id,
  pv.product_id,
  pv.company_id,
  pv.sku,
  COALESCE(pv.title, p.title) AS variant_title,
  p.title AS product_title,
  p.product_type,
  p.tags,
  pv.price,
  pv.cost,
  pv.inventory_quantity,
  pv.reorder_point,
  pv.reorder_quantity,
  pv.supplier_id,
  p.image_url,
  pv.created_at,
  pv.updated_at
FROM public.product_variants pv
JOIN public.products p ON p.id = pv.product_id;

-- 4. Create the product_variants_with_details view
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
  pv.*,
  p.title AS product_title,
  p.status AS product_status,
  p.product_type,
  p.tags,
  p.image_url,
  s.name AS supplier_name,
  COALESCE(s.default_lead_time_days) AS supplier_lead_time_days
FROM public.product_variants pv
JOIN public.products p ON p.id = pv.product_id
LEFT JOIN public.suppliers s ON s.id = pv.supplier_id;

-- 5. Create the sales view
CREATE OR REPLACE VIEW public.sales AS
SELECT
  o.id AS order_id,
  o.company_id,
  o.order_number,
  o.created_at AS order_date,
  o.source_platform AS channel,
  o.customer_id,
  o.total_amount,
  o.financial_status AS status,
  'unknown'::text AS payment_method, -- Placeholder
  oi.id as line_item_id,
  oi.product_id,
  oi.variant_id,
  oi.quantity,
  oi.price,
  oi.tax_amount,
  oi.total_discount,
  ((oi.price * oi.quantity) - COALESCE(oi.total_discount,0) + COALESCE(oi.tax_amount,0)) AS line_total
FROM public.orders o
JOIN public.order_line_items oi ON oi.order_id = o.id;

-- 6. Drop old functions if they exist
DROP FUNCTION IF EXISTS public.get_inventory_analytics(uuid);
DROP FUNCTION IF EXISTS public.get_sales_analytics(uuid);

-- 7. Create lightweight analytics functions
CREATE OR REPLACE FUNCTION public.get_inventory_analytics(p_company_id uuid)
RETURNS jsonb
LANGUAGE sql STABLE
AS $$
  SELECT jsonb_build_object(
    'total_products', (SELECT count(*) FROM public.products p WHERE p.company_id = p_company_id),
    'total_variants', (SELECT count(*) FROM public.product_variants pv WHERE pv.company_id = p_company_id),
    'total_inventory_value', (SELECT COALESCE(sum(pv.cost * pv.inventory_quantity), 0) FROM public.product_variants pv WHERE pv.company_id = p_company_id),
    'low_stock_items', (SELECT count(*) FROM public.product_variants pv WHERE pv.company_id = p_company_id AND pv.inventory_quantity > 0 AND pv.inventory_quantity <= pv.reorder_point)
  )
$$;

CREATE OR REPLACE FUNCTION public.get_sales_analytics(p_company_id uuid)
RETURNS jsonb
LANGUAGE sql STABLE
AS $$
  SELECT jsonb_build_object(
    'total_revenue', (SELECT COALESCE(sum(s.total_amount),0) FROM public.sales s WHERE s.company_id = p_company_id),
    'total_orders', (SELECT count(DISTINCT s.order_id) FROM public.sales s WHERE s.company_id = p_company_id),
    'average_order_value', (SELECT COALESCE(avg(s.total_amount),0) FROM public.sales s WHERE s.company_id = p_company_id)
  )
$$;


COMMIT;
