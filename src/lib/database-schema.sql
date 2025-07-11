
-- Comprehensive Database Migration & Cleanup Script
-- This script is designed to be idempotent and safely migrates the database
-- to a simplified, intelligence-focused schema. It removes all remnants of
-- the Purchase Order and multi-location systems.

-- Step 1: Drop dependent views and functions in the correct order.
DROP MATERIALIZED VIEW IF EXISTS public.company_dashboard_metrics;
DROP FUNCTION IF EXISTS public.get_purchase_order_analytics(uuid);
DROP FUNCTION IF EXISTS public.receive_purchase_order_items(uuid, jsonb, uuid, uuid);
DROP FUNCTION IF EXISTS public.get_supplier_performance(uuid);
DROP FUNCTION IF EXISTS public.get_reorder_suggestions(uuid, text); -- Drop old version first
DROP FUNCTION IF EXISTS public.get_reorder_suggestions(uuid, integer); -- Drop other old version

-- Step 2: Drop the tables. `CASCADE` will handle dependent triggers and constraints.
DROP TABLE IF EXISTS public.purchase_order_items CASCADE;
DROP TABLE IF EXISTS public.purchase_orders CASCADE;
DROP TABLE IF EXISTS public.locations CASCADE;

-- Step 3: Remove the 'location_id' column from the inventory table.
ALTER TABLE public.inventory DROP COLUMN IF EXISTS location_id;

-- Step 4: Recreate the dashboard metrics view without PO data.
CREATE MATERIALIZED VIEW public.company_dashboard_metrics AS
SELECT
  i.company_id,
  SUM(i.quantity * i.cost) AS inventory_value,
  COUNT(DISTINCT i.sku) FILTER (WHERE i.quantity > 0) AS total_skus,
  COUNT(DISTINCT i.sku) FILTER (WHERE i.quantity < i.reorder_point AND i.reorder_point IS NOT NULL) AS low_stock_count
FROM public.inventory i
WHERE i.deleted_at IS NULL
GROUP BY i.company_id;

-- Create an index for faster lookups on the new view
CREATE UNIQUE INDEX IF NOT EXISTS company_dashboard_metrics_pkey ON public.company_dashboard_metrics(company_id);

-- Step 5: Update the refresh function to only handle the new view.
DROP FUNCTION IF EXISTS public.refresh_materialized_views(uuid, text[]);
CREATE OR REPLACE FUNCTION public.refresh_materialized_views(p_company_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY public.company_dashboard_metrics;
  REFRESH MATERIALIZED VIEW CONCURRENTLY public.customer_analytics_metrics;
END;
$$;


-- Step 6: Clean up other functions that referenced deleted tables or columns.

-- Redefine `get_unified_inventory` to remove `location_id`.
DROP FUNCTION IF EXISTS public.get_unified_inventory(uuid, text, text, uuid, uuid, text, integer, integer);
CREATE OR REPLACE FUNCTION public.get_unified_inventory(
    p_company_id uuid,
    p_query text DEFAULT NULL,
    p_category text DEFAULT NULL,
    p_supplier_id uuid DEFAULT NULL,
    p_product_id_filter uuid DEFAULT NULL,
    p_limit integer DEFAULT 50,
    p_offset integer DEFAULT 0
)
RETURNS TABLE(items json, total_count bigint)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  WITH filtered_inventory AS (
    SELECT
      i.id as product_id,
      i.sku,
      i.name as product_name,
      i.category,
      i.quantity,
      i.cost,
      i.price,
      (i.quantity * i.cost) as total_value,
      i.reorder_point,
      s.name as supplier_name,
      i.supplier_id,
      i.barcode
    FROM inventory i
    LEFT JOIN suppliers s ON i.supplier_id = s.id AND i.company_id = s.company_id
    WHERE i.company_id = p_company_id
      AND i.deleted_at IS NULL
      AND (p_product_id_filter IS NULL OR i.id = p_product_id_filter)
      AND (p_query IS NULL OR (i.name ILIKE '%' || p_query || '%' OR i.sku ILIKE '%' || p_query || '%'))
      AND (p_category IS NULL OR i.category = p_category)
      AND (p_supplier_id IS NULL OR i.supplier_id = p_supplier_id)
  )
  SELECT
    (SELECT json_agg(fi.*) FROM (SELECT * FROM filtered_inventory ORDER BY product_name LIMIT p_limit OFFSET p_offset) AS fi) as items,
    (SELECT COUNT(*) FROM filtered_inventory) as total_count;
END;
$$;

-- Redefine `get_business_profile` to remove `outstanding_po_value`.
DROP FUNCTION IF EXISTS public.get_business_profile(uuid);
CREATE OR REPLACE FUNCTION public.get_business_profile(
    p_company_id uuid
)
RETURNS TABLE (
    monthly_revenue bigint,
    risk_tolerance text
)
LANGUAGE sql
AS $$
SELECT
    (SUM(total_amount) / 3)::bigint AS monthly_revenue,
    'medium'::text as risk_tolerance -- Placeholder
FROM sales
WHERE
    company_id = p_company_id
    AND created_at >= NOW() - INTERVAL '90 days';
$$;


-- Final Step: Ensure `gen_random_uuid` function exists if not already present.
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
