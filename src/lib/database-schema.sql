
-- ============================================================================
-- ARVO: DATABASE SCHEMA & AUTHENTICATION SETUP
-- ============================================================================
-- This script sets up the entire database schema, including tables,
-- functions, row-level security (RLS) policies, and database triggers.
-- It is designed to be run once in the Supabase SQL Editor.
-- ============================================================================

-- Force a transaction to ensure all or nothing
BEGIN;

-- ============================================================================
-- EXTENSIONS
-- ============================================================================
-- Enable required PostgreSQL extensions.

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- ENUM TYPES
-- ============================================================================
-- Define custom ENUM types for consistency across the database.

-- Drop existing enums if they exist to start fresh
DROP TYPE IF EXISTS public.company_role CASCADE;
DROP TYPE IF EXISTS public.integration_platform CASCADE;
DROP TYPE IF EXISTS public.message_role CASCADE;
DROP TYPE IF EXISTS public.feedback_type CASCADE;

-- Create the ENUM types
CREATE TYPE public.company_role AS ENUM ('Owner', 'Admin', 'Member');
CREATE TYPE public.integration_platform AS ENUM ('shopify', 'woocommerce', 'amazon_fba');
CREATE TYPE public.message_role AS ENUM ('user', 'assistant', 'tool');
CREATE TYPE public.feedback_type AS ENUM ('helpful', 'unhelpful');


-- ============================================================================
-- TABLES
-- ============================================================================
-- Define all the tables for the application.

-- 1. COMPANIES: Stores company information
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    name text NOT NULL,
    owner_id uuid REFERENCES auth.users(id),
    created_at timestamptz NOT NULL DEFAULT now()
);

-- 2. COMPANY_USERS: Links users to companies with roles
CREATE TABLE IF NOT EXISTS public.company_users (
    company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE NOT NULL,
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    role public.company_role NOT NULL DEFAULT 'Member',
    PRIMARY KEY (company_id, user_id)
);

-- 3. PRODUCTS: Stores main product information
CREATE TABLE IF NOT EXISTS public.products (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    description text,
    handle text,
    product_type text,
    tags text[],
    status text,
    image_url text,
    external_product_id text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    CONSTRAINT unique_product_external_id UNIQUE (company_id, external_product_id)
);

-- 4. SUPPLIERS: Stores supplier information
CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);

-- 5. PRODUCT_VARIANTS: Stores individual product variants (SKUs)
CREATE TABLE IF NOT EXISTS public.product_variants (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL,
    sku text NOT NULL,
    title text,
    option1_name text,
    option1_value text,
    option2_name text,
    option2_value text,
    option3_name text,
    option3_value text,
    barcode text,
    price integer,
    compare_at_price integer,
    cost integer,
    reorder_point integer,
    reorder_quantity integer,
    inventory_quantity integer NOT NULL DEFAULT 0,
    location text,
    external_variant_id text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    CONSTRAINT unique_sku_per_company UNIQUE (company_id, sku)
);

-- 6. CUSTOMERS: Stores customer information
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text,
    email text,
    phone text,
    external_customer_id text,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz
);

-- 7. ORDERS: Stores sales order information
CREATE TABLE IF NOT EXISTS public.orders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
    order_number text NOT NULL,
    external_order_id text,
    financial_status text,
    fulfillment_status text,
    currency text,
    subtotal integer NOT NULL,
    total_tax integer,
    total_shipping integer,
    total_discounts integer,
    total_amount integer NOT NULL,
    source_platform text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz
);

-- 8. ORDER_LINE_ITEMS: Stores individual items within an order
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id uuid REFERENCES public.product_variants(id) ON DELETE SET NULL,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_name text,
    variant_title text,
    sku text,
    quantity integer NOT NULL,
    price integer NOT NULL,
    total_discount integer,
    tax_amount integer,
    cost_at_time integer,
    external_line_item_id text
);

-- 9. PURCHASE_ORDERS: Stores purchase order information
CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL,
    status text NOT NULL DEFAULT 'Draft',
    po_number text NOT NULL,
    total_cost integer NOT NULL,
    expected_arrival_date date,
    idempotency_key uuid,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);

-- 10. PURCHASE_ORDER_LINE_ITEMS: Stores items within a purchase order
CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    purchase_order_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    quantity integer NOT NULL,
    cost integer NOT NULL
);

-- 11. INVENTORY_LEDGER: Transactional log of all stock movements
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- 12. INTEGRATIONS: Stores third-party platform connection details
CREATE TABLE IF NOT EXISTS public.integrations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform public.integration_platform NOT NULL,
    shop_domain text,
    shop_name text,
    is_active boolean DEFAULT false,
    last_sync_at timestamptz,
    sync_status text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, platform)
);

-- 13. WEBHOOK_EVENTS: Logs incoming webhooks to prevent replay attacks
CREATE TABLE IF NOT EXISTS public.webhook_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id text NOT NULL,
    created_at timestamptz DEFAULT now(),
    UNIQUE (integration_id, webhook_id)
);

-- 14. COMPANY_SETTINGS: Stores company-specific settings for AI and business logic
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    fast_moving_days integer NOT NULL DEFAULT 30,
    overstock_multiplier real NOT NULL DEFAULT 3.0,
    high_value_threshold integer NOT NULL DEFAULT 100000, -- in cents
    predictive_stock_days integer NOT NULL DEFAULT 7,
    currency text DEFAULT 'USD',
    timezone text DEFAULT 'UTC',
    tax_rate numeric DEFAULT 0,
    alert_settings jsonb DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);

-- 15. CHANNEL_FEES: Stores sales channel specific fees for profit calculations
CREATE TABLE IF NOT EXISTS public.channel_fees (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    channel_name text NOT NULL,
    percentage_fee numeric,
    fixed_fee integer, -- in cents
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    UNIQUE (company_id, channel_name)
);

-- 16. EXPORT_JOBS: Stores information about data export requests
CREATE TABLE IF NOT EXISTS public.export_jobs (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    requested_by_user_id uuid NOT NULL REFERENCES auth.users(id),
    status text NOT NULL DEFAULT 'pending',
    download_url text,
    expires_at timestamptz,
    error_message text,
    created_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz
);

-- 17. AUDIT_LOG: Stores a record of all significant user actions
CREATE TABLE IF NOT EXISTS public.audit_log (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id uuid REFERENCES auth.users(id),
    action text NOT NULL,
    details jsonb,
    created_at timestamptz DEFAULT now()
);

-- 18. CONVERSATIONS: Stores metadata for AI chat conversations
CREATE TABLE IF NOT EXISTS public.conversations (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  title text NOT NULL,
  created_at timestamptz DEFAULT now(),
  last_accessed_at timestamptz DEFAULT now(),
  is_starred boolean DEFAULT false
);

-- 19. MESSAGES: Stores individual messages within a conversation
CREATE TABLE IF NOT EXISTS public.messages (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  role public.message_role NOT NULL,
  content text NOT NULL,
  component text,
  "componentProps" jsonb,
  visualization jsonb,
  confidence numeric,
  assumptions text[],
  "isError" boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);

-- 20. FEEDBACK: Stores user feedback on AI responses
CREATE TABLE IF NOT EXISTS public.feedback (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    subject_id text NOT NULL,
    subject_type text NOT NULL,
    feedback public.feedback_type NOT NULL,
    created_at timestamptz DEFAULT now()
);

-- 21. IMPORTS: Stores a log of all data import jobs
CREATE TABLE IF NOT EXISTS public.imports (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    import_type text NOT NULL,
    file_name text NOT NULL,
    total_rows integer,
    processed_rows integer,
    failed_rows integer,
    status text NOT NULL DEFAULT 'pending',
    errors jsonb,
    summary jsonb,
    created_at timestamptz DEFAULT now(),
    completed_at timestamptz
);

-- ============================================================================
-- FIX #1: ROBUST USER SIGNUP TRIGGER
-- ============================================================================
-- This single function replaces the previous logic to be more resilient.

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
  company_name_clean := COALESCE(TRIM(new.raw_user_meta_data->>'company_name'), '');
  
  IF LENGTH(company_name_clean) = 0 THEN
    company_name_final := 'Company for ' || new.email;
  ELSE
    company_name_final := LEFT(company_name_clean, 100);
  END IF;

  INSERT INTO public.companies (name, owner_id)
  VALUES (company_name_final, new.id)
  RETURNING id INTO company_id_to_set;

  INSERT INTO public.company_users (user_id, company_id, role)
  VALUES (new.id, company_id_to_set, user_role);

  UPDATE auth.users
  SET raw_app_meta_data = jsonb_set(
      COALESCE(raw_app_meta_data, '{}'::jsonb),
      '{company_id}',
      to_jsonb(company_id_to_set)
  )
  WHERE id = new.id;
  
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
-- FIX #2: GET_COMPANY_ID_FOR_USER HELPER FUNCTION
-- ============================================================================
-- This function fixes the infinite recursion bug and JWT race condition by
-- securely reading the company_id from the user's session token.

-- First, drop the dependent policies temporarily
DO $$
DECLARE
    policy_record record;
BEGIN
    FOR policy_record IN
        SELECT
            'ALTER TABLE ' || quote_ident(schemaname) || '.' || quote_ident(tablename) ||
            ' DISABLE ROW LEVEL SECURITY;' AS disable_command
        FROM
            pg_policies
        WHERE
            -- This condition finds policies that use our specific function in their definitions
            (policyname LIKE '%User can access their own company data%' OR qual ILIKE '%get_company_id_for_user(auth.uid())%')
        GROUP BY schemaname, tablename
    LOOP
        EXECUTE policy_record.disable_command;
    END LOOP;
END;
$$;


-- Now we can safely drop and recreate the function
DROP FUNCTION IF EXISTS public.get_company_id_for_user(p_user_id uuid);
CREATE OR REPLACE FUNCTION public.get_company_id_for_user()
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
BEGIN
  -- This is the secure way to get a value from the user's JWT claims.
  -- The 'true' argument makes it return NULL instead of throwing an error if the claim is missing.
  RETURN NULLIF(current_setting('request.jwt.claims', true)::jsonb->'app_metadata'->>'company_id', '')::uuid;
EXCEPTION
  -- Handle cases where the setting is not available or casting fails
  WHEN OTHERS THEN
    RETURN NULL;
END;
$$;

-- ============================================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================================================
-- Re-create policies using the corrected helper function and re-enable RLS.

-- -- Helper to safely drop policies
-- CREATE OR REPLACE PROCEDURE drop_policy_if_exists(t_name text, p_name text) AS $$
-- BEGIN
--   IF EXISTS (SELECT 1 FROM pg_policies WHERE tablename=t_name AND policyname=p_name)
--   THEN EXECUTE format('DROP POLICY %I ON %I;', p_name, t_name);
--   END IF;
-- END;
-- $$ LANGUAGE plpgsql;

-- Simplified RLS policy creation
CREATE OR REPLACE PROCEDURE apply_rls_policy(
    t_name text,
    p_name text,
    p_command text,
    p_using text
) AS $$
BEGIN
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I;', p_name, t_name);
    EXECUTE format('CREATE POLICY %I ON %I FOR %s USING (%s);', p_name, t_name, p_command, p_using);
END;
$$ LANGUAGE plpgsql;

-- Apply common read policy to multiple tables
DO $$
DECLARE
    table_name text;
BEGIN
    FOREACH table_name IN ARRAY ARRAY[
        'products', 'product_variants', 'suppliers', 'customers', 'orders',
        'order_line_items', 'purchase_orders', 'purchase_order_line_items',
        'inventory_ledger', 'company_settings', 'integrations', 'channel_fees',
        'audit_log', 'conversations', 'messages', 'feedback', 'export_jobs',
        'imports', 'webhook_events', 'companies', 'company_users'
    ]
    LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', table_name);
        CALL apply_rls_policy(table_name, 'User can access their own company data', 'ALL', 'company_id = public.get_company_id_for_user()');
    END LOOP;
END;
$$;

-- ============================================================================
-- INDEXES
-- ============================================================================
-- Add indexes for performance.

CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_variants_company_id ON public.product_variants(company_id);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_po_company_id ON public.purchase_orders(company_id);
CREATE INDEX IF NOT EXISTS idx_po_items_po_id ON public.purchase_order_line_items(purchase_order_id);
CREATE INDEX IF NOT EXISTS idx_ledger_variant_id ON public.inventory_ledger(variant_id);
CREATE INDEX IF NOT EXISTS idx_ledger_company_id_created_at ON public.inventory_ledger(company_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_company_users_user_company ON public.company_users(user_id, company_id);

-- Commit the transaction
COMMIT;
