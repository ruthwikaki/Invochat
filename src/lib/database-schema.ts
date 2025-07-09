
-- INVOCHAT - THE COMPLETE & IDEMPOTENT DATABASE SETUP SCRIPT
-- This script is designed to be run in its entirety. It sets up all
-- necessary tables, functions, triggers, and security policies for
-- the InvoChat application to function correctly. It is idempotent,
-- meaning it can be run multiple times without causing errors.

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE public.user_role AS ENUM (
            'Owner',
            'Admin',
            'Member'
        );
    END IF;
END
$$;

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
    role public.user_role NOT NULL DEFAULT 'Member',
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_users_company_id ON public.users(company_id);

CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    overstock_multiplier numeric(10,2) NOT NULL DEFAULT 3,
    high_value_threshold bigint NOT NULL DEFAULT 100000,
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
    cost bigint NOT NULL DEFAULT 0,
    price bigint,
    reorder_point integer,
    on_order_quantity integer NOT NULL DEFAULT 0,
    last_sold_date date,
    landed_cost bigint,
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
    UNIQUE(company_id, sku),
    CONSTRAINT inventory_quantity_non_negative CHECK ((quantity >= 0)),
    CONSTRAINT on_order_quantity_non_negative CHECK ((on_order_quantity >= 0))
);
CREATE INDEX IF NOT EXISTS idx_inventory_company_sku ON public.inventory(company_id, sku);
CREATE INDEX IF NOT EXISTS idx_inventory_category ON public.inventory(company_id, category);
CREATE INDEX IF NOT EXISTS idx_inventory_deleted_at ON public.inventory(company_id, deleted_at);

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
    unit_cost bigint NOT NULL,
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
    total_amount bigint,
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
    unit_cost bigint,
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
    total_spent bigint DEFAULT 0,
    first_order_date date,
    status text,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now(),
    UNIQUE(company_id, email)
);

CREATE SEQUENCE IF NOT EXISTS sales_sale_number_seq;

CREATE TABLE IF NOT EXISTS public.sales (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sale_number text NOT NULL UNIQUE,
    customer_name text,
    customer_email text,
    total_amount bigint NOT NULL,
    payment_method text,
    notes text,
    created_at timestamptz DEFAULT now(),
    created_by uuid REFERENCES auth.users(id),
    external_id text,
    UNIQUE(company_id, sale_number)
);
CREATE INDEX IF NOT EXISTS idx_sales_company_id ON public.sales(company_id);
CREATE INDEX IF NOT EXISTS idx_sales_created_at ON public.sales(company_id, created_at);
CREATE INDEX IF NOT EXISTS idx_sales_customer_email ON public.sales(company_id, customer_email);

CREATE TABLE IF NOT EXISTS public.sale_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    sale_id uuid NOT NULL REFERENCES public.sales(id) ON DELETE CASCADE,
    company_id uuid NOT NULL,
    sku text NOT NULL,
    product_name text,
    quantity integer NOT NULL,
    unit_price bigint NOT NULL,
    cost_at_time bigint,
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
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id_created_at ON public.messages(conversation_id, created_at);

CREATE TABLE IF NOT EXISTS public.integrations (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  platform text NOT NULL,
  shop_domain text,
  shop_name text,
  is_active boolean DEFAULT false,
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
    fixed_fee bigint NOT NULL,
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
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    sync_type text NOT NULL,
    last_processed_cursor text,
    last_update timestamptz,
    PRIMARY KEY(integration_id, sync_type)
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

CREATE MATERIALIZED VIEW IF NOT EXISTS public.company_dashboard_metrics AS
SELECT
  i.company_id,
  COUNT(DISTINCT i.sku) as total_skus,
  SUM(i.quantity * i.cost) as inventory_value,
  COUNT(CASE WHEN i.quantity <= i.reorder_point AND i.reorder_point > 0 THEN 1 END) as low_stock_count
FROM public.inventory AS i
WHERE i.deleted_at IS NULL
GROUP BY i.company_id;
CREATE UNIQUE INDEX IF NOT EXISTS company_dashboard_metrics_pkey ON public.company_dashboard_metrics(company_id);

CREATE MATERIALIZED VIEW IF NOT EXISTS public.customer_analytics_metrics AS
WITH customer_stats AS (
    SELECT
        c.company_id,
        c.id,
        MIN(s.created_at) as first_order_date,
        COUNT(s.id) as total_orders,
        SUM(s.total_amount) as total_spent
    FROM public.customers AS c
    JOIN public.sales AS s ON c.email = s.customer_email AND c.company_id = s.company_id
    WHERE c.deleted_at IS NULL
    GROUP BY c.company_id, c.id
)
SELECT
    cs.company_id,
    COUNT(cs.id) as total_customers,
    COUNT(*) FILTER (WHERE cs.first_order_date >= NOW() - INTERVAL '30 days') as new_customers_last_30_days,
    COALESCE(AVG(cs.total_spent), 0) as average_lifetime_value,
    CASE WHEN COUNT(cs.id) > 0 THEN
        (COUNT(*) FILTER (WHERE cs.total_orders > 1))::numeric * 100 / COUNT(cs.id)::numeric
    ELSE 0 END as repeat_customer_rate
FROM customer_stats AS cs
GROUP BY cs.company_id;
CREATE UNIQUE INDEX IF NOT EXISTS customer_analytics_metrics_pkey ON public.customer_analytics_metrics(company_id);

DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  new_company_id uuid;
  user_role public.user_role;
  company_name_text text;
BEGIN
  company_name_text := trim(new.raw_user_meta_data->>'company_name');
  IF company_name_text IS NULL OR company_name_text = '' THEN
    RAISE EXCEPTION 'Company name cannot be empty.';
  END IF;

  INSERT INTO public.companies (name)
  VALUES (company_name_text)
  RETURNING id INTO new_company_id;

  user_role := 'Owner';
  
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (new.id, new_company_id, new.email, user_role);
  
  UPDATE auth.users
  SET raw_app_meta_data = jsonb_set(
      COALESCE(raw_app_meta_data, '{}'::jsonb),
      '{company_id}',
      to_jsonb(new_company_id)
  ) || jsonb_build_object('role', user_role)
  WHERE id = new.id;
  
  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

DROP FUNCTION IF EXISTS public.increment_version() CASCADE;
CREATE OR REPLACE FUNCTION public.increment_version()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
   NEW.version = OLD.version + 1;
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS handle_inventory_update ON public.inventory;
CREATE TRIGGER handle_inventory_update
BEFORE UPDATE ON public.inventory
FOR EACH ROW
EXECUTE PROCEDURE public.increment_version();

DROP FUNCTION IF EXISTS public.batch_upsert_with_transaction(text, jsonb, text[]);
CREATE OR REPLACE FUNCTION public.batch_upsert_with_transaction(
    p_table_name text,
    p_records jsonb,
    p_conflict_columns text[]
) RETURNS void
LANGUAGE plpgsql
AS $$
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
$$;

DROP FUNCTION IF EXISTS public.refresh_materialized_views(uuid);
CREATE OR REPLACE FUNCTION public.refresh_materialized_views(p_company_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY public.company_dashboard_metrics;
  REFRESH MATERIALIZED VIEW CONCURRENTLY public.customer_analytics_metrics;
END;
$$;

DROP FUNCTION IF EXISTS public.get_distinct_categories(uuid);
CREATE OR REPLACE FUNCTION public.get_distinct_categories(p_company_id uuid)
RETURNS TABLE(category text)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT i.category::text
    FROM public.inventory AS i
    WHERE i.company_id = p_company_id
    AND i.category IS NOT NULL
    AND i.category <> ''
    ORDER BY i.category::text;
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
    SELECT
        'low_stock'::text AS type, i.sku, i.name::text, i.quantity, i.reorder_point,
        i.last_sold_date, (i.quantity * i.cost)::numeric AS value, NULL::numeric AS days_of_stock_remaining
    FROM public.inventory AS i
    WHERE i.company_id = p_company_id AND i.reorder_point IS NOT NULL AND i.quantity <= i.reorder_point AND i.quantity > 0 AND i.deleted_at IS NULL

    UNION ALL

    SELECT
        'dead_stock'::text, i.sku, i.name::text, i.quantity, i.reorder_point,
        i.last_sold_date, (i.quantity * i.cost)::numeric, NULL::numeric
    FROM public.inventory AS i
    WHERE i.company_id = p_company_id AND i.deleted_at IS NULL AND i.quantity > 0 AND (i.last_sold_date IS NULL OR i.last_sold_date < (NOW() - (p_dead_stock_days || ' day')::interval))

    UNION ALL

    (
        WITH sales_velocity AS (
          SELECT
            si.sku,
            SUM(si.quantity)::numeric / p_fast_moving_days as daily_sales
          FROM public.sale_items AS si
          JOIN public.sales AS s ON si.sale_id = s.id AND si.company_id = s.company_id
          WHERE s.company_id = p_company_id AND s.created_at >= (NOW() - (p_fast_moving_days || ' day')::interval)
          GROUP BY si.sku
        )
        SELECT
            'predictive'::text, i.sku, i.name::text, i.quantity, i.reorder_point,
            i.last_sold_date, (i.quantity * i.cost)::numeric, (i.quantity / sv.daily_sales)
        FROM public.inventory AS i
        JOIN sales_velocity AS sv ON i.sku = sv.sku
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
        FROM public.sales AS s
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
        FROM daily_stats AS ds, avg_stats AS a
    )
    SELECT
        a.stat_date::text, a.revenue, a.customers::bigint, ROUND(a.avg_revenue, 2), ROUND(a.avg_customers, 2),
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
    FROM anomalies AS a
    WHERE ABS(COALESCE(a.revenue_deviation, 0)) > 2 OR ABS(COALESCE(a.customers_deviation, 0)) > 2;
END;
$$;

DROP FUNCTION IF EXISTS public.check_inventory_references(uuid, text[]);
CREATE OR REPLACE FUNCTION public.check_inventory_references(p_company_id uuid, p_skus text[])
RETURNS TABLE(sku text)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT i.sku
    FROM public.inventory AS i
    WHERE i.company_id = p_company_id
    AND i.sku = ANY(p_skus)
    AND (
        EXISTS (
            SELECT 1 FROM public.sale_items AS si
            JOIN public.sales AS s ON si.sale_id = s.id AND si.company_id = s.company_id
            WHERE si.sku = i.sku AND s.company_id = p_company_id
        )
        OR EXISTS (
            SELECT 1 FROM public.purchase_order_items AS poi
            JOIN public.purchase_orders AS po ON poi.po_id = po.id
            WHERE poi.sku = i.sku AND po.company_id = p_company_id
        )
    );
END;
$$;

DROP FUNCTION IF EXISTS public.create_purchase_order_and_update_inventory(uuid, uuid, text, date, date, text, jsonb);
CREATE OR REPLACE FUNCTION public.create_purchase_order_and_update_inventory(
    p_company_id uuid,
    p_supplier_id uuid,
    p_po_number text,
    p_order_date date,
    p_expected_date date,
    p_notes text,
    p_items jsonb
)
RETURNS public.purchase_orders
LANGUAGE plpgsql
AS $$
DECLARE
  new_po public.purchase_orders;
  item_record record;
  v_total_amount bigint := 0;
BEGIN
  FOR item_record IN SELECT * FROM jsonb_to_recordset(p_items) AS x(quantity_ordered int, unit_cost bigint)
  LOOP
    v_total_amount := v_total_amount + (item_record.quantity_ordered * item_record.unit_cost);
  END LOOP;

  INSERT INTO public.purchase_orders
    (company_id, supplier_id, po_number, status, order_date, expected_date, notes, total_amount)
  VALUES
    (p_company_id, p_supplier_id, p_po_number, 'draft', p_order_date, p_expected_date, p_notes, v_total_amount)
  RETURNING * INTO new_po;

  FOR item_record IN SELECT * FROM jsonb_to_recordset(p_items) AS x(sku text, quantity_ordered int, unit_cost bigint)
  LOOP
    INSERT INTO public.purchase_order_items
      (po_id, sku, quantity_ordered, unit_cost)
    VALUES
      (new_po.id, item_record.sku, item_record.quantity_ordered, item_record.unit_cost);

    UPDATE public.inventory
    SET on_order_quantity = on_order_quantity + item_record.quantity_ordered
    WHERE sku = item_record.sku AND company_id = p_company_id;
  END LOOP;

  RETURN new_po;
END;
$$;

DROP FUNCTION IF EXISTS public.create_purchase_orders_from_suggestions_tx(uuid, jsonb);
CREATE OR REPLACE FUNCTION public.create_purchase_orders_from_suggestions_tx(
    p_company_id uuid,
    p_po_payload jsonb
)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
    po_data jsonb;
    item_data jsonb;
    new_po_id uuid;
    created_count integer := 0;
    v_total_amount bigint;
BEGIN
    FOR po_data IN SELECT * FROM jsonb_array_elements(p_po_payload)
    LOOP
        IF (po_data->>'supplier_id') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.vendors WHERE id = (po_data->>'supplier_id')::uuid) THEN
            RAISE EXCEPTION 'Supplier with ID % does not exist.', (po_data->>'supplier_id');
        END IF;

        INSERT INTO public.purchase_orders (company_id, supplier_id, po_number, order_date, status, total_amount)
        VALUES (
            p_company_id,
            (po_data->>'supplier_id')::uuid,
            'PO-' || (nextval('sales_sale_number_seq'::regclass)),
            CURRENT_DATE,
            'draft',
            0
        ) RETURNING id INTO new_po_id;
        
        v_total_amount := 0;

        FOR item_data IN SELECT * FROM jsonb_array_elements(po_data->'items')
        LOOP
            IF NOT EXISTS (SELECT 1 FROM public.inventory WHERE sku = (item_data->>'sku') AND company_id = p_company_id AND deleted_at IS NULL) THEN
                RAISE EXCEPTION 'Product with SKU % does not exist or is deleted.', (item_data->>'sku');
            END IF;

            INSERT INTO public.purchase_order_items (po_id, sku, quantity_ordered, unit_cost)
            VALUES (
                new_po_id,
                item_data->>'sku',
                (item_data->>'quantity_ordered')::integer,
                (item_data->>'unit_cost')::bigint
            );

            UPDATE public.inventory
            SET on_order_quantity = on_order_quantity + (item_data->>'quantity_ordered')::integer
            WHERE sku = item_data->>'sku' AND company_id = p_company_id;
            
            v_total_amount := v_total_amount + ((item_data->>'quantity_ordered')::integer * (item_data->>'unit_cost')::bigint);
        END LOOP;
        
        UPDATE public.purchase_orders
        SET total_amount = v_total_amount
        WHERE id = new_po_id;

        created_count := created_count + 1;
    END LOOP;

    RETURN created_count;
END;
$$;

DROP FUNCTION IF EXISTS public.delete_location_and_unassign_inventory(uuid, uuid);
CREATE OR REPLACE FUNCTION public.delete_location_and_unassign_inventory(p_location_id uuid, p_company_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE public.inventory SET location_id = NULL WHERE location_id = p_location_id AND company_id = p_company_id;
    DELETE FROM public.locations WHERE id = p_location_id AND company_id = p_company_id;
END;
$$;

DROP FUNCTION IF EXISTS public.delete_purchase_order(uuid, uuid);
CREATE OR REPLACE FUNCTION public.delete_purchase_order(p_po_id uuid, p_company_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  item_record record;
BEGIN
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
END;
$$;

DROP FUNCTION IF EXISTS public.delete_supplier_and_catalogs(uuid, uuid);
CREATE OR REPLACE FUNCTION public.delete_supplier_and_catalogs(p_supplier_id uuid, p_company_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.purchase_orders WHERE supplier_id = p_supplier_id AND company_id = p_company_id) THEN
    RAISE EXCEPTION 'Cannot delete supplier with active purchase orders.';
  END IF;
  DELETE FROM public.supplier_catalogs WHERE supplier_id = p_supplier_id;
  DELETE FROM public.vendors WHERE id = p_supplier_id AND company_id = p_company_id;
END;
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
            i.name AS product_name,
            COALESCE(SUM(si.quantity * si.unit_price), 0) AS revenue
        FROM public.inventory AS i
        LEFT JOIN public.sale_items AS si ON i.sku = si.sku AND i.company_id = si.company_id
        LEFT JOIN public.sales AS s ON si.sale_id = s.id AND s.created_at >= NOW() - interval '1 year' AND s.company_id = si.company_id
        WHERE i.company_id = p_company_id AND i.deleted_at IS NULL
        GROUP BY i.sku, i.name
    ),
    total_revenue AS (
        SELECT SUM(revenue) AS total FROM product_revenue
    ),
    ranked_revenue AS (
        SELECT
            pr.sku,
            pr.product_name,
            pr.revenue,
            (pr.revenue * 100.0 / NULLIF((SELECT total FROM total_revenue), 0)) AS percentage_of_total,
            SUM(pr.revenue) OVER (ORDER BY pr.revenue DESC) * 100.0 / NULLIF((SELECT total FROM total_revenue), 0) AS cumulative_percentage
        FROM product_revenue AS pr
    )
    SELECT
        rr.sku,
        rr.product_name,
        rr.revenue,
        rr.percentage_of_total,
        CASE
            WHEN rr.cumulative_percentage <= 80 THEN 'A'
            WHEN rr.cumulative_percentage <= 95 THEN 'B'
            ELSE 'C'
        END::text AS abc_category
    FROM ranked_revenue AS rr
    WHERE rr.revenue > 0;
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
            COALESCE(SUM(s.total_amount), 0) as total_spent
        FROM public.customers AS c
        LEFT JOIN public.sales AS s ON c.email = s.customer_email AND c.company_id = s.company_id
        WHERE c.company_id = p_company_id AND c.deleted_at IS NULL
        GROUP BY c.id
    ),
    analytics_view AS (
        SELECT * FROM public.customer_analytics_metrics WHERE company_id = p_company_id
    )
    SELECT json_build_object(
        'total_customers', COALESCE((SELECT total_customers FROM analytics_view), 0),
        'new_customers_last_30_days', COALESCE((SELECT new_customers_last_30_days FROM analytics_view), 0),
        'average_lifetime_value', COALESCE((SELECT average_lifetime_value FROM analytics_view), 0),
        'repeat_customer_rate', COALESCE((SELECT repeat_customer_rate / 100.0 FROM analytics_view), 0),
        'top_customers_by_spend', COALESCE((
            SELECT json_agg(json_build_object('name', customer_name, 'value', total_spent))
            FROM (
                SELECT customer_name, total_spent
                FROM customer_stats
                ORDER BY total_spent DESC
                LIMIT 5
            ) top_spend
        ), '[]'::json),
        'top_customers_by_sales', COALESCE((
            SELECT json_agg(json_build_object('name', customer_name, 'value', total_orders))
            FROM (
                SELECT customer_name, total_orders
                FROM customer_stats
                ORDER BY total_orders DESC
                LIMIT 5
            ) top_sales
        ), '[]'::json)
    ) INTO result_json;

    RETURN result_json;
END;
$$;

DROP FUNCTION IF EXISTS public.get_customers_with_stats(uuid, text, integer, integer);
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
            COALESCE(SUM(s.total_amount), 0) as total_spent
        FROM public.customers AS c
        LEFT JOIN public.sales AS s ON c.email = s.customer_email AND c.company_id = s.company_id
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
        'items', COALESCE((SELECT json_agg(cs) FROM (
            SELECT * FROM customer_stats ORDER BY total_spent DESC LIMIT p_limit OFFSET p_offset
        ) AS cs), '[]'::json),
        'totalCount', (SELECT total FROM count_query)
    ) INTO result_json;
    
    RETURN result_json;
END;
$$;

DROP FUNCTION IF EXISTS public.get_dashboard_metrics(uuid, integer);
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
    SELECT COALESCE(cs.dead_stock_days, 90) INTO dead_stock_days
    FROM public.company_settings AS cs
    WHERE cs.company_id = p_company_id;

    WITH date_series AS (
        SELECT generate_series(start_date::date, now()::date, '1 day'::interval) as date
    ),
    sales_data AS (
        SELECT
            date_trunc('day', s.created_at)::date AS sale_day,
            SUM(s.total_amount) AS daily_revenue,
            SUM(si.quantity * si.cost_at_time) AS daily_cogs,
            COUNT(DISTINCT s.id) AS daily_orders
        FROM public.sales AS s
        JOIN public.sale_items AS si ON s.id = si.sale_id AND s.company_id = si.company_id
        WHERE s.company_id = p_company_id AND si.company_id = p_company_id AND s.created_at >= start_date AND si.cost_at_time IS NOT NULL
        GROUP BY 1
    ),
    totals AS (
        SELECT
            COALESCE(SUM(daily_revenue), 0) AS total_revenue,
            COALESCE(SUM(daily_revenue - daily_cogs), 0) AS total_profit,
            COALESCE(SUM(daily_orders), 0) AS total_sales
        FROM sales_data
    )
    SELECT json_build_object(
        'totalSalesValue', (SELECT total_revenue FROM totals),
        'totalProfit', (SELECT total_profit FROM totals),
        'totalSales', (SELECT total_sales FROM totals),
        'averageOrderValue', (SELECT CASE WHEN total_sales > 0 THEN total_revenue / total_sales ELSE 0 END FROM totals),
        'deadStockItemsCount', (
            SELECT COUNT(*)
            FROM public.inventory
            WHERE company_id = p_company_id AND deleted_at IS NULL
            AND (last_sold_date IS NULL OR last_sold_date < now() - (dead_stock_days || ' days')::interval)
        ),
        'salesTrendData', (
            SELECT json_agg(json_build_object('date', ds.date, 'Sales', COALESCE(sd.daily_revenue, 0)))
            FROM date_series AS ds
            LEFT JOIN sales_data AS sd ON ds.date = sd.sale_day
        ),
        'inventoryByCategoryData', (
            SELECT json_agg(json_build_object('name', COALESCE(category, 'Uncategorized'), 'value', category_value))
            FROM (
                SELECT category, SUM(quantity * cost) as category_value
                FROM public.inventory
                WHERE company_id = p_company_id AND deleted_at IS NULL
                GROUP BY category
                ORDER BY category_value DESC
                LIMIT 5
            ) AS cat_data
        ),
        'topCustomersData', (
            SELECT json_agg(json_build_object('name', customer_name, 'value', customer_total))
            FROM (
                SELECT c.customer_name, SUM(s.total_amount) as customer_total
                FROM public.sales AS s
                JOIN public.customers AS c ON s.customer_email = c.email AND s.company_id = c.company_id
                WHERE s.company_id = p_company_id
                    AND s.created_at >= start_date
                    AND c.deleted_at IS NULL
                GROUP BY c.customer_name
                ORDER BY customer_total DESC
                LIMIT 5
            ) AS cust_data
        )
    ) INTO result_json;

    RETURN result_json;
END;
$$;

DROP FUNCTION IF EXISTS public.get_dead_stock_alerts_data(uuid, integer);
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
    FROM public.inventory AS i
    WHERE i.company_id = p_company_id
      AND i.quantity > 0
      AND (i.last_sold_date IS NULL OR i.last_sold_date < (NOW() - (p_dead_stock_days || ' day')::interval))
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
        FROM public.sale_items AS si
        JOIN public.sales AS s ON si.sale_id = s.id AND si.company_id = s.company_id
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
    FROM regression_params AS rp
    JOIN public.inventory AS i ON rp.sku = i.sku
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
        si.product_name,
        s.payment_method AS sales_channel,
        SUM(si.quantity * si.unit_price) AS total_revenue,
        SUM(si.quantity * si.cost_at_time) AS total_cogs,
        CASE
            WHEN SUM(si.quantity * si.unit_price) > 0 THEN
                (SUM(si.quantity * (si.unit_price - si.cost_at_time)) * 100) / SUM(si.quantity * si.unit_price)
            ELSE 0
        END AS gross_margin_percentage
    FROM public.sale_items AS si
    JOIN public.sales AS s ON si.sale_id = s.id AND s.company_id = si.company_id
    WHERE s.company_id = p_company_id AND si.company_id = p_company_id AND si.cost_at_time IS NOT NULL AND s.created_at >= NOW() - INTERVAL '90 days'
    GROUP BY si.product_name, s.payment_method;
END;
$$;

DROP FUNCTION IF EXISTS public.get_historical_sales(uuid, text[]);
CREATE OR REPLACE FUNCTION public.get_historical_sales(p_company_id uuid, p_skus text[])
RETURNS TABLE(sku text, monthly_sales jsonb)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        s.sku,
        jsonb_agg(jsonb_build_object('month', s.month, 'total_quantity', s.total_quantity)) AS monthly_sales
    FROM (
        SELECT
            si.sku,
            to_char(s.created_at, 'YYYY-MM') AS month,
            SUM(si.quantity) AS total_quantity
        FROM public.sale_items AS si
        JOIN public.sales AS s ON si.sale_id = s.id AND si.company_id = s.company_id
        WHERE s.company_id = p_company_id AND si.company_id = p_company_id
          AND si.sku = ANY(p_skus)
          AND s.created_at >= NOW() - INTERVAL '24 months'
        GROUP BY si.sku, month
        ORDER BY si.sku, month
    ) AS s
    GROUP BY s.sku;
END;
$$;

DROP FUNCTION IF EXISTS public.get_inventory_ledger_for_sku(uuid, text);
CREATE OR REPLACE FUNCTION public.get_inventory_ledger_for_sku(p_company_id uuid, p_sku text)
RETURNS TABLE(id uuid, company_id uuid, sku text, created_at text, change_type text, quantity_change integer, new_quantity integer, related_id uuid, notes text)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        l.id, l.company_id, l.sku, l.created_at::text, l.change_type, l.quantity_change, l.new_quantity, l.related_id, l.notes
    FROM public.inventory_ledger AS l
    WHERE l.company_id = p_company_id AND l.sku = p_sku
    ORDER BY l.created_at DESC;
END;
$$;

DROP FUNCTION IF EXISTS public.get_inventory_turnover_report(uuid, integer);
CREATE OR REPLACE FUNCTION public.get_inventory_turnover_report(p_company_id uuid, p_days integer)
RETURNS TABLE(turnover_rate numeric, total_cogs numeric, average_inventory_value numeric, period_days integer)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH cogs_calc AS (
        SELECT COALESCE(SUM(si.quantity * si.cost_at_time), 0) AS total_cogs
        FROM public.sale_items AS si
        JOIN public.sales AS s ON si.sale_id = s.id AND s.company_id = si.company_id
        WHERE s.company_id = p_company_id AND si.company_id = p_company_id AND s.created_at >= NOW() - (p_days || ' day')::interval AND si.cost_at_time IS NOT NULL
    ),
    inventory_value_calc AS (
        SELECT COALESCE(SUM(i.quantity * i.cost), 1) AS current_inventory_value
        FROM public.inventory i
        WHERE i.company_id = p_company_id AND i.deleted_at IS NULL
    )
    SELECT
        (cc.total_cogs / NULLIF(iv.current_inventory_value, 0))::numeric,
        cc.total_cogs::numeric,
        iv.current_inventory_value::numeric,
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
                (SUM(si.quantity * (si.unit_price - si.cost_at_time)) * 100) / SUM(si.quantity * si.unit_price)
            ELSE 0
        END AS gross_margin_percentage
    FROM public.sales AS s
    JOIN public.sale_items AS si ON s.id = si.sale_id AND s.company_id = si.company_id
    WHERE s.company_id = p_company_id AND si.company_id = p_company_id AND si.cost_at_time IS NOT NULL
      AND s.created_at >= NOW() - INTERVAL '12 months'
    GROUP BY month
    ORDER BY month;
END;
$$;

DROP FUNCTION IF EXISTS public.get_net_margin_by_channel(uuid, text);
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
            SUM(si.quantity * si.cost_at_time) AS cogs,
            COUNT(s.id) as number_of_sales
        FROM public.sales AS s
        JOIN public.sale_items AS si ON s.id = si.sale_id AND s.company_id = si.company_id
        WHERE s.company_id = p_company_id AND si.company_id = p_company_id AND si.cost_at_time IS NOT NULL
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
    FROM channel_sales AS cs
    JOIN public.channel_fees AS cf ON cs.channel = cf.channel_name AND cf.company_id = p_company_id;
END;
$$;

DROP FUNCTION IF EXISTS public.get_purchase_order_details(uuid, uuid);
CREATE OR REPLACE FUNCTION public.get_purchase_order_details(p_po_id uuid, p_company_id uuid)
RETURNS TABLE(id uuid, company_id uuid, supplier_id uuid, po_number text, status text, order_date text, expected_date text, total_amount bigint, notes text, created_at text, updated_at text, supplier_name text, supplier_email text, items jsonb)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        po.id, po.company_id, po.supplier_id, po.po_number, po.status,
        po.order_date::text, po.expected_date::text, po.total_amount, po.notes,
        po.created_at::text, po.updated_at::text, v.vendor_name AS supplier_name,
        v.contact_info AS supplier_email,
        (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'id', poi.id, 'po_id', poi.po_id, 'sku', poi.sku,
                    'product_name', i.name, 'quantity_ordered', poi.quantity_ordered,
                    'quantity_received', poi.quantity_received, 'unit_cost', poi.unit_cost,
                    'tax_rate', poi.tax_rate
                )
            )
            FROM public.purchase_order_items AS poi
            LEFT JOIN public.inventory AS i ON i.sku = poi.sku AND i.company_id = po.company_id
            WHERE poi.po_id = po.id
        ) as items
    FROM public.purchase_orders AS po
    LEFT JOIN public.vendors AS v ON po.supplier_id = v.id
    WHERE po.id = p_po_id AND po.company_id = p_company_id;
END;
$$;

DROP FUNCTION IF EXISTS public.get_purchase_orders(uuid, text, integer, integer);
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
        FROM public.purchase_orders AS po
        LEFT JOIN public.vendors AS v ON po.supplier_id = v.id
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
        'items', COALESCE((SELECT json_agg(t) FROM (
            SELECT * FROM filtered_pos ORDER BY order_date DESC LIMIT p_limit OFFSET p_offset
        ) AS t), '[]'::json),
        'totalCount', (SELECT total FROM count_query)
    ) INTO result_json;

    RETURN result_json;
END;
$$;

DROP FUNCTION IF EXISTS public.get_reorder_suggestions(uuid, integer);
CREATE OR REPLACE FUNCTION public.get_reorder_suggestions(p_company_id uuid, p_fast_moving_days integer)
RETURNS TABLE(sku text, product_name text, current_quantity integer, reorder_point integer, suggested_reorder_quantity integer, supplier_name text, supplier_id uuid, unit_cost bigint, base_quantity integer)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH sales_velocity AS (
      SELECT
        si.sku,
        SUM(si.quantity)::numeric / p_fast_moving_days as daily_sales
      FROM public.sale_items AS si
      JOIN public.sales AS s ON si.sale_id = s.id AND si.company_id = s.company_id
      WHERE s.company_id = p_company_id AND si.company_id = p_company_id AND s.created_at >= (NOW() - (p_fast_moving_days || ' day')::interval)
      GROUP BY si.sku
    ),
    base_suggestions AS (
        SELECT
            i.sku,
            i.name AS product_name,
            i.quantity AS current_quantity,
            i.reorder_point,
            GREATEST(0, (COALESCE(i.reorder_point, 0) + CEIL(COALESCE(sv.daily_sales, 0) * 30)) - i.quantity)::integer AS base_quantity,
            v.vendor_name,
            v.id AS supplier_id,
            sc.unit_cost
        FROM public.inventory AS i
        LEFT JOIN sales_velocity AS sv ON i.sku = sv.sku
        LEFT JOIN public.supplier_catalogs AS sc ON i.sku = sc.sku
        LEFT JOIN public.vendors AS v ON sc.supplier_id = v.id
        WHERE i.company_id = p_company_id
          AND i.quantity <= COALESCE(i.reorder_point, 0)
          AND i.deleted_at IS NULL
    )
    SELECT
        bs.sku, bs.product_name, bs.current_quantity, bs.reorder_point,
        bs.base_quantity AS suggested_reorder_quantity,
        bs.supplier_name, bs.supplier_id, bs.unit_cost,
        bs.base_quantity
    FROM base_suggestions AS bs;
END;
$$;

DROP FUNCTION IF EXISTS public.get_supplier_performance(uuid);
CREATE OR REPLACE FUNCTION public.get_supplier_performance(p_company_id uuid)
RETURNS TABLE(supplier_name text, total_completed_orders bigint, on_time_delivery_rate numeric, average_delivery_variance_days numeric, average_lead_time_days numeric)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH po_delivery_dates AS (
        SELECT
            il.related_id AS po_id,
            MAX(il.created_at) AS actual_delivery_date
        FROM public.inventory_ledger AS il
        WHERE il.company_id = p_company_id
          AND il.change_type = 'purchase_order_received'
          AND il.related_id IS NOT NULL
        GROUP BY il.related_id
    ),
    po_stats AS (
        SELECT
            po.supplier_id,
            po.status,
            po.order_date,
            po.expected_date,
            podd.actual_delivery_date
        FROM public.purchase_orders AS po
        JOIN po_delivery_dates AS podd ON po.id = podd.po_id
        WHERE po.company_id = p_company_id
          AND po.status IN ('received', 'partial')
    )
    SELECT
        v.vendor_name,
        COUNT(ps.*) AS total_completed_orders,
        COALESCE(
            ROUND(
                (COUNT(*) FILTER (WHERE ps.status = 'received' AND ps.expected_date IS NOT NULL AND ps.actual_delivery_date::date <= ps.expected_date))::numeric * 100
                / NULLIF(COUNT(*) FILTER (WHERE ps.status = 'received' AND ps.expected_date IS NOT NULL), 0),
                2
            ),
            0
        ) AS on_time_delivery_rate,
        COALESCE(
            ROUND(
                AVG(EXTRACT(DAY FROM (ps.actual_delivery_date::date - ps.expected_date)))
                FILTER (WHERE ps.expected_date IS NOT NULL),
                1
            ),
            0
        ) AS average_delivery_variance_days,
        COALESCE(
            ROUND(
                AVG(EXTRACT(DAY FROM (ps.actual_delivery_date::date - ps.order_date))),
                1
            ),
            0
        ) AS average_lead_time_days
    FROM public.vendors AS v
    JOIN po_stats AS ps ON v.id = ps.supplier_id
    WHERE v.company_id = p_company_id
    GROUP BY v.id, v.vendor_name
    ORDER BY total_completed_orders DESC;
END;
$$;

DROP FUNCTION IF EXISTS public.get_unified_inventory(uuid, text, text, uuid, uuid, text, integer, integer);
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
    WITH filtered_inventory AS (
        SELECT
            i.*,
            l.name AS location_name
        FROM public.inventory AS i
        LEFT JOIN public.locations AS l ON i.location_id = l.id
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
                SELECT 1 FROM public.supplier_catalogs AS sc
                WHERE sc.sku = i.sku AND sc.supplier_id = p_supplier_id
            ))
            AND (p_sku_filter IS NULL OR i.sku = p_sku_filter)
    ),
    counted_inventory AS (
        SELECT *, COUNT(*) OVER() AS full_count FROM filtered_inventory
    ),
    paginated_inventory AS (
        SELECT * FROM counted_inventory
        ORDER BY name
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
                     FROM public.sales AS s
                     JOIN public.sale_items AS si ON s.id = si.sale_id AND s.company_id = si.company_id
                     WHERE si.sku = pi.sku
                       AND s.company_id = pi.company_id AND si.company_id = pi.company_id
                       AND s.created_at >= CURRENT_DATE - interval '30 days'
                    ), 0
                ),
                'monthly_profit', COALESCE(
                    (SELECT SUM(si.quantity * (si.unit_price - si.cost_at_time))
                     FROM public.sales AS s
                     JOIN public.sale_items AS si ON s.id = si.sale_id AND s.company_id = si.company_id
                     WHERE si.sku = pi.sku
                       AND s.company_id = pi.company_id AND si.company_id = pi.company_id
                       AND s.created_at >= CURRENT_DATE - interval '30 days'
                       AND si.cost_at_time IS NOT NULL
                    ), 0
                ),
                'version', pi.version
            )
        ),
        (SELECT full_count FROM counted_inventory LIMIT 1)
    INTO result_items, count_result
    FROM paginated_inventory AS pi;

    RETURN QUERY SELECT COALESCE(result_items, '[]'::json), COALESCE(count_result, 0);
END;
$$;

DROP FUNCTION IF EXISTS public.process_sales_order_inventory(uuid, uuid, jsonb);
CREATE OR REPLACE FUNCTION public.process_sales_order_inventory(p_company_id uuid, p_sale_id uuid, p_inventory_updates jsonb)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    item_record record;
    updated_row_count int;
BEGIN
    FOR item_record IN SELECT * FROM jsonb_to_recordset(p_inventory_updates) AS x(sku text, quantity int, expected_version int)
    LOOP
        UPDATE public.inventory AS i
        SET
            quantity = i.quantity - item_record.quantity,
            last_sold_date = CURRENT_DATE
        WHERE i.sku = item_record.sku
          AND i.company_id = p_company_id
          AND i.version = item_record.expected_version;

        GET DIAGNOSTICS updated_row_count = ROW_COUNT;
        IF updated_row_count = 0 THEN
            RAISE EXCEPTION 'Concurrency error: Inventory for SKU % was updated by another process. Please try again.', item_record.sku;
        END IF;

        INSERT INTO public.inventory_ledger (company_id, sku, created_at, change_type, quantity_change, new_quantity, related_id, notes)
        SELECT
            p_company_id,
            item_record.sku,
            NOW(),
            'sale',
            -item_record.quantity,
            (SELECT quantity FROM public.inventory WHERE sku = item_record.sku AND company_id = p_company_id),
            p_sale_id,
            'Sale fulfillment';
    END LOOP;
END;
$$;

DROP FUNCTION IF EXISTS public.receive_purchase_order_items(uuid, jsonb, uuid);
CREATE OR REPLACE FUNCTION public.receive_purchase_order_items(p_po_id uuid, p_items_to_receive jsonb, p_company_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    item RECORD;
    v_ordered_quantity INTEGER;
    v_already_received INTEGER;
    v_can_receive INTEGER;
    total_ordered INTEGER;
    total_received INTEGER;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.purchase_orders WHERE id = p_po_id AND company_id = p_company_id) THEN
        RAISE EXCEPTION 'Purchase order not found or access denied';
    END IF;

    FOR item IN SELECT * FROM jsonb_to_recordset(p_items_to_receive) AS x(sku TEXT, quantity_to_receive INTEGER) LOOP
        SELECT poi.quantity_ordered, COALESCE(poi.quantity_received, 0)
        INTO v_ordered_quantity, v_already_received
        FROM public.purchase_order_items AS poi WHERE poi.po_id = p_po_id AND poi.sku = item.sku FOR UPDATE;
        
        IF NOT FOUND THEN RAISE EXCEPTION 'SKU % not found in this purchase order.', item.sku; END IF;
        
        v_can_receive := v_ordered_quantity - v_already_received;
        
        IF item.quantity_to_receive > v_can_receive THEN
            RAISE EXCEPTION 'Cannot receive % units for SKU %. Only % are outstanding.', item.quantity_to_receive, item.sku, v_can_receive;
        END IF;
        
        IF item.quantity_to_receive > 0 THEN
            UPDATE public.purchase_order_items SET quantity_received = quantity_received + item.quantity_to_receive WHERE po_id = p_po_id AND sku = item.sku;
            UPDATE public.inventory
            SET
                quantity = quantity + item.quantity_to_receive,
                on_order_quantity = on_order_quantity - item.quantity_to_receive
            WHERE company_id = p_company_id AND sku = item.sku;
            INSERT INTO public.inventory_ledger (company_id, sku, change_type, quantity_change, new_quantity, related_id)
            VALUES (p_company_id, item.sku, 'purchase_order_received', item.quantity_to_receive, (SELECT quantity FROM public.inventory WHERE sku=item.sku AND company_id=p_company_id), p_po_id);
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

DROP FUNCTION IF EXISTS public.record_sale_transaction(uuid, uuid, jsonb, text, text, text, text, text);
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
RETURNS public.sales
LANGUAGE plpgsql
AS $$
DECLARE
    new_sale public.sales;
    item_record record;
    total_amount bigint := 0;
    current_inventory record;
    inventory_updates jsonb := '[]'::jsonb;
BEGIN
    FOR item_record IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(sku text, quantity int) LOOP
        SELECT quantity, version INTO current_inventory FROM public.inventory WHERE sku = item_record.sku AND company_id = p_company_id AND deleted_at IS NULL FOR UPDATE;
        IF NOT FOUND OR current_inventory.quantity < item_record.quantity THEN
            RAISE EXCEPTION 'Insufficient stock for SKU: %. Available: %, Requested: %', item_record.sku, COALESCE(current_inventory.quantity, 0), item_record.quantity;
        END IF;
        inventory_updates := inventory_updates || jsonb_build_object('sku', item_record.sku, 'quantity', item_record.quantity, 'expected_version', current_inventory.version);
    END LOOP;

    FOR item_record IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(sku text, quantity int, unit_price bigint) LOOP
        total_amount := total_amount + (item_record.quantity * item_record.unit_price);
    END LOOP;

    INSERT INTO public.sales (company_id, sale_number, customer_name, customer_email, total_amount, payment_method, notes, created_by, external_id)
    VALUES (p_company_id, 'SALE-' || nextval('sales_sale_number_seq'::regclass), p_customer_name, p_customer_email, total_amount, p_payment_method, p_notes, p_user_id, p_external_id)
    RETURNING * INTO new_sale;

    FOR item_record IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(sku text, product_name text, quantity int, unit_price bigint, cost_at_time bigint) LOOP
        INSERT INTO public.sale_items (sale_id, company_id, sku, product_name, quantity, unit_price, cost_at_time)
        VALUES (new_sale.id, p_company_id, item_record.sku, item_record.product_name, item_record.quantity, item_record.unit_price, item_record.cost_at_time);
    END LOOP;
    
    PERFORM public.process_sales_order_inventory(new_sale.company_id, new_sale.id, inventory_updates);

    RETURN new_sale;
END;
$$;

DROP FUNCTION IF EXISTS public.update_inventory_item_with_lock(uuid, text, integer, text, text, bigint, integer, bigint, text, uuid);
CREATE OR REPLACE FUNCTION public.update_inventory_item_with_lock(
    p_company_id uuid,
    p_sku text,
    p_expected_version integer,
    p_name text,
    p_category text,
    p_cost bigint,
    p_reorder_point integer,
    p_landed_cost bigint,
    p_barcode text,
    p_location_id uuid
)
RETURNS public.inventory
LANGUAGE plpgsql
AS $$
DECLARE
    updated_item public.inventory;
BEGIN
    UPDATE public.inventory
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
        RAISE EXCEPTION 'Update failed. The item may have been modified by another process.';
    END IF;
    
    RETURN updated_item;
END;
$$;

DROP FUNCTION IF EXISTS public.update_purchase_order(uuid, uuid, uuid, text, text, date, date, text, jsonb);
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
DECLARE
  item_change record;
  new_total_amount bigint := 0;
BEGIN
    FOR item_change IN
        WITH old_items AS (
            SELECT oi.sku, oi.quantity_ordered FROM public.purchase_order_items AS oi WHERE oi.po_id = p_po_id
        ), new_items AS (
            SELECT ni.sku, ni.quantity_ordered FROM jsonb_to_recordset(p_items) AS ni(sku text, quantity_ordered int)
        )
        SELECT 
            COALESCE(oi.sku, ni.sku) as sku,
            COALESCE(ni.quantity_ordered, 0) - COALESCE(oi.quantity_ordered, 0) as quantity_diff
        FROM old_items AS oi
        FULL OUTER JOIN new_items AS ni ON oi.sku = ni.sku
    LOOP
        UPDATE public.inventory
        SET on_order_quantity = on_order_quantity + item_change.quantity_diff
        WHERE sku = item_change.sku AND company_id = p_company_id;
    END LOOP;
  
  DELETE FROM public.purchase_order_items WHERE po_id = p_po_id;

  FOR item_change IN SELECT * FROM jsonb_to_recordset(p_items) AS x(sku text, quantity_ordered int, unit_cost bigint)
  LOOP
    INSERT INTO public.purchase_order_items
      (po_id, sku, quantity_ordered, unit_cost)
    VALUES
      (p_po_id, item_change.sku, item_change.quantity_ordered, item_change.unit_cost);
    
    new_total_amount := new_total_amount + (item_change.quantity_ordered * item_change.unit_cost);
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
END;
$$;

DROP FUNCTION IF EXISTS public.validate_same_company_reference() CASCADE;
CREATE OR REPLACE FUNCTION public.validate_same_company_reference()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    ref_company_id uuid;
BEGIN
    IF TG_TABLE_NAME = 'purchase_orders' AND NEW.supplier_id IS NOT NULL THEN
        SELECT company_id INTO ref_company_id FROM public.vendors WHERE id = NEW.supplier_id;
        IF ref_company_id != NEW.company_id THEN
            RAISE EXCEPTION 'Security violation: Cannot reference a vendor from a different company.';
        END IF;
    END IF;

    IF TG_TABLE_NAME = 'inventory' AND NEW.location_id IS NOT NULL THEN
        SELECT company_id INTO ref_company_id FROM public.locations WHERE id = NEW.location_id;
        IF ref_company_id != NEW.company_id THEN
            RAISE EXCEPTION 'Security violation: Cannot assign to a location from a different company.';
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$;

DROP FUNCTION IF EXISTS public.get_inventory_analytics(uuid);
CREATE OR REPLACE FUNCTION public.get_inventory_analytics(p_company_id uuid)
RETURNS json
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN (
        SELECT json_build_object(
            'total_inventory_value', COALESCE(SUM(quantity * cost), 0),
            'total_skus', COUNT(DISTINCT sku),
            'low_stock_items', COUNT(*) FILTER (WHERE quantity <= reorder_point),
            'potential_profit', COALESCE(SUM((price - cost) * quantity), 0)
        )
        FROM public.inventory
        WHERE company_id = p_company_id AND deleted_at IS NULL
    );
END;
$$;

DROP FUNCTION IF EXISTS public.get_purchase_order_analytics(uuid);
CREATE OR REPLACE FUNCTION public.get_purchase_order_analytics(p_company_id uuid)
RETURNS json
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN (
        WITH po_stats AS (
            SELECT
                status,
                COUNT(*) as count,
                SUM(CASE WHEN status IN ('draft', 'sent', 'partial') THEN total_amount ELSE 0 END) as open_value,
                COUNT(*) FILTER (WHERE status IN ('draft', 'sent', 'partial') AND expected_date < NOW()) as overdue_count
            FROM public.purchase_orders
            WHERE company_id = p_company_id
            GROUP BY status
        ),
        lead_time_stats AS (
            SELECT AVG(updated_at::date - order_date::date) as avg_lead_time
            FROM public.purchase_orders
            WHERE company_id = p_company_id AND status = 'received' AND updated_at IS NOT NULL AND order_date IS NOT NULL
        )
        SELECT json_build_object(
            'open_po_value', COALESCE(SUM(open_value), 0),
            'overdue_po_count', COALESCE(SUM(overdue_count), 0),
            'avg_lead_time', COALESCE((SELECT avg_lead_time FROM lead_time_stats), 0),
            'status_distribution', (SELECT json_agg(json_build_object('name', status, 'value', count)) FROM po_stats)
        )
        FROM po_stats
    );
END;
$$;

DROP FUNCTION IF EXISTS public.get_sales_analytics(uuid);
CREATE OR REPLACE FUNCTION public.get_sales_analytics(p_company_id uuid)
RETURNS json
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN (
        WITH payment_methods AS (
            SELECT
                payment_method as name,
                COUNT(*) as value
            FROM public.sales
            WHERE company_id = p_company_id
            GROUP BY payment_method
        )
        SELECT json_build_object(
            'total_revenue', COALESCE(SUM(total_amount), 0),
            'average_sale_value', COALESCE(AVG(total_amount), 0),
            'payment_method_distribution', (SELECT json_agg(payment_methods) FROM payment_methods)
        )
        FROM public.sales
        WHERE company_id = p_company_id
    );
END;
$$;

DROP FUNCTION IF EXISTS public.get_suppliers_with_performance(uuid);
CREATE OR REPLACE FUNCTION public.get_suppliers_with_performance(p_company_id uuid)
RETURNS TABLE (
    id uuid,
    company_id uuid,
    vendor_name text,
    contact_info text,
    address text,
    terms text,
    account_number text,
    created_at timestamptz,
    on_time_delivery_rate numeric,
    average_lead_time_days numeric,
    total_completed_orders bigint
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        v.id,
        v.company_id,
        v.vendor_name,
        v.contact_info,
        v.address,
        v.terms,
        v.account_number,
        v.created_at,
        p.on_time_delivery_rate,
        p.average_lead_time_days,
        p.total_completed_orders
    FROM public.vendors AS v
    LEFT JOIN public.get_supplier_performance(p_company_id) AS p ON v.vendor_name = p.supplier_name
    WHERE v.company_id = p_company_id;
END;
$$;

DROP FUNCTION IF EXISTS public.get_business_profile(uuid);
CREATE OR REPLACE FUNCTION public.get_business_profile(p_company_id uuid)
RETURNS TABLE (monthly_revenue bigint, outstanding_po_value bigint, risk_tolerance text)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH monthly_sales AS (
        SELECT COALESCE(SUM(total_amount), 0) as revenue
        FROM public.sales
        WHERE company_id = p_company_id AND created_at >= NOW() - INTERVAL '30 days'
    ),
    open_pos AS (
        SELECT COALESCE(SUM(total_amount), 0) as po_value
        FROM public.purchase_orders
        WHERE company_id = p_company_id AND status IN ('draft', 'sent', 'partial')
    )
    SELECT
        (SELECT revenue FROM monthly_sales),
        (SELECT po_value FROM open_pos),
        'moderate'::text as risk_tolerance;
END;
$$;

DROP FUNCTION IF EXISTS public.health_check_inventory_consistency(uuid);
CREATE OR REPLACE FUNCTION public.health_check_inventory_consistency(p_company_id uuid)
RETURNS TABLE (healthy boolean, metric numeric, message text)
LANGUAGE plpgsql
AS $$
DECLARE
    negative_count int;
BEGIN
    SELECT COUNT(*) INTO negative_count
    FROM public.inventory
    WHERE company_id = p_company_id AND quantity < 0 AND deleted_at IS NULL;

    RETURN QUERY SELECT
        negative_count = 0,
        negative_count::numeric,
        CASE
            WHEN negative_count = 0 THEN 'Inventory levels are consistent.'
            ELSE negative_count || ' item(s) have negative stock, indicating data corruption.'
        END;
END;
$$;

DROP FUNCTION IF EXISTS public.health_check_financial_consistency(uuid);
CREATE OR REPLACE FUNCTION public.health_check_financial_consistency(p_company_id uuid)
RETURNS TABLE (healthy boolean, metric numeric, message text)
LANGUAGE plpgsql
AS $$
DECLARE
    mismatch_count int;
BEGIN
    SELECT COUNT(*) INTO mismatch_count
    FROM public.sale_items si
    WHERE si.company_id = p_company_id AND si.cost_at_time IS NULL;

    RETURN QUERY SELECT
        mismatch_count = 0,
        mismatch_count::numeric,
        CASE
            WHEN mismatch_count = 0 THEN 'All sales have recorded costs, financial data is consistent.'
            ELSE mismatch_count || ' sale line items are missing cost data, affecting profit reports.'
        END;
END;
$$;

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
CREATE POLICY "Users can only see their own company" ON public.companies FOR SELECT USING (id = COALESCE((SELECT company_id FROM public.users WHERE id = auth.uid() LIMIT 1), '00000000-0000-0000-0000-000000000000'::uuid));

DROP POLICY IF EXISTS "Users can only see users in their own company" ON public.users;
CREATE POLICY "Users can only see users in their own company" ON public.users FOR SELECT USING (company_id = COALESCE((SELECT company_id FROM public.users WHERE id = auth.uid() LIMIT 1), '00000000-0000-0000-0000-000000000000'::uuid));

DROP POLICY IF EXISTS "Users can manage settings for their own company" ON public.company_settings;
CREATE POLICY "Users can manage settings for their own company" ON public.company_settings FOR ALL USING (company_id = COALESCE((SELECT company_id FROM public.users WHERE id = auth.uid() LIMIT 1), '00000000-0000-0000-0000-000000000000'::uuid));

DROP POLICY IF EXISTS "Users can manage inventory for their own company" ON public.inventory;
CREATE POLICY "Users can manage inventory for their own company" ON public.inventory FOR ALL USING (company_id = COALESCE((SELECT company_id FROM public.users WHERE id = auth.uid() LIMIT 1), '00000000-0000-0000-0000-000000000000'::uuid));

DROP POLICY IF EXISTS "Users can manage vendors for their own company" ON public.vendors;
CREATE POLICY "Users can manage vendors for their own company" ON public.vendors FOR ALL USING (company_id = COALESCE((SELECT company_id FROM public.users WHERE id = auth.uid() LIMIT 1), '00000000-0000-0000-0000-000000000000'::uuid));

DROP POLICY IF EXISTS "Users can manage POs for their own company" ON public.purchase_orders;
CREATE POLICY "Users can manage POs for their own company" ON public.purchase_orders FOR ALL USING (company_id = COALESCE((SELECT company_id FROM public.users WHERE id = auth.uid() LIMIT 1), '00000000-0000-0000-0000-000000000000'::uuid));

DROP POLICY IF EXISTS "Users can manage PO Items for their own company" ON public.purchase_order_items;
CREATE POLICY "Users can manage PO Items for their own company" ON public.purchase_order_items FOR ALL USING (po_id IN (SELECT id FROM public.purchase_orders WHERE company_id = COALESCE((SELECT company_id FROM public.users WHERE id = auth.uid() LIMIT 1), '00000000-0000-0000-0000-000000000000'::uuid)));

DROP POLICY IF EXISTS "Users can manage sales for their own company" ON public.sales;
CREATE POLICY "Users can manage sales for their own company" ON public.sales FOR ALL USING (company_id = COALESCE((SELECT company_id FROM public.users WHERE id = auth.uid() LIMIT 1), '00000000-0000-0000-0000-000000000000'::uuid));

DROP POLICY IF EXISTS "Users can manage sale items for sales in their own company" ON public.sale_items;
CREATE POLICY "Users can manage sale items for sales in their own company" ON public.sale_items FOR ALL USING (sale_id IN (SELECT id FROM public.sales WHERE company_id = COALESCE((SELECT company_id FROM public.users WHERE id = auth.uid() LIMIT 1), '00000000-0000-0000-0000-000000000000'::uuid)) AND company_id = COALESCE((SELECT company_id FROM public.users WHERE id = auth.uid() LIMIT 1), '00000000-0000-0000-0000-000000000000'::uuid));

DROP POLICY IF EXISTS "Users can manage customers for their own company" ON public.customers;
CREATE POLICY "Users can manage customers for their own company" ON public.customers FOR ALL USING (company_id = COALESCE((SELECT company_id FROM public.users WHERE id = auth.uid() LIMIT 1), '00000000-0000-0000-0000-000000000000'::uuid));

DROP POLICY IF EXISTS "Users can manage locations for their own company" ON public.locations;
CREATE POLICY "Users can manage locations for their own company" ON public.locations FOR ALL USING (company_id = COALESCE((SELECT company_id FROM public.users WHERE id = auth.uid() LIMIT 1), '00000000-0000-0000-0000-000000000000'::uuid));

DROP POLICY IF EXISTS "Users can manage integrations for their own company" ON public.integrations;
CREATE POLICY "Users can manage integrations for their own company" ON public.integrations FOR ALL USING (company_id = COALESCE((SELECT company_id FROM public.users WHERE id = auth.uid() LIMIT 1), '00000000-0000-0000-0000-000000000000'::uuid));

DROP POLICY IF EXISTS "Users can manage ledger for their own company" ON public.inventory_ledger;
CREATE POLICY "Users can manage ledger for their own company" ON public.inventory_ledger FOR ALL USING (company_id = COALESCE((SELECT company_id FROM public.users WHERE id = auth.uid() LIMIT 1), '00000000-0000-0000-0000-000000000000'::uuid));

DROP POLICY IF EXISTS "Users can manage fees for their own company" ON public.channel_fees;
CREATE POLICY "Users can manage fees for their own company" ON public.channel_fees FOR ALL USING (company_id = COALESCE((SELECT company_id FROM public.users WHERE id = auth.uid() LIMIT 1), '00000000-0000-0000-0000-000000000000'::uuid));

DROP POLICY IF EXISTS "Users can manage export jobs for their own company" ON public.export_jobs;
CREATE POLICY "Users can manage export jobs for their own company" ON public.export_jobs FOR ALL USING (company_id = COALESCE((SELECT company_id FROM public.users WHERE id = auth.uid() LIMIT 1), '00000000-0000-0000-0000-000000000000'::uuid));

DROP POLICY IF EXISTS "Users can manage their own conversations" ON public.conversations;
CREATE POLICY "Users can manage their own conversations" ON public.conversations FOR ALL USING (user_id = COALESCE(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid));

DROP POLICY IF EXISTS "Users can manage their own messages" ON public.messages;
CREATE POLICY "Users can manage their own messages" ON public.messages FOR ALL USING (conversation_id IN (SELECT id FROM public.conversations WHERE user_id = COALESCE(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid)));

DROP POLICY IF EXISTS "Users can manage their own company's supplier catalogs" ON public.supplier_catalogs;
CREATE POLICY "Users can manage their own company's supplier catalogs" ON public.supplier_catalogs FOR ALL USING (supplier_id IN (SELECT id FROM public.vendors WHERE company_id = COALESCE((SELECT company_id FROM public.users WHERE id = auth.uid() LIMIT 1), '00000000-0000-0000-0000-000000000000'::uuid)));

DROP POLICY IF EXISTS "Users can manage their own company's reorder rules" ON public.reorder_rules;
CREATE POLICY "Users can manage their own company's reorder rules" ON public.reorder_rules FOR ALL USING (company_id = COALESCE((SELECT company_id FROM public.users WHERE id = auth.uid() LIMIT 1), '00000000-0000-0000-0000-000000000000'::uuid));

GRANT USAGE ON SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO postgres, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public to authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;

DROP TRIGGER IF EXISTS validate_purchase_order_refs on public.purchase_orders;
CREATE TRIGGER validate_purchase_order_refs
    BEFORE INSERT OR UPDATE ON public.purchase_orders
    FOR EACH ROW
    EXECUTE FUNCTION public.validate_same_company_reference();

DROP TRIGGER IF EXISTS validate_inventory_location_ref on public.inventory;
CREATE TRIGGER validate_inventory_location_ref
    BEFORE INSERT OR UPDATE ON public.inventory
    FOR EACH ROW
    EXECUTE FUNCTION public.validate_same_company_reference();

ALTER TABLE public.sale_items DROP CONSTRAINT IF EXISTS fk_sale_items_company;
ALTER TABLE public.sale_items
ADD CONSTRAINT fk_sale_items_company
FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;

ALTER TABLE public.inventory DROP CONSTRAINT IF EXISTS fk_inventory_location;
ALTER TABLE public.inventory
ADD CONSTRAINT fk_inventory_location
FOREIGN KEY (location_id) REFERENCES public.locations(id) ON DELETE SET NULL;
