-- This script is designed to be run once to set up or migrate the database schema.
-- It is idempotent, meaning it can be run multiple times without causing errors.

-- =============================================
-- SECTION 1: PRE-FLIGHT CHECKS & EXTENSIONS
-- =============================================
DO $$
BEGIN
    -- This ensures the script is run by a user with appropriate permissions.
    IF NOT (SELECT rolsuper FROM pg_roles WHERE rolname = current_user) THEN
        RAISE EXCEPTION 'This script must be run by a superuser. Please run this from the Supabase SQL Editor in the dashboard.';
    END IF;
END
$$;

-- Enable UUID generation function if not already enabled.
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =============================================
-- SECTION 2: FUNCTION DEPENDENCY MANAGEMENT
-- =============================================
-- Drop dependent views and policies before modifying the function they use.
DROP VIEW IF EXISTS public.product_variants_with_details;
DROP VIEW IF EXISTS public.orders_view;

DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public') LOOP
        EXECUTE 'ALTER TABLE public.' || quote_ident(r.tablename) || ' DISABLE ROW LEVEL SECURITY';
        EXECUTE 'DROP POLICY IF EXISTS "Allow all access to own company data" ON public.' || quote_ident(r.tablename);
    END LOOP;
END $$;


-- Drop the function using CASCADE to remove all dependent policies automatically.
-- This is the most reliable way to handle the dependencies.
DROP FUNCTION IF EXISTS public.get_company_id() CASCADE;

-- =============================================
-- SECTION 3: CORE FUNCTIONS
-- =============================================

-- get_company_id(): A security function to get the company ID from a user's JWT.
CREATE OR REPLACE FUNCTION public.get_company_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT
    NULLIF(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid;
$$;
COMMENT ON FUNCTION public.get_company_id() IS 'Get the company_id from the JWT of the currently authenticated user.';

-- handle_new_user(): A trigger function to automatically set up a new company and user profile upon signup.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  company_id uuid;
  user_id uuid := new.id;
  user_email text := new.email;
  company_name text := new.raw_app_meta_data->>'company_name';
BEGIN
  -- Create a new company for the user
  INSERT INTO public.companies (name)
  VALUES (company_name)
  RETURNING id INTO company_id;

  -- Create a user profile linked to the new company
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (user_id, company_id, user_email, 'Owner');

  -- Update the user's app_metadata with the new company_id and role
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id, 'role', 'Owner')
  WHERE id = user_id;

  RETURN new;
END;
$$;
COMMENT ON FUNCTION public.handle_new_user() IS 'Triggered on new user signup. Creates a company and user profile.';

-- on_auth_user_created trigger: Hooks into Supabase Auth to run handle_new_user.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- =============================================
-- SECTION 4: TABLE CONSTRAINTS & INDEXES
-- =============================================

-- Add foreign key constraints to ensure data integrity.
-- The DROP...ADD pattern makes the script re-runnable.
ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_company_id_fkey;
ALTER TABLE public.users ADD CONSTRAINT users_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;

ALTER TABLE public.product_variants DROP CONSTRAINT IF EXISTS product_variants_company_id_fkey;
ALTER TABLE public.product_variants ADD CONSTRAINT product_variants_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.product_variants DROP CONSTRAINT IF EXISTS product_variants_product_id_fkey;
ALTER TABLE public.product_variants ADD CONSTRAINT product_variants_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;

ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_customer_id_fkey;
ALTER TABLE public.orders ADD CONSTRAINT orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE SET NULL;

ALTER TABLE public.order_line_items DROP CONSTRAINT IF EXISTS order_line_items_order_id_fkey;
ALTER TABLE public.order_line_items ADD CONSTRAINT order_line_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;
ALTER TABLE public.order_line_items DROP CONSTRAINT IF EXISTS order_line_items_variant_id_fkey;
ALTER TABLE public.order_line_items ADD CONSTRAINT order_line_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE SET NULL;

-- Indexes for performance on frequently queried columns.
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_company_id ON public.product_variants(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_sku ON public.product_variants(sku);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers(company_id);
CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON public.suppliers(company_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id ON public.inventory_ledger(variant_id);

-- =============================================
-- SECTION 5: ROW-LEVEL SECURITY (RLS)
-- =============================================

-- A helper function to dynamically apply RLS policies to all tables.
CREATE OR REPLACE FUNCTION public.enable_rls_for_all_tables(schema_name text DEFAULT 'public')
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = schema_name) LOOP
        EXECUTE 'ALTER TABLE ' || quote_ident(schema_name) || '.' || quote_ident(r.tablename) || ' ENABLE ROW LEVEL SECURITY';
        EXECUTE 'ALTER TABLE ' || quote_ident(schema_name) || '.' || quote_ident(r.tablename) || ' FORCE ROW LEVEL SECURITY';

        -- Drop policy if it exists, to ensure this script is re-runnable
        EXECUTE 'DROP POLICY IF EXISTS "Allow all access to own company data" ON ' || quote_ident(schema_name) || '.' || quote_ident(r.tablename);

        -- Special handling for tables without a direct company_id
        IF r.tablename = 'companies' THEN
            EXECUTE 'CREATE POLICY "Allow all access to own company data" ON public.companies FOR ALL USING (id = public.get_company_id());';
        ELSIF r.tablename = 'customer_addresses' THEN
             EXECUTE 'CREATE POLICY "Allow all access to own company data" ON public.customer_addresses FOR ALL USING (customer_id IN (SELECT id FROM customers WHERE company_id = public.get_company_id()));';
        ELSIF r.tablename = 'webhook_events' THEN
             EXECUTE 'CREATE POLICY "Allow all access to own company data" ON public.webhook_events FOR ALL USING (integration_id IN (SELECT id FROM integrations WHERE company_id = public.get_company_id()));';
        ELSIF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = schema_name AND table_name = r.tablename AND column_name = 'company_id') THEN
            EXECUTE 'CREATE POLICY "Allow all access to own company data" ON ' || quote_ident(schema_name) || '.' || quote_ident(r.tablename) ||
                    ' FOR ALL USING (company_id = public.get_company_id());';
        END IF;
    END LOOP;
END;
$$;
COMMENT ON FUNCTION public.enable_rls_for_all_tables(text) IS 'A helper function to enable RLS and apply a standard company_id policy to all tables in a schema.';

-- Execute the function to apply RLS to the public schema.
SELECT public.enable_rls_for_all_tables('public');

-- =============================================
-- SECTION 6: RECREATE VIEWS
-- =============================================

-- product_variants_with_details: A convenience view for joining product and variant data.
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
COMMENT ON VIEW public.product_variants_with_details IS 'Combines product and variant data for easy querying.';


-- orders_view: A convenience view for joining order and customer data.
CREATE OR REPLACE VIEW public.orders_view AS
SELECT
    o.*,
    c.customer_name,
    c.email AS customer_email
FROM
    public.orders o
LEFT JOIN
    public.customers c ON o.customer_id = c.id;
COMMENT ON VIEW public.orders_view IS 'Combines order and customer data for easy querying.';


-- customers_view: A convenience view to show only non-deleted customers.
CREATE OR REPLACE VIEW public.customers_view AS
SELECT *
FROM public.customers
WHERE deleted_at IS NULL;
COMMENT ON VIEW public.customers_view IS 'Filters out soft-deleted customers from the customers table.';

-- =============================================
-- SECTION 7: MATERIALIZED VIEWS FOR PERFORMANCE
-- =============================================

-- daily_sales_by_company: Pre-aggregates sales data by day for fast dashboard loading.
CREATE MATERIALIZED VIEW IF NOT EXISTS public.daily_sales_by_company AS
SELECT
    company_id,
    date_trunc('day', created_at) AS sale_date,
    SUM(total_amount) AS total_revenue,
    COUNT(id) AS total_orders
FROM
    public.orders
GROUP BY
    company_id,
    sale_date
WITH DATA;
CREATE INDEX IF NOT EXISTS idx_daily_sales_company_date ON public.daily_sales_by_company(company_id, sale_date);
COMMENT ON MATERIALIZED VIEW public.daily_sales_by_company IS 'Pre-aggregates total revenue and order count by day and company for performance.';

-- sales_analytics_by_product: Pre-calculates key metrics for each product variant.
CREATE MATERIALIZED VIEW IF NOT EXISTS public.sales_analytics_by_product AS
SELECT
    oli.company_id,
    oli.variant_id,
    pv.sku,
    p.title AS product_name,
    p.image_url,
    SUM(oli.quantity) AS total_quantity_sold,
    SUM(oli.price * oli.quantity) AS total_revenue,
    SUM((oli.price - COALESCE(oli.cost_at_time, pv.cost, 0)) * oli.quantity) AS total_profit,
    AVG(oli.price - COALESCE(oli.cost_at_time, pv.cost, 0)) AS average_margin_per_unit,
    (COUNT(DISTINCT o.id)::decimal / NULLIF(COUNT(DISTINCT c.id), 0)) as avg_orders_per_customer
FROM
    public.order_line_items oli
JOIN
    public.orders o ON oli.order_id = o.id
JOIN
    public.product_variants pv ON oli.variant_id = pv.id
JOIN
    public.products p ON pv.product_id = p.id
LEFT JOIN
    public.customers c ON o.customer_id = c.id
GROUP BY
    oli.company_id,
    oli.variant_id,
    pv.sku,
    p.title,
    p.image_url
WITH DATA;
CREATE INDEX IF NOT EXISTS idx_sales_analytics_product_company_variant ON public.sales_analytics_by_product(company_id, variant_id);
COMMENT ON MATERIALIZED VIEW public.sales_analytics_by_product IS 'Pre-calculates sales metrics per product variant for high-performance analytics.';


-- refresh_materialized_views(): A function to refresh all materialized views.
CREATE OR REPLACE FUNCTION public.refresh_materialized_views()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.daily_sales_by_company;
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.sales_analytics_by_product;
    RAISE LOG 'Materialized views refreshed successfully.';
END;
$$;
COMMENT ON FUNCTION public.refresh_materialized_views() IS 'Refreshes all materialized views in the database.';

-- =============================================
-- FINALIZATION
-- =============================================
DO $$
BEGIN
    RAISE INFO 'Database migration script completed successfully.';
END
$$;
