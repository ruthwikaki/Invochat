-- This view is required for sales analytics to function correctly.
-- It normalizes order data into a simpler format for reporting.

DROP VIEW IF EXISTS public.sales;

CREATE OR REPLACE VIEW public.sales AS
SELECT
  o.id                          AS order_id,
  o.company_id,
  o.order_number,
  o.created_at,
  o.financial_status            AS status,
  oli.variant_id,
  oli.quantity,
  oli.price                     AS unit_price,
  (oli.quantity * oli.price)    AS line_total
FROM 
  public.orders o
JOIN 
  public.order_line_items oli ON oli.order_id = o.id;
