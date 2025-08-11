-- src/lib/migrations/002_add_sales_view.sql
CREATE OR REPLACE VIEW public.sales AS
SELECT
  o.id                          AS order_id,
  o.company_id,
  o.order_number,
  o.created_at,
  o.total_amount,
  o.financial_status as status,
  oi.variant_id,
  oi.quantity,
  oi.price AS unit_price,
  (oi.quantity * oi.price) AS line_total
FROM public.orders o
JOIN public.order_line_items oi ON oi.order_id = o.id;
