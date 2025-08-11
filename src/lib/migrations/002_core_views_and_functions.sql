-- Add the missing supplier_id on product_variants
ALTER TABLE public.product_variants
ADD COLUMN IF NOT EXISTS supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL;

-- Recreate the inventory view
DROP VIEW IF EXISTS public.inventory;
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

-- Recreate the product_variants_with_details view
DROP VIEW IF EXISTS public.product_variants_with_details;
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
  pv.*,
  p.title AS product_title,
  p.product_type,
  p.status AS product_status,
  p.tags,
  p.image_url
FROM public.product_variants pv
JOIN public.products p ON p.id = pv.product_id;

-- Recreate the sales view
DROP VIEW IF EXISTS public.sales;
CREATE OR REPLACE VIEW public.sales AS
SELECT
  o.company_id,
  o.id AS order_id,
  o.order_number,
  o.created_at AS order_date,
  oli.product_id,
  oli.variant_id,
  oli.quantity,
  oli.price,
  oli.tax_amount,
  oli.total_discount,
  ((oli.price * oli.quantity) - COALESCE(oli.total_discount,0) + COALESCE(oli.tax_amount,0)) AS line_total,
  o.currency,
  o.source_platform,
  'unknown'::text AS payment_method,
  o.financial_status
FROM public.orders o
JOIN public.order_line_items oli ON oli.order_id = o.id;

-- Drop old functions
DROP FUNCTION IF EXISTS public.get_inventory_analytics(uuid);
DROP FUNCTION IF EXISTS public.get_sales_analytics(uuid);

-- Recreate inventory analytics function
CREATE OR REPLACE FUNCTION public.get_inventory_analytics(p_company_id uuid)
RETURNS jsonb
LANGUAGE sql STABLE
AS $$
  SELECT jsonb_build_object(
    'total_products', (SELECT count(*) FROM public.products p WHERE p.company_id = p_company_id),
    'total_variants', (SELECT count(*) FROM public.product_variants pv WHERE pv.company_id = p_company_id),
    'total_inventory_units', (SELECT coalesce(sum(pv.inventory_quantity),0) FROM public.product_variants pv WHERE pv.company_id = p_company_id),
    'total_inventory_value', (SELECT coalesce(sum(COALESCE(pv.cost,0) * pv.inventory_quantity),0) FROM public.product_variants pv WHERE pv.company_id = p_company_id),
    'low_stock_items', (SELECT count(*) FROM public.product_variants pv WHERE pv.company_id = p_company_id AND pv.inventory_quantity > 0 AND pv.inventory_quantity <= pv.reorder_point)
  )
$$;

-- Recreate sales analytics function
CREATE OR REPLACE FUNCTION public.get_sales_analytics(p_company_id uuid)
RETURNS jsonb
LANGUAGE sql STABLE
AS $$
  WITH s AS (
    SELECT * FROM public.sales WHERE company_id = p_company_id AND financial_status = 'paid'
  )
  SELECT jsonb_build_object(
    'total_orders', (SELECT count(distinct order_id) FROM s),
    'total_revenue', (SELECT coalesce(sum(line_total),0) FROM s),
    'average_order_value', (SELECT coalesce(sum(line_total),0) / count(distinct order_id) FROM s WHERE (SELECT count(distinct order_id) FROM s) > 0)
  )
$$;

-- Refresh materialized views to apply changes
-- Note: In a real migration, you might want to refresh concurrently if the views are large.
-- For this context, a direct refresh is fine.
REFRESH MATERIALIZED VIEW customers_view;
REFRESH MATERIALIZED VIEW orders_view;
REFRESH MATERIALIZED VIEW purchase_orders_view;
REFRESH MATERIALIZED VIEW audit_log_view;
REFRESH MATERIALIZED VIEW feedback_view;
