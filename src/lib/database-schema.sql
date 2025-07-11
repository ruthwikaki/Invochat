
-- Add the columns for billing/subscription management to the company_settings table.
ALTER TABLE public.company_settings
ADD COLUMN IF NOT EXISTS subscription_status text DEFAULT 'trial',
ADD COLUMN IF NOT EXISTS subscription_plan text DEFAULT 'starter',
ADD COLUMN IF NOT EXISTS subscription_expires_at timestamptz,
ADD COLUMN IF NOT EXISTS stripe_customer_id text,
ADD COLUMN IF NOT EXISTS stripe_subscription_id text,
ADD COLUMN IF NOT EXISTS usage_limits jsonb,
ADD COLUMN IF NOT EXISTS current_usage jsonb;

-- Add the columns for improved inventory reconciliation and tracking.
ALTER TABLE public.inventory
ADD COLUMN IF NOT EXISTS conflict_status text,
ADD COLUMN IF NOT EXISTS last_external_sync timestamptz,
ADD COLUMN IF NOT EXISTS manual_override boolean DEFAULT false;

-- Add the columns for expiration and lot tracking, which are critical for many SMBs.
ALTER TABLE public.inventory
ADD COLUMN IF NOT EXISTS expiration_date date,
ADD COLUMN IF NOT EXISTS lot_number text;

-- Add an index for expiration date to speed up queries for soon-to-expire stock.
CREATE INDEX IF NOT EXISTS idx_inventory_expiration ON public.inventory(company_id, expiration_date) 
WHERE expiration_date IS NOT NULL;

-- Add columns to purchase_orders for better payment tracking.
ALTER TABLE public.purchase_orders
ADD COLUMN IF NOT EXISTS payment_terms_days integer,
ADD COLUMN IF NOT EXISTS payment_due_date date,
ADD COLUMN IF NOT EXISTS amount_paid bigint DEFAULT 0;

-- Function to securely validate PO financials before creation or update.
-- This acts as a centralized circuit breaker.
CREATE OR REPLACE FUNCTION public.validate_po_financials(
    p_company_id uuid,
    p_po_value bigint
) RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    profile record;
BEGIN
    SELECT * INTO profile FROM public.get_business_profile(p_company_id);
    
    IF p_po_value > (profile.monthly_revenue * 0.15) THEN
        RAISE EXCEPTION 'Financial Risk: Purchase order value exceeds 15%% of monthly revenue.';
    END IF;

    IF (profile.outstanding_po_value + p_po_value) > (profile.monthly_revenue * 0.35) THEN
        RAISE EXCEPTION 'Financial Risk: Total outstanding PO value exceeds 35%% of monthly revenue.';
    END IF;
END;
$$;

-- Modify the delete location function to require transferring inventory.
DROP FUNCTION IF EXISTS public.delete_location_and_unassign_inventory(uuid, uuid);
CREATE OR REPLACE FUNCTION public.delete_location_and_unassign_inventory(
    p_location_id uuid,
    p_company_id uuid,
    p_transfer_to_location_id uuid
) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    -- Check if the target location exists and belongs to the same company
    IF NOT EXISTS (
        SELECT 1 FROM public.locations 
        WHERE id = p_transfer_to_location_id AND company_id = p_company_id
    ) THEN
        RAISE EXCEPTION 'Target transfer location not found or does not belong to the company.';
    END IF;

    -- Transfer inventory to the new location
    UPDATE public.inventory
    SET location_id = p_transfer_to_location_id
    WHERE location_id = p_location_id AND company_id = p_company_id;

    -- Delete the old location
    DELETE FROM public.locations WHERE id = p_location_id AND company_id = p_company_id;
END;
$$;

-- Update the purchase order creation function to include the financial check.
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

-- Add user_id to receive PO function for audit logging
DROP FUNCTION IF EXISTS public.receive_purchase_order_items(uuid, jsonb, uuid);
CREATE OR REPLACE FUNCTION public.receive_purchase_order_items(
    p_po_id uuid, 
    p_items_to_receive jsonb, 
    p_company_id uuid,
    p_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    -- ... existing function body
BEGIN
    -- ... existing logic ...

    -- Add this inside the loop after a successful update
    INSERT INTO public.audit_log (user_id, company_id, action, details)
    VALUES (p_user_id, p_company_id, 'po_items_received', jsonb_build_object('po_id', p_po_id, 'sku', item.sku, 'quantity', item.quantity_to_receive));
    
    -- ... rest of the existing logic ...
END;
$$;


