-- InvoChat: Database Migration Script
-- This script simplifies the database by removing the Purchase Order and Multi-Location systems.
-- It is designed to be idempotent and can be run on a database that has been partially updated.

BEGIN;

-- 1. DROP DEPENDENT TRIGGERS
-- ===================================
-- Drop triggers that depend on functions we are about to drop.
DROP TRIGGER IF EXISTS validate_inventory_location_ref ON public.inventory;
DROP TRIGGER IF EXISTS handle_inventory_update ON public.inventory;

-- 2. DROP DEPENDENT FUNCTIONS
-- ===================================
-- Drop functions that depend on tables or columns being removed.
DROP FUNCTION IF EXISTS public.validate_same_company_reference();
DROP FUNCTION IF EXISTS public.increment_version();
DROP FUNCTION IF EXISTS public.get_business_profile();
DROP FUNCTION IF EXISTS public.receive_purchase_order_items(uuid, jsonb, uuid, uuid);
DROP FUNCTION IF EXISTS public.get_purchase_order_analytics();
DROP FUNCTION IF EXISTS public.get_purchase_orders(uuid, text, int, int);
DROP FUNCTION IF EXISTS public.delete_location_and_unassign_inventory(uuid, uuid);
DROP FUNCTION IF EXISTS public.get_supplier_performance(uuid);

-- Must drop the old materialized view refresh function before dropping the view itself
DROP FUNCTION IF EXISTS public.refresh_materialized_views(uuid);
DROP MATERIALIZED VIEW IF EXISTS public.company_dashboard_metrics;

-- 3. DROP TABLES
-- ===================================
-- Drop tables related to the old PO and location systems.
DROP TABLE IF EXISTS public.purchase_order_items CASCADE;
DROP TABLE IF EXISTS public.purchase_orders CASCADE;
DROP TABLE IF EXISTS public.locations CASCADE;

-- 4. ALTER EXISTING TABLES
-- ===================================
-- Remove columns and constraints related to removed features.
ALTER TABLE public.inventory DROP COLUMN IF EXISTS location_id;
ALTER TABLE public.inventory DROP COLUMN IF EXISTS landed_cost;

ALTER TABLE public.suppliers DROP COLUMN IF EXISTS account_number;

-- 5. RECREATE/UPDATE FUNCTIONS & VIEWS
-- ===================================

-- Create a simplified dashboard metrics view without PO data
CREATE MATERIALIZED VIEW public.company_dashboard_metrics AS
SELECT
    c.id AS company_id,
    COALESCE(SUM(i.quantity * i.cost), 0) AS inventory_value,
    COALESCE(SUM(CASE WHEN i.quantity <= i.reorder_point THEN 1 ELSE 0 END), 0) AS low_stock_count,
    COUNT(i.id) AS total_skus
FROM
    public.companies c
LEFT JOIN
    public.inventory i ON c.id = i.company_id
WHERE i.deleted_at IS NULL
GROUP BY
    c.id;

-- Index the new view for performance
CREATE UNIQUE INDEX company_dashboard_metrics_pkey ON public.company_dashboard_metrics(company_id);

-- Recreate the refresh function for the new view
CREATE OR REPLACE FUNCTION public.refresh_materialized_views(p_company_id uuid, p_view_names text[] DEFAULT ARRAY['company_dashboard_metrics', 'customer_analytics_metrics'])
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF 'company_dashboard_metrics' = ANY(p_view_names) THEN
        REFRESH MATERIALIZED VIEW CONCURRENTLY public.company_dashboard_metrics;
    END IF;
    IF 'customer_analytics_metrics' = ANY(p_view_names) THEN
        REFRESH MATERIALIZED VIEW CONCURRENTLY public.customer_analytics_metrics;
    END IF;
END;
$$;


-- Update get_unified_inventory to remove location and PO logic
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
          s.id as supplier_id
      FROM
          inventory i
      LEFT JOIN
          suppliers s ON i.supplier_id = s.id AND i.company_id = s.company_id
      WHERE
          i.company_id = p_company_id
          AND i.deleted_at IS NULL
          AND (p_query IS NULL OR (i.name ILIKE '%' || p_query || '%' OR i.sku ILIKE '%' || p_query || '%'))
          AND (p_category IS NULL OR i.category = p_category)
          AND (p_supplier_id IS NULL OR i.supplier_id = p_supplier_id)
          AND (p_product_id_filter IS NULL OR i.id = p_product_id_filter)
  )
  SELECT
      (SELECT json_agg(fi.*) FROM (SELECT * FROM filtered_inventory ORDER BY product_name LIMIT p_limit OFFSET p_offset) fi) as items,
      (SELECT COUNT(*) FROM filtered_inventory) as total_count;
END;
$$;

-- Update record_sale_transaction to correctly use product_id
CREATE OR REPLACE FUNCTION public.record_sale_transaction(
    p_company_id uuid,
    p_user_id uuid,
    p_sale_items jsonb,
    p_customer_name text DEFAULT NULL,
    p_customer_email text DEFAULT NULL,
    p_payment_method text DEFAULT 'other',
    p_notes text DEFAULT NULL,
    p_external_id text DEFAULT NULL
)
RETURNS sales
LANGUAGE plpgsql
AS $$
DECLARE
    new_sale sales;
    sale_item jsonb;
    inv_record inventory;
    total_sale_amount numeric := 0;
BEGIN
    -- Calculate total amount
    FOR sale_item IN SELECT * FROM jsonb_array_elements(p_sale_items)
    LOOP
        total_sale_amount := total_sale_amount + (sale_item->>'quantity')::numeric * (sale_item->>'unit_price')::numeric;
    END LOOP;

    -- Create Sale record
    INSERT INTO sales (company_id, sale_number, customer_name, customer_email, total_amount, payment_method, notes, external_id)
    VALUES (p_company_id, 'SALE-' || nextval('sales_sale_number_seq'), p_customer_name, p_customer_email, total_sale_amount, p_payment_method, p_notes, p_external_id)
    RETURNING * INTO new_sale;

    -- Create Sale Items and update inventory
    FOR sale_item IN SELECT * FROM jsonb_array_elements(p_sale_items)
    LOOP
        -- Find the inventory record by SKU
        SELECT * INTO inv_record FROM inventory WHERE sku = sale_item->>'sku' AND company_id = p_company_id AND deleted_at IS NULL;

        IF inv_record IS NULL THEN
            RAISE EXCEPTION 'Product with SKU % not found in inventory for this company.', sale_item->>'sku';
        END IF;

        INSERT INTO sale_items (sale_id, company_id, sku, product_name, quantity, unit_price, cost_at_time)
        VALUES (new_sale.id, p_company_id, sale_item->>'sku', sale_item->>'product_name', (sale_item->>'quantity')::integer, (sale_item->>'unit_price')::numeric, inv_record.cost);

        -- Update inventory quantity and create ledger entry
        UPDATE inventory
        SET
            quantity = quantity - (sale_item->>'quantity')::integer,
            last_sold_date = CURRENT_DATE,
            updated_at = NOW()
        WHERE id = inv_record.id;

        INSERT INTO inventory_ledger (company_id, product_id, change_type, quantity_change, new_quantity, related_id, notes)
        SELECT p_company_id, inv_record.id, 'sale', -(sale_item->>'quantity')::integer, i.quantity, new_sale.id, 'Sale #' || new_sale.sale_number
        FROM inventory i
        WHERE i.id = inv_record.id;
    END LOOP;

    RETURN new_sale;
END;
$$;


-- Simplify get_reorder_suggestions
CREATE OR REPLACE FUNCTION public.get_reorder_suggestions(
    p_company_id uuid,
    p_fast_moving_days integer
)
RETURNS TABLE(
    product_id uuid,
    sku text,
    product_name text,
    current_quantity integer,
    reorder_point integer,
    suggested_reorder_quantity integer,
    supplier_name text,
    supplier_id uuid,
    unit_cost numeric
)
LANGUAGE sql
AS $$
WITH sales_velocity AS (
  SELECT
    si.sku,
    SUM(si.quantity)::numeric / p_fast_moving_days AS daily_velocity
  FROM sale_items si
  JOIN sales s ON si.sale_id = s.id
  WHERE s.company_id = p_company_id
    AND s.created_at >= NOW() - (p_fast_moving_days || ' days')::interval
  GROUP BY si.sku
)
SELECT
  i.id AS product_id,
  i.sku,
  i.name AS product_name,
  i.quantity AS current_quantity,
  i.reorder_point,
  GREATEST(
    0,
    COALESCE(i.reorder_point, 0) + COALESCE(sv.daily_velocity::integer * COALESCE(s.default_lead_time_days, 0), 0) - i.quantity
  ) AS suggested_reorder_quantity,
  s.name AS supplier_name,
  s.id AS supplier_id,
  i.cost AS unit_cost
FROM inventory i
LEFT JOIN suppliers s ON i.supplier_id = s.id
LEFT JOIN sales_velocity sv ON i.sku = sv.sku
WHERE i.company_id = p_company_id
  AND i.deleted_at IS NULL
  AND i.quantity < COALESCE(i.reorder_point, 0);
$$;

-- Clean up and re-add constraints to be safe
ALTER TABLE public.inventory_ledger DROP CONSTRAINT IF EXISTS inventory_ledger_product_id_fkey;
ALTER TABLE public.inventory_ledger
ADD CONSTRAINT inventory_ledger_product_id_fkey
FOREIGN KEY (product_id) REFERENCES public.inventory(id);

ALTER TABLE public.inventory DROP CONSTRAINT IF EXISTS inventory_company_id_sku_key;
ALTER TABLE public.inventory
ADD CONSTRAINT inventory_company_id_sku_key UNIQUE (company_id, sku);

ALTER TABLE public.inventory DROP CONSTRAINT IF EXISTS inventory_supplier_id_fkey;
ALTER TABLE public.inventory
ADD CONSTRAINT inventory_supplier_id_fkey
FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id);

COMMIT;
