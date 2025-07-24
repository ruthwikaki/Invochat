-- This script updates a single function to prevent negative inventory.
-- It is safe to run on an existing database.

-- Drop the existing function if it exists
DROP FUNCTION IF EXISTS public.decrement_inventory_for_order(p_order_id uuid);

-- Create the function with negative inventory prevention
CREATE OR REPLACE FUNCTION public.decrement_inventory_for_order(p_order_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    line_item RECORD;
    variant_stock INT;
BEGIN
    -- Loop through each line item in the specified order
    FOR line_item IN
        SELECT oli.variant_id, oli.quantity, pv.sku
        FROM public.order_line_items oli
        JOIN public.product_variants pv ON oli.variant_id = pv.id
        WHERE oli.order_id = p_order_id
    LOOP
        -- Lock the row and check current stock
        SELECT inventory_quantity INTO variant_stock
        FROM public.product_variants
        WHERE id = line_item.variant_id
        FOR UPDATE;

        -- Check for sufficient stock BEFORE decrementing
        IF variant_stock < line_item.quantity THEN
            RAISE EXCEPTION 'Insufficient stock for SKU %: Tried to sell %, but only % available.', 
                            line_item.sku, line_item.quantity, variant_stock;
        END IF;

        -- Decrement the inventory quantity for the variant
        UPDATE public.product_variants
        SET inventory_quantity = inventory_quantity - line_item.quantity
        WHERE id = line_item.variant_id;

        -- Create a corresponding entry in the inventory ledger
        INSERT INTO public.inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes)
        SELECT
            pv.company_id,
            line_item.variant_id,
            'sale',
            -line_item.quantity,
            pv.inventory_quantity - line_item.quantity,
            p_order_id,
            'Sale from Order #' || o.order_number
        FROM public.product_variants pv
        JOIN public.orders o ON o.id = p_order_id
        WHERE pv.id = line_item.variant_id;

    END LOOP;
END;
$$;

COMMENT ON FUNCTION public.decrement_inventory_for_order(p_order_id uuid) IS 'Decrements inventory for all items in an order and records the change in the ledger, with a check to prevent negative inventory.';
