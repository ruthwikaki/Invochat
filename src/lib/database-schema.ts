
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
    customer_id UUID REFERENCES public.customers(id) ON DELETE SET NULL,
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
    theme_primary_color TEXT DEFAULT '256 47% 52%',
    theme_background_color TEXT DEFAULT '0 0% 98%',
    theme_accent_color TEXT DEFAULT '256 47% 52% / 0.1',
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
-- This section ensures older schemas are updated correctly.

ALTER TABLE public.inventory ADD COLUMN IF NOT EXISTS source_platform TEXT;
ALTER TABLE public.inventory ADD COLUMN IF NOT EXISTS external_product_id TEXT;
ALTER TABLE public.inventory ADD COLUMN IF NOT EXISTS external_variant_id TEXT;
ALTER TABLE public.inventory DROP CONSTRAINT IF EXISTS unique_shopify_variant_per_company;
ALTER TABLE public.inventory DROP CONSTRAINT IF EXISTS unique_external_variant_per_company;
ALTER TABLE public.inventory ADD CONSTRAINT unique_external_variant_per_company UNIQUE (company_id, source_platform, external_variant_id);

ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS platform TEXT;
ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS external_id TEXT;
ALTER TABLE public.customers DROP CONSTRAINT IF EXISTS unique_shopify_customer_per_company;
ALTER TABLE public.customers DROP COLUMN IF EXISTS shopify_customer_id;
ALTER TABLE public.customers DROP CONSTRAINT IF EXISTS unique_external_customer_per_company;
ALTER TABLE public.customers ADD CONSTRAINT unique_external_customer_per_company UNIQUE (company_id, platform, external_id);

ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS platform TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS external_id TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS customer_id UUID REFERENCES public.customers(id) ON DELETE SET NULL;
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS unique_shopify_order_per_company;
ALTER TABLE public.orders DROP COLUMN IF EXISTS shopify_order_id;
ALTER TABLE public.orders DROP COLUMN IF EXISTS customer_name;
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS unique_external_order_per_company;
ALTER TABLE public.orders ADD CONSTRAINT unique_external_order_per_company UNIQUE (company_id, platform, external_id);

-- ========= Part 3: Functions and Triggers =========

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  user_company_id uuid;
  user_company_name text;
  user_role text;
  is_invite boolean;
begin
  is_invite := new.invited_at IS NOT NULL;
  IF is_invite THEN
    user_company_id := (new.raw_user_meta_data->>'company_id')::uuid;
    user_role := 'Member';
    IF user_company_id IS NULL THEN
      raise exception 'Invited user must have a company_id in metadata.';
    END IF;
  ELSE
    user_company_id := (new.raw_user_meta_data->>'company_id')::uuid;
    user_company_name := new.raw_user_meta_data->>'company_name';
    user_role := 'Owner';
    insert into public.companies (id, name)
    values (user_company_id, user_company_name)
    on conflict (id) do nothing;
  END IF;
  insert into public.users (id, email, company_id, role)
  values (new.id, new.email, user_company_id, user_role);
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', user_company_id, 'role', user_role)
  where id = new.id;
  return new;
end;
$$;

create or replace trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

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

CREATE OR REPLACE FUNCTION public.get_unified_inventory(p_company_id uuid, p_query text, p_category text, p_location_id uuid)
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
        LEFT JOIN locations l ON i.location_id = l.id
        LEFT JOIN monthly_sales ms ON i.sku = ms.sku
        WHERE i.company_id = p_company_id
        AND (p_query IS NULL OR (i.name ILIKE '%' || p_query || '%' OR i.sku ILIKE '%' || p_query || '%'))
        AND (p_category IS NULL OR i.category = p_category)
        AND (p_location_id IS NULL OR i.location_id = p_location_id)
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
RETURNS json AS $$
DECLARE result_json json;
BEGIN
    WITH date_range AS (SELECT (CURRENT_DATE - (p_days || ' days')::interval) as start_date),
    orders_in_range AS (SELECT id, total_amount, sale_date, customer_id FROM public.orders WHERE company_id = p_company_id AND sale_date >= (SELECT start_date FROM date_range)),
    sales_details_in_range AS (SELECT oi.quantity, oi.unit_price as sales_price, COALESCE(i.landed_cost, i.cost) as cost FROM public.order_items oi JOIN orders_in_range s ON oi.sale_id = s.id JOIN public.inventory i ON oi.sku = oi.sku AND i.company_id = p_company_id),
    sales_trend AS (SELECT TO_CHAR(sale_date, 'YYYY-MM-DD') as date, SUM(total_amount) as "Sales" FROM orders_in_range GROUP BY 1 ORDER BY 1),
    top_customers AS (SELECT c.customer_name as name, SUM(s.total_amount) as value FROM orders_in_range s JOIN public.customers c ON s.customer_id = c.id WHERE s.customer_id IS NOT NULL GROUP BY c.customer_name ORDER BY value DESC LIMIT 5),
    inventory_by_category AS (SELECT category as name, sum(quantity * cost) as value FROM public.inventory WHERE company_id = p_company_id AND category IS NOT NULL GROUP BY category),
    main_metrics AS (SELECT (SELECT COALESCE(SUM(total_amount), 0) FROM orders_in_range) as "totalSalesValue", (SELECT COALESCE(SUM((sales_price - cost) * quantity), 0) FROM sales_details_in_range) as "totalProfit", (SELECT COUNT(*) FROM orders_in_range) as "totalOrders")
    SELECT json_build_object(
        'totalSalesValue', m."totalSalesValue", 'totalProfit', m."totalProfit",
        'averageOrderValue', CASE WHEN m."totalOrders" > 0 THEN m."totalSalesValue" / m."totalOrders" ELSE 0 END,
        'totalOrders', m."totalOrders", 'salesTrendData', (SELECT json_agg(t) FROM sales_trend t),
        'topCustomersData', (SELECT json_agg(t) FROM top_customers t), 'inventoryByCategoryData', (SELECT json_agg(t) FROM inventory_by_category t),
        'deadStockItemsCount', (SELECT COUNT(*)::int FROM public.inventory i JOIN public.company_settings s ON i.company_id = s.company_id WHERE i.company_id = p_company_id AND i.quantity > 0 AND (i.last_sold_date IS NULL OR i.last_sold_date < CURRENT_DATE - (s.dead_stock_days || ' days')::interval))
    ) INTO result_json FROM main_metrics m;
    RETURN result_json;
END;
$$ LANGUAGE plpgsql;

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

-- ========= Part 12: Row-Level Security (RLS) Policies =========

CREATE OR REPLACE FUNCTION public.current_user_company_id()
RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT (auth.jwt()->>'company_id')::uuid;
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
`;
```