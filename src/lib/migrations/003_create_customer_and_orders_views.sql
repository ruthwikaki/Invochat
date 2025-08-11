-- This script creates the views needed for the customers and orders pages.
-- It is designed to be idempotent and can be re-run safely.

BEGIN;

-- First, drop the existing views if they exist to avoid column name conflicts.
DROP VIEW IF EXISTS public.customers_view;
DROP VIEW IF EXISTS public.orders_view;
DROP VIEW IF EXISTS public.purchase_orders_view;

-- Create the customers_view
-- This view aggregates order data for each customer.
CREATE OR REPLACE VIEW public.customers_view AS
SELECT
    c.id,
    c.company_id,
    c.customer_name,
    c.email,
    COALESCE(o.total_orders, 0) as total_orders,
    COALESCE(o.total_spent, 0) as total_spent,
    o.first_order_date,
    c.created_at,
    c.deleted_at
FROM
    public.customers c
LEFT JOIN (
    SELECT
        customer_id,
        COUNT(id) AS total_orders,
        SUM(total_amount) AS total_spent,
        MIN(created_at) AS first_order_date
    FROM
        public.orders
    GROUP BY
        customer_id
) o ON c.id = o.customer_id;

-- Create the orders_view
-- This view joins orders with customer emails for easier searching.
CREATE OR REPLACE VIEW public.orders_view AS
SELECT
    o.*,
    c.email as customer_email
FROM
    public.orders o
LEFT JOIN
    public.customers c ON o.customer_id = c.id;

-- Create the purchase_orders_view
-- This view joins purchase orders with supplier names.
CREATE OR REPLACE VIEW public.purchase_orders_view AS
SELECT
    po.*,
    s.name as supplier_name
FROM
    public.purchase_orders po
LEFT JOIN
    public.suppliers s ON po.supplier_id = s.id;


COMMIT;
