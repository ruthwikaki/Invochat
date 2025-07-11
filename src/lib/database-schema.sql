-- InvoChat - Simplified Database Migration Script
-- This script transforms an existing InvoChat database into the new, leaner "inventory intelligence" schema.
-- It is designed to be idempotent and can be re-run if it fails.

-- Step 1: Drop all functions that might have dependencies on the tables we will modify or drop.
-- This must be done first to avoid dependency errors.
DROP FUNCTION IF EXISTS public.create_purchase_order_and_update_inventory(uuid, uuid, text, date, date, text, jsonb);
DROP FUNCTION IF EXISTS public.create_purchase_orders_from_suggestions_tx(uuid, jsonb);
DROP FUNCTION IF EXISTS public.delete_location(uuid, uuid, uuid);
DROP FUNCTION IF EXISTS public.delete_purchase_order(uuid, uuid);
DROP FUNCTION IF EXISTS public.delete_supplier_and_catalogs(uuid, uuid);
DROP FUNCTION IF EXISTS public.get_purchase_order_details(uuid, uuid);
DROP FUNCTION IF EXISTS public.get_purchase_orders(uuid, text, integer, integer);
DROP FUNCTION IF EXISTS public.get_suppliers_with_performance(uuid);
DROP FUNCTION IF EXISTS public.receive_purchase_order_items(uuid, jsonb, uuid, uuid);
DROP FUNCTION IF EXISTS public.update_purchase_order(uuid, uuid, uuid, text, text, date, date, text, jsonb);
DROP FUNCTION IF EXISTS public.update_po_status(uuid, uuid);
DROP FUNCTION IF EXISTS public.validate_po_financials(uuid, bigint);
DROP FUNCTION IF EXISTS public.get_purchase_order_analytics(uuid);
DROP FUNCTION IF EXISTS public.update_inventory_item_with_lock(uuid, text, integer, text, text, bigint, integer, bigint, text, uuid);

-- Drop triggers before dropping the functions they use or the tables they are on.
DROP TRIGGER IF EXISTS validate_inventory_location_ref ON public.inventory;
DROP TRIGGER IF EXISTS validate_purchase_order_refs ON public.purchase_orders;

-- Now, drop the functions that had triggers depending on them.
DROP FUNCTION IF EXISTS public.validate_same_company_reference();


-- Step 2: Drop all tables that are no longer needed in the new schema.
-- Using CASCADE to handle any remaining minor dependencies like constraints.
DROP TABLE IF EXISTS public.purchase_order_items CASCADE;
DROP TABLE IF EXISTS public.purchase_orders CASCADE;
DROP TABLE IF EXISTS public.supplier_catalogs CASCADE;
DROP TABLE IF EXISTS public.reorder_rules CASCADE;
DROP TABLE IF EXISTS public.locations CASCADE;


-- Step 3: Rename the 'vendors' table to 'suppliers'.
-- We use a check to only run this if the 'vendors' table exists and 'suppliers' does not.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'vendors' AND table_schema = 'public') AND
       NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'suppliers' AND table_schema = 'public') THEN
        ALTER TABLE public.vendors RENAME TO suppliers;
    END IF;
END;
$$;


-- Step 4: Alter the newly named 'suppliers' table.
-- Drop old columns and rename 'vendor_name' to 'name'.
ALTER TABLE public.suppliers DROP COLUMN IF EXISTS contact_info;
ALTER TABLE public.suppliers DROP COLUMN IF EXISTS address;
ALTER TABLE public.suppliers DROP COLUMN IF EXISTS terms;
ALTER TABLE public.suppliers DROP COLUMN IF EXISTS account_number;

-- Conditionally rename the column
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'suppliers' AND column_name = 'vendor_name' AND table_schema = 'public') THEN
        ALTER TABLE public.suppliers RENAME COLUMN vendor_name TO name;
    END IF;
END;
$$;


-- Step 5: Alter the 'inventory' table to remove obsolete columns.
ALTER TABLE public.inventory DROP COLUMN IF EXISTS on_order_quantity;
ALTER TABLE public.inventory DROP COLUMN IF EXISTS landed_cost;
ALTER TABLE public.inventory DROP COLUMN IF EXISTS location_id;
ALTER TABLE public.inventory DROP COLUMN IF EXISTS conflict_status;
ALTER TABLE public.inventory DROP COLUMN IF EXISTS last_external_sync;
ALTER TABLE public.inventory DROP COLUMN IF EXISTS manual_override;
ALTER TABLE public.inventory DROP COLUMN IF EXISTS expiration_date;
ALTER TABLE public.inventory DROP COLUMN IF EXISTS lot_number;
ALTER TABLE public.inventory ADD COLUMN IF NOT EXISTS supplier_id uuid;


-- Step 6: Alter the 'customers' table to simplify it.
ALTER TABLE public.customers DROP COLUMN IF EXISTS platform;
ALTER TABLE public.customers DROP COLUMN IF EXISTS external_id;
ALTER TABLE public.customers DROP COLUMN IF EXISTS status;


-- Step 7: Alter the 'sales' table to simplify it.
ALTER TABLE public.sales DROP COLUMN IF EXISTS created_by;


-- Step 8: Create the new, simplified inventory_ledger table if it doesn't exist.
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    product_id uuid NOT NULL,
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    related_id uuid,
    notes text,
    CONSTRAINT inventory_ledger_pkey PRIMARY KEY (id),
    CONSTRAINT inventory_ledger_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT inventory_ledger_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.inventory(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_product_id ON public.inventory_ledger(product_id);


-- Step 9: Re-create and update necessary database functions for the new schema.
-- This function is updated to be simpler and use the new table structure.
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
SECURITY DEFINER
AS $$
DECLARE
    new_sale record;
    item record;
    total_sale_amount numeric := 0;
    inv_record record;
    ledger_entries jsonb := '[]'::jsonb;
BEGIN
    -- Calculate total sale amount
    FOR item IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(sku text, quantity int, unit_price numeric, cost_at_time numeric)
    LOOP
        total_sale_amount := total_sale_amount + (item.quantity * item.unit_price);
    END LOOP;

    -- Insert the new sale record
    INSERT INTO public.sales (company_id, sale_number, customer_name, customer_email, total_amount, payment_method, notes, external_id)
    VALUES (p_company_id, 'SALE-' || nextval('sales_sale_number_seq'), p_customer_name, p_customer_email, total_sale_amount, p_payment_method, p_notes, p_external_id)
    RETURNING * INTO new_sale;

    -- Process each sale item to update inventory and create ledger entries
    FOR item IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(sku text, product_id uuid, product_name text, quantity int, unit_price numeric, cost_at_time numeric)
    LOOP
        -- Find the inventory record by SKU
        SELECT id, quantity INTO inv_record FROM public.inventory WHERE company_id = p_company_id AND sku = item.sku;

        IF inv_record IS NULL THEN
            RAISE WARNING 'Product with SKU % not found in inventory for company %', item.sku, p_company_id;
            CONTINUE;
        END IF;
        
        -- Update inventory quantity
        UPDATE public.inventory
        SET
            quantity = quantity - item.quantity,
            last_sold_date = now()
        WHERE id = inv_record.id;
        
        -- Add to ledger entries
        ledger_entries := ledger_entries || jsonb_build_object(
            'company_id', p_company_id,
            'product_id', inv_record.id,
            'change_type', 'sale',
            'quantity_change', -item.quantity,
            'new_quantity', (inv_record.quantity - item.quantity),
            'related_id', new_sale.id,
            'notes', 'Sale #' || new_sale.sale_number
        );

        -- Insert sale item
        INSERT INTO public.sale_items (sale_id, company_id, sku, product_name, quantity, unit_price, cost_at_time)
        VALUES (new_sale.id, p_company_id, item.sku, item.product_name, item.quantity, item.unit_price, item.cost_at_time);
    END LOOP;
    
    -- Bulk insert ledger entries
    IF jsonb_array_length(ledger_entries) > 0 THEN
        INSERT INTO public.inventory_ledger (company_id, product_id, change_type, quantity_change, new_quantity, related_id, notes)
        SELECT
            (e->>'company_id')::uuid,
            (e->>'product_id')::uuid,
            e->>'change_type',
            (e->>'quantity_change')::int,
            (e->>'new_quantity')::int,
            (e->>'related_id')::uuid,
            e->>'notes'
        FROM jsonb_array_elements(ledger_entries) e;
    END IF;

    RETURN new_sale;
END;
$$;


-- This function is simplified to remove PO logic.
CREATE OR REPLACE FUNCTION public.get_unified_inventory(
    p_company_id uuid,
    p_query text DEFAULT NULL::text,
    p_category text DEFAULT NULL::text,
    p_supplier_id uuid DEFAULT NULL::uuid,
    p_product_id_filter uuid DEFAULT NULL::uuid,
    p_limit integer DEFAULT 50,
    p_offset integer DEFAULT 0
)
RETURNS json
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN (
        SELECT json_build_object(
            'items', COALESCE(json_agg(u), '[]'::json),
            'total_count', (SELECT count(*) FROM inventory WHERE company_id = p_company_id AND deleted_at IS NULL)
        )
        FROM (
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
            FROM inventory i
            LEFT JOIN suppliers s ON i.supplier_id = s.id
            WHERE i.company_id = p_company_id
            AND i.deleted_at IS NULL
            AND (p_query IS NULL OR (i.name ILIKE '%' || p_query || '%' OR i.sku ILIKE '%' || p_query || '%'))
            AND (p_category IS NULL OR i.category = p_category)
            AND (p_supplier_id IS NULL OR i.supplier_id = p_supplier_id)
            AND (p_product_id_filter IS NULL OR i.id = p_product_id_filter)
            ORDER BY i.name
            LIMIT p_limit
            OFFSET p_offset
        ) u
    );
END;
$$;


-- Final Step: Clean up foreign key constraints and re-apply them correctly.
-- This ensures the relationships between the remaining tables are solid.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.table_constraints WHERE constraint_name='inventory_supplier_id_fkey' AND table_name='inventory') THEN
        ALTER TABLE public.inventory DROP CONSTRAINT "inventory_supplier_id_fkey";
    END IF;
    
    ALTER TABLE public.inventory ADD CONSTRAINT "inventory_supplier_id_fkey" FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) ON DELETE SET NULL;
END;
$$;

-- Add a unique constraint on SKU per company for data integrity.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.table_constraints WHERE constraint_name='inventory_company_id_sku_key' AND table_name='inventory') THEN
         ALTER TABLE public.inventory ADD CONSTRAINT inventory_company_id_sku_key UNIQUE (company_id, sku);
    END IF;
END;
$$;


-- Re-create a simplified version of get_reorder_suggestions.
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
    unit_cost numeric,
    base_quantity integer
)
LANGUAGE sql
AS $$
    WITH sales_velocity AS (
      SELECT
        i.id as product_id,
        COALESCE(SUM(si.quantity) / p_fast_moving_days::decimal, 0) as daily_velocity
      FROM inventory i
      JOIN sale_items si ON i.sku = si.sku AND i.company_id = si.company_id
      JOIN sales s ON si.sale_id = s.id
      WHERE i.company_id = p_company_id
        AND s.created_at >= now() - (p_fast_moving_days || ' days')::interval
      GROUP BY i.id
    )
    SELECT
        i.id as product_id,
        i.sku,
        i.name as product_name,
        i.quantity as current_quantity,
        i.reorder_point,
        GREATEST(0, COALESCE(i.reorder_point, 0) + CEIL(sv.daily_velocity * COALESCE(s.default_lead_time_days, 7))::int - i.quantity) as suggested_reorder_quantity,
        s.name as supplier_name,
        s.id as supplier_id,
        i.cost as unit_cost,
        GREATEST(0, COALESCE(i.reorder_point, 0) - i.quantity) as base_quantity
    FROM inventory i
    LEFT JOIN suppliers s ON i.supplier_id = s.id
    LEFT JOIN sales_velocity sv ON i.id = sv.product_id
    WHERE i.company_id = p_company_id
      AND i.deleted_at IS NULL
      AND i.quantity < COALESCE(i.reorder_point, 0)
    ORDER BY (COALESCE(i.reorder_point, 0) - i.quantity) DESC;
$$;

-- Final cleanup of any lingering types from the old PO system.
DROP TYPE IF EXISTS public.purchase_order_item_input;

-- --- END OF SCRIPT ---
