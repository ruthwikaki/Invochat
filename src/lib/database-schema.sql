-- InvoChat: Database Migration & Simplification Script
-- This script transforms the database to the new, focused "Inventory Intelligence" schema.
-- It is designed to be idempotent and can be run safely on the existing database.

-- STEP 1: Drop all functions that depend on the tables we are about to remove.
-- This must be done first to avoid dependency errors.
DROP FUNCTION IF EXISTS public.create_purchase_order_and_update_inventory(uuid,uuid,text,date,date,text,numeric,jsonb);
DROP FUNCTION IF EXISTS public.create_purchase_orders_from_suggestions_tx(uuid, jsonb);
DROP FUNCTION IF EXISTS public.delete_location(uuid, uuid, uuid);
DROP FUNCTION IF EXISTS public.delete_purchase_order(uuid, uuid);
DROP FUNCTION IF EXISTS public.delete_supplier_and_catalogs(uuid, uuid);
DROP FUNCTION IF EXISTS public.get_purchase_order_analytics(uuid);
DROP FUNCTION IF EXISTS public.get_purchase_order_details(uuid, uuid);
DROP FUNCTION IF EXISTS public.get_purchase_orders(uuid, text, integer, integer);
DROP FUNCTION IF EXISTS public.get_suppliers_with_performance(uuid);
DROP FUNCTION IF EXISTS public.receive_purchase_order_items(uuid, jsonb, uuid, uuid);
DROP FUNCTION IF EXISTS public.update_inventory_item_with_lock(uuid,text,integer,text,text,numeric,integer,numeric,text,uuid);
DROP FUNCTION IF EXISTS public.update_inventory_item_with_lock(uuid,text,integer,text,text,bigint,integer,bigint,text,uuid);
DROP FUNCTION IF EXISTS public.update_po_status(uuid, uuid);
DROP FUNCTION IF EXISTS public.update_purchase_order(uuid,uuid,uuid,text,text,date,date,text,jsonb);
DROP FUNCTION IF EXISTS public.validate_po_financials(uuid, bigint);

-- STEP 2: Drop the now-unused tables. CASCADE handles dependent indexes and constraints.
DROP TABLE IF EXISTS public.purchase_order_items CASCADE;
DROP TABLE IF EXISTS public.purchase_orders CASCADE;
DROP TABLE IF EXISTS public.reorder_rules CASCADE;
DROP TABLE IF EXISTS public.supplier_catalogs CASCADE;
DROP TABLE IF EXISTS public.vendors CASCADE;
DROP TABLE IF EXISTS public.locations CASCADE;

-- STEP 3: Alter existing tables to remove obsolete columns.
-- We use a function to safely drop columns only if they exist.
CREATE OR REPLACE FUNCTION drop_column_if_exists(table_name TEXT, column_name TEXT)
RETURNS VOID AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
        AND columns.table_name = drop_column_if_exists.table_name
        AND columns.column_name = drop_column_if_exists.column_name
    ) THEN
        EXECUTE 'ALTER TABLE public.' || quote_ident(table_name) || ' DROP COLUMN ' || quote_ident(column_name);
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Remove location and PO-related columns from the inventory table
SELECT drop_column_if_exists('inventory', 'location_id');
SELECT drop_column_if_exists('inventory', 'on_order_quantity');
SELECT drop_column_if_exists('inventory', 'landed_cost');
SELECT drop_column_if_exists('inventory', 'expiration_date');
SELECT drop_column_if_exists('inventory', 'lot_number');
SELECT drop_column_if_exists('inventory', 'conflict_status');
SELECT drop_column_if_exists('inventory', 'manual_override');

-- Remove external platform references from customers table
SELECT drop_column_if_exists('customers', 'platform');
SELECT drop_column_if_exists('customers', 'external_id');
SELECT drop_column_if_exists('customers', 'status');

-- Remove unnecessary user_id from sales table (will use audit log instead)
SELECT drop_column_if_exists('sales', 'created_by');

-- Drop the helper function as it's no longer needed
DROP FUNCTION drop_column_if_exists(TEXT, TEXT);


-- STEP 4: Alter the inventory_ledger table to use product_id instead of SKU
-- First, drop the old SKU column if it exists
DO $$
BEGIN
   IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_name='inventory_ledger' AND column_name='sku'
   ) THEN
      ALTER TABLE public.inventory_ledger DROP COLUMN sku;
   END IF;
END;
$$;

-- Add the product_id column if it doesn't exist
DO $$
BEGIN
   IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_name='inventory_ledger' AND column_name='product_id'
   ) THEN
      ALTER TABLE public.inventory_ledger ADD COLUMN product_id uuid;
   END IF;
END;
$$;

-- Add the foreign key constraint safely
ALTER TABLE public.inventory_ledger DROP CONSTRAINT IF EXISTS inventory_ledger_product_id_fkey;
ALTER TABLE public.inventory_ledger ADD CONSTRAINT inventory_ledger_product_id_fkey
   FOREIGN KEY (product_id) REFERENCES public.inventory(id);

-- Make the column not nullable after ensuring it exists
ALTER TABLE public.inventory_ledger ALTER COLUMN product_id SET NOT NULL;
ALTER TABLE public.inventory_ledger ALTER COLUMN new_quantity SET NOT NULL;


-- STEP 5: Add supplier_id to the inventory table if it doesn't exist
DO $$
BEGIN
   IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'inventory' AND column_name = 'supplier_id'
   ) THEN
      ALTER TABLE public.inventory ADD COLUMN supplier_id uuid;
   END IF;
END;
$$;

-- Add the foreign key constraint safely
ALTER TABLE public.inventory DROP CONSTRAINT IF EXISTS inventory_supplier_id_fkey;
ALTER TABLE public.inventory ADD CONSTRAINT inventory_supplier_id_fkey
  FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) ON DELETE SET NULL;


-- STEP 6: Re-create and update necessary functions for the new schema.
-- This ensures all functions are up-to-date with the simplified structure.
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
            i.id,
            i.sku,
            i.name,
            i.category,
            i.quantity,
            i.cost,
            i.price,
            i.reorder_point,
            s.name AS supplier_name,
            s.id AS supplier_id
        FROM public.inventory i
        LEFT JOIN public.suppliers s ON i.supplier_id = s.id AND i.company_id = s.company_id
        WHERE
            i.company_id = p_company_id
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
                'supplier_name', fi.supplier_name,
                'supplier_id', fi.supplier_id
            )
        ) FROM (SELECT * FROM filtered_inventory ORDER BY name LIMIT p_limit OFFSET p_offset) AS fi) AS items,
        (SELECT COUNT(*) FROM filtered_inventory) AS total_count;
END;
$$;


DROP FUNCTION IF EXISTS public.record_sale_transaction(uuid, uuid, jsonb, text, text, text, text, text);
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
RETURNS sales AS $$
DECLARE
    new_sale sales;
    sale_item jsonb;
    inv_id uuid;
    inv_version integer;
BEGIN
    INSERT INTO sales (company_id, sale_number, customer_name, customer_email, total_amount, payment_method, notes, created_by, external_id)
    VALUES (
        p_company_id,
        'SALE-' || nextval('sales_sale_number_seq'),
        p_customer_name,
        p_customer_email,
        (SELECT sum((item->>'quantity')::int * (item->>'unit_price')::numeric) FROM jsonb_array_elements(p_sale_items) item),
        p_payment_method,
        p_notes,
        p_user_id,
        p_external_id
    ) RETURNING * INTO new_sale;

    FOR sale_item IN SELECT * FROM jsonb_array_elements(p_sale_items)
    LOOP
        SELECT id, version INTO inv_id, inv_version
        FROM inventory
        WHERE company_id = p_company_id AND sku = sale_item->>'sku' AND deleted_at IS NULL;

        IF inv_id IS NOT NULL THEN
            UPDATE inventory
            SET
                quantity = quantity - (sale_item->>'quantity')::int,
                last_sold_date = CURRENT_DATE,
                version = version + 1
            WHERE id = inv_id AND company_id = p_company_id;

            INSERT INTO sale_items (sale_id, company_id, sku, product_name, quantity, unit_price, cost_at_time)
            VALUES (new_sale.id, p_company_id, sale_item->>'sku', sale_item->>'product_name', (sale_item->>'quantity')::int, (sale_item->>'unit_price')::numeric, (SELECT cost FROM inventory WHERE id = inv_id));
            
            INSERT INTO inventory_ledger (company_id, product_id, change_type, quantity_change, new_quantity, related_id, notes)
            SELECT p_company_id, inv_id, 'sale', -(sale_item->>'quantity')::int, quantity, new_sale.id, 'Sale #' || new_sale.sale_number
            FROM inventory WHERE id = inv_id;
        END IF;
    END LOOP;

    RETURN new_sale;
END;
$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS public.get_business_profile(uuid);
CREATE OR REPLACE FUNCTION public.get_business_profile(p_company_id uuid)
RETURNS TABLE(monthly_revenue bigint)
LANGUAGE sql
AS $$
    SELECT
        COALESCE(SUM(total_amount), 0)::bigint AS monthly_revenue
    FROM public.sales
    WHERE
        company_id = p_company_id
        AND created_at >= now() - interval '30 days';
$$;

-- STEP 7: Final cleanup of any other old functions that may have been missed.
DROP FUNCTION IF EXISTS public.batch_upsert_with_transaction(text,jsonb,text[]);
DROP FUNCTION IF EXISTS public.check_inventory_references(uuid,text[]);
DROP FUNCTION IF EXISTS public.delete_supplier_and_catalogs(uuid,uuid);
DROP FUNCTION IF EXISTS public.update_inventory_item_with_lock(uuid,text,integer,text,text,bigint,integer,bigint,text);
DROP FUNCTION IF EXISTS public.validate_same_company_reference();

-- Drop trigger that relied on validate_same_company_reference
DROP TRIGGER IF EXISTS validate_inventory_location_ref ON public.inventory;
DROP TRIGGER IF EXISTS validate_purchase_order_refs ON public.purchase_orders;

-- Log completion
SELECT 'Database migration to simplified schema is complete.' as status;
