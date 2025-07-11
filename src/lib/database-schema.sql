
-- InvoChat - Conversational Inventory Intelligence
-- © 2024 Google LLC. All Rights Reserved.
--
-- This SQL script sets up the complete database schema for the InvoChat application.
-- It should be run once in your Supabase project's SQL Editor.
--
-- For new setups: Run this entire script.
-- For existing setups: Please review carefully before running, as it may modify existing tables.

-- 1. Extensions
-- Enable pgcrypto for gen_random_uuid(), which is standard and secure.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 2. Custom Types
-- Define custom ENUM types for clarity and data integrity.
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

-- 3. Tables
-- Core tables for companies, users, and application data.

CREATE TABLE IF NOT EXISTS public.companies (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  company_name text NOT NULL,
  created_at timestamptz DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.users (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  company_id uuid REFERENCES public.companies(id) ON DELETE SET NULL,
  email text UNIQUE,
  role public.user_role DEFAULT 'Member'::public.user_role,
  deleted_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.company_settings (
  company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
  dead_stock_days integer DEFAULT 90 NOT NULL,
  overstock_multiplier numeric DEFAULT 3 NOT NULL,
  high_value_threshold integer DEFAULT 100000,
  fast_moving_days integer DEFAULT 30,
  predictive_stock_days integer DEFAULT 7,
  currency text DEFAULT 'USD'::text,
  timezone text DEFAULT 'UTC'::text,
  tax_rate numeric DEFAULT 0,
  custom_rules jsonb,
  created_at timestamptz DEFAULT now() NOT NULL,
  updated_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.products (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  sku text NOT NULL,
  name text NOT NULL,
  category text,
  barcode text,
  created_at timestamptz DEFAULT now() NOT NULL,
  updated_at timestamptz,
  UNIQUE(company_id, sku)
);

CREATE TABLE IF NOT EXISTS public.locations (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  name text NOT NULL,
  address text,
  is_default boolean DEFAULT false,
  deleted_at timestamptz,
  UNIQUE(company_id, name)
);

CREATE TABLE IF NOT EXISTS public.inventory (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
  location_id uuid REFERENCES public.locations(id) ON DELETE SET NULL,
  quantity integer DEFAULT 0 NOT NULL,
  cost integer DEFAULT 0 NOT NULL,
  price integer,
  landed_cost integer,
  on_order_quantity integer DEFAULT 0 NOT NULL,
  last_sold_date date,
  version integer DEFAULT 1 NOT NULL,
  deleted_at timestamptz,
  deleted_by uuid REFERENCES public.users(id),
  source_platform text,
  external_product_id text,
  external_variant_id text,
  external_quantity integer,
  created_at timestamptz DEFAULT now() NOT NULL,
  updated_at timestamptz,
  UNIQUE(company_id, product_id, location_id)
);

CREATE TABLE IF NOT EXISTS public.vendors (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    vendor_name text NOT NULL,
    contact_info text,
    address text,
    terms text,
    account_number text,
    deleted_at timestamptz,
    UNIQUE(company_id, vendor_name)
);

CREATE TABLE IF NOT EXISTS public.purchase_orders (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  supplier_id uuid REFERENCES public.vendors(id) ON DELETE SET NULL,
  po_number text NOT NULL,
  status public.po_status DEFAULT 'draft',
  order_date date DEFAULT CURRENT_DATE NOT NULL,
  expected_date date,
  total_amount integer DEFAULT 0 NOT NULL,
  tax_amount integer,
  shipping_cost integer,
  notes text,
  requires_approval boolean DEFAULT false,
  approved_by uuid REFERENCES public.users(id),
  approved_at timestamptz,
  created_at timestamptz DEFAULT now() NOT NULL,
  updated_at timestamptz,
  UNIQUE(company_id, po_number)
);

CREATE SEQUENCE IF NOT EXISTS purchase_orders_po_number_seq;
ALTER TABLE public.purchase_orders ALTER COLUMN po_number SET DEFAULT 'PO-' || TO_CHAR(nextval('purchase_orders_po_number_seq'), 'FM000000');


CREATE TABLE IF NOT EXISTS public.purchase_order_items (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  po_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
  quantity_ordered integer NOT NULL,
  quantity_received integer DEFAULT 0 NOT NULL,
  unit_cost integer NOT NULL,
  tax_rate numeric
);

CREATE TABLE IF NOT EXISTS public.customers (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform text,
    external_id text,
    customer_name text NOT NULL,
    email text,
    status text,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now(),
    UNIQUE(company_id, email)
);

CREATE TABLE IF NOT EXISTS public.sales (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  sale_number text NOT NULL,
  customer_id uuid REFERENCES public.customers(id),
  customer_name text,
  customer_email text,
  total_amount integer NOT NULL,
  tax_amount integer,
  payment_method text NOT NULL,
  notes text,
  created_at timestamptz DEFAULT now() NOT NULL,
  created_by uuid REFERENCES public.users(id),
  UNIQUE(company_id, sale_number)
);
CREATE SEQUENCE IF NOT EXISTS sales_sale_number_seq;

CREATE TABLE IF NOT EXISTS public.sale_items (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    sale_id uuid NOT NULL REFERENCES public.sales(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    quantity integer NOT NULL,
    unit_price integer NOT NULL,
    cost_at_time integer NOT NULL
);

CREATE TABLE IF NOT EXISTS public.conversations (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES public.users(id),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  title text NOT NULL,
  created_at timestamptz DEFAULT now() NOT NULL,
  last_accessed_at timestamptz DEFAULT now() NOT NULL,
  is_starred boolean DEFAULT false NOT NULL
);

CREATE TABLE IF NOT EXISTS public.messages (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES public.companies(id),
  role public.message_role NOT NULL,
  content text NOT NULL,
  visualization jsonb,
  confidence numeric,
  assumptions text[],
  component text,
  component_props jsonb,
  is_error boolean DEFAULT false,
  created_at timestamptz DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.channel_fees (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    channel_name text NOT NULL,
    percentage_fee numeric NOT NULL,
    fixed_fee integer NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz,
    UNIQUE(company_id, channel_name)
);

CREATE TABLE IF NOT EXISTS public.reorder_rules (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    location_id uuid REFERENCES public.locations(id) ON DELETE CASCADE,
    rule_type text DEFAULT 'manual',
    min_stock integer,
    max_stock integer,
    reorder_quantity integer,
    CHECK (min_stock IS NULL OR max_stock IS NULL OR min_stock <= max_stock),
    UNIQUE(company_id, product_id, location_id)
);

CREATE TABLE IF NOT EXISTS public.integrations (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  platform text NOT NULL,
  shop_domain text,
  shop_name text,
  is_active boolean DEFAULT true,
  last_sync_at timestamptz,
  sync_status text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz,
  UNIQUE(company_id, platform)
);

CREATE TABLE IF NOT EXISTS public.sync_state (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    sync_type text NOT NULL,
    last_processed_cursor text,
    last_update timestamptz DEFAULT now(),
    UNIQUE(integration_id, sync_type)
);

CREATE TABLE IF NOT EXISTS public.sync_logs (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    sync_type text NOT NULL,
    status text NOT NULL,
    records_synced integer,
    error_message text,
    started_at timestamptz DEFAULT now(),
    completed_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    location_id uuid REFERENCES public.locations(id) ON DELETE CASCADE,
    created_at timestamptz DEFAULT now() NOT NULL,
    created_by uuid REFERENCES public.users(id),
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid,
    notes text
);

CREATE TABLE IF NOT EXISTS public.supplier_catalogs (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    supplier_id uuid NOT NULL REFERENCES public.vendors(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    supplier_sku text,
    unit_cost integer NOT NULL,
    moq integer DEFAULT 1,
    lead_time_days integer,
    is_active boolean DEFAULT true,
    UNIQUE(supplier_id, product_id)
);

CREATE TABLE IF NOT EXISTS public.user_feedback (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES public.users(id),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    subject_id text NOT NULL,
    subject_type text NOT NULL,
    feedback text NOT NULL,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.audit_log (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid REFERENCES public.users(id),
    company_id uuid REFERENCES public.companies(id),
    action text NOT NULL,
    details jsonb,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.export_jobs (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id),
    requested_by_user_id uuid NOT NULL REFERENCES public.users(id),
    status text NOT NULL,
    download_url text,
    expires_at timestamptz,
    created_at timestamptz DEFAULT now()
);

-- 4. Indexes
-- Add indexes for performance on frequently queried columns, especially foreign keys.
CREATE INDEX IF NOT EXISTS users_company_id_idx ON public.users(company_id);
CREATE INDEX IF NOT EXISTS products_company_id_idx ON public.products(company_id);
CREATE INDEX IF NOT EXISTS inventory_product_id_idx ON public.inventory(product_id);
CREATE INDEX IF NOT EXISTS inventory_location_id_idx ON public.inventory(location_id);
CREATE INDEX IF NOT EXISTS purchase_orders_company_id_idx ON public.purchase_orders(company_id);
CREATE INDEX IF NOT EXISTS purchase_orders_supplier_id_idx ON public.purchase_orders(supplier_id);
CREATE INDEX IF NOT EXISTS purchase_order_items_product_id_idx ON public.purchase_order_items(product_id);
CREATE INDEX IF NOT EXISTS customers_company_id_idx ON public.customers(company_id);
CREATE INDEX IF NOT EXISTS sales_company_id_idx ON public.sales(company_id);
CREATE INDEX IF NOT EXISTS sale_items_company_id_idx ON public.sale_items(company_id);
CREATE INDEX IF NOT EXISTS sale_items_product_id_idx ON public.sale_items(product_id);
CREATE INDEX IF NOT EXISTS conversations_user_id_idx ON public.conversations(user_id);
CREATE INDEX IF NOT EXISTS messages_conversation_id_idx ON public.messages(conversation_id);
CREATE INDEX IF NOT EXISTS messages_company_id_idx ON public.messages(company_id);
CREATE INDEX IF NOT EXISTS channel_fees_company_id_idx ON public.channel_fees(company_id);
CREATE INDEX IF NOT EXISTS reorder_rules_product_id_idx ON public.reorder_rules(product_id);
CREATE INDEX IF NOT EXISTS integrations_company_id_idx ON public.integrations(company_id);
CREATE INDEX IF NOT EXISTS sync_logs_integration_id_idx ON public.sync_logs(integration_id);
CREATE INDEX IF NOT EXISTS inventory_ledger_company_id_idx ON public.inventory_ledger(company_id);
CREATE INDEX IF NOT EXISTS inventory_ledger_product_location_idx ON public.inventory_ledger(product_id, location_id);
CREATE INDEX IF NOT EXISTS supplier_catalogs_product_id_idx ON public.supplier_catalogs(product_id);
CREATE INDEX IF NOT EXISTS export_jobs_company_id_idx ON public.export_jobs(company_id);

-- 5. Helper Functions & Triggers
-- Define functions and triggers for automatic data handling.

CREATE OR REPLACE FUNCTION public.auth_company_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT (auth.jwt()->>'app_metadata')::jsonb->>'company_id'::text
$$;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  company_name_text text;
  new_company_id uuid;
  user_email text;
BEGIN
  -- Extract company name and user email from metadata
  company_name_text := trim(new.raw_user_meta_data->>'company_name');
  user_email := new.email;

  -- Create a new company if a name is provided
  IF company_name_text IS NOT NULL AND company_name_text <> '' THEN
    INSERT INTO public.companies(company_name)
    VALUES (company_name_text)
    RETURNING id INTO new_company_id;
    
    -- Update the user's app_metadata with the new company ID and Owner role
    UPDATE auth.users
    SET app_metadata = jsonb_set(
        jsonb_set(app_metadata, '{company_id}', to_jsonb(new_company_id)),
        '{role}', to_jsonb('Owner'::text)
    )
    WHERE id = new.id;
  END IF;

  -- Insert into public.users
  INSERT INTO public.users(id, company_id, email, role)
  SELECT new.id, (new.app_metadata->>'company_id')::uuid, user_email, (new.app_metadata->>'role')::public.user_role
  WHERE new.id NOT IN (SELECT id FROM public.users);

  RETURN new;
END;
$$;
-- Drop trigger if exists to ensure it's re-creatable
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE PROCEDURE public.handle_new_user();


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
DROP TRIGGER IF EXISTS handle_inventory_update ON public.inventory;
CREATE TRIGGER handle_inventory_update
  BEFORE UPDATE ON public.inventory
  FOR EACH ROW
  EXECUTE PROCEDURE public.increment_version();
  
CREATE OR REPLACE FUNCTION public.bump_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trigger_products_updated_at ON public.products;
CREATE TRIGGER trigger_products_updated_at
  BEFORE UPDATE ON public.products
  FOR EACH ROW
  EXECUTE PROCEDURE public.bump_updated_at();
DROP TRIGGER IF EXISTS trigger_vendors_updated_at ON public.vendors;
CREATE TRIGGER trigger_vendors_updated_at
  BEFORE UPDATE ON public.vendors
  FOR EACH ROW
  EXECUTE PROCEDURE public.bump_updated_at();
DROP TRIGGER IF EXISTS trigger_purchase_orders_updated_at ON public.purchase_orders;
CREATE TRIGGER trigger_purchase_orders_updated_at
  BEFORE UPDATE ON public.purchase_orders
  FOR EACH ROW
  EXECUTE PROCEDURE public.bump_updated_at();

-- 6. Row-Level Security (RLS)
-- Define policies to ensure data isolation between companies.

ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company members can view their own company" ON public.companies FOR SELECT USING (id = auth_company_id());

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view other members of their company" ON public.users FOR SELECT USING (company_id = auth_company_id() AND deleted_at IS NULL);
CREATE POLICY "Users can update their own user record" ON public.users FOR UPDATE USING (id = auth.uid());

ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access to settings" ON public.company_settings FOR ALL USING (company_id = auth_company_id());

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access to products" ON public.products FOR ALL USING (company_id = auth_company_id());

ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access to inventory" ON public.inventory FOR ALL USING (company_id = auth_company_id() AND deleted_at IS NULL);

ALTER TABLE public.vendors ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access to vendors" ON public.vendors FOR ALL USING (company_id = auth_company_id() AND deleted_at IS NULL);

ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access to purchase orders" ON public.purchase_orders FOR ALL USING (company_id = auth_company_id());

ALTER TABLE public.purchase_order_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access to po_items" ON public.purchase_order_items FOR ALL USING (po_id IN (SELECT id FROM public.purchase_orders WHERE company_id = auth_company_id()));

ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access to customers" ON public.customers FOR ALL USING (company_id = auth_company_id() AND deleted_at IS NULL);

ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access to sales" ON public.sales FOR ALL USING (company_id = auth_company_id());

ALTER TABLE public.sale_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access to sale_items" ON public.sale_items FOR ALL USING (company_id = auth_company_id());

ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage their own conversations" ON public.conversations FOR ALL USING (user_id = auth.uid());

-- Trigger to enforce company_id consistency on messages
CREATE OR REPLACE FUNCTION public.enforce_message_company_id()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.company_id <> (SELECT company_id FROM public.conversations WHERE id = NEW.conversation_id) THEN
    RAISE EXCEPTION 'Message company_id must match conversation company_id';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trigger_message_company_id ON public.messages;
CREATE TRIGGER trigger_message_company_id
  BEFORE INSERT OR UPDATE ON public.messages
  FOR EACH ROW
  EXECUTE PROCEDURE public.enforce_message_company_id();
  
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can access messages in their conversations" ON public.messages FOR ALL USING (conversation_id IN (SELECT id FROM public.conversations WHERE user_id = auth.uid()));

ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access to channel fees" ON public.channel_fees FOR ALL USING (company_id = auth_company_id());

ALTER TABLE public.reorder_rules ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access to reorder rules" ON public.reorder_rules FOR ALL USING (company_id = auth_company_id());

ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access to integrations" ON public.integrations FOR ALL USING (company_id = auth_company_id());

ALTER TABLE public.sync_state ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Integration sync state access" ON public.sync_state FOR ALL USING (integration_id IN (SELECT id FROM public.integrations WHERE company_id = auth_company_id()));

ALTER TABLE public.sync_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Integration sync log access" ON public.sync_logs FOR ALL USING (integration_id IN (SELECT id FROM public.integrations WHERE company_id = auth_company_id()));

ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access to inventory ledger" ON public.inventory_ledger FOR ALL USING (company_id = auth_company_id());

ALTER TABLE public.supplier_catalogs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access to supplier catalogs" ON public.supplier_catalogs FOR ALL USING (supplier_id IN (SELECT id FROM public.vendors WHERE company_id = auth_company_id()));

ALTER TABLE public.user_feedback ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users manage their own feedback" ON public.user_feedback FOR ALL USING (company_id = auth_company_id() AND user_id = auth.uid());

ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access to audit log" ON public.audit_log FOR ALL USING (company_id = auth_company_id());

ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access to export jobs" ON public.export_jobs FOR ALL USING (company_id = auth_company_id());


-- 7. Permissions
-- Grant usage and select permissions to roles.
GRANT USAGE ON SCHEMA public TO authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated, service_role;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public to service_role;
GRANT USAGE ON TYPE public.user_role TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO authenticated, service_role;

-- 8. Advanced Functions (RPCs)
-- Stored procedures for complex business logic.
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
  new_sale_id uuid;
  new_customer_id uuid;
  total_amount_cents bigint := 0;
  company_tax_rate numeric;
  tax_amount numeric := 0;
  item_record record;
  temp_table_name text;
BEGIN
  -- Create a temporary table for sale items
  temp_table_name := 'sale_items_temp_' || replace(gen_random_uuid()::text, '-', '');
  EXECUTE format(
    'CREATE TEMP TABLE %I (
      product_id uuid,
      product_name text,
      quantity integer,
      unit_price integer,
      location_id uuid,
      cost_at_time integer
    ) ON COMMIT DROP;',
    temp_table_name
  );

  -- Populate the temporary table
  EXECUTE format(
    'INSERT INTO %I (product_id, product_name, quantity, unit_price, location_id, cost_at_time)
     SELECT
       i.product_id,
       p.name,
       i.quantity,
       i.unit_price,
       i.location_id,
       inv.cost
     FROM
       jsonb_to_recordset(%L) AS i(product_id uuid, quantity integer, unit_price integer, location_id uuid)
       JOIN public.products p ON p.id = i.product_id
       JOIN public.inventory inv ON inv.product_id = i.product_id AND inv.location_id = i.location_id
     WHERE p.company_id = %L;',
    temp_table_name, p_sale_items, p_company_id
  );

  -- Check for sufficient stock
  FOR item_record IN EXECUTE format('SELECT * FROM %I', temp_table_name) LOOP
    IF NOT EXISTS (
      SELECT 1 FROM public.inventory
      WHERE product_id = item_record.product_id
        AND location_id = item_record.location_id
        AND company_id = p_company_id
        AND quantity >= item_record.quantity
    ) THEN
      RAISE EXCEPTION 'Insufficient stock for product % at the specified location', item_record.product_name;
    END IF;
  END LOOP;
  
  -- Calculate total amount from temp table
  EXECUTE format('SELECT SUM(quantity * unit_price) FROM %I', temp_table_name)
  INTO total_amount_cents;

  -- Upsert customer and get their ID
  IF p_customer_email IS NOT NULL THEN
    INSERT INTO public.customers (company_id, customer_name, email)
    VALUES (p_company_id, p_customer_name, p_customer_email)
    ON CONFLICT (company_id, email) DO UPDATE SET customer_name = EXCLUDED.customer_name
    RETURNING id INTO new_customer_id;
  END IF;

  -- Get company tax rate
  SELECT s.tax_rate INTO company_tax_rate FROM public.company_settings s WHERE s.company_id = p_company_id;
  IF company_tax_rate > 0 THEN
    tax_amount := total_amount_cents * company_tax_rate;
  END IF;

  -- Insert the sale
  INSERT INTO public.sales (company_id, sale_number, customer_id, customer_name, customer_email, total_amount, tax_amount, payment_method, notes, created_by)
  VALUES (p_company_id, 'SALE-' || nextval('sales_sale_number_seq'), new_customer_id, p_customer_name, p_customer_email, total_amount_cents, tax_amount, p_payment_method, p_notes, p_user_id)
  RETURNING id INTO new_sale_id;

  -- Insert sale items and update inventory
  FOR item_record IN EXECUTE format('SELECT * FROM %I', temp_table_name) LOOP
    INSERT INTO public.sale_items (sale_id, company_id, product_id, quantity, unit_price, cost_at_time)
    VALUES (new_sale_id, p_company_id, item_record.product_id, item_record.quantity, item_record.unit_price, item_record.cost_at_time);

    UPDATE public.inventory
    SET
      quantity = quantity - item_record.quantity,
      last_sold_date = CURRENT_DATE
    WHERE
      company_id = p_company_id
      AND product_id = item_record.product_id
      AND location_id = item_record.location_id;
      
    INSERT INTO public.inventory_ledger(company_id, product_id, location_id, change_type, quantity_change, new_quantity, related_id, notes, created_by)
    VALUES (p_company_id, item_record.product_id, item_record.location_id, 'sale', -item_record.quantity, 
            (SELECT quantity FROM public.inventory WHERE product_id = item_record.product_id AND location_id = item_record.location_id),
            new_sale_id, 'Sale #' || (SELECT sale_number FROM sales WHERE id = new_sale_id), p_user_id);
  END LOOP;
  
  RETURN (SELECT * FROM public.sales WHERE id = new_sale_id);
END;
$$;


CREATE OR REPLACE FUNCTION public.check_inventory_references(p_company_id uuid, p_product_ids uuid[])
RETURNS TABLE(product_id uuid)
LANGUAGE sql
AS $$
  SELECT product_id FROM public.sale_items WHERE company_id = p_company_id AND product_id = ANY(p_product_ids)
  UNION
  SELECT product_id FROM public.purchase_order_items WHERE po_id IN (SELECT id FROM purchase_orders WHERE company_id = p_company_id) AND product_id = ANY(p_product_ids);
$$;

-- 9. Views
-- Define materialized views for performance-intensive dashboard queries.
CREATE MATERIALIZED VIEW IF NOT EXISTS public.company_dashboard_metrics AS
SELECT
  c.id as company_id,
  COALESCE(SUM(i.quantity * i.cost), 0) AS inventory_value,
  COALESCE(SUM(CASE WHEN i.quantity < COALESCE(rr.min_stock, 0) THEN 1 ELSE 0 END), 0) AS low_stock_count,
  COUNT(DISTINCT p.id) as total_skus
FROM public.companies c
LEFT JOIN public.products p ON p.company_id = c.id
LEFT JOIN public.inventory i ON i.product_id = p.id
LEFT JOIN public.reorder_rules rr ON rr.product_id = p.id AND rr.location_id = i.location_id
GROUP BY c.id;

CREATE MATERIALIZED VIEW IF NOT EXISTS public.customer_analytics_metrics AS
SELECT
  c.id as company_id,
  COUNT(DISTINCT cust.id) as total_customers,
  COUNT(DISTINCT CASE WHEN cust.created_at >= now() - interval '30 days' THEN cust.id END) as new_customers_last_30_days,
  AVG(s.total_amount) as average_lifetime_value,
  (COUNT(DISTINCT CASE WHEN s.order_count > 1 THEN s.customer_id END)::numeric / NULLIF(COUNT(DISTINCT s.customer_id), 0)) as repeat_customer_rate
FROM public.companies c
LEFT JOIN public.customers cust ON cust.company_id = c.id
LEFT JOIN (
  SELECT customer_id, COUNT(id) as order_count, SUM(total_amount) as total_amount
  FROM public.sales
  GROUP BY customer_id
) s ON s.customer_id = cust.id
GROUP BY c.id;

ALTER MATERIALIZED VIEW public.company_dashboard_metrics ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company can access own dashboard metrics" ON public.company_dashboard_metrics FOR SELECT USING (company_id = auth_company_id());

ALTER MATERIALIZED VIEW public.customer_analytics_metrics ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company can access own customer metrics" ON public.customer_analytics_metrics FOR SELECT USING (company_id = auth_company_id());

-- Create the refresh function
CREATE OR REPLACE FUNCTION public.refresh_materialized_views()
RETURNS void LANGUAGE sql AS $$
  REFRESH MATERIALIZED VIEW CONCURRENTLY public.company_dashboard_metrics;
  REFRESH MATERIALIZED VIEW CONCURRENTLY public.customer_analytics_metrics;
$$;

-- Initial refresh of the views
SELECT public.refresh_materialized_views();
