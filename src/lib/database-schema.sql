
-- =========== InvoChat Database Migration & Simplification Script ===========
-- This script transforms the existing database to the new, simplified schema.
-- It is designed to be run once on your existing database.

-- Step 1: Drop legacy functions that have dependencies on tables to be dropped.
-- This must be done before dropping the tables themselves.
DROP FUNCTION IF EXISTS public.create_purchase_order_and_update_inventory(uuid, uuid, uuid, text, date, date, text, jsonb);
DROP FUNCTION IF EXISTS public.create_purchase_orders_from_suggestions_tx(uuid, jsonb);
DROP FUNCTION IF EXISTS public.delete_location_and_unassign_inventory(uuid);
DROP FUNCTION IF EXISTS public.delete_purchase_order(uuid, uuid);
DROP FUNCTION IF EXISTS public.delete_supplier_and_catalogs(uuid, uuid);
DROP FUNCTION IF EXISTS public.get_purchase_order_details(uuid, uuid);
DROP FUNCTION IF EXISTS public.get_purchase_orders(uuid, text, integer, integer);
DROP FUNCTION IF EXISTS public.get_supplier_performance(uuid, integer);
DROP FUNCTION IF EXISTS public.get_suppliers_with_performance(uuid);
DROP FUNCTION IF EXISTS public.receive_purchase_order_items(uuid, jsonb, uuid, uuid);
DROP FUNCTION IF EXISTS public.update_inventory_item_with_lock(uuid, text, integer, text, text, numeric, integer, numeric, text, uuid);
DROP FUNCTION IF EXISTS public.update_po_status(uuid, uuid);
DROP FUNCTION IF EXISTS public.update_purchase_order(uuid, uuid, uuid, text, text, date, date, text, jsonb);
DROP FUNCTION IF EXISTS public.get_purchase_order_analytics(uuid);


-- Step 2: Drop all unnecessary tables. CASCADE will handle related indexes, constraints, etc.
DROP TABLE IF EXISTS public.purchase_order_items CASCADE;
DROP TABLE IF EXISTS public.purchase_orders CASCADE;
DROP TABLE IF EXISTS public.locations CASCADE;
DROP TABLE IF EXISTS public.vendors CASCADE;
DROP TABLE IF EXISTS public.reorder_rules CASCADE;
DROP TABLE IF EXISTS public.supplier_catalogs CASCADE;


-- Step 3: Simplify existing tables by dropping obsolete columns.
ALTER TABLE public.inventory
  DROP COLUMN IF EXISTS location_id,
  DROP COLUMN IF EXISTS on_order_quantity,
  DROP COLUMN IF EXISTS landed_cost,
  DROP COLUMN IF EXISTS expiration_date,
  DROP COLUMN IF EXISTS lot_number,
  ADD COLUMN IF NOT EXISTS supplier_id UUID REFERENCES public.suppliers(id) ON DELETE SET NULL;

ALTER TABLE public.customers
  DROP COLUMN IF EXISTS platform,
  DROP COLUMN IF EXISTS external_id,
  DROP COLUMN IF EXISTS status;

ALTER TABLE public.sales
  DROP COLUMN IF EXISTS created_by;

ALTER TABLE public.inventory_ledger
  ADD COLUMN IF NOT EXISTS product_id UUID,
  DROP COLUMN IF EXISTS sku;

-- Step 4: Re-create the `suppliers` table with the new simplified schema.
-- We drop and re-create instead of altering to ensure a clean state.
DROP TABLE IF EXISTS public.suppliers CASCADE;
CREATE TABLE public.suppliers (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT suppliers_pkey PRIMARY KEY (id),
    CONSTRAINT suppliers_company_id_name_key UNIQUE (company_id, name)
);
CREATE INDEX idx_suppliers_name_company ON public.suppliers(company_id, name);

-- Step 5: Add foreign key constraint from inventory to the new suppliers table.
-- This is done after the table is recreated.
ALTER TABLE public.inventory
  ADD CONSTRAINT inventory_supplier_id_fkey
  FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) ON DELETE SET NULL;

-- Add foreign key constraint for inventory_ledger to inventory
ALTER TABLE public.inventory_ledger
  ADD CONSTRAINT inventory_ledger_product_id_fkey
  FOREIGN KEY (product_id) REFERENCES public.inventory(id) ON DELETE CASCADE;


-- Step 6: Create or replace functions with updated, simplified logic.

-- get_unified_inventory: REMOVED on_order_quantity and location logic
CREATE OR REPLACE FUNCTION public.get_unified_inventory(p_company_id uuid, p_query text DEFAULT NULL, p_category text DEFAULT NULL, p_supplier_id uuid DEFAULT NULL, p_product_id_filter uuid DEFAULT NULL, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
RETURNS TABLE(items json, total_count bigint)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  WITH filtered_inventory AS (
      SELECT i.*
      FROM inventory i
      WHERE i.company_id = p_company_id
        AND i.deleted_at IS NULL
        AND (p_query IS NULL OR i.name ILIKE '%' || p_query || '%' OR i.sku ILIKE '%' || p_query || '%')
        AND (p_category IS NULL OR i.category = p_category)
        AND (p_supplier_id IS NULL OR i.supplier_id = p_supplier_id)
        AND (p_product_id_filter IS NULL OR i.id = p_product_id_filter)
  )
  SELECT
      (SELECT json_agg(
          json_build_object(
              'product_id', fi.id,
              'sku', fi.sku,
              'product_name', fi.name,
              'category', fi.category,
              'quantity', fi.quantity,
              'cost', fi.cost,
              'price', fi.price,
              'total_value', fi.quantity * fi.cost,
              'reorder_point', fi.reorder_point,
              'supplier_name', s.name,
              'supplier_id', s.id
          )
      )
      FROM (
          SELECT *
          FROM filtered_inventory
          ORDER BY name
          LIMIT p_limit
          OFFSET p_offset
      ) AS fi
      LEFT JOIN suppliers s ON fi.supplier_id = s.id AND fi.company_id = s.company_id),
      (SELECT COUNT(*) FROM filtered_inventory)::bigint;
END;
$$;


-- record_sale_transaction: CORRECTED to use product_id instead of sku for ledger
CREATE OR REPLACE FUNCTION public.record_sale_transaction(p_company_id uuid, p_sale_items jsonb, p_customer_name text DEFAULT NULL, p_customer_email text DEFAULT NULL, p_payment_method text DEFAULT 'other', p_notes text DEFAULT NULL, p_external_id text DEFAULT NULL)
RETURNS sales
LANGUAGE plpgsql
AS $$
DECLARE
    new_sale sales;
    sale_item jsonb;
    inv_record inventory;
BEGIN
    INSERT INTO sales (company_id, sale_number, customer_name, customer_email, total_amount, payment_method, notes, external_id)
    VALUES (
        p_company_id,
        'SALE-' || nextval('sales_sale_number_seq'),
        p_customer_name,
        p_customer_email,
        (SELECT sum((item->>'unit_price')::numeric * (item->>'quantity')::integer) FROM jsonb_array_elements(p_sale_items) item),
        p_payment_method,
        p_notes,
        p_external_id
    ) RETURNING * INTO new_sale;

    FOR sale_item IN SELECT * FROM jsonb_array_elements(p_sale_items)
    LOOP
        SELECT * INTO inv_record FROM inventory WHERE company_id = p_company_id AND sku = sale_item->>'sku' AND deleted_at IS NULL;

        IF inv_record IS NULL THEN
            RAISE EXCEPTION 'Product with SKU % not found in inventory.', sale_item->>'sku';
        END IF;

        INSERT INTO sale_items (sale_id, company_id, sku, product_name, quantity, unit_price, cost_at_time)
        VALUES (
            new_sale.id,
            p_company_id,
            sale_item->>'sku',
            sale_item->>'product_name',
            (sale_item->>'quantity')::integer,
            (sale_item->>'unit_price')::numeric,
            inv_record.cost
        );

        INSERT INTO inventory_ledger (company_id, product_id, change_type, quantity_change, new_quantity, related_id, notes)
        VALUES (
            p_company_id,
            inv_record.id,
            'sale',
            -(sale_item->>'quantity')::integer,
            inv_record.quantity - (sale_item->>'quantity')::integer,
            new_sale.id,
            'Sale #' || new_sale.sale_number
        );
        
        UPDATE inventory
        SET
            quantity = quantity - (sale_item->>'quantity')::integer,
            last_sold_date = CURRENT_DATE,
            updated_at = now()
        WHERE id = inv_record.id;
    END LOOP;

    RETURN new_sale;
END;
$$;

-- get_business_profile: REMOVED outstanding_po_value
CREATE OR REPLACE FUNCTION public.get_business_profile(p_company_id uuid)
RETURNS TABLE(monthly_revenue bigint, risk_tolerance text) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COALESCE((SELECT SUM(total_amount) FROM sales WHERE company_id = p_company_id AND created_at >= NOW() - INTERVAL '30 days'), 0)::bigint AS monthly_revenue,
        'medium'::text as risk_tolerance;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- get_reorder_suggestions: SIMPLIFIED to not rely on complex PO logic
CREATE OR REPLACE FUNCTION public.get_reorder_suggestions(p_company_id uuid, p_fast_moving_days integer)
RETURNS TABLE(product_id uuid, sku text, product_name text, current_quantity integer, reorder_point integer, suggested_reorder_quantity integer, supplier_name text, supplier_id uuid, unit_cost bigint, base_quantity integer)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  WITH sales_velocity AS (
    SELECT
      si.sku,
      SUM(si.quantity) / p_fast_moving_days::decimal AS daily_velocity
    FROM sale_items si
    JOIN sales s ON si.sale_id = s.id
    WHERE s.company_id = p_company_id
      AND s.created_at >= NOW() - (p_fast_moving_days || ' days')::interval
    GROUP BY si.sku
  )
  SELECT
    i.id as product_id,
    i.sku,
    i.name as product_name,
    i.quantity as current_quantity,
    i.reorder_point,
    GREATEST(i.reorder_point, COALESCE(sv.daily_velocity::integer * (COALESCE(s.default_lead_time_days, 7) + 7), 0)) - i.quantity AS suggested_reorder_quantity,
    s.name as supplier_name,
    s.id as supplier_id,
    i.cost::bigint as unit_cost,
    GREATEST(i.reorder_point, 0) - i.quantity AS base_quantity
  FROM inventory i
  LEFT JOIN suppliers s ON i.supplier_id = s.id AND i.company_id = s.company_id
  LEFT JOIN sales_velocity sv ON i.sku = sv.sku
  WHERE i.company_id = p_company_id
    AND i.deleted_at IS NULL
    AND i.reorder_point IS NOT NULL
    AND i.quantity < i.reorder_point;
END;
$$;


-- Final Step: Clean up any now-unused triggers or types if they exist.
DROP TRIGGER IF EXISTS validate_purchase_order_refs ON public.purchase_orders;

-- The functions related to inventory ledger and sales transaction are kept as they are core.
-- All other unnecessary functions and tables have been dropped.
SELECT 'Migration script completed successfully.';
