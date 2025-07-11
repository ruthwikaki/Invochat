-- Simplified DB Schema for InvoChat - Focus on Intelligence
-- This script is designed to be run on an existing database to migrate it to the new, leaner schema.

-- STEP 1: Drop all functions that depend on the tables we are about to drop.
-- This must be done first to avoid dependency errors.
DROP FUNCTION IF EXISTS public.get_purchase_order_details(uuid, uuid);
DROP FUNCTION IF EXISTS public.get_purchase_orders(uuid, text, integer, integer);
DROP FUNCTION IF EXISTS public.get_supplier_performance(uuid);
DROP FUNCTION IF EXISTS public.receive_purchase_order_items(uuid, jsonb, uuid, uuid);
DROP FUNCTION IF EXISTS public.delete_purchase_order(uuid, uuid);
DROP FUNCTION IF EXISTS public.update_purchase_order(uuid, uuid, uuid, text, text, date, date, text, jsonb);
DROP FUNCTION IF EXISTS public.create_purchase_order_and_update_inventory(uuid, uuid, uuid, text, date, date, text, jsonb);
DROP FUNCTION IF EXISTS public.update_po_status(uuid, uuid);
DROP FUNCTION IF EXISTS public.get_purchase_order_analytics(uuid);
DROP FUNCTION IF EXISTS public.get_suppliers_with_performance(uuid);
DROP FUNCTION IF EXISTS public.delete_location(uuid, uuid, uuid);
DROP TRIGGER IF EXISTS validate_purchase_order_refs ON public.purchase_orders;
DROP TRIGGER IF EXISTS validate_inventory_location_ref ON public.inventory;

-- STEP 2: Drop unused tables using CASCADE to handle remaining dependencies like indexes.
DROP TABLE IF EXISTS public.purchase_order_items CASCADE;
DROP TABLE IF EXISTS public.purchase_orders CASCADE;
DROP TABLE IF EXISTS public.vendors CASCADE; -- Old name for suppliers
DROP TABLE IF EXISTS public.locations CASCADE;
DROP TABLE IF EXISTS public.supplier_catalogs CASCADE;
DROP TABLE IF EXISTS public.reorder_rules CASCADE;

-- STEP 3: Simplify the 'inventory' table
-- Remove location_id and other unnecessary columns
ALTER TABLE public.inventory DROP COLUMN IF EXISTS location_id;
ALTER TABLE public.inventory DROP COLUMN IF EXISTS on_order_quantity;
ALTER TABLE public.inventory DROP COLUMN IF EXISTS landed_cost;
ALTER TABLE public.inventory DROP COLUMN IF EXISTS expiration_date;
ALTER TABLE public.inventory DROP COLUMN IF EXISTS lot_number;
ALTER TABLE public.inventory DROP COLUMN IF EXISTS conflict_status;
ALTER TABLE public.inventory DROP COLUMN IF EXISTS manual_override;
ALTER TABLE public.inventory DROP COLUMN IF EXISTS last_external_sync;
-- Add a simple supplier_id foreign key
ALTER TABLE public.inventory ADD COLUMN IF NOT EXISTS supplier_id UUID REFERENCES public.suppliers(id) ON DELETE SET NULL;

-- STEP 4: Simplify the 'customers' table
ALTER TABLE public.customers DROP COLUMN IF EXISTS platform;
ALTER TABLE public.customers DROP COLUMN IF EXISTS external_id;
ALTER TABLE public.customers DROP COLUMN IF EXISTS status;

-- STEP 5: Create the simplified inventory ledger table.
DROP TABLE IF EXISTS public.inventory_ledger;
CREATE TABLE public.inventory_ledger (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.inventory(id) ON DELETE CASCADE,
    change_type text NOT NULL, -- 'sale', 'restock', 'adjustment'
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    related_id uuid, -- e.g., sale_id for sales, or null for adjustments
    notes text,
    CONSTRAINT inventory_ledger_pkey PRIMARY KEY (id)
);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_product_id ON public.inventory_ledger(product_id);

-- STEP 6: Re-create and update necessary functions with simplified logic.

-- get_reorder_suggestions: Simplified to remove dependencies on old tables.
CREATE OR REPLACE FUNCTION public.get_reorder_suggestions(p_company_id uuid)
RETURNS TABLE(
    product_id uuid,
    sku text,
    product_name text,
    current_quantity integer,
    reorder_point integer,
    suggested_reorder_quantity integer,
    supplier_name text,
    supplier_id uuid,
    unit_cost integer,
    base_quantity integer
)
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
        i.reorder_point - i.quantity AS suggested_reorder_quantity,
        s.name as supplier_name,
        s.id as supplier_id,
        CAST(i.cost AS integer) as unit_cost,
        i.reorder_point - i.quantity AS base_quantity
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

-- record_sale_transaction: Updated to work with the new inventory_ledger and simplified schema.
CREATE OR REPLACE FUNCTION public.record_sale_transaction(
    p_company_id uuid,
    p_user_id uuid,
    p_sale_items jsonb,
    p_customer_name text DEFAULT NULL::text,
    p_customer_email text DEFAULT NULL::text,
    p_payment_method text DEFAULT 'other'::text,
    p_notes text DEFAULT NULL::text,
    p_external_id text DEFAULT NULL::text
)
RETURNS sales
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    new_sale sales;
    item record;
    inv record;
    new_customer_id uuid;
    total_sale_amount numeric := 0;
BEGIN
    -- Upsert customer
    IF p_customer_email IS NOT NULL THEN
        INSERT INTO public.customers (company_id, customer_name, email)
        VALUES (p_company_id, COALESCE(p_customer_name, p_customer_email), p_customer_email)
        ON CONFLICT (company_id, email) DO UPDATE SET customer_name = EXCLUDED.customer_name
        RETURNING id INTO new_customer_id;
    END IF;
    
    -- Calculate total sale amount
    FOR item IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(sku text, quantity int, unit_price numeric)
    LOOP
        total_sale_amount := total_sale_amount + (item.quantity * item.unit_price);
    END LOOP;

    -- Create sale record
    INSERT INTO public.sales (company_id, sale_number, customer_name, customer_email, total_amount, payment_method, notes, created_by, external_id)
    VALUES (p_company_id, 'SALE-' || (SELECT to_hex(nextval('serial'))), p_customer_name, p_customer_email, total_sale_amount, p_payment_method, p_notes, p_user_id, p_external_id)
    RETURNING * INTO new_sale;

    -- Process sale items and update inventory
    FOR item IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(sku text, product_name text, quantity int, unit_price numeric, cost_at_time numeric)
    LOOP
        -- Find the inventory record
        SELECT * INTO inv FROM public.inventory WHERE inventory.company_id = p_company_id AND inventory.sku = item.sku AND inventory.deleted_at IS NULL;

        IF inv.id IS NOT NULL THEN
            -- Insert into sale_items
            INSERT INTO public.sale_items (sale_id, company_id, sku, product_name, quantity, unit_price, cost_at_time)
            VALUES (new_sale.id, p_company_id, item.sku, inv.name, item.quantity, item.unit_price, inv.cost);

            -- Update inventory quantity and log change
            INSERT INTO public.inventory_ledger (company_id, product_id, change_type, quantity_change, new_quantity, related_id, notes)
            VALUES (p_company_id, inv.id, 'sale', -item.quantity, inv.quantity - item.quantity, new_sale.id, 'Sale #' || new_sale.sale_number);
            
            UPDATE public.inventory
            SET quantity = quantity - item.quantity, last_sold_date = CURRENT_DATE
            WHERE id = inv.id;
        END IF;
    END LOOP;

    RETURN new_sale;
END;
$$;


-- get_unified_inventory: Simplified to remove location parameter.
CREATE OR REPLACE FUNCTION public.get_unified_inventory(p_company_id uuid, p_query text DEFAULT NULL::text, p_category text DEFAULT NULL::text, p_supplier_id uuid DEFAULT NULL::uuid, p_product_id_filter uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS TABLE(items json, total_count bigint)
 LANGUAGE plpgsql
AS $function$
DECLARE
    query_sql TEXT;
    count_sql TEXT;
    where_clauses TEXT[] := ARRAY['i.company_id = $1', 'i.deleted_at IS NULL'];
BEGIN
    IF p_query IS NOT NULL AND p_query <> '' THEN
        where_clauses := where_clauses || ' (i.name ILIKE $2 OR i.sku ILIKE $2)';
    END IF;
    IF p_category IS NOT NULL AND p_category <> '' THEN
        where_clauses := where_clauses || ' i.category = $3';
    END IF;
    IF p_supplier_id IS NOT NULL THEN
        where_clauses := where_clauses || ' i.supplier_id = $4';
    END IF;
    IF p_product_id_filter IS NOT NULL THEN
        where_clauses := where_clauses || ' i.id = $5';
    END IF;

    query_sql := '
        SELECT COALESCE(json_agg(t.*), ''[]''::json)
        FROM (
            SELECT
                i.id AS product_id,
                i.sku,
                i.name AS product_name,
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
            WHERE ' || array_to_string(where_clauses, ' AND ') || '
            ORDER BY i.name
            LIMIT $6 OFFSET $7
        ) t';

    count_sql := '
        SELECT COUNT(*)
        FROM inventory i
        WHERE ' || array_to_string(where_clauses, ' AND ');

    EXECUTE format('SELECT (%s), (%s)', query_sql, count_sql)
    INTO items, total_count
    USING p_company_id, 
          '%' || p_query || '%',
          p_category,
          p_supplier_id,
          p_product_id_filter,
          p_limit,
          p_offset;
END;
$function$;

-- get_business_profile: Simplified to remove PO value.
CREATE OR REPLACE FUNCTION public.get_business_profile(p_company_id uuid)
RETURNS TABLE(monthly_revenue bigint)
LANGUAGE sql
AS $$
    SELECT
        COALESCE(SUM(total_amount), 0) AS monthly_revenue
    FROM public.sales
    WHERE company_id = p_company_id AND created_at >= NOW() - INTERVAL '30 days';
$$;


-- Final sanity check: Ensure all other necessary functions still exist or are recreated if they were dropped.
-- Most of the other functions (analytics, etc.) did not have hard dependencies on the dropped tables and should be fine.

-- This concludes the migration script.

