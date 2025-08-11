-- src/lib/database-schema.sql
-- This file is the single source of truth for the database schema.
-- It is designed to be idempotent and can be run on a fresh database.

-- Drop existing objects in reverse order of dependency to ensure a clean slate.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP VIEW IF EXISTS public.sales;
DROP VIEW IF EXISTS public.customers_view;
DROP VIEW IF EXISTS public.orders_view;
DROP VIEW IF EXISTS public.product_variants_with_details;
DROP VIEW IF EXISTS public.inventory;
DROP VIEW IF EXISTS public.purchase_orders_view;
DROP VIEW IF EXISTS public.audit_log_view;
DROP VIEW IF EXISTS public.feedback_view;

-- Drop functions that will be recreated
DROP FUNCTION IF EXISTS public.get_dashboard_metrics(uuid,integer);
DROP FUNCTION IF EXISTS public.get_sales_analytics(uuid);
DROP FUNCTION IF EXISTS public.get_inventory_analytics(uuid);
DROP FUNCTION IF EXISTS public.get_customer_analytics(uuid);
DROP FUNCTION IF EXISTS public.get_dead_stock_report(uuid);
DROP FUNCTION IF EXISTS public.get_reorder_suggestions(uuid);
DROP FUNCTION IF EXISTS public.get_supplier_performance_report(uuid);
DROP FUNCTION IF EXISTS public.get_inventory_turnover(uuid, integer);
DROP FUNCTION IF EXISTS public.get_abc_analysis(uuid);
DROP FUNCTION IF EXISTS public.forecast_demand(uuid);
DROP FUNCTION IF EXISTS public.get_sales_velocity(uuid,integer,integer);
DROP FUNCTION IF EXISTS public.get_margin_trends(uuid);
DROP FUNCTION IF EXISTS public.get_gross_margin_analysis(uuid);
DROP FUNCTION IF EXISTS public.get_net_margin_by_channel(uuid,text);
DROP FUNCTION IF EXISTS public.get_financial_impact_of_promotion(uuid,text[],double precision,integer);
DROP FUNCTION IF EXISTS public.get_historical_sales_for_sku(uuid,text);
DROP FUNCTION IF EXISTS public.get_historical_sales_for_skus(uuid,text[]);
DROP FUNCTION IF EXISTS public.check_user_permission(uuid, public.company_role);
DROP FUNCTION IF EXISTS public.get_users_for_company(uuid);
DROP FUNCTION IF EXISTS public.remove_user_from_company(uuid,uuid);
DROP FUNCTION IF EXISTS public.update_user_role_in_company(uuid,uuid,public.company_role);
DROP FUNCTION IF EXISTS public.adjust_inventory_quantity(uuid,uuid,integer,text,uuid);
DROP FUNCTION IF EXISTS public.create_full_purchase_order(uuid,uuid,uuid,text,text,date,jsonb);
DROP FUNCTION IF EXISTS public.update_full_purchase_order(uuid,uuid,uuid,uuid,text,text,date,jsonb);
DROP FUNCTION IF EXISTS public.create_purchase_orders_from_suggestions(uuid,uuid,jsonb);
DROP FUNCTION IF EXISTS public.record_order_from_platform(uuid,jsonb,text);
DROP FUNCTION IF EXISTS public.reconcile_inventory_from_integration(uuid,uuid,uuid);
DROP FUNCTION IF EXISTS public.refresh_all_matviews(uuid);

-- Recreate types
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'company_role') THEN
        CREATE TYPE public.company_role AS ENUM ('Owner', 'Admin', 'Member');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'integration_platform') THEN
        CREATE TYPE public.integration_platform AS ENUM ('shopify', 'woocommerce', 'amazon_fba');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'message_role') THEN
        CREATE TYPE public.message_role AS ENUM ('user', 'assistant', 'tool');
    END IF;
     IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'feedback_type') THEN
        CREATE TYPE public.feedback_type AS ENUM ('helpful', 'unhelpful');
    END IF;
END$$;


-- Create tables
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    name text NOT NULL,
    owner_id uuid NOT NULL REFERENCES auth.users(id),
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.company_users (
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role public.company_role DEFAULT 'Member'::public.company_role NOT NULL,
    PRIMARY KEY (user_id, company_id)
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_company_users_user ON public.company_users (user_id);


CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer DEFAULT 90 NOT NULL,
    fast_moving_days integer DEFAULT 30 NOT NULL,
    predictive_stock_days integer DEFAULT 7 NOT NULL,
    currency text DEFAULT 'USD'::text NOT NULL,
    timezone text DEFAULT 'UTC'::text NOT NULL,
    tax_rate real DEFAULT 0 NOT NULL,
    overstock_multiplier real DEFAULT 3 NOT NULL,
    high_value_threshold integer DEFAULT 100000 NOT NULL,
    alert_settings jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);


CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.products (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    external_product_id text,
    title text NOT NULL,
    description text,
    handle text,
    product_type text,
    status text,
    tags text[],
    image_url text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    UNIQUE (company_id, external_product_id)
);

CREATE TABLE IF NOT EXISTS public.product_variants (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    external_variant_id text,
    sku text NOT NULL,
    title text,
    option1_name text,
    option1_value text,
    option2_name text,
    option2_value text,
    option3_name text,
    option3_value text,
    barcode text,
    price integer,
    compare_at_price integer,
    cost integer,
    inventory_quantity integer DEFAULT 0 NOT NULL,
    location text,
    reorder_point integer,
    reorder_quantity integer,
    supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    UNIQUE (company_id, sku),
    UNIQUE (company_id, external_variant_id)
);

CREATE TABLE IF NOT EXISTS public.customers (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    external_customer_id text,
    name text,
    email text,
    phone text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    deleted_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.orders (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    external_order_id text,
    order_number text NOT NULL,
    customer_id uuid REFERENCES public.customers(id),
    financial_status text,
    fulfillment_status text,
    currency text,
    subtotal integer NOT NULL,
    total_discounts integer,
    total_shipping integer,
    total_tax integer,
    total_amount integer NOT NULL,
    source_platform text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    UNIQUE (company_id, external_order_id)
);

CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id uuid REFERENCES public.product_variants(id),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    external_line_item_id text,
    product_name text,
    variant_title text,
    sku text,
    quantity integer NOT NULL,
    price integer NOT NULL,
    total_discount integer,
    tax_amount integer,
    cost_at_time integer
);

CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.suppliers(id),
    po_number text NOT NULL,
    status text DEFAULT 'Draft'::text NOT NULL,
    expected_arrival_date date,
    total_cost integer NOT NULL,
    notes text,
    idempotency_key uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    purchase_order_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    quantity integer NOT NULL,
    cost integer NOT NULL
);

CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

-- AI & App specific tables
CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    last_accessed_at timestamp with time zone DEFAULT now() NOT NULL,
    is_starred boolean DEFAULT false NOT NULL
);

CREATE TABLE IF NOT EXISTS public.messages (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role public.message_role NOT NULL,
    content text NOT NULL,
    visualization jsonb,
    component text,
    "componentProps" jsonb,
    confidence real,
    assumptions text[],
    "isError" boolean,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

-- ... Other tables from your original schema (integrations, etc.) go here ...
CREATE TABLE IF NOT EXISTS public.integrations (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform public.integration_platform NOT NULL,
    shop_name text,
    shop_domain text,
    is_active boolean DEFAULT true NOT NULL,
    sync_status text,
    last_sync_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    UNIQUE (company_id, platform)
);

CREATE TABLE IF NOT EXISTS public.webhook_events (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    UNIQUE (integration_id, webhook_id)
);


CREATE TABLE IF NOT EXISTS public.audit_log (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id uuid REFERENCES auth.users(id),
    action text NOT NULL,
    details jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.feedback (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    subject_id text NOT NULL,
    subject_type text NOT NULL,
    feedback public.feedback_type NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.channel_fees (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    channel_name text NOT NULL,
    percentage_fee real,
    fixed_fee integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    UNIQUE (company_id, channel_name)
);

CREATE TABLE IF NOT EXISTS public.export_jobs (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    requested_by_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    status text DEFAULT 'pending'::text NOT NULL,
    download_url text,
    expires_at timestamp with time zone,
    error_message text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_at timestamp with time zone
);


-- Function to handle new user creation
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_name text;
  v_lock_key bigint;
BEGIN
  -- Use an advisory lock to prevent race conditions from concurrent signups
  v_lock_key := ('x' || substr(md5(new.id::text), 1, 16))::bit(64)::bigint;
  PERFORM pg_advisory_xact_lock(v_lock_key);

  -- Check if the user is already associated with a company (idempotency)
  SELECT company_id INTO v_company_id FROM public.company_users WHERE user_id = new.id LIMIT 1;
  IF v_company_id IS NOT NULL THEN
    RETURN new; -- Already handled
  END IF;

  -- Get company name from metadata or generate a default
  v_name := COALESCE(new.raw_user_meta_data->>'company_name', 'Company for ' || COALESCE(new.email, new.id::text));

  -- Create a new company for the user
  INSERT INTO public.companies (name, owner_id)
  VALUES (v_name, new.id)
  RETURNING id INTO v_company_id;

  -- Create default settings for the new company
  INSERT INTO public.company_settings (company_id)
  VALUES (v_company_id)
  ON CONFLICT (company_id) DO NOTHING;

  -- Associate the user with the new company
  INSERT INTO public.company_users (user_id, company_id, role)
  VALUES (new.id, v_company_id, 'Owner')
  ON CONFLICT (user_id, company_id) DO NOTHING;

  -- Update the user's app_metadata with the new company_id
  UPDATE auth.users
  SET raw_app_meta_data = COALESCE(raw_app_meta_data, '{}'::jsonb) || jsonb_build_object('company_id', v_company_id)
  WHERE id = new.id;
  
  RETURN new;
END;
$$;

-- Ensure the function is owned by postgres to have the necessary permissions
ALTER FUNCTION public.handle_new_user() OWNER TO postgres;

-- Create the trigger on the auth.users table
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- VIEWS
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.id,
    pv.product_id,
    pv.company_id,
    pv.external_variant_id,
    pv.sku,
    pv.title,
    pv.option1_name,
    pv.option1_value,
    pv.option2_name,
    pv.option2_value,
    pv.option3_name,
    pv.option3_value,
    pv.barcode,
    pv.price,
    pv.compare_at_price,
    pv.cost,
    pv.inventory_quantity,
    pv.location,
    pv.reorder_point,
    pv.reorder_quantity,
    pv.supplier_id,
    pv.created_at,
    pv.updated_at,
    p.title AS product_title,
    p.description AS product_description,
    p.handle AS product_handle,
    p.product_type,
    p.status AS product_status,
    p.tags AS product_tags,
    p.image_url
FROM public.product_variants pv
JOIN public.products p ON pv.product_id = p.id;

CREATE OR REPLACE VIEW public.sales AS
SELECT
    o.id AS order_id,
    o.company_id,
    o.order_number,
    o.created_at,
    o.source_platform,
    o.customer_id,
    oli.id AS line_item_id,
    oli.variant_id,
    oli.sku,
    oli.product_name,
    oli.quantity,
    oli.price,
    oli.cost_at_time,
    (oli.price * oli.quantity) AS total_revenue,
    ((oli.price - COALESCE(oli.cost_at_time, 0)) * oli.quantity) AS total_profit
FROM public.orders o
JOIN public.order_line_items oli ON o.id = oli.order_id
WHERE o.financial_status = 'paid';

CREATE OR REPLACE VIEW public.customers_view AS
 SELECT c.id,
    c.company_id,
    c.name as customer_name,
    c.email,
    c.phone,
    c.created_at,
    c.updated_at,
    c.deleted_at,
    count(o.id) AS total_orders,
    sum(o.total_amount) AS total_spent,
    min(o.created_at) AS first_order_date
   FROM (public.customers c
     LEFT JOIN public.orders o ON (((c.id = o.customer_id) AND (c.company_id = o.company_id))))
  WHERE (c.deleted_at IS NULL)
  GROUP BY c.id, c.company_id, c.name, c.email, c.phone, c.created_at, c.updated_at, c.deleted_at;


CREATE OR REPLACE VIEW public.orders_view AS
 SELECT o.id,
    o.company_id,
    o.external_order_id,
    o.order_number,
    o.customer_id,
    o.financial_status,
    o.fulfillment_status,
    o.currency,
    o.subtotal,
    o.total_discounts,
    o.total_shipping,
    o.total_tax,
    o.total_amount,
    o.source_platform,
    o.created_at,
    o.updated_at,
    c.email AS customer_email
   FROM (public.orders o
     LEFT JOIN public.customers c ON ((o.customer_id = c.id)));


-- FUNCTIONS
CREATE OR REPLACE FUNCTION public.get_dashboard_metrics(p_company_id uuid, p_days integer)
RETURNS jsonb
LANGUAGE sql STABLE
AS $$
WITH date_series AS (
    SELECT generate_series(
        CURRENT_DATE - (p_days - 1) * INTERVAL '1 day',
        CURRENT_DATE,
        '1 day'::interval
    )::date AS day
),
daily_sales AS (
    SELECT
        (s.created_at AT TIME ZONE 'UTC')::date AS sale_date,
        SUM(s.total_amount) AS daily_revenue
    FROM public.orders s
    WHERE s.company_id = p_company_id
      AND s.financial_status = 'paid'
      AND s.created_at >= (CURRENT_DATE - (p_days - 1) * INTERVAL '1 day')
    GROUP BY 1
),
sales_over_time AS (
    SELECT
        ds.day::text AS date,
        COALESCE(d.daily_revenue, 0) AS revenue
    FROM date_series ds
    LEFT JOIN daily_sales d ON ds.day = d.sale_date
    ORDER BY ds.day
),
current_period_sales AS (
    SELECT
        SUM(total_amount) AS total_revenue,
        COUNT(id) AS total_orders
    FROM public.orders
    WHERE company_id = p_company_id
      AND financial_status = 'paid'
      AND created_at >= (CURRENT_DATE - (p_days - 1) * INTERVAL '1 day')
),
previous_period_sales AS (
    SELECT
        SUM(total_amount) AS total_revenue,
        COUNT(id) AS total_orders
    FROM public.orders
    WHERE company_id = p_company_id
      AND financial_status = 'paid'
      AND created_at >= (CURRENT_DATE - (p_days * 2 - 1) * INTERVAL '1 day')
      AND created_at < (CURRENT_DATE - (p_days - 1) * INTERVAL '1 day')
),
customers_stats AS (
    SELECT
        COUNT(id) as new_customers
    FROM public.customers
    WHERE company_id = p_company_id
      AND created_at >= (CURRENT_DATE - (p_days - 1) * INTERVAL '1 day')
),
inventory_stats AS (
    SELECT
        SUM(pv.inventory_quantity * COALESCE(pv.cost, 0)) AS total_value,
        SUM(CASE WHEN pv.inventory_quantity > COALESCE(cs.dead_stock_days, 90) THEN pv.inventory_quantity * COALESCE(pv.cost, 0) ELSE 0 END) AS in_stock_value,
        SUM(CASE WHEN pv.inventory_quantity <= pv.reorder_point THEN pv.inventory_quantity * COALESCE(pv.cost, 0) ELSE 0 END) AS low_stock_value
    FROM public.product_variants pv
    JOIN public.company_settings cs ON pv.company_id = cs.company_id
    WHERE pv.company_id = p_company_id
),
dead_stock_agg AS (
    SELECT
        SUM(d.total_value) as dead_stock_value
    FROM get_dead_stock_report(p_company_id) d
)
SELECT jsonb_build_object(
    'total_revenue', COALESCE((SELECT total_revenue FROM current_period_sales), 0),
    'revenue_change', ((COALESCE((SELECT total_revenue FROM current_period_sales), 0) - COALESCE((SELECT total_revenue FROM previous_period_sales), 0)) / NULLIF(COALESCE((SELECT total_revenue FROM previous_period_sales), 0), 0) * 100),
    'total_orders', COALESCE((SELECT total_orders FROM current_period_sales), 0),
    'orders_change', ((COALESCE((SELECT total_orders FROM current_period_sales), 0)::float - COALESCE((SELECT total_orders FROM previous_period_sales), 0)::float) / NULLIF(COALESCE((SELECT total_orders FROM previous_period_sales), 0)::float, 0) * 100),
    'new_customers', COALESCE((SELECT new_customers FROM customers_stats), 0),
    'customers_change', 0, -- Placeholder for previous period customer comparison
    'dead_stock_value', COALESCE((SELECT dead_stock_value FROM dead_stock_agg), 0),
    'sales_over_time', (SELECT jsonb_agg(sot) FROM sales_over_time sot),
    'top_selling_products', (
        SELECT jsonb_agg(p) FROM (
            SELECT
                pvd.product_id,
                pvd.product_title AS product_name,
                pvd.image_url,
                SUM(s.quantity) AS quantity_sold,
                SUM(s.total_revenue) AS total_revenue
            FROM public.sales s
            JOIN public.product_variants_with_details pvd ON s.variant_id = pvd.id
            WHERE s.company_id = p_company_id
            GROUP BY 1, 2, 3
            ORDER BY 5 DESC
            LIMIT 5
        ) p
    ),
    'inventory_summary', (SELECT jsonb_build_object(
        'total_value', COALESCE(total_value,0), 'in_stock_value', COALESCE(in_stock_value,0), 'low_stock_value', COALESCE(low_stock_value,0), 'dead_stock_value', COALESCE((SELECT dead_stock_value FROM dead_stock_agg), 0)
    ) FROM inventory_stats)
)
$$;

CREATE OR REPLACE FUNCTION public.get_sales_analytics(p_company_id uuid)
RETURNS jsonb
LANGUAGE sql STABLE
AS $$
    WITH s AS (
      SELECT * FROM public.sales WHERE company_id = p_company_id
    )
    SELECT jsonb_build_object(
      'total_orders', (SELECT count(DISTINCT order_id) FROM s),
      'total_revenue', (SELECT coalesce(sum(line_total),0) FROM s),
      'average_order_value', (SELECT coalesce(sum(line_total),0) / NULLIF(count(DISTINCT order_id), 0) FROM s)
    )
$$;

CREATE OR REPLACE FUNCTION public.get_inventory_analytics(p_company_id uuid)
RETURNS jsonb
LANGUAGE sql STABLE
AS $$
  SELECT jsonb_build_object(
    'total_products', (SELECT count(DISTINCT product_id) FROM public.product_variants pv WHERE pv.company_id = p_company_id),
    'total_variants', (SELECT count(*) FROM public.product_variants pv WHERE pv.company_id = p_company_id),
    'total_inventory_units', (SELECT coalesce(sum(pv.inventory_quantity),0) FROM public.product_variants pv WHERE pv.company_id = p_company_id),
    'total_inventory_value', (SELECT coalesce(sum(coalesce(pv.cost,0) * pv.inventory_quantity),0) FROM public.product_variants pv WHERE pv.company_id = p_company_id),
    'low_stock_items', (SELECT count(*) FROM public.product_variants pv WHERE pv.company_id = p_company_id AND pv.inventory_quantity <= pv.reorder_point)
  )
$$;
