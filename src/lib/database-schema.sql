
-- ### UNIVERSAL SETUP ###
-- This section should be run for all new projects.

-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Enable the "pg_cron" extension for scheduling tasks
CREATE EXTENSION IF NOT EXISTS "pg_cron";

-- Enable the "pgsodium" extension for encryption
CREATE EXTENSION IF NOT EXISTS "pgsodium";

-- Enable the Vault for storing secrets
CREATE EXTENSION IF NOT EXISTS "supabase_vault";

-- ### CUSTOM TYPES ###
-- Custom data types used throughout the schema.

DO $$ BEGIN
    CREATE TYPE public.user_role AS ENUM ('Owner', 'Admin', 'Member');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE public.integration_platform AS ENUM ('shopify', 'woocommerce', 'amazon_fba');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE public.sync_status AS ENUM ('idle', 'syncing', 'success', 'failed', 'syncing_products', 'syncing_sales');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;


-- ### DROP DEPENDENT OBJECTS ###
-- Drop views and policies that depend on tables/columns being changed.

DROP MATERIALIZED VIEW IF EXISTS public.company_dashboard_metrics;
DROP VIEW IF EXISTS public.product_variants_with_details;

-- Drop existing policies safely before altering tables
DO $$ BEGIN ALTER TABLE public.products DROP POLICY IF EXISTS "Allow company members to read"; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN ALTER TABLE public.product_variants DROP POLICY IF EXISTS "Allow company members to read"; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN ALTER TABLE public.orders DROP POLICY IF EXISTS "Allow company members to read"; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN ALTER TABLE public.order_line_items DROP POLICY IF EXISTS "Allow company members to read"; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN ALTER TABLE public.customers DROP POLICY IF EXISTS "Allow company members to manage"; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN ALTER TABLE public.refunds DROP POLICY IF EXISTS "Allow company members to read"; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN ALTER TABLE public.suppliers DROP POLICY IF EXISTS "Allow company members to manage"; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN ALTER TABLE public.purchase_orders DROP POLICY IF EXISTS "Allow company members to manage"; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN ALTER TABLE public.inventory_ledger DROP POLICY IF EXISTS "Allow company members to read"; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN ALTER TABLE public.integrations DROP POLICY IF EXISTS "Allow company members to manage"; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN ALTER TABLE public.company_settings DROP POLICY IF EXISTS "Allow company members to manage"; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN ALTER TABLE public.audit_log DROP POLICY IF EXISTS "Allow admins to read audit logs for their company"; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN ALTER TABLE public.messages DROP POLICY IF EXISTS "Allow user to manage messages in their conversations"; EXCEPTION WHEN undefined_object THEN END; $$;
DO $$ BEGIN ALTER TABLE public.conversations DROP POLICY IF EXISTS "Users can only access their own conversations"; EXCEPTION WHEN undefined_object THEN END; $$;

-- Drop the old insecure function
DROP FUNCTION IF EXISTS get_my_company_id();


-- ### TABLE CREATION & ALTERATION ###

CREATE TABLE IF NOT EXISTS public.companies (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.users (
    id uuid PRIMARY KEY REFERENCES auth.users(id),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    email text,
    role public.user_role NOT NULL DEFAULT 'Member',
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now()
);

-- Add idempotency key to purchase_orders
ALTER TABLE public.purchase_orders
ADD COLUMN IF NOT EXISTS idempotency_key uuid;

-- Change numeric columns to integer for consistency (storing money as cents)
ALTER TABLE public.customers ALTER COLUMN total_spent TYPE integer USING (total_spent * 100)::integer;
ALTER TABLE public.refunds ALTER COLUMN total_amount TYPE integer USING (total_amount * 100)::integer;
ALTER TABLE public.refund_line_items ALTER COLUMN amount TYPE integer USING (amount * 100)::integer;
ALTER TABLE public.discounts ALTER COLUMN value TYPE integer USING (value * 100)::integer;
ALTER TABLE public.discounts ALTER COLUMN minimum_purchase TYPE integer USING (minimum_purchase * 100)::integer;


-- Add missing NOT NULL constraints for data integrity
ALTER TABLE public.product_variants ALTER COLUMN sku SET NOT NULL;
ALTER TABLE public.product_variants ALTER COLUMN title SET NOT NULL;


-- Add full-text search column to products table
ALTER TABLE public.products
ADD COLUMN IF NOT EXISTS fts_document tsvector;


-- ### INDEX CREATION ###
-- Create indexes for performance, especially on foreign keys and frequently queried columns.

-- Drop indexes if they exist to prevent errors on re-run
DROP INDEX IF EXISTS po_company_idempotency_idx;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_company_id ON public.product_variants(company_id);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id ON public.inventory_ledger(variant_id);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_supplier_id ON public.purchase_orders(supplier_id);
CREATE INDEX IF NOT EXISTS idx_purchase_order_line_items_purchase_order_id ON public.purchase_order_line_items(purchase_order_id);
CREATE INDEX IF NOT EXISTS idx_products_fts_document ON public.products USING GIN (fts_document);
CREATE UNIQUE INDEX IF NOT EXISTS po_company_idempotency_idx ON public.purchase_orders (company_id, idempotency_key) WHERE idempotency_key IS NOT NULL;


-- ### FUNCTIONS & TRIGGERS ###

-- Function to get the user's company_id securely from the users table.
CREATE OR REPLACE FUNCTION get_user_company_id(p_user_id uuid)
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT company_id
  FROM public.users
  WHERE id = p_user_id;
$$;

-- Function to handle new user setup.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_company_id uuid;
  v_company_name text := new.raw_app_meta_data->>'company_name';
BEGIN
  -- Create a new company for the user
  INSERT INTO public.companies (name)
  VALUES (v_company_name)
  RETURNING id INTO v_company_id;

  -- Create a corresponding user entry in the public.users table
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (new.id, v_company_id, new.email, 'Owner');

  -- Update the user's app_metadata with the new company_id
  new.raw_app_meta_data := new.raw_app_meta_data || jsonb_build_object('company_id', v_company_id);
  
  RETURN new;
END;
$$;

-- Trigger to execute the handle_new_user function on new user signup.
CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();
  
-- Function to update the full-text search vector for products.
CREATE OR REPLACE FUNCTION update_product_fts_document()
RETURNS TRIGGER AS $$
BEGIN
    NEW.fts_document := to_tsvector('english', coalesce(NEW.title, '') || ' ' || coalesce(NEW.description, ''));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for full-text search on products.
CREATE OR REPLACE TRIGGER product_fts_update_trigger
BEFORE INSERT OR UPDATE ON public.products
FOR EACH ROW
EXECUTE FUNCTION update_product_fts_document();

-- ### VIEWS & MATERIALIZED VIEWS ###

-- Recreate the detailed product variants view
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT 
    pv.*,
    p.title as product_title,
    p.status as product_status,
    p.image_url
FROM 
    public.product_variants pv
JOIN 
    public.products p ON pv.product_id = p.id;
    
-- Recreate the dashboard metrics materialized view
CREATE MATERIALIZED VIEW IF NOT EXISTS public.company_dashboard_metrics AS
SELECT
    oli.company_id,
    p.title as product_name,
    p.image_url,
    date_trunc('day', o.created_at) as sale_date,
    sum(oli.price * oli.quantity) as daily_revenue,
    sum(oli.quantity) as daily_quantity,
    sum(oli.quantity * COALESCE(oli.cost_at_time, pv.cost, 0)) as daily_cogs,
    o.customer_id
FROM
    public.order_line_items oli
JOIN
    public.orders o ON oli.order_id = o.id
JOIN
    public.product_variants pv ON oli.variant_id = pv.id
JOIN
    public.products p ON pv.product_id = p.id
WHERE 
    o.status = 'completed'
GROUP BY
    oli.company_id,
    p.title,
    p.image_url,
    sale_date,
    o.customer_id;
    
CREATE UNIQUE INDEX IF NOT EXISTS idx_company_dashboard_metrics ON public.company_dashboard_metrics (company_id, product_name, sale_date);


-- ### ROW-LEVEL SECURITY (RLS) ###

-- Enable RLS for all relevant tables
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refunds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

-- Create secure RLS policies
CREATE POLICY "Allow company members to read" ON public.products FOR SELECT USING (company_id = get_user_company_id(auth.uid()));
CREATE POLICY "Allow company members to read" ON public.product_variants FOR SELECT USING (company_id = get_user_company_id(auth.uid()));
CREATE POLICY "Allow company members to read" ON public.orders FOR SELECT USING (company_id = get_user_company_id(auth.uid()));
CREATE POLICY "Allow company members to read" ON public.order_line_items FOR SELECT USING (company_id = get_user_company_id(auth.uid()));
CREATE POLICY "Allow company members to manage" ON public.customers FOR ALL USING (company_id = get_user_company_id(auth.uid()));
CREATE POLICY "Allow company members to read" ON public.refunds FOR SELECT USING (company_id = get_user_company_id(auth.uid()));
CREATE POLICY "Allow company members to manage" ON public.suppliers FOR ALL USING (company_id = get_user_company_id(auth.uid()));
CREATE POLICY "Allow company members to manage" ON public.purchase_orders FOR ALL USING (company_id = get_user_company_id(auth.uid()));
CREATE POLICY "Allow company members to read" ON public.inventory_ledger FOR SELECT USING (company_id = get_user_company_id(auth.uid()));
CREATE POLICY "Allow company members to manage" ON public.integrations FOR ALL USING (company_id = get_user_company_id(auth.uid()));
CREATE POLICY "Allow company members to manage" ON public.company_settings FOR ALL USING (company_id = get_user_company_id(auth.uid()));
CREATE POLICY "Allow admins to read audit logs for their company" ON public.audit_log FOR SELECT USING (company_id = get_user_company_id(auth.uid()));
CREATE POLICY "Allow user to manage messages in their conversations" ON public.messages FOR ALL USING (company_id = get_user_company_id(auth.uid()));
CREATE POLICY "Users can only access their own conversations" ON public.conversations FOR SELECT USING (user_id = auth.uid());


-- ### FINAL SETUP ###
-- Schedule materialized view refresh using pg_cron.
SELECT cron.schedule('daily-dashboard-refresh', '0 1 * * *', 'REFRESH MATERIALIZED VIEW public.company_dashboard_metrics');
