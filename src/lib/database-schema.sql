--
-- Edge Case Fix: Negative Inventory Prevention
-- This script updates the core order processing function to prevent inventory from dropping below zero.
--

-- Drop the existing function to ensure a clean update
DROP FUNCTION IF EXISTS public.record_order_from_platform(p_company_id uuid, p_order_payload jsonb, p_platform text);

-- Recreate the function with the negative inventory check
CREATE OR REPLACE FUNCTION public.record_order_from_platform(
    p_company_id uuid,
    p_order_payload jsonb,
    p_platform text
)
RETURNS text AS $$
DECLARE
    v_order_id uuid;
    v_customer_id uuid;
    v_line_item jsonb;
    v_variant_id uuid;
    v_current_stock integer;
    v_quantity_to_decrement integer;
BEGIN
    -- 1. Find or Create Customer
    SELECT id INTO v_customer_id
    FROM customers
    WHERE email = (p_order_payload->>'customer'->>'email')
      AND company_id = p_company_id;

    IF v_customer_id IS NULL AND p_order_payload->'customer'->>'email' IS NOT NULL THEN
        INSERT INTO customers (company_id, email, name)
        VALUES (
            p_company_id,
            p_order_payload->'customer'->>'email',
            COALESCE(
                p_order_payload->'customer'->>'first_name' || ' ' || p_order_payload->'customer'->>'last_name',
                p_order_payload->'customer'->>'username'
            )
        )
        RETURNING id INTO v_customer_id;
    END IF;

    -- 2. Create Order
    INSERT INTO orders (
        company_id,
        external_order_id,
        order_number,
        customer_id,
        total_amount,
        created_at,
        source_platform
    )
    VALUES (
        p_company_id,
        p_order_payload->>'id',
        p_order_payload->>'number',
        v_customer_id,
        (p_order_payload->>'total')::numeric * 100,
        (p_order_payload->>'date_created_gmt')::timestamptz,
        p_platform
    )
    RETURNING id INTO v_order_id;

    -- 3. Loop through line items to check stock and then create them
    FOR v_line_item IN SELECT * FROM jsonb_array_elements(p_order_payload->'line_items')
    LOOP
        -- Find variant by SKU
        SELECT id INTO v_variant_id
        FROM product_variants
        WHERE sku = v_line_item->>'sku' AND company_id = p_company_id;

        IF v_variant_id IS NOT NULL THEN
            -- Get quantity to decrement
            v_quantity_to_decrement := (v_line_item->>'quantity')::integer;

            -- 🔥 CRITICAL: Negative Inventory Check
            -- Lock the row and get current stock
            SELECT inventory_quantity INTO v_current_stock
            FROM product_variants
            WHERE id = v_variant_id FOR UPDATE;

            -- Check if there is sufficient stock
            IF v_current_stock < v_quantity_to_decrement THEN
                RAISE EXCEPTION 'Insufficient stock for SKU % (variant_id: %). Available: %, Required: %',
                    v_line_item->>'sku', v_variant_id, v_current_stock, v_quantity_to_decrement;
            END IF;

            -- Insert the line item
            INSERT INTO order_line_items (
                order_id,
                company_id,
                variant_id,
                quantity,
                price
            )
            VALUES (
                v_order_id,
                p_company_id,
                v_variant_id,
                v_quantity_to_decrement,
                (v_line_item->>'price')::numeric * 100
            );

            -- Decrement stock and create ledger entry
            -- This is now safe because of the check above.
            UPDATE product_variants
            SET inventory_quantity = inventory_quantity - v_quantity_to_decrement
            WHERE id = v_variant_id;
            
            INSERT INTO inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes)
            VALUES (p_company_id, v_variant_id, 'sale', -v_quantity_to_decrement, v_current_stock - v_quantity_to_decrement, v_order_id, 'Order #' || p_order_payload->>'number');

        ELSE
             -- Log a warning or handle cases where the SKU is not found
            RAISE WARNING 'SKU not found: % for order #%', v_line_item->>'sku', p_order_payload->>'number';
        END IF;
    END LOOP;

    RETURN v_order_id;
END;
$$ LANGUAGE plpgsql;
