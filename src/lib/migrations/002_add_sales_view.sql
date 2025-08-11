-- src/lib/migrations/002_add_sales_view.sql
CREATE OR REPLACE VIEW public.sales AS
SELECT
  o.id AS order_id,
  o.company_id,
  o.order_number,
  o.created_at,
  o.financial_status AS status,
  oli.variant_id,
  p.id AS product_id,
  oli.quantity,
  oli.price AS unit_price,
  (oli.quantity * oli.price) AS line_total
FROM 
  public.orders o
JOIN 
  public.order_line_items oli ON oli.order_id = o.id
JOIN
  public.product_variants pv ON pv.id = oli.variant_id
JOIN
  public.products p ON p.id = pv.product_id;
