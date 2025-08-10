-- supabase/seed.sql
-- This file is executed by Supabase when the database is created.
-- It's a good place to define your initial schema, tables, and RLS policies.
-- For more information, see: https://supabase.com/docs/guides/database/managing-tables

-- Set up Row Level Security
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;

-- Create the auth.company_id() function that RLS policies need
CREATE OR REPLACE FUNCTION auth.company_id()
RETURNS UUID AS $$
DECLARE
    company_id_val UUID;
BEGIN
    -- Get company_id from JWT token
    company_id_val := NULLIF(current_setting('request.jwt.claims', true)::JSONB -> 'app_metadata' ->> 'company_id', '')::UUID;
    
    -- If not found, get from users table as a fallback (e.g., during tests)
    IF company_id_val IS NULL THEN
        SELECT (raw_app_meta_data ->> 'company_id')::UUID
        INTO company_id_val
        FROM auth.users
        WHERE id = auth.uid();
    END IF;
    
    RETURN company_id_val;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- Grant usage on the function to authenticated users
GRANT EXECUTE ON FUNCTION auth.company_id() TO authenticated;


-- RLS Policies
-- Companies: Users can only see the company they belong to.
CREATE POLICY "Users can view their own company"
ON public.companies FOR SELECT
USING (id = auth.company_id());

-- Company Users: Users can see other members of their own company.
CREATE POLICY "Users can view members of their own company"
ON public.company_users FOR SELECT
USING (company_id = auth.company_id());

-- Generic RLS Policy for all tables with a company_id column
DO $$
DECLARE
    t TEXT;
BEGIN
    FOR t IN 
        SELECT table_name FROM information_schema.columns WHERE column_name = 'company_id' AND table_schema = 'public'
    LOOP
        EXECUTE format('CREATE POLICY "Users can only access their own company data" ON public.%I FOR ALL USING (company_id = auth.company_id());', t);
    END LOOP;
END;
$$;


-- A trigger to automatically create a company for a new user and link them.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    new_company_id UUID;
    user_company_name TEXT;
BEGIN
    -- Extract company_name from metadata, default if not present
    user_company_name := COALESCE(new.raw_user_meta_data ->> 'company_name', 'My New Company');

    -- Create a new company for the user
    INSERT INTO public.companies (name, owner_id)
    VALUES (user_company_name, new.id)
    RETURNING id INTO new_company_id;

    -- Link the user to the new company as an Owner
    INSERT INTO public.company_users (user_id, company_id, role)
    VALUES (new.id, new_company_id, 'Owner');
    
    -- Update the user's app_metadata with the new company_id
    UPDATE auth.users
    SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id)
    WHERE id = new.id;

    RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create the trigger on the auth.users table
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Create materialized views for performance
CREATE MATERIALIZED VIEW public.customers_view AS
SELECT
    c.id,
    c.company_id,
    c.name AS customer_name,
    c.email,
    COUNT(o.id) AS total_orders,
    COALESCE(SUM(o.total_amount), 0) AS total_spent,
    MIN(o.created_at) AS first_order_date,
    c.created_at
FROM
    public.customers c
LEFT JOIN
    public.orders o ON c.id = o.customer_id AND o.company_id = c.company_id
WHERE c.deleted_at IS NULL
GROUP BY
    c.id, c.company_id;
CREATE UNIQUE INDEX ON public.customers_view (id);

CREATE MATERIALIZED VIEW public.product_variants_with_details AS
SELECT
    pv.*,
    p.title as product_title,
    p.status as product_status,
    p.image_url,
    p.product_type
FROM
    public.product_variants pv
JOIN
    public.products p ON pv.product_id = p.id;
CREATE UNIQUE INDEX ON public.product_variants_with_details (id);

CREATE MATERIALIZED VIEW public.orders_view AS
SELECT
    o.*,
    c.email as customer_email
FROM
    public.orders o
LEFT JOIN
    public.customers c ON o.customer_id = c.id;
CREATE UNIQUE INDEX ON public.orders_view (id);

CREATE OR REPLACE FUNCTION refresh_all_matviews(p_company_id UUID)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  -- Refresh views that depend on base tables
  REFRESH MATERIALIZED VIEW CONCURRENTLY customers_view;
  REFRESH MATERIALIZED VIEW CONCURRENTLY product_variants_with_details;
  REFRESH MATERIALIZED VIEW CONCURRENTLY orders_view;
END;
$$;

-- 1) Replace existing function
DROP FUNCTION IF EXISTS public.get_dashboard_metrics(uuid, integer);

CREATE OR REPLACE FUNCTION public.get_dashboard_metrics(
  p_company_id uuid,
  p_days int DEFAULT 30
)
RETURNS TABLE (
  total_orders bigint,
  total_revenue bigint,
  total_customers bigint,
  inventory_count bigint,
  sales_series jsonb,
  top_products jsonb,
  inventory_summary jsonb,
  revenue_change double precision,
  orders_change double precision,
  customers_change double precision,
  dead_stock_value bigint
)
LANGUAGE sql
STABLE
AS $$
WITH time_window AS (
  SELECT
    now() - make_interval(days => p_days)            AS start_at,
    now() - make_interval(days => p_days * 2)        AS prev_start_at,
    now() - make_interval(days => p_days)            AS prev_end_at
),
filtered_orders AS (
  SELECT o.*
  FROM public.orders o
  JOIN time_window w ON true
  WHERE o.company_id = p_company_id
    AND o.created_at >= w.start_at
    AND o.cancelled_at IS NULL
),
prev_filtered_orders AS (
  SELECT o.*
  FROM public.orders o
  JOIN time_window w ON true
  WHERE o.company_id = p_company_id
    AND o.created_at >= w.prev_start_at
    AND o.created_at < w.prev_end_at
    AND o.cancelled_at IS NULL
),
day_series AS (
  SELECT date_trunc('day', o.created_at) AS day,
         SUM(o.total_amount)::bigint     AS revenue,
         COUNT(*)::int                   AS orders
  FROM filtered_orders o
  GROUP BY 1
  ORDER BY 1
),
top_products_cte AS (
  SELECT
    p.id                                    AS product_id,
    p.title                                 AS product_name,
    p.image_url,
    SUM(li.quantity)::int                   AS quantity_sold,
    SUM((li.price::bigint) * (li.quantity::bigint))::bigint AS total_revenue
  FROM public.order_line_items li
  JOIN public.orders o   ON o.id = li.order_id
  LEFT JOIN public.products p ON p.id = li.product_id
  WHERE o.company_id = p_company_id
    AND o.cancelled_at IS NULL
    AND o.created_at >= (SELECT start_at FROM time_window)
  GROUP BY 1,2,3
  ORDER BY total_revenue DESC
  LIMIT 5
),
inventory_values AS (
  SELECT
    SUM((v.inventory_quantity::bigint) * (v.cost::bigint))::bigint AS total_value,
    SUM(CASE WHEN v.reorder_point IS NULL OR v.inventory_quantity > v.reorder_point
             THEN (v.inventory_quantity::bigint) * (v.cost::bigint) ELSE 0 END)::bigint AS in_stock_value,
    SUM(CASE WHEN v.reorder_point IS NOT NULL
               AND v.inventory_quantity <= v.reorder_point
               AND v.inventory_quantity > 0
             THEN (v.inventory_quantity::bigint) * (v.cost::bigint) ELSE 0 END)::bigint AS low_stock_value
  FROM public.product_variants v
  WHERE v.company_id = p_company_id
    AND v.cost IS NOT NULL
    AND v.deleted_at IS NULL
),
variant_last_sale AS (
  SELECT li.variant_id, MAX(o.created_at) AS last_sale_at
  FROM public.order_line_items li
  JOIN public.orders o ON o.id = li.order_id
  WHERE o.company_id = p_company_id
    AND o.cancelled_at IS NULL
  GROUP BY li.variant_id
),
dead_stock AS (
  SELECT
    SUM((v.inventory_quantity::bigint) * (v.cost::bigint))::bigint AS value
  FROM public.product_variants v
  LEFT JOIN variant_last_sale ls ON ls.variant_id = v.id
  LEFT JOIN public.company_settings cs ON cs.company_id = v.company_id
  WHERE v.company_id = p_company_id
    AND v.cost IS NOT NULL
    AND v.deleted_at IS NULL
    AND v.inventory_quantity > 0
    AND (
      ls.last_sale_at IS NULL
      OR ls.last_sale_at < (now() - make_interval(days => COALESCE(cs.dead_stock_days, 90)))
    )
),
current_period AS (
  SELECT
    COALESCE(COUNT(*), 0)::bigint                      AS orders,
    COALESCE(SUM(total_amount), 0)::bigint             AS revenue,
    COALESCE(COUNT(DISTINCT customer_id), 0)::bigint   AS customers
  FROM filtered_orders
),
previous_period AS (
  SELECT
    COALESCE(COUNT(*), 0)::bigint                      AS orders,
    COALESCE(SUM(total_amount), 0)::bigint             AS revenue,
    COALESCE(COUNT(DISTINCT customer_id), 0)::bigint   AS customers
  FROM prev_filtered_orders
)
SELECT
  (SELECT orders    FROM current_period) AS total_orders,
  (SELECT revenue   FROM current_period) AS total_revenue,
  (SELECT customers FROM current_period) AS total_customers,

  COALESCE((
    SELECT SUM(pv.inventory_quantity)
    FROM public.product_variants pv
    WHERE pv.company_id = p_company_id AND pv.deleted_at IS NULL
  ), 0)::bigint AS inventory_count,

  COALESCE((
    SELECT jsonb_agg(
      jsonb_build_object('date', to_char(day, 'YYYY-MM-DD'), 'revenue', revenue, 'orders', orders)
      ORDER BY day
    )
    FROM day_series
  ), '[]'::jsonb) AS sales_series,

  COALESCE((SELECT jsonb_agg(to_jsonb(tp)) FROM top_products_cte tp), '[]'::jsonb) AS top_products,

  jsonb_build_object(
    'total_value',     COALESCE((SELECT total_value     FROM inventory_values), 0),
    'in_stock_value',  COALESCE((SELECT in_stock_value  FROM inventory_values), 0),
    'low_stock_value', COALESCE((SELECT low_stock_value FROM inventory_values), 0),
    'dead_stock_value',COALESCE((SELECT value           FROM dead_stock), 0)
  ) AS inventory_summary,

  CASE WHEN (SELECT revenue FROM previous_period) = 0
       THEN 0.0
       ELSE (((SELECT revenue FROM current_period)::float
             - (SELECT revenue FROM previous_period)::float)
             / (SELECT revenue FROM previous_period)::float) * 100
  END AS revenue_change,
  CASE WHEN (SELECT orders FROM previous_period) = 0
       THEN 0.0
       ELSE (((SELECT orders FROM current_period)::float
             - (SELECT orders FROM previous_period)::float)
             / (SELECT orders FROM previous_period)::float) * 100
  END AS orders_change,
  CASE WHEN (SELECT customers FROM previous_period) = 0
       THEN 0.0
       ELSE (((SELECT customers FROM current_period)::float
             - (SELECT customers FROM previous_period)::float)
             / (SELECT customers FROM previous_period)::float) * 100
  END AS customers_change,

  COALESCE((SELECT value FROM dead_stock), 0)::bigint AS dead_stock_value;
$$;

-- 2) Helpful indexes (idempotent)
CREATE INDEX IF NOT EXISTS idx_orders_company_created
  ON public.orders(company_id, created_at);

CREATE INDEX IF NOT EXISTS idx_orders_company_not_cancelled
  ON public.orders(company_id) WHERE cancelled_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_olis_order
  ON public.order_line_items(order_id);

CREATE INDEX IF NOT EXISTS idx_olis_company_variant
  ON public.order_line_items(company_id, variant_id);

CREATE INDEX IF NOT EXISTS idx_products_company
  ON public.products(company_id);

CREATE INDEX IF NOT EXISTS idx_variants_company
  ON public.product_variants(company_id);

CREATE INDEX IF NOT EXISTS idx_customers_company
  ON public.customers(company_id);
  
CREATE INDEX IF NOT EXISTS idx_variants_company_not_deleted
  ON public.product_variants(company_id)
  WHERE deleted_at IS NULL;
