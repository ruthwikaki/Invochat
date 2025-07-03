
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
    role TEXT
);

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
    CONSTRAINT unique_sku_per_company UNIQUE (company_id, sku)
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
    customer_name TEXT NOT NULL,
    email TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sale_date TIMESTAMP WITH TIME ZONE NOT NULL,
    total_amount NUMERIC(10, 2) NOT NULL,
    sales_channel TEXT,
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

CREATE TABLE IF NOT EXISTS public.query_patterns (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    user_question text NOT NULL,
    successful_sql_query text NOT NULL,
    usage_count integer DEFAULT 1,
    last_used_at timestamp with time zone DEFAULT now(),
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT unique_question_per_company UNIQUE (company_id, user_question)
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

CREATE TABLE IF NOT EXISTS public.notification_preferences (
  user_id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  email_daily_digest BOOLEAN DEFAULT TRUE,
  email_low_stock BOOLEAN DEFAULT TRUE,
  sms_critical_alerts BOOLEAN DEFAULT FALSE,
  sms_phone_number TEXT,
  digest_time TIME WITH TIME ZONE DEFAULT '07:00:00+00'
);

-- ========= Part 2: Schema Migrations & Alterations =========
-- This section ensures older schemas are updated correctly by adding columns if they don't exist.

ALTER TABLE public.inventory ADD COLUMN IF NOT EXISTS source_platform TEXT;
ALTER TABLE public.inventory ADD COLUMN IF NOT EXISTS external_product_id TEXT;
ALTER TABLE public.inventory ADD COLUMN IF NOT EXISTS external_variant_id TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS platform TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS external_id TEXT;
ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS platform TEXT;
ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS external_id TEXT;

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
AS $$
DECLARE
  new_company_id UUID;
  user_role TEXT;
  company_name_from_meta TEXT;
  company_id_from_meta_text TEXT;
BEGIN
  -- Extract values from raw_user_meta_data, which is of type jsonb
  company_name_from_meta := new.raw_user_meta_data->>'company_name';
  company_id_from_meta_text := new.raw_user_meta_data->>'company_id';

  -- If a company ID was passed during signup (e.g., from an invite), use it.
  IF company_id_from_meta_text IS NOT NULL THEN
    new_company_id := company_id_from_meta_text::UUID;
    user_role := 'Member'; -- Invited users start as Members
  ELSE
    -- Otherwise, create a new company for the new user.
    INSERT INTO public.companies (name)
    VALUES (COALESCE(company_name_from_meta, 'My Company'))
    RETURNING id INTO new_company_id;
    user_role := 'Owner';
  END IF;

  -- Update the user's app_metadata with the company ID and role
  UPDATE auth.users
  SET app_metadata = jsonb_set(
      jsonb_set(COALESCE(app_metadata, '{}'::jsonb), '{company_id}', to_jsonb(new_company_id)),
      '{role}', to_jsonb(user_role)
  )
  WHERE id = new.id;

  -- Insert a corresponding record into the public.users table
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (new.id, new_company_id, new.email, user_role);

  RETURN new;
END;
$$;


-- Drop existing trigger to avoid duplicates, then re-create it
DROP TRIGGER IF EXISTS on_auth_user_created on auth.users;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();


create or replace function public.execute_dynamic_query(query_text text)
returns json
language plpgsql
as $$
declare
  result_json json;
begin
  execute format('select coalesce(json_agg(t), ''[]'') from (%s) t', query_text)
  into result_json;
  return result_json;
end;
$$;

create or replace function public.batch_upsert_with_transaction(
  p_table_name text,
  p_records jsonb,
  p_conflict_columns text[]
)
returns void
language plpgsql
security definer
as $$
declare
  update_set_clause text := (
    select string_agg(format('%I = excluded.%I', key, key), ', ')
    from jsonb_object_keys(p_records -> 0) as key
    where not (key = any(p_conflict_columns))
  );
  query text;
begin
  if p_table_name not in ('inventory', 'vendors', 'supplier_catalogs', 'reorder_rules', 'locations', 'customers', 'orders', 'order_items') then
    raise exception 'Invalid table name provided for batch upsert: %', p_table_name;
  end if;
  query := format(
    'INSERT INTO %I SELECT * FROM jsonb_populate_recordset(null::%I, $1) ON CONFLICT (%s) DO UPDATE SET %s;',
    p_table_name, p_table_name, array_to_string(p_conflict_columns, ', '), update_set_clause
  );
  execute query using p_records;
exception
    when unique_violation then
        raise notice 'A unique constraint violation occurred during batch upsert on table %. Details: %', p_table_name, SQLERRM;
        raise exception 'Duplicate entry found in CSV. %', SQLERRM;
end;
$$;

CREATE MATERIALIZED VIEW IF NOT EXISTS public.company_dashboard_metrics AS
SELECT
  i.company_id,
  COUNT(DISTINCT i.sku) as total_skus,
  SUM(i.quantity * i.cost) as inventory_value,
  COUNT(CASE WHEN i.quantity <= i.reorder_point AND i.reorder_point > 0 THEN 1 END) as low_stock_count
FROM inventory i
GROUP BY i.company_id
WITH DATA;

CREATE UNIQUE INDEX IF NOT EXISTS idx_company_dashboard_metrics_company_id
ON public.company_dashboard_metrics(company_id);

CREATE OR REPLACE FUNCTION public.refresh_dashboard_metrics()
RETURNS void
LANGUAGE sql
AS $$
  REFRESH MATERIALIZED VIEW CONCURRENTLY public.company_dashboard_metrics;
$$;

create or replace function public.delete_location_and_unassign_inventory(p_location_id uuid, p_company_id uuid)
returns void language plpgsql security definer as $$
begin
  update public.inventory set location_id = null where location_id = p_location_id and company_id = p_company_id;
  delete from public.locations where id = p_location_id and company_id = p_company_id;
end;
$$;

create or replace function public.delete_supplier_and_catalogs(p_supplier_id uuid, p_company_id uuid)
returns void language plpgsql security definer as $$
begin
  if exists (select 1 from public.purchase_orders where supplier_id = p_supplier_id and company_id = p_company_id) then
    raise exception 'Cannot delete supplier with active purchase orders.';
  end if;
  delete from public.supplier_catalogs where supplier_id = p_supplier_id;
  delete from public.vendors where id = p_supplier_id and company_id = p_company_id;
end;
$$;

CREATE OR REPLACE FUNCTION public.get_unified_inventory(p_company_id uuid, p_query text, p_category text, p_location_id uuid, p_supplier_id uuid)
RETURNS json LANGUAGE plpgsql AS $$
DECLARE result_json json;
BEGIN
    WITH monthly_sales AS (
        SELECT oi.sku, SUM(oi.quantity) as units_sold
        FROM order_items oi JOIN orders o ON oi.sale_id = o.id
        WHERE o.company_id = p_company_id AND o.sale_date >= CURRENT_DATE - INTERVAL '30 days'
        GROUP BY oi.sku
    )
    SELECT coalesce(json_agg(t), '[]') INTO result_json
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
            SELECT DISTINCT ON (sc.sku) sc.sku, sc.supplier_id 
            FROM supplier_catalogs sc
            JOIN vendors v ON sc.supplier_id = v.id AND v.company_id = p_company_id
        ) as primary_supplier ON i.sku = primary_supplier.sku
        LEFT JOIN monthly_sales ms ON i.sku = ms.sku
        WHERE i.company_id = p_company_id
        AND (p_query IS NULL OR p_query = '' OR (i.name ILIKE '%' || p_query || '%' OR i.sku ILIKE '%' || p_query || '%'))
        AND (p_category IS NULL OR p_category = '' OR i.category = p_category)
        AND (p_location_id IS NULL OR i.location_id = p_location_id)
        AND (p_supplier_id IS NULL OR primary_supplier.supplier_id = p_supplier_id)
        ORDER BY i.name
    ) t;
    RETURN result_json;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_historical_sales(p_company_id uuid, p_skus text[])
RETURNS json LANGUAGE plpgsql AS $$
DECLARE result_json json;
BEGIN
    SELECT coalesce(json_agg(t), '[]') INTO result_json
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

CREATE OR REPLACE FUNCTION public.receive_purchase_order_items(p_po_id uuid, p_items_to_receive jsonb, p_company_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE item jsonb; current_po_status text; total_ordered integer; total_received integer;
BEGIN
    FOR item IN SELECT * FROM jsonb_array_elements(p_items_to_receive) LOOP
        UPDATE public.purchase_order_items SET quantity_received = quantity_received + (item->>'quantity_to_receive')::integer WHERE po_id = p_po_id AND sku = item->>'sku';
        UPDATE public.inventory SET quantity = quantity + (item->>'quantity_to_receive')::integer, on_order_quantity = on_order_quantity - (item->>'quantity_to_receive')::integer WHERE company_id = p_company_id AND sku = item->>'sku';
        PERFORM public.create_inventory_ledger_entry(p_company_id, item->>'sku', 'purchase_order_received', (item->>'quantity_to_receive')::integer, p_po_id);
    END LOOP;
    SELECT SUM(quantity_ordered), SUM(quantity_received) INTO total_ordered, total_received FROM public.purchase_order_items WHERE po_id = p_po_id;
    IF total_received >= total_ordered THEN current_po_status := 'received';
    ELSIF total_received > 0 THEN current_po_status := 'partial';
    ELSE SELECT status INTO current_po_status FROM public.purchase_orders WHERE id = p_po_id;
    END IF;
    UPDATE public.purchase_orders SET status = current_po_status, updated_at = NOW() WHERE id = p_po_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_inventory_ledger_for_sku(p_company_id uuid, p_sku text)
RETURNS json LANGUAGE plpgsql AS $$
DECLARE result_json json;
BEGIN
    SELECT coalesce(json_agg(t), '[]') INTO result_json
    FROM ( SELECT * FROM public.inventory_ledger WHERE company_id = p_company_id AND sku = p_sku ORDER BY created_at DESC LIMIT 100 ) t;
    RETURN result_json;
END;
$$;

CREATE OR REPLACE FUNCTION get_dashboard_metrics(p_company_id uuid, p_days integer)
RETURNS json LANGUAGE plpgsql AS $$
DECLARE
    result_json json;
BEGIN
    WITH date_range AS (
        SELECT (CURRENT_DATE - (p_days || ' days')::interval)::date as start_date,
               CURRENT_DATE as end_date
    ),
    orders_in_range AS (
        SELECT id, total_amount, sale_date, customer_id
        FROM public.orders
        WHERE company_id = p_company_id AND sale_date::date BETWEEN (SELECT start_date FROM date_range) AND (SELECT end_date FROM date_range)
    ),
    sales_details_in_range AS (
        SELECT
            oi.quantity,
            oi.unit_price as sales_price,
            COALESCE(i.landed_cost, i.cost) as cost
        FROM public.order_items oi
        -- Use LEFT JOIN to not lose sales data if inventory item is deleted
        LEFT JOIN public.inventory i ON oi.sku = i.sku AND i.company_id = p_company_id
        WHERE oi.sale_id IN (SELECT id FROM orders_in_range)
    )
    SELECT json_build_object(
        'totalSalesValue', (SELECT COALESCE(SUM(total_amount), 0) FROM orders_in_range),
        'totalProfit', (SELECT COALESCE(SUM((sales_price - cost) * quantity), 0) FROM sales_details_in_range),
        'totalOrders', (SELECT COUNT(*) FROM orders_in_range),
        'averageOrderValue', (SELECT COALESCE(AVG(total_amount), 0) FROM orders_in_range),
        'salesTrendData', COALESCE((
            SELECT json_agg(t)
            FROM (
                SELECT TO_CHAR(sale_date, 'YYYY-MM-DD') as date, SUM(total_amount) as "Sales"
                FROM orders_in_range
                GROUP BY 1 ORDER BY 1
            ) t
        ), '[]'::json),
        'topCustomersData', COALESCE((
            SELECT json_agg(t)
            FROM (
                SELECT c.customer_name as name, SUM(s.total_amount) as value
                FROM orders_in_range s
                LEFT JOIN public.customers c ON s.customer_id = c.id
                WHERE s.customer_id IS NOT NULL
                GROUP BY c.customer_name ORDER BY value DESC LIMIT 5
            ) t
        ), '[]'::json),
        'inventoryByCategoryData', COALESCE((
            SELECT json_agg(t)
            FROM (
                SELECT COALESCE(category, 'Uncategorized') as name, sum(quantity * cost) as value
                FROM public.inventory
                WHERE company_id = p_company_id
                GROUP BY category
            ) t
        ), '[]'::json),
        'deadStockItemsCount', (
            SELECT COUNT(*)::int
            FROM public.inventory i
            JOIN public.company_settings s ON i.company_id = s.company_id
            WHERE i.company_id = p_company_id
              AND i.quantity > 0
              AND (i.last_sold_date IS NULL OR i.last_sold_date < CURRENT_DATE - (s.dead_stock_days || ' days')::interval)
        )
    ) INTO result_json;
    RETURN result_json;
END;
$$;


CREATE OR REPLACE FUNCTION get_alerts(p_company_id uuid)
RETURNS json AS $$
DECLARE result_json json;
BEGIN
    WITH settings AS (SELECT * FROM company_settings WHERE company_id = p_company_id LIMIT 1),
    low_stock_alerts AS (SELECT 'low_stock' as type, sku, name as product_name, quantity as current_stock, reorder_point FROM inventory WHERE company_id = p_company_id AND quantity > 0 AND reorder_point > 0 AND quantity < reorder_point),
    dead_stock_alerts AS (SELECT 'dead_stock' as type, sku, name as product_name, quantity as current_stock, last_sold_date, (quantity * cost) as value FROM inventory, settings WHERE inventory.company_id = p_company_id AND quantity > 0 AND (last_sold_date IS NULL OR last_sold_date < CURRENT_DATE - (settings.dead_stock_days || ' days')::interval)),
    predictive_alerts AS (SELECT 'predictive' as type, i.sku, i.name as product_name, i.quantity as current_stock, i.quantity / sv.daily_sales_velocity as days_of_stock_remaining FROM inventory i JOIN (SELECT oi.sku, SUM(oi.quantity)::float / NULLIF((SELECT fast_moving_days FROM settings), 0) as daily_sales_velocity FROM order_items oi JOIN orders o ON oi.sale_id = o.id WHERE o.company_id = p_company_id AND o.sale_date >= CURRENT_DATE - ((SELECT fast_moving_days FROM settings) || ' days')::interval GROUP BY oi.sku) sv ON i.sku = sv.sku WHERE i.company_id = p_company_id AND i.quantity > 0 AND sv.daily_sales_velocity > 0 AND (i.quantity / sv.daily_sales_velocity) < 7)
    SELECT coalesce(json_agg(t), '[]') INTO result_json FROM (SELECT * FROM low_stock_alerts UNION ALL SELECT * FROM dead_stock_alerts UNION ALL SELECT null as reorder_point, * FROM predictive_alerts) t;
    RETURN result_json;
END;
$$ LANGUAGE plpgsql;

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


-- ========= Part 12: Row-Level Security (RLS) Policies =========

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
            'users', 'company_settings', 'query_patterns', 'inventory', 'customers',
            'orders', 'vendors', 'reorder_rules', 'purchase_orders', 'integrations',
            'notification_preferences', 'channel_fees', 'locations', 'inventory_ledger'
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

ALTER TABLE public.sync_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view sync logs for their own company" ON public.sync_logs;
CREATE POLICY "Users can view sync logs for their own company" ON public.sync_logs FOR SELECT USING ((SELECT company_id FROM public.integrations WHERE id = integration_id) = public.current_user_company_id());

ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can see their own company" ON public.companies;
CREATE POLICY "Users can see their own company" ON public.companies FOR SELECT USING (id = public.current_user_company_id());

-- ========= Part 13: Secure Unused Future Tables =========
-- This section ensures that any unused tables from previous schema versions
-- are secured by default, resolving all linter warnings.
DO $$
DECLARE
    t_name TEXT;
    unused_tables TEXT[] := ARRAY[
        'returns', 'return_items', 'daily_stats', 'sales_detail', 'inventory_valuation',
        'warehouse_locations', 'product_attributes', 'price_lists', 'fba_inventory',
        'sync_queue', 'platform_events', 'refunds', 'order_tax_lines', 'order_notes',
        'order_shipping_lines', 'inventory_adjustments', 'platform_connections'
    ];
BEGIN
    FOREACH t_name IN ARRAY unused_tables
    LOOP
        -- Check if the table exists before trying to modify it
        IF EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = t_name) THEN
            EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', t_name);
            EXECUTE format('DROP POLICY IF EXISTS "Deny all access by default" ON public.%I;', t_name);
            -- This policy denies all access until a proper, company-specific policy is defined
            EXECUTE format('CREATE POLICY "Deny all access by default" ON public.%I FOR ALL USING (false);', t_name);
        END IF;
    END LOOP;
END;
$$;

