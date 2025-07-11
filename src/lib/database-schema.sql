-- Simplified Schema Migration for InvoChat (v2)
-- This script transforms an existing database to the new, focused schema.

-- Step 1: Drop dependent functions first in the correct order.
-- Drop functions that depend on tables we will be deleting.
DROP FUNCTION IF EXISTS public.get_purchase_order_details(uuid, uuid);
DROP FUNCTION IF EXISTS public.get_purchase_orders(uuid, text, integer, integer);
DROP FUNCTION IF EXISTS public.get_purchase_order_analytics(uuid);
DROP FUNCTION IF EXISTS public.delete_purchase_order(uuid, uuid);
DROP FUNCTION IF EXISTS public.update_purchase_order(uuid, uuid, uuid, text, text, date, date, text, jsonb);
DROP FUNCTION IF EXISTS public.update_po_status(uuid, uuid);
DROP FUNCTION IF EXISTS public.receive_purchase_order_items(uuid, jsonb, uuid, uuid);

-- Step 2: Drop unnecessary tables using CASCADE to handle dependencies.
DROP TABLE IF EXISTS public.purchase_order_items CASCADE;
DROP TABLE IF EXISTS public.purchase_orders CASCADE;
DROP TABLE IF EXISTS public.locations CASCADE;
DROP TABLE IF EXISTS public.reorder_rules CASCADE;
DROP TABLE IF EXISTS public.supplier_catalogs CASCADE;
DROP TABLE IF EXISTS public.vendors CASCADE; -- This is the old suppliers table

-- Step 3: Alter existing tables to match the new schema.

-- Simplify the 'inventory' table
ALTER TABLE public.inventory
  DROP COLUMN IF EXISTS on_order_quantity,
  DROP COLUMN IF EXISTS landed_cost,
  DROP COLUMN IF EXISTS location_id,
  DROP COLUMN IF EXISTS expiration_date,
  DROP COLUMN IF EXISTS lot_number,
  ADD COLUMN IF NOT EXISTS supplier_id uuid,
  ADD CONSTRAINT inventory_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) ON DELETE SET NULL;

-- Make sure the unique constraint on inventory is correct and exists.
-- Drop it first to ensure the script is re-runnable, then add it.
ALTER TABLE public.inventory DROP CONSTRAINT IF EXISTS inventory_company_id_sku_key;
ALTER TABLE public.inventory ADD CONSTRAINT inventory_company_id_sku_key UNIQUE (company_id, sku);


-- Step 4: Create the new 'suppliers' table (if it doesn't exist from a partial run)
-- This replaces the old 'vendors' table
CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid DEFAULT uuid_generate_v4() NOT NULL PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT suppliers_company_id_name_key UNIQUE (company_id, name)
);


-- Step 5: Create the simplified inventory ledger table
DROP TABLE IF EXISTS public.inventory_ledger CASCADE;
CREATE TABLE public.inventory_ledger (
    id uuid DEFAULT uuid_generate_v4() NOT NULL PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.inventory(id) ON DELETE CASCADE,
    change_type text NOT NULL, -- 'sale', 'restock', 'adjustment'
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    related_id uuid, -- e.g., sale_id or manual adjustment id
    notes text
);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_product_id ON public.inventory_ledger(product_id);

-- Step 6: Update existing functions to work with the new schema.

-- get_unified_inventory: Simplified to remove location and PO logic
CREATE OR REPLACE FUNCTION public.get_unified_inventory(
    p_company_id uuid,
    p_query text DEFAULT NULL,
    p_category text DEFAULT NULL,
    p_supplier_id uuid DEFAULT NULL,
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
      SELECT
          i.id,
          i.sku,
          i.name,
          i.category,
          i.quantity,
          i.cost,
          i.price,
          i.reorder_point,
          s.name as supplier_name,
          s.id as supplier_id,
          i.updated_at
      FROM
          public.inventory i
      LEFT JOIN
          public.suppliers s ON i.supplier_id = s.id
      WHERE
          i.company_id = p_company_id
          AND i.deleted_at IS NULL
          AND (p_query IS NULL OR i.name ILIKE '%' || p_query || '%' OR i.sku ILIKE '%' || p_query || '%')
          AND (p_category IS NULL OR i.category = p_category)
          AND (p_supplier_id IS NULL OR i.supplier_id = p_supplier_id)
          AND (p_product_id_filter IS NULL OR i.id = p_product_id_filter)
  )
  SELECT
      (SELECT json_agg(fi.*) FROM (
          SELECT
              fi.id as product_id,
              fi.sku,
              fi.name as product_name,
              fi.category,
              fi.quantity,
              fi.cost::bigint,
              fi.price::bigint,
              (fi.quantity * fi.cost)::bigint as total_value,
              fi.reorder_point,
              fi.supplier_name,
              fi.supplier_id,
              fi.updated_at
          FROM filtered_inventory fi
          ORDER BY fi.updated_at DESC NULLS LAST
          LIMIT p_limit
          OFFSET p_offset
      ) AS fi) as items,
      (SELECT COUNT(*) FROM filtered_inventory) as total_count;
END;
$$;


-- record_sale_transaction: Simplified to only update inventory and create a ledger entry.
CREATE OR REPLACE FUNCTION public.record_sale_transaction(
    p_company_id uuid,
    p_sale_items jsonb,
    p_customer_name text DEFAULT NULL,
    p_customer_email text DEFAULT NULL,
    p_payment_method text DEFAULT 'other',
    p_notes text DEFAULT NULL,
    p_external_id text DEFAULT NULL
) RETURNS public.sales
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    new_sale record;
    sale_item jsonb;
    inv_record record;
    total_sale_amount numeric := 0;
BEGIN
    -- Calculate total amount
    FOR sale_item IN SELECT * FROM jsonb_array_elements(p_sale_items)
    LOOP
        total_sale_amount := total_sale_amount + ((sale_item->>'unit_price')::numeric * (sale_item->>'quantity')::integer);
    END LOOP;

    -- Insert the sale
    INSERT INTO public.sales (company_id, sale_number, customer_name, customer_email, total_amount, payment_method, notes, external_id)
    VALUES (p_company_id, 'SALE-' || nextval('sales_sale_number_seq'), p_customer_name, p_customer_email, total_sale_amount, p_payment_method, p_notes, p_external_id)
    RETURNING * INTO new_sale;

    -- Process sale items
    FOR sale_item IN SELECT * FROM jsonb_array_elements(p_sale_items)
    LOOP
        -- Find the corresponding inventory item
        SELECT * INTO inv_record FROM public.inventory WHERE sku = sale_item->>'sku' AND company_id = p_company_id;

        IF inv_record IS NOT NULL THEN
            -- Update inventory quantity
            UPDATE public.inventory
            SET
                quantity = quantity - (sale_item->>'quantity')::integer,
                last_sold_date = NOW()
            WHERE id = inv_record.id;

            -- Create a ledger entry
            INSERT INTO public.inventory_ledger (company_id, product_id, change_type, quantity_change, new_quantity, related_id)
            VALUES (p_company_id, inv_record.id, 'sale', -(sale_item->>'quantity')::integer, inv_record.quantity - (sale_item->>'quantity')::integer, new_sale.id);

            -- Insert into sale_items
            INSERT INTO public.sale_items (sale_id, company_id, sku, product_name, quantity, unit_price, cost_at_time)
            VALUES (new_sale.id, p_company_id, sale_item->>'sku', sale_item->>'product_name', (sale_item->>'quantity')::integer, (sale_item->>'unit_price')::numeric, inv_record.cost);
        END IF;
    END LOOP;

    RETURN new_sale;
END;
$$;


-- get_reorder_suggestions: Simplified to remove PO logic.
CREATE OR REPLACE FUNCTION public.get_reorder_suggestions(p_company_id uuid)
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
SELECT
    i.id as product_id,
    i.sku,
    i.name as product_name,
    i.quantity as current_quantity,
    i.reorder_point,
    GREATEST(i.reorder_point - i.quantity, 0) as suggested_reorder_quantity,
    s.name as supplier_name,
    s.id as supplier_id,
    i.cost as unit_cost,
    GREATEST(i.reorder_point - i.quantity, 0) as base_quantity
FROM
    public.inventory i
LEFT JOIN
    public.suppliers s ON i.supplier_id = s.id
WHERE
    i.company_id = p_company_id
    AND i.reorder_point IS NOT NULL
    AND i.quantity < i.reorder_point
    AND i.deleted_at IS NULL;
$$;

-- get_business_profile: Simplified to remove PO logic
CREATE OR REPLACE FUNCTION public.get_business_profile(p_company_id uuid)
RETURNS TABLE(monthly_revenue bigint)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT
      COALESCE(SUM(total_amount)::bigint, 0) as monthly_revenue
  FROM
      public.sales
  WHERE
      company_id = p_company_id
      AND created_at >= NOW() - INTERVAL '30 days';
END;
$$;

-- Add a dummy function to replace the old PO-related financial impact one
CREATE OR REPLACE FUNCTION public.get_financial_impact_of_po(
    p_company_id uuid,
    p_items jsonb
)
RETURNS TABLE (
    total_cost numeric,
    inventory_value_increase numeric,
    notes text
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        0::numeric,
        0::numeric,
        'Purchase Order functionality has been removed. This function is a placeholder.'::text;
END;
$$;


-- Final step: Clean up any lingering types that might have been created by old scripts.
DROP TYPE IF EXISTS public.po_item_input;

-- Re-enable Row Level Security if it was disabled
ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
-- ... add for all other tables that should have RLS.

-- Grant usage on new sequences if any, and on schema
GRANT USAGE ON SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO postgres, anon, authenticated, service_role;


-- End of script
