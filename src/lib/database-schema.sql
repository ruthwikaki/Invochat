
-- ----------------------------------------------------------------
-- InvoChat - Destructive Migration to Intelligence-Focused Schema
-- ----------------------------------------------------------------
-- This script will:
--   1. Drop functions that depend on the tables being removed.
--   2. Drop tables related to Purchase Orders, Locations, and other complex features.
--   3. Alter remaining tables to simplify them.
--   4. Create new, simpler tables like 'inventory_ledger'.
--   5. Re-create the essential functions needed for the new schema.
--
-- WARNING: This is a DESTRUCTIVE migration. It will permanently delete data.
--          Backup your database before running this script.
-- ----------------------------------------------------------------

SET client_min_messages TO WARNING;

-- STEP 1: Drop dependent functions and views before dropping tables.
-- This must be done to remove dependencies on the tables we're about to drop.
DROP FUNCTION IF EXISTS public.get_purchase_order_details(uuid, uuid);
DROP FUNCTION IF EXISTS public.receive_purchase_order_items(uuid, jsonb, uuid, uuid);
DROP FUNCTION IF EXISTS public.create_purchase_order_and_update_inventory(uuid, uuid, uuid, text, date, date, text, jsonb);
DROP FUNCTION IF EXISTS public.get_purchase_orders(uuid, text, int, int);
DROP FUNCTION IF EXISTS public.get_purchase_order_analytics(uuid);
DROP FUNCTION IF EXISTS public.get_supplier_performance(uuid);
DROP FUNCTION IF EXISTS public.get_suppliers_with_performance(uuid);
DROP FUNCTION IF EXISTS public.delete_location_and_unassign_inventory(uuid, uuid, uuid);
DROP FUNCTION IF EXISTS public.validate_po_financials(uuid, bigint);
DROP FUNCTION IF EXISTS public.update_purchase_order(uuid, uuid, uuid, text, text, date, date, text, jsonb);
DROP FUNCTION IF EXISTS public.delete_purchase_order(uuid, uuid);
DROP MATERIALIZED VIEW IF EXISTS public.company_dashboard_metrics;

-- STEP 2: Drop tables in an order that respects foreign key constraints.
-- Start with tables that are referenced by others (child tables).
DROP TABLE IF EXISTS public.purchase_order_items;
DROP TABLE IF EXISTS public.reorder_rules;
DROP TABLE IF EXISTS public.supplier_catalogs;
DROP TABLE IF EXISTS public.sync_logs;
DROP TABLE IF EXISTS public.sync_state;

-- Now drop the parent tables.
DROP TABLE IF EXISTS public.purchase_orders;
DROP TABLE IF EXISTS public.vendors; -- This was the old name for suppliers

-- Drop inventory_ledger and we will recreate it as inventory_changes later.
DROP TABLE IF EXISTS public.inventory_ledger;
DROP TABLE IF EXISTS public.inventory; -- We will recreate this to simplify it.
DROP TABLE IF EXISTS public.locations;

-- STEP 3: Re-create simplified tables and create new ones.

-- Simplified Suppliers Table
CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    CONSTRAINT uq_supplier_name_company UNIQUE (company_id, name)
);

-- Simplified Inventory Table (no locations, simpler fields)
CREATE TABLE IF NOT EXISTS public.inventory (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku text NOT NULL,
    name text NOT NULL,
    category text,
    quantity integer NOT NULL DEFAULT 0,
    cost integer DEFAULT 0, -- In cents
    price integer, -- In cents
    reorder_point integer,
    reorder_quantity integer,
    last_sold_date date,
    supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    source_platform text,
    external_product_id text,
    external_variant_id text,
    deleted_at timestamptz,
    CONSTRAINT uq_inventory_sku_company UNIQUE (company_id, sku)
);
CREATE INDEX IF NOT EXISTS idx_inventory_company_id ON public.inventory(company_id);


-- New Inventory Ledger table (renamed from inventory_changes for clarity)
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.inventory(id) ON DELETE CASCADE,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    change_type text NOT NULL, -- e.g., 'sale', 'restock', 'adjustment'
    related_id text, -- e.g., sale_id or manual adjustment note
    created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_product_id ON public.inventory_ledger(product_id);

-- STEP 4: Update remaining tables to remove dependencies.

-- Sale Items: need a product_id now instead of just SKU.
-- We will drop and recreate for simplicity in this migration.
DROP TABLE IF EXISTS public.sale_items;
CREATE TABLE public.sale_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    sale_id uuid NOT NULL REFERENCES public.sales(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.inventory(id) ON DELETE RESTRICT,
    quantity integer NOT NULL,
    unit_price integer NOT NULL, -- In cents
    cost_at_time integer NOT NULL, -- In cents
    CONSTRAINT uq_sale_item UNIQUE (sale_id, product_id)
);

-- STEP 5: Re-create essential database functions for the new schema.

-- Function to handle new user setup.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_company_id uuid;
  v_company_name text;
BEGIN
  v_company_name := NEW.raw_user_meta_data->>'company_name';

  -- Create a new company for the user
  INSERT INTO public.companies (name)
  VALUES (v_company_name)
  RETURNING id INTO v_company_id;

  -- Create a corresponding user entry
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (NEW.id, v_company_id, NEW.email, 'Owner');
  
  -- Update the user's app_metadata with the new company_id and role
  UPDATE auth.users
  SET app_metadata = jsonb_set(
    jsonb_set(app_metadata, '{company_id}', to_jsonb(v_company_id)),
    '{role}', to_jsonb('Owner'::text)
  )
  WHERE id = NEW.id;

  RETURN NEW;
END;
$$;

-- Trigger for handle_new_user
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- Function to record a sale and update inventory atomically
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
SECURITY DEFINER
AS $$
DECLARE
    new_sale public.sales;
    item record;
    v_total_amount integer := 0;
    inv_record record;
    customer_id uuid;
BEGIN
    -- Upsert customer record
    IF p_customer_email IS NOT NULL THEN
        INSERT INTO public.customers (company_id, customer_name, email)
        VALUES (p_company_id, COALESCE(p_customer_name, p_customer_email), p_customer_email)
        ON CONFLICT (company_id, email) DO UPDATE SET customer_name = EXCLUDED.customer_name
        RETURNING id INTO customer_id;
    END IF;

    -- Calculate total amount
    FOR item IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(unit_price integer, quantity integer) LOOP
        v_total_amount := v_total_amount + (item.unit_price * item.quantity);
    END LOOP;

    -- Create sales record
    INSERT INTO public.sales (company_id, created_by, customer_id, total_amount, payment_method, notes, external_id)
    VALUES (p_company_id, p_user_id, customer_id, v_total_amount, p_payment_method, p_notes, p_external_id)
    RETURNING * INTO new_sale;

    -- Process sale items
    FOR item IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(product_id uuid, quantity integer, unit_price integer) LOOP
        -- Get current inventory cost
        SELECT cost INTO inv_record FROM public.inventory WHERE id = item.product_id AND company_id = p_company_id;

        INSERT INTO public.sale_items (sale_id, company_id, product_id, quantity, unit_price, cost_at_time)
        VALUES (new_sale.id, p_company_id, item.product_id, item.quantity, item.unit_price, inv_record.cost);
        
        -- Update inventory quantity
        UPDATE public.inventory
        SET 
            quantity = quantity - item.quantity,
            last_sold_date = CURRENT_DATE
        WHERE id = item.product_id AND company_id = p_company_id
        RETURNING quantity INTO inv_record.quantity;
        
        -- Log the inventory change
        INSERT INTO public.inventory_ledger (company_id, product_id, quantity_change, new_quantity, change_type, related_id)
        VALUES (p_company_id, item.product_id, -item.quantity, inv_record.quantity, 'sale', new_sale.id::text);
    END LOOP;

    RETURN new_sale;
END;
$$;


-- Function for batch upserting product costs and rules
CREATE OR REPLACE FUNCTION public.batch_upsert_costs(
    p_records jsonb,
    p_company_id uuid,
    p_user_id uuid
) RETURNS void AS $$
DECLARE
    item record;
    v_supplier_id uuid;
    v_inventory_id uuid;
BEGIN
    FOR item IN SELECT * FROM jsonb_to_recordset(p_records) AS x(
        sku text, 
        cost integer, 
        supplier_name text, 
        reorder_point integer, 
        reorder_quantity integer,
        lead_time_days integer
    )
    LOOP
        -- Find or create supplier
        IF item.supplier_name IS NOT NULL THEN
            INSERT INTO public.suppliers (company_id, name, default_lead_time_days)
            VALUES (p_company_id, item.supplier_name, item.lead_time_days)
            ON CONFLICT (company_id, name) DO UPDATE SET default_lead_time_days = EXCLUDED.default_lead_time_days
            RETURNING id INTO v_supplier_id;
        END IF;
        
        -- Update inventory
        UPDATE public.inventory
        SET
            cost = COALESCE(item.cost, cost),
            reorder_point = COALESCE(item.reorder_point, reorder_point),
            reorder_quantity = COALESCE(item.reorder_quantity, reorder_quantity),
            supplier_id = COALESCE(v_supplier_id, supplier_id),
            updated_at = now()
        WHERE sku = item.sku AND company_id = p_company_id
        RETURNING id into v_inventory_id;
        
        IF v_inventory_id IS NOT NULL THEN
            INSERT INTO public.audit_log (user_id, company_id, action, details)
            VALUES (p_user_id, p_company_id, 'cost_import_update', jsonb_build_object('product_id', v_inventory_id, 'sku', item.sku));
        END IF;
        
        v_supplier_id := NULL;
        v_inventory_id := NULL;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Simplified materialized view for dashboard
CREATE MATERIALIZED VIEW public.company_dashboard_metrics AS
SELECT
    i.company_id,
    SUM(i.quantity * i.cost) AS inventory_value,
    COUNT(*) FILTER (WHERE i.quantity <= i.reorder_point) AS low_stock_count,
    COUNT(*) AS total_skus
FROM
    inventory i
WHERE i.deleted_at IS NULL
GROUP BY
    i.company_id;

CREATE UNIQUE INDEX company_dashboard_metrics_pkey ON public.company_dashboard_metrics(company_id);

-- Function to refresh the view
CREATE OR REPLACE FUNCTION public.refresh_materialized_views(p_company_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY company_dashboard_metrics;
END;
$$;


ALTER TABLE public.users
ADD CONSTRAINT users_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
ADD CONSTRAINT users_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE public.conversations
ADD CONSTRAINT conversations_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;

ALTER TABLE public.customers
ADD CONSTRAINT customers_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;

ALTER TABLE public.sales
ADD CONSTRAINT sales_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


-- Final step: Add a log to indicate completion.
INSERT INTO public.audit_log(action, details) VALUES ('migration_completed', '{"script": "intelligence_pivot_v1"}');

-- --- END OF SCRIPT ---
