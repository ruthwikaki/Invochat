-- =====================================================
-- FIX FUNCTIONS THAT REFERENCE OLD ORDERS TABLES
-- =====================================================

-- 1. Fix process_sales_order_inventory
DROP FUNCTION IF EXISTS public.process_sales_order_inventory(uuid, uuid);
CREATE OR REPLACE FUNCTION public.process_sales_order_inventory(p_company_id uuid, p_sale_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    -- Update inventory quantities based on sale items
    UPDATE inventory i
    SET quantity = i.quantity - si.quantity,
        last_sold_date = CURRENT_DATE,
        updated_at = NOW()
    FROM sale_items si
    JOIN sales s ON si.sale_id = s.id
    WHERE s.id = p_sale_id
    AND s.company_id = p_company_id
    AND i.sku = si.sku
    AND i.company_id = p_company_id;

    -- Create inventory ledger entries
    INSERT INTO inventory_ledger (company_id, sku, created_at, change_type, quantity_change, new_quantity, related_id, notes)
    SELECT 
        p_company_id,
        si.sku,
        NOW(),
        'sale',
        -si.quantity,
        i.quantity,
        p_sale_id,
        'Sale fulfillment'
    FROM sale_items si
    JOIN sales s ON si.sale_id = s.id
    JOIN inventory i ON si.sku = i.sku AND i.company_id = p_company_id
    WHERE s.id = p_sale_id
    AND s.company_id = p_company_id;
END;
$$;

-- 2. Fix validate_same_company_reference trigger function
CREATE OR REPLACE FUNCTION public.validate_same_company_reference()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    ref_company_id uuid;
    current_company_id uuid;
BEGIN
    -- Check vendor reference for purchase_orders
    IF TG_TABLE_NAME = 'purchase_orders' AND NEW.supplier_id IS NOT NULL THEN
        SELECT company_id INTO ref_company_id FROM vendors WHERE id = NEW.supplier_id;
        IF ref_company_id != NEW.company_id THEN
            RAISE EXCEPTION 'Security violation: Cannot reference a vendor from a different company.';
        END IF;
    END IF;

    -- Check inventory location reference
    IF TG_TABLE_NAME = 'inventory' AND NEW.location_id IS NOT NULL THEN
        SELECT company_id INTO ref_company_id FROM locations WHERE id = NEW.location_id;
        IF ref_company_id != NEW.company_id THEN
            RAISE EXCEPTION 'Security violation: Cannot assign to a location from a different company.';
        END IF;
    END IF;

    -- Check sale items reference inventory (updated from order_items)
    IF TG_TABLE_NAME = 'sale_items' THEN
        SELECT company_id INTO ref_company_id FROM sales WHERE id = NEW.sale_id;
        IF NOT EXISTS (SELECT 1 FROM inventory WHERE sku = NEW.sku and company_id = ref_company_id) THEN
            RAISE EXCEPTION 'Security violation: SKU does not exist for this company.';
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$;

-- 3. Fix get_unified_inventory function
CREATE OR REPLACE FUNCTION public.get_unified_inventory(
    p_company_id uuid,
    p_query text DEFAULT NULL,
    p_category text DEFAULT NULL,
    p_location_id uuid DEFAULT NULL,
    p_supplier_id uuid DEFAULT NULL,
    p_sku_filter text DEFAULT NULL,
    p_limit integer DEFAULT 50,
    p_offset integer DEFAULT 0
)
RETURNS TABLE(items json, total_count bigint)
LANGUAGE plpgsql
AS $$
DECLARE
    result_items json;
    total_count bigint;
BEGIN
    -- Get filtered items
    WITH filtered_inventory AS (
        SELECT 
            i.sku,
            i.name as product_name,
            i.category,
            i.quantity,
            i.cost,
            i.price,
            (i.quantity * i.cost) as total_value,
            i.reorder_point,
            i.on_order_quantity,
            i.landed_cost,
            i.barcode,
            i.location_id,
            l.name as location_name,
            COALESCE(
                (SELECT SUM(si.quantity) 
                 FROM sales s 
                 JOIN sale_items si ON s.id = si.sale_id 
                 WHERE si.sku = i.sku 
                   AND s.company_id = i.company_id 
                   AND s.created_at >= CURRENT_DATE - interval '30 days'
                ), 0
            ) as monthly_units_sold,
            COALESCE(
                (SELECT SUM(si.quantity * (si.unit_price - i.cost))
                 FROM sales s 
                 JOIN sale_items si ON s.id = si.sale_id 
                 WHERE si.sku = i.sku 
                   AND s.company_id = i.company_id 
                   AND s.created_at >= CURRENT_DATE - interval '30 days'
                ), 0
            ) as monthly_profit,
            i.version
        FROM inventory i
        LEFT JOIN locations l ON i.location_id = l.id
        WHERE i.company_id = p_company_id
            AND i.deleted_at IS NULL
            AND (p_query IS NULL OR (
                i.sku ILIKE '%' || p_query || '%' OR
                i.name ILIKE '%' || p_query || '%' OR
                i.barcode ILIKE '%' || p_query || '%'
            ))
            AND (p_category IS NULL OR i.category = p_category)
            AND (p_location_id IS NULL OR i.location_id = p_location_id)
            AND (p_supplier_id IS NULL OR EXISTS (
                SELECT 1 FROM supplier_catalogs sc 
                WHERE sc.sku = i.sku AND sc.supplier_id = p_supplier_id
            ))
            AND (p_sku_filter IS NULL OR i.sku = p_sku_filter)
    )
    SELECT 
        json_agg(fi.*) as items,
        COUNT(*) OVER() as total_count
    INTO result_items, total_count
    FROM (
        SELECT * FROM filtered_inventory
        ORDER BY sku
        LIMIT p_limit
        OFFSET p_offset
    ) fi;

    RETURN QUERY SELECT COALESCE(result_items, '[]'::json), COALESCE(total_count, 0);
END;
$$;

-- 4. Fix get_customers_with_stats function
CREATE OR REPLACE FUNCTION public.get_customers_with_stats(
    p_company_id uuid,
    p_query text DEFAULT NULL,
    p_limit integer DEFAULT 50,
    p_offset integer DEFAULT 0
)
RETURNS json
LANGUAGE plpgsql
AS $$
DECLARE
    result_json json;
BEGIN
    WITH customer_stats AS (
        SELECT
            c.id,
            c.company_id,
            c.platform,
            c.external_id,
            c.customer_name,
            c.email,
            c.status,
            c.deleted_at,
            c.created_at,
            COUNT(s.id) as total_orders,
            COALESCE(SUM(s.total_amount), 0) as total_spend
        FROM public.customers c
        LEFT JOIN public.sales s ON c.email = s.customer_email AND c.company_id = s.company_id
        WHERE c.company_id = p_company_id
          AND c.deleted_at IS NULL
          AND (
            p_query IS NULL OR
            c.customer_name ILIKE '%' || p_query || '%' OR
            c.email ILIKE '%' || p_query || '%'
          )
        GROUP BY c.id
    ),
    count_query AS (
        SELECT count(*) as total FROM customer_stats
    )
    SELECT json_build_object(
        'items', (SELECT json_agg(cs) FROM (
            SELECT * FROM customer_stats ORDER BY total_spend DESC LIMIT p_limit OFFSET p_offset
        ) cs),
        'totalCount', (SELECT total FROM count_query)
    ) INTO result_json;
    
    RETURN result_json;
END;
$$;

-- 5. Grant permissions to all fixed functions
GRANT EXECUTE ON FUNCTION public.process_sales_order_inventory(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.validate_same_company_reference() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_unified_inventory(uuid, text, text, uuid, uuid, text, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_customers_with_stats(uuid, text, integer, integer) TO authenticated;

-- 6. If you have triggers using validate_same_company_reference, recreate them
-- First drop old triggers if they exist
DROP TRIGGER IF EXISTS validate_sale_items_company ON sale_items;

-- Create trigger for sale_items instead of order_items
CREATE TRIGGER validate_sale_items_company
    BEFORE INSERT OR UPDATE ON sale_items
    FOR EACH ROW
    EXECUTE FUNCTION validate_same_company_reference();

-- =====================================================
-- Script completed - all references to orders/order_items 
-- have been updated to sales/sale_items
-- =====================================================