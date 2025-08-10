-- This script creates the necessary function and indexes for the dashboard.

-- Metrics for last N days (default 30)
create or replace function public.get_dashboard_metrics(
  p_company_id uuid,
  p_days int default 30
)
returns table (
  total_orders bigint,
  total_revenue bigint,
  total_customers bigint,
  inventory_count bigint,
  sales_series jsonb,
  top_products jsonb,
  inventory_summary jsonb,
  revenue_change float,
  orders_change float,
  customers_change float,
  dead_stock_value bigint
)
language sql
stable
as $$
with window as (
  select now() - make_interval(days => p_days) as start_at,
         now() - make_interval(days => p_days * 2) as prev_start_at,
         now() - make_interval(days => p_days) as prev_end_at
),
filtered_orders as (
  select o.*
  from orders o, window w
  where o.company_id = p_company_id
    and o.created_at >= w.start_at
    and (o.cancelled_at is null)
),
prev_filtered_orders as (
  select o.*
  from orders o, window w
  where o.company_id = p_company_id
    and o.created_at between w.prev_start_at and w.prev_end_at
    and (o.cancelled_at is null)
),
day_series as (
  select date_trunc('day', o.created_at) as day,
         sum(o.total_amount)::bigint as revenue,
         count(*)::int as orders
  from filtered_orders o
  group by 1
  order by 1
),
top_products as (
  select
    p.id as product_id,
    p.title as product_name,
    p.image_url,
    sum(li.quantity)::int as quantity_sold,
    sum(li.price * li.quantity)::bigint as total_revenue
  from order_line_items li
  join orders o on o.id = li.order_id
  left join products p on p.id = li.product_id
  where o.company_id = p_company_id
    and (o.cancelled_at is null)
    and o.created_at >= (select start_at from window)
  group by 1, 2, 3
  order by total_revenue desc
  limit 5
),
inventory_values as (
    select
        sum(v.inventory_quantity * v.cost) as total_value,
        sum(case when v.inventory_quantity > v.reorder_point then v.inventory_quantity * v.cost else 0 end) as in_stock_value,
        sum(case when v.inventory_quantity <= v.reorder_point and v.inventory_quantity > 0 then v.inventory_quantity * v.cost else 0 end) as low_stock_value
    from product_variants v
    where v.company_id = p_company_id and v.cost is not null
),
dead_stock as (
    select sum(total_value) as value
    from get_dead_stock_report(p_company_id)
),
current_period as (
    select
        coalesce(count(*), 0)::bigint as orders,
        coalesce(sum(total_amount), 0)::bigint as revenue,
        coalesce(count(distinct customer_id), 0)::bigint as customers
    from filtered_orders
),
previous_period as (
    select
        coalesce(count(*), 0)::bigint as orders,
        coalesce(sum(total_amount), 0)::bigint as revenue,
        coalesce(count(distinct customer_id), 0)::bigint as customers
    from prev_filtered_orders
)
select
  /* totals in period */
  (select orders from current_period) as total_orders,
  (select revenue from current_period) as total_revenue,
  (select customers from current_period) as total_customers,

  /* inventory is global, not range-limited */
  coalesce((
    select sum(pv.inventory_quantity)
    from product_variants pv
    where pv.company_id = p_company_id
  ), 0)::bigint as inventory_count,

  /* series + top products as JSON for the UI */
  coalesce((select jsonb_agg(jsonb_build_object('date', to_char(day, 'YYYY-MM-DD'), 'revenue', revenue) order by day) from day_series), '[]'::jsonb) as sales_series,
  coalesce((select jsonb_agg(top_products) from top_products), '[]'::jsonb) as top_products,

  /* inventory summary */
  jsonb_build_object(
      'total_value', coalesce((select total_value from inventory_values), 0),
      'in_stock_value', coalesce((select in_stock_value from inventory_values), 0),
      'low_stock_value', coalesce((select low_stock_value from inventory_values), 0),
      'dead_stock_value', coalesce((select value from dead_stock), 0)
  ) as inventory_summary,

  /* percentage changes */
  (case when (select revenue from previous_period) = 0 then 0.0 else
      (((select revenue from current_period)::float - (select revenue from previous_period)::float) / (select revenue from previous_period)::float) * 100
  end) as revenue_change,
  (case when (select orders from previous_period) = 0 then 0.0 else
      (((select orders from current_period)::float - (select orders from previous_period)::float) / (select orders from previous_period)::float) * 100
  end) as orders_change,
  (case when (select customers from previous_period) = 0 then 0.0 else
      (((select customers from current_period)::float - (select customers from previous_period)::float) / (select customers from previous_period)::float) * 100
  end) as customers_change,
  coalesce((select value from dead_stock), 0)::bigint as dead_stock_value
$$;


-- Helpful indexes for faster metrics and list pages
create index if not exists idx_orders_company_created
  on orders(company_id, created_at);

create index if not exists idx_orders_company_cancelled
  on orders(company_id) where cancelled_at is null;

create index if not exists idx_olis_order
  on order_line_items(order_id);

create index if not exists idx_olis_company_variant
  on order_line_items(company_id, variant_id);

create index if not exists idx_products_company
  on products(company_id);

create index if not exists idx_variants_company
  on product_variants(company_id);

create index if not exists idx_customers_company
  on customers(company_id);
