-- Drop the existing function if it exists, to allow for signature changes.
DROP FUNCTION IF EXISTS public.get_dead_stock_report(uuid);

-- Create the missing get_dead_stock_report function
-- This function is referenced by get_dashboard_metrics but was never defined.
CREATE OR REPLACE FUNCTION public.get_dead_stock_report(p_company_id uuid)
RETURNS TABLE (
    sku text,
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
        COALESCE(SUM(pv.inventory_quantity * COALESCE(pv.cost, 0)), 0) as dead_stock_value
    FROM public.product_variants pv
    LEFT JOIN public.company_settings cs ON pv.company_id = cs.company_id
    LEFT JOIN (
        SELECT oli.sku, MAX(o.created_at) AS last_sale_date
        FROM public.order_line_items oli
        JOIN public.orders o ON oli.order_id = o.id
        WHERE o.company_id = p_company_id AND o.financial_status = 'paid'
        GROUP BY oli.sku
    ) ls ON pv.sku = ls.sku
    WHERE pv.company_id = p_company_id
      AND pv.inventory_quantity > 0
      AND (ls.last_sale_date IS NULL OR ls.last_sale_date < (CURRENT_DATE - INTERVAL '1 day' * COALESCE(cs.dead_stock_days, 90)))
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
