-- InvoChat Database Schema
-- Version: 2.0.0
-- Description: Complete schema for the InvoChat application, including tables, RLS, and functions.

--
-- Setup: Extensions
--
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "vector";

--
-- Teardown: Drop existing objects in reverse order of dependency
--
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.get_current_company_id();
DROP FUNCTION IF EXISTS public.apply_updated_at_trigger(regclass[]);

--
-- Function: get_current_company_id
-- Description: Safely retrieves the company_id for the currently authenticated user from their JWT.
--
CREATE OR REPLACE FUNCTION public.get_current_company_id()
RETURNS UUID AS $$
BEGIN
  RETURN (auth.jwt()->>'app_metadata')::jsonb->>'company_id';
EXCEPTION
  WHEN OTHERS THEN
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

--
-- Function: handle_new_user
-- Description: Trigger function to create a new company for a user upon signup and link them.
--
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  new_company_id UUID;
  user_company_name TEXT := NEW.raw_app_meta_data->>'company_name';
BEGIN
  -- Create a new company
  INSERT INTO public.companies (name)
  VALUES (user_company_name)
  RETURNING id INTO new_company_id;

  -- Update the user's app_metadata with the new company_id
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id)
  WHERE id = NEW.id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

--
-- Trigger: on_auth_user_created
-- Description: Executes after a new user is created in the auth schema.
--
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

--
-- Table: companies
-- Description: Stores company information.
--
CREATE TABLE IF NOT EXISTS public.companies (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT (now() AT TIME ZONE 'utc')
);
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;

--
-- Table: users
-- Description: Mirrors auth.users for RLS and profile information.
--
CREATE TABLE IF NOT EXISTS public.users (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT UNIQUE NOT NULL,
  company_id UUID REFERENCES public.companies(id) ON DELETE SET NULL,
  role TEXT NOT NULL DEFAULT 'Member' -- e.g., 'Admin', 'Member'
);
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

--
-- Table: company_settings
-- Description: Stores business logic settings for each company.
--
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id UUID PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days INT NOT NULL DEFAULT 90,
    fast_moving_days INT NOT NULL DEFAULT 30,
    overstock_multiplier NUMERIC NOT NULL DEFAULT 3,
    high_value_threshold NUMERIC NOT NULL DEFAULT 1000,
    predictive_stock_days INT NOT NULL DEFAULT 7,
    created_at TIMESTAMPTZ DEFAULT (now() AT TIME ZONE 'utc'),
    updated_at TIMESTAMPTZ
);
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;


--
-- Table: locations
-- Description: Stores inventory locations like warehouses or stores.
--
CREATE TABLE IF NOT EXISTS public.locations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT (now() AT TIME ZONE 'utc'),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, name)
);
ALTER TABLE public.locations ENABLE ROW LEVEL SECURITY;

--
-- Table: products
-- Description: Core product information.
--
CREATE TABLE IF NOT EXISTS public.products (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT,
  handle TEXT,
  product_type TEXT,
  tags TEXT[],
  status TEXT,
  image_url TEXT,
  external_product_id TEXT,
  created_at TIMESTAMPTZ DEFAULT (now() AT TIME ZONE 'utc'),
  updated_at TIMESTAMPTZ,
  UNIQUE(company_id, external_product_id)
);
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

--
-- Table: product_variants
-- Description: Represents different versions of a product (e.g., size, color).
--
CREATE TABLE IF NOT EXISTS public.product_variants (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  sku TEXT,
  title TEXT,
  option1_name TEXT,
  option1_value TEXT,
  option2_name TEXT,
  option2_value TEXT,
  option3_name TEXT,
  option3_value TEXT,
  barcode TEXT,
  price INT, -- in cents
  compare_at_price INT,
  cost INT, -- in cents
  inventory_quantity INT NOT NULL DEFAULT 0,
  location_id UUID REFERENCES public.locations(id) ON DELETE SET NULL,
  external_variant_id TEXT,
  created_at TIMESTAMPTZ DEFAULT (now() AT TIME ZONE 'utc'),
  updated_at TIMESTAMPTZ,
  UNIQUE(company_id, sku),
  UNIQUE(company_id, external_variant_id)
);
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;

--
-- Table: inventory_ledger
-- Description: Transactional log of all inventory movements for auditing.
--
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type TEXT NOT NULL, -- 'sale', 'purchase_order', 'reconciliation', 'manual_adjustment', 'transfer_in', 'transfer_out'
    quantity_change INT NOT NULL,
    new_quantity INT NOT NULL,
    related_id UUID,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT (now() AT TIME ZONE 'utc')
);
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;


--
-- Table: customers
-- Description: Stores customer information.
--
CREATE TABLE IF NOT EXISTS public.customers (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  customer_name TEXT,
  email TEXT,
  total_orders INT NOT NULL DEFAULT 0,
  total_spent INT NOT NULL DEFAULT 0,
  first_order_date DATE,
  created_at TIMESTAMPTZ DEFAULT (now() AT TIME ZONE 'utc'),
  deleted_at TIMESTAMPTZ
);
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;


--
-- Table: orders
-- Description: Stores sales order headers.
--
CREATE TABLE IF NOT EXISTS public.orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number TEXT NOT NULL,
    external_order_id TEXT,
    customer_id UUID REFERENCES public.customers(id) ON DELETE SET NULL,
    financial_status TEXT,
    fulfillment_status TEXT,
    currency TEXT,
    subtotal INT NOT NULL DEFAULT 0,
    total_tax INT,
    total_shipping INT,
    total_discounts INT,
    total_amount INT NOT NULL,
    source_platform TEXT,
    created_at TIMESTAMPTZ DEFAULT (now() AT TIME ZONE 'utc'),
    updated_at TIMESTAMPTZ
);
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;


--
-- Table: order_line_items
-- Description: Stores individual line items for each sales order.
--
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id UUID REFERENCES public.product_variants(id) ON DELETE SET NULL,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_name TEXT,
    variant_title TEXT,
    sku TEXT,
    quantity INT NOT NULL,
    price INT NOT NULL,
    total_discount INT,
    tax_amount INT,
    cost_at_time INT,
    external_line_item_id TEXT
);
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;

--
-- Table: refund_line_items
-- Description: Logs refund details for order line items.
--
CREATE TABLE IF NOT EXISTS public.refund_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    line_item_id UUID NOT NULL REFERENCES public.order_line_items(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    quantity INT NOT NULL,
    refund_amount INT NOT NULL,
    reason TEXT,
    refunded_at TIMESTAMPTZ DEFAULT (now() AT TIME ZONE 'utc')
);
ALTER TABLE public.refund_line_items ENABLE ROW LEVEL SECURITY;


--
-- Table: suppliers
-- Description: Stores supplier/vendor information.
--
CREATE TABLE IF NOT EXISTS public.suppliers (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  email TEXT,
  phone TEXT,
  default_lead_time_days INT,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT (now() AT TIME ZONE 'utc'),
  updated_at TIMESTAMPTZ,
  UNIQUE(company_id, name)
);
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;

--
-- Table: purchase_orders
-- Description: Stores purchase order headers.
--
CREATE TABLE IF NOT EXISTS public.purchase_orders (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  supplier_id UUID REFERENCES public.suppliers(id) ON DELETE SET NULL,
  status TEXT NOT NULL DEFAULT 'draft', -- draft, sent, partially_received, received, cancelled
  po_number TEXT NOT NULL,
  total_cost INT,
  expected_arrival_date DATE,
  created_at TIMESTAMPTZ DEFAULT (now() AT TIME ZONE 'utc'),
  updated_at TIMESTAMPTZ,
  UNIQUE(company_id, po_number)
);
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;

--
-- Table: purchase_order_line_items
-- Description: Stores individual line items for each purchase order.
--
CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    purchase_order_id UUID NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    quantity INT NOT NULL,
    cost INT NOT NULL,
    quantity_received INT NOT NULL DEFAULT 0
);
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;

--
-- Table: conversations
-- Description: Stores chat conversation threads.
--
CREATE TABLE IF NOT EXISTS public.conversations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT (now() AT TIME ZONE 'utc'),
  last_accessed_at TIMESTAMPTZ DEFAULT (now() AT TIME ZONE 'utc'),
  is_starred BOOLEAN NOT NULL DEFAULT FALSE
);
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;


--
-- Table: messages
-- Description: Stores individual chat messages within a conversation.
--
CREATE TABLE IF NOT EXISTS public.messages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  role TEXT NOT NULL, -- 'user' or 'assistant'
  content TEXT NOT NULL,
  visualization JSONB,
  confidence REAL,
  assumptions TEXT[],
  component TEXT,
  componentProps JSONB,
  created_at TIMESTAMPTZ DEFAULT (now() AT TIME ZONE 'utc')
);
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

--
-- Table: integrations
-- Description: Stores information about connected third-party platforms.
--
CREATE TABLE IF NOT EXISTS public.integrations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  platform TEXT NOT NULL,
  shop_domain TEXT,
  shop_name TEXT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  last_sync_at TIMESTAMPTZ,
  sync_status TEXT,
  created_at TIMESTAMPTZ DEFAULT (now() AT TIME ZONE 'utc'),
  updated_at TIMESTAMPTZ,
  UNIQUE(company_id, platform)
);
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;

--
-- Table: audit_log
-- Description: Logs important events for security and compliance.
--
CREATE TABLE IF NOT EXISTS public.audit_log (
    id BIGSERIAL PRIMARY KEY,
    company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    details JSONB,
    created_at TIMESTAMPTZ DEFAULT (now() AT TIME ZONE 'utc')
);
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

--
-- Table: webhook_events
-- Description: Stores processed webhook IDs to prevent replay attacks.
--
CREATE TABLE IF NOT EXISTS public.webhook_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    integration_id UUID NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id TEXT NOT NULL,
    processed_at TIMESTAMPTZ DEFAULT (now() AT TIME ZONE 'utc'),
    UNIQUE(integration_id, webhook_id)
);
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;


--
-- Table: export_jobs
-- Description: Tracks data export requests.
--
CREATE TABLE IF NOT EXISTS public.export_jobs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    requested_by_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'pending', -- pending, processing, completed, failed
    file_url TEXT,
    error_message TEXT,
    created_at TIMESTAMPTZ DEFAULT (now() AT TIME ZONE 'utc'),
    completed_at TIMESTAMPTZ
);
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;

--
-- View: product_variants_with_details
-- Description: A convenience view for querying variants with their parent product and location info.
--
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.*,
    p.title AS product_title,
    p.status AS product_status,
    p.image_url,
    l.name AS location_name
FROM
    public.product_variants pv
LEFT JOIN public.products p ON pv.product_id = p.id
LEFT JOIN public.locations l ON pv.location_id = l.id;


--
-- RLS Policies
--
CREATE OR REPLACE FUNCTION public.create_rls_policy(
    p_table_name TEXT,
    p_policy_name TEXT,
    p_command TEXT,
    p_using TEXT,
    p_check TEXT DEFAULT 'true'
)
RETURNS VOID AS $$
BEGIN
    EXECUTE format(
        'DROP POLICY IF EXISTS %I ON public.%I; CREATE POLICY %I ON public.%I FOR %s USING (%s) WITH CHECK (%s);',
        p_policy_name, p_table_name, p_policy_name, p_table_name, p_command, p_using, p_check
    );
END;
$$ LANGUAGE plpgsql;

-- Companies
SELECT public.create_rls_policy('companies', 'Users can see their own company.', 'SELECT', 'id = get_current_company_id()');
SELECT public.create_rls_policy('companies', 'Users can update their own company.', 'UPDATE', 'id = get_current_company_id()');

-- Users
SELECT public.create_rls_policy('users', 'Users can see other users in their company.', 'SELECT', 'company_id = get_current_company_id()');
SELECT public.create_rls_policy('users', 'Users can see their own user record.', 'SELECT', 'id = auth.uid()');

-- Generic Company-Scoped Tables
DO $$
DECLARE
    t_name TEXT;
BEGIN
    FOR t_name IN
        SELECT table_name FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name IN (
            'company_settings', 'products', 'product_variants', 'inventory_ledger', 'customers',
            'orders', 'order_line_items', 'suppliers', 'purchase_orders', 'purchase_order_line_items',
            'integrations', 'audit_log', 'webhook_events', 'export_jobs', 'refund_line_items', 'locations'
        )
    LOOP
        PERFORM public.create_rls_policy(t_name, 'Allow full access based on company_id', 'ALL', 'company_id = get_current_company_id()');
    END LOOP;
END;
$$;

-- Conversation & Message Policies
SELECT public.create_rls_policy('conversations', 'Allow access to own conversations', 'ALL', 'user_id = auth.uid() AND company_id = get_current_company_id()');
SELECT public.create_rls_policy('messages', 'Allow access to messages in own conversations', 'ALL', 'company_id = get_current_company_id() AND conversation_id IN (SELECT id FROM conversations WHERE user_id = auth.uid())');


--
-- Indexes for Performance
--
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_products_tags ON public.products USING GIN (tags);
CREATE INDEX IF NOT EXISTS idx_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_variants_sku ON public.product_variants(sku);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON public.orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON public.order_line_items(variant_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id ON public.inventory_ledger(variant_id);
CREATE INDEX IF NOT EXISTS idx_po_line_items_variant_id ON public.purchase_order_line_items(variant_id);


--
-- Function: set_updated_at
-- Description: Automatically sets the updated_at timestamp on a row.
--
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now() at time zone 'utc';
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

--
-- Function: apply_updated_at_trigger
-- Description: Applies the updated_at trigger to a list of tables.
--
CREATE OR REPLACE FUNCTION public.apply_updated_at_trigger(tables regclass[])
RETURNS void AS $$
DECLARE
    tbl regclass;
BEGIN
    FOREACH tbl IN ARRAY tables
    LOOP
        EXECUTE format('
            DROP TRIGGER IF EXISTS handle_updated_at ON %s;
            CREATE TRIGGER handle_updated_at
            BEFORE UPDATE ON %s
            FOR EACH ROW
            EXECUTE FUNCTION public.set_updated_at();
        ', tbl, tbl);
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Apply the trigger to all tables with an 'updated_at' column
SELECT public.apply_updated_at_trigger(ARRAY[
    'public.company_settings', 'public.products', 'public.product_variants',
    'public.orders', 'public.suppliers', 'public.purchase_orders',
    'public.integrations', 'public.locations'
]);

--
-- Function: cleanup_old_data
-- Description: A maintenance function to delete old records to keep the database trim.
--
CREATE OR REPLACE FUNCTION public.cleanup_old_data(
    p_audit_log_retention_days INT DEFAULT 90,
    p_messages_retention_days INT DEFAULT 90
)
RETURNS VOID AS $$
BEGIN
    -- Delete old audit logs
    DELETE FROM public.audit_log
    WHERE created_at < (now() - (p_audit_log_retention_days || ' days')::interval);

    -- Delete old messages
    DELETE FROM public.messages
    WHERE created_at < (now() - (p_messages_retention_days || ' days')::interval);
END;
$$ LANGUAGE plpgsql;

--
-- Final Setup
--
-- Grant usage on the public schema to the service_role (necessary for RLS)
GRANT USAGE ON SCHEMA public TO service_role;
-- Grant permissions for authenticated users
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;
