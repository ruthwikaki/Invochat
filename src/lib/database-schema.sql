-- Add a product_id column to sale_items
ALTER TABLE public.sale_items
ADD COLUMN product_id UUID REFERENCES public.inventory(id);

-- Backfill product_id for existing sale_items based on sku
UPDATE
    public.sale_items si
SET
    product_id = i.id
FROM
    public.inventory i
WHERE
    si.sku = i.sku
    AND si.company_id = i.company_id
    AND si.product_id IS NULL;

-- Make the product_id column non-nullable after backfilling
ALTER TABLE public.sale_items
ALTER COLUMN product_id
SET NOT NULL;

-- Drop the now-redundant sku and product_name columns
ALTER TABLE public.sale_items
DROP COLUMN sku,
DROP COLUMN product_name;

-- Drop the old function if it exists
DROP FUNCTION IF EXISTS public.record_sale_transaction(uuid, uuid, jsonb[], text, text, text, text, text);

-- Recreate the function to use product_id
CREATE OR REPLACE FUNCTION public.record_sale_transaction(
    p_company_id uuid,
    p_user_id uuid,
    p_sale_items jsonb,
    p_customer_name text,
    p_customer_email text,
    p_payment_method text,
    p_notes text,
    p_external_id text
)
RETURNS public.sales
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_sale_id uuid;
    v_total_amount numeric := 0;
    v_item RECORD;
    v_inventory_item RECORD;
    v_customer_id uuid;
    v_new_sale_number text;
BEGIN
    -- Validate that all product_ids exist for the given company
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(product_id uuid, quantity int, unit_price numeric)
    LOOP
        SELECT * INTO v_inventory_item FROM public.inventory WHERE id = v_item.product_id AND company_id = p_company_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Product with ID % not found for this company', v_item.product_id;
        END IF;
    END LOOP;

    -- Upsert customer and get their ID
    IF p_customer_email IS NOT NULL AND p_customer_email <> '' THEN
        INSERT INTO public.customers (company_id, customer_name, email)
        VALUES (p_company_id, COALESCE(p_customer_name, p_customer_email), p_customer_email)
        ON CONFLICT (company_id, email) DO UPDATE SET customer_name = COALESCE(p_customer_name, p_customer_email)
        RETURNING id INTO v_customer_id;
    END IF;

    -- Calculate total amount from sale items
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(product_id uuid, quantity int, unit_price numeric)
    LOOP
        v_total_amount := v_total_amount + (v_item.quantity * v_item.unit_price);
    END LOOP;

    -- Generate a new sale number
    SELECT COALESCE(MAX(SUBSTRING(sale_number, 4)::integer), 0) + 1 INTO v_new_sale_number
    FROM public.sales
    WHERE company_id = p_company_id;

    -- Insert the main sale record
    INSERT INTO public.sales (company_id, sale_number, customer_id, total_amount, payment_method, notes, external_id)
    VALUES (p_company_id, 'SALE-' || v_new_sale_number, v_customer_id, v_total_amount, p_payment_method, p_notes, p_external_id)
    RETURNING id INTO v_sale_id;

    -- Insert sale items and update inventory
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(product_id uuid, quantity int, unit_price numeric)
    LOOP
        -- Get current cost for the ledger
        SELECT cost INTO v_inventory_item FROM public.inventory WHERE id = v_item.product_id;

        INSERT INTO public.sale_items (sale_id, company_id, product_id, quantity, unit_price, cost_at_time)
        VALUES (v_sale_id, p_company_id, v_item.product_id, v_item.quantity, v_item.unit_price, v_inventory_item.cost);

        -- This will trigger the update_inventory_from_sale function
    END LOOP;

    -- Return the newly created sale
    RETURN (SELECT * FROM public.sales WHERE id = v_sale_id);
END;
$$;
