-- =================================================================
-- INVOCHAT - THE COMPLETE & IDEMPOTENT DATABASE SETUP SCRIPT
-- =================================================================
-- This script is designed to be run in its entirety. It sets up all
-- necessary tables, functions, triggers, and security policies for
-- the InvoChat application to function correctly. It is idempotent,
-- meaning it can be run multiple times without causing errors.
-- =================================================================

-- Step 1: Extensions
-- -----------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Step 2: Custom Types
-- -----------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE public.user_role AS ENUM (
            'Owner',
            'Admin',
            'Member'
        );
    END IF;
END$$;

-- Step 3: Tables and Indexes
-- This section includes ALL required tables for the application.
-- -----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    name text NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_companies_created_at ON public.companies(created_at);

CREATE TABLE IF NOT EXISTS public.users (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email text,
    role user_role NOT NULL DEFAULT 'Member',
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_users_company_id ON public.users(company_id);

CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    overstock_multiplier numeric(10,2) NOT NULL DEFAULT 3,
    high_value_threshold numeric(10,2) NOT NULL DEFAULT 1000,
    fast_moving_days integer NOT NULL DEFAULT 30,
    predictive_stock_days integer NOT NULL DEFAULT 7,
    currency text DEFAULT 'USD',
    timezone text DEFAULT 'UTC',
    tax_rate numeric(5,4) DEFAULT 0,
    custom_rules jsonb,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.locations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    address text,
    is_default boolean DEFAULT false,
    created_at timestamptz DEFAULT now(),
    UNIQUE(company_id, name)
);

CREATE TABLE IF NOT EXISTS public.inventory (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku text NOT NULL,
    name text NOT NULL,
    category text,
    quantity integer NOT NULL DEFAULT 0,
    cost numeric(10,2) NOT NULL DEFAULT 0,
    price numeric(10,2),
    reorder_point integer,
    on_order_quantity integer NOT NULL DEFAULT 0,
    last_sold_date date,
    landed_cost numeric(10,2),
    barcode text,
    location_id uuid REFERENCES public.locations(id) ON DELETE SET NULL,
    version integer NOT NULL DEFAULT 1,
    deleted_at timestamptz,
    deleted_by uuid REFERENCES auth.users(id),
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    source_platform text,
    external_product_id text,
    external_variant_id text,
    external_quantity integer,
    UNIQUE(company_id, sku)
);
CREATE INDEX IF NOT EXISTS idx_inventory_company_sku ON public.inventory(company_id, sku);

CREATE TABLE IF NOT EXISTS public.vendors (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    vendor_name text NOT NULL,
    contact_info text,
    address text,
    terms text,
    account_number text,
    created_at timestamptz DEFAULT now(),
    UNIQUE(company_id, vendor_name)
);

CREATE TABLE IF NOT EXISTS public.supplier_catalogs (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    supplier_id uuid NOT NULL REFERENCES public.vendors(id) ON DELETE CASCADE,
    sku text NOT NULL,
    supplier_sku text,
    product_name text,
    unit_cost numeric(10,2) NOT NULL,
    moq integer DEFAULT 1,
    lead_time_days integer,
    is_active boolean DEFAULT true,
    created_at timestamptz DEFAULT now(),
    UNIQUE(supplier_id, sku)
);

CREATE TABLE IF NOT EXISTS public.reorder_rules (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku text NOT NULL,
    rule_type text DEFAULT 'manual',
    min_stock integer,
    max_stock integer,
    reorder_quantity integer,
    UNIQUE(company_id, sku)
);

CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.vendors(id),
    po_number text NOT NULL,
    status text,
    order_date date,
    expected_date date,
    total_amount numeric(10,2),
    notes text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, po_number)
);

CREATE TABLE IF NOT EXISTS public.purchase_order_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    po_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    sku text NOT NULL,
    quantity_ordered integer NOT NULL,
    quantity_received integer DEFAULT 0 NOT NULL,
    unit_cost numeric(10,2),
    tax_rate numeric(5,4),
    UNIQUE(po_id, sku)
);

CREATE TABLE IF NOT EXISTS public.customers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform text,
    external_id text,
    customer_name text NOT NULL,
    email text,
    total_orders integer DEFAULT 0,
    total_spent numeric(12,2) DEFAULT 0,
    first_order_date date,
    status text,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now(),
    UNIQUE(company_id, email)
);

CREATE TABLE IF NOT EXISTS public.sales (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sale_number text NOT NULL,
    customer_name text,
    customer_email text,
    total_amount numeric(10,2) NOT NULL,
    payment_method text,
    notes text,
    created_at timestamptz DEFAULT now(),
    created_by uuid REFERENCES auth.users(id),
    external_id text,
    UNIQUE(company_id, sale_number)
);
CREATE INDEX IF NOT EXISTS idx_sales_company_id ON public.sales(company_id);

CREATE TABLE IF NOT EXISTS public.sale_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    sale_id uuid NOT NULL REFERENCES public.sales(id) ON DELETE CASCADE,
    sku text NOT NULL,
    product_name text,
    quantity integer NOT NULL,
    unit_price numeric(10,2) NOT NULL,
    cost_at_time numeric(10,2),
    UNIQUE(sale_id, sku)
);

CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    created_at timestamptz DEFAULT now(),
    last_accessed_at timestamptz DEFAULT now(),
    is_starred boolean DEFAULT false
);

CREATE TABLE IF NOT EXISTS public.messages (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role text NOT NULL,
    content text,
    component text,
    component_props jsonb,
    visualization jsonb,
    confidence numeric(3,2),
    assumptions text[],
    created_at timestamptz DEFAULT now(),
    is_error boolean DEFAULT false
);

CREATE TABLE IF NOT EXISTS public.integrations (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  platform text NOT NULL,
  shop_domain text,
  shop_name text,
  is_active boolean DEFAULT false,
  access_token text,
  last_sync_at timestamptz,
  sync_status text,
  created_at timestamptz DEFAULT now() NOT NULL,
  updated_at timestamptz,
  UNIQUE(company_id, platform)
);

CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku text NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL,
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer,
    related_id uuid,
    notes text
);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_company_sku_date ON public.inventory_ledger(company_id, sku, created_at DESC);

CREATE TABLE IF NOT EXISTS public.channel_fees (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    channel_name text NOT NULL,
    percentage_fee numeric(8,6) NOT NULL,
    fixed_fee numeric(10,4) NOT NULL,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, channel_name)
);

CREATE TABLE IF NOT EXISTS public.export_jobs (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    requested_by_user_id uuid NOT NULL REFERENCES auth.users(id),
    status text DEFAULT 'pending'::text NOT NULL,
    download_url text,
    expires_at timestamptz,
    created_at timestamptz DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.audit_log (
    id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    user_id uuid REFERENCES auth.users(id),
    action text NOT NULL,
    details jsonb,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.sync_state (
    integration_id uuid PRIMARY KEY REFERENCES public.integrations(id) ON DELETE CASCADE,
    sync_type text NOT NULL,
    last_processed_cursor text,
    last_update timestamptz,
    UNIQUE(integration_id, sync_type)
);

CREATE TABLE IF NOT EXISTS public.sync_logs (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    sync_type text,
    status text,
    records_synced integer,
    error_message text,
    started_at timestamptz DEFAULT now(),
    completed_at timestamptz
);

-- Step 4: Materialized Views
-- -----------------------------------------------------------------
DROP MATERIALIZED VIEW IF EXISTS public.company_dashboard_metrics;
CREATE MATERIALIZED VIEW public.company_dashboard_metrics AS
SELECT 
  company_id,
  COUNT(DISTINCT sku) as total_skus,
  SUM(quantity * cost) as inventory_value,
  COUNT(CASE WHEN quantity <= reorder_point AND reorder_point > 0 THEN 1 END) as low_stock_count
FROM inventory
WHERE deleted_at IS NULL
GROUP BY company_id;
CREATE UNIQUE INDEX IF NOT EXISTS company_dashboard_metrics_pkey ON public.company_dashboard_metrics(company_id);


-- Step 5: Trigger Functions & Triggers
-- -----------------------------------------------------------------
-- Function to create a company and link it to the new user
DROP FUNCTION IF EXISTS public.handle_new_user();
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  new_company_id uuid;
  user_role public.user_role;
BEGIN
  -- Create a new company for the user
  INSERT INTO public.companies (name)
  VALUES (new.raw_user_meta_data->>'company_name')
  RETURNING id INTO new_company_id;

  -- The first user is the Owner
  user_role := 'Owner';
  
  -- Insert a row into public.users
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (new.id, new_company_id, new.email, user_role);
  
  -- Update the user's app_metadata in auth.users
  UPDATE auth.users
  SET app_metadata = jsonb_set(
      COALESCE(app_metadata, '{}'::jsonb),
      '{company_id}',
      to_jsonb(new_company_id)
  ) || jsonb_build_object('role', user_role)
  WHERE id = new.id;
  
  RETURN new;
END;
$$;

-- Drop trigger if it exists to ensure idempotency
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
-- Create the trigger to fire after a new user is created in auth.users
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Trigger for optimistic concurrency control
DROP FUNCTION IF EXISTS increment_version();
CREATE OR REPLACE FUNCTION increment_version()
RETURNS TRIGGER AS $$
BEGIN
   NEW.version = OLD.version + 1;
   NEW.updated_at = now();
   RETURN NEW;
END;
$$ language 'plpgsql';

DROP TRIGGER IF EXISTS handle_inventory_update ON inventory;
CREATE TRIGGER handle_inventory_update
BEFORE UPDATE ON inventory
FOR EACH ROW
EXECUTE PROCEDURE increment_version();


-- Step 6: All RPC Functions
-- -----------------------------------------------------------------

DROP FUNCTION IF EXISTS public.batch_upsert_with_transaction(text,jsonb,text[]);
CREATE OR REPLACE FUNCTION public.batch_upsert_with_transaction(
    p_table_name text,
    p_records jsonb,
    p_conflict_columns text[]
) RETURNS void AS $$
BEGIN
    EXECUTE format(
        'INSERT INTO %I SELECT * FROM jsonb_populate_recordset(null::%I, %L) ON CONFLICT (%s) DO UPDATE SET %s',
        p_table_name,
        p_table_name,
        p_records,
        array_to_string(p_conflict_columns, ', '),
        (SELECT string_agg(format('%I = EXCLUDED.%I', col, col), ', ')
         FROM information_schema.columns
         WHERE table_name = p_table_name AND column_name NOT IN (SELECT unnest(p_conflict_columns)))
    );
END;
$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS public.refresh_dashboard_metrics_for_company(uuid);
CREATE OR REPLACE FUNCTION public.refresh_dashboard_metrics_for_company(p_company_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY public.company_dashboard_metrics;
END;
$$;


DROP FUNCTION IF EXISTS public.get_distinct_categories(uuid);
CREATE OR REPLACE FUNCTION public.get_distinct_categories(p_company_id uuid)
RETURNS TABLE(category text)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT i.category
    FROM inventory i
    WHERE i.company_id = p_company_id
    AND i.category IS NOT NULL
    AND i.category <> ''
    ORDER BY i.category;
END;
$$;

DROP FUNCTION IF EXISTS public.get_alerts(uuid, integer, integer, integer);
CREATE OR REPLACE FUNCTION public.get_alerts(
    p_company_id uuid,
    p_dead_stock_days integer,
    p_fast_moving_days integer,
    p_predictive_stock_days integer
)
RETURNS TABLE(type text, sku text, product_name text, current_stock integer, reorder_point integer, last_sold_date date, value numeric, days_of_stock_remaining numeric)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    -- Low Stock Alerts
    SELECT
        'low_stock'::text, i.sku, i.name::text, i.quantity, i.reorder_point,
        i.last_sold_date, (i.quantity * i.cost), NULL::numeric
    FROM inventory i
    WHERE i.company_id = p_company_id AND i.reorder_point IS NOT NULL AND i.quantity <= i.reorder_point AND i.quantity > 0 AND i.deleted_at IS NULL

    UNION ALL

    -- Dead Stock Alerts
    SELECT
        'dead_stock'::text, i.sku, i.name::text, i.quantity, i.reorder_point,
        i.last_sold_date, (i.quantity * i.cost), NULL::numeric
    FROM inventory i
    WHERE i.company_id = p_company_id AND i.deleted_at IS NULL AND i.last_sold_date IS NOT NULL AND i.last_sold_date < (NOW() - (p_dead_stock_days || ' day')::interval)

    UNION ALL

    -- Predictive Stockout Alerts
    (
        WITH sales_velocity AS (
          SELECT
            si.sku,
            SUM(si.quantity)::numeric / p_fast_moving_days as daily_sales
          FROM sale_items si
          JOIN sales s ON si.sale_id = s.id
          WHERE s.company_id = p_company_id AND s.created_at >= (NOW() - (p_fast_moving_days || ' day')::interval)
          GROUP BY si.sku
        )
        SELECT
            'predictive'::text, i.sku, i.name::text, i.quantity, i.reorder_point,
            i.last_sold_date, (i.quantity * i.cost), (i.quantity / sv.daily_sales)
        FROM inventory i
        JOIN sales_velocity sv ON i.sku = sv.sku
        WHERE i.company_id = p_company_id AND sv.daily_sales > 0 AND (i.quantity / sv.daily_sales) <= p_predictive_stock_days AND i.deleted_at IS NULL
    );
END;
$$;

DROP FUNCTION IF EXISTS public.get_anomaly_insights(uuid);
CREATE OR REPLACE FUNCTION public.get_anomaly_insights(p_company_id uuid)
RETURNS TABLE(date text, daily_revenue numeric, daily_customers bigint, avg_revenue numeric, avg_customers numeric, anomaly_type text, deviation_percentage numeric)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH daily_stats AS (
        SELECT
            s.created_at::date AS stat_date,
            SUM(s.total_amount) AS revenue,
            COUNT(DISTINCT s.customer_email) AS customers
        FROM public.sales s
        WHERE s.company_id = p_company_id AND s.created_at >= NOW() - INTERVAL '30 days'
        GROUP BY s.created_at::date
    ),
    avg_stats AS (
        SELECT
            AVG(revenue) AS avg_revenue,
            AVG(customers) AS avg_customers
        FROM daily_stats
    ),
    anomalies AS (
        SELECT
            ds.stat_date, ds.revenue, ds.customers, a.avg_revenue, a.avg_customers,
            (ds.revenue - a.avg_revenue) / NULLIF(a.avg_revenue, 0) AS revenue_deviation,
            (ds.customers::numeric - a.avg_customers) / NULLIF(a.avg_customers, 0) AS customers_deviation
        FROM daily_stats ds, avg_stats a
    )
    SELECT
        a.stat_date::text, a.revenue, a.customers, ROUND(a.avg_revenue, 2), ROUND(a.avg_customers, 2),
        CASE
            WHEN ABS(COALESCE(a.revenue_deviation, 0)) > 2 THEN 'Revenue Anomaly'
            WHEN ABS(COALESCE(a.customers_deviation, 0)) > 2 THEN 'Customer Anomaly'
            ELSE 'No Anomaly'
        END,
        CASE
            WHEN ABS(COALESCE(a.revenue_deviation, 0)) > 2 THEN ROUND(a.revenue_deviation * 100, 2)
            WHEN ABS(COALESCE(a.customers_deviation, 0)) > 2 THEN ROUND(a.customers_deviation * 100, 2)
            ELSE 0
        END
    FROM anomalies a
    WHERE ABS(COALESCE(a.revenue_deviation, 0)) > 2 OR ABS(COALESCE(a.customers_deviation, 0)) > 2;
END;
$$;

DROP FUNCTION IF EXISTS public.check_inventory_references(uuid,text[]);
CREATE OR REPLACE FUNCTION public.check_inventory_references(p_company_id uuid, p_skus text[])
RETURNS TABLE(sku text)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT i.sku
    FROM inventory i
    WHERE i.company_id = p_company_id 
    AND i.sku = ANY(p_skus)
    AND (
        EXISTS (
            SELECT 1 FROM sale_items si 
            JOIN sales s ON si.sale_id = s.id 
            WHERE si.sku = i.sku AND s.company_id = p_company_id
        )
        OR EXISTS (
            SELECT 1 FROM purchase_order_items poi 
            JOIN purchase_orders po ON poi.po_id = po.id 
            WHERE poi.sku = i.sku AND po.company_id = p_company_id
        )
    );
END;
$$;

DROP FUNCTION IF EXISTS public.create_purchase_order_and_update_inventory(uuid,uuid,text,date,date,text,numeric,jsonb);
CREATE OR REPLACE FUNCTION public.create_purchase_order_and_update_inventory(
    p_company_id uuid,
    p_supplier_id uuid,
    p_po_number text,
    p_order_date date,
    p_expected_date date,
    p_notes text,
    p_total_amount numeric,
    p_items jsonb
)
RETURNS purchase_orders
LANGUAGE plpgsql
AS $$
declare
  new_po purchase_orders;
  item_record record;
begin
  -- 1. Create the main purchase order record
  INSERT INTO public.purchase_orders
    (company_id, supplier_id, po_number, status, order_date, expected_date, notes, total_amount)
  VALUES
    (p_company_id, p_supplier_id, p_po_number, 'draft', p_order_date, p_expected_date, p_notes, p_total_amount)
  RETURNING * INTO new_po;

  -- 2. Insert all items and update inventory on_order_quantity in a loop
  FOR item_record IN SELECT * FROM jsonb_to_recordset(p_items) AS x(sku text, quantity_ordered int, unit_cost numeric)
  LOOP
    -- Insert the item into purchase_order_items
    INSERT INTO public.purchase_order_items
      (po_id, sku, quantity_ordered, unit_cost)
    VALUES
      (new_po.id, item_record.sku, item_record.quantity_ordered, item_record.unit_cost);

    -- Increment the on_order_quantity for the corresponding inventory item
    UPDATE public.inventory
    SET on_order_quantity = on_order_quantity + item_record.quantity_ordered
    WHERE sku = item_record.sku AND company_id = p_company_id;
  END LOOP;

  -- 3. Return the newly created PO
  return new_po;
end;
$$;

DROP FUNCTION IF EXISTS public.delete_location_and_unassign_inventory(uuid,uuid);
CREATE OR REPLACE FUNCTION public.delete_location_and_unassign_inventory(p_location_id uuid, p_company_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE inventory SET location_id = NULL WHERE location_id = p_location_id AND company_id = p_company_id;
    DELETE FROM locations WHERE id = p_location_id AND company_id = p_company_id;
END;
$$;

DROP FUNCTION IF EXISTS public.delete_purchase_order(uuid,uuid);
CREATE OR REPLACE FUNCTION public.delete_purchase_order(p_po_id uuid, p_company_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
declare
  item_record record;
begin
  IF NOT EXISTS (SELECT 1 FROM public.purchase_orders WHERE id = p_po_id AND company_id = p_company_id) THEN
    RAISE EXCEPTION 'Purchase order not found or permission denied';
  END IF;

  FOR item_record IN
    SELECT sku, quantity_ordered FROM public.purchase_order_items WHERE po_id = p_po_id
  LOOP
    UPDATE public.inventory
    SET on_order_quantity = on_order_quantity - item_record.quantity_ordered
    WHERE sku = item_record.sku AND company_id = p_company_id;
  END LOOP;
  
  DELETE FROM public.purchase_orders WHERE id = p_po_id;
end;
$$;

DROP FUNCTION IF EXISTS public.delete_supplier_and_catalogs(uuid,uuid);
CREATE OR REPLACE FUNCTION public.delete_supplier_and_catalogs(p_supplier_id uuid, p_company_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
begin
  if exists (select 1 from public.purchase_orders where supplier_id = p_supplier_id and company_id = p_company_id) then
    raise exception 'Cannot delete supplier with active purchase orders.';
  end if;
  delete from public.supplier_catalogs where supplier_id = p_supplier_id;
  delete from public.vendors where id = p_supplier_id and company_id = p_company_id;
end;
$$;

DROP FUNCTION IF EXISTS public.get_abc_analysis(uuid);
CREATE OR REPLACE FUNCTION public.get_abc_analysis(p_company_id uuid)
RETURNS TABLE(sku text, product_name text, total_revenue numeric, percentage_of_total_revenue numeric, abc_category text)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH product_revenue AS (
        SELECT
            i.sku,
            i.name,
            SUM(si.quantity * si.unit_price) AS revenue
        FROM inventory i
        JOIN sale_items si ON i.sku = si.sku
        JOIN sales s ON si.sale_id = s.id
        WHERE i.company_id = p_company_id AND s.company_id = p_company_id
        GROUP BY i.sku, i.name
    ),
    total_revenue AS (
        SELECT SUM(revenue) AS total FROM product_revenue
    ),
    ranked_revenue AS (
        SELECT
            pr.sku,
            pr.name,
            pr.revenue,
            pr.revenue * 100 / tr.total AS percentage_of_total,
            SUM(pr.revenue * 100 / tr.total) OVER (ORDER BY pr.revenue DESC) AS cumulative_percentage
        FROM product_revenue pr, total_revenue tr
    )
    SELECT
        rr.sku,
        rr.name,
        rr.revenue,
        rr.percentage_of_total,
        CASE
            WHEN rr.cumulative_percentage <= 70 THEN 'A'
            WHEN rr.cumulative_percentage <= 90 THEN 'B'
            ELSE 'C'
        END::text AS abc_category
    FROM ranked_revenue rr;
END;
$$;

DROP FUNCTION IF EXISTS public.get_customer_analytics(uuid);
CREATE OR REPLACE FUNCTION public.get_customer_analytics(p_company_id uuid)
RETURNS json
LANGUAGE plpgsql
AS $$
DECLARE
    result_json json;
BEGIN
    WITH customer_stats AS (
        SELECT
            COUNT(*) as total_customers,
            COUNT(*) FILTER (WHERE c.first_order_date >= NOW() - INTERVAL '30 days') as new_customers_last_30_days,
            COALESCE(AVG(c.total_spent), 0) as average_lifetime_value,
            CASE WHEN COUNT(*) > 0 THEN
                (COUNT(*) FILTER (WHERE c.total_orders > 1))::numeric * 100 / COUNT(*)::numeric
            ELSE 0 END as repeat_customer_rate
        FROM customers c
        WHERE c.company_id = p_company_id AND c.deleted_at IS NULL
    )
    SELECT json_build_object(
        'total_customers', (SELECT total_customers FROM customer_stats),
        'new_customers_last_30_days', (SELECT new_customers_last_30_days FROM customer_stats),
        'average_lifetime_value', (SELECT average_lifetime_value FROM customer_stats),
        'repeat_customer_rate', (SELECT repeat_customer_rate / 100.0 FROM customer_stats),
        'top_customers_by_spend', COALESCE((
            SELECT json_agg(json_build_object('name', customer_name, 'value', total_spent))
            FROM (
                SELECT customer_name, total_spent
                FROM customers
                WHERE company_id = p_company_id AND deleted_at IS NULL
                ORDER BY total_spent DESC
                LIMIT 5
            ) top_spend
        ), '[]'::json),
        'top_customers_by_orders', COALESCE((
            SELECT json_agg(json_build_object('name', customer_name, 'value', total_orders))
            FROM (
                SELECT customer_name, total_orders
                FROM customers
                WHERE company_id = p_company_id AND deleted_at IS NULL
                ORDER BY total_orders DESC
                LIMIT 5
            ) top_orders
        ), '[]'::json)
    ) INTO result_json;

    RETURN result_json;
END;
$$;


DROP FUNCTION IF EXISTS public.get_customers_with_stats(uuid,text,integer,integer);
CREATE OR REPLACE FUNCTION public.get_customers_with_stats(
    p_company_id uuid,
    p_query text DEFAULT NULL,
    p_limit integer DEFAULT 50,
    p_offset integer DEFAULT 0
)
RETURNS json
LANGUAGE plpgsql
AS $$
DECLARE
    result_json json;
BEGIN
    WITH customer_stats AS (
        SELECT
            c.id,
            c.company_id,
            c.platform,
            c.external_id,
            c.customer_name,
            c.email,
            c.status,
            c.deleted_at,
            c.created_at,
            COUNT(s.id) as total_orders,
            COALESCE(SUM(s.total_amount), 0) as total_spend
        FROM public.customers c
        LEFT JOIN public.sales s ON c.email = s.customer_email AND c.company_id = s.company_id
        WHERE c.company_id = p_company_id
          AND c.deleted_at IS NULL
          AND (
            p_query IS NULL OR
            c.customer_name ILIKE '%' || p_query || '%' OR
            c.email ILIKE '%' || p_query || '%'
          )
        GROUP BY c.id
    ),
    count_query AS (
        SELECT count(*) as total FROM customer_stats
    )
    SELECT json_build_object(
        'items', (SELECT json_agg(cs) FROM (
            SELECT * FROM customer_stats ORDER BY total_spend DESC LIMIT p_limit OFFSET p_offset
        ) cs),
        'totalCount', (SELECT total FROM count_query)
    ) INTO result_json;
    
    RETURN result_json;
END;
$$;

DROP FUNCTION IF EXISTS public.get_dashboard_metrics(uuid,integer);
CREATE OR REPLACE FUNCTION public.get_dashboard_metrics(
    p_company_id uuid,
    p_days integer DEFAULT 30
)
RETURNS json
LANGUAGE plpgsql
AS $$
DECLARE
    result_json json;
    start_date timestamptz := now() - (p_days || ' days')::interval;
    dead_stock_days integer;
BEGIN
    -- Get company settings
    SELECT COALESCE(cs.dead_stock_days, 90) INTO dead_stock_days
    FROM company_settings cs
    WHERE cs.company_id = p_company_id;

    WITH date_series AS (
        SELECT generate_series(start_date::date, now()::date, '1 day'::interval) as date
    ),
    sales_data AS (
        SELECT
            date_trunc('day', s.created_at)::date as sale_day,
            SUM(s.total_amount) as daily_revenue,
            SUM(si.quantity * (si.unit_price - COALESCE(i.cost, 0))) as daily_profit,
            COUNT(DISTINCT s.id) as daily_orders
        FROM sales s
        JOIN sale_items si ON s.id = si.sale_id
        LEFT JOIN inventory i ON si.sku = i.sku AND s.company_id = i.company_id
        WHERE s.company_id = p_company_id AND s.created_at >= start_date
        GROUP BY 1
    ),
    totals AS (
        SELECT 
            COALESCE(SUM(daily_revenue), 0) as total_revenue,
            COALESCE(SUM(daily_profit), 0) as total_profit,
            COALESCE(SUM(daily_orders), 0) as total_orders
        FROM sales_data
    )
    SELECT json_build_object(
        'totalSalesValue', (SELECT total_revenue FROM totals),
        'totalProfit', (SELECT total_profit FROM totals),
        'totalSales', (SELECT total_orders FROM totals),
        'averageOrderValue', (SELECT CASE WHEN total_orders > 0 THEN total_revenue / total_orders ELSE 0 END FROM totals),
        'deadStockItemsCount', (
            SELECT COUNT(*) 
            FROM inventory 
            WHERE company_id = p_company_id AND deleted_at IS NULL
            AND last_sold_date < now() - (dead_stock_days || ' days')::interval
        ),
        'salesTrendData', (
            SELECT json_agg(json_build_object('date', ds.date, 'Sales', COALESCE(sd.daily_revenue, 0)))
            FROM date_series ds
            LEFT JOIN sales_data sd ON ds.date = sd.sale_day
        ),
        'inventoryByCategoryData', (
            SELECT json_agg(json_build_object('name', COALESCE(category, 'Uncategorized'), 'value', category_value))
            FROM (
                SELECT category, SUM(quantity * cost) as category_value
                FROM inventory
                WHERE company_id = p_company_id AND deleted_at IS NULL
                GROUP BY category
                ORDER BY category_value DESC
                LIMIT 5
            ) cat_data
        ),
        'topCustomersData', (
            SELECT json_agg(json_build_object('name', customer_name, 'value', customer_total))
            FROM (
                SELECT c.customer_name, SUM(s.total_amount) as customer_total
                FROM sales s
                JOIN customers c ON s.customer_email = c.email AND s.company_id = c.company_id
                WHERE s.company_id = p_company_id 
                    AND s.created_at >= start_date 
                    AND c.deleted_at IS NULL
                GROUP BY c.customer_name
                ORDER BY customer_total DESC
                LIMIT 5
            ) cust_data
        )
    ) INTO result_json;

    RETURN result_json;
END;
$$;

DROP FUNCTION IF EXISTS public.get_dead_stock_alerts_data(uuid,integer);
CREATE OR REPLACE FUNCTION public.get_dead_stock_alerts_data(p_company_id uuid, p_dead_stock_days integer)
RETURNS TABLE(sku text, product_name text, quantity integer, cost numeric, total_value numeric, last_sale_date date)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        i.sku::text, 
        i.name::text, 
        i.quantity::integer, 
        i.cost::numeric, 
        (i.quantity * i.cost)::numeric, 
        i.last_sold_date::date
    FROM inventory i
    WHERE i.company_id = p_company_id
      AND i.quantity > 0
      AND i.last_sold_date < (NOW() - (p_dead_stock_days || ' day')::interval)
      AND i.deleted_at IS NULL
    ORDER BY total_value DESC;
END;
$$;

DROP FUNCTION IF EXISTS public.get_demand_forecast(uuid);
CREATE OR REPLACE FUNCTION public.get_demand_forecast(p_company_id uuid)
RETURNS TABLE(sku text, product_name text, forecast_30_days numeric)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH monthly_sales AS (
        SELECT
            si.sku,
            date_trunc('month', s.created_at) AS sale_month,
            SUM(si.quantity) AS total_quantity
        FROM sale_items si
        JOIN sales s ON si.sale_id = s.id
        WHERE s.company_id = p_company_id AND s.created_at >= NOW() - INTERVAL '12 months'
        GROUP BY si.sku, sale_month
    ),
    sales_with_time AS (
        SELECT
            sku,
            total_quantity,
            EXTRACT(EPOCH FROM sale_month) / (30.44 * 24 * 60 * 60) AS month_number
        FROM monthly_sales
    ),
    regression_params AS (
        SELECT
            sku,
            regr_slope(total_quantity, month_number) AS slope,
            regr_intercept(total_quantity, month_number) AS intercept
        FROM sales_with_time
        GROUP BY sku
    )
    SELECT
        rp.sku,
        i.name,
        GREATEST(0, (rp.slope * (EXTRACT(EPOCH FROM (NOW() + INTERVAL '1 month')) / (30.44 * 24 * 60 * 60)) + rp.intercept))::numeric
    FROM regression_params rp
    JOIN inventory i ON rp.sku = i.sku
    WHERE i.company_id = p_company_id;
END;
$$;

DROP FUNCTION IF EXISTS public.get_gross_margin_analysis(uuid);
CREATE OR REPLACE FUNCTION public.get_gross_margin_analysis(p_company_id uuid)
RETURNS TABLE(product_name text, sales_channel text, total_revenue numeric, total_cogs numeric, gross_margin_percentage numeric)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        i.name,
        s.payment_method,
        SUM(si.quantity * si.unit_price) AS total_revenue,
        SUM(si.quantity * i.cost) AS total_cogs,
        CASE
            WHEN SUM(si.quantity * si.unit_price) > 0 THEN
                (SUM(si.quantity * (si.unit_price - i.cost)) * 100) / SUM(si.quantity * si.unit_price)
            ELSE 0
        END AS gross_margin_percentage
    FROM inventory i
    JOIN sale_items si ON i.sku = si.sku
    JOIN sales s ON si.sale_id = s.id
    WHERE i.company_id = p_company_id AND s.created_at >= NOW() - INTERVAL '90 days'
    GROUP BY i.name, s.payment_method;
END;
$$;

DROP FUNCTION IF EXISTS public.get_historical_sales(uuid,text[]);
CREATE OR REPLACE FUNCTION public.get_historical_sales(p_company_id uuid, p_skus text[])
RETURNS TABLE(sku text, monthly_sales jsonb)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        s.sku,
        jsonb_agg(jsonb_build_object('month', s.month, 'total_quantity', s.total_quantity)) as monthly_sales
    FROM (
        SELECT
            si.sku,
            to_char(s.created_at, 'YYYY-MM') AS month,
            SUM(si.quantity) AS total_quantity
        FROM sale_items si
        JOIN sales s ON si.sale_id = s.id
        WHERE s.company_id = p_company_id
          AND si.sku = ANY(p_skus)
          AND s.created_at >= NOW() - INTERVAL '24 months'
        GROUP BY si.sku, month
        ORDER BY si.sku, month
    ) s
    GROUP BY s.sku;
END;
$$;

DROP FUNCTION IF EXISTS public.get_inventory_ledger_for_sku(uuid,text);
CREATE OR REPLACE FUNCTION public.get_inventory_ledger_for_sku(p_company_id uuid, p_sku text)
RETURNS TABLE(id uuid, company_id uuid, sku text, created_at text, change_type text, quantity_change integer, new_quantity integer, related_id uuid, notes text)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        l.id, l.company_id, l.sku, l.created_at::text, l.change_type, l.quantity_change, l.new_quantity, l.related_id, l.notes
    FROM inventory_ledger l
    WHERE l.company_id = p_company_id AND l.sku = p_sku
    ORDER BY l.created_at DESC;
END;
$$;

DROP FUNCTION IF EXISTS public.get_inventory_turnover_report(uuid,integer);
CREATE OR REPLACE FUNCTION public.get_inventory_turnover_report(p_company_id uuid, p_days integer)
RETURNS TABLE(turnover_rate numeric, total_cogs numeric, average_inventory_value numeric, period_days integer)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH cogs_calc AS (
        SELECT SUM(si.quantity * i.cost) AS total_cogs
        FROM sale_items si
        JOIN sales s ON si.sale_id = s.id
        JOIN inventory i ON si.sku = i.sku
        WHERE s.company_id = p_company_id AND s.created_at >= NOW() - (p_days || ' day')::interval
          AND i.company_id = p_company_id
    ),
    inventory_value_calc AS (
        SELECT SUM(quantity * cost) AS current_inventory_value
        FROM inventory
        WHERE company_id = p_company_id
    )
    SELECT
        CASE
            WHEN iv.current_inventory_value > 0 THEN cc.total_cogs / iv.current_inventory_value
            ELSE 0
        END,
        cc.total_cogs,
        iv.current_inventory_value,
        p_days
    FROM cogs_calc cc, inventory_value_calc iv;
END;
$$;

DROP FUNCTION IF EXISTS public.get_margin_trends(uuid);
CREATE OR REPLACE FUNCTION public.get_margin_trends(p_company_id uuid)
RETURNS TABLE(month text, gross_margin_percentage numeric)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        to_char(date_trunc('month', s.created_at), 'YYYY-MM') AS month,
        CASE
            WHEN SUM(si.quantity * si.unit_price) > 0 THEN
                (SUM(si.quantity * (si.unit_price - i.cost)) * 100) / SUM(si.quantity * si.unit_price)
            ELSE 0
        END AS gross_margin_percentage
    FROM sales s
    JOIN sale_items si ON s.id = si.sale_id
    JOIN inventory i ON si.sku = i.sku
    WHERE s.company_id = p_company_id AND i.company_id = p_company_id
      AND s.created_at >= NOW() - INTERVAL '12 months'
    GROUP BY month
    ORDER BY month;
END;
$$;

DROP FUNCTION IF EXISTS public.get_net_margin_by_channel(uuid,text);
CREATE OR REPLACE FUNCTION public.get_net_margin_by_channel(p_company_id uuid, p_channel_name text)
RETURNS TABLE(sales_channel text, total_revenue numeric, total_cogs numeric, total_fees numeric, net_margin_percentage numeric)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH channel_sales AS (
        SELECT
            s.payment_method AS channel,
            SUM(si.quantity * si.unit_price) AS revenue,
            SUM(si.quantity * i.cost) AS cogs,
            COUNT(s.id) as number_of_sales
        FROM sales s
        JOIN sale_items si ON s.id = si.sale_id
        JOIN inventory i ON si.sku = i.sku
        WHERE s.company_id = p_company_id AND i.company_id = p_company_id
          AND s.payment_method = p_channel_name
        GROUP BY s.payment_method
    )
    SELECT
        cs.channel,
        cs.revenue,
        cs.cogs,
        (cs.revenue * cf.percentage_fee + cs.number_of_sales * cf.fixed_fee) AS total_fees,
        CASE
            WHEN cs.revenue > 0 THEN
                ((cs.revenue - cs.cogs - (cs.revenue * cf.percentage_fee + cs.number_of_sales * cf.fixed_fee)) * 100) / cs.revenue
            ELSE 0
        END AS net_margin_percentage
    FROM channel_sales cs
    JOIN channel_fees cf ON cs.channel = cf.channel_name AND cf.company_id = p_company_id;
END;
$$;

DROP FUNCTION IF EXISTS public.get_purchase_order_details(uuid,uuid);
CREATE OR REPLACE FUNCTION public.get_purchase_order_details(p_po_id uuid, p_company_id uuid)
RETURNS TABLE(id uuid, company_id uuid, supplier_id uuid, po_number text, status text, order_date text, expected_date text, total_amount numeric, notes text, created_at text, updated_at text, supplier_name text, supplier_email text, items jsonb)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        po.id, po.company_id, po.supplier_id, po.po_number, po.status,
        po.order_date::text, po.expected_date::text, po.total_amount, po.notes,
        po.created_at::text, po.updated_at::text, v.vendor_name as supplier_name,
        v.contact_info as supplier_email,
        (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'id', poi.id, 'po_id', poi.po_id, 'sku', poi.sku,
                    'product_name', i.name, 'quantity_ordered', poi.quantity_ordered,
                    'quantity_received', poi.quantity_received, 'unit_cost', poi.unit_cost,
                    'tax_rate', poi.tax_rate
                )
            )
            FROM purchase_order_items poi
            LEFT JOIN inventory i ON i.sku = poi.sku AND i.company_id = po.company_id
            WHERE poi.po_id = po.id
        ) as items
    FROM purchase_orders po
    LEFT JOIN vendors v ON po.supplier_id = v.id
    WHERE po.id = p_po_id AND po.company_id = p_company_id;
END;
$$;

DROP FUNCTION IF EXISTS public.get_purchase_orders(uuid,text,integer,integer);
CREATE OR REPLACE FUNCTION public.get_purchase_orders(
    p_company_id uuid,
    p_query text DEFAULT NULL,
    p_limit integer DEFAULT 50,
    p_offset integer DEFAULT 0
)
RETURNS json
LANGUAGE plpgsql
AS $$
DECLARE
    result_json json;
BEGIN
    WITH filtered_pos AS (
        SELECT
            po.id, po.company_id, po.supplier_id, po.po_number, po.status, po.order_date::text,
            po.expected_date::text, po.total_amount, po.notes, po.created_at::text, po.updated_at::text,
            v.vendor_name,
            v.contact_info as supplier_email
        FROM public.purchase_orders po
        LEFT JOIN public.vendors v ON po.supplier_id = v.id
        WHERE po.company_id = p_company_id
          AND (
            p_query IS NULL OR
            po.po_number ILIKE '%' || p_query || '%' OR
            v.vendor_name ILIKE '%' || p_query || '%'
          )
    ),
    count_query AS (
        SELECT count(*) as total FROM filtered_pos
    )
    SELECT json_build_object(
        'items', (SELECT json_agg(t) FROM (
            SELECT * FROM filtered_pos ORDER BY order_date DESC LIMIT p_limit OFFSET p_offset
        ) t),
        'totalCount', (SELECT total FROM count_query)
    ) INTO result_json;
    
    RETURN result_json;
END;
$$;

DROP FUNCTION IF EXISTS public.get_reorder_suggestions(uuid,integer);
CREATE OR REPLACE FUNCTION public.get_reorder_suggestions(p_company_id uuid, p_fast_moving_days integer)
RETURNS TABLE(sku text, product_name text, current_quantity integer, reorder_point integer, suggested_reorder_quantity integer, supplier_name text, supplier_id uuid, unit_cost numeric)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH sales_velocity AS (
      SELECT
        si.sku,
        SUM(si.quantity)::numeric / p_fast_moving_days as daily_sales
      FROM sale_items si
      JOIN sales s ON si.sale_id = s.id
      WHERE s.company_id = p_company_id AND s.created_at >= (NOW() - (p_fast_moving_days || ' day')::interval)
      GROUP BY si.sku
    )
    SELECT
        i.sku,
        i.name,
        i.quantity,
        i.reorder_point,
        GREATEST(i.reorder_point, CEIL(COALESCE(sv.daily_sales, 0) * 30))::integer - i.quantity,
        v.vendor_name,
        v.id,
        sc.unit_cost
    FROM inventory i
    LEFT JOIN sales_velocity sv ON i.sku = sv.sku
    LEFT JOIN supplier_catalogs sc ON i.sku = sc.sku
    LEFT JOIN vendors v ON sc.supplier_id = v.id
    WHERE i.company_id = p_company_id
      AND i.quantity <= i.reorder_point
      AND i.deleted_at IS NULL;
END;
$$;

DROP FUNCTION IF EXISTS public.get_supplier_performance(uuid);
CREATE OR REPLACE FUNCTION public.get_supplier_performance(p_company_id uuid)
RETURNS TABLE(supplier_name text, total_completed_orders bigint, on_time_delivery_rate numeric, average_delivery_variance_days numeric, average_lead_time_days numeric)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        v.vendor_name,
        COUNT(CASE WHEN po.status IN ('received', 'partial') THEN 1 END),
        ROUND(
            COUNT(CASE WHEN po.status = 'received' AND po.expected_date IS NOT NULL AND po.updated_at::date <= po.expected_date THEN 1 END)::numeric * 100 / 
            NULLIF(COUNT(CASE WHEN po.status = 'received' THEN 1 END), 0), 
            2
        ),
        ROUND(AVG(
            CASE 
                WHEN po.status = 'received' AND po.expected_date IS NOT NULL 
                THEN EXTRACT(DAY FROM (po.updated_at::date - po.expected_date))
            END
        ), 1),
        ROUND(AVG(
            CASE 
                WHEN po.status = 'received' 
                THEN EXTRACT(DAY FROM (po.updated_at::date - po.order_date))
            END
        ), 1)
    FROM vendors v
    LEFT JOIN purchase_orders po ON po.supplier_id = v.id
    WHERE v.company_id = p_company_id
    GROUP BY v.id, v.vendor_name
    HAVING COUNT(CASE WHEN po.status IN ('received', 'partial') THEN 1 END) > 0
    ORDER BY COUNT(CASE WHEN po.status IN ('received', 'partial') THEN 1 END) DESC;
END;
$$;


DROP FUNCTION IF EXISTS public.get_unified_inventory(uuid,text,text,uuid,uuid,text,integer,integer);
CREATE OR REPLACE FUNCTION public.get_unified_inventory(
    p_company_id uuid,
    p_query text DEFAULT NULL,
    p_category text DEFAULT NULL,
    p_location_id uuid DEFAULT NULL,
    p_supplier_id uuid DEFAULT NULL,
    p_sku_filter text DEFAULT NULL,
    p_limit integer DEFAULT 50,
    p_offset integer DEFAULT 0
)
RETURNS TABLE(items json, total_count bigint)
LANGUAGE plpgsql
AS $$
DECLARE
    result_items json;
    count_result bigint;
BEGIN
    -- This CTE gets the base filtered inventory and calculates counts in one pass
    WITH filtered_inventory AS (
        SELECT 
            i.*,
            l.name as location_name
        FROM inventory i
        LEFT JOIN locations l ON i.location_id = l.id
        WHERE i.company_id = p_company_id
            AND i.deleted_at IS NULL
            AND (p_query IS NULL OR (
                i.sku ILIKE '%' || p_query || '%' OR
                i.name ILIKE '%' || p_query || '%' OR
                i.barcode ILIKE '%' || p_query || '%'
            ))
            AND (p_category IS NULL OR i.category = p_category)
            AND (p_location_id IS NULL OR i.location_id = p_location_id)
            AND (p_supplier_id IS NULL OR EXISTS (
                SELECT 1 FROM supplier_catalogs sc 
                WHERE sc.sku = i.sku AND sc.supplier_id = p_supplier_id
            ))
            AND (p_sku_filter IS NULL OR i.sku = p_sku_filter)
    ),
    counted_inventory AS (
        SELECT *, COUNT(*) OVER() as full_count FROM filtered_inventory
    ),
    paginated_inventory AS (
        SELECT * FROM counted_inventory
        ORDER BY product_name
        LIMIT p_limit
        OFFSET p_offset
    )
    SELECT 
        json_agg(
            json_build_object(
                'sku', pi.sku,
                'product_name', pi.name,
                'category', pi.category,
                'quantity', pi.quantity,
                'cost', pi.cost,
                'price', pi.price,
                'total_value', (pi.quantity * pi.cost),
                'reorder_point', pi.reorder_point,
                'on_order_quantity', pi.on_order_quantity,
                'landed_cost', pi.landed_cost,
                'barcode', pi.barcode,
                'location_id', pi.location_id,
                'location_name', pi.location_name,
                'monthly_units_sold', COALESCE(
                    (SELECT SUM(si.quantity) 
                     FROM sales s 
                     JOIN sale_items si ON s.id = si.sale_id 
                     WHERE si.sku = pi.sku 
                       AND s.company_id = pi.company_id 
                       AND s.created_at >= CURRENT_DATE - interval '30 days'
                    ), 0
                ),
                'monthly_profit', COALESCE(
                    (SELECT SUM(si.quantity * (si.unit_price - pi.cost))
                     FROM sales s 
                     JOIN sale_items si ON s.id = si.sale_id 
                     WHERE si.sku = pi.sku 
                       AND s.company_id = pi.company_id 
                       AND s.created_at >= CURRENT_DATE - interval '30 days'
                    ), 0
                ),
                'version', pi.version
            )
        ),
        (SELECT full_count FROM counted_inventory LIMIT 1)
    INTO result_items, count_result
    FROM paginated_inventory pi;

    RETURN QUERY SELECT COALESCE(result_items, '[]'::json), COALESCE(count_result, 0);
END;
$$;


DROP FUNCTION IF EXISTS public.process_sales_order_inventory(uuid,uuid);
CREATE OR REPLACE FUNCTION public.process_sales_order_inventory(p_company_id uuid, p_sale_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE inventory i
    SET quantity = i.quantity - si.quantity,
        last_sold_date = CURRENT_DATE,
        updated_at = NOW()
    FROM sale_items si
    JOIN sales s ON si.sale_id = s.id
    WHERE s.id = p_sale_id
    AND s.company_id = p_company_id
    AND i.sku = si.sku
    AND i.company_id = p_company_id;

    INSERT INTO inventory_ledger (company_id, sku, created_at, change_type, quantity_change, new_quantity, related_id, notes)
    SELECT 
        p_company_id,
        si.sku,
        NOW(),
        'sale',
        -si.quantity,
        i.quantity,
        p_sale_id,
        'Sale fulfillment'
    FROM sale_items si
    JOIN sales s ON si.sale_id = s.id
    JOIN inventory i ON si.sku = i.sku AND i.company_id = p_company_id
    WHERE s.id = p_sale_id
    AND s.company_id = p_company_id;
END;
$$;

DROP FUNCTION IF EXISTS public.receive_purchase_order_items(uuid,jsonb,uuid);
CREATE OR REPLACE FUNCTION public.receive_purchase_order_items(p_po_id uuid, p_items_to_receive jsonb, p_company_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE 
    item RECORD;
    v_already_received INTEGER;
    v_ordered_quantity INTEGER;
    v_can_receive INTEGER;
    total_ordered INTEGER;
    total_received INTEGER;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM purchase_orders WHERE id = p_po_id AND company_id = p_company_id) THEN
        RAISE EXCEPTION 'Purchase order not found or access denied';
    END IF;

    FOR item IN SELECT * FROM jsonb_to_recordset(p_items_to_receive) AS x(sku TEXT, quantity_to_receive INTEGER) LOOP
        SELECT poi.quantity_ordered, COALESCE(poi.quantity_received, 0) INTO v_ordered_quantity, v_already_received
        FROM purchase_order_items poi WHERE poi.po_id = p_po_id AND poi.sku = item.sku;
        
        IF NOT FOUND THEN RAISE EXCEPTION 'SKU % not found in this purchase order.', item.sku; END IF;
        v_can_receive := v_ordered_quantity - v_already_received;
        
        IF item.quantity_to_receive > v_can_receive THEN
            RAISE EXCEPTION 'Cannot receive % units for SKU %. Only % are outstanding.', item.quantity_to_receive, item.sku, v_can_receive;
        END IF;
        
        IF item.quantity_to_receive > 0 THEN
            UPDATE public.purchase_order_items SET quantity_received = quantity_received + item.quantity_to_receive WHERE po_id = p_po_id AND sku = item.sku;
            UPDATE public.inventory SET quantity = quantity + item.quantity_to_receive, on_order_quantity = on_order_quantity - item.quantity_to_receive WHERE company_id = p_company_id AND sku = item.sku;
            INSERT INTO inventory_ledger (company_id, sku, change_type, quantity_change, new_quantity, related_id)
            VALUES (p_company_id, item.sku, 'purchase_order_received', item.quantity_to_receive, (SELECT quantity FROM inventory WHERE sku=item.sku AND company_id=p_company_id), p_po_id);
        END IF;
    END LOOP;
    
    SELECT SUM(quantity_ordered), SUM(quantity_received) INTO total_ordered, total_received FROM public.purchase_order_items WHERE po_id = p_po_id;
    IF total_received >= total_ordered THEN 
        UPDATE public.purchase_orders SET status = 'received' WHERE id = p_po_id;
    ELSIF total_received > 0 THEN 
        UPDATE public.purchase_orders SET status = 'partial' WHERE id = p_po_id;
    END IF;
END;
$$;

DROP FUNCTION IF EXISTS public.record_sale_transaction(uuid,uuid,jsonb,text,text,text,text);
CREATE OR REPLACE FUNCTION public.record_sale_transaction(
    p_company_id uuid,
    p_user_id uuid,
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
    new_sale sales;
    item_record record;
    total_amount numeric := 0;
BEGIN
    FOR item_record IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(sku text, quantity int, unit_price numeric) LOOP
        total_amount := total_amount + (item_record.quantity * item_record.unit_price);
    END LOOP;

    INSERT INTO sales (company_id, sale_number, customer_name, customer_email, total_amount, payment_method, notes, created_by, external_id)
    VALUES (p_company_id, 'SALE-' || nextval('sales_sale_number_seq'::regclass), p_customer_name, p_customer_email, total_amount, p_payment_method, p_notes, p_user_id, p_external_id)
    RETURNING * INTO new_sale;

    FOR item_record IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(sku text, product_name text, quantity int, unit_price numeric, cost_at_time numeric) LOOP
        INSERT INTO sale_items (sale_id, sku, product_name, quantity, unit_price, cost_at_time)
        VALUES (new_sale.id, item_record.sku, item_record.product_name, item_record.quantity, item_record.unit_price, item_record.cost_at_time);
    END LOOP;
    
    RETURN new_sale;
END;
$$;

DROP FUNCTION IF EXISTS public.update_inventory_item_with_lock(uuid,text,integer,text,text,numeric,integer,numeric,text,uuid);
CREATE OR REPLACE FUNCTION public.update_inventory_item_with_lock(
    p_company_id uuid,
    p_sku text,
    p_expected_version integer,
    p_name text,
    p_category text,
    p_cost numeric,
    p_reorder_point integer,
    p_landed_cost numeric,
    p_barcode text,
    p_location_id uuid
)
RETURNS inventory
LANGUAGE plpgsql
AS $$
DECLARE
    updated_item inventory;
BEGIN
    UPDATE inventory
    SET 
        name = p_name,
        category = p_category,
        cost = p_cost,
        reorder_point = p_reorder_point,
        landed_cost = p_landed_cost,
        barcode = p_barcode,
        location_id = p_location_id
    WHERE company_id = p_company_id AND sku = p_sku AND version = p_expected_version
    RETURNING * INTO updated_item;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Update failed. The item may have been modified by someone else.';
    END IF;
    
    RETURN updated_item;
END;
$$;

DROP FUNCTION IF EXISTS public.update_purchase_order(uuid,uuid,uuid,text,text,date,date,text,jsonb);
CREATE OR REPLACE FUNCTION public.update_purchase_order(
    p_po_id uuid,
    p_company_id uuid,
    p_supplier_id uuid,
    p_po_number text,
    p_status text,
    p_order_date date,
    p_expected_date date,
    p_notes text,
    p_items jsonb
)
RETURNS void
LANGUAGE plpgsql
AS $$
declare
  old_item record;
  new_item_record record;
  new_total_amount numeric := 0;
begin
  FOR old_item IN
    SELECT sku, quantity_ordered FROM public.purchase_order_items WHERE po_id = p_po_id
  LOOP
    UPDATE public.inventory
    SET on_order_quantity = on_order_quantity - old_item.quantity_ordered
    WHERE sku = old_item.sku AND company_id = p_company_id;
  END LOOP;
  
  DELETE FROM public.purchase_order_items WHERE po_id = p_po_id;

  FOR new_item_record IN SELECT * FROM jsonb_to_recordset(p_items) AS x(sku text, quantity_ordered int, unit_cost numeric)
  LOOP
    INSERT INTO public.purchase_order_items
      (po_id, sku, quantity_ordered, unit_cost)
    VALUES
      (p_po_id, new_item_record.sku, new_item_record.quantity_ordered, new_item_record.unit_cost);

    UPDATE public.inventory
    SET on_order_quantity = on_order_quantity + new_item_record.quantity_ordered
    WHERE sku = new_item_record.sku AND company_id = p_company_id;
    
    new_total_amount := new_total_amount + (new_item_record.quantity_ordered * new_item_record.unit_cost);
  END LOOP;

  UPDATE public.purchase_orders
  SET
    supplier_id = p_supplier_id,
    po_number = p_po_number,
    order_date = p_order_date,
    expected_date = p_expected_date,
    notes = p_notes,
    total_amount = new_total_amount,
    status = p_status,
    updated_at = now()
  WHERE id = p_po_id AND company_id = p_company_id;
end;
$$;

DROP FUNCTION IF EXISTS public.validate_same_company_reference();
CREATE OR REPLACE FUNCTION public.validate_same_company_reference()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    ref_company_id uuid;
    current_company_id uuid;
BEGIN
    IF TG_TABLE_NAME = 'purchase_orders' AND NEW.supplier_id IS NOT NULL THEN
        SELECT company_id INTO ref_company_id FROM vendors WHERE id = NEW.supplier_id;
        IF ref_company_id != NEW.company_id THEN
            RAISE EXCEPTION 'Security violation: Cannot reference a vendor from a different company.';
        END IF;
    END IF;

    IF TG_TABLE_NAME = 'inventory' AND NEW.location_id IS NOT NULL THEN
        SELECT company_id INTO ref_company_id FROM locations WHERE id = NEW.location_id;
        IF ref_company_id != NEW.company_id THEN
            RAISE EXCEPTION 'Security violation: Cannot assign to a location from a different company.';
        END IF;
    END IF;

    IF TG_TABLE_NAME = 'sale_items' THEN
        SELECT company_id INTO ref_company_id FROM sales WHERE id = NEW.sale_id;
        IF NOT EXISTS (SELECT 1 FROM inventory WHERE sku = NEW.sku and company_id = ref_company_id) THEN
            RAISE EXCEPTION 'Security violation: SKU does not exist for this company.';
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$;


-- Step 7: Final RLS Policies
-- -----------------------------------------------------------------
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vendors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sale_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_catalogs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reorder_rules ENABLE ROW LEVEL SECURITY;


DROP POLICY IF EXISTS "Users can only see their own company" ON public.companies;
CREATE POLICY "Users can only see their own company" ON public.companies FOR SELECT USING (id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "Users can only see users in their own company" ON public.users;
CREATE POLICY "Users can only see users in their own company" ON public.users FOR SELECT USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "Users can manage settings for their own company" ON public.company_settings;
CREATE POLICY "Users can manage settings for their own company" ON public.company_settings FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "Users can manage inventory for their own company" ON public.inventory;
CREATE POLICY "Users can manage inventory for their own company" ON public.inventory FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "Users can manage vendors for their own company" ON public.vendors;
CREATE POLICY "Users can manage vendors for their own company" ON public.vendors FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "Users can manage POs for their own company" ON public.purchase_orders;
CREATE POLICY "Users can manage POs for their own company" ON public.purchase_orders FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "Users can manage PO Items for their own company" ON public.purchase_order_items;
CREATE POLICY "Users can manage PO Items for their own company" ON public.purchase_order_items FOR ALL USING (po_id IN (SELECT id FROM purchase_orders WHERE company_id = (SELECT company_id FROM public.users WHERE id = auth.uid())));

DROP POLICY IF EXISTS "Users can manage sales for their own company" ON public.sales;
CREATE POLICY "Users can manage sales for their own company" ON public.sales FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "Users can manage sale items for sales in their own company" ON public.sale_items;
CREATE POLICY "Users can manage sale items for sales in their own company" ON public.sale_items FOR ALL USING (sale_id IN (SELECT id FROM sales WHERE company_id = (SELECT company_id FROM public.users WHERE id = auth.uid())));

DROP POLICY IF EXISTS "Users can manage customers for their own company" ON public.customers;
CREATE POLICY "Users can manage customers for their own company" ON public.customers FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "Users can manage locations for their own company" ON public.locations;
CREATE POLICY "Users can manage locations for their own company" ON public.locations FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "Users can manage integrations for their own company" ON public.integrations;
CREATE POLICY "Users can manage integrations for their own company" ON public.integrations FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "Users can manage ledger for their own company" ON public.inventory_ledger;
CREATE POLICY "Users can manage ledger for their own company" ON public.inventory_ledger FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "Users can manage fees for their own company" ON public.channel_fees;
CREATE POLICY "Users can manage fees for their own company" ON public.channel_fees FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "Users can manage export jobs for their own company" ON public.export_jobs;
CREATE POLICY "Users can manage export jobs for their own company" ON public.export_jobs FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "Users can manage their own conversations" ON public.conversations;
CREATE POLICY "Users can manage their own conversations" ON public.conversations FOR ALL USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can manage their own messages" ON public.messages;
CREATE POLICY "Users can manage their own messages" ON public.messages FOR ALL USING (conversation_id IN (SELECT id FROM conversations WHERE user_id = auth.uid()));

DROP POLICY IF EXISTS "Users can manage their own company's supplier catalogs" ON public.supplier_catalogs;
CREATE POLICY "Users can manage their own company's supplier catalogs" ON public.supplier_catalogs FOR ALL USING (supplier_id IN (SELECT id FROM vendors WHERE company_id = (SELECT company_id FROM users WHERE id = auth.uid())));

DROP POLICY IF EXISTS "Users can manage their own company's reorder rules" ON public.reorder_rules;
CREATE POLICY "Users can manage their own company's reorder rules" ON public.reorder_rules FOR ALL USING (company_id = (SELECT company_id FROM users WHERE id = auth.uid()));


-- Step 8: Grant Permissions
-- -----------------------------------------------------------------
GRANT USAGE ON SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO postgres, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public to authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;

-- =================================================================
-- SCRIPT COMPLETE
-- =================================================================
