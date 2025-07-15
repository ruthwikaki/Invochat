
-- InvoChat Schema Migration & Setup Script
-- This script is designed to be idempotent and can be run multiple times safely.

-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Drop dependent views and functions first to allow table alterations.
DROP MATERIALIZED VIEW IF EXISTS public.company_dashboard_metrics;
DROP VIEW IF EXISTS public.product_variants_with_details;
DROP VIEW IF EXISTS public.sales_by_day;

-- Drop existing policies and the insecure function to break dependencies.
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN 
        SELECT 'ALTER TABLE ' || quote_ident(schemaname) || '.' || quote_ident(tablename) || ' DROP POLICY IF EXISTS "' || policyname || '";' AS drop_cmd
        FROM pg_policies
        WHERE schemaname = 'public'
    LOOP
        EXECUTE rec.drop_cmd;
    END LOOP;
END
$$;
DROP FUNCTION IF EXISTS get_my_company_id();
DROP FUNCTION IF EXISTS public.get_user_company_id(p_user_id uuid);

-- 1. Table Structure Modifications
-- ===============================
-- Add company_id and other missing columns to tables that need them.
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS company_id UUID;
ALTER TABLE public.product_variants ADD COLUMN IF NOT EXISTS company_id UUID;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS company_id UUID;
ALTER TABLE public.order_line_items ADD COLUMN IF NOT EXISTS company_id UUID;
ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS company_id UUID;
ALTER TABLE public.suppliers ADD COLUMN IF NOT EXISTS company_id UUID;
ALTER TABLE public.purchase_orders ADD COLUMN IF NOT EXISTS company_id UUID;
ALTER TABLE public.purchase_order_line_items ADD COLUMN IF NOT EXISTS company_id UUID;
ALTER TABLE public.purchase_order_line_items ADD COLUMN IF NOT EXISTS idempotency_key TEXT;
ALTER TABLE public.integrations ADD COLUMN IF NOT EXISTS company_id UUID;
ALTER TABLE public.conversations ADD COLUMN IF NOT EXISTS company_id UUID;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS company_id UUID;
ALTER TABLE public.audit_log ADD COLUMN IF NOT EXISTS company_id UUID;
ALTER TABLE public.audit_log ADD COLUMN IF NOT EXISTS user_id UUID;
ALTER TABLE public.purchase_orders ADD COLUMN IF NOT EXISTS idempotency_key TEXT;


-- Standardize all monetary columns to be INTEGERS (storing cents)
ALTER TABLE public.product_variants ALTER COLUMN price TYPE INTEGER;
ALTER TABLE public.product_variants ALTER COLUMN compare_at_price TYPE INTEGER;
ALTER TABLE public.product_variants ALTER COLUMN cost TYPE INTEGER;
ALTER TABLE public.order_line_items ALTER COLUMN price TYPE INTEGER;
ALTER TABLE public.order_line_items ALTER COLUMN total_discount TYPE INTEGER;
ALTER TABLE public.order_line_items ALTER COLUMN tax_amount TYPE INTEGER;
ALTER TABLE public.order_line_items ALTER COLUMN cost_at_time TYPE INTEGER;
ALTER TABLE public.orders ALTER COLUMN subtotal TYPE INTEGER;
ALTER TABLE public.orders ALTER COLUMN total_tax TYPE INTEGER;
ALTER TABLE public.orders ALTER COLUMN total_shipping TYPE INTEGER;
ALTER TABLE public.orders ALTER COLUMN total_discounts TYPE INTEGER;
ALTER TABLE public.orders ALTER COLUMN total_amount TYPE INTEGER;
ALTER TABLE public.purchase_orders ALTER COLUMN total_cost TYPE INTEGER;
ALTER TABLE public.purchase_order_line_items ALTER COLUMN cost TYPE INTEGER;
ALTER TABLE public.customers ALTER COLUMN total_spent TYPE INTEGER;

-- Make columns non-nullable where required for data integrity
ALTER TABLE public.product_variants ALTER COLUMN sku SET NOT NULL;

-- Drop obsolete columns
ALTER TABLE public.product_variants DROP COLUMN IF EXISTS weight;
ALTER TABLE public.product_variants DROP COLUMN IF EXISTS weight_unit;


-- 2. New Helper Functions
-- ===============================

-- Securely get the company_id for the currently authenticated user
CREATE OR REPLACE FUNCTION public.get_my_company_id()
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
    company_uuid uuid;
BEGIN
    SELECT u.company_id INTO company_uuid
    FROM public.users u
    WHERE u.id = auth.uid();
    RETURN company_uuid;
END;
$$;


-- 3. Views and Materialized Views
-- ===============================
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT 
    pv.*,
    p.title AS product_title,
    p.status AS product_status,
    p.image_url
FROM 
    public.product_variants pv
JOIN 
    public.products p ON pv.product_id = p.id;

CREATE OR REPLACE VIEW public.sales_by_day AS
SELECT
    company_id,
    date_trunc('day', created_at) AS sale_date,
    SUM(total_amount) AS daily_revenue,
    COUNT(id) AS daily_orders
FROM
    public.orders
GROUP BY
    company_id,
    date_trunc('day', created_at);

CREATE MATERIALIZED VIEW IF NOT EXISTS public.company_dashboard_metrics AS
SELECT 
    c.id as company_id,
    p.product_type,
    pv.cost,
    o.created_at::date as order_date
FROM companies c
JOIN products p ON c.id = p.company_id
JOIN product_variants pv ON p.id = pv.product_id
JOIN order_line_items oli ON pv.id = oli.variant_id
JOIN orders o ON oli.order_id = o.id
WHERE o.status = 'completed';


-- 4. Create Indexes for Performance
-- ===================================
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_variants_sku_company ON public.product_variants(sku, company_id);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_customers_email_company ON public.customers(email, company_id);
CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON public.suppliers(company_id);
CREATE INDEX IF NOT EXISTS idx_po_company_id ON public.purchase_orders(company_id);
CREATE INDEX IF NOT EXISTS idx_po_items_po_id ON public.purchase_order_line_items(purchase_order_id);
CREATE INDEX IF NOT EXISTS idx_ledger_variant_id ON public.inventory_ledger(variant_id);
CREATE UNIQUE INDEX IF NOT EXISTS po_company_idempotency_idx ON public.purchase_orders (company_id, idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS webhook_events_unique_idx ON public.webhook_events (integration_id, webhook_id);


-- 5. Row-Level Security (RLS) Setup
-- ===============================
-- This is the most critical part for security.

-- Helper function to check if a user belongs to a company.
CREATE OR REPLACE FUNCTION is_member_of(p_company_id uuid)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = auth.uid() AND u.company_id = p_company_id
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Define a reusable policy template function
CREATE OR REPLACE FUNCTION create_company_rls_policy(table_name text)
RETURNS void AS $$
BEGIN
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', table_name);
    EXECUTE format('DROP POLICY IF EXISTS "Allow company members full access" ON public.%I;', table_name);
    EXECUTE format(
        'CREATE POLICY "Allow company members full access" ON public.%I ' ||
        'FOR ALL USING (company_id = public.get_my_company_id());',
        table_name
    );
END;
$$ LANGUAGE plpgsql;

-- Apply the RLS policy to all company-specific tables
SELECT create_company_rls_policy('products');
SELECT create_company_rls_policy('product_variants');
SELECT create_company_rls_policy('orders');
SELECT create_company_rls_policy('order_line_items');
SELECT create_company_rls_policy('customers');
SELECT create_company_rls_policy('refunds');
SELECT create_company_rls_policy('refund_line_items');
SELECT create_company_rls_policy('suppliers');
SELECT create_company_rls_policy('purchase_orders');
SELECT create_company_rls_policy('purchase_order_line_items');
SELECT create_company_rls_policy('inventory_ledger');
SELECT create_company_rls_policy('integrations');
SELECT create_company_rls_policy('company_settings');
SELECT create_company_rls_policy('conversations');
SELECT create_company_rls_policy('messages');
SELECT create_company_rls_policy('audit_log');
SELECT create_company_rls_policy('channel_fees');
SELECT create_company_rls_policy('discounts');
SELECT create_company_rls_policy('export_jobs');
SELECT create_company_rls_policy('webhook_events');


-- Specific policy for the users table itself
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow users to see other members of their own company" ON public.users;
CREATE POLICY "Allow users to see other members of their own company"
    ON public.users FOR SELECT
    USING (company_id = public.get_my_company_id());
DROP POLICY IF EXISTS "Allow users to update their own record" ON public.users;
CREATE POLICY "Allow users to update their own record"
    ON public.users FOR UPDATE
    USING (id = auth.uid());
    
-- Final sanity check refresh
REFRESH MATERIALIZED VIEW public.company_dashboard_metrics;

