-- InvoChat: Simplified Intelligence-Focused Database Schema Migration
-- This script transforms an existing database to the new, leaner schema.
-- It drops unnecessary tables and functions, simplifies others, and adds new intelligence-focused functions.

-- Step 1: Drop all functions that might depend on the tables we are about to remove.
-- This must be done first to avoid dependency errors.
DROP FUNCTION IF EXISTS public.create_purchase_order_and_update_inventory(uuid, uuid, text, date, date, text, numeric, jsonb);
DROP FUNCTION IF EXISTS public.create_purchase_order_and_update_inventory(uuid, uuid, uuid, text, date, date, text, jsonb);
DROP FUNCTION IF EXISTS public.delete_purchase_order(uuid, uuid);
DROP FUNCTION IF EXISTS public.delete_supplier_and_catalogs(uuid, uuid);
DROP FUNCTION IF EXISTS public.get_purchase_order_analytics(uuid);
DROP FUNCTION IF EXISTS public.get_purchase_order_details(uuid, uuid);
DROP FUNCTION IF EXISTS public.get_purchase_orders(uuid, text, integer, integer);
DROP FUNCTION IF EXISTS public.get_suppliers_with_performance(uuid);
DROP FUNCTION IF EXISTS public.get_unified_inventory(uuid, text, text, uuid, uuid, text, integer, integer);
DROP FUNCTION IF EXISTS public.receive_purchase_order_items(uuid, jsonb, uuid, uuid);
DROP FUNCTION IF EXISTS public.update_inventory_item_with_lock(uuid, text, integer, text, text, numeric, integer, numeric, text, uuid);
DROP FUNCTION IF EXISTS public.update_inventory_item_with_lock(uuid, text, integer, text, text, bigint, integer, bigint, text, uuid);
DROP FUNCTION IF EXISTS public.update_po_status(uuid, uuid);
DROP FUNCTION IF EXISTS public.update_purchase_order(uuid, uuid, uuid, text, text, date, date, text, jsonb);
DROP FUNCTION IF EXISTS public.validate_po_financials(uuid, bigint);
DROP FUNCTION IF EXISTS public.delete_location(uuid, uuid, uuid);

-- Step 2: Drop the unnecessary tables. CASCADE will handle dependent objects like indexes.
DROP TABLE IF EXISTS public.purchase_order_items CASCADE;
DROP TABLE IF EXISTS public.purchase_orders CASCADE;
DROP TABLE IF EXISTS public.locations CASCADE;
DROP TABLE IF EXISTS public.vendors CASCADE;
DROP TABLE IF EXISTS public.supplier_catalogs CASCADE;
DROP TABLE IF EXISTS public.reorder_rules CASCADE;

-- Step 3: Simplify the remaining tables by dropping columns.
ALTER TABLE public.inventory
DROP COLUMN IF EXISTS on_order_quantity,
DROP COLUMN IF EXISTS landed_cost,
DROP COLUMN IF EXISTS expiration_date,
DROP COLUMN IF EXISTS lot_number,
DROP COLUMN IF EXISTS location_id;

-- Ensure sku and company_id are unique together
ALTER TABLE public.inventory
ADD CONSTRAINT inventory_company_id_sku_key UNIQUE (company_id, sku);

-- Step 4: Drop the old inventory ledger and create the new, simpler one.
DROP TABLE IF EXISTS public.inventory_ledger CASCADE;
CREATE TABLE public.inventory_ledger (
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

CREATE INDEX idx_inventory_ledger_product_id ON public.inventory_ledger(product_id);
CREATE INDEX idx_inventory_ledger_company_sku_date ON public.inventory_ledger(company_id, created_at DESC);


-- Step 5: Re-create and update necessary functions for the new schema.

-- Function to record a sale and update inventory atomically
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
    v_sale_id uuid;
    v_total_amount numeric := 0;
    v_item record;
    v_product_id uuid;
    v_new_quantity int;
    v_current_quantity int;
    new_sale record;
BEGIN
    -- Calculate total amount
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(sku text, quantity int, unit_price numeric)
    LOOP
        v_total_amount := v_total_amount + (v_item.quantity * v_item.unit_price);
    END LOOP;

    -- Insert the sale
    INSERT INTO public.sales (company_id, customer_name, customer_email, total_amount, payment_method, notes, external_id)
    VALUES (p_company_id, p_customer_name, p_customer_email, v_total_amount, p_payment_method, p_notes, p_external_id)
    RETURNING * INTO new_sale;
    
    v_sale_id := new_sale.id;

    -- Insert sale items and update inventory
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(sku text, product_name text, quantity int, unit_price numeric, cost_at_time numeric)
    LOOP
        -- Find the product_id from the SKU
        SELECT id INTO v_product_id FROM public.inventory WHERE sku = v_item.sku AND company_id = p_company_id;

        IF v_product_id IS NULL THEN
            RAISE EXCEPTION 'Product with SKU % not found', v_item.sku;
        END IF;

        INSERT INTO public.sale_items (sale_id, company_id, sku, product_name, quantity, unit_price, cost_at_time)
        VALUES (v_sale_id, p_company_id, v_item.sku, v_item.product_name, v_item.quantity, v_item.unit_price, v_item.cost_at_time);

        -- Update inventory quantity
        UPDATE public.inventory
        SET
            quantity = quantity - v_item.quantity,
            last_sold_date = CURRENT_DATE,
            updated_at = now()
        WHERE id = v_product_id
        RETURNING quantity INTO v_new_quantity;
        
        -- Get old quantity for ledger
        v_current_quantity := v_new_quantity + v_item.quantity;

        -- Log the change in the ledger
        INSERT INTO public.inventory_ledger (company_id, product_id, change_type, quantity_change, new_quantity, related_id, notes)
        VALUES (p_company_id, v_product_id, 'sale', -v_item.quantity, v_new_quantity, v_sale_id, 'Sale #' || new_sale.sale_number);

    END LOOP;

    RETURN new_sale;
END;
$$;


-- Simplified reorder suggestions function
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
STABLE
AS $$
WITH sales_velocity AS (
    SELECT
        product_id,
        (SUM(quantity) / p_fast_moving_days::decimal) AS daily_velocity
    FROM sale_items si
    JOIN sales s ON si.sale_id = s.id
    WHERE s.company_id = p_company_id
      AND s.created_at >= now() - (p_fast_moving_days || ' days')::interval
    GROUP BY product_id
)
SELECT
    i.id as product_id,
    i.sku,
    i.name as product_name,
    i.quantity as current_quantity,
    i.reorder_point,
    GREATEST(i.reorder_quantity, 1) as suggested_reorder_quantity,
    s.name as supplier_name,
    s.id as supplier_id,
    i.cost as unit_cost,
    GREATEST(i.reorder_quantity, 1) as base_quantity
FROM inventory i
LEFT JOIN sales_velocity sv ON i.id = sv.product_id
LEFT JOIN suppliers s ON i.supplier_id = s.id
WHERE i.company_id = p_company_id
  AND i.deleted_at IS NULL
  AND i.quantity <= i.reorder_point;
$$;


-- Simplified business profile function
CREATE OR REPLACE FUNCTION public.get_business_profile(p_company_id uuid)
RETURNS TABLE(monthly_revenue bigint, risk_tolerance text)
LANGUAGE sql
STABLE
AS $$
  SELECT
    (SUM(total_amount) / 100)::bigint as monthly_revenue,
    'medium'::text as risk_tolerance
  FROM sales
  WHERE company_id = p_company_id AND created_at >= now() - interval '30 days';
$$;


-- Simplified unified inventory view
CREATE OR REPLACE FUNCTION public.get_unified_inventory(
    p_company_id uuid,
    p_query text DEFAULT NULL::text,
    p_category text DEFAULT NULL::text,
    p_supplier_id uuid DEFAULT NULL::uuid,
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
        SELECT i.*, s.name as supplier_name
        FROM public.inventory i
        LEFT JOIN public.suppliers s ON i.supplier_id = s.id
        WHERE i.company_id = p_company_id
          AND i.deleted_at IS NULL
          AND (p_query IS NULL OR (i.name ILIKE '%' || p_query || '%' OR i.sku ILIKE '%' || p_query || '%'))
          AND (p_category IS NULL OR i.category = p_category)
          AND (p_supplier_id IS NULL OR i.supplier_id = p_supplier_id)
          AND (p_product_id_filter IS NULL OR i.id = p_product_id_filter)
    )
    SELECT
        (SELECT json_agg(fi.*) FROM (
            SELECT
                id as product_id,
                sku,
                name as product_name,
                category,
                quantity,
                cost,
                price,
                (quantity * cost) as total_value,
                reorder_point,
                supplier_name,
                supplier_id
            FROM filtered_inventory
            ORDER BY name
            LIMIT p_limit
            OFFSET p_offset
        ) AS fi) as items,
        (SELECT COUNT(*) FROM filtered_inventory) as total_count;
END;
$$;


GRANT EXECUTE ON FUNCTION public.record_sale_transaction(uuid, jsonb, text, text, text, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_reorder_suggestions(uuid, integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_business_profile(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_unified_inventory(uuid, text, text, uuid, uuid, integer, integer) TO authenticated, service_role;

ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Enable all access for users based on company_id" ON public.inventory;
CREATE POLICY "Enable all access for users based on company_id" ON public.inventory FOR ALL USING (auth.uid() IN (SELECT user_id FROM company_users WHERE company_id = inventory.company_id));

DROP POLICY IF EXISTS "Enable all access for users based on company_id" ON public.sales;
CREATE POLICY "Enable all access for users based on company_id" ON public.sales FOR ALL USING (auth.uid() IN (SELECT user_id FROM company_users WHERE company_id = sales.company_id));

DROP POLICY IF EXISTS "Enable all access for users based on company_id" ON public.customers;
CREATE POLICY "Enable all access for users based on company_id" ON public.customers FOR ALL USING (auth.uid() IN (SELECT user_id FROM company_users WHERE company_id = customers.company_id));

DROP POLICY IF EXISTS "Enable all access for users based on company_id" ON public.suppliers;
CREATE POLICY "Enable all access for users based on company_id" ON public.suppliers FOR ALL USING (auth.uid() IN (SELECT user_id FROM company_users WHERE company_id = suppliers.company_id));

DROP POLICY IF EXISTS "Enable all access for users based on company_id" ON public.inventory_ledger;
CREATE POLICY "Enable all access for users based on company_id" ON public.inventory_ledger FOR ALL USING (auth.uid() IN (SELECT user_id FROM company_users WHERE company_id = inventory_ledger.company_id));


-- Final cleanup of any other functions that may have been missed
DROP FUNCTION IF EXISTS public.create_purchase_order_and_update_inventory(uuid, uuid, text, date, date, text, numeric, jsonb);
DROP FUNCTION IF EXISTS public.create_purchase_order_and_update_inventory(uuid, uuid, uuid, text, date, date, text, jsonb);

COMMIT;
