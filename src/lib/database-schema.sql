-- InvoChat: Database Migration & Simplification Script
-- This script transforms the existing database to the new "Inventory Intelligence" focused schema.
-- It is designed to be run ONCE on your existing database.

BEGIN;

-- STEP 1: Drop functions that depend on tables we are about to delete.
-- The order is critical to avoid dependency errors.

DROP FUNCTION IF EXISTS public.create_purchase_order_and_update_inventory(uuid, uuid, text, date, date, text, jsonb);
DROP FUNCTION IF EXISTS public.create_purchase_order_and_update_inventory(uuid, uuid, uuid, text, date, date, text, jsonb);
DROP FUNCTION IF EXISTS public.receive_purchase_order_items(uuid, jsonb, uuid, uuid);
DROP FUNCTION IF EXISTS public.delete_purchase_order(uuid, uuid);
DROP FUNCTION IF EXISTS public.get_purchase_order_details(uuid, uuid);
DROP FUNCTION IF EXISTS public.get_purchase_orders(uuid, text, integer, integer);
DROP FUNCTION IF EXISTS public.update_po_status(uuid, uuid);
DROP FUNCTION IF EXISTS public.update_purchase_order(uuid, uuid, uuid, text, text, date, date, text, jsonb);
DROP FUNCTION IF EXISTS public.get_purchase_order_analytics(uuid);
DROP FUNCTION IF EXISTS public.validate_po_financials(uuid, bigint);
DROP FUNCTION IF EXISTS public.get_suppliers_with_performance(uuid);
DROP FUNCTION IF EXISTS public.delete_location(uuid, uuid, uuid);
DROP FUNCTION IF EXISTS public.delete_supplier_and_catalogs(uuid, uuid);

-- STEP 2: Drop the now-unused tables.
-- CASCADE will handle removing associated indexes and constraints.
DROP TABLE IF EXISTS public.purchase_order_items CASCADE;
DROP TABLE IF EXISTS public.purchase_orders CASCADE;
DROP TABLE IF EXISTS public.locations CASCADE;
DROP TABLE IF EXISTS public.vendors CASCADE;
DROP TABLE IF EXISTS public.supplier_catalogs CASCADE;
DROP TABLE IF EXISTS public.reorder_rules CASCADE;

-- STEP 3: Alter the remaining 'inventory' table to remove obsolete columns.
-- We must remove the foreign key constraint before dropping the column.
ALTER TABLE public.inventory DROP CONSTRAINT IF EXISTS inventory_location_id_fkey;
ALTER TABLE public.inventory
  DROP COLUMN IF EXISTS location_id,
  DROP COLUMN IF EXISTS on_order_quantity,
  DROP COLUMN IF EXISTS landed_cost,
  DROP COLUMN IF EXISTS conflict_status,
  DROP COLUMN IF EXISTS last_external_sync,
  DROP COLUMN IF EXISTS manual_override,
  DROP COLUMN IF EXISTS expiration_date,
  DROP COLUMN IF EXISTS lot_number;

-- Add a simplified supplier link to inventory
ALTER TABLE public.inventory ADD COLUMN IF NOT EXISTS supplier_id UUID REFERENCES public.suppliers(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_inventory_supplier_id ON public.inventory(supplier_id);


-- STEP 4: Rename 'inventory_changes' to 'inventory_ledger' for clarity and fix columns
ALTER TABLE IF EXISTS public.inventory_changes RENAME TO inventory_ledger;
ALTER TABLE public.inventory_ledger 
  ALTER COLUMN sku TYPE text,
  ADD COLUMN IF NOT EXISTS product_id UUID,
  ADD COLUMN IF NOT EXISTS new_quantity integer;

-- Back-fill product_id in the new ledger table from inventory sku
UPDATE public.inventory_ledger led
SET product_id = inv.id
FROM public.inventory inv
WHERE led.sku = inv.sku AND led.company_id = inv.company_id AND led.product_id IS NULL;

-- Now that product_id is populated, we can add the foreign key constraint
ALTER TABLE public.inventory_ledger ADD CONSTRAINT inventory_ledger_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.inventory(id) ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_product_id ON public.inventory_ledger(product_id);


-- STEP 5: Simplify and recreate necessary functions

-- Function to get reorder suggestions (simplified)
CREATE OR REPLACE FUNCTION public.get_reorder_suggestions(p_company_id uuid, p_fast_moving_days integer)
RETURNS TABLE(product_id uuid, sku text, product_name text, current_quantity integer, reorder_point integer, suggested_reorder_quantity integer, supplier_name text, supplier_id uuid, unit_cost bigint, base_quantity integer)
LANGUAGE sql STABLE
AS $$
  -- This function is now focused purely on suggestion, not PO creation logic.
  SELECT
      i.id as product_id,
      i.sku,
      i.name as product_name,
      i.quantity as current_quantity,
      i.reorder_point,
      GREATEST(i.reorder_point - i.quantity, 0) as suggested_reorder_quantity,
      s.name as supplier_name,
      s.id as supplier_id,
      CAST(i.cost AS bigint) as unit_cost,
      GREATEST(i.reorder_point - i.quantity, 0) as base_quantity
  FROM
      public.inventory i
  LEFT JOIN
      public.suppliers s ON i.supplier_id = s.id
  WHERE
      i.company_id = p_company_id
      AND i.quantity < i.reorder_point
      AND i.deleted_at IS NULL;
$$;


-- Function to record a sale and update inventory
CREATE OR REPLACE FUNCTION public.record_sale_transaction(
    p_company_id uuid,
    p_sale_items jsonb,
    p_customer_name text DEFAULT NULL,
    p_customer_email text DEFAULT NULL,
    p_payment_method text DEFAULT 'other',
    p_notes text DEFAULT NULL,
    p_external_id text DEFAULT NULL
)
RETURNS public.sales
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
  FOR item_record IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(sku text, quantity integer, unit_price numeric)
  LOOP
    v_total_amount := v_total_amount + (item_record.quantity * item_record.unit_price);
  END LOOP;

  -- Create sale record
  INSERT INTO public.sales (company_id, customer_name, customer_email, total_amount, payment_method, notes, external_id)
  VALUES (p_company_id, p_customer_name, p_customer_email, v_total_amount, p_payment_method, p_notes, p_external_id)
  RETURNING * INTO new_sale;

  -- Create sale items and update inventory
  FOR item_record IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(sku text, product_name text, quantity integer, unit_price numeric, cost_at_time numeric)
  LOOP
    -- Find the product ID for the given SKU
    SELECT id, quantity INTO v_product_id, v_current_quantity FROM public.inventory WHERE sku = item_record.sku AND company_id = p_company_id;

    IF v_product_id IS NOT NULL THEN
      INSERT INTO public.sale_items (sale_id, sku, product_name, quantity, unit_price, cost_at_time, company_id)
      VALUES (new_sale.id, item_record.sku, item_record.product_name, item_record.quantity, item_record.unit_price, item_record.cost_at_time, p_company_id);
      
      -- Update inventory quantity
      UPDATE public.inventory
      SET quantity = quantity - item_record.quantity,
          last_sold_date = NOW()
      WHERE id = v_product_id;

      -- Create ledger entry
      INSERT INTO public.inventory_ledger (company_id, product_id, sku, change_type, quantity_change, new_quantity, related_id)
      VALUES (p_company_id, v_product_id, item_record.sku, 'sale', -item_record.quantity, (v_current_quantity - item_record.quantity), new_sale.id);
    ELSE
        -- Optionally, handle cases where SKU is not found
        RAISE WARNING 'SKU % not found in inventory for company %. Sale item not created.', item_record.sku, p_company_id;
    END IF;
  END LOOP;

  RETURN new_sale;
END;
$$;


COMMIT;
