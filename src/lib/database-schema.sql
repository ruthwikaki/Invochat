-- This script is designed to be run on your existing database.
-- It will drop old tables and functions and create a new, simplified schema.

-- =================================================================
-- STEP 1: DROP DEPENDENT FUNCTIONS
-- =================================================================
DROP FUNCTION IF EXISTS public.create_purchase_order_and_update_inventory(uuid, uuid, uuid, text, date, date, text, jsonb);
DROP FUNCTION IF EXISTS public.create_purchase_order_and_update_inventory(uuid, uuid, text, date, date, text, numeric, jsonb);
DROP FUNCTION IF EXISTS public.create_purchase_orders_from_suggestions_tx(uuid, jsonb);
DROP FUNCTION IF EXISTS public.update_purchase_order(uuid, uuid, uuid, text, text, date, date, text, jsonb);
DROP FUNCTION IF EXISTS public.get_purchase_order_details(uuid, uuid);
DROP FUNCTION IF EXISTS public.delete_purchase_order(uuid, uuid);
DROP FUNCTION IF EXISTS public.update_po_status(uuid, uuid);
DROP FUNCTION IF EXISTS public.delete_location(uuid, uuid, uuid);
DROP FUNCTION IF EXISTS public.delete_location_and_unassign_inventory(uuid, uuid, uuid);
DROP FUNCTION IF EXISTS public.get_suppliers_with_performance(uuid);
DROP FUNCTION IF EXISTS public.validate_po_financials(uuid, bigint);


-- =================================================================
-- STEP 2: DROP OLD AND UNNECESSARY TABLES
-- =================================================================
-- Drop tables with dependencies first.
DROP TABLE IF EXISTS public.purchase_order_items CASCADE;
DROP TABLE IF EXISTS public.supplier_catalogs CASCADE;
DROP TABLE IF EXISTS public.inventory_ledger CASCADE; -- Renaming this to inventory_changes later
DROP TABLE IF EXISTS public.reorder_rules CASCADE;

-- Drop remaining unnecessary tables
DROP TABLE IF EXISTS public.purchase_orders CASCADE;
DROP TABLE IF EXISTS public.vendors CASCADE; -- Dropping this to replace with simplified 'suppliers'
DROP TABLE IF EXISTS public.locations CASCADE;


-- =================================================================
-- STEP 3: ALTER AND SIMPLIFY EXISTING TABLES
-- =================================================================

-- Create the new 'suppliers' table (replaces 'vendors')
CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid NOT NULL DEFAULT uuid_generate_v4 (),
    company_id uuid NOT NULL,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT suppliers_pkey PRIMARY KEY (id),
    CONSTRAINT suppliers_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies (id) ON DELETE CASCADE,
    CONSTRAINT suppliers_company_id_name_key UNIQUE (company_id, name)
);

-- Simplify the 'inventory' table
ALTER TABLE public.inventory
DROP COLUMN IF EXISTS location_id,
DROP COLUMN IF EXISTS landed_cost,
DROP COLUMN IF EXISTS on_order_quantity,
DROP COLUMN IF EXISTS conflict_status,
DROP COLUMN IF EXISTS last_external_sync,
DROP COLUMN IF EXISTS manual_override,
DROP COLUMN IF EXISTS expiration_date,
DROP COLUMN IF EXISTS lot_number,
ADD COLUMN IF NOT EXISTS supplier_id uuid,
ADD CONSTRAINT inventory_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) ON DELETE SET NULL;

-- Simplify the 'sales' table
ALTER TABLE public.sales
DROP COLUMN IF EXISTS created_by;

-- Simplify 'customers' table
ALTER TABLE public.customers
DROP COLUMN IF EXISTS platform,
DROP COLUMN IF EXISTS external_id,
DROP COLUMN IF EXISTS status;

-- =================================================================
-- STEP 4: CREATE NEW FOCUSED TABLES
-- =================================================================

-- Create a simple inventory ledger for auditing stock changes
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid NOT NULL DEFAULT uuid_generate_v4 (),
    company_id uuid NOT NULL,
    product_id uuid NOT NULL,
    change_type text NOT NULL, -- e.g., 'sale', 'restock', 'adjustment'
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    related_id uuid, -- e.g., sale_id for a sale
    notes text,
    CONSTRAINT inventory_ledger_pkey PRIMARY KEY (id),
    CONSTRAINT inventory_ledger_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies (id) ON DELETE CASCADE,
    CONSTRAINT inventory_ledger_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.inventory (id) ON DELETE CASCADE
);

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_inventory_sku_company ON public.inventory (sku, company_id);
CREATE INDEX IF NOT EXISTS idx_suppliers_name_company ON public.suppliers (name, company_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_product_id ON public.inventory_ledger (product_id);

-- =================================================================
-- STEP 5: RE-CREATE AND SIMPLIFY DATABASE FUNCTIONS
-- =================================================================

-- Function to handle new user setup.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  new_company_id uuid;
BEGIN
  -- Create a new company for the new user
  INSERT INTO public.companies (name)
  VALUES (new.raw_user_meta_data->>'company_name')
  RETURNING id INTO new_company_id;

  -- Update the user's app_metadata with the new company_id
  UPDATE auth.users
  SET app_metadata = jsonb_set(
    COALESCE(app_metadata, '{}'::jsonb),
    '{company_id}',
    to_jsonb(new_company_id)
  )
  WHERE id = new.id;

  -- Create default settings for the new company
  INSERT INTO public.company_settings (company_id)
  VALUES (new_company_id);

  RETURN new;
END;
$$;

-- Function to record a sale and update inventory atomically.
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
AS $$
DECLARE
  new_sale public.sales;
  item_record record;
  v_total_amount integer := 0;
  v_customer_id uuid;
  current_stock integer;
BEGIN
  -- Calculate total amount
  FOR item_record IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(unit_price integer, quantity integer)
  LOOP
    v_total_amount := v_total_amount + (item_record.quantity * item_record.unit_price);
  END LOOP;

  -- Upsert customer
  IF p_customer_email IS NOT NULL THEN
    INSERT INTO public.customers (company_id, customer_name, email)
    VALUES (p_company_id, COALESCE(p_customer_name, p_customer_email), p_customer_email)
    ON CONFLICT (company_id, email) DO UPDATE SET customer_name = EXCLUDED.customer_name
    RETURNING id INTO v_customer_id;
  END IF;

  -- Create the sale record
  INSERT INTO public.sales (company_id, customer_id, total_amount, payment_method, notes, external_id)
  VALUES (p_company_id, v_customer_id, v_total_amount, p_payment_method, p_notes, p_external_id)
  RETURNING * INTO new_sale;

  -- Process sale items, update inventory, and log changes
  FOR item_record IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(product_id uuid, quantity integer, unit_price integer, cost_at_time integer)
  LOOP
    INSERT INTO public.sale_items (sale_id, company_id, product_id, quantity, unit_price, cost_at_time)
    VALUES (new_sale.id, p_company_id, item_record.product_id, item_record.quantity, item_record.unit_price, item_record.cost_at_time);

    -- Update inventory quantity and get the new quantity
    UPDATE public.inventory
    SET
      quantity = quantity - item_record.quantity,
      last_sold_date = CURRENT_DATE,
      updated_at = now()
    WHERE id = item_record.product_id AND company_id = p_company_id
    RETURNING quantity INTO current_stock;

    -- Log the change in the new ledger table
    INSERT INTO public.inventory_ledger (company_id, product_id, change_type, quantity_change, new_quantity, related_id)
    VALUES (p_company_id, item_record.product_id, 'sale', -item_record.quantity, current_stock, new_sale.id);
  END LOOP;

  RETURN new_sale;
END;
$$;


-- Ensure the trigger for handle_new_user is present
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();


-- Final check on RLS policies to ensure they are still valid
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
-- ... (and so on for other tables that need RLS)

DROP POLICY IF EXISTS "Users can only see their own company" ON public.companies;
CREATE POLICY "Users can only see their own company" ON public.companies FOR SELECT USING (id = (current_setting('request.jwt.claims', true)::jsonb ->> 'company_id')::uuid);
-- ... (and other policies)

-- Grant usage on the new schema elements to authenticated roles
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- Grant usage to the service_role for full access
GRANT USAGE ON SCHEMA public TO service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO service_role;

-- Refresh materialized views if they exist to reflect schema changes
-- This might need to be run manually after the migration if views depend heavily on dropped columns
-- For now, we attempt a refresh.
-- REFRESH MATERIALIZED VIEW CONCURRENTLY public.company_dashboard_metrics;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY public.customer_analytics_metrics;

SELECT 'Migration script completed successfully.';

