
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
    external_id text
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

CREATE OR REPLACE FUNCTION public.refresh_dashboard_metrics_for_company(p_company_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY public.company_dashboard_metrics;
END;
$$;

-- All other functions from previous attempts have been consolidated or fixed below.
-- Recreating all functions ensures they are correct.
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
    ORDER BY category;
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
    total_count_result bigint;
BEGIN
    WITH filtered_inventory AS (
        SELECT 
            i.sku,
            i.name as product_name,
            i.category,
            i.quantity,
            i.cost,
            i.price,
            (i.quantity * i.cost) as total_value,
            i.reorder_point,
            i.on_order_quantity,
            i.landed_cost,
            i.barcode,
            i.location_id,
            l.name as location_name,
            COALESCE(
                (SELECT SUM(si.quantity) 
                 FROM public.sales s 
                 JOIN public.sale_items si ON s.id = si.sale_id 
                 WHERE si.sku = i.sku 
                   AND s.company_id = i.company_id 
                   AND s.created_at >= (NOW() - interval '30 days')
                ), 0
            ) as monthly_units_sold,
            COALESCE(
                (SELECT SUM(si.quantity * (si.unit_price - i.cost))
                 FROM public.sales s 
                 JOIN public.sale_items si ON s.id = si.sale_id 
                 WHERE si.sku = i.sku 
                   AND s.company_id = i.company_id 
                   AND s.created_at >= (NOW() - interval '30 days')
                ), 0
            ) as monthly_profit,
            i.version
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
    count_query AS (
        SELECT count(*) as total FROM filtered_inventory
    )
    SELECT 
        (SELECT COALESCE(json_agg(fi.*), '[]'::json) FROM (SELECT * FROM filtered_inventory ORDER BY product_name LIMIT p_limit OFFSET p_offset) fi),
        (SELECT total FROM count_query)
    INTO result_items, total_count_result;

    RETURN QUERY SELECT result_items, total_count_result;
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
            c.id, c.company_id, c.platform, c.external_id, c.customer_name,
            c.email, c.status, c.deleted_at, c.created_at,
            COUNT(s.id) as total_sales,
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
    count_query AS (SELECT count(*) as total FROM customer_stats)
    SELECT json_build_object(
        'items', COALESCE((SELECT json_agg(cs) FROM (
            SELECT * FROM customer_stats ORDER BY total_spend DESC LIMIT p_limit OFFSET p_offset
        ) cs), '[]'::json),
        'totalCount', (SELECT total FROM count_query)
    ) INTO result_json;
    
    RETURN result_json;
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
        'low_stock'::text, i.sku, i.name, i.quantity, i.reorder_point,
        i.last_sold_date, (i.quantity * i.cost), NULL::numeric
    FROM inventory i
    WHERE i.company_id = p_company_id AND i.reorder_point IS NOT NULL AND i.quantity <= i.reorder_point AND i.quantity > 0 AND i.deleted_at IS NULL

    UNION ALL

    -- Dead Stock Alerts
    SELECT
        'dead_stock'::text, i.sku, i.name, i.quantity, i.reorder_point,
        i.last_sold_date, (i.quantity * i.cost), NULL::numeric
    FROM inventory i
    WHERE i.company_id = p_company_id AND i.last_sold_date < (NOW() - (p_dead_stock_days || ' day')::interval) AND i.deleted_at IS NULL

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
            'predictive'::text, i.sku, i.name, i.quantity, i.reorder_point,
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
