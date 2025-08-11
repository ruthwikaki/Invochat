
-- Add a foreign key for supplier_id to product_variants
ALTER TABLE public.product_variants
ADD COLUMN IF NOT EXISTS supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL;

-- Create a view for a unified inventory list
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

-- Create a more detailed view for product variants
DROP VIEW IF EXISTS public.product_variants_with_details;
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

-- Create a view for sales data for easier analytics
DROP VIEW IF EXISTS public.sales;
CREATE OR REPLACE VIEW public.sales AS
SELECT
  o.id as order_id,
  o.company_id,
  o.order_number,
  o.created_at,
  o.customer_id,
  o.total_amount,
  o.financial_status AS status,
  'unknown'::text as payment_method,
  oli.id as line_item_id,
  oli.variant_id,
  oli.quantity,
  oli.price
FROM public.orders o
JOIN public.order_line_items oli ON oli.order_id = o.id;

-- Drop old, potentially conflicting functions
DROP FUNCTION IF EXISTS public.get_inventory_analytics(uuid);
DROP FUNCTION IF EXISTS public.get_sales_analytics(uuid);

-- Create a simplified inventory analytics function
CREATE OR REPLACE FUNCTION public.get_inventory_analytics(p_company_id uuid)
RETURNS jsonb
LANGUAGE sql STABLE
AS $$
  SELECT jsonb_build_object(
    'total_products', (SELECT count(DISTINCT product_id) FROM public.product_variants WHERE company_id = p_company_id),
    'total_variants', (SELECT count(*) FROM public.product_variants WHERE company_id = p_company_id),
    'total_inventory_value', (SELECT coalesce(sum(cost * inventory_quantity), 0) FROM public.product_variants WHERE company_id = p_company_id),
    'low_stock_items', (SELECT count(*) FROM public.product_variants WHERE company_id = p_company_id AND inventory_quantity <= reorder_point AND reorder_point > 0)
  )
$$;

-- Create a simplified sales analytics function
CREATE OR REPLACE FUNCTION public.get_sales_analytics(p_company_id uuid)
RETURNS jsonb
LANGUAGE sql STABLE
AS $$
  WITH s AS (
    SELECT * FROM public.sales WHERE company_id = p_company_id
  )
  SELECT jsonb_build_object(
    'total_revenue', (SELECT coalesce(sum(total_amount), 0) FROM public.orders WHERE company_id = p_company_id AND status = 'paid'),
    'total_orders', (SELECT count(*) FROM public.orders WHERE company_id = p_company_id),
    'average_order_value', (SELECT coalesce(avg(total_amount), 0) FROM public.orders WHERE company_id = p_company_id AND status = 'paid')
  )
$$;
