
export const SETUP_SQL_SCRIPT = `
-- InvoChat Database Setup Script
-- Idempotent: Can be run multiple times without causing errors.

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Step 1: Types and Sequences
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE public.user_role AS ENUM ('Owner', 'Admin', 'Member');
    END IF;
END
$$;

CREATE SEQUENCE IF NOT EXISTS sales_sale_number_seq;

-- Step 2: Core Tables
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    name text NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.users (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT,
    email text,
    role public.user_role NOT NULL DEFAULT 'Member',
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now()
);

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

-- Step 3: Entity Tables
CREATE TABLE IF NOT EXISTS public.products (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku text NOT NULL,
    name text NOT NULL,
    category text,
    barcode text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, sku)
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
    company_id uuid NOT NULL,
    product_id uuid NOT NULL,
    location_id uuid REFERENCES public.locations(id) ON DELETE SET NULL,
    quantity integer NOT NULL DEFAULT 0,
    reorder_point integer,
    on_order_quantity integer NOT NULL DEFAULT 0,
    cost bigint NOT NULL DEFAULT 0,
    price bigint,
    landed_cost bigint,
    last_sold_date date,
    version integer NOT NULL DEFAULT 1,
    deleted_at timestamptz,
    deleted_by uuid REFERENCES auth.users(id),
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    source_platform text,
    external_product_id text,
    external_variant_id text,
    external_quantity integer,
    CONSTRAINT fk_inventory_company FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT fk_inventory_product FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE,
    UNIQUE(company_id, product_id, location_id),
    CONSTRAINT inventory_quantity_non_negative CHECK ((quantity >= 0)),
    CONSTRAINT on_order_quantity_non_negative CHECK ((on_order_quantity >= 0)),
    CONSTRAINT price_non_negative CHECK ((price IS NULL OR price >= 0))
);
CREATE INDEX IF NOT EXISTS inventory_location_id_idx ON public.inventory(location_id);
CREATE INDEX IF NOT EXISTS inventory_product_id_idx ON public.inventory(product_id);


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

CREATE TABLE IF NOT EXISTS public.customers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform text,
    external_id text,
    customer_name text NOT NULL,
    email text,
    status text,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now(),
    UNIQUE(company_id, email)
);
CREATE INDEX IF NOT EXISTS customers_email_idx ON public.customers(email);


-- Step 4: Transactional Tables
CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.vendors(id) ON DELETE SET NULL,
    po_number text NOT NULL,
    status text,
    order_date date,
    expected_date date,
    total_amount bigint,
    tax_amount bigint,
    shipping_cost bigint,
    notes text,
    requires_approval boolean DEFAULT false,
    approved_by uuid REFERENCES auth.users(id),
    approved_at timestamptz,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, po_number),
    CONSTRAINT order_date_before_expected CHECK (expected_date IS NULL OR order_date <= expected_date)
);

CREATE TABLE IF NOT EXISTS public.purchase_order_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    po_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id),
    quantity_ordered integer NOT NULL,
    quantity_received integer DEFAULT 0 NOT NULL,
    unit_cost bigint,
    tax_rate numeric(5,4),
    UNIQUE(po_id, product_id)
);
CREATE INDEX IF NOT EXISTS po_items_po_id_idx ON public.purchase_order_items(po_id);
CREATE INDEX IF NOT EXISTS po_items_product_id_idx ON public.purchase_order_items(product_id);


CREATE TABLE IF NOT EXISTS public.sales (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sale_number text NOT NULL UNIQUE,
    customer_name text,
    customer_email text,
    total_amount bigint NOT NULL,
    tax_amount bigint,
    payment_method text,
    notes text,
    created_at timestamptz DEFAULT now(),
    created_by uuid REFERENCES auth.users(id),
    external_id text,
    UNIQUE(company_id, sale_number)
);
CREATE INDEX IF NOT EXISTS sales_created_at_idx ON public.sales(created_at);

CREATE TABLE IF NOT EXISTS public.sale_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    sale_id uuid NOT NULL REFERENCES public.sales(id) ON DELETE CASCADE,
    company_id uuid, -- Allow NULL initially
    product_id uuid NOT NULL,
    quantity integer NOT NULL,
    unit_price bigint NOT NULL,
    cost_at_time bigint,
    UNIQUE(sale_id, product_id)
);
CREATE INDEX IF NOT EXISTS sale_items_sale_id_idx ON public.sale_items(sale_id);
CREATE INDEX IF NOT EXISTS sale_items_product_id_idx ON public.sale_items(product_id);


DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'sale_items' AND column_name = 'company_id'
    ) THEN
        ALTER TABLE public.sale_items ADD COLUMN company_id uuid;
    END IF;
    
    IF EXISTS (SELECT 1 FROM public.sale_items WHERE company_id IS NULL) THEN
        UPDATE public.sale_items si
        SET company_id = s.company_id
        FROM public.sales s
        WHERE si.sale_id = s.id AND si.company_id IS NULL;
    END IF;
    
    -- Correctly update existing NULL cost_at_time to prevent NOT NULL violation
    UPDATE public.sale_items si
    SET cost_at_time = (
        SELECT i.cost
        FROM public.inventory i
        WHERE i.product_id = si.product_id
          AND i.company_id = si.company_id
          AND i.deleted_at IS NULL
        LIMIT 1
    )
    WHERE si.cost_at_time IS NULL;

    ALTER TABLE public.sale_items ALTER COLUMN company_id SET NOT NULL;
    ALTER TABLE public.sale_items ALTER COLUMN cost_at_time SET NOT NULL;
END $$;

ALTER TABLE public.sale_items DROP CONSTRAINT IF EXISTS fk_sale_items_company;
ALTER TABLE public.sale_items ADD CONSTRAINT fk_sale_items_company FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id),
    location_id uuid NOT NULL REFERENCES public.locations(id),
    created_at timestamptz DEFAULT now() NOT NULL,
    created_by uuid REFERENCES auth.users(id),
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer,
    related_id uuid,
    notes text
);

-- Step 5: Supporting Tables
CREATE TABLE IF NOT EXISTS public.supplier_catalogs (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    supplier_id uuid NOT NULL REFERENCES public.vendors(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    supplier_sku text,
    unit_cost bigint NOT NULL,
    moq integer DEFAULT 1,
    lead_time_days integer,
    is_active boolean DEFAULT true,
    created_at timestamptz DEFAULT now(),
    UNIQUE(supplier_id, product_id)
);

CREATE TABLE IF NOT EXISTS public.reorder_rules (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    rule_type text DEFAULT 'manual',
    min_stock integer,
    max_stock integer,
    reorder_quantity integer,
    UNIQUE(company_id, product_id)
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
  last_sync_at timestamptz,
  sync_status text,
  created_at timestamptz DEFAULT now() NOT NULL,
  updated_at timestamptz,
  UNIQUE(company_id, platform)
);

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
    company_id uuid REFERENCES public.companies(id),
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

CREATE TABLE IF NOT EXISTS public.user_feedback (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL REFERENCES auth.users(id),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    subject_id text NOT NULL,
    subject_type text NOT NULL,
    feedback text NOT NULL,
    created_at timestamptz DEFAULT now()
);

-- Step 6: Materialized Views
CREATE MATERIALIZED VIEW IF NOT EXISTS public.company_dashboard_metrics AS
SELECT
  p.company_id,
  COUNT(DISTINCT p.id) as total_skus,
  SUM(i.quantity * i.cost) as inventory_value,
  COUNT(CASE WHEN i.quantity <= i.reorder_point AND i.reorder_point > 0 THEN 1 END) as low_stock_count
FROM public.products p
JOIN public.inventory i ON p.id = i.product_id AND p.company_id = i.company_id
WHERE i.deleted_at IS NULL
GROUP BY p.company_id;
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


-- Step 7: Functions
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

CREATE OR REPLACE FUNCTION public.refresh_materialized_views(p_company_id uuid, p_view_names text[] DEFAULT ARRAY['company_dashboard_metrics', 'customer_analytics_metrics'])
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    view_name text;
BEGIN
    FOREACH view_name IN ARRAY p_view_names LOOP
        EXECUTE 'REFRESH MATERIALIZED VIEW CONCURRENTLY public.' || quote_ident(view_name);
    END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_distinct_categories(p_company_id uuid)
RETURNS TABLE(category text)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT p.category::text
    FROM public.products AS p
    WHERE p.company_id = p_company_id
    AND p.category IS NOT NULL
    AND p.category <> ''
    ORDER BY p.category::text;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_alerts(
    p_company_id uuid,
    p_dead_stock_days integer,
    p_fast_moving_days integer,
    p_predictive_stock_days integer
)
RETURNS TABLE(type text, product_id uuid, product_name text, current_stock integer, reorder_point integer, last_sold_date date, value numeric, days_of_stock_remaining numeric)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        'low_stock'::text AS type, p.id, p.name::text, i.quantity, i.reorder_point,
        i.last_sold_date, (i.quantity * i.cost)::numeric AS value, NULL::numeric AS days_of_stock_remaining
    FROM public.inventory i
    JOIN public.products p ON i.product_id = p.id AND i.company_id = p.company_id
    WHERE i.company_id = p_company_id AND i.reorder_point IS NOT NULL AND i.quantity <= i.reorder_point AND i.quantity > 0 AND i.deleted_at IS NULL

    UNION ALL

    SELECT
        'dead_stock'::text, p.id, p.name::text, i.quantity, i.reorder_point,
        i.last_sold_date, (i.quantity * i.cost)::numeric, NULL::numeric
    FROM public.inventory i
    JOIN public.products p ON i.product_id = p.id AND i.company_id = p.company_id
    WHERE i.company_id = p_company_id AND i.deleted_at IS NULL AND i.quantity > 0 AND (i.last_sold_date IS NULL OR i.last_sold_date < (NOW() - (p_dead_stock_days || ' day')::interval))

    UNION ALL

    (
        WITH sales_velocity AS (
          SELECT
            si.product_id,
            SUM(si.quantity)::numeric / p_fast_moving_days as daily_sales
          FROM public.sale_items si
          JOIN public.sales s ON si.sale_id = s.id AND si.company_id = s.company_id
          WHERE s.company_id = p_company_id AND s.created_at >= (NOW() - (p_fast_moving_days || ' day')::interval)
          GROUP BY si.product_id
        )
        SELECT
            'predictive'::text, p.id, p.name::text, i.quantity, i.reorder_point,
            i.last_sold_date, (i.quantity * i.cost)::numeric, (i.quantity / sv.daily_sales)
        FROM public.inventory i
        JOIN public.products p ON i.product_id = p.id AND i.company_id = p.company_id
        JOIN sales_velocity sv ON i.product_id = sv.product_id
        WHERE i.company_id = p_company_id AND sv.daily_sales > 0 AND (i.quantity / sv.daily_sales) <= p_predictive_stock_days AND i.deleted_at IS NULL
    );
END;
$$;

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
    FROM anomalies a
    WHERE ABS(COALESCE(a.revenue_deviation, 0)) > 2 OR ABS(COALESCE(a.customers_deviation, 0)) > 2;
END;
$$;

CREATE OR REPLACE FUNCTION public.check_inventory_references(p_company_id uuid, p_product_ids uuid[])
RETURNS TABLE(product_id uuid)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH referenced_products AS (
        -- Get all product_ids from sales for the given company
        SELECT si.product_id
        FROM public.sale_items si
        WHERE si.company_id = p_company_id AND si.product_id = ANY(p_product_ids)
        UNION ALL
        -- Get all product_ids from purchase orders for the given company
        SELECT poi.product_id
        FROM public.purchase_order_items poi
        JOIN public.purchase_orders po ON poi.po_id = po.id
        WHERE po.company_id = p_company_id AND poi.product_id = ANY(p_product_ids)
    )
    SELECT DISTINCT rp.product_id::uuid
    FROM referenced_products rp;
END;
$$;

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
    tax_amount bigint := 0;
    company_tax_rate numeric;
    current_inventory record;
    min_stock_level integer;
    v_product_id uuid;
BEGIN
    IF EXISTS (SELECT 1 FROM jsonb_to_recordset(p_sale_items) AS x(created_at timestamptz) WHERE x.created_at > NOW()) THEN
      RAISE EXCEPTION 'Sale date cannot be in the future.';
    END IF;

    FOR item_record IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(product_id uuid, quantity int) LOOP
        v_product_id := item_record.product_id;
        
        -- Lock the inventory row to prevent race conditions
        SELECT i.quantity, i.location_id INTO current_inventory FROM public.inventory i WHERE i.product_id = v_product_id AND i.company_id = p_company_id AND i.deleted_at IS NULL FOR UPDATE;
        
        IF NOT FOUND OR current_inventory.quantity < item_record.quantity THEN
            RAISE EXCEPTION 'Insufficient stock for product_id: %. Available: %, Requested: %', v_product_id, COALESCE(current_inventory.quantity, 0), item_record.quantity;
        END IF;

        -- Enforce minimum stock level
        SELECT rr.min_stock INTO min_stock_level FROM public.reorder_rules rr WHERE rr.product_id = v_product_id AND rr.company_id = p_company_id;
        IF min_stock_level IS NOT NULL AND (current_inventory.quantity - item_record.quantity) < min_stock_level THEN
            RAISE EXCEPTION 'This sale would bring stock for product_id % below its minimum level of %.', v_product_id, min_stock_level;
        END IF;
    END LOOP;

    SELECT tax_rate INTO company_tax_rate FROM public.company_settings WHERE company_id = p_company_id;
    company_tax_rate := COALESCE(company_tax_rate, 0);

    FOR item_record IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(quantity int, unit_price bigint) LOOP
        total_amount := total_amount + (item_record.quantity * item_record.unit_price);
    END LOOP;
    
    tax_amount := total_amount * company_tax_rate;
    total_amount := total_amount + tax_amount;

    INSERT INTO public.sales (company_id, sale_number, customer_name, customer_email, total_amount, tax_amount, payment_method, notes, created_by, external_id)
    VALUES (p_company_id, 'SALE-' || nextval('sales_sale_number_seq'::regclass), p_customer_name, p_customer_email, total_amount, tax_amount, p_payment_method, p_notes, p_user_id, p_external_id)
    RETURNING * INTO new_sale;

    FOR item_record IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(product_id uuid, quantity int, unit_price bigint, cost_at_time bigint) LOOP
        INSERT INTO public.sale_items (sale_id, company_id, product_id, quantity, unit_price, cost_at_time)
        VALUES (new_sale.id, p_company_id, item_record.product_id, item_record.quantity, item_record.unit_price, item_record.cost_at_time);
    END LOOP;
    
    RETURN new_sale;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_audit_log(
    p_user_id uuid,
    p_company_id uuid,
    p_action text,
    p_details jsonb
)
RETURNS void AS $$
BEGIN
    INSERT INTO public.audit_log (user_id, company_id, action, details)
    VALUES (p_user_id, p_company_id, p_action, p_details);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.purge_soft_deleted_data(p_retention_days integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    DELETE FROM public.inventory
    WHERE deleted_at < NOW() - (p_retention_days || ' days')::interval;
    
    DELETE FROM public.customers
    WHERE deleted_at < NOW() - (p_retention_days || ' days')::interval;
END;
$$;

CREATE OR REPLACE FUNCTION public.transfer_inventory(
    p_company_id uuid,
    p_product_id uuid,
    p_from_location_id uuid,
    p_to_location_id uuid,
    p_quantity integer,
    p_notes text,
    p_user_id uuid
) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    from_loc_quantity integer;
BEGIN
    IF p_from_location_id = p_to_location_id THEN
        RAISE EXCEPTION 'Source and destination locations cannot be the same.';
    END IF;

    -- Lock source inventory row
    SELECT quantity INTO from_loc_quantity FROM public.inventory WHERE product_id = p_product_id AND location_id = p_from_location_id AND company_id = p_company_id FOR UPDATE;

    IF NOT FOUND OR from_loc_quantity < p_quantity THEN
        RAISE EXCEPTION 'Insufficient stock at source location. Available: %, Requested: %', COALESCE(from_loc_quantity, 0), p_quantity;
    END IF;

    -- Decrement from source
    UPDATE public.inventory SET quantity = quantity - p_quantity WHERE product_id = p_product_id AND location_id = p_from_location_id AND company_id = p_company_id;

    -- Increment or insert into destination
    INSERT INTO public.inventory (company_id, product_id, location_id, quantity, cost, price)
    SELECT p_company_id, p_product_id, p_to_location_id, p_quantity, cost, price
    FROM public.inventory
    WHERE product_id = p_product_id AND location_id = p_from_location_id AND company_id = p_company_id
    ON CONFLICT (company_id, product_id, location_id) DO UPDATE
    SET quantity = inventory.quantity + p_quantity;

    -- Log both sides of the transfer
    INSERT INTO public.inventory_ledger (company_id, product_id, location_id, created_by, change_type, quantity_change, new_quantity, notes)
    VALUES
        (p_company_id, p_product_id, p_from_location_id, p_user_id, 'transfer_out', -p_quantity, (SELECT quantity FROM public.inventory WHERE product_id = p_product_id AND location_id = p_from_location_id), p_notes),
        (p_company_id, p_product_id, p_to_location_id, p_user_id, 'transfer_in', p_quantity, (SELECT quantity FROM public.inventory WHERE product_id = p_product_id AND location_id = p_to_location_id), p_notes);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_inventory_aging_report(p_company_id uuid)
RETURNS TABLE(
    product_name text,
    sku text,
    days_since_last_sale integer,
    quantity integer,
    total_value bigint
) LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.name as product_name,
        p.sku,
        EXTRACT(DAY FROM (NOW() - COALESCE(i.last_sold_date, i.created_at)))::integer as days_since_last_sale,
        i.quantity,
        (i.quantity * i.cost)::bigint as total_value
    FROM public.inventory i
    JOIN public.products p ON i.product_id = p.id AND i.company_id = p.company_id
    WHERE i.company_id = p_company_id AND i.deleted_at IS NULL AND i.quantity > 0
    ORDER BY days_since_last_sale DESC;
END;
$$;

-- Step 8: Triggers
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

DROP TRIGGER IF EXISTS handle_inventory_update ON public.inventory;
CREATE TRIGGER handle_inventory_update
BEFORE UPDATE ON public.inventory
FOR EACH ROW
EXECUTE PROCEDURE public.increment_version();

-- Step 9: RLS Policies
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
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
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_feedback ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can only see their own company" ON public.companies;
CREATE POLICY "Users can only see their own company" ON public.companies FOR SELECT USING (id = COALESCE((SELECT company_id FROM public.users WHERE id = auth.uid() LIMIT 1), '00000000-0000-0000-0000-000000000000'::uuid));
DROP POLICY IF EXISTS "Users can only see users in their own company" ON public.users;
CREATE POLICY "Users can only see users in their own company" ON public.users FOR SELECT USING (company_id = COALESCE((SELECT company_id FROM public.users WHERE id = auth.uid() LIMIT 1), '00000000-0000-0000-0000-000000000000'::uuid));
DROP POLICY IF EXISTS "Users can manage settings for their own company" ON public.company_settings;
CREATE POLICY "Users can manage settings for their own company" ON public.company_settings FOR ALL USING (company_id = COALESCE((SELECT company_id FROM public.users WHERE id = auth.uid() LIMIT 1), '00000000-0000-0000-0000-000000000000'::uuid));
DROP POLICY IF EXISTS "Users can manage products for their own company" ON public.products;
CREATE POLICY "Users can manage products for their own company" ON public.products FOR ALL USING (company_id = COALESCE((SELECT company_id FROM public.users WHERE id = auth.uid() LIMIT 1), '00000000-0000-0000-0000-000000000000'::uuid));
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
CREATE POLICY "Users can manage sale items for sales in their own company" ON public.sale_items FOR ALL USING (company_id = COALESCE((SELECT company_id FROM public.users WHERE id = auth.uid() LIMIT 1), '00000000-0000-0000-0000-000000000000'::uuid));
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
DROP POLICY IF EXISTS "Users can manage audit logs for their own company" ON public.audit_log;
CREATE POLICY "Users can manage audit logs for their own company" ON public.audit_log FOR ALL USING (company_id = COALESCE((SELECT company_id FROM public.users WHERE id = auth.uid() LIMIT 1), '00000000-0000-0000-0000-000000000000'::uuid));
DROP POLICY IF EXISTS "Users can manage their own feedback" ON public.user_feedback;
CREATE POLICY "Users can manage their own feedback" ON public.user_feedback FOR ALL USING (user_id = auth.uid());

-- Step 10: Grants
GRANT USAGE ON SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO postgres, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public to authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
`;
