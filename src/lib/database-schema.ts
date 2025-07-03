
export const SETUP_SQL_SCRIPT = `-- InvoChat Database Setup Script
-- This script is idempotent and can be safely re-run on an existing database.

-- ========= Part 1: Core Table Definitions =========
-- All tables are created here with their essential columns.
-- Alterations and constraints will be applied in a later section.

create extension if not exists "uuid-ossp" with schema extensions;

CREATE TABLE IF NOT EXISTS public.companies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY,
    company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE,
    email TEXT,
    role TEXT,
    deleted_at TIMESTAMPTZ -- For soft-deleting user association
);

-- Handle pre-existing duplicates before adding unique constraint
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM inventory
        GROUP BY company_id, sku
        HAVING COUNT(*) > 1
    ) THEN
        WITH duplicates AS (
            SELECT id, ROW_NUMBER() OVER (PARTITION BY company_id, sku ORDER BY id) as rn
            FROM inventory
        )
        UPDATE inventory
        SET sku = sku || '-DUP-' || id::text
        WHERE id IN (SELECT id FROM duplicates WHERE rn > 1);
    END IF;
END;
$$;


CREATE TABLE IF NOT EXISTS public.inventory (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku TEXT NOT NULL,
    name TEXT NOT NULL,
    category TEXT,
    quantity INTEGER NOT NULL DEFAULT 0,
    cost NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
    price NUMERIC(10, 2),
    reorder_point INTEGER,
    on_order_quantity INTEGER DEFAULT 0,
    last_sold_date DATE,
    landed_cost NUMERIC(10, 2),
    barcode TEXT,
    location_id UUID,
    version INTEGER DEFAULT 1 NOT NULL, -- For optimistic locking
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_sku_per_company UNIQUE (company_id, sku)
);

CREATE TABLE IF NOT EXISTS public.inventory_adjustments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku TEXT NOT NULL,
    old_quantity INTEGER,
    new_quantity INTEGER NOT NULL,
    change_reason TEXT,
    adjusted_by UUID REFERENCES public.users(id),
    adjusted_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.locations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    address TEXT,
    is_default BOOLEAN DEFAULT false,
    CONSTRAINT unique_location_name_per_company UNIQUE (company_id, name)
);

CREATE TABLE IF NOT EXISTS public.vendors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    vendor_name TEXT NOT NULL,
    contact_info TEXT,
    address TEXT,
    terms TEXT,
    account_number TEXT,
    CONSTRAINT unique_vendor_name_per_company UNIQUE (company_id, vendor_name)
);

CREATE TABLE IF NOT EXISTS public.customers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform TEXT,
    external_id TEXT,
    customer_name TEXT NOT NULL,
    email TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_id UUID,
    sale_date TIMESTAMP WITH TIME ZONE NOT NULL,
    total_amount NUMERIC(10, 2) NOT NULL,
    sales_channel TEXT,
    platform TEXT,
    external_id TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.order_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sale_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    sku TEXT NOT NULL,
    quantity INTEGER NOT NULL,
    unit_price NUMERIC(10, 2) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id UUID REFERENCES public.vendors(id) ON DELETE SET NULL,
    po_number TEXT NOT NULL,
    status TEXT DEFAULT 'draft',
    order_date DATE NOT NULL,
    expected_date DATE,
    total_amount NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE,
    CONSTRAINT unique_po_number_per_company UNIQUE (company_id, po_number)
);

CREATE TABLE IF NOT EXISTS public.purchase_order_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    po_id UUID NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    sku TEXT NOT NULL,
    quantity_ordered INTEGER NOT NULL,
    quantity_received INTEGER NOT NULL DEFAULT 0,
    unit_cost NUMERIC(10, 2) NOT NULL,
    tax_rate NUMERIC(5, 4) DEFAULT 0
);

CREATE TABLE IF NOT EXISTS public.integrations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform TEXT NOT NULL,
    shop_domain TEXT,
    shop_name TEXT,
    is_active BOOLEAN DEFAULT false,
    last_sync_at TIMESTAMP WITH TIME ZONE,
    sync_status TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE,
    CONSTRAINT unique_platform_per_company UNIQUE (company_id, platform)
);

CREATE TABLE IF NOT EXISTS public.sync_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id UUID NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    sync_type TEXT NOT NULL,
    status TEXT NOT NULL,
    records_synced INTEGER,
    error_message TEXT,
    started_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    completed_at TIMESTAMP WITH TIME ZONE
);

CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id UUID PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days INTEGER DEFAULT 90,
    overstock_multiplier NUMERIC DEFAULT 3,
    high_value_threshold NUMERIC DEFAULT 1000,
    fast_moving_days INTEGER DEFAULT 30,
    predictive_stock_days INTEGER DEFAULT 7,
    currency TEXT DEFAULT 'USD',
    timezone TEXT DEFAULT 'UTC',
    tax_rate NUMERIC DEFAULT 0,
    theme_primary_color TEXT DEFAULT '256 75% 61%',
    theme_background_color TEXT DEFAULT '222 83% 4%',
    theme_accent_color TEXT DEFAULT '217 33% 17%',
    custom_rules JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.channel_fees (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    channel_name TEXT NOT NULL,
    percentage_fee NUMERIC(5, 4) NOT NULL,
    fixed_fee NUMERIC(10, 2) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE,
    CONSTRAINT unique_channel_per_company UNIQUE (company_id, channel_name)
);

CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid,
    notes text
);

CREATE TABLE IF NOT EXISTS public.supplier_catalogs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    supplier_id UUID NOT NULL REFERENCES public.vendors(id) ON DELETE CASCADE,
    sku TEXT NOT NULL,
    supplier_sku TEXT,
    product_name TEXT,
    unit_cost NUMERIC(10, 2) NOT NULL,
    moq INTEGER DEFAULT 1,
    lead_time_days INTEGER,
    is_active BOOLEAN DEFAULT true,
    CONSTRAINT unique_supplier_sku UNIQUE (supplier_id, sku)
);

CREATE TABLE IF NOT EXISTS public.reorder_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku TEXT NOT NULL,
    rule_type TEXT DEFAULT 'manual',
    min_stock INTEGER,
    max_stock INTEGER,
    reorder_quantity INTEGER,
    CONSTRAINT unique_reorder_rule_sku UNIQUE (company_id, sku)
);

CREATE TABLE IF NOT EXISTS public.audit_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL,
  user_id uuid NOT NULL,
  action text NOT NULL CHECK (action IN ('INSERT', 'UPDATE', 'DELETE')),
  table_name text NOT NULL,
  record_id text,
  old_data jsonb,
  new_data jsonb,
  query_text text,
  ip_address inet,
  created_at timestamptz DEFAULT now()
);

-- ========= Part 2: Schema Migrations & Alterations =========
-- This section ensures older schemas are updated correctly by adding columns if they don't exist.

-- Alterations for integration fields
ALTER TABLE public.inventory ADD COLUMN IF NOT EXISTS source_platform TEXT;
ALTER TABLE public.inventory ADD COLUMN IF NOT EXISTS external_product_id TEXT;
ALTER TABLE public.inventory ADD COLUMN IF NOT EXISTS external_variant_id TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS platform TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS external_id TEXT;
ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS platform TEXT;
ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS external_id TEXT;
ALTER TABLE public.customers ADD CONSTRAINT unique_customer_per_platform UNIQUE (company_id, platform, external_id);
ALTER TABLE public.orders ADD CONSTRAINT unique_order_per_platform UNIQUE (company_id, platform, external_id);


-- Add foreign key constraint from inventory to locations
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_inventory_location' AND conrelid = 'public.inventory'::regclass
    ) THEN
        ALTER TABLE public.inventory ADD CONSTRAINT fk_inventory_location
        FOREIGN KEY (location_id) REFERENCES public.locations(id) ON DELETE SET NULL;
    END IF;
END;
$$;

-- Add foreign key constraint from orders to customers
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_orders_customer' AND conrelid = 'public.orders'::regclass
    ) THEN
        ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS customer_id UUID;
        ALTER TABLE public.orders ADD CONSTRAINT fk_orders_customer
        FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE SET NULL;
    END IF;
END;
$$;

-- ========= Part 3: Functions & Triggers =========

-- Function to handle new user creation
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_company_id UUID;
  user_role TEXT := 'Owner'; -- New users are always owners of their new company
  new_company_name TEXT;
BEGIN
  -- Create a new company for the new user
  new_company_name := COALESCE(new.raw_user_meta_data->>'company_name', 'My Company');
  INSERT INTO public.companies (name)
  VALUES (new_company_name)
  RETURNING id INTO new_company_id;

  -- Insert a corresponding record into the public.users table for application use
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (new.id, new_company_id, new.email, user_role);

  -- Create default settings for the new company
  INSERT INTO public.company_settings (company_id)
  VALUES (new_company_id)
  ON CONFLICT (company_id) DO NOTHING;

  -- Update the user's app_metadata with the new company ID and their role
  -- This is the critical step that makes the user's session valid
  UPDATE auth.users
  SET app_metadata = jsonb_set(
      COALESCE(app_metadata, '{}'::jsonb),
      '{role}',
      to_jsonb(user_role)
  )
  WHERE id = new.id;
  
   UPDATE auth.users
  SET app_metadata = jsonb_set(
      COALESCE(app_metadata, '{}'::jsonb),
      '{company_id}',
      to_jsonb(new_company_id)
  )
  WHERE id = new.id;

  RETURN new;
END;
$$;


-- Drop existing trigger to avoid duplicates, then re-create it
DROP TRIGGER IF EXISTS on_auth_user_created on auth.users;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();


-- Secure batch upsert function
CREATE OR REPLACE FUNCTION public.batch_upsert_with_transaction(
  p_table_name text,
  p_records jsonb,
  p_conflict_columns text[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  company_id_from_jwt uuid;
  sanitized_records jsonb;
  update_set_clause text;
  query text;
BEGIN
  -- Whitelist allowed tables for safety
  IF p_table_name NOT IN ('inventory', 'vendors', 'supplier_catalogs', 'reorder_rules', 'locations', 'customers', 'orders', 'order_items') THEN
    RAISE EXCEPTION 'Invalid table name provided for batch upsert: %', p_table_name;
  END IF;

  -- Get the company_id from the authenticated user's JWT
  company_id_from_jwt := (auth.jwt() -> 'app_metadata' ->> 'company_id')::uuid;
  
  -- Rebuild the entire JSONB array, forcing the correct company_id on every record
  SELECT jsonb_agg(jsonb_set(elem, '{company_id}', to_jsonb(company_id_from_jwt)))
  INTO sanitized_records
  FROM jsonb_array_elements(p_records) AS elem;

  -- Dynamically build the UPDATE SET clause for the ON CONFLICT action
  update_set_clause := (
    SELECT string_agg(format('%I = excluded.%I', key, key), ', ')
    FROM jsonb_object_keys(sanitized_records -> 0) AS key
    WHERE NOT (key = ANY(p_conflict_columns))
  );

  -- Build the final query
  query := format(
    'INSERT INTO %I SELECT * FROM jsonb_populate_recordset(null::%I, $1) ON CONFLICT (%s) DO UPDATE SET %s;',
    p_table_name, p_table_name, array_to_string(p_conflict_columns, ', '), update_set_clause
  );
  
  -- Execute the query with the sanitized records
  EXECUTE query USING sanitized_records;
END;
$$;


-- Changed from Materialized View to a regular table for per-company refreshes
CREATE TABLE IF NOT EXISTS public.company_dashboard_metrics (
  company_id UUID PRIMARY KEY,
  total_skus BIGINT,
  inventory_value NUMERIC,
  low_stock_count BIGINT,
  last_refreshed TIMESTAMPTZ
);


CREATE OR REPLACE FUNCTION public.refresh_dashboard_metrics_for_company(p_company_id uuid)
RETURNS VOID AS $$
BEGIN
    DELETE FROM company_dashboard_metrics WHERE company_id = p_company_id;
    
    INSERT INTO company_dashboard_metrics (
        company_id, total_skus, inventory_value, low_stock_count, last_refreshed
    )
    SELECT 
        p_company_id,
        COUNT(DISTINCT i.sku),
        SUM(i.quantity * i.cost),
        COUNT(CASE WHEN i.quantity <= i.reorder_point AND i.reorder_point > 0 THEN 1 END),
        NOW()
    FROM inventory i
    WHERE i.company_id = p_company_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Function to securely delete a location and unassign inventory
create or replace function public.delete_location_and_unassign_inventory(p_location_id uuid, p_company_id uuid)
returns void language plpgsql security definer as $$
begin
  if (p_company_id != (auth.jwt() -> 'app_metadata' ->> 'company_id')::uuid) then
    raise exception 'Unauthorized';
  end if;
  update public.inventory set location_id = null where location_id = p_location_id and company_id = p_company_id;
  delete from public.locations where id = p_location_id and company_id = p_company_id;
end;
$$;

-- Function to securely delete a supplier and their catalog items
create or replace function public.delete_supplier_and_catalogs(p_supplier_id uuid, p_company_id uuid)
returns void language plpgsql security definer as $$
begin
  if (p_company_id != (auth.jwt() -> 'app_metadata' ->> 'company_id')::uuid) then
    raise exception 'Unauthorized';
  end if;
  if exists (select 1 from public.purchase_orders where supplier_id = p_supplier_id and company_id = p_company_id) then
    raise exception 'Cannot delete supplier with active purchase orders.';
  end if;
  delete from public.supplier_catalogs where supplier_id = p_supplier_id;
  delete from public.vendors where id = p_supplier_id and company_id = p_company_id;
end;
$$;

CREATE OR REPLACE FUNCTION public.get_unified_inventory(p_company_id uuid, p_query text, p_category text, p_location_id uuid, p_supplier_id uuid, p_limit integer, p_offset integer)
RETURNS json LANGUAGE plpgsql SECURITY INVOKER AS $$
DECLARE 
    result_json json;
    total_count integer;
    filtered_skus TEXT[];
BEGIN
    -- Step 1: Get the SKUs that match the filter criteria
    SELECT array_agg(i.sku) INTO filtered_skus
    FROM inventory i
    LEFT JOIN (
        SELECT DISTINCT ON (sc.sku) sc.sku, sc.supplier_id
        FROM supplier_catalogs sc
        JOIN vendors v ON sc.supplier_id = v.id AND v.company_id = p_company_id
    ) as primary_supplier ON i.sku = primary_supplier.sku
    WHERE i.company_id = p_company_id
    AND (p_query IS NULL OR p_query = '' OR (i.name ILIKE '%' || p_query || '%' OR i.sku ILIKE '%' || p_query || '%'))
    AND (p_category IS NULL OR p_category = '' OR i.category = p_category)
    AND (p_location_id IS NULL OR i.location_id = p_location_id)
    AND (p_supplier_id IS NULL OR primary_supplier.supplier_id = p_supplier_id);
    
    total_count := COALESCE(array_length(filtered_skus, 1), 0);

    -- Step 2: Fetch the full data for the paginated set of SKUs
    SELECT json_build_object(
        'items', COALESCE(json_agg(t), '[]'::json),
        'totalCount', total_count
    )
    INTO result_json
    FROM (
        SELECT
            i.sku, i.name as product_name, i.category, i.quantity, i.cost, i.price,
            (i.quantity * i.cost) as total_value, i.reorder_point, i.on_order_quantity,
            i.landed_cost, i.barcode, i.location_id, l.name as location_name,
            COALESCE(ms.units_sold, 0) as monthly_units_sold,
            ((i.price - COALESCE(i.landed_cost, i.cost)) * COALESCE(ms.units_sold, 0)) as monthly_profit
        FROM inventory i
        LEFT JOIN locations l ON i.location_id = l.id AND l.company_id = i.company_id
        LEFT JOIN (
             SELECT oi.sku, SUM(oi.quantity) as units_sold
             FROM order_items oi JOIN orders o ON oi.sale_id = o.id
             WHERE o.company_id = p_company_id AND o.sale_date >= CURRENT_DATE - INTERVAL '30 days'
             GROUP BY oi.sku
        ) ms ON i.sku = ms.sku
        WHERE i.sku = ANY(filtered_skus)
        ORDER BY i.name
        LIMIT p_limit
        OFFSET p_offset
    ) t;

    RETURN result_json;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_historical_sales(p_company_id uuid, p_skus text[])
RETURNS json LANGUAGE plpgsql SECURITY INVOKER AS $$
DECLARE result_json json;
BEGIN
    SELECT coalesce(json_agg(t), '[]'::json) INTO result_json
    FROM (
        SELECT sku, json_agg(json_build_object('month', sales_month, 'total_quantity', total_quantity) ORDER BY sales_month) as monthly_sales
        FROM (
            SELECT oi.sku, TO_CHAR(DATE_TRUNC('month', o.sale_date), 'YYYY-MM') as sales_month, SUM(oi.quantity) as total_quantity
            FROM order_items oi JOIN orders o ON oi.sale_id = o.id
            WHERE o.company_id = p_company_id AND oi.sku = ANY(p_skus) AND o.sale_date >= CURRENT_DATE - INTERVAL '24 months'
            GROUP BY oi.sku, DATE_TRUNC('month', o.sale_date)
        ) as monthly_data
        GROUP BY sku
    ) t;
    RETURN result_json;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_inventory_ledger_entry(p_company_id uuid, p_sku text, p_change_type text, p_quantity_change integer, p_related_id uuid DEFAULT null, p_notes text DEFAULT null)
RETURNS void AS $$
DECLARE current_quantity_val int;
BEGIN
    SELECT quantity INTO current_quantity_val FROM public.inventory WHERE sku = p_sku AND company_id = p_company_id;
    INSERT INTO public.inventory_ledger (company_id, sku, change_type, quantity_change, new_quantity, related_id, notes)
    VALUES (p_company_id, p_sku, p_change_type, p_quantity_change, current_quantity_val, p_related_id, p_notes);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.process_sales_order_inventory(p_order_id uuid, p_company_id uuid)
RETURNS void AS $$
DECLARE order_item record;
BEGIN
    FOR order_item IN SELECT sku, quantity FROM public.order_items WHERE sale_id = p_order_id LOOP
        UPDATE public.inventory SET quantity = quantity - order_item.quantity WHERE sku = order_item.sku AND company_id = p_company_id;
        PERFORM public.create_inventory_ledger_entry(p_company_id, order_item.sku, 'sale', -order_item.quantity, p_order_id);
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Hardened receive_purchase_order_items function
CREATE OR REPLACE FUNCTION public.receive_purchase_order_items(p_po_id uuid, p_items_to_receive jsonb, p_company_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE 
    item RECORD; 
    current_po_status TEXT; 
    total_ordered INTEGER; 
    total_received INTEGER;
    v_already_received INTEGER;
    v_ordered_quantity INTEGER;
    v_can_receive INTEGER;
BEGIN
    -- Validate PO belongs to company
    IF NOT EXISTS (SELECT 1 FROM purchase_orders WHERE id = p_po_id AND company_id = p_company_id) THEN
        RAISE EXCEPTION 'Purchase order not found or access denied';
    END IF;

    FOR item IN SELECT * FROM jsonb_to_recordset(p_items_to_receive) AS x(sku TEXT, quantity_to_receive INTEGER) LOOP
        -- Get ordered and already received quantities
        SELECT poi.quantity_ordered, COALESCE(poi.quantity_received, 0)
        INTO v_ordered_quantity, v_already_received
        FROM purchase_order_items poi
        WHERE poi.po_id = p_po_id AND poi.sku = item.sku;
        
        IF NOT FOUND THEN
            RAISE EXCEPTION 'SKU % not found in this purchase order.', item.sku;
        END IF;

        v_can_receive := v_ordered_quantity - v_already_received;
        
        -- Add validation to prevent over-receiving
        IF item.quantity_to_receive > v_can_receive THEN
            RAISE EXCEPTION 'Cannot receive % units of SKU %. Only % are remaining to be received.', item.quantity_to_receive, item.sku, v_can_receive;
        END IF;
        
        IF item.quantity_to_receive > 0 THEN
            UPDATE public.purchase_order_items SET quantity_received = quantity_received + item.quantity_to_receive WHERE po_id = p_po_id AND sku = item.sku;
            UPDATE public.inventory SET quantity = quantity + item.quantity_to_receive, on_order_quantity = on_order_quantity - item.quantity_to_receive, updated_at = NOW() WHERE company_id = p_company_id AND sku = item.sku;
            PERFORM public.create_inventory_ledger_entry(p_company_id, item.sku, 'purchase_order_received', item.quantity_to_receive, p_po_id);
        END IF;
    END LOOP;

    -- Update overall PO status
    SELECT SUM(quantity_ordered), SUM(quantity_received) INTO total_ordered, total_received FROM public.purchase_order_items WHERE po_id = p_po_id;
    
    IF total_received >= total_ordered THEN current_po_status := 'received';
    ELSIF total_received > 0 THEN current_po_status := 'partial';
    ELSE SELECT status INTO current_po_status FROM public.purchase_orders WHERE id = p_po_id;
    END IF;

    UPDATE public.purchase_orders SET status = current_po_status, updated_at = NOW() WHERE id = p_po_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_inventory_ledger_for_sku(p_company_id uuid, p_sku text)
RETURNS json LANGUAGE plpgsql SECURITY INVOKER AS $$
DECLARE result_json json;
BEGIN
    SELECT coalesce(json_agg(t), '[]'::json) INTO result_json
    FROM ( SELECT * FROM public.inventory_ledger WHERE company_id = p_company_id AND sku = p_sku ORDER BY created_at DESC LIMIT 100 ) t;
    RETURN result_json;
END;
$$;


CREATE OR REPLACE FUNCTION public.create_purchase_order_and_update_inventory(p_company_id uuid, p_supplier_id uuid, p_po_number text, p_order_date date, p_total_amount numeric, p_items jsonb, p_expected_date date DEFAULT NULL, p_notes text DEFAULT NULL)
RETURNS public.purchase_orders LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE new_po purchase_orders; item jsonb;
BEGIN
    INSERT INTO public.purchase_orders (company_id, supplier_id, po_number, order_date, expected_date, notes, total_amount, status)
    VALUES (p_company_id, p_supplier_id, p_po_number, p_order_date, p_expected_date, p_notes, p_total_amount, 'draft')
    RETURNING * INTO new_po;

    FOR item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        INSERT INTO public.purchase_order_items (po_id, sku, quantity_ordered, unit_cost)
        VALUES (new_po.id, item->>'sku', (item->>'quantity_ordered')::integer, (item->>'unit_cost')::numeric);

        UPDATE public.inventory SET on_order_quantity = on_order_quantity + (item->>'quantity_ordered')::integer
        WHERE company_id = p_company_id AND sku = item->>'sku';
    END LOOP;
    RETURN new_po;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_purchase_order(p_po_id uuid, p_company_id uuid, p_supplier_id uuid, p_po_number text, p_status text, p_order_date date, p_items jsonb, p_expected_date date DEFAULT NULL, p_notes text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    new_total_amount numeric;
    item_update jsonb;
    item_from_db purchase_order_items;
    diff integer;
BEGIN
    new_total_amount := (SELECT SUM((item->>'quantity_ordered')::numeric * (item->>'unit_cost')::numeric) FROM jsonb_array_elements(p_items) as item);

    UPDATE public.purchase_orders SET supplier_id = p_supplier_id, po_number = p_po_number, status = p_status, order_date = p_order_date, expected_date = p_expected_date, notes = p_notes, total_amount = new_total_amount, updated_at = NOW()
    WHERE id = p_po_id AND company_id = p_company_id;

    -- Adjust inventory for removed items
    FOR item_from_db IN SELECT * FROM public.purchase_order_items WHERE po_id = p_po_id AND sku NOT IN (SELECT value->>'sku' FROM jsonb_array_elements_text(p_items)) LOOP
        UPDATE public.inventory SET on_order_quantity = on_order_quantity - (item_from_db.quantity_ordered - item_from_db.quantity_received)
        WHERE company_id = p_company_id AND sku = item_from_db.sku;
    END LOOP;

    DELETE FROM public.purchase_order_items WHERE po_id = p_po_id AND sku NOT IN (SELECT value->>'sku' FROM jsonb_array_elements_text(p_items));

    -- Upsert new/updated items
    FOR item_update IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        SELECT * INTO item_from_db FROM public.purchase_order_items WHERE po_id = p_po_id AND sku = item_update->>'sku';

        IF FOUND THEN
            -- Item exists, update it and adjust inventory by the difference
            diff := (item_update->>'quantity_ordered')::integer - item_from_db.quantity_ordered;
            UPDATE public.purchase_order_items SET quantity_ordered = (item_update->>'quantity_ordered')::integer, unit_cost = (item_update->>'unit_cost')::numeric
            WHERE id = item_from_db.id;
            UPDATE public.inventory SET on_order_quantity = on_order_quantity + diff WHERE company_id = p_company_id AND sku = item_update->>'sku';
        ELSE
            -- New item, insert it and add to inventory on_order_quantity
            INSERT INTO public.purchase_order_items (po_id, sku, quantity_ordered, unit_cost)
            VALUES (p_po_id, item_update->>'sku', (item_update->>'quantity_ordered')::integer, (item_update->>'unit_cost')::numeric);
            UPDATE public.inventory SET on_order_quantity = on_order_quantity + (item_update->>'quantity_ordered')::integer
            WHERE company_id = p_company_id AND sku = item_update->>'sku';
        END IF;
    END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_purchase_order(p_po_id uuid, p_company_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE item record;
BEGIN
    FOR item IN SELECT sku, quantity_ordered, quantity_received FROM public.purchase_order_items WHERE po_id = p_po_id LOOP
        UPDATE public.inventory SET on_order_quantity = on_order_quantity - (item.quantity_ordered - item.quantity_received)
        WHERE company_id = p_company_id AND sku = item.sku;
    END LOOP;

    DELETE FROM public.purchase_orders WHERE id = p_po_id AND company_id = p_company_id;
END;
$$;

-- Secure function to prevent cross-tenant references
CREATE OR REPLACE FUNCTION validate_same_company_reference()
RETURNS TRIGGER AS $$
DECLARE
  ref_company_id uuid;
  current_company_id uuid;
BEGIN
  current_company_id := NEW.company_id;
  
  -- Check vendor reference (for purchase_orders)
  IF TG_TABLE_NAME = 'purchase_orders' AND NEW.supplier_id IS NOT NULL THEN
    SELECT company_id INTO ref_company_id FROM vendors WHERE id = NEW.supplier_id;
    IF ref_company_id != current_company_id THEN
      RAISE EXCEPTION 'Cannot reference a vendor from a different company.';
    END IF;
  END IF;

  -- Check inventory location reference
  IF TG_TABLE_NAME = 'inventory' AND NEW.location_id IS NOT NULL THEN
    SELECT company_id INTO ref_company_id FROM locations WHERE id = NEW.location_id;
    IF ref_company_id != current_company_id THEN
        RAISE EXCEPTION 'Cannot assign to a location from a different company.';
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for audit logging
CREATE OR REPLACE FUNCTION audit_trigger()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO audit_log (
    company_id,
    user_id,
    action,
    table_name,
    record_id,
    old_data,
    new_data,
    ip_address
  ) VALUES (
    COALESCE(NEW.company_id, OLD.company_id),
    auth.uid(),
    TG_OP,
    TG_TABLE_NAME,
    COALESCE((NEW.id)::text, (OLD.id)::text),
    CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN row_to_json(OLD) ELSE NULL END,
    CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN row_to_json(NEW) ELSE NULL END,
    inet_client_addr()
  );
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- ========= Part 4: Row-Level Security (RLS) Policies =========

-- This function is a helper for RLS policies
CREATE OR REPLACE FUNCTION public.current_user_company_id()
RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT (auth.jwt()->'app_metadata'->>'company_id')::uuid;
$$;

DO $$
DECLARE
    t_name TEXT;
BEGIN
    FOR t_name IN
        SELECT table_name FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_name IN (
            'users', 'company_settings', 'inventory', 'customers',
            'orders', 'vendors', 'reorder_rules', 'purchase_orders', 'integrations',
            'channel_fees', 'locations', 'inventory_ledger', 'audit_log', 'sync_logs'
          )
    LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', t_name);
        EXECUTE format('DROP POLICY IF EXISTS "Users can manage data for their own company" ON public.%I;', t_name);
        EXECUTE format('CREATE POLICY "Users can manage data for their own company" ON public.%I FOR ALL USING (company_id = public.current_user_company_id());', t_name);
    END LOOP;
END;
$$;

ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can manage order items for their own company" ON public.order_items;
CREATE POLICY "Users can manage order items for their own company" ON public.order_items FOR ALL USING ((SELECT company_id FROM public.orders WHERE id = sale_id) = public.current_user_company_id());

ALTER TABLE public.purchase_order_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can manage PO items for their own company" ON public.purchase_order_items;
CREATE POLICY "Users can manage PO items for their own company" ON public.purchase_order_items FOR ALL USING ((SELECT company_id FROM public.purchase_orders WHERE id = po_id) = public.current_user_company_id());

ALTER TABLE public.supplier_catalogs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can manage supplier catalogs for their own company" ON public.supplier_catalogs;
CREATE POLICY "Users can manage supplier catalogs for their own company" ON public.supplier_catalogs FOR ALL USING ((SELECT company_id FROM public.vendors WHERE id = supplier_id) = public.current_user_company_id());

ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can see their own company" ON public.companies;
CREATE POLICY "Users can see their own company" ON public.companies FOR SELECT USING (id = public.current_user_company_id());


-- ========= Part 5: Apply Triggers =========
DROP TRIGGER IF EXISTS validate_purchase_order_refs ON public.purchase_orders;
CREATE TRIGGER validate_purchase_order_refs
  BEFORE INSERT OR UPDATE ON public.purchase_orders
  FOR EACH ROW EXECUTE FUNCTION validate_same_company_reference();

DROP TRIGGER IF EXISTS validate_inventory_location_ref ON public.inventory;
CREATE TRIGGER validate_inventory_location_ref
  BEFORE INSERT OR UPDATE ON public.inventory
  FOR EACH ROW EXECUTE FUNCTION validate_same_company_reference();

-- Apply Audit Triggers
DROP TRIGGER IF EXISTS audit_inventory_changes ON public.inventory;
CREATE TRIGGER audit_inventory_changes AFTER INSERT OR UPDATE OR DELETE ON public.inventory
  FOR EACH ROW EXECUTE FUNCTION audit_trigger();

DROP TRIGGER IF EXISTS audit_po_changes ON public.purchase_orders;
CREATE TRIGGER audit_po_changes AFTER INSERT OR UPDATE OR DELETE ON public.purchase_orders
  FOR EACH ROW EXECUTE FUNCTION audit_trigger();
  
DROP TRIGGER IF EXISTS audit_settings_changes ON public.company_settings;
CREATE TRIGGER audit_settings_changes AFTER UPDATE ON public.company_settings
  FOR EACH ROW EXECUTE FUNCTION audit_trigger();

`;
