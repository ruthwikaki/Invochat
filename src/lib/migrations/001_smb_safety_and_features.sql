-- MIGRATION SCRIPT: SMB Safety & Features
-- This script is designed to be run ONCE on the existing database schema.
-- It adds new columns and replaces functions with safer, more robust versions.

BEGIN;

-- 1. Add columns for billing/subscription management to the company_settings table.
ALTER TABLE public.company_settings
ADD COLUMN IF NOT EXISTS subscription_status text DEFAULT 'trial',
ADD COLUMN IF NOT EXISTS subscription_plan text DEFAULT 'starter',
ADD COLUMN IF NOT EXISTS subscription_expires_at timestamptz,
ADD COLUMN IF NOT EXISTS stripe_customer_id text,
ADD COLUMN IF NOT EXISTS stripe_subscription_id text;

-- 2. Add the columns for improved inventory reconciliation and tracking.
ALTER TABLE public.inventory
ADD COLUMN IF NOT EXISTS conflict_status text,
ADD COLUMN IF NOT EXISTS last_external_sync timestamptz,
ADD COLUMN IF NOT EXISTS manual_override boolean DEFAULT false;

-- 3. Add the columns for expiration and lot tracking.
ALTER TABLE public.inventory
ADD COLUMN IF NOT EXISTS expiration_date date,
ADD COLUMN IF NOT EXISTS lot_number text;

-- Add an index for expiration date to speed up queries for soon-to-expire stock.
CREATE INDEX IF NOT EXISTS idx_inventory_expiration ON public.inventory(company_id, expiration_date) 
WHERE expiration_date IS NOT NULL;

-- Add CHECK constraint to prevent negative inventory
ALTER TABLE public.inventory
ADD CONSTRAINT check_inventory_quantity_non_negative CHECK (quantity >= 0);

-- 4. Add columns to purchase_orders for better payment tracking.
ALTER TABLE public.purchase_orders
ADD COLUMN IF NOT EXISTS payment_terms_days integer,
ADD COLUMN IF NOT EXISTS payment_due_date date,
ADD COLUMN IF NOT EXISTS amount_paid bigint DEFAULT 0; -- Stored in cents

-- 5. Function to securely validate PO financials before creation or update.
-- This acts as a centralized circuit breaker.
CREATE OR REPLACE FUNCTION public.validate_po_financials(
    p_company_id uuid,
    p_po_value bigint
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    profile record;
BEGIN
    SELECT * INTO profile FROM public.get_business_profile(p_company_id);
    
    -- Check against single order limit (e.g., 15% of monthly revenue)
    IF p_po_value > (profile.monthly_revenue * 0.15) THEN
        RAISE EXCEPTION 'Financial Risk: Purchase order value of % exceeds the safety limit of 15%% of monthly revenue.', p_po_value;
    END IF;

    -- Check against total exposure limit (e.g., 35% of monthly revenue)
    IF (profile.outstanding_po_value + p_po_value) > (profile.monthly_revenue * 0.35) THEN
        RAISE EXCEPTION 'Financial Risk: Total outstanding PO value including this order would exceed 35%% of monthly revenue.';
    END IF;
END;
$$;

-- 6. Modify the delete location function to require transferring inventory.
-- This prevents "lost" inventory.
DROP FUNCTION IF EXISTS public.delete_location_and_unassign_inventory(uuid, uuid);
CREATE OR REPLACE FUNCTION public.delete_location(
    p_location_id uuid,
    p_company_id uuid,
    p_transfer_to_location_id uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Ensure the user is not trying to transfer to the same location being deleted
    IF p_location_id = p_transfer_to_location_id THEN
        RAISE EXCEPTION 'Cannot transfer inventory to the same location being deleted.';
    END IF;

    -- Check if the target location exists and belongs to the same company
    IF NOT EXISTS (
        SELECT 1 FROM public.locations 
        WHERE id = p_transfer_to_location_id AND company_id = p_company_id
    ) THEN
        RAISE EXCEPTION 'Target transfer location not found or does not belong to the company.';
    END IF;

    -- Transfer inventory to the new location within a transaction
    UPDATE public.inventory
    SET location_id = p_transfer_to_location_id
    WHERE location_id = p_location_id AND company_id = p_company_id;

    -- Delete the old location
    DELETE FROM public.locations WHERE id = p_location_id AND company_id = p_company_id;

    -- Log the action
    INSERT INTO public.audit_log (company_id, action, details)
    VALUES (p_company_id, 'location_deleted_with_transfer', jsonb_build_object('from_location_id', p_location_id, 'to_location_id', p_transfer_to_location_id));
END;
$$;

-- 7. Update the purchase order creation function to include the financial check and audit logging.
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
) RETURNS public.purchase_orders
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  new_po public.purchase_orders;
  item_record record;
  v_total_amount bigint := 0;
BEGIN
  -- Calculate total amount first for validation
  FOR item_record IN SELECT * FROM jsonb_to_recordset(p_items) AS x(unit_cost bigint, quantity_ordered int)
  LOOP
    v_total_amount := v_total_amount + (item_record.quantity_ordered * item_record.unit_cost);
  END LOOP;

  -- Perform financial circuit breaker check
  PERFORM public.validate_po_financials(p_company_id, v_total_amount);

  -- Proceed with PO creation
  INSERT INTO public.purchase_orders
    (company_id, supplier_id, po_number, status, order_date, expected_date, notes, total_amount, approved_by)
  VALUES
    (p_company_id, p_supplier_id, p_po_number, 'draft', p_order_date, p_expected_date, p_notes, v_total_amount, p_user_id)
  RETURNING * INTO new_po;

  -- Add audit log entry
  INSERT INTO public.audit_log (user_id, company_id, action, details)
  VALUES (p_user_id, p_company_id, 'purchase_order_created', jsonb_build_object('po_id', new_po.id, 'total_amount', v_total_amount));

  FOR item_record IN SELECT * FROM jsonb_to_recordset(p_items) AS x(sku text, quantity_ordered int, unit_cost bigint)
  LOOP
    INSERT INTO public.purchase_order_items
      (po_id, sku, quantity_ordered, unit_cost)
    VALUES
      (new_po.id, item_record.sku, item_record.quantity_ordered, item_record.unit_cost);

    UPDATE public.inventory
    SET on_order_quantity = on_order_quantity + item_record.quantity_ordered
    WHERE sku = item_record.sku AND company_id = p_company_id;
  END LOOP;

  RETURN new_po;
END;
$$;

-- 8. Add user_id to receive PO function for audit logging and improve concurrency.
DROP FUNCTION IF EXISTS public.receive_purchase_order_items(uuid, jsonb, uuid);
CREATE OR REPLACE FUNCTION public.receive_purchase_order_items(
    p_po_id uuid, 
    p_items_to_receive jsonb, 
    p_company_id uuid,
    p_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    item record;
    v_product_id uuid;
    v_ordered_quantity integer;
    v_already_received integer;
BEGIN
    FOR item IN SELECT * FROM jsonb_to_recordset(p_items_to_receive) AS x(sku text, quantity_to_receive int)
    LOOP
        IF item.quantity_to_receive > 0 THEN
            -- Lock the PO item row to prevent concurrent receiving
            SELECT po_item.quantity_ordered, po_item.quantity_received INTO v_ordered_quantity, v_already_received
            FROM public.purchase_order_items po_item
            WHERE po_item.po_id = p_po_id AND po_item.sku = item.sku
            FOR UPDATE;

            -- Find the corresponding product_id
            SELECT id INTO v_product_id FROM public.products WHERE sku = item.sku AND company_id = p_company_id;

            IF v_product_id IS NULL THEN
                RAISE EXCEPTION 'Product with SKU % not found for this company.', item.sku;
            END IF;

            IF v_already_received + item.quantity_to_receive > v_ordered_quantity THEN
                RAISE EXCEPTION 'Cannot receive more items than were ordered for SKU %.', item.sku;
            END IF;

            -- Update inventory and ledger
            UPDATE public.inventory
            SET quantity = quantity + item.quantity_to_receive,
                on_order_quantity = on_order_quantity - item.quantity_to_receive
            WHERE sku = item.sku AND company_id = p_company_id;

            INSERT INTO public.inventory_ledger(company_id, product_id, sku, created_by, change_type, quantity_change, related_id)
            VALUES (p_company_id, v_product_id, item.sku, p_user_id, 'purchase_order_received', item.quantity_to_receive, p_po_id);

            -- Update PO item received quantity
            UPDATE public.purchase_order_items
            SET quantity_received = quantity_received + item.quantity_to_receive
            WHERE po_id = p_po_id AND sku = item.sku;

            -- Add audit log entry
            INSERT INTO public.audit_log (user_id, company_id, action, details)
            VALUES (p_user_id, p_company_id, 'po_items_received', jsonb_build_object('po_id', p_po_id, 'sku', item.sku, 'quantity', item.quantity_to_receive));
        END IF;
    END LOOP;

    -- Update the overall PO status
    PERFORM public.update_po_status(p_po_id, p_company_id);
END;
$$;

-- This is a helper function to automatically update the PO status to 'partial' or 'received'
CREATE OR REPLACE FUNCTION public.update_po_status(p_po_id uuid, p_company_id uuid)
RETURNS void AS $$
DECLARE
    total_ordered integer;
    total_received integer;
BEGIN
    SELECT 
        SUM(quantity_ordered), 
        SUM(quantity_received)
    INTO 
        total_ordered, 
        total_received
    FROM public.purchase_order_items
    WHERE po_id = p_po_id;

    IF total_received >= total_ordered THEN
        UPDATE public.purchase_orders SET status = 'received' WHERE id = p_po_id AND company_id = p_company_id;
    ELSIF total_received > 0 THEN
        UPDATE public.purchase_orders SET status = 'partial' WHERE id = p_po_id AND company_id = p_company_id;
    END IF;
END;
$$ LANGUAGE plpgsql;

COMMIT;
