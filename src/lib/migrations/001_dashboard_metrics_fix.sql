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
    p.id                                  AS product_id,
    p.title                               AS product_name,
    p.image_url,
    SUM(li.quantity)::int                 AS quantity_sold,
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
