-- THIS IS A MIGRATION SCRIPT TO UPDATE THE EXISTING DATABASE.
-- IT SIMPLIFIES THE SCHEMA BY REMOVING OPERATIONAL FEATURES LIKE
-- PURCHASE ORDERS AND MULTI-LOCATION INVENTORY, FOCUSING PURELY ON
-- INVENTORY INTELLIGENCE.

BEGIN;

-- STEP 1: DROP OLD FUNCTIONS THAT DEPEND ON TABLES TO BE DELETED
-- This must be done first to remove dependencies.
DROP FUNCTION IF EXISTS public.create_purchase_order_and_update_inventory(uuid, uuid, uuid, text, date, date, text, jsonb);
DROP FUNCTION IF EXISTS public.create_purchase_order_and_update_inventory(uuid, uuid, text, date, date, text, numeric, jsonb);
DROP FUNCTION IF EXISTS public.delete_purchase_order(uuid, uuid);
DROP FUNCTION IF EXISTS public.get_purchase_order_details(uuid, uuid);
DROP FUNCTION IF EXISTS public.get_purchase_orders(uuid, text, integer, integer);
DROP FUNCTION IF EXISTS public.receive_purchase_order_items(uuid, jsonb, uuid, uuid);
DROP FUNCTION IF EXISTS public.update_purchase_order(uuid, uuid, uuid, text, text, date, date, text, jsonb);
DROP FUNCTION IF EXISTS public.update_po_status(uuid, uuid);
DROP FUNCTION IF EXISTS public.validate_po_financials(uuid, bigint);
DROP FUNCTION IF EXISTS public.delete_location(uuid, uuid, uuid);
DROP FUNCTION IF EXISTS public.delete_location_and_unassign_inventory(uuid, uuid, uuid);
DROP FUNCTION IF EXISTS public.delete_supplier_and_catalogs(uuid, uuid);


-- STEP 2: DROP OBSOLETE TABLES
-- Using CASCADE to remove dependent objects like indexes and constraints.
DROP TABLE IF EXISTS public.purchase_order_items CASCADE;
DROP TABLE IF EXISTS public.purchase_orders CASCADE;
DROP TABLE IF EXISTS public.locations CASCADE;
DROP TABLE IF EXISTS public.reorder_rules CASCADE;
DROP TABLE IF EXISTS public.supplier_catalogs CASCADE;
DROP TABLE IF EXISTS public.vendors CASCADE;


-- STEP 3: ALTER EXISTING TABLES TO SIMPLIFY THEM

-- Simplify 'inventory' table
ALTER TABLE public.inventory
  DROP COLUMN IF EXISTS on_order_quantity,
  DROP COLUMN IF EXISTS location_id,
  DROP COLUMN IF EXISTS conflict_status,
  DROP COLUMN IF EXISTS last_external_sync,
  DROP COLUMN IF EXISTS manual_override,
  DROP COLUMN IF EXISTS expiration_date,
  DROP COLUMN IF EXISTS lot_number,
  ADD COLUMN IF NOT EXISTS supplier_id UUID REFERENCES public.suppliers(id) ON DELETE SET NULL;

-- Simplify 'customers' table
ALTER TABLE public.customers
  DROP COLUMN IF EXISTS platform,
  DROP COLUMN IF EXISTS external_id,
  DROP COLUMN IF EXISTS status;

-- Simplify 'sales' table
ALTER TABLE public.sales
  DROP COLUMN IF EXISTS created_by;

-- Rename 'inventory_ledger' to 'inventory_changes' and ensure its schema is correct
-- First, drop the old ledger if it exists
DROP TABLE IF EXISTS public.inventory_ledger CASCADE;
-- Then, create the new, correctly defined table
CREATE TABLE public.inventory_ledger (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  product_id uuid NOT NULL, -- This will be linked to inventory.id
  change_type text NOT NULL,
  quantity_change integer NOT NULL,
  new_quantity integer NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  related_id uuid,
  notes text,
  CONSTRAINT inventory_ledger_pkey PRIMARY KEY (id)
);
-- Add a foreign key constraint to the correct column in inventory
ALTER TABLE public.inventory_ledger ADD CONSTRAINT inventory_ledger_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.inventory(id) ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_product_id ON public.inventory_ledger(product_id);


-- STEP 4: RE-CREATE AND UPDATE NECESSARY FUNCTIONS FOR THE NEW SCHEMA

-- Function to record a sale and update inventory quantities accordingly
CREATE OR REPLACE FUNCTION public.record_sale_transaction(
    p_company_id uuid,
    p_sale_items jsonb,
    p_customer_name text DEFAULT NULL::text,
    p_customer_email text DEFAULT NULL::text,
    p_payment_method text DEFAULT 'other'::text,
    p_notes text DEFAULT NULL::text,
    p_external_id text DEFAULT NULL::text
) RETURNS public.sales
LANGUAGE plpgsql
AS $$
DECLARE
    new_sale public.sales;
    item_record record;
    v_total_amount numeric := 0;
    v_product_id uuid;
    v_current_quantity integer;
BEGIN
    -- Calculate total amount
    FOR item_record IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(unit_price numeric, quantity int)
    LOOP
        v_total_amount := v_total_amount + (item_record.quantity * item_record.unit_price);
    END LOOP;

    -- Create the sale record
    INSERT INTO public.sales (company_id, sale_number, customer_name, customer_email, total_amount, payment_method, notes, external_id)
    VALUES (p_company_id, 'SALE-' || nextval('sales_sale_number_seq'), p_customer_name, p_customer_email, v_total_amount, p_payment_method, p_notes, p_external_id)
    RETURNING * INTO new_sale;

    -- Process each sale item
    FOR item_record IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(sku text, product_name text, quantity int, unit_price numeric, cost_at_time numeric)
    LOOP
        -- Find the product_id from the SKU
        SELECT id, quantity INTO v_product_id, v_current_quantity FROM public.inventory WHERE sku = item_record.sku AND company_id = p_company_id;

        IF v_product_id IS NULL THEN
            RAISE WARNING 'SKU % not found in inventory for company %. Skipping item.', item_record.sku, p_company_id;
            CONTINUE;
        END IF;

        -- Insert into sale_items
        INSERT INTO public.sale_items (sale_id, company_id, sku, product_name, quantity, unit_price, cost_at_time)
        VALUES (new_sale.id, p_company_id, item_record.sku, item_record.product_name, item_record.quantity, item_record.unit_price, item_record.cost_at_time);

        -- Update inventory quantity and last_sold_date
        UPDATE public.inventory
        SET
            quantity = quantity - item_record.quantity,
            last_sold_date = CURRENT_DATE
        WHERE id = v_product_id;

        -- Log the change in the new ledger table
        INSERT INTO public.inventory_ledger (company_id, product_id, change_type, quantity_change, new_quantity, related_id, notes)
        VALUES (p_company_id, v_product_id, 'sale', -item_record.quantity, v_current_quantity - item_record.quantity, new_sale.id, 'Sale #' || new_sale.sale_number);

    END LOOP;

    RETURN new_sale;
END;
$$;


-- Simplified reorder suggestions function
CREATE OR REPLACE FUNCTION public.get_reorder_suggestions(
    p_company_id uuid,
    p_timezone text DEFAULT 'UTC'
)
RETURNS TABLE(
    product_id uuid,
    sku text,
    product_name text,
    current_quantity integer,
    reorder_point integer,
    suggested_reorder_quantity integer,
    supplier_id uuid,
    supplier_name text,
    unit_cost numeric
)
LANGUAGE sql
AS $$
    -- This function's body would be updated to reflect the simplified schema
    -- For now, it returns the necessary columns without complex logic
    -- that depended on deleted tables.
    SELECT
        i.id as product_id,
        i.sku,
        i.name as product_name,
        i.quantity as current_quantity,
        i.reorder_point,
        (i.reorder_point - i.quantity) as suggested_reorder_quantity,
        s.id as supplier_id,
        s.name as supplier_name,
        i.cost as unit_cost
    FROM public.inventory i
    LEFT JOIN public.suppliers s ON i.supplier_id = s.id
    WHERE i.company_id = p_company_id
      AND i.reorder_point IS NOT NULL
      AND i.quantity < i.reorder_point;
$$;


COMMIT;
