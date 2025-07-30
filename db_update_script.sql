
-- This script updates your existing database schema with necessary performance and security improvements.
-- It is safe to run on your existing database.

-- 1. Add Performance Indexes
-- These indexes were identified in the performance audit to speed up common queries on large tables.
-- Using `IF NOT EXISTS` ensures this script is safe to run multiple times.
CREATE INDEX CONCURRENTLY IF NOT EXISTS orders_analytics_idx ON public.orders(company_id, created_at, financial_status);
CREATE INDEX CONCURRENTLY IF NOT EXISTS inventory_ledger_history_idx ON public.inventory_ledger(variant_id, created_at);

-- 2. Drop the old, problematic get_reorder_suggestions function
-- This function is being replaced with a more performant and accurate version.
DROP FUNCTION IF EXISTS public.get_reorder_suggestions(p_company_id uuid);

-- 3. Create the new, optimized get_reorder_suggestions function
-- This new version correctly calculates suggestions and resolves previous errors.
CREATE OR REPLACE FUNCTION public.get_reorder_suggestions(p_company_id uuid)
RETURNS TABLE(
    variant_id uuid,
    product_id uuid,
    sku text,
    product_name text,
    supplier_name text,
    supplier_id uuid,
    current_quantity integer,
    suggested_reorder_quantity integer,
    unit_cost integer
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    WITH sales_velocity AS (
        SELECT
            oli.variant_id,
            (SUM(oli.quantity)::decimal / 90) AS daily_sales_velocity
        FROM public.order_line_items oli
        JOIN public.orders o ON oli.order_id = o.id
        WHERE o.company_id = p_company_id
          AND o.created_at >= (NOW() - INTERVAL '90 days')
        GROUP BY oli.variant_id
    )
    SELECT
        pv.id AS variant_id,
        pv.product_id,
        pv.sku,
        p.title AS product_name,
        s.name AS supplier_name,
        pv.supplier_id,
        pv.inventory_quantity AS current_quantity,
        GREATEST(
            0,
            (COALESCE(sv.daily_sales_velocity, 0) * (COALESCE(s.default_lead_time_days, 14) + 14)) -- Lead Time + 14-day buffer
            - (pv.inventory_quantity + pv.in_transit_quantity)
        )::integer AS suggested_reorder_quantity,
        pv.cost AS unit_cost
    FROM public.product_variants pv
    JOIN public.products p ON pv.product_id = p.id
    LEFT JOIN public.suppliers s ON pv.supplier_id = s.id
    LEFT JOIN sales_velocity sv ON pv.id = sv.variant_id
    WHERE pv.company_id = p_company_id
      AND pv.reorder_point IS NOT NULL
      AND pv.inventory_quantity <= pv.reorder_point;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_reorder_suggestions(uuid) TO "authenticated";

-- 4. Update the check_user_permission function to resolve the function overload error.
-- This ensures the function correctly handles the role check without ambiguity.
CREATE OR REPLACE FUNCTION public.check_user_permission(p_user_id uuid, p_required_role text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    user_role company_role;
    role_hierarchy_map jsonb := '{
        "Member": 1,
        "Admin": 2,
        "Owner": 3
    }';
    user_level int;
    required_level int;
BEGIN
    SELECT "role" INTO user_role FROM company_users WHERE user_id = p_user_id;

    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    user_level := (role_hierarchy_map->>user_role::text)::int;
    required_level := (role_hierarchy_map->>p_required_role)::int;

    RETURN user_level >= required_level;
END;
$$;


GRANT EXECUTE ON FUNCTION public.check_user_permission(uuid, text) TO "authenticated";

-- End of script
