-- InvoChat Schema Migration: From Full-featured to Lean Intelligence
-- This script migrates the database to a simplified, intelligence-focused schema.
-- It is designed to be run on an existing database and is idempotent.

BEGIN;

-- =================================================================
-- STEP 1: DROP DEPENDENT OBJECTS (Triggers, Functions, etc.)
-- =================================================================
-- Drop triggers that depend on functions we are about to drop.
DROP TRIGGER IF EXISTS validate_inventory_location_ref ON public.inventory;
DROP TRIGGER IF EXISTS validate_purchase_order_refs ON public.purchase_orders;

-- Drop all functions that might have dependencies on the tables being removed.
DROP FUNCTION IF EXISTS public.create_purchase_order_and_update_inventory(uuid, uuid, text, date, date, text, numeric, jsonb);
DROP FUNCTION IF EXISTS public.create_purchase_order_and_update_inventory(uuid, uuid, uuid, text, date, date, text, jsonb);
DROP FUNCTION IF EXISTS public.create_purchase_orders_from_suggestions_tx(uuid, jsonb);
DROP FUNCTION IF EXISTS public.delete_location(uuid, uuid, uuid);
DROP FUNCTION IF EXISTS public.delete_purchase_order(uuid, uuid);
DROP FUNCTION IF EXISTS public.get_purchase_order_analytics(uuid);
DROP FUNCTION IF EXISTS public.get_purchase_order_details(uuid, uuid);
DROP FUNCTION IF EXISTS public.get_purchase_orders(uuid, text, integer, integer);
DROP FUNCTION IF EXISTS public.receive_purchase_order_items(uuid, jsonb, uuid, uuid);
DROP FUNCTION IF EXISTS public.update_po_status(uuid, uuid);
DROP FUNCTION IF EXISTS public.update_purchase_order(uuid, uuid, uuid, text, text, date, date, text, jsonb);
DROP FUNCTION IF EXISTS public.validate_po_financials(uuid, bigint);
DROP FUNCTION IF EXISTS public.validate_same_company_reference();
DROP FUNCTION IF EXISTS public.delete_supplier_and_catalogs(uuid, uuid);


-- =reactivate
-- =================================================================
-- STEP 2: DROP OBSOLETE TABLES
-- =================================================================
DROP TABLE IF EXISTS public.purchase_order_items;
DROP TABLE IF EXISTS public.purchase_orders;
DROP TABLE IF EXISTS public.locations;
DROP TABLE IF EXISTS public.vendors;
DROP TABLE IF EXISTS public.supplier_catalogs;
DROP TABLE IF EXISTS public.reorder_rules;


-- =================================================================
-- STEP 3: ALTER EXISTING TABLES FOR SIMPLIFICATION
-- =================================================================
-- Standardize supplier table (migrating from 'vendors')
CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid NOT NULL DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    UNIQUE (company_id, name)
);

-- Alter inventory table to remove obsolete columns
ALTER TABLE public.inventory DROP COLUMN IF EXISTS location_id;
ALTER TABLE public.inventory DROP COLUMN IF EXISTS on_order_quantity;
ALTER TABLE public.inventory DROP COLUMN IF EXISTS landed_cost;
ALTER TABLE public.inventory DROP COLUMN IF EXISTS expiration_date;
ALTER TABLE public.inventory DROP COLUMN IF EXISTS lot_number;
ALTER TABLE public.inventory DROP COLUMN IF EXISTS manual_override;
ALTER TABLE public.inventory DROP COLUMN IF EXISTS conflict_status;
ALTER TABLE public.inventory DROP COLUMN IF EXISTS last_external_sync;

-- Add supplier_id to inventory if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='inventory' AND column_name='supplier_id') THEN
        ALTER TABLE public.inventory ADD COLUMN supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL;
    END IF;
END;
$$;


-- Alter sales table to remove unused columns
ALTER TABLE public.sales DROP COLUMN IF EXISTS created_by;

-- Alter customers table to remove unused columns
ALTER TABLE public.customers DROP COLUMN IF EXISTS platform;
ALTER TABLE public.customers DROP COLUMN IF EXISTS external_id;
ALTER TABLE public.customers DROP COLUMN IF EXISTS status;

-- Alter inventory_ledger to use product_id instead of sku
ALTER TABLE public.inventory_ledger DROP CONSTRAINT IF EXISTS inventory_ledger_product_id_fkey;
ALTER TABLE public.inventory_ledger DROP COLUMN IF EXISTS sku;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='inventory_ledger' AND column_name='product_id') THEN
        ALTER TABLE public.inventory_ledger ADD COLUMN product_id uuid;
    END IF;
END;
$$;

ALTER TABLE public.inventory_ledger
  ADD CONSTRAINT inventory_ledger_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.inventory(id) ON DELETE CASCADE;


-- =================================================================
-- STEP 4: RE-CREATE & UPDATE FUNCTIONS FOR NEW SCHEMA
-- =================================================================

-- Function to record a sale and update inventory ledger
CREATE OR REPLACE FUNCTION public.record_sale_transaction(
    p_company_id uuid,
    p_sale_items jsonb,
    p_customer_name text DEFAULT NULL::text,
    p_customer_email text DEFAULT NULL::text,
    p_payment_method text DEFAULT 'other'::text,
    p_notes text DEFAULT NULL::text,
    p_external_id text DEFAULT NULL::text
)
RETURNS sales
LANGUAGE plpgsql
AS $$
DECLARE
    new_sale_id uuid;
    new_sale_number text;
    sale_customer_id uuid;
    item record;
    inv_record record;
    new_sale public.sales;
BEGIN
    -- Get or create customer
    IF p_customer_email IS NOT NULL THEN
        SELECT id INTO sale_customer_id FROM customers WHERE company_id = p_company_id AND email = p_customer_email;
        IF sale_customer_id IS NULL THEN
            INSERT INTO customers (company_id, customer_name, email, total_orders, total_spent)
            VALUES (p_company_id, COALESCE(p_customer_name, 'New Customer'), p_customer_email, 0, 0)
            RETURNING id INTO sale_customer_id;
        END IF;
    END IF;

    -- Create the sale record
    INSERT INTO sales (company_id, sale_number, customer_name, customer_email, total_amount, payment_method, notes, external_id)
    VALUES (
        p_company_id,
        'INV-' || to_char(now(), 'YYYYMMDD-HH24MISS') || '-' || substr(md5(random()::text), 1, 4),
        p_customer_name,
        p_customer_email,
        (SELECT sum((i->>'unit_price')::numeric * (i->>'quantity')::integer) FROM jsonb_array_elements(p_sale_items) i),
        p_payment_method,
        p_notes,
        p_external_id
    ) RETURNING * INTO new_sale;

    new_sale_id := new_sale.id;
    new_sale_number := new_sale.sale_number;

    -- Process sale items
    FOR item IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(sku text, product_name text, quantity integer, unit_price numeric)
    LOOP
        -- Find inventory item by SKU
        SELECT id, cost, quantity INTO inv_record FROM inventory WHERE company_id = p_company_id AND sku = item.sku;

        IF inv_record IS NOT NULL THEN
            -- Insert into sale_items
            INSERT INTO sale_items (sale_id, company_id, sku, product_name, quantity, unit_price, cost_at_time)
            VALUES (new_sale_id, p_company_id, item.sku, item.product_name, item.quantity, item.unit_price, inv_record.cost);

            -- Update inventory quantity
            UPDATE inventory SET
                quantity = inv_record.quantity - item.quantity,
                last_sold_date = now()
            WHERE id = inv_record.id;

            -- Create ledger entry
            INSERT INTO inventory_ledger (company_id, product_id, change_type, quantity_change, new_quantity, related_id)
            VALUES (p_company_id, inv_record.id, 'sale', -item.quantity, inv_record.quantity - item.quantity, new_sale_id);
        ELSE
             -- Log a warning or handle missing inventory item case
            RAISE WARNING 'SKU % not found in inventory for sale %', item.sku, new_sale_number;
        END IF;
    END LOOP;

    -- Update customer stats
    IF sale_customer_id IS NOT NULL THEN
        UPDATE customers
        SET
            total_orders = total_orders + 1,
            total_spent = total_spent + new_sale.total_amount,
            first_order_date = COALESCE(first_order_date, now()::date)
        WHERE id = sale_customer_id;
    END IF;

    RETURN new_sale;
END;
$$;


-- Function to get supplier performance (simplified)
CREATE OR REPLACE FUNCTION public.get_supplier_performance(p_company_id uuid)
RETURNS TABLE(supplier_name text, total_products bigint, total_inventory_value numeric)
LANGUAGE sql
AS $$
  SELECT
      s.name AS supplier_name,
      COUNT(i.id) AS total_products,
      SUM(i.quantity * i.cost) AS total_inventory_value
  FROM public.suppliers s
  JOIN public.inventory i ON s.id = i.supplier_id
  WHERE s.company_id = p_company_id
  AND i.deleted_at IS NULL
  GROUP BY s.name;
$$;


-- Function to get unified inventory (simplified)
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
            (i.quantity * i.cost) AS total_value,
            i.reorder_point,
            s.name AS supplier_name,
            s.id AS supplier_id
        FROM inventory i
        LEFT JOIN suppliers s ON i.supplier_id = s.id
        WHERE i.company_id = p_company_id
          AND i.deleted_at IS NULL
          AND (p_product_id_filter IS NULL OR i.id = p_product_id_filter)
          AND (p_query IS NULL OR i.name ILIKE '%' || p_query || '%' OR i.sku ILIKE '%' || p_query || '%')
          AND (p_category IS NULL OR i.category = p_category)
          AND (p_supplier_id IS NULL OR i.supplier_id = p_supplier_id)
    )
    SELECT
        (SELECT json_agg(fi.*) FROM (SELECT * FROM filtered_inventory ORDER BY product_name LIMIT p_limit OFFSET p_offset) fi) AS items,
        (SELECT COUNT(*) FROM filtered_inventory) AS total_count;
END;
$$;

-- Function to get reorder suggestions (simplified)
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
    unit_cost numeric,
    base_quantity integer
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        i.id as product_id,
        i.sku,
        i.name as product_name,
        i.quantity as current_quantity,
        i.reorder_point,
        -- Suggested quantity is what's needed to get back to the reorder point + a buffer (e.g., reorder_quantity or just enough to get above the point)
        -- Simplified: just suggest what is needed to get back to the reorder point.
        GREATEST(0, i.reorder_point - i.quantity) AS suggested_reorder_quantity,
        s.id as supplier_id,
        s.name as supplier_name,
        i.cost as unit_cost,
        GREATEST(0, i.reorder_point - i.quantity) AS base_quantity
    FROM inventory i
    LEFT JOIN suppliers s ON i.supplier_id = s.id
    WHERE i.company_id = p_company_id
    AND i.deleted_at IS NULL
    AND i.reorder_point IS NOT NULL
    AND i.quantity < i.reorder_point;
$$;


COMMIT;
