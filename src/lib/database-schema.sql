-- Simplified Schema for InvoChat (Inventory Intelligence)
-- This script is designed to be run on an existing database to clean it up.

-- Step 1: Drop functions that depend on the tables we are about to remove.
-- The order is important to avoid dependency errors.
DROP FUNCTION IF EXISTS public.create_purchase_order_and_update_inventory(uuid, uuid, text, date, date, text, jsonb);
DROP FUNCTION IF EXISTS public.delete_purchase_order(uuid, uuid);
DROP FUNCTION IF EXISTS public.update_purchase_order(uuid, uuid, uuid, text, text, date, date, text, jsonb);
DROP FUNCTION IF EXISTS public.update_po_status(uuid, uuid);
DROP FUNCTION IF EXISTS public.receive_purchase_order_items(uuid, jsonb, uuid, uuid);
DROP FUNCTION IF EXISTS public.get_purchase_order_details(uuid, uuid);
DROP FUNCTION IF EXISTS public.get_purchase_orders(uuid, text, integer, integer);
DROP FUNCTION IF EXISTS public.get_purchase_order_analytics(uuid);
DROP FUNCTION IF EXISTS public.get_suppliers_with_performance(uuid);
DROP FUNCTION IF EXISTS public.delete_location_and_unassign_inventory(uuid, uuid, uuid);


-- Step 2: Drop the obsolete tables. CASCADE will handle related indexes and constraints.
DROP TABLE IF EXISTS public.purchase_order_items CASCADE;
DROP TABLE IF EXISTS public.purchase_orders CASCADE;
DROP TABLE IF EXISTS public.locations CASCADE;
DROP TABLE IF EXISTS public.vendors CASCADE;
DROP TABLE IF EXISTS public.reorder_rules CASCADE;
DROP TABLE IF EXISTS public.supplier_catalogs CASCADE;

-- Step 3: Create the simplified 'suppliers' table.
-- If it already exists, this ensures it has the correct, simplified structure.
DROP TABLE IF EXISTS public.suppliers CASCADE;
CREATE TABLE public.suppliers (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamp with time zone DEFAULT now(),
    PRIMARY KEY (id),
    UNIQUE (company_id, name)
);

-- Step 4: Alter existing tables to remove obsolete columns.
ALTER TABLE public.inventory DROP COLUMN IF EXISTS location_id;
ALTER TABLE public.inventory DROP COLUMN IF EXISTS on_order_quantity;

-- Step 5: Re-create and simplify necessary functions.

-- This function now only fetches suppliers, without complex performance metrics.
CREATE OR REPLACE FUNCTION public.get_suppliers_data(p_company_id uuid)
RETURNS TABLE (
    id uuid,
    company_id uuid,
    name text,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT s.id, s.company_id, s.name, s.email, s.phone, s.default_lead_time_days, s.notes
    FROM public.suppliers s
    WHERE s.company_id = p_company_id;
END;
$$;

-- Simplified reorder suggestions, no longer creating POs.
CREATE OR REPLACE FUNCTION public.get_reorder_suggestions_from_db(p_company_id uuid)
RETURNS TABLE (
    product_id uuid,
    sku text,
    product_name text,
    current_quantity integer,
    reorder_point integer,
    suggested_reorder_quantity integer,
    supplier_id uuid,
    supplier_name text,
    unit_cost integer
)
LANGUAGE sql
STABLE
AS $$
SELECT
    p.id as product_id,
    i.sku,
    p.name as product_name,
    i.quantity as current_quantity,
    i.reorder_point,
    GREATEST(i.reorder_quantity, i.reorder_point - i.quantity) as suggested_reorder_quantity,
    s.id as supplier_id,
    s.name as supplier_name,
    i.cost::integer as unit_cost
FROM
    inventory i
JOIN
    products p ON i.product_id = p.id
LEFT JOIN
    suppliers s ON p.supplier_id = s.id
WHERE
    i.company_id = p_company_id
    AND i.quantity < i.reorder_point;
$$;

-- Simplified inventory ledger table (renamed from inventory_changes for clarity).
DROP TABLE IF EXISTS public.inventory_changes;
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    change_type text NOT NULL, -- e.g., 'sale', 'restock', 'adjustment'
    related_id uuid, -- e.g., sale_id for a sale
    created_at timestamp with time zone DEFAULT now(),
    created_by uuid REFERENCES auth.users(id)
);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_product_id ON public.inventory_ledger(product_id);

-- Updated sale recording function to log to the new ledger.
CREATE OR REPLACE FUNCTION public.record_sale_transaction(
    p_company_id uuid,
    p_user_id uuid,
    p_sale_items jsonb,
    p_customer_name text DEFAULT NULL,
    p_customer_email text DEFAULT NULL,
    p_payment_method text DEFAULT 'other',
    p_notes text DEFAULT NULL,
    p_external_id text DEFAULT NULL
) RETURNS public.sales
LANGUAGE plpgsql
AS $$
DECLARE
    new_sale public.sales;
    item record;
    v_total_amount integer := 0;
    v_product_id uuid;
    v_current_quantity integer;
BEGIN
    -- Calculate total amount
    FOR item IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(product_id uuid, quantity integer, unit_price integer)
    LOOP
        v_total_amount := v_total_amount + (item.quantity * item.unit_price);
    END LOOP;

    -- Create sale record
    INSERT INTO public.sales (company_id, created_by, total_amount, payment_method, notes, customer_name, customer_email, external_id)
    VALUES (p_company_id, p_user_id, v_total_amount, p_payment_method, p_notes, p_customer_name, p_customer_email, p_external_id)
    RETURNING * INTO new_sale;

    -- Update inventory and log changes
    FOR item IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(product_id uuid, quantity integer, unit_price integer, product_name text)
    LOOP
        INSERT INTO public.sale_items (sale_id, company_id, product_id, quantity, unit_price, product_name)
        VALUES (new_sale.id, p_company_id, item.product_id, item.quantity, item.unit_price, item.product_name);

        UPDATE public.inventory
        SET quantity = quantity - item.quantity
        WHERE id = item.product_id AND company_id = p_company_id
        RETURNING quantity INTO v_current_quantity;

        INSERT INTO public.inventory_ledger (company_id, product_id, quantity_change, new_quantity, change_type, related_id, created_by)
        VALUES (p_company_id, item.product_id, -item.quantity, v_current_quantity, 'sale', new_sale.id, p_user_id);
    END LOOP;

    RETURN new_sale;
END;
$$;


-- Final check: Ensure the basic handle_new_user trigger is still there.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  new_company_id uuid;
BEGIN
  -- Create a new company for the user
  INSERT INTO public.companies (name)
  VALUES (new.raw_user_meta_data->>'company_name')
  RETURNING id INTO new_company_id;

  -- Insert into our public users table
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (new.id, new_company_id, new.email, 'Owner');
  
  -- Update the user's app_metadata in auth.users
  UPDATE auth.users
  SET app_metadata = jsonb_set(
    COALESCE(app_metadata, '{}'::jsonb),
    '{company_id}',
    to_jsonb(new_company_id)
  )
  WHERE id = new.id;

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop trigger if it exists, then re-create to ensure it's correct.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- That's it! This script cleans up and simplifies the database.
SELECT 'Database migration complete.';
