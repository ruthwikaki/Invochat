
-- Migration to add the alerting system to the database.
-- This function generates alerts for various business conditions like low stock and dead stock.

CREATE OR REPLACE FUNCTION get_alerts(p_company_id UUID)
RETURNS JSON[] AS $$
DECLARE
    alerts JSON[];
    r RECORD;
    settings record;
BEGIN
    -- Get company-specific settings
    SELECT * INTO settings FROM company_settings WHERE company_id = p_company_id;

    -- Low Stock Alerts
    FOR r IN (
        SELECT 
            v.id,
            v.sku,
            p.title as product_name,
            v.inventory_quantity,
            v.reorder_point
        FROM product_variants v
        JOIN products p ON v.product_id = p.id
        WHERE v.company_id = p_company_id
          AND v.inventory_quantity <= v.reorder_point
          AND v.reorder_point IS NOT NULL AND v.reorder_point > 0
    ) LOOP
        alerts := array_append(alerts, json_build_object(
            'id', 'low_stock_' || r.id,
            'type', 'low_stock',
            'title', 'Low Stock Warning',
            'message', r.product_name || ' is running low on stock.',
            'severity', 'warning',
            'timestamp', now(),
            'metadata', json_build_object(
                'productId', r.id,
                'productName', r.product_name,
                'sku', r.sku,
                'currentStock', r.inventory_quantity,
                'reorderPoint', r.reorder_point
            )
        ));
    END LOOP;

    -- Dead Stock Alerts
    FOR r IN (
        SELECT 
            v.id,
            v.sku,
            p.title as product_name,
            v.inventory_quantity,
            (v.inventory_quantity * v.cost) as value,
            max(oli.created_at) as last_sold_date
        FROM product_variants v
        JOIN products p ON v.product_id = p.id
        LEFT JOIN order_line_items oli ON v.id = oli.variant_id
        WHERE v.company_id = p_company_id
        GROUP BY v.id, p.title
        HAVING max(oli.created_at) < (now() - (settings.dead_stock_days || ' days')::interval)
           AND v.inventory_quantity > 0
    ) LOOP
        alerts := array_append(alerts, json_build_object(
            'id', 'dead_stock_' || r.id,
            'type', 'dead_stock',
            'title', 'Dead Stock Detected',
            'message', r.product_name || ' has not sold in over ' || settings.dead_stock_days || ' days.',
            'severity', 'critical',
            'timestamp', now(),
            'metadata', json_build_object(
                'productId', r.id,
                'productName', r.product_name,
                'sku', r.sku,
                'currentStock', r.inventory_quantity,
                'value', r.value,
                'lastSoldDate', r.last_sold_date
            )
        ));
    END LOOP;

    RETURN alerts;
END;
$$ LANGUAGE plpgsql;
