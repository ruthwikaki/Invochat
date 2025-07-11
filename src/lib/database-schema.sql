-- ===== InvoChat Simplification Migration Script =====
-- This script removes all remnants of the Purchase Order and Multi-Location
-- systems from your database. It is designed to be run on your existing
-- database and is safe to re-run if it fails.

-- Step 1: Drop dependent views and triggers first.
DROP MATERIALIZED VIEW IF EXISTS public.company_dashboard_metrics;
DROP TRIGGER IF EXISTS validate_inventory_location_ref ON public.inventory;

-- Step 2: Drop all functions that have dependencies or are being removed.
-- Order is critical to avoid dependency errors.

DROP FUNCTION IF EXISTS public.get_purchase_order_analytics();
DROP FUNCTION IF EXISTS public.get_purchase_orders(uuid, text, int, int);
DROP FUNCTION IF EXISTS public.receive_purchase_order_items(uuid, jsonb, uuid, uuid);
DROP FUNCTION IF EXISTS public.validate_same_company_reference();
DROP FUNCTION IF EXISTS public.get_business_profile(uuid);
DROP FUNCTION IF EXISTS public.get_supplier_performance(uuid);
DROP FUNCTION IF EXISTS public.get_unified_inventory(uuid, text, text, uuid, uuid, text, int, int);
DROP FUNCTION IF EXISTS public.get_reorder_suggestions(uuid, text); -- Dropping old version with timezone
DROP FUNCTION IF EXISTS public.get_reorder_suggestions(uuid, integer); -- Dropping old version with fast_moving_days

-- Step 3: Remove the 'location_id' column from the inventory table as it is no longer used.
ALTER TABLE public.inventory DROP COLUMN IF EXISTS location_id;

-- Step 4: Recreate the necessary functions with simplified logic.

-- get_reorder_suggestions: Simplified to no longer reference POs or complex logic.
CREATE OR REPLACE FUNCTION public.get_reorder_suggestions(p_company_id uuid)
RETURNS TABLE(
    product_id uuid,
    sku text,
    product_name text,
    current_quantity integer,
    reorder_point integer,
    suggested_reorder_quantity integer,
    supplier_id uuid,
    supplier_name text,
    unit_cost numeric
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        i.id AS product_id,
        i.sku,
        i.name AS product_name,
        i.quantity AS current_quantity,
        i.reorder_point,
        GREATEST(0, COALESCE(i.reorder_point, 0) - i.quantity) AS suggested_reorder_quantity,
        s.id AS supplier_id,
        s.name AS supplier_name,
        i.cost AS unit_cost
    FROM
        public.inventory i
    LEFT JOIN
        public.suppliers s ON i.supplier_id = s.id
    WHERE
        i.company_id = p_company_id
        AND i.deleted_at IS NULL
        AND i.reorder_point IS NOT NULL
        AND i.quantity < i.reorder_point;
END;
$$;

-- get_unified_inventory: Simplified to remove the unused 'location_id' parameter.
CREATE OR REPLACE FUNCTION public.get_unified_inventory(
    p_company_id uuid,
    p_query text DEFAULT NULL,
    p_category text DEFAULT NULL,
    p_supplier_id uuid DEFAULT NULL,
    p_sku_filter text DEFAULT NULL,
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
            s.id as supplier_id,
            i.barcode
        FROM
            public.inventory i
        LEFT JOIN
            public.suppliers s ON i.supplier_id = s.id
        WHERE
            i.company_id = p_company_id
            AND i.deleted_at IS NULL
            AND (p_query IS NULL OR i.name ILIKE '%' || p_query || '%' OR i.sku ILIKE '%' || p_query || '%')
            AND (p_category IS NULL OR i.category = p_category)
            AND (p_supplier_id IS NULL OR i.supplier_id = p_supplier_id)
            AND (p_sku_filter IS NULL OR i.sku = p_sku_filter)
    )
    SELECT
        (SELECT json_agg(fi.*) FROM (SELECT * FROM filtered_inventory ORDER BY product_name LIMIT p_limit OFFSET p_offset) AS fi) AS items,
        (SELECT COUNT(*) FROM filtered_inventory) AS total_count;
END;
$$;


-- Step 5: Recreate the materialized view without dependencies on removed tables.
CREATE MATERIALIZED VIEW public.company_dashboard_metrics AS
SELECT
    i.company_id,
    SUM(i.quantity * i.cost) AS inventory_value,
    COUNT(DISTINCT i.sku) AS total_skus,
    COUNT(*) FILTER (WHERE i.quantity < i.reorder_point) AS low_stock_count
FROM
    public.inventory i
WHERE i.deleted_at IS NULL
GROUP BY
    i.company_id;

-- Step 6: Recreate the function to refresh the new, simplified view.
CREATE OR REPLACE FUNCTION public.refresh_materialized_views(
    p_company_id uuid
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.company_dashboard_metrics;
    -- Note: customer_analytics_metrics is independent and can remain.
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.customer_analytics_metrics;
END;
$$;


-- Final step: Grant usage on the public schema to the authenticated role.
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO authenticated;

-- Grant execution rights for the recreated functions to the authenticated role.
GRANT EXECUTE ON FUNCTION public.get_reorder_suggestions(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_unified_inventory(uuid, text, text, uuid, text, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_materialized_views(uuid) TO authenticated;

-- End of script
SELECT 'Migration script completed successfully.' as status;
