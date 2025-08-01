-- ============================================================================
-- ARVO: CORE DATABASE SCHEMA
-- ============================================================================
-- This script is idempotent and can be run multiple times safely.
-- It is designed to be the single source of truth for the database structure.
--
-- Sections:
-- 1. Extensions: Enable necessary PostgreSQL extensions.
-- 2. Types: Define custom ENUM types.
-- 3. Core Tables: Create the main tables for the application.
-- 4. Helper Functions: Create SQL functions used in triggers and policies.
-- 5. Triggers: Set up automated actions on data changes.
-- 6. Row-Level Security (RLS): Define access policies for data security.
-- 7. Materialized Views: Create pre-computed views for performance.
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. EXTENSIONS
-- ============================================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_trgm;


-- ============================================================================
-- 2. TYPES
-- ============================================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'company_role') THEN
        CREATE TYPE public.company_role AS ENUM ('Owner', 'Admin', 'Member');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'integration_platform') THEN
        CREATE TYPE public.integration_platform AS ENUM ('shopify', 'woocommerce', 'amazon_fba');
    END IF;
     IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'message_role') THEN
        CREATE TYPE public.message_role AS ENUM ('user', 'assistant', 'tool');
    END IF;
     IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'feedback_type') THEN
        CREATE TYPE public.feedback_type AS ENUM ('helpful', 'unhelpful');
    END IF;
END $$;


-- ============================================================================
-- 3. CORE TABLES
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.companies (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    name text NOT NULL,
    owner_id uuid REFERENCES auth.users(id),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.company_users (
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role public.company_role NOT NULL DEFAULT 'Member',
    PRIMARY KEY (company_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    fast_moving_days integer NOT NULL DEFAULT 30,
    overstock_multiplier real NOT NULL DEFAULT 3.0,
    high_value_threshold integer NOT NULL DEFAULT 100000,
    predictive_stock_days integer NOT NULL DEFAULT 7,
    currency text DEFAULT 'USD',
    timezone text DEFAULT 'UTC',
    tax_rate numeric DEFAULT 0,
    alert_settings jsonb DEFAULT '{"low_stock_threshold": 10, "critical_stock_threshold": 5, "email_notifications": true, "morning_briefing_enabled": true, "morning_briefing_time": "09:00"}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);
-- Additional tables (products, orders, etc.) would follow the same pattern...

-- Ensure all tables exist before moving on to functions/triggers
CREATE TABLE IF NOT EXISTS public.products (id uuid PRIMARY KEY DEFAULT uuid_generate_v4(), company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE, title text NOT NULL, description text, handle text, product_type text, tags text[], status text, image_url text, external_product_id text, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz);
CREATE TABLE IF NOT EXISTS public.product_variants (id uuid PRIMARY KEY DEFAULT uuid_generate_v4(), product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE, company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE, sku text NOT NULL, title text, option1_name text, option1_value text, option2_name text, option2_value text, option3_name text, option3_value text, barcode text, price integer, compare_at_price integer, cost integer, inventory_quantity integer NOT NULL DEFAULT 0, location text, external_variant_id text, reorder_point integer, reorder_quantity integer, created_at timestamptz DEFAULT now(), updated_at timestamptz);
CREATE TABLE IF NOT EXISTS public.inventory_ledger (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE, variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE, change_type text NOT NULL, quantity_change integer NOT NULL, new_quantity integer NOT NULL, related_id uuid, notes text, created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS public.suppliers (id uuid PRIMARY KEY DEFAULT uuid_generate_v4(), company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE, name text NOT NULL, email text, phone text, default_lead_time_days integer, notes text, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz);
CREATE TABLE IF NOT EXISTS public.purchase_orders (id uuid PRIMARY KEY DEFAULT uuid_generate_v4(), company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE, po_number text NOT NULL, supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL, status text NOT NULL DEFAULT 'Draft', total_cost integer NOT NULL DEFAULT 0, expected_arrival_date date, idempotency_key uuid, notes text, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz);
CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (id uuid PRIMARY KEY DEFAULT uuid_generate_v4(), company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE, purchase_order_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE, variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE, quantity integer NOT NULL, cost integer NOT NULL);
CREATE TABLE IF NOT EXISTS public.customers (id uuid PRIMARY KEY DEFAULT uuid_generate_v4(), company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE, name text, email text, external_customer_id text, created_at timestamptz DEFAULT now(), updated_at timestamptz, deleted_at timestamptz);
CREATE TABLE IF NOT EXISTS public.orders (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE, order_number text NOT NULL, external_order_id text, customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL, financial_status text, fulfillment_status text, currency text, subtotal integer NOT NULL, total_tax integer, total_shipping integer, total_discounts integer, total_amount integer NOT NULL, source_platform text, created_at timestamptz DEFAULT now(), updated_at timestamptz);
CREATE TABLE IF NOT EXISTS public.order_line_items (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE, variant_id uuid REFERENCES public.product_variants(id) ON DELETE SET NULL, company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE, product_name text, variant_title text, sku text, quantity integer NOT NULL, price integer NOT NULL, total_discount integer, tax_amount integer, cost_at_time integer, external_line_item_id text);
CREATE TABLE IF NOT EXISTS public.integrations (id uuid PRIMARY KEY DEFAULT uuid_generate_v4(), company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE, platform public.integration_platform NOT NULL, shop_domain text, shop_name text, is_active boolean DEFAULT false, last_sync_at timestamptz, sync_status text, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz);
CREATE TABLE IF NOT EXISTS public.conversations (id uuid PRIMARY KEY DEFAULT uuid_generate_v4(), user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE, company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE, title text NOT NULL, created_at timestamptz DEFAULT now(), last_accessed_at timestamptz DEFAULT now(), is_starred boolean DEFAULT false);
CREATE TABLE IF NOT EXISTS public.messages (id uuid PRIMARY KEY DEFAULT uuid_generate_v4(), conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE, company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE, role public.message_role NOT NULL, content text NOT NULL, component text, componentProps jsonb, visualization jsonb, confidence numeric, assumptions text[], isError boolean, created_at timestamptz DEFAULT now());
CREATE TABLE IF NOT EXISTS public.audit_log (id bigserial PRIMARY KEY, company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE, user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL, action text NOT NULL, details jsonb, created_at timestamptz DEFAULT now());
CREATE TABLE IF NOT EXISTS public.feedback (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE, company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE, subject_id text NOT NULL, subject_type text NOT NULL, feedback public.feedback_type NOT NULL, created_at timestamptz DEFAULT now());
CREATE TABLE IF NOT EXISTS public.channel_fees (id uuid PRIMARY KEY DEFAULT uuid_generate_v4(), company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE, channel_name text NOT NULL, fixed_fee integer, percentage_fee numeric, created_at timestamptz DEFAULT now(), updated_at timestamptz, UNIQUE(company_id, channel_name));
CREATE TABLE IF NOT EXISTS public.export_jobs (id uuid PRIMARY KEY DEFAULT uuid_generate_v4(), company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE, requested_by_user_id uuid NOT NULL REFERENCES auth.users(id), status text NOT NULL DEFAULT 'pending', download_url text, expires_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(), completed_at timestamptz, error_message text);
CREATE TABLE IF NOT EXISTS public.imports (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE, created_by uuid NOT NULL REFERENCES auth.users(id), import_type text NOT NULL, file_name text NOT NULL, total_rows integer, processed_rows integer, failed_rows integer, status text NOT NULL DEFAULT 'pending', errors jsonb, summary jsonb, created_at timestamptz DEFAULT now(), completed_at timestamptz);
CREATE TABLE IF NOT EXISTS public.webhook_events (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE, webhook_id text NOT NULL, created_at timestamptz DEFAULT now(), UNIQUE(integration_id, webhook_id));
-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_company_users_user_id ON public.company_users(user_id);
CREATE INDEX IF NOT EXISTS idx_company_users_company_id ON public.company_users(company_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_company_users_unique ON public.company_users(user_id, company_id);


-- ============================================================================
-- 4. HELPER FUNCTIONS
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_company_id_for_user(p_user_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
BEGIN
  RETURN (
    SELECT company_id 
    FROM public.company_users 
    WHERE user_id = p_user_id 
    LIMIT 1
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.check_user_permission(p_user_id uuid, p_required_role public.company_role)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.company_users
    WHERE user_id = p_user_id
    AND role >= p_required_role
  );
END;
$$;


-- ============================================================================
-- 5. TRIGGERS
-- ============================================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  company_id_to_set uuid;
  user_role public.company_role := 'Owner';
  company_name_clean text;
  company_name_final text;
BEGIN
  -- Sanitize and create a fallback company name
  company_name_clean := COALESCE(TRIM(new.raw_user_meta_data->>'company_name'), '');
  company_name_final := CASE
    WHEN LENGTH(company_name_clean) > 0 THEN LEFT(company_name_clean, 100)
    ELSE COALESCE(SPLIT_PART(new.email, '@', 1), 'My Company')
  END;

  -- Create a new company for the new user
  INSERT INTO public.companies (name, owner_id)
  VALUES (company_name_final, new.id)
  RETURNING id INTO company_id_to_set;

  -- Add the user to the company_users table
  INSERT INTO public.company_users (user_id, company_id, role)
  VALUES (new.id, company_id_to_set, user_role);

  -- Update the user's app_metadata with the new company_id
  UPDATE auth.users
  SET raw_app_meta_data = COALESCE(raw_app_meta_data, '{}'::jsonb) || jsonb_build_object('company_id', company_id_to_set)
  WHERE id = new.id;
  
  -- Create default company settings
  INSERT INTO public.company_settings (company_id)
  VALUES (company_id_to_set);

  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();


-- ============================================================================
-- 6. ROW-LEVEL SECURITY (RLS)
-- ============================================================================

-- Enable RLS on all relevant tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.feedback ENABLE ROW LEVEL SECURITY;

-- Generic policy for tables with a `company_id` column
CREATE OR REPLACE FUNCTION create_rls_policies(table_name text)
RETURNS void AS $$
BEGIN
    -- Policy for SELECT access
    EXECUTE format('DROP POLICY IF EXISTS "Users can read their own company data" ON public.%I;', table_name);
    EXECUTE format('CREATE POLICY "Users can read their own company data" ON public.%I FOR SELECT USING (company_id = public.get_company_id_for_user(auth.uid()));', table_name);

    -- Policy for INSERT access
    EXECUTE format('DROP POLICY IF EXISTS "Users can insert data for their own company" ON public.%I;', table_name);
    EXECUTE format('CREATE POLICY "Users can insert data for their own company" ON public.%I FOR INSERT WITH CHECK (company_id = public.get_company_id_for_user(auth.uid()));', table_name);

    -- Policy for UPDATE access (can be more restrictive)
    EXECUTE format('DROP POLICY IF EXISTS "Users can update their own company data" ON public.%I;', table_name);
    EXECUTE format('CREATE POLICY "Users can update their own company data" ON public.%I FOR UPDATE USING (company_id = public.get_company_id_for_user(auth.uid()));', table_name);

    -- Policy for DELETE access
    EXECUTE format('DROP POLICY IF EXISTS "Users can delete their own company data" ON public.%I;', table_name);
    EXECUTE format('CREATE POLICY "Users can delete their own company data" ON public.%I FOR DELETE USING (company_id = public.get_company_id_for_user(auth.uid()));', table_name);
END;
$$ LANGUAGE plpgsql;

-- Apply generic policies to all tables that have a company_id
SELECT create_rls_policies(table_name) FROM information_schema.columns WHERE column_name = 'company_id' AND table_schema = 'public' AND table_name != 'company_users';


-- Specific policies for `company_users` to avoid recursion
DROP POLICY IF EXISTS "Users can view their own membership" ON public.company_users;
CREATE POLICY "Users can view their own membership" ON public.company_users
    FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Admins can view other members of their company" ON public.company_users;
CREATE POLICY "Admins can view other members of their company" ON public.company_users
    FOR SELECT USING (
        company_id = public.get_company_id_for_user(auth.uid()) AND
        public.check_user_permission(auth.uid(), 'Admin')
    );

DROP POLICY IF EXISTS "Owners can manage their company users" ON public.company_users;
CREATE POLICY "Owners can manage their company users" ON public.company_users
    FOR ALL USING (
        company_id = public.get_company_id_for_user(auth.uid()) AND
        public.check_user_permission(auth.uid(), 'Owner')
    ) WITH CHECK (
        company_id = public.get_company_id_for_user(auth.uid()) AND
        public.check_user_permission(auth.uid(), 'Owner')
    );


-- ============================================================================
-- 7. MATERIALIZED VIEWS
-- ============================================================================
-- These views are used for performance-intensive dashboard queries.

CREATE MATERIALIZED VIEW IF NOT EXISTS public.daily_sales AS
SELECT
    date_trunc('day', o.created_at) AS sale_date,
    o.company_id,
    sum(o.total_amount) AS total_revenue,
    count(DISTINCT o.id) AS total_orders,
    sum(oli.quantity) AS total_items_sold
FROM public.orders o
JOIN public.order_line_items oli ON o.id = oli.order_id
GROUP BY 1, 2;

CREATE UNIQUE INDEX IF NOT EXISTS daily_sales_unique_idx ON public.daily_sales(sale_date, company_id);

-- Add other materialized views here as needed...


-- Function to refresh all materialized views for a given company.
CREATE OR REPLACE FUNCTION public.refresh_all_matviews(p_company_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    REFRESH MATERIALIZED VIEW public.daily_sales;
    -- Add more REFRESH statements here for other views.
END;
$$;


COMMIT;
