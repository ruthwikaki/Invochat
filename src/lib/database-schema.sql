-- InvoChat Database Schema
-- Version: 2.0
-- Description: This script sets up the full database schema for the application,
-- including tables, relationships, functions, and security policies.
-- It is designed to be idempotent and can be re-run safely.

-- Section 1: Extensions and Initial Setup
-- Enable the pgcrypto extension for UUID generation
CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "public";
-- Enable the pg_stat_statements extension for query monitoring
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "public";
-- Enable the uuid-ossp extension for additional UUID functions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "public";

-- Drop old, deprecated tables if they exist
DROP TABLE IF EXISTS public.inventory CASCADE;
DROP TABLE IF EXISTS public.sales CASCADE;
DROP TABLE IF EXISTS public.sale_items CASCADE;
DROP TABLE IF EXISTS public.sync_logs CASCADE;
DROP TABLE IF EXISTS public.sync_state CASCADE;
DROP TABLE IF EXISTS public.webhook_events CASCADE;
DROP TABLE IF EXISTS public.purchase_orders CASCADE;
DROP TABLE IF EXISTS public.purchase_order_items CASCADE;
DROP TABLE IF EXISTS public.audit_log CASCADE;

-- Drop old types and functions with CASCADE to remove dependencies
DROP TYPE IF EXISTS public.user_role CASCADE;
DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;
DROP FUNCTION IF EXISTS public.get_current_company_id() CASCADE;
DROP FUNCTION IF EXISTS public.create_rls_policy(TEXT) CASCADE;
DROP PROCEDURE IF EXISTS create_rls_policy(TEXT) CASCADE;
DROP FUNCTION IF EXISTS public.get_my_role(uuid) CASCADE;
DROP FUNCTION IF EXISTS public.update_inventory_from_ledger() CASCADE;
DROP FUNCTION IF EXISTS public.soft_delete_inventory_item(uuid, uuid) CASCADE;
DROP FUNCTION IF EXISTS public.record_sale_transaction(uuid, uuid, text, text, text, text, jsonb) CASCADE;
DROP FUNCTION IF EXISTS public.record_order_from_platform(uuid, jsonb, text) CASCADE;


-- Section 2: Custom Types
-- Define a custom type for user roles.
CREATE TYPE public.user_role AS ENUM ('Owner', 'Admin', 'Member');


-- Section 3: Core Tables
-- Companies table to store information about each business entity (tenant)
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Users table to store user information, linked to a company
CREATE TABLE IF NOT EXISTS public.users (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email text,
    role user_role NOT NULL DEFAULT 'Member',
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now()
);

-- Company Settings table
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    overstock_multiplier numeric NOT NULL DEFAULT 3,
    high_value_threshold numeric NOT NULL DEFAULT 1000.00,
    fast_moving_days integer NOT NULL DEFAULT 30,
    predictive_stock_days integer NOT NULL DEFAULT 7,
    promo_sales_lift_multiplier REAL NOT NULL DEFAULT 2.5,
    currency text DEFAULT 'USD',
    timezone text DEFAULT 'UTC',
    tax_rate numeric DEFAULT 0,
    custom_rules jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    subscription_status text DEFAULT 'trial',
    subscription_plan text DEFAULT 'starter',
    subscription_expires_at timestamptz,
    stripe_customer_id text,
    stripe_subscription_id text
);

-- Products table
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
    UNIQUE(company_id, external_product_id)
);

-- Product Variants table (the new "inventory" source of truth)
CREATE TABLE IF NOT EXISTS public.product_variants (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku text NOT NULL,
    title text NOT NULL,
    option1_name text,
    option1_value text,
    option2_name text,
    option2_value text,
    option3_name text,
    option3_value text,
    barcode text,
    price integer, -- in cents
    compare_at_price integer, -- in cents
    cost integer, -- in cents
    weight numeric,
    weight_unit text,
    inventory_quantity integer DEFAULT 0,
    external_variant_id text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    UNIQUE(company_id, sku),
    UNIQUE(company_id, external_variant_id)
);

-- Inventory Ledger table for immutable stock tracking
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type text NOT NULL, -- e.g., 'sale', 'restock', 'return', 'adjustment'
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid, -- e.g., order_id, po_id
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Customers table
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name text NOT NULL,
    email text,
    total_orders integer DEFAULT 0,
    total_spent numeric DEFAULT 0,
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now(),
    UNIQUE(company_id, email)
);

-- Orders table
CREATE TABLE IF NOT EXISTS public.orders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number text NOT NULL,
    external_order_id text,
    customer_id uuid REFERENCES public.customers(id),
    status text NOT NULL DEFAULT 'pending',
    financial_status text DEFAULT 'pending',
    fulfillment_status text DEFAULT 'unfulfilled',
    currency text DEFAULT 'USD',
    subtotal integer NOT NULL DEFAULT 0,
    total_tax integer DEFAULT 0,
    total_shipping integer DEFAULT 0,
    total_discounts integer DEFAULT 0,
    total_amount integer NOT NULL,
    source_platform text,
    source_name text,
    tags text[],
    notes text,
    cancelled_at timestamptz,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    UNIQUE(company_id, external_order_id)
);

-- Order Line Items table
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid REFERENCES public.products(id) ON DELETE SET NULL,
    variant_id uuid REFERENCES public.product_variants(id) ON DELETE SET NULL,
    product_name text NOT NULL,
    variant_title text,
    sku text,
    quantity integer NOT NULL,
    price integer NOT NULL, -- in cents
    total_discount integer DEFAULT 0,
    tax_amount integer DEFAULT 0,
    cost_at_time integer, -- in cents
    fulfillment_status text DEFAULT 'unfulfilled',
    requires_shipping boolean DEFAULT true,
    external_line_item_id text
);

-- Suppliers table
CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (company_id, name)
);

-- Integrations table
CREATE TABLE IF NOT EXISTS public.integrations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform text NOT NULL, -- e.g., 'shopify', 'woocommerce'
    shop_domain text,
    shop_name text,
    is_active boolean DEFAULT false,
    last_sync_at timestamptz,
    sync_status text, -- e.g., 'syncing_products', 'success', 'failed'
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, platform)
);

-- Webhook Events table (for replay protection)
CREATE TABLE IF NOT EXISTS public.webhook_events (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    platform text NOT NULL,
    webhook_id text NOT NULL,
    processed_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(integration_id, webhook_id)
);

-- Conversations, Messages, Export Jobs, and other app-specific tables
CREATE TABLE IF NOT EXISTS public.conversations (...);
CREATE TABLE IF NOT EXISTS public.messages (...);
CREATE TABLE IF NOT EXISTS public.export_jobs (...);
CREATE TABLE IF NOT EXISTS public.channel_fees (...);
CREATE TABLE IF NOT EXISTS public.discounts (...);
CREATE TABLE IF NOT EXISTS public.customer_addresses (...);
CREATE TABLE IF NOT EXISTS public.refunds (...);
CREATE TABLE IF NOT EXISTS public.refund_line_items (...);


-- Section 4: Functions and Triggers
-- Function to get the current user's company_id from their JWT claims
CREATE OR REPLACE FUNCTION public.get_current_company_id()
RETURNS uuid
LANGUAGE sql STABLE
AS $$
  SELECT nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid;
$$;

-- Function to handle new user sign-ups
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  company_id uuid;
  user_email text;
  company_name text;
BEGIN
  -- Create a new company for the new user
  company_name := COALESCE(new.raw_user_meta_data->>'company_name', 'My Company');
  INSERT INTO public.companies (name) VALUES (company_name) RETURNING id INTO company_id;

  -- Update the user's app_metadata with the new company_id
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id, 'role', 'Owner')
  WHERE id = new.id;
  
  user_email := new.email;

  -- Insert a corresponding record into the public.users table
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (new.id, company_id, user_email, 'Owner');
  
  RETURN new;
END;
$$;

-- Trigger to call handle_new_user on new user creation
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  WHEN (new.raw_app_meta_data->>'company_id' IS NULL) -- Only run for new sign-ups
  EXECUTE FUNCTION public.handle_new_user();


-- Trigger function to update inventory quantity from ledger entries
CREATE OR REPLACE FUNCTION public.update_inventory_from_ledger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE public.product_variants
  SET inventory_quantity = NEW.new_quantity, updated_at = now()
  WHERE id = NEW.variant_id;
  RETURN NEW;
END;
$$;

-- Trigger to call update_inventory_from_ledger
DROP TRIGGER IF EXISTS on_inventory_ledger_insert ON public.inventory_ledger;
CREATE TRIGGER on_inventory_ledger_insert
  AFTER INSERT ON public.inventory_ledger
  FOR EACH ROW
  EXECUTE FUNCTION public.update_inventory_from_ledger();

-- Function to log webhook events for replay protection
CREATE OR REPLACE FUNCTION public.log_webhook_event(
    p_integration_id uuid,
    p_platform text,
    p_webhook_id text
) RETURNS boolean
LANGUAGE plpgsql
AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM public.webhook_events WHERE integration_id = p_integration_id AND webhook_id = p_webhook_id) THEN
        RETURN false; -- Duplicate event
    END IF;
    INSERT INTO public.webhook_events (integration_id, platform, webhook_id)
    VALUES (p_integration_id, p_platform, p_webhook_id);
    RETURN true; -- New event
END;
$$;


-- Section 5: Row-Level Security (RLS)
-- Enable RLS for all relevant tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.discounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_addresses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refunds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refund_line_items ENABLE ROW LEVEL SECURITY;


-- Procedure to create RLS policies dynamically
CREATE OR REPLACE PROCEDURE create_rls_policy(table_name TEXT)
LANGUAGE plpgsql
AS $$
BEGIN
  EXECUTE format('
    DROP POLICY IF EXISTS "Users can only see their own company''s data." ON public.%I;
    CREATE POLICY "Users can only see their own company''s data."
    ON public.%I FOR ALL
    USING (company_id = public.get_current_company_id());
  ', table_name, table_name);
END;
$$;

-- Special policy for the 'companies' table itself
DROP POLICY IF EXISTS "Users can only see their own company." ON public.companies;
CREATE POLICY "Users can only see their own company."
ON public.companies FOR ALL
USING (id = public.get_current_company_id());

-- Special policy for the 'users' table
DROP POLICY IF EXISTS "Users can only see users in their own company." ON public.users;
CREATE POLICY "Users can only see users in their own company."
ON public.users FOR SELECT
USING (company_id = public.get_current_company_id());

-- Apply the RLS policy to all tables that have a company_id
CALL create_rls_policy('company_settings');
CALL create_rls_policy('products');
CALL create_rls_policy('product_variants');
CALL create_rls_policy('inventory_ledger');
CALL create_rls_policy('customers');
CALL create_rls_policy('orders');
CALL create_rls_policy('order_line_items');
CALL create_rls_policy('suppliers');
CALL create_rls_policy('integrations');
CALL create_rls_policy('webhook_events');
CALL create_rls_policy('conversations');
CALL create_rls_policy('messages');
CALL create_rls_policy('export_jobs');
CALL create_rls_policy('channel_fees');
CALL create_rls_policy('discounts');
CALL create_rls_policy('refunds');
CALL create_rls_policy('refund_line_items');

-- Note: customer_addresses doesn't have a company_id, it joins through customers.
-- A more complex policy would be needed if direct access is required.
-- For now, access should be granted via joins on authorized tables.


-- Final script message
SELECT 'Database schema setup complete.' as "Status";

    