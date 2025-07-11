
-- InvoChat: Simplified Schema Migration Script

-- This script will remove all operational features like Purchase Orders and Multi-Location
-- and focus the schema on pure Inventory Intelligence.

BEGIN;

-- =================================================================
-- Step 1: Drop dependent objects (Functions and Triggers)
-- This must be done before dropping the tables they reference.
-- =================================================================

-- Drop triggers first
DROP TRIGGER IF EXISTS handle_inventory_update ON public.inventory;
DROP TRIGGER IF EXISTS validate_inventory_location_ref ON public.inventory;
DROP TRIGGER IF EXISTS validate_purchase_order_refs ON public.purchase_orders;

-- Now drop the functions that were used by triggers or are no longer needed
DROP FUNCTION IF EXISTS public.increment_version();
DROP FUNCTION IF EXISTS public.validate_same_company_reference();
DROP FUNCTION IF EXISTS public.create_purchase_order_and_update_inventory(uuid,uuid,text,date,date,text,numeric,jsonb);
DROP FUNCTION IF EXISTS public.create_purchase_order_and_update_inventory(uuid,uuid,text,date,date,text,p_items jsonb);
DROP FUNCTION IF EXISTS public.create_purchase_orders_from_suggestions_tx(uuid, jsonb);
DROP FUNCTION IF EXISTS public.delete_location(uuid, uuid, uuid);
DROP FUNCTION IF EXISTS public.delete_purchase_order(uuid, uuid);
DROP FUNCTION IF EXISTS public.delete_supplier_and_catalogs(uuid, uuid);
DROP FUNCTION IF EXISTS public.get_purchase_order_analytics(uuid);
DROP FUNCTION IF EXISTS public.get_purchase_order_details(uuid, uuid);
DROP FUNCTION IF EXISTS public.get_purchase_orders(uuid, text, integer, integer);
DROP FUNCTION IF EXISTS public.get_supplier_performance(uuid);
DROP FUNCTION IF EXISTS public.receive_purchase_order_items(uuid, jsonb, uuid, uuid);
DROP FUNCTION IF EXISTS public.update_inventory_item_with_lock(uuid,text,integer,text,text,numeric,integer,numeric,text,uuid);
DROP FUNCTION IF EXISTS public.update_po_status(uuid, uuid);
DROP FUNCTION IF EXISTS public.update_purchase_order(uuid,uuid,uuid,text,text,date,date,text,jsonb);
DROP FUNCTION IF EXISTS public.validate_po_financials(uuid, bigint);
DROP FUNCTION IF EXISTS public.batch_upsert_with_transaction(text, jsonb, text[]);

-- =================================================================
-- Step 2: Drop unnecessary tables in the correct order
-- =================================================================
DROP TABLE IF EXISTS public.purchase_order_items;
DROP TABLE IF EXISTS public.purchase_orders;
DROP TABLE IF EXISTS public.reorder_rules;
DROP TABLE IF EXISTS public.supplier_catalogs;
DROP TABLE IF EXISTS public.vendors; -- Old name for suppliers
DROP TABLE IF EXISTS public.locations;


-- =================================================================
-- Step 3: Alter existing tables to remove obsolete columns
-- =================================================================

-- Simplify Inventory table
ALTER TABLE public.inventory DROP COLUMN IF EXISTS on_order_quantity;
ALTER TABLE public.inventory DROP COLUMN IF EXISTS landed_cost;
ALTER TABLE public.inventory DROP COLUMN IF EXISTS location_id;
ALTER TABLE public.inventory DROP COLUMN IF EXISTS conflict_status;
ALTER TABLE public.inventory DROP COLUMN IF EXISTS last_external_sync;
ALTER TABLE public.inventory DROP COLUMN IF EXISTS manual_override;
ALTER TABLE public.inventory DROP COLUMN IF EXISTS expiration_date;
ALTER TABLE public.inventory DROP COLUMN IF EXISTS lot_number;
ALTER TABLE public.inventory ADD COLUMN IF NOT EXISTS supplier_id uuid;
ALTER TABLE public.inventory DROP CONSTRAINT IF EXISTS inventory_supplier_id_fkey;

-- Simplify Customers table
ALTER TABLE public.customers DROP COLUMN IF EXISTS platform;
ALTER TABLE public.customers DROP COLUMN IF EXISTS external_id;
ALTER TABLE public.customers DROP COLUMN IF EXISTS status;

-- Simplify Sales table
ALTER TABLE public.sales DROP COLUMN IF EXISTS created_by;

-- Rename 'vendors' to 'suppliers' if it exists
DO $$
BEGIN
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'vendors') THEN
        ALTER TABLE public.vendors RENAME TO suppliers;
    END IF;
END$$;

-- Add any missing columns to suppliers table just in case
ALTER TABLE public.suppliers ADD COLUMN IF NOT EXISTS notes text;
ALTER TABLE public.suppliers RENAME COLUMN IF EXISTS vendor_name TO name;
ALTER TABLE public.suppliers RENAME COLUMN IF EXISTS contact_info TO email;

-- =================================================================
-- Step 4: Re-create and update necessary tables and constraints
-- =================================================================

-- Create Inventory Ledger table (if it doesn't exist)
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid NOT NULL DEFAULT extensions.uuid_generate_v4(),
    company_id uuid NOT NULL,
    product_id uuid NOT NULL,
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    related_id uuid,
    notes text,
    CONSTRAINT inventory_ledger_pkey PRIMARY KEY (id),
    CONSTRAINT inventory_ledger_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT inventory_ledger_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.inventory(id) ON DELETE CASCADE
);

-- Ensure inventory has a foreign key to suppliers
ALTER TABLE public.inventory ADD CONSTRAINT inventory_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) ON DELETE SET NULL;

-- Ensure inventory sku is unique per company
ALTER TABLE public.inventory DROP CONSTRAINT IF EXISTS inventory_company_id_sku_key;
ALTER TABLE public.inventory ADD CONSTRAINT inventory_company_id_sku_key UNIQUE (company_id, sku);

-- =================================================================
-- Step 5: Create or Replace updated, simplified functions
-- =================================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Create a new company for the new user
    INSERT INTO public.companies (name)
    VALUES (NEW.raw_user_meta_data->>'company_name');

    -- Update the user's app_metadata with the new company_id and role
    UPDATE auth.users
    SET app_metadata = jsonb_set(
        jsonb_set(COALESCE(app_metadata, '{}'::jsonb), '{company_id}', (SELECT id FROM public.companies WHERE name = NEW.raw_user_meta_data->>'company_name')::jsonb),
        '{role}',
        '"Owner"'::jsonb
    )
    WHERE id = NEW.id;

    -- Add user to the public users table
    INSERT INTO public.users (id, company_id, email, role)
    VALUES (
        NEW.id,
        (SELECT id FROM public.companies WHERE name = NEW.raw_user_meta_data->>'company_name'),
        NEW.email,
        'Owner'
    );
    RETURN NEW;
END;
$$;

-- Ensure handle_new_user trigger exists and is correct
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

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
            i.id as product_id,
            i.sku,
            i.name as product_name,
            i.category,
            i.quantity,
            i.cost,
            i.price,
            (i.quantity * i.cost) as total_value,
            i.reorder_point,
            s.name as supplier_name,
            s.id as supplier_id
        FROM public.inventory i
        LEFT JOIN public.suppliers s ON i.supplier_id = s.id AND i.company_id = s.company_id
        WHERE i.company_id = p_company_id
          AND i.deleted_at IS NULL
          AND (p_query IS NULL OR i.name ILIKE '%' || p_query || '%' OR i.sku ILIKE '%' || p_query || '%')
          AND (p_category IS NULL OR i.category = p_category)
          AND (p_supplier_id IS NULL OR i.supplier_id = p_supplier_id)
          AND (p_product_id_filter IS NULL OR i.id = p_product_id_filter)
    )
    SELECT
        (SELECT json_agg(fi.*) FROM (SELECT * FROM filtered_inventory ORDER BY product_name LIMIT p_limit OFFSET p_offset) fi) as items,
        (SELECT count(*) FROM filtered_inventory) as total_count;
END;
$$;


CREATE OR REPLACE FUNCTION public.record_sale_transaction(
    p_company_id uuid,
    p_sale_items jsonb,
    p_customer_name text DEFAULT NULL,
    p_customer_email text DEFAULT NULL,
    p_payment_method text DEFAULT 'other',
    p_notes text DEFAULT NULL,
    p_external_id text DEFAULT NULL
)
RETURNS sales
LANGUAGE plpgsql
AS $$
DECLARE
    new_sale_id uuid;
    new_sale_number text;
    total_sale_amount numeric := 0;
    sale_item jsonb;
    inv_record RECORD;
    new_sale record;
BEGIN
    -- Generate a unique sale number
    new_sale_number := 'SALE-' || to_char(now(), 'YYMMDD') || '-' || (
        SELECT lpad( (count(*) + 1)::text, 4, '0')
        FROM sales
        WHERE created_at::date = current_date AND company_id = p_company_id
    );

    -- Calculate total sale amount
    FOR sale_item IN SELECT * FROM jsonb_array_elements(p_sale_items)
    LOOP
        total_sale_amount := total_sale_amount + ((sale_item->>'quantity')::numeric * (sale_item->>'unit_price')::numeric);
    END LOOP;

    -- Create the sale record
    INSERT INTO public.sales (company_id, sale_number, customer_name, customer_email, total_amount, payment_method, notes, external_id)
    VALUES (p_company_id, new_sale_number, p_customer_name, p_customer_email, total_sale_amount, p_payment_method, p_notes, p_external_id)
    RETURNING id INTO new_sale_id;

    -- Process each sale item
    FOR sale_item IN SELECT * FROM jsonb_array_elements(p_sale_items)
    LOOP
        -- Find the inventory record by SKU
        SELECT * INTO inv_record FROM public.inventory
        WHERE company_id = p_company_id AND sku = sale_item->>'sku';

        IF inv_record IS NULL THEN
            RAISE EXCEPTION 'Product with SKU % not found.', sale_item->>'sku';
        END IF;

        -- Insert into sale_items
        INSERT INTO public.sale_items (sale_id, company_id, sku, product_name, quantity, unit_price, cost_at_time)
        VALUES (new_sale_id, p_company_id, sale_item->>'sku', sale_item->>'product_name', (sale_item->>'quantity')::int, (sale_item->>'unit_price')::numeric, inv_record.cost);

        -- Update inventory quantity and log the change
        UPDATE public.inventory
        SET
            quantity = quantity - (sale_item->>'quantity')::int,
            last_sold_date = current_date
        WHERE id = inv_record.id;

        INSERT INTO public.inventory_ledger (company_id, product_id, change_type, quantity_change, new_quantity, related_id)
        VALUES (p_company_id, inv_record.id, 'sale', -(sale_item->>'quantity')::int, inv_record.quantity - (sale_item->>'quantity')::int, new_sale_id);

    END LOOP;
    
    SELECT * INTO new_sale FROM public.sales WHERE id = new_sale_id;
    RETURN new_sale;
END;
$$;


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
    supplier_name text,
    supplier_id uuid,
    unit_cost integer,
    base_quantity integer
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH sales_velocity AS (
        SELECT
            si.sku,
            (SUM(si.quantity)::decimal / 30) as daily_sales_velocity
        FROM public.sale_items si
        JOIN public.sales s ON si.sale_id = s.id
        WHERE si.company_id = p_company_id
          AND s.created_at >= (now() at time zone p_timezone) - interval '30 days'
        GROUP BY si.sku
    )
    SELECT
        i.id as product_id,
        i.sku,
        i.name as product_name,
        i.quantity as current_quantity,
        i.reorder_point,
        -- Suggested reorder quantity logic
        GREATEST(
            i.reorder_point,
            (COALESCE(sv.daily_sales_velocity, 0) * 30)::integer -- default to 30 days of stock
        ) as suggested_reorder_quantity,
        s.name as supplier_name,
        s.id as supplier_id,
        (i.cost)::integer as unit_cost,
        i.reorder_point as base_quantity
    FROM public.inventory i
    LEFT JOIN public.suppliers s ON i.supplier_id = s.id
    LEFT JOIN sales_velocity sv ON i.sku = sv.sku
    WHERE i.company_id = p_company_id
      AND i.deleted_at IS NULL
      AND i.quantity < i.reorder_point;
END;
$$;


CREATE OR REPLACE FUNCTION public.get_historical_sales(p_company_id uuid, p_skus text[])
RETURNS TABLE(sku text, monthly_sales jsonb)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        s.sku,
        jsonb_agg(s.sales_data)
    FROM (
        SELECT
            si.sku,
            jsonb_build_object(
                'month', to_char(date_trunc('month', s.created_at), 'YYYY-MM'),
                'total_quantity', SUM(si.quantity)
            ) as sales_data
        FROM sale_items si
        JOIN sales s ON si.sale_id = s.id
        WHERE si.company_id = p_company_id AND si.sku = ANY(p_skus)
        GROUP BY si.sku, date_trunc('month', s.created_at)
        ORDER BY date_trunc('month', s.created_at) DESC
        LIMIT 24
    ) as s
    GROUP BY s.sku;
END;
$$;


CREATE OR REPLACE FUNCTION public.get_inventory_analytics(p_company_id uuid)
RETURNS json
LANGUAGE sql STABLE
AS $$
    SELECT json_build_object(
        'total_inventory_value', COALESCE(SUM(i.quantity * i.cost), 0),
        'total_skus', COUNT(i.id),
        'low_stock_items', COUNT(i.id) FILTER (WHERE i.quantity < i.reorder_point),
        'potential_profit', COALESCE(SUM(i.quantity * (i.price - i.cost)), 0)
    )
    FROM public.inventory i
    WHERE i.company_id = p_company_id AND i.deleted_at IS NULL;
$$;

COMMIT;
