-- InvoChat: Simplified "Inventory Intelligence" Schema Migration
-- This script is designed to be run ONCE on your existing database.
-- It will remove unnecessary tables and functions, simplifying the schema
-- to focus on core intelligence features.

-- Step 1: Drop functions that depend on tables we are about to delete.
-- This must be done first to avoid dependency errors.
DROP FUNCTION IF EXISTS public.create_purchase_order_and_update_inventory(uuid, uuid, text, date, date, text, jsonb);
DROP FUNCTION IF EXISTS public.create_purchase_order_and_update_inventory(uuid, uuid, uuid, text, date, date, text, jsonb);
DROP FUNCTION IF EXISTS public.delete_location(uuid, uuid, uuid);
DROP FUNCTION IF EXISTS public.delete_purchase_order(uuid, uuid);
DROP FUNCTION IF EXISTS public.get_purchase_order_details(uuid, uuid);
DROP FUNCTION IF EXISTS public.get_purchase_orders(uuid, text, integer, integer);
DROP FUNCTION IF EXISTS public.receive_purchase_order_items(uuid, jsonb, uuid, uuid);
DROP FUNCTION IF EXISTS public.update_po_status(uuid, uuid);
DROP FUNCTION IF EXISTS public.update_purchase_order(uuid, uuid, uuid, text, text, date, date, text, jsonb);

-- Step 2: Drop unnecessary tables. Using CASCADE to handle related constraints and indexes automatically.
DROP TABLE IF EXISTS public.purchase_order_items CASCADE;
DROP TABLE IF EXISTS public.purchase_orders CASCADE;
DROP TABLE IF EXISTS public.locations CASCADE;
DROP TABLE IF EXISTS public.reorder_rules CASCADE;
DROP TABLE IF EXISTS public.supplier_catalogs CASCADE;
DROP TABLE IF EXISTS public.vendors CASCADE; -- This table will be replaced by a simplified 'suppliers' table.

-- Step 3: Create the new, simplified 'suppliers' table.
CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone,
    CONSTRAINT suppliers_pkey PRIMARY KEY (id),
    CONSTRAINT suppliers_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT suppliers_company_id_name_key UNIQUE (company_id, name)
);
CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON public.suppliers(company_id);

-- Step 4: Alter existing tables to remove obsolete columns.
ALTER TABLE public.inventory
    DROP COLUMN IF EXISTS location_id,
    DROP COLUMN IF EXISTS landed_cost,
    DROP COLUMN IF EXISTS on_order_quantity;

-- Step 5: Add new `supplier_id` column to inventory and create foreign key.
ALTER TABLE public.inventory
    ADD COLUMN IF NOT EXISTS supplier_id UUID,
    ADD CONSTRAINT fk_inventory_supplier
        FOREIGN KEY(supplier_id) REFERENCES public.suppliers(id) ON DELETE SET NULL;

-- Step 6: Create the new simplified inventory ledger table.
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    product_id uuid NOT NULL,
    change_type text NOT NULL, -- 'sale', 'restock', 'adjustment'
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid, -- e.g., sale_id for a sale
    notes text,
    created_at timestamp with time zone DEFAULT now(),
    created_by uuid REFERENCES auth.users(id)
);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_product_id ON public.inventory_ledger(product_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_company_id_created_at ON public.inventory_ledger(company_id, created_at DESC);


-- Step 7: Re-create essential functions with updated logic for the new schema.

-- Simplified function to get reorder suggestions
CREATE OR REPLACE FUNCTION public.get_reorder_report(p_company_id uuid)
RETURNS TABLE(
    sku text,
    product_name text,
    current_quantity integer,
    reorder_point integer,
    sales_velocity_30d numeric,
    days_of_stock_left numeric,
    supplier_name text,
    supplier_email text,
    suggested_reorder_quantity integer
)
LANGUAGE sql STABLE
AS $$
    WITH thirty_day_sales AS (
        SELECT
            si.sku,
            SUM(si.quantity)::numeric AS total_sold
        FROM public.sales s
        JOIN public.sale_items si ON s.id = si.sale_id
        WHERE s.company_id = p_company_id AND s.created_at >= (NOW() - INTERVAL '30 days')
        GROUP BY si.sku
    )
    SELECT
        i.sku,
        i.name as product_name,
        i.quantity as current_quantity,
        i.reorder_point,
        COALESCE(tds.total_sold / 30.0, 0) as sales_velocity_30d,
        CASE
            WHEN COALESCE(tds.total_sold / 30.0, 0) > 0 THEN i.quantity / (tds.total_sold / 30.0)
            ELSE 999 -- Effectively infinite days of stock if no sales
        END as days_of_stock_left,
        sup.name as supplier_name,
        sup.email as supplier_email,
        (i.reorder_point - i.quantity) + (COALESCE(tds.total_sold / 30.0, 0) * 14)::integer as suggested_reorder_quantity
    FROM public.inventory i
    LEFT JOIN thirty_day_sales tds ON i.sku = tds.sku AND i.company_id = p_company_id
    LEFT JOIN public.suppliers sup ON i.supplier_id = sup.id
    WHERE i.company_id = p_company_id AND i.quantity < i.reorder_point;
$$;


-- Simplified function to get dead stock
CREATE OR REPLACE FUNCTION public.get_dead_stock_report(
    p_company_id uuid,
    p_dead_stock_days integer
)
RETURNS TABLE (
    sku text,
    product_name text,
    quantity integer,
    cost bigint,
    total_value bigint,
    last_sale_date date
)
LANGUAGE sql STABLE
AS $$
    SELECT
        i.sku,
        i.name as product_name,
        i.quantity,
        i.cost,
        (i.quantity * i.cost) as total_value,
        i.last_sold_date
    FROM public.inventory i
    WHERE i.company_id = p_company_id
      AND i.quantity > 0
      AND (i.last_sold_date IS NULL OR i.last_sold_date <= NOW() - (p_dead_stock_days || ' days')::interval);
$$;

-- Simplified handle_new_user function without PO table reference
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_company_id uuid;
    v_company_name text;
BEGIN
    -- Extract company name from metadata
    v_company_name := new.raw_user_meta_data->>'company_name';

    -- Create a new company if a name is provided
    IF v_company_name IS NOT NULL THEN
        INSERT INTO public.companies (name)
        VALUES (v_company_name)
        RETURNING id INTO v_company_id;

        -- Update the user's app_metadata with the new company_id
        UPDATE auth.users
        SET app_metadata = jsonb_set(
            COALESCE(app_metadata, '{}'::jsonb),
            '{company_id}',
            to_jsonb(v_company_id)
        )
        WHERE id = new.id;
        
    END IF;

    RETURN new;
END;
$$;

-- Drop the old trigger if it exists and recreate it
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- Log inventory changes from sales
CREATE OR REPLACE FUNCTION public.log_sale_inventory_changes()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    item_record RECORD;
BEGIN
    FOR item_record IN SELECT * FROM jsonb_to_recordset(NEW.items) AS x(product_id uuid, quantity int)
    LOOP
        INSERT INTO public.inventory_ledger (company_id, product_id, change_type, quantity_change, new_quantity, related_id, created_by)
        SELECT
            NEW.company_id,
            item_record.product_id,
            'sale',
            -item_record.quantity,
            (SELECT quantity FROM public.inventory WHERE id = item_record.product_id),
            NEW.id,
            NEW.created_by;
    END LOOP;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS after_sale_insert_log_inventory ON public.sales;
CREATE TRIGGER after_sale_insert_log_inventory
    AFTER INSERT ON public.sales
    FOR EACH ROW EXECUTE FUNCTION public.log_sale_inventory_changes();

SELECT 'Migration to simplified schema complete.' as result;
