-- InvoChat - Database Schema
-- Version: 4.0
-- Description: This script sets up the entire database schema for a new InvoChat instance.

-- 1. Extensions
------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 2. Custom Types
------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE public.user_role AS ENUM ('Owner', 'Admin', 'Member');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'po_status') THEN
        CREATE TYPE public.po_status AS ENUM ('draft', 'pending_approval', 'sent', 'partial', 'received', 'cancelled');
    END IF;
END$$;


-- 3. Tables
------------------------------------------------------------

-- Companies Table
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);

-- Users Table
CREATE TABLE IF NOT EXISTS public.users (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid REFERENCES public.companies(id) ON DELETE SET NULL,
    email text UNIQUE,
    role public.user_role NOT NULL DEFAULT 'Member',
    deleted_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);
CREATE INDEX IF NOT EXISTS users_company_id_idx ON public.users(company_id);


-- Products Table
CREATE TABLE IF NOT EXISTS public.products (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku text NOT NULL,
    name text NOT NULL,
    category text,
    barcode text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, sku)
);
CREATE INDEX IF NOT EXISTS products_company_id_idx ON public.products(company_id);


-- Locations Table
CREATE TABLE IF NOT EXISTS public.locations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    address text,
    is_default boolean NOT NULL DEFAULT false,
    deleted_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, name)
);
CREATE INDEX IF NOT EXISTS locations_company_id_idx ON public.locations(company_id);

-- Inventory Table
CREATE TABLE IF NOT EXISTS public.inventory (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    location_id uuid REFERENCES public.locations(id) ON DELETE SET NULL,
    quantity integer NOT NULL DEFAULT 0,
    price integer, -- in cents
    cost integer NOT NULL DEFAULT 0, -- in cents
    landed_cost integer, -- in cents
    reorder_point integer,
    on_order_quantity integer NOT NULL DEFAULT 0,
    last_sold_date timestamptz,
    version integer NOT NULL DEFAULT 1,
    deleted_at timestamptz,
    deleted_by uuid REFERENCES public.users(id),
    source_platform text,
    external_product_id text,
    external_variant_id text,
    external_quantity integer,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, product_id, location_id)
);
CREATE INDEX IF NOT EXISTS inventory_company_id_idx ON public.inventory(company_id);
CREATE INDEX IF NOT EXISTS inventory_product_id_idx ON public.inventory(product_id);
CREATE INDEX IF NOT EXISTS inventory_location_id_idx ON public.inventory(location_id);


-- Vendors Table
CREATE TABLE IF NOT EXISTS public.vendors (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
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
CREATE INDEX IF NOT EXISTS vendors_company_id_idx ON public.vendors(company_id);

-- Supplier Catalogs Table
CREATE TABLE IF NOT EXISTS public.supplier_catalogs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid NOT NULL REFERENCES public.vendors(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    supplier_sku text,
    unit_cost integer NOT NULL, -- in cents
    moq integer DEFAULT 1,
    lead_time_days integer,
    is_active boolean DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(supplier_id, product_id)
);
CREATE INDEX IF NOT EXISTS supplier_catalogs_company_id_idx ON public.supplier_catalogs(company_id);
CREATE INDEX IF NOT EXISTS supplier_catalogs_product_id_idx ON public.supplier_catalogs(product_id);

-- Customers Table
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform text,
    external_id text,
    customer_name text NOT NULL,
    email text,
    status text,
    deleted_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, email)
);
CREATE INDEX IF NOT EXISTS customers_company_id_idx ON public.customers(company_id);

-- Sales Table
CREATE SEQUENCE IF NOT EXISTS sales_sale_number_seq;
CREATE TABLE IF NOT EXISTS public.sales (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sale_number text NOT NULL,
    customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
    customer_name text,
    customer_email text,
    total_amount integer NOT NULL, -- in cents
    tax_amount integer, -- in cents
    payment_method text NOT NULL,
    notes text,
    created_by uuid REFERENCES public.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(company_id, sale_number)
);
CREATE INDEX IF NOT EXISTS sales_company_id_idx ON public.sales(company_id);
CREATE INDEX IF NOT EXISTS sales_customer_id_idx ON public.sales(customer_id);

-- Sale Items Table
CREATE TABLE IF NOT EXISTS public.sale_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    sale_id uuid NOT NULL REFERENCES public.sales(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    quantity integer NOT NULL,
    unit_price integer NOT NULL, -- in cents
    cost_at_time integer, -- in cents
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS sale_items_sale_id_idx ON public.sale_items(sale_id);
CREATE INDEX IF NOT EXISTS sale_items_company_id_idx ON public.sale_items(company_id);
CREATE INDEX IF NOT EXISTS sale_items_product_id_idx ON public.sale_items(product_id);

-- Purchase Orders Table
CREATE SEQUENCE IF NOT EXISTS purchase_orders_po_number_seq;
CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.vendors(id) ON DELETE SET NULL,
    po_number text NOT NULL,
    status public.po_status NOT NULL DEFAULT 'draft',
    order_date date NOT NULL DEFAULT current_date,
    expected_date date,
    total_amount integer NOT NULL DEFAULT 0, -- in cents
    tax_amount integer,
    shipping_cost integer,
    notes text,
    requires_approval boolean NOT NULL DEFAULT false,
    approved_by uuid REFERENCES public.users(id),
    approved_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, po_number)
);
CREATE INDEX IF NOT EXISTS purchase_orders_company_id_idx ON public.purchase_orders(company_id);
CREATE INDEX IF NOT EXISTS purchase_orders_supplier_id_idx ON public.purchase_orders(supplier_id);


-- Purchase Order Items Table
CREATE TABLE IF NOT EXISTS public.purchase_order_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    po_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    quantity_ordered integer NOT NULL,
    quantity_received integer NOT NULL DEFAULT 0,
    unit_cost integer NOT NULL, -- in cents
    tax_rate numeric,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(po_id, product_id)
);
CREATE INDEX IF NOT EXISTS po_items_po_id_idx ON public.purchase_order_items(po_id);
CREATE INDEX IF NOT EXISTS po_items_product_id_idx ON public.purchase_order_items(product_id);


-- Reorder Rules Table
CREATE TABLE IF NOT EXISTS public.reorder_rules (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    rule_type text,
    min_stock integer,
    max_stock integer,
    reorder_quantity integer,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, product_id),
    CHECK (min_stock IS NULL OR max_stock IS NULL OR min_stock <= max_stock),
    CHECK (reorder_quantity IS NULL OR reorder_quantity > 0)
);
CREATE INDEX IF NOT EXISTS reorder_rules_company_id_idx ON public.reorder_rules(company_id);
CREATE INDEX IF NOT EXISTS reorder_rules_product_id_idx ON public.reorder_rules(product_id);

-- Integrations Table
CREATE TABLE IF NOT EXISTS public.integrations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform text NOT NULL,
    shop_domain text,
    shop_name text,
    is_active boolean NOT NULL DEFAULT false,
    sync_status text,
    last_sync_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, platform)
);
CREATE INDEX IF NOT EXISTS integrations_company_id_idx ON public.integrations(company_id);

-- Sync State Table
CREATE TABLE IF NOT EXISTS public.sync_state (
    integration_id uuid PRIMARY KEY REFERENCES public.integrations(id) ON DELETE CASCADE,
    sync_type text NOT NULL,
    last_processed_cursor text,
    last_update timestamptz NOT NULL,
    UNIQUE(integration_id, sync_type)
);

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
CREATE INDEX IF NOT EXISTS sync_logs_integration_id_idx ON public.sync_logs(integration_id);

-- Conversations Table
CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES public.users(id),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    title text NOT NULL,
    is_starred boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    last_accessed_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS conversations_user_id_idx ON public.conversations(user_id);

-- Messages Table
CREATE TABLE IF NOT EXISTS public.messages (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role text NOT NULL,
    content text,
    component text,
    component_props jsonb,
    visualization jsonb,
    confidence numeric,
    assumptions text[],
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS messages_conversation_id_idx ON public.messages(conversation_id);
CREATE INDEX IF NOT EXISTS messages_company_id_idx ON public.messages(company_id);

-- Inventory Ledger Table
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    location_id uuid NOT NULL REFERENCES public.locations(id) ON DELETE RESTRICT,
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid REFERENCES public.users(id),
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid,
    notes text
);
CREATE INDEX IF NOT EXISTS inventory_ledger_product_loc_idx ON public.inventory_ledger(product_id, location_id);
CREATE INDEX IF NOT EXISTS inventory_ledger_company_id_idx ON public.inventory_ledger(company_id);


-- Company Settings Table
CREATE TABLE IF NOT EXISTS public.company_settings (
  company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
  dead_stock_days integer NOT NULL DEFAULT 90,
  overstock_multiplier numeric NOT NULL DEFAULT 3.0,
  high_value_threshold integer NOT NULL DEFAULT 100000, -- in cents
  fast_moving_days integer NOT NULL DEFAULT 30,
  predictive_stock_days integer NOT NULL DEFAULT 7,
  currency text NOT NULL DEFAULT 'USD',
  timezone text NOT NULL DEFAULT 'UTC',
  tax_rate numeric NOT NULL DEFAULT 0.0,
  custom_rules jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz
);

-- Channel Fees Table
CREATE TABLE IF NOT EXISTS public.channel_fees (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  channel_name text NOT NULL,
  percentage_fee numeric NOT NULL DEFAULT 0.0,
  fixed_fee integer NOT NULL DEFAULT 0, -- in cents
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz,
  UNIQUE(company_id, channel_name)
);
CREATE INDEX IF NOT EXISTS channel_fees_company_id_idx ON public.channel_fees(company_id);

-- Export Jobs Table
CREATE TABLE IF NOT EXISTS public.export_jobs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    requested_by_user_id uuid NOT NULL REFERENCES public.users(id),
    status text NOT NULL DEFAULT 'pending',
    download_url text,
    expires_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS export_jobs_company_id_idx ON public.export_jobs(company_id);

-- Audit Log Table
CREATE TABLE IF NOT EXISTS public.audit_log (
    id bigint PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    user_id uuid REFERENCES public.users(id),
    company_id uuid REFERENCES public.companies(id),
    action text NOT NULL,
    details jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- User Feedback Table
CREATE TABLE IF NOT EXISTS public.user_feedback (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    subject_id text NOT NULL,
    subject_type text NOT NULL, -- e.g., 'anomaly_explanation', 'ai_response'
    feedback text NOT NULL, -- e.g., 'helpful', 'unhelpful'
    created_at timestamptz NOT NULL DEFAULT now()
);

-- 4. Helper Functions & Triggers
------------------------------------------------------------
-- Function to get the current user's company ID from the auth token
CREATE OR REPLACE FUNCTION auth.company_id()
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT (current_setting('request.jwt.claims', true)::jsonb -> 'app_metadata' ->> 'company_id')::uuid;
$$;


-- Function to increment version on update
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

-- Trigger to auto-increment version on inventory table
DROP TRIGGER IF EXISTS handle_inventory_update ON public.inventory;
CREATE TRIGGER handle_inventory_update
  BEFORE UPDATE ON public.inventory
  FOR EACH ROW
  EXECUTE PROCEDURE public.increment_version();


-- Function to handle new user signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    company_name_text text;
    new_company_id uuid;
BEGIN
    company_name_text := trim(new.raw_user_meta_data->>'company_name');

    -- Use a default if company name is not provided
    IF company_name_text IS NULL OR company_name_text = '' THEN
      company_name_text := 'My Company';
    END IF;

    -- Create a new company for the user
    INSERT INTO public.companies (company_name)
    VALUES (company_name_text)
    RETURNING id INTO new_company_id;

    -- Insert a corresponding record into public.users
    INSERT INTO public.users (id, company_id, email, role)
    VALUES (new.id, new_company_id, new.email, 'Owner');

    -- Update the user's app_metadata with the new company ID and role
    UPDATE auth.users
    SET app_metadata = jsonb_set(
        jsonb_set(new.raw_user_meta_data::jsonb, '{company_id}', to_jsonb(new_company_id)),
        '{role}',
        '"Owner"'
    )
    WHERE id = new.id;

    RETURN new;
END;
$$;

-- Trigger for new user signup
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE PROCEDURE public.handle_new_user();

-- Trigger to enforce message company_id matches conversation company_id
CREATE OR REPLACE FUNCTION public.enforce_message_company_id()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    conv_company_id uuid;
BEGIN
    SELECT company_id INTO conv_company_id FROM public.conversations WHERE id = NEW.conversation_id;
    IF NEW.company_id IS DISTINCT FROM conv_company_id THEN
        RAISE EXCEPTION 'Message company_id does not match conversation company_id';
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS before_message_insert_update ON public.messages;
CREATE TRIGGER before_message_insert_update
  BEFORE INSERT OR UPDATE ON public.messages
  FOR EACH ROW
  EXECUTE PROCEDURE public.enforce_message_company_id();


-- 5. Business Logic Functions (RPC)
------------------------------------------------------------
-- Function to check if a product has active references in sales or POs
CREATE OR REPLACE FUNCTION public.check_inventory_references(p_company_id uuid, p_product_ids uuid[])
RETURNS TABLE(product_id uuid)
LANGUAGE sql
AS $$
    SELECT product_id FROM public.sale_items WHERE company_id = p_company_id AND product_id = ANY(p_product_ids)
    UNION
    SELECT product_id FROM public.purchase_order_items WHERE po_id IN (SELECT id FROM purchase_orders WHERE company_id = p_company_id) AND product_id = ANY(p_product_ids);
$$;

-- Other RPC functions... (get_alerts, record_sale_transaction, etc.)
-- These are complex and defined below to ensure all tables exist first.

-- 6. Row-Level Security (RLS)
------------------------------------------------------------
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company members can view their own company" ON public.companies FOR SELECT USING (id = auth.company_id());

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view other users in their company" ON public.users FOR SELECT USING (company_id = auth.company_id() AND deleted_at IS NULL);
CREATE POLICY "Owners can manage users in their company" ON public.users FOR ALL USING (company_id = auth.company_id()) WITH CHECK (company_id = auth.company_id());

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access for products" ON public.products FOR ALL USING (company_id = auth.company_id());

ALTER TABLE public.locations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access for locations" ON public.locations FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL);

ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access for inventory" ON public.inventory FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL);

ALTER TABLE public.vendors ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access for vendors" ON public.vendors FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL);

ALTER TABLE public.supplier_catalogs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access for supplier catalogs" ON public.supplier_catalogs FOR ALL USING (company_id = auth.company_id());

ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access for customers" ON public.customers FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL);

ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access for sales" ON public.sales FOR ALL USING (company_id = auth.company_id());

ALTER TABLE public.sale_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access for sale items" ON public.sale_items FOR ALL USING (company_id = auth.company_id());

ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access for purchase orders" ON public.purchase_orders FOR ALL USING (company_id = auth.company_id());

ALTER TABLE public.purchase_order_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access for po items" ON public.purchase_order_items FOR ALL USING (EXISTS (SELECT 1 FROM purchase_orders po WHERE po.id = po_id AND po.company_id = auth.company_id()));

ALTER TABLE public.reorder_rules ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access for reorder rules" ON public.reorder_rules FOR ALL USING (company_id = auth.company_id());

ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access for integrations" ON public.integrations FOR ALL USING (company_id = auth.company_id());

ALTER TABLE public.sync_state ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Integration access for sync state" ON public.sync_state FOR ALL USING (EXISTS (SELECT 1 FROM integrations i WHERE i.id = integration_id AND i.company_id = auth.company_id()));

ALTER TABLE public.sync_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Integration access for sync logs" ON public.sync_logs FOR ALL USING (EXISTS (SELECT 1 FROM integrations i WHERE i.id = integration_id AND i.company_id = auth.company_id()));

ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage their own conversations" ON public.conversations FOR ALL USING (user_id = auth.uid());

ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage messages in their conversations" ON public.messages FOR ALL USING (conversation_id IN (SELECT id FROM public.conversations WHERE user_id = auth.uid()));

ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access to inventory ledger" ON public.inventory_ledger FOR ALL USING (company_id = auth.company_id());

ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company members can access their settings" ON public.company_settings FOR ALL USING (company_id = auth.company_id());

ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access to channel fees" ON public.channel_fees FOR ALL USING (company_id = auth.company_id());

ALTER TABLE public.user_feedback ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage their own feedback" ON public.user_feedback FOR ALL USING (user_id = auth.uid());

ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access for export jobs" ON public.export_jobs FOR ALL USING (company_id = auth.company_id());

-- 7. Advanced RPC Functions (Defined last due to dependencies)
------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_sale_transaction(
    p_company_id uuid,
    p_user_id uuid,
    p_sale_items jsonb,
    p_customer_name text,
    p_customer_email text,
    p_payment_method text,
    p_notes text
)
RETURNS public.sales
LANGUAGE plpgsql
AS $$
DECLARE
    new_sale_id uuid;
    new_customer_id uuid;
    total_amount_cents bigint := 0;
    company_tax_rate numeric;
    tax_amount_numeric numeric;
    item_record RECORD;
    sale_item_temp_table_name text;
BEGIN
    -- Create a temporary table with a unique name
    sale_item_temp_table_name := 'sale_items_temp_' || replace(gen_random_uuid()::text, '-', '');

    EXECUTE format(
        'CREATE TEMP TABLE %I (
            product_id uuid,
            product_name text,
            quantity int,
            unit_price int,
            cost_at_time int,
            max_quantity int,
            min_stock int
        ) ON COMMIT DROP;',
        sale_item_temp_table_name
    );

    -- Populate the temporary table
    EXECUTE format(
        'INSERT INTO %I (product_id, product_name, quantity, unit_price, max_quantity, min_stock)
         SELECT
            (x.item->>''product_id'')::uuid,
            x.item->>''product_name'',
            (x.item->>''quantity'')::int,
            (x.item->>''unit_price'')::int,
            (x.item->>''max_quantity'')::int,
            (x.item->>''min_stock'')::int
         FROM jsonb_array_elements($1) AS x(item)',
        sale_item_temp_table_name
    ) USING p_sale_items;

    -- Update cost_at_time from the main inventory table
    EXECUTE format(
        'UPDATE %I temp
         SET cost_at_time = inv.cost
         FROM public.inventory inv
         WHERE temp.product_id = inv.product_id AND inv.company_id = $1;',
        sale_item_temp_table_name
    ) USING p_company_id;

    -- Check for sufficient stock and business rules
    FOR item_record IN EXECUTE format('SELECT * FROM %I', sale_item_temp_table_name) LOOP
        IF item_record.quantity > item_record.max_quantity THEN
            RAISE EXCEPTION 'Not enough stock for product % (%). Requested: %, Available: %',
                item_record.product_name, item_record.product_id, item_record.quantity, item_record.max_quantity;
        END IF;

        IF item_record.min_stock IS NOT NULL AND (item_record.max_quantity - item_record.quantity) < item_record.min_stock THEN
            -- This is a soft guardrail; we allow the sale but might create an alert later.
            -- For a hard guardrail, use RAISE EXCEPTION here.
        END IF;
    END LOOP;

    -- Calculate total amount
    EXECUTE format('SELECT SUM(quantity * unit_price) FROM %I', sale_item_temp_table_name)
    INTO total_amount_cents;
    total_amount_cents := COALESCE(total_amount_cents, 0);

    -- Get company tax rate
    SELECT tax_rate INTO company_tax_rate FROM public.company_settings WHERE company_id = p_company_id;
    company_tax_rate := COALESCE(company_tax_rate, 0);
    tax_amount_numeric := total_amount_cents * company_tax_rate;

    -- Handle customer
    IF p_customer_email IS NOT NULL AND p_customer_email <> '' THEN
        INSERT INTO public.customers (company_id, customer_name, email)
        VALUES (p_company_id, COALESCE(p_customer_name, 'Valued Customer'), p_customer_email)
        ON CONFLICT (company_id, email) DO UPDATE SET customer_name = EXCLUDED.customer_name
        RETURNING id INTO new_customer_id;
    END IF;

    -- Create the sale record
    INSERT INTO public.sales (company_id, sale_number, customer_id, customer_name, customer_email, total_amount, tax_amount, payment_method, notes, created_by)
    VALUES (
        p_company_id,
        'SALE-' || TO_CHAR(nextval('sales_sale_number_seq'), 'FM000000'),
        new_customer_id,
        p_customer_name,
        p_customer_email,
        total_amount_cents,
        tax_amount_numeric::bigint,
        p_payment_method,
        p_notes,
        p_user_id
    ) RETURNING id INTO new_sale_id;

    -- Insert sale items and update inventory
    FOR item_record IN EXECUTE format('SELECT * FROM %I', sale_item_temp_table_name) LOOP
        -- Insert into sale_items
        INSERT INTO public.sale_items (sale_id, company_id, product_id, quantity, unit_price, cost_at_time)
        VALUES (new_sale_id, p_company_id, item_record.product_id, item_record.quantity, item_record.unit_price, item_record.cost_at_time);

        -- Decrement inventory and add to ledger
        WITH updated_inv AS (
            UPDATE public.inventory
            SET
                quantity = quantity - item_record.quantity,
                last_sold_date = now()
            WHERE product_id = item_record.product_id
              AND company_id = p_company_id
              AND location_id IS NOT NULL -- Placeholder for location logic
            RETURNING id, quantity, location_id
        )
        INSERT INTO public.inventory_ledger (company_id, product_id, location_id, created_by, change_type, quantity_change, new_quantity, related_id, notes)
        SELECT p_company_id, item_record.product_id, u.location_id, p_user_id, 'sale', -item_record.quantity, u.quantity, new_sale_id, 'Sale #' || (SELECT sale_number FROM sales WHERE id = new_sale_id)
        FROM updated_inv u;
    END LOOP;

    -- Refresh materialized views
    PERFORM public.refresh_materialized_views(p_company_id, ARRAY['company_dashboard_metrics', 'customer_analytics_metrics']);

    RETURN (SELECT * FROM public.sales WHERE id = new_sale_id);
END;
$$;


CREATE OR REPLACE FUNCTION public.get_alerts(
    p_company_id uuid,
    p_dead_stock_days integer,
    p_fast_moving_days integer,
    p_predictive_stock_days integer
)
RETURNS TABLE (
    product_id uuid,
    product_name text,
    sku text,
    type text,
    current_stock integer,
    reorder_point integer,
    last_sold_date timestamptz,
    value integer,
    days_of_stock_remaining numeric
)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Low Stock Alerts
    RETURN QUERY
    SELECT
        p.id AS product_id,
        p.name AS product_name,
        p.sku,
        'low_stock'::text AS type,
        i.quantity AS current_stock,
        i.reorder_point,
        NULL::timestamptz,
        NULL::integer,
        NULL::numeric
    FROM public.inventory i
    JOIN public.products p ON i.product_id = p.id
    WHERE i.company_id = p_company_id AND i.reorder_point IS NOT NULL AND i.quantity < i.reorder_point AND i.deleted_at IS NULL;

    -- Dead Stock Alerts
    RETURN QUERY
    SELECT
        p.id AS product_id,
        p.name AS product_name,
        p.sku,
        'dead_stock'::text AS type,
        i.quantity AS current_stock,
        NULL::integer,
        i.last_sold_date,
        (i.quantity * i.cost)::integer AS value,
        NULL::numeric
    FROM public.inventory i
    JOIN public.products p ON i.product_id = p.id
    WHERE i.company_id = p_company_id
      AND i.quantity > 0
      AND i.last_sold_date IS NOT NULL
      AND i.last_sold_date < (now() - (p_dead_stock_days || ' days')::interval)
      AND i.deleted_at IS NULL;

    -- Predictive Stockout Alerts
    RETURN QUERY
    WITH sales_velocity AS (
        SELECT
            si.product_id,
            SUM(si.quantity)::numeric / NULLIF(p_fast_moving_days, 0) AS daily_sales
        FROM public.sale_items si
        JOIN public.sales s ON si.sale_id = s.id
        WHERE s.company_id = p_company_id AND s.created_at >= (now() - (p_fast_moving_days || ' days')::interval)
        GROUP BY si.product_id
    )
    SELECT
        p.id AS product_id,
        p.name AS product_name,
        p.sku,
        'predictive'::text AS type,
        i.quantity AS current_stock,
        NULL::integer,
        NULL::timestamptz,
        NULL::integer,
        i.quantity / sv.daily_sales AS days_of_stock_remaining
    FROM public.inventory i
    JOIN public.products p ON i.product_id = p.id
    JOIN sales_velocity sv ON i.product_id = sv.product_id
    WHERE i.company_id = p_company_id
      AND sv.daily_sales > 0
      AND (i.quantity / sv.daily_sales) <= p_predictive_stock_days
      AND i.deleted_at IS NULL;
END;
$$;


-- 8. Views & Materialized Views
------------------------------------------------------------
DROP MATERIALIZED VIEW IF EXISTS public.company_dashboard_metrics;
CREATE MATERIALIZED VIEW public.company_dashboard_metrics AS
SELECT
    i.company_id,
    SUM(i.quantity * i.cost) as inventory_value,
    COUNT(DISTINCT p.id) as total_skus,
    SUM(CASE WHEN i.reorder_point IS NOT NULL AND i.quantity < i.reorder_point THEN 1 ELSE 0 END) as low_stock_count
FROM public.inventory i
JOIN public.products p ON i.product_id = p.id
WHERE i.deleted_at IS NULL
GROUP BY i.company_id;

CREATE UNIQUE INDEX IF NOT EXISTS company_dashboard_metrics_company_id_idx ON public.company_dashboard_metrics(company_id);
ALTER TABLE public.company_dashboard_metrics ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company can access their own dashboard metrics" ON public.company_dashboard_metrics FOR SELECT USING (company_id = auth.company_id());

DROP MATERIALIZED VIEW IF EXISTS public.customer_analytics_metrics;
CREATE MATERIALIZED VIEW public.customer_analytics_metrics AS
SELECT
    s.company_id,
    c.id as customer_id,
    SUM(s.total_amount) as lifetime_value,
    COUNT(s.id) as total_orders
FROM public.sales s
JOIN public.customers c ON s.customer_id = c.id
WHERE c.deleted_at IS NULL
GROUP BY s.company_id, c.id;

CREATE UNIQUE INDEX IF NOT EXISTS customer_analytics_metrics_company_customer_id_idx ON public.customer_analytics_metrics(company_id, customer_id);
ALTER TABLE public.customer_analytics_metrics ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company can access their own customer analytics" ON public.customer_analytics_metrics FOR SELECT USING (company_id = auth.company_id());


-- 9. Final Grants & Privileges
------------------------------------------------------------
GRANT USAGE ON SCHEMA public TO authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO service_role;

GRANT USAGE ON TYPE public.user_role TO authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO authenticated;

-- Grant select on all tables/views to authenticated users (RLS will handle access)
GRANT SELECT ON ALL TABLES IN SCHEMA public TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO authenticated;

-- Allow authenticated users to insert/update/delete on specific tables
GRANT INSERT, UPDATE, DELETE ON
    public.companies, public.users, public.products, public.inventory, public.vendors,
    public.supplier_catalogs, public.customers, public.sales, public.sale_items,
    public.purchase_orders, public.purchase_order_items, public.reorder_rules,
    public.integrations, public.sync_state, public.sync_logs, public.conversations,
    public.messages, public.inventory_ledger, public.company_settings, public.channel_fees,
    public.export_jobs, public.user_feedback
TO authenticated;

ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT INSERT, UPDATE, DELETE ON TABLES TO authenticated;

-- Reset and grant sequence usage
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO authenticated;

-- RLS must be enforced for the table owner
ALTER TABLE public.companies FORCE ROW LEVEL SECURITY;
ALTER TABLE public.users FORCE ROW LEVEL SECURITY;
-- ... repeat for all tables with RLS ...
ALTER TABLE public.products FORCE ROW LEVEL SECURITY;
ALTER TABLE public.locations FORCE ROW LEVEL SECURITY;
ALTER TABLE public.inventory FORCE ROW LEVEL SECURITY;
ALTER TABLE public.vendors FORCE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_catalogs FORCE ROW LEVEL SECURITY;
ALTER TABLE public.customers FORCE ROW LEVEL SECURITY;
ALTER TABLE public.sales FORCE ROW LEVEL SECURITY;
ALTER TABLE public.sale_items FORCE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders FORCE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_items FORCE ROW LEVEL SECURITY;
ALTER TABLE public.reorder_rules FORCE ROW LEVEL SECURITY;
ALTER TABLE public.integrations FORCE ROW LEVEL SECURITY;
ALTER TABLE public.sync_state FORCE ROW LEVEL SECURITY;
ALTER TABLE public.sync_logs FORCE ROW LEVEL SECURITY;
ALTER TABLE public.conversations FORCE ROW LEVEL SECURITY;
ALTER TABLE public.messages FORCE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger FORCE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings FORCE ROW LEVEL SECURITY;
ALTER TABLE public.channel_fees FORCE ROW LEVEL SECURITY;
ALTER TABLE public.export_jobs FORCE ROW LEVEL SECURITY;
ALTER TABLE public.user_feedback FORCE ROW LEVEL SECURITY;
ALTER TABLE public.company_dashboard_metrics FORCE ROW LEVEL SECURITY;
ALTER TABLE public.customer_analytics_metrics FORCE ROW LEVEL SECURITY;
