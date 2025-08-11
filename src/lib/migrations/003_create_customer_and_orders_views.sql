-- Migration to create essential views for customers and orders

BEGIN;

-- Drop views if they exist to ensure a clean creation
DROP VIEW IF EXISTS public.customers_view;
DROP VIEW IF EXISTS public.orders_view;

-- Create a view for customers with aggregated sales data
CREATE OR REPLACE VIEW public.customers_view AS
SELECT
    c.id,
    c.company_id,
    c.name,
    c.email,
    c.phone,
    c.created_at,
    c.deleted_at,
    c.external_customer_id,
    COUNT(o.id) AS total_orders,
    COALESCE(SUM(o.total_amount), 0) AS total_spent,
    MIN(o.created_at) AS first_order_date
FROM
    public.customers c
LEFT JOIN
    public.orders o ON c.id = o.customer_id AND c.company_id = o.company_id
GROUP BY
    c.id, c.company_id;

-- Create a simplified view for orders that includes customer email for searching
CREATE OR REPLACE VIEW public.orders_view AS
SELECT
    o.*,
    c.email AS customer_email
FROM
    public.orders o
LEFT JOIN
    public.customers c ON o.customer_id = c.id;

COMMIT;
