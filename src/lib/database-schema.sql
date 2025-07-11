
-- ===============================================================================================
--
--                              INVOCHAT DATABASE SCHEMA (v4.0)
--
--  This script is designed to be idempotent. It can be run multiple times without causing errors.
--
-- ===============================================================================================

-- -----------------------------------------------------------------------------------------------
--  Schema: Extensions & Settings
--  Set up necessary extensions and basic database settings.
-- -----------------------------------------------------------------------------------------------

-- Use pgcrypto for UUID generation, as it's more standard and has fewer permission issues than uuid-ossp.
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Install the pg_cron extension for scheduled tasks.
CREATE EXTENSION IF NOT EXISTS "pg_cron";

-- Enable PostGIS for geographic data types if needed in the future.
-- CREATE EXTENSION IF NOT EXISTS "postgis" WITH SCHEMA "extensions";


-- -----------------------------------------------------------------------------------------------
--  Schema: Custom Types
--  Define custom ENUM types for consistent data values across the application.
-- -----------------------------------------------------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
    CREATE TYPE public.user_role AS ENUM ('Owner', 'Admin', 'Member');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'po_status') THEN
    CREATE TYPE public.po_status AS ENUM ('draft', 'sent', 'partial', 'received', 'cancelled', 'pending_approval');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'message_role') THEN
    CREATE TYPE public.message_role AS ENUM ('user', 'assistant');
  END IF;
END
$$;

-- Grant usage on custom types to authenticated users.
GRANT USAGE ON TYPE public.user_role TO authenticated;
GRANT USAGE ON TYPE public.po_status TO authenticated;
GRANT USAGE ON TYPE public.message_role TO authenticated;


-- -----------------------------------------------------------------------------------------------
--  Schema: Tables
--  Core table definitions for the InvoChat application.
-- -----------------------------------------------------------------------------------------------

-- Companies Table: Represents a tenant in the multi-tenant system.
CREATE TABLE IF NOT EXISTS public.companies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz
);
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;

-- Company Settings Table: Stores configurable business logic for each company.
-- company_id is the primary key to enforce a one-to-one relationship with companies.
CREATE TABLE IF NOT EXISTS public.company_settings (
  company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
  dead_stock_days integer NOT NULL DEFAULT 90,
  fast_moving_days integer NOT NULL DEFAULT 30,
  overstock_multiplier numeric NOT NULL DEFAULT 3,
  high_value_threshold integer NOT NULL DEFAULT 100000,
  predictive_stock_days integer NOT NULL DEFAULT 7,
  currency text NOT NULL DEFAULT 'USD',
  timezone text NOT NULL DEFAULT 'UTC',
  tax_rate numeric NOT NULL DEFAULT 0.0,
  custom_rules jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz
);
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;

-- Products Table: Central repository of all products.
CREATE TABLE IF NOT EXISTS public.products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT,
  sku text NOT NULL,
  name text NOT NULL,
  category text,
  barcode text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz,
  deleted_at timestamptz,
  UNIQUE(company_id, sku)
);
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

-- Locations Table: Warehouses or other places where stock is held.
CREATE TABLE IF NOT EXISTS public.locations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT,
  name text NOT NULL,
  address text,
  is_default boolean NOT NULL DEFAULT false,
  deleted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz,
  UNIQUE(company_id, name)
);
ALTER TABLE public.locations ENABLE ROW LEVEL SECURITY;

-- Inventory Table: Tracks stock levels for each product at each location.
CREATE TABLE IF NOT EXISTS public.inventory (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT,
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
  location_id uuid REFERENCES public.locations(id) ON DELETE SET NULL,
  quantity integer NOT NULL DEFAULT 0,
  on_order_quantity integer NOT NULL DEFAULT 0,
  cost integer NOT NULL DEFAULT 0,
  price integer,
  landed_cost integer,
  last_sold_date date,
  version integer NOT NULL DEFAULT 1,
  source_platform text,
  external_product_id text,
  external_variant_id text,
  external_quantity integer,
  last_sync_at timestamptz,
  deleted_at timestamptz,
  deleted_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz,
  UNIQUE(company_id, product_id, location_id)
);
ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;

-- Vendors (Suppliers) Table
CREATE TABLE IF NOT EXISTS public.vendors (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT,
  vendor_name text NOT NULL,
  contact_info text,
  address text,
  terms text,
  account_number text,
  deleted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz,
  UNIQUE(company_id, vendor_name)
);
ALTER TABLE public.vendors ENABLE ROW LEVEL SECURITY;

-- Supplier Catalogs Table: Links products to suppliers with specific pricing/terms.
CREATE TABLE IF NOT EXISTS public.supplier_catalogs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  supplier_id uuid NOT NULL REFERENCES public.vendors(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  supplier_sku text,
  unit_cost integer NOT NULL,
  moq integer NOT NULL DEFAULT 1,
  lead_time_days integer,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz,
  UNIQUE(supplier_id, product_id)
);
ALTER TABLE public.supplier_catalogs ENABLE ROW LEVEL SECURITY;

-- Reorder Rules Table: Defines reordering logic for products.
CREATE TABLE IF NOT EXISTS public.reorder_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT,
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  location_id uuid REFERENCES public.locations(id) ON DELETE CASCADE,
  rule_type text NOT NULL DEFAULT 'manual',
  min_stock integer,
  max_stock integer,
  reorder_quantity integer,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz,
  UNIQUE(company_id, product_id, location_id),
  CHECK (min_stock IS NULL OR max_stock IS NULL OR min_stock <= max_stock)
);
ALTER TABLE public.reorder_rules ENABLE ROW LEVEL SECURITY;

-- Purchase Orders Table
CREATE TABLE IF NOT EXISTS public.purchase_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT,
  supplier_id uuid REFERENCES public.vendors(id) ON DELETE SET NULL,
  po_number text NOT NULL,
  status public.po_status DEFAULT 'draft',
  order_date date NOT NULL,
  expected_date date,
  total_amount integer NOT NULL DEFAULT 0,
  tax_amount integer,
  shipping_cost integer,
  notes text,
  requires_approval boolean NOT NULL DEFAULT false,
  approved_by uuid,
  approved_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz,
  UNIQUE(company_id, po_number)
);
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ALTER COLUMN po_number SET DEFAULT 'PO-' || TO_CHAR(nextval('purchase_orders_po_number_seq'), 'FM000000');


-- Purchase Order Items Table
CREATE TABLE IF NOT EXISTS public.purchase_order_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  po_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
  quantity_ordered integer NOT NULL,
  quantity_received integer NOT NULL DEFAULT 0,
  unit_cost integer NOT NULL,
  tax_rate numeric,
  UNIQUE(po_id, product_id)
);
ALTER TABLE public.purchase_order_items ENABLE ROW LEVEL SECURITY;

-- Customers Table
CREATE TABLE IF NOT EXISTS public.customers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT,
  platform text,
  external_id text,
  customer_name text NOT NULL,
  email text,
  status text,
  deleted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(company_id, email)
);
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;

-- Sales Table
CREATE TABLE IF NOT EXISTS public.sales (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT,
  sale_number text NOT NULL,
  customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
  customer_name text,
  customer_email text,
  total_amount integer NOT NULL,
  tax_amount integer,
  payment_method text NOT NULL,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users(id),
  external_id text,
  UNIQUE(company_id, sale_number)
);
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales ALTER COLUMN sale_number SET DEFAULT 'SALE-' || TO_CHAR(nextval('sales_sale_number_seq'), 'FM000000');


-- Sale Items Table
CREATE TABLE IF NOT EXISTS public.sale_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sale_id uuid NOT NULL REFERENCES public.sales(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES public.companies(id),
  product_id uuid NOT NULL REFERENCES public.products(id),
  location_id uuid REFERENCES public.locations(id) ON DELETE SET NULL,
  quantity integer NOT NULL,
  unit_price integer NOT NULL,
  cost_at_time integer
);
ALTER TABLE public.sale_items ENABLE ROW LEVEL SECURITY;

-- Conversations Table (for AI chat)
CREATE TABLE IF NOT EXISTS public.conversations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  title text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  last_accessed_at timestamptz NOT NULL DEFAULT now(),
  is_starred boolean NOT NULL DEFAULT false
);
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

-- Messages Table (for AI chat)
CREATE TABLE IF NOT EXISTS public.messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES public.companies(id),
  role public.message_role NOT NULL,
  content text NOT NULL,
  visualization jsonb,
  confidence real,
  assumptions text[],
  component text,
  component_props jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- Channel Fees Table
CREATE TABLE IF NOT EXISTS public.channel_fees (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  channel_name text NOT NULL,
  percentage_fee numeric NOT NULL DEFAULT 0,
  fixed_fee integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz,
  UNIQUE(company_id, channel_name)
);
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;

-- Integrations Table
CREATE TABLE IF NOT EXISTS public.integrations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  platform text NOT NULL,
  shop_domain text,
  shop_name text,
  is_active boolean NOT NULL DEFAULT false,
  last_sync_at timestamptz,
  sync_status text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz,
  UNIQUE(company_id, platform)
);
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;

-- Sync Logs Table
CREATE TABLE IF NOT EXISTS public.sync_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
  sync_type text NOT NULL,
  status text NOT NULL,
  records_synced integer,
  error_message text,
  started_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz
);
ALTER TABLE public.sync_logs ENABLE ROW LEVEL SECURITY;

-- Sync State Table
CREATE TABLE IF NOT EXISTS public.sync_state (
  integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
  sync_type text NOT NULL,
  last_processed_cursor text,
  last_update timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (integration_id, sync_type)
);
ALTER TABLE public.sync_state ENABLE ROW LEVEL SECURITY;

-- Inventory Ledger Table
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  product_id uuid NOT NULL REFERENCES public.products(id),
  location_id uuid REFERENCES public.locations(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users(id),
  change_type text NOT NULL,
  quantity_change integer NOT NULL,
  new_quantity integer NOT NULL,
  related_id uuid,
  notes text
);
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;

-- Export Jobs Table
CREATE TABLE IF NOT EXISTS public.export_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  requested_by_user_id uuid NOT NULL REFERENCES auth.users(id),
  status text NOT NULL DEFAULT 'pending',
  download_url text,
  expires_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;

-- User Feedback Table
CREATE TABLE IF NOT EXISTS public.user_feedback (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  subject_id text NOT NULL,
  subject_type text NOT NULL,
  feedback text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.user_feedback ENABLE ROW LEVEL SECURITY;

-- Audit Log Table
CREATE TABLE IF NOT EXISTS public.audit_log (
  id bigserial PRIMARY KEY,
  timestamp timestamptz NOT NULL DEFAULT now(),
  user_id uuid REFERENCES auth.users(id),
  company_id uuid REFERENCES public.companies(id),
  ip_address inet,
  action text NOT NULL,
  details jsonb
);
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

-- -----------------------------------------------------------------------------------------------
--  Schema: Sequences
--  Define sequences for auto-incrementing numbers.
-- -----------------------------------------------------------------------------------------------

CREATE SEQUENCE IF NOT EXISTS public.sales_sale_number_seq;
CREATE SEQUENCE IF NOT EXISTS public.purchase_orders_po_number_seq;

-- -----------------------------------------------------------------------------------------------
--  Schema: Indexes
--  Create indexes on frequently queried columns to improve performance.
-- -----------------------------------------------------------------------------------------------
-- Indexes on Foreign Keys
CREATE INDEX IF NOT EXISTS idx_users_company_id ON auth.users (id) WHERE (raw_app_meta_data->>'company_id') IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products (company_id);
CREATE INDEX IF NOT EXISTS idx_inventory_product_id ON public.inventory (product_id);
CREATE INDEX IF NOT EXISTS idx_inventory_location_id ON public.inventory (location_id);
CREATE INDEX IF NOT EXISTS idx_vendors_company_id ON public.vendors (company_id);
CREATE INDEX IF NOT EXISTS idx_po_company_id ON public.purchase_orders (company_id);
CREATE INDEX IF NOT EXISTS idx_po_supplier_id ON public.purchase_orders (supplier_id);
CREATE INDEX IF NOT EXISTS idx_po_items_product_id ON public.purchase_order_items (product_id);
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers (company_id);
CREATE INDEX IF NOT EXISTS idx_sales_company_id ON public.sales (company_id);
CREATE INDEX IF NOT EXISTS idx_sales_customer_id ON public.sales (customer_id);
CREATE INDEX IF NOT EXISTS idx_sale_items_company_id ON public.sale_items (company_id);
CREATE INDEX IF NOT EXISTS idx_sale_items_product_id ON public.sale_items (product_id);
CREATE INDEX IF NOT EXISTS idx_conversations_user_id ON public.conversations (user_id);
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id ON public.messages (conversation_id);
CREATE INDEX IF NOT EXISTS idx_integrations_company_id ON public.integrations (company_id);
CREATE INDEX IF NOT EXISTS idx_sync_logs_integration_id ON public.sync_logs (integration_id);
CREATE INDEX IF NOT EXISTS idx_reorder_rules_product_id ON public.reorder_rules (product_id);
CREATE INDEX IF NOT EXISTS idx_supplier_catalogs_product_id ON public.supplier_catalogs (product_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_company_id ON public.inventory_ledger (company_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_product_location ON public.inventory_ledger (product_id, location_id);
CREATE INDEX IF NOT EXISTS idx_export_jobs_company_id ON public.export_jobs (company_id);
CREATE INDEX IF NOT EXISTS idx_channel_fees_company_id ON public.channel_fees (company_id);

-- Other Performance Indexes
CREATE INDEX IF NOT EXISTS idx_inventory_last_sold_date ON public.inventory (last_sold_date);

-- -----------------------------------------------------------------------------------------------
--  Schema: Helper Functions
--  Define helper functions for use in RLS policies, triggers, and RPCs.
-- -----------------------------------------------------------------------------------------------

-- Get company_id from the currently authenticated user's JWT.
CREATE OR REPLACE FUNCTION auth.company_id()
RETURNS uuid
LANGUAGE sql STABLE
AS $$
  SELECT (auth.jwt()->>'app_metadata')::jsonb->>'company_id'::text;
$$;


-- -----------------------------------------------------------------------------------------------
--  Schema: Triggers & Trigger Functions
--  Automate database actions based on table events (INSERT, UPDATE, DELETE).
-- -----------------------------------------------------------------------------------------------

-- Trigger function to handle new user signup.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_company_id uuid;
  company_name_text text;
BEGIN
  -- Extract company name from user metadata.
  company_name_text := trim(new.raw_user_meta_data->>'company_name');
  IF company_name_text IS NULL OR company_name_text = '' THEN
    RAISE EXCEPTION 'Company name cannot be empty.';
  END IF;

  -- Create a new company for the user.
  INSERT INTO public.companies (name)
  VALUES (company_name_text)
  RETURNING id INTO new_company_id;

  -- Update the user's app_metadata with the new company_id and role.
  -- This is the correct, permission-safe way to update user metadata.
  PERFORM auth.admin_update_user_by_id(
    new.id,
    jsonb_build_object(
      'app_metadata', jsonb_build_object(
        'company_id', new_company_id,
        'role', 'Owner'
      )
    )
  );

  RETURN new;
END;
$$;
-- Drop existing trigger to ensure idempotency, then create it.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE PROCEDURE public.handle_new_user();


-- Trigger function to automatically increment a 'version' column on update.
CREATE OR REPLACE FUNCTION public.increment_version()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.version = OLD.version + 1;
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;
-- Apply the version trigger to the inventory table.
DROP TRIGGER IF EXISTS handle_inventory_update ON public.inventory;
CREATE TRIGGER handle_inventory_update
  BEFORE UPDATE ON public.inventory
  FOR EACH ROW
  EXECUTE PROCEDURE public.increment_version();

-- Generic trigger to bump the 'updated_at' column on any table.
CREATE OR REPLACE FUNCTION public.bump_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;
-- Apply the updated_at trigger to relevant tables.
DROP TRIGGER IF EXISTS trigger_products_updated_at ON public.products;
CREATE TRIGGER trigger_products_updated_at BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();

DROP TRIGGER IF EXISTS trigger_vendors_updated_at ON public.vendors;
CREATE TRIGGER trigger_vendors_updated_at BEFORE UPDATE ON public.vendors FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();

DROP TRIGGER IF EXISTS trigger_locations_updated_at ON public.locations;
CREATE TRIGGER trigger_locations_updated_at BEFORE UPDATE ON public.locations FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();

DROP TRIGGER IF EXISTS trigger_purchase_orders_updated_at ON public.purchase_orders;
CREATE TRIGGER trigger_purchase_orders_updated_at BEFORE UPDATE ON public.purchase_orders FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();

DROP TRIGGER IF EXISTS trigger_company_settings_updated_at ON public.company_settings;
CREATE TRIGGER trigger_company_settings_updated_at BEFORE UPDATE ON public.company_settings FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();

-- Trigger to enforce that a message's company_id matches its conversation's company_id
CREATE OR REPLACE FUNCTION public.enforce_message_company_id()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  conv_company_id uuid;
BEGIN
  SELECT company_id INTO conv_company_id
  FROM public.conversations
  WHERE id = NEW.conversation_id;

  IF conv_company_id IS NULL OR conv_company_id <> NEW.company_id THEN
    RAISE EXCEPTION 'Message company_id does not match conversation company_id';
  END IF;

  RETURN NEW;
END;
$$;
-- Apply the message company_id trigger
DROP TRIGGER IF EXISTS trigger_message_company_id ON public.messages;
CREATE TRIGGER trigger_message_company_id
  BEFORE INSERT OR UPDATE ON public.messages
  FOR EACH ROW
  EXECUTE PROCEDURE public.enforce_message_company_id();


-- -----------------------------------------------------------------------------------------------
-- Schema: Row Level Security (RLS) Policies
-- Secure the database by ensuring users can only access their own company's data.
-- -----------------------------------------------------------------------------------------------

-- Policies for core tables
CREATE POLICY "Company access for companies" ON public.companies FOR ALL USING (id = auth.company_id());
CREATE POLICY "Company access for settings" ON public.company_settings FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access for products" ON public.products FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL);
CREATE POLICY "Company access for inventory" ON public.inventory FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL);
CREATE POLICY "Company access for vendors" ON public.vendors FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL);
CREATE POLICY "Company access for reorder_rules" ON public.reorder_rules FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access for po" ON public.purchase_orders FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access for po_items" ON public.purchase_order_items FOR ALL USING (po_id IN (SELECT id FROM public.purchase_orders WHERE company_id = auth.company_id()));
CREATE POLICY "Company access for customers" ON public.customers FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL);
CREATE POLICY "Company access for sales" ON public.sales FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access for sale_items" ON public.sale_items FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Users can manage their own conversations" ON public.conversations FOR ALL USING (user_id = auth.uid());
CREATE POLICY "Users can manage messages in their conversations" ON public.messages FOR ALL USING (conversation_id IN (SELECT id FROM public.conversations WHERE user_id = auth.uid()));
CREATE POLICY "Company access for locations" ON public.locations FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL);
CREATE POLICY "Company access for supplier_catalogs" ON public.supplier_catalogs FOR ALL USING (supplier_id IN (SELECT id FROM public.vendors WHERE company_id = auth.company_id()));
CREATE POLICY "Company access for channel_fees" ON public.channel_fees FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access for user_feedback" ON public.user_feedback FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access to audit log" ON public.audit_log FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access to integrations" ON public.integrations FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access to sync_logs" ON public.sync_logs FOR ALL USING (integration_id IN (SELECT id FROM public.integrations WHERE company_id = auth.company_id()));
CREATE POLICY "Company access to sync_state" ON public.sync_state FOR ALL USING (integration_id IN (SELECT id FROM public.integrations WHERE company_id = auth.company_id()));
CREATE POLICY "Company access to inventory_ledger" ON public.inventory_ledger FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access to export_jobs" ON public.export_jobs FOR ALL USING (company_id = auth.company_id());

-- -----------------------------------------------------------------------------------------------
-- Schema: Stored Procedures (RPCs)
-- Define complex, transactional logic as stored procedures for safety and performance.
-- -----------------------------------------------------------------------------------------------

-- RPC to record a sale and update inventory atomically.
CREATE OR REPLACE FUNCTION public.record_sale_transaction(
  p_company_id uuid,
  p_user_id uuid,
  p_sale_items jsonb,
  p_customer_name text DEFAULT NULL,
  p_customer_email text DEFAULT NULL,
  p_payment_method text DEFAULT 'other',
  p_notes text DEFAULT NULL,
  p_external_id text DEFAULT NULL
)
RETURNS public.sales
LANGUAGE plpgsql
AS $$
DECLARE
  new_sale record;
  new_customer_id uuid;
  total_amount_cents bigint;
  tax_rate numeric;
  tax_amount_cents bigint;
  item_record record;
  inv_record record;
  temp_table_name text := 'sale_items_temp_' || replace(gen_random_uuid()::text, '-', '');
BEGIN
  -- 1. Create a temporary table to hold processed sale items
  EXECUTE format(
    'CREATE TEMP TABLE %I (
      product_id uuid,
      location_id uuid,
      quantity integer,
      unit_price integer,
      cost_at_time integer
    ) ON COMMIT DROP;',
    temp_table_name
  );

  -- 2. Populate the temporary table from the JSON payload, joining to get current cost
  EXECUTE format(
    'INSERT INTO %I (product_id, location_id, quantity, unit_price, cost_at_time)
     SELECT
       (item->>''product_id'')::uuid,
       (item->>''location_id'')::uuid,
       (item->>''quantity'')::integer,
       (item->>''unit_price'')::integer,
       inv.cost
     FROM jsonb_array_elements($1) AS x(item)
     JOIN public.inventory inv
       ON inv.product_id = (x.item->>''product_id'')::uuid
       AND inv.location_id = (x.item->>''location_id'')::uuid
       AND inv.company_id = $2;',
    temp_table_name
  ) USING p_sale_items, p_company_id;

  -- 3. Validate stock levels for all items in the transaction
  FOR item_record IN EXECUTE format('SELECT * FROM %I', temp_table_name)
  LOOP
    SELECT * INTO inv_record FROM public.inventory
    WHERE company_id = p_company_id
      AND product_id = item_record.product_id
      AND location_id = item_record.location_id;

    IF NOT FOUND OR inv_record.quantity < item_record.quantity THEN
      RAISE EXCEPTION 'Insufficient stock for product % at location %.', item_record.product_id, item_record.location_id;
    END IF;
  END LOOP;

  -- 4. Calculate total amount
  EXECUTE format('SELECT SUM(quantity * unit_price) FROM %I', temp_table_name)
  INTO total_amount_cents;

  -- 5. Calculate tax
  SELECT cs.tax_rate INTO tax_rate FROM public.company_settings cs WHERE cs.company_id = p_company_id;
  tax_amount_cents := total_amount_cents * COALESCE(tax_rate, 0);

  -- 6. Upsert customer
  IF p_customer_email IS NOT NULL THEN
    INSERT INTO public.customers(company_id, customer_name, email)
    VALUES (p_company_id, p_customer_name, p_customer_email)
    ON CONFLICT (company_id, email) DO UPDATE
    SET customer_name = EXCLUDED.customer_name
    RETURNING id INTO new_customer_id;
  END IF;

  -- 7. Insert the main sale record
  INSERT INTO public.sales(
    company_id, sale_number, customer_id, customer_name, customer_email,
    total_amount, tax_amount, payment_method, notes, created_by, external_id
  )
  VALUES (
    p_company_id, 'SALE-' || TO_CHAR(nextval('sales_sale_number_seq'), 'FM000000'), new_customer_id,
    p_customer_name, p_customer_email, total_amount_cents, tax_amount_cents,
    p_payment_method, p_notes, p_user_id, p_external_id
  )
  RETURNING * INTO new_sale;

  -- 8. Loop through temp table to insert sale items, update inventory, and create ledger entries
  FOR item_record IN EXECUTE format('SELECT * FROM %I', temp_table_name)
  LOOP
    -- Insert sale item
    INSERT INTO public.sale_items(sale_id, company_id, product_id, location_id, quantity, unit_price, cost_at_time)
    VALUES (new_sale.id, p_company_id, item_record.product_id, item_record.location_id, item_record.quantity, item_record.unit_price, item_record.cost_at_time);

    -- Decrement inventory
    UPDATE public.inventory
    SET
      quantity = quantity - item_record.quantity,
      last_sold_date = CURRENT_DATE
    WHERE
      company_id = p_company_id
      AND product_id = item_record.product_id
      AND location_id = item_record.location_id;

    -- Create inventory ledger entry
    INSERT INTO public.inventory_ledger(company_id, product_id, location_id, change_type, quantity_change, new_quantity, related_id, notes, created_by)
    VALUES (
      p_company_id, item_record.product_id, item_record.location_id, 'sale', -item_record.quantity,
      (SELECT quantity FROM public.inventory WHERE product_id = item_record.product_id AND location_id = item_record.location_id AND company_id = p_company_id),
      new_sale.id, 'Sale #' || new_sale.sale_number, p_user_id
    );
  END LOOP;
  
  -- Refresh materialized views after a successful sale
  PERFORM public.refresh_materialized_views(p_company_id, ARRAY['company_dashboard_metrics', 'customer_analytics_metrics']);

  RETURN new_sale;
END;
$$;


-- -----------------------------------------------------------------------------------------------
-- Schema: Materialized Views
-- Pre-calculate and store complex query results for fast dashboard loading.
-- -----------------------------------------------------------------------------------------------

-- Dashboard Metrics View
CREATE MATERIALIZED VIEW IF NOT EXISTS public.company_dashboard_metrics AS
SELECT
  c.id as company_id,
  SUM(i.quantity * i.cost) AS inventory_value,
  COUNT(DISTINCT i.product_id) AS total_skus,
  COUNT(DISTINCT CASE WHEN i.quantity <= COALESCE(rr.min_stock, 0) THEN i.product_id END) AS low_stock_count
FROM public.companies c
LEFT JOIN public.inventory i ON c.id = i.company_id AND i.deleted_at IS NULL
LEFT JOIN public.reorder_rules rr ON i.product_id = rr.product_id AND i.company_id = rr.company_id
GROUP BY c.id;

CREATE UNIQUE INDEX IF NOT EXISTS company_dashboard_metrics_company_id_idx ON public.company_dashboard_metrics(company_id);

-- Customer Analytics View
CREATE MATERIALIZED VIEW IF NOT EXISTS public.customer_analytics_metrics AS
SELECT
  c.id as company_id,
  COUNT(cust.id) as total_customers,
  COUNT(CASE WHEN cust.created_at >= NOW() - INTERVAL '30 days' THEN cust.id END) as new_customers_last_30_days,
  AVG(s.total_amount) as average_lifetime_value,
  (COUNT(CASE WHEN s.order_count > 1 THEN cust.id END)::numeric / NULLIF(COUNT(cust.id), 0)) as repeat_customer_rate
FROM public.companies c
LEFT JOIN public.customers cust ON c.id = cust.company_id AND cust.deleted_at IS NULL
LEFT JOIN (
  SELECT customer_id, COUNT(*) as order_count, SUM(total_amount) as total_amount
  FROM public.sales
  GROUP BY customer_id
) s ON cust.id = s.customer_id
GROUP BY c.id;

CREATE UNIQUE INDEX IF NOT EXISTS customer_analytics_metrics_company_id_idx ON public.customer_analytics_metrics(company_id);

-- Add RLS to the materialized views
ALTER MATERIALIZED VIEW public.company_dashboard_metrics ENABLE ROW LEVEL SECURITY;
ALTER MATERIALIZED VIEW public.customer_analytics_metrics ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Company can access their own dashboard metrics" ON public.company_dashboard_metrics FOR SELECT USING (company_id = auth.company_id());
CREATE POLICY "Company can access their own customer metrics" ON public.customer_analytics_metrics FOR SELECT USING (company_id = auth.company_id());

-- -----------------------------------------------------------------------------------------------
-- Schema: Functions for Managing Views
-- -----------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.refresh_materialized_views(p_company_id uuid, p_view_names text[] DEFAULT ARRAY['company_dashboard_metrics', 'customer_analytics_metrics'])
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF 'company_dashboard_metrics' = ANY(p_view_names) THEN
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.company_dashboard_metrics;
  END IF;
  IF 'customer_analytics_metrics' = ANY(p_view_names) THEN
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.customer_analytics_metrics;
  END IF;
END;
$$;

-- -----------------------------------------------------------------------------------------------
-- Grant Permissions
-- Set appropriate permissions for different user roles.
-- -----------------------------------------------------------------------------------------------
GRANT USAGE ON SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO postgres, service_role;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO postgres, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO postgres, service_role;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- Allow authenticated users to execute RPCs
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
-- Allow new functions to be executable by default
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO authenticated;

-- -----------------------------------------------------------------------------------------------
-- Storage Policies
-- -----------------------------------------------------------------------------------------------

-- Create a bucket for public assets if it doesn't exist
INSERT INTO storage.buckets (id, name, public)
VALUES ('public_assets', 'public_assets', true)
ON CONFLICT (id) DO NOTHING;

-- Enable RLS on storage objects
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

-- Allow public read access to the 'public_assets' bucket
CREATE POLICY "Enable read access for public assets"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'public_assets');

-- -----------------------------------------------------------------------------------------------
-- Initial Data Refresh
-- -----------------------------------------------------------------------------------------------
-- Perform an initial refresh of the materialized views
-- Note: This might fail on the very first run if no companies exist yet, which is okay.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.companies) THEN
    PERFORM public.refresh_materialized_views(NULL);
  END IF;
END $$;
