-- Final Cleanup and Simplification Script
-- This script removes all remnants of Purchase Order and multi-location features from the database functions.
-- It is designed to run on the existing database to resolve all previous dependency errors.

BEGIN;

-- Drop dependent triggers before dropping their functions
DROP TRIGGER IF EXISTS validate_inventory_location_ref ON public.inventory;
DROP TRIGGER IF EXISTS handle_inventory_update ON public.inventory;

-- Drop functions that depend on other functions or have complex dependencies first
DROP FUNCTION IF EXISTS public.get_purchase_order_analytics();
DROP FUNCTION IF EXISTS public.validate_same_company_reference();
DROP FUNCTION IF EXISTS public.get_supplier_performance(uuid);
DROP FUNCTION IF EXISTS public.refresh_materialized_views(uuid);

-- Drop the materialized view that depends on now-deleted tables
DROP MATERIALIZED VIEW IF EXISTS public.company_dashboard_metrics;

-- Re-create a simplified dashboard metrics view without POs or locations
CREATE MATERIALIZED VIEW public.company_dashboard_metrics AS
SELECT
    i.company_id,
    SUM(i.quantity * i.cost) AS inventory_value,
    COUNT(DISTINCT i.sku) AS total_skus,
    SUM(CASE WHEN i.quantity < i.reorder_point THEN 1 ELSE 0 END) AS low_stock_count
FROM
    public.inventory i
WHERE i.deleted_at IS NULL
GROUP BY
    i.company_id;

-- Create an index on the new materialized view
CREATE UNIQUE INDEX IF NOT EXISTS company_dashboard_metrics_pkey ON public.company_dashboard_metrics(company_id);

-- Re-create the refresh function for the new, simplified view
CREATE OR REPLACE FUNCTION public.refresh_materialized_views(p_company_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.company_dashboard_metrics;
END;
$$;


-- Drop remaining obsolete functions
DROP FUNCTION IF EXISTS public.get_business_profile(uuid);
DROP FUNCTION IF EXISTS public.get_customers_with_stats(uuid, text, integer, integer);
DROP FUNCTION IF EXISTS public.get_dead_stock_alerts_data(uuid, integer);
DROP FUNCTION IF EXISTS public.process_sales_order_inventory(uuid, uuid);
DROP FUNCTION IF EXISTS public.process_sales_order_inventory(uuid, uuid, jsonb);
DROP FUNCTION IF EXISTS public.receive_purchase_order_items(uuid, jsonb, uuid, uuid);
DROP FUNCTION IF EXISTS public.update_inventory_item_with_lock(uuid, text, integer, text, text, numeric, integer, numeric, text, uuid);
DROP FUNCTION IF EXISTS public.update_inventory_item_with_lock(uuid, text, integer, text, text, bigint, integer, bigint, text, uuid);
DROP FUNCTION IF EXISTS public.batch_upsert_with_transaction(text, jsonb, text[]);
DROP FUNCTION IF EXISTS public.check_inventory_references(uuid, text[]);
DROP FUNCTION IF EXISTS public.delete_supplier_and_catalogs(uuid, uuid);


-- Modify remaining functions to remove dependencies on deleted columns/logic

-- Modify get_unified_inventory to remove location logic and on_order_quantity
CREATE OR REPLACE FUNCTION public.get_unified_inventory(
    p_company_id uuid,
    p_query text DEFAULT NULL::text,
    p_category text DEFAULT NULL::text,
    p_supplier_id uuid DEFAULT NULL::uuid,
    p_product_id_filter uuid DEFAULT NULL::uuid,
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
            i.id,
            i.sku,
            i.name,
            i.category,
            i.quantity,
            i.cost,
            i.price,
            (i.quantity * i.cost) as total_value,
            i.reorder_point,
            s.name AS supplier_name,
            s.id AS supplier_id,
            i.barcode
        FROM
            public.inventory i
        LEFT JOIN
            public.suppliers s ON i.supplier_id = s.id AND i.company_id = s.company_id
        WHERE
            i.company_id = p_company_id
            AND i.deleted_at IS NULL
            AND (p_query IS NULL OR (i.name ILIKE '%' || p_query || '%' OR i.sku ILIKE '%' || p_query || '%'))
            AND (p_category IS NULL OR i.category = p_category)
            AND (p_supplier_id IS NULL OR i.supplier_id = p_supplier_id)
            AND (p_product_id_filter IS NULL OR i.id = p_product_id_filter)
    ),
    counted_cte AS (
        SELECT COUNT(*) as total FROM filtered_inventory
    )
    SELECT
        (SELECT json_agg(fi) FROM (SELECT * FROM filtered_inventory ORDER BY name LIMIT p_limit OFFSET p_offset) fi) as items,
        (SELECT total FROM counted_cte) as total_count;
END;
$$;


-- Modify get_reorder_suggestions to remove dependency on timezone and simplify
CREATE OR REPLACE FUNCTION public.get_reorder_suggestions(
    p_company_id uuid
)
RETURNS TABLE(product_id uuid, sku text, product_name text, current_quantity integer, reorder_point integer, suggested_reorder_quantity integer, supplier_id uuid, supplier_name text, unit_cost numeric)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT
      i.id as product_id,
      i.sku,
      i.name as product_name,
      i.quantity as current_quantity,
      i.reorder_point,
      GREATEST(0, COALESCE(i.reorder_point, 0) - i.quantity) as suggested_reorder_quantity,
      i.supplier_id,
      s.name as supplier_name,
      i.cost as unit_cost
  FROM
      public.inventory i
      LEFT JOIN public.suppliers s ON i.supplier_id = s.id
  WHERE
      i.company_id = p_company_id
      AND i.deleted_at IS NULL
      AND i.quantity < i.reorder_point
  ORDER BY
      (COALESCE(i.reorder_point, 0) - i.quantity) DESC;
END;
$$;


-- Modify get_inventory_ledger_for_sku to use product_id instead of sku
CREATE OR REPLACE FUNCTION public.get_inventory_ledger_for_sku(
    p_company_id uuid,
    p_product_id uuid
)
RETURNS TABLE(id uuid, company_id uuid, product_id uuid, created_at text, change_type text, quantity_change integer, new_quantity integer, related_id uuid, notes text)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        il.id,
        il.company_id,
        il.product_id,
        il.created_at::text,
        il.change_type,
        il.quantity_change,
        il.new_quantity,
        il.related_id,
        il.notes
    FROM
        public.inventory_ledger il
    WHERE
        il.company_id = p_company_id AND il.product_id = p_product_id
    ORDER BY
        il.created_at DESC;
END;
$$;

-- Re-create the versioning trigger
CREATE TRIGGER handle_inventory_update
BEFORE UPDATE ON public.inventory
FOR EACH ROW
EXECUTE FUNCTION public.increment_version();

COMMIT;
