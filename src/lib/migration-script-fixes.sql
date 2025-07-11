-- MIGRATION SCRIPT TO APPLY CRITICAL BUSINESS LOGIC FIXES
-- Run this script on your existing database to apply the updates.
-- Do NOT run this on a fresh database; use database-schema.sql for that.

BEGIN;

-- FIX 1: Add Expiration & Lot Tracking to Inventory
ALTER TABLE public.inventory
    ADD COLUMN IF NOT EXISTS expiration_date DATE,
    ADD COLUMN IF NOT EXISTS lot_number TEXT,
    ADD COLUMN IF NOT EXISTS conflict_status TEXT,
    ADD COLUMN IF NOT EXISTS last_external_sync TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS manual_override BOOLEAN DEFAULT FALSE;

-- Create an index for querying soon-to-expire products
CREATE INDEX IF NOT EXISTS idx_inventory_expiration ON public.inventory(company_id, expiration_date)
WHERE expiration_date IS NOT NULL;

-- FIX 2: Add Payment Tracking to Purchase Orders
ALTER TABLE public.purchase_orders
    ADD COLUMN IF NOT EXISTS payment_terms_days INTEGER,
    ADD COLUMN IF NOT EXISTS payment_due_date DATE,
    ADD COLUMN IF NOT EXISTS amount_paid BIGINT DEFAULT 0;

-- FIX 3: Add user_id for better audit trails where missing
ALTER TABLE public.inventory_ledger
    ADD COLUMN IF NOT EXISTS user_id uuid REFERENCES auth.users(id);

-- FIX 4: Centralize and Enforce Financial Circuit Breakers
-- This function will be called by all other PO functions.
CREATE OR REPLACE FUNCTION public.validate_po_financials(
    p_company_id uuid,
    p_po_value bigint
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_monthly_revenue bigint;
    v_outstanding_po_value bigint;
    v_max_single_order_percent numeric;
    v_max_total_exposure_percent numeric;
BEGIN
    -- Get business profile metrics
    SELECT monthly_revenue, outstanding_po_value
    INTO v_monthly_revenue, v_outstanding_po_value
    FROM public.get_business_profile(p_company_id);

    -- In a real app, these would come from company settings or a config file
    v_max_single_order_percent := 0.15;
    v_max_total_exposure_percent := 0.35;

    -- Check 1: Single PO value limit
    IF p_po_value > (v_monthly_revenue * v_max_single_order_percent) THEN
        RAISE EXCEPTION 'Purchase order value of % exceeds the single order safety limit of %%.', p_po_value, v_max_single_order_percent * 100;
    END IF;

    -- Check 2: Total exposure limit
    IF (v_outstanding_po_value + p_po_value) > (v_monthly_revenue * v_max_total_exposure_percent) THEN
        RAISE EXCEPTION 'This order would push total outstanding PO value to % which exceeds the cash flow exposure limit of %%.', (v_outstanding_po_value + p_po_value), v_max_total_exposure_percent * 100;
    END IF;
END;
$$;


-- FIX 5: Safer Location Deletion
-- The function now requires a new location to transfer inventory to, preventing "lost" inventory.
DROP FUNCTION IF EXISTS public.delete_location_and_unassign_inventory(uuid, uuid);
CREATE OR REPLACE FUNCTION public.delete_location_and_unassign_inventory(
    p_company_id uuid,
    p_location_id_to_delete uuid,
    p_new_location_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF p_location_id_to_delete = p_new_location_id THEN
        RAISE EXCEPTION 'New location cannot be the same as the one being deleted.';
    END IF;

    -- Transfer inventory to the new location
    UPDATE public.inventory
    SET location_id = p_new_location_id
    WHERE company_id = p_company_id AND location_id = p_location_id_to_delete;

    -- Now it's safe to delete the old location
    DELETE FROM public.locations
    WHERE id = p_location_id_to_delete AND company_id = p_company_id;
END;
$$;


-- FIX 6: Correct Cost of Goods Sold in Sale Items
-- This ensures profit reports are accurate by snapshotting cost at the time of sale.
ALTER TABLE public.sale_items
    ALTER COLUMN cost_at_time SET NOT NULL;

-- This function is now corrected to use cost_at_time
DROP FUNCTION IF EXISTS public.get_gross_margin_analysis(uuid);
CREATE OR REPLACE FUNCTION public.get_gross_margin_analysis(p_company_id uuid)
RETURNS TABLE(product_name text, sales_channel text, total_revenue bigint, total_cogs bigint, gross_margin_percentage numeric)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        si.product_name,
        s.payment_method AS sales_channel,
        SUM(si.quantity * si.unit_price) AS total_revenue,
        SUM(si.quantity * si.cost_at_time) AS total_cogs, -- CORRECT: Uses historical cost
        CASE
            WHEN SUM(si.quantity * si.unit_price) > 0 THEN
                (SUM(si.quantity * (si.unit_price - si.cost_at_time)) * 100) / SUM(si.quantity * si.unit_price)
            ELSE 0
        END AS gross_margin_percentage
    FROM public.sale_items AS si
    JOIN public.sales AS s ON si.sale_id = s.id
    WHERE s.company_id = p_company_id
      AND si.company_id = p_company_id
      AND si.cost_at_time IS NOT NULL
      AND s.created_at >= NOW() - INTERVAL '90 days'
    GROUP BY si.product_name, s.payment_method;
END;
$$;

-- FIX 7: Update `create_purchase_order_and_update_inventory` to use financial validation
-- NOTE: We are assuming `p_user_id` is now passed for audit purposes.
DROP FUNCTION IF EXISTS public.create_purchase_order_and_update_inventory(uuid, uuid, text, date, date, text, jsonb);
CREATE OR REPLACE FUNCTION public.create_purchase_order_and_update_inventory(
    p_company_id uuid,
    p_user_id uuid,
    p_supplier_id uuid,
    p_po_number text,
    p_order_date date,
    p_expected_date date,
    p_notes text,
    p_items jsonb
)
RETURNS public.purchase_orders
LANGUAGE plpgsql
AS $$
DECLARE
  new_po public.purchase_orders;
  item_record record;
  v_total_amount bigint := 0;
BEGIN
    FOR item_record IN SELECT * FROM jsonb_to_recordset(p_items) AS x(quantity_ordered int, unit_cost bigint) LOOP
        v_total_amount := v_total_amount + (item_record.quantity_ordered * item_record.unit_cost);
    END LOOP;

    -- ENFORCE FINANCIAL SAFEGUARD
    PERFORM public.validate_po_financials(p_company_id, v_total_amount);

    INSERT INTO public.purchase_orders
        (company_id, supplier_id, po_number, status, order_date, expected_date, notes, total_amount)
    VALUES
        (p_company_id, p_supplier_id, p_po_number, 'draft', p_order_date, p_expected_date, p_notes, v_total_amount)
    RETURNING * INTO new_po;

    -- Continue with item insertion and inventory update logic...
    FOR item_record IN SELECT * FROM jsonb_to_recordset(p_items) AS x(sku text, quantity_ordered int, unit_cost bigint) LOOP
        INSERT INTO public.purchase_order_items (po_id, sku, quantity_ordered, unit_cost)
        VALUES (new_po.id, item_record.sku, item_record.quantity_ordered, item_record.unit_cost);

        UPDATE public.inventory SET on_order_quantity = on_order_quantity + item_record.quantity_ordered
        WHERE sku = item_record.sku AND company_id = p_company_id;
    END LOOP;

    -- ADD TO AUDIT TRAIL
    INSERT INTO public.audit_log(user_id, company_id, action, details)
    VALUES (p_user_id, p_company_id, 'purchase_order_created', jsonb_build_object('po_id', new_po.id, 'po_number', new_po.po_number));

    RETURN new_po;
END;
$$;


-- FIX 8: Corrected `record_sale_transaction` to prevent negative inventory and record costs.
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
RETURNS public.sales
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    new_sale public.sales;
    item_record record;
    total_amount bigint := 0;
    current_inventory record;
BEGIN
    -- Calculate total amount first
    FOR item_record IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(quantity int, unit_price bigint) LOOP
        total_amount := total_amount + (item_record.quantity * item_record.unit_price);
    END LOOP;

    -- Create the sale record
    INSERT INTO public.sales (company_id, sale_number, customer_name, customer_email, total_amount, payment_method, notes, created_by, external_id)
    VALUES (p_company_id, 'SALE-' || nextval('sales_sale_number_seq'::regclass), p_customer_name, p_customer_email, total_amount, p_payment_method, p_notes, p_user_id, p_external_id)
    RETURNING * INTO new_sale;

    -- Process each item, lock inventory, insert sale_item, create ledger entry
    FOR item_record IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(sku text, product_name text, quantity int, unit_price bigint, location_id uuid)
    LOOP
        -- Lock the inventory row for this SKU and location to prevent race conditions
        SELECT * INTO current_inventory FROM public.inventory
        WHERE sku = item_record.sku AND company_id = p_company_id AND location_id = item_record.location_id AND deleted_at IS NULL
        FOR UPDATE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Inventory record not found for SKU: % at specified location.', item_record.sku;
        END IF;

        IF current_inventory.quantity < item_record.quantity THEN
            RAISE EXCEPTION 'Insufficient stock for SKU: %. Available: %, Requested: %', item_record.sku, current_inventory.quantity, item_record.quantity;
        END IF;

        -- Update inventory quantity
        UPDATE public.inventory
        SET quantity = quantity - item_record.quantity,
            last_sold_date = CURRENT_DATE,
            updated_at = NOW()
        WHERE id = current_inventory.id;

        -- Insert into sale_items with the cost at the time of sale
        INSERT INTO public.sale_items (sale_id, company_id, sku, product_name, quantity, unit_price, cost_at_time)
        VALUES (new_sale.id, p_company_id, item_record.sku, item_record.product_name, item_record.quantity, item_record.unit_price, current_inventory.cost);

        -- Create a ledger entry for the inventory change
        INSERT INTO public.inventory_ledger (company_id, sku, user_id, change_type, quantity_change, new_quantity, related_id, notes, location_id)
        VALUES (p_company_id, item_record.sku, p_user_id, 'sale', -item_record.quantity, current_inventory.quantity - item_record.quantity, new_sale.id, 'Sale #' || new_sale.sale_number, item_record.location_id);
    END LOOP;

    RETURN new_sale;
END;
$$;


COMMIT;
