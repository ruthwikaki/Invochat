-- InvoChat Database Schema
-- Version: 4.0
-- Description: A comprehensive, secure, and performant schema for the InvoChat application.

-- 1. Extensions
--------------------------------------------------
-- Use pgcrypto for UUID generation, as it's a standard extension.
CREATE EXTENSION IF NOT EXISTS "pgcrypto";


-- 2. Custom Types
--------------------------------------------------
-- Define a custom type for user roles to ensure data integrity.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE public.user_role AS ENUM ('Owner', 'Admin', 'Member');
    END IF;
END$$;


-- 3. Tables
--------------------------------------------------

CREATE TABLE IF NOT EXISTS public.companies (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.companies IS 'Stores company-level information.';

CREATE TABLE IF NOT EXISTS public.users (
    id uuid NOT NULL PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid REFERENCES public.companies(id) ON DELETE SET NULL,
    email text,
    role public.user_role DEFAULT 'Member',
    deleted_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);
COMMENT ON TABLE public.users IS 'Stores user profiles and their association with companies.';

CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    overstock_multiplier numeric NOT NULL DEFAULT 3,
    high_value_threshold integer NOT NULL DEFAULT 100000,
    fast_moving_days integer NOT NULL DEFAULT 30,
    predictive_stock_days integer NOT NULL DEFAULT 7,
    currency text DEFAULT 'USD',
    timezone text DEFAULT 'UTC',
    tax_rate numeric DEFAULT 0,
    custom_rules jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);
COMMENT ON TABLE public.company_settings IS 'Stores business logic settings for each company.';

CREATE TABLE IF NOT EXISTS public.products (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku text NOT NULL,
    name text NOT NULL,
    category text,
    barcode text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    CONSTRAINT products_company_id_sku_key UNIQUE (company_id, sku)
);
COMMENT ON TABLE public.products IS 'Core product catalog information.';

CREATE TABLE IF NOT EXISTS public.locations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    address text,
    is_default boolean DEFAULT false,
    deleted_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    CONSTRAINT locations_company_id_name_key UNIQUE (company_id, name)
);
COMMENT ON TABLE public.locations IS 'Represents physical locations where inventory is stored.';

CREATE TABLE IF NOT EXISTS public.inventory (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    location_id uuid REFERENCES public.locations(id) ON DELETE SET NULL,
    quantity integer NOT NULL DEFAULT 0,
    cost integer,
    price integer,
    landed_cost integer,
    on_order_quantity integer NOT NULL DEFAULT 0,
    last_sold_date date,
    version integer NOT NULL DEFAULT 1,
    deleted_at timestamptz,
    deleted_by uuid REFERENCES public.users(id),
    source_platform text,
    external_product_id text,
    external_variant_id text,
    external_quantity integer,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    CONSTRAINT inventory_company_product_location_unique UNIQUE (company_id, product_id, location_id)
);
COMMENT ON TABLE public.inventory IS 'Tracks stock levels for products at different locations.';

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
    CONSTRAINT vendors_company_id_vendor_name_key UNIQUE (company_id, vendor_name)
);
COMMENT ON TABLE public.vendors IS 'Stores information about suppliers.';

CREATE TABLE IF NOT EXISTS public.supplier_catalogs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    supplier_id uuid NOT NULL REFERENCES public.vendors(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_sku text,
    unit_cost integer,
    moq integer,
    lead_time_days integer,
    is_active boolean DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    CONSTRAINT supplier_catalogs_supplier_id_product_id_key UNIQUE (supplier_id, product_id)
);
COMMENT ON TABLE public.supplier_catalogs IS 'Maps products to suppliers with specific purchasing details.';

CREATE TABLE IF NOT EXISTS public.reorder_rules (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    location_id uuid REFERENCES public.locations(id) ON DELETE CASCADE,
    rule_type text DEFAULT 'manual',
    min_stock integer,
    max_stock integer,
    reorder_quantity integer,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    CONSTRAINT reorder_rules_check CHECK (min_stock <= max_stock),
    CONSTRAINT reorder_rules_company_product_location_key UNIQUE (company_id, product_id, location_id)
);
COMMENT ON TABLE public.reorder_rules IS 'Defines reordering thresholds for products.';

CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.vendors(id) ON DELETE SET NULL,
    po_number text NOT NULL,
    status public.purchase_order_status DEFAULT 'draft',
    order_date date NOT NULL,
    expected_date date,
    total_amount integer,
    tax_amount integer,
    shipping_cost integer,
    notes text,
    requires_approval boolean NOT NULL DEFAULT false,
    approved_by uuid,
    approved_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);
COMMENT ON TABLE public.purchase_orders IS 'Tracks purchase orders sent to suppliers.';
CREATE SEQUENCE IF NOT EXISTS purchase_orders_po_number_seq;
ALTER TABLE public.purchase_orders
  ALTER COLUMN po_number
  SET DEFAULT 'PO-' || TO_CHAR(nextval('purchase_orders_po_number_seq'), 'FM000000');


CREATE TABLE IF NOT EXISTS public.purchase_order_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    po_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    quantity_ordered integer NOT NULL,
    quantity_received integer DEFAULT 0,
    unit_cost integer,
    tax_rate numeric
);
COMMENT ON TABLE public.purchase_order_items IS 'Line items for each purchase order.';

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
    updated_at timestamptz
);
COMMENT ON TABLE public.customers IS 'Stores customer information.';

CREATE TABLE IF NOT EXISTS public.sales (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sale_number text NOT NULL,
    customer_id uuid REFERENCES public.customers(id),
    total_amount integer,
    tax_amount integer,
    payment_method text,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid REFERENCES public.users(id),
    CONSTRAINT sales_company_id_sale_number_key UNIQUE (company_id, sale_number)
);
COMMENT ON TABLE public.sales IS 'Tracks individual sales transactions.';
CREATE SEQUENCE IF NOT EXISTS sales_sale_number_seq;

CREATE TABLE IF NOT EXISTS public.sale_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    sale_id uuid NOT NULL REFERENCES public.sales(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    location_id uuid REFERENCES public.locations(id) ON DELETE SET NULL,
    quantity integer NOT NULL,
    unit_price integer,
    cost_at_time integer
);
COMMENT ON TABLE public.sale_items IS 'Line items for each sale.';

CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    is_starred boolean DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    last_accessed_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.conversations IS 'Stores AI chat conversation sessions.';

CREATE TABLE IF NOT EXISTS public.messages (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role public.message_role NOT NULL,
    content text,
    visualization jsonb,
    confidence real,
    assumptions text[],
    component text,
    component_props jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    is_error boolean DEFAULT false
);
COMMENT ON TABLE public.messages IS 'Stores individual messages within a conversation.';

CREATE TABLE IF NOT EXISTS public.integrations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform text NOT NULL,
    shop_domain text,
    shop_name text,
    is_active boolean DEFAULT true,
    last_sync_at timestamptz,
    sync_status text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    CONSTRAINT integrations_company_id_platform_key UNIQUE (company_id, platform)
);
COMMENT ON TABLE public.integrations IS 'Stores third-party integration settings.';

CREATE TABLE IF NOT EXISTS public.sync_state (
    integration_id uuid PRIMARY KEY REFERENCES public.integrations(id) ON DELETE CASCADE,
    sync_type text NOT NULL,
    last_processed_cursor text,
    last_update timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT sync_state_pkey PRIMARY KEY (integration_id, sync_type)
);
COMMENT ON TABLE public.sync_state IS 'Tracks the state of ongoing data syncs to allow for resumption.';

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
COMMENT ON TABLE public.sync_logs IS 'Logs the history and outcomes of data synchronization jobs.';

CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    product_id uuid NOT NULL REFERENCES public.products(id),
    location_id uuid REFERENCES public.locations(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid REFERENCES public.users(id),
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid,
    notes text
);
COMMENT ON TABLE public.inventory_ledger IS 'An audit trail of all inventory movements.';

CREATE TABLE IF NOT EXISTS public.export_jobs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    requested_by_user_id uuid NOT NULL REFERENCES public.users(id),
    status text NOT NULL,
    download_url text,
    expires_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.export_jobs IS 'Tracks data export job requests.';

CREATE TABLE IF NOT EXISTS public.channel_fees (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    channel_name text NOT NULL,
    percentage_fee numeric NOT NULL,
    fixed_fee integer NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    CONSTRAINT channel_fees_company_id_channel_name_key UNIQUE (company_id, channel_name)
);
COMMENT ON TABLE public.channel_fees IS 'Stores fees for different sales channels for net margin calculations.';

CREATE TABLE IF NOT EXISTS public.audit_log (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid REFERENCES auth.users(id),
    company_id uuid REFERENCES public.companies(id),
    action text NOT NULL,
    details jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.audit_log IS 'Records important actions taken by users or the system.';

CREATE TABLE IF NOT EXISTS public.user_feedback (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES public.users(id),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    subject_id text NOT NULL,
    subject_type text NOT NULL,
    feedback text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.user_feedback IS 'Stores user feedback on AI-generated content.';


-- 4. Materialized Views
--------------------------------------------------
-- A materialized view to pre-calculate expensive dashboard metrics.
CREATE MATERIALIZED VIEW IF NOT EXISTS public.company_dashboard_metrics AS
SELECT
    c.id AS company_id,
    COALESCE(SUM(i.quantity * i.cost), 0) AS inventory_value,
    COUNT(DISTINCT i.product_id) AS total_skus,
    COUNT(DISTINCT CASE WHEN i.quantity < COALESCE(rr.min_stock, 0) THEN i.product_id END) AS low_stock_count
FROM
    public.companies c
LEFT JOIN
    public.inventory i ON c.id = i.company_id AND i.deleted_at IS NULL
LEFT JOIN
    public.reorder_rules rr ON i.product_id = rr.product_id AND i.location_id = rr.location_id
GROUP BY
    c.id;

-- A materialized view for customer analytics.
CREATE MATERIALIZED VIEW IF NOT EXISTS public.customer_analytics_metrics AS
SELECT
    c.id AS company_id,
    COUNT(DISTINCT cust.id) AS total_customers,
    SUM(CASE WHEN cust.created_at >= now() - interval '30 days' THEN 1 ELSE 0 END) AS new_customers_last_30_days,
    COALESCE(SUM(s.total_amount), 0) AS total_revenue,
    CASE WHEN COUNT(DISTINCT cust.id) > 0 THEN AVG(s.total_amount) ELSE 0 END AS average_lifetime_value,
    CASE WHEN COUNT(DISTINCT s.customer_id) > 0
         THEN (COUNT(DISTINCT CASE WHEN (SELECT COUNT(*) FROM public.sales s2 WHERE s2.customer_id = s.customer_id) > 1 THEN s.customer_id END)::numeric / COUNT(DISTINCT s.customer_id))
         ELSE 0
    END AS repeat_customer_rate
FROM
    public.companies c
LEFT JOIN
    public.customers cust ON c.id = cust.company_id AND cust.deleted_at IS NULL
LEFT JOIN
    public.sales s ON cust.id = s.customer_id
GROUP BY
    c.id;


-- 5. Indexes
--------------------------------------------------
-- Indexes for Foreign Keys
CREATE INDEX IF NOT EXISTS users_company_id_idx ON public.users(company_id);
CREATE INDEX IF NOT EXISTS products_company_id_idx ON public.products(company_id);
CREATE INDEX IF NOT EXISTS inventory_company_id_idx ON public.inventory(company_id);
CREATE INDEX IF NOT EXISTS inventory_product_id_idx ON public.inventory(product_id);
CREATE INDEX IF NOT EXISTS inventory_location_id_idx ON public.inventory(location_id);
CREATE INDEX IF NOT EXISTS vendors_company_id_idx ON public.vendors(company_id);
CREATE INDEX IF NOT EXISTS supplier_catalogs_company_id_idx ON public.supplier_catalogs(company_id);
CREATE INDEX IF NOT EXISTS supplier_catalogs_product_id_idx ON public.supplier_catalogs(product_id);
CREATE INDEX IF NOT EXISTS reorder_rules_company_id_idx ON public.reorder_rules(company_id);
CREATE INDEX IF NOT EXISTS reorder_rules_product_id_idx ON public.reorder_rules(product_id);
CREATE INDEX IF NOT EXISTS purchase_orders_company_id_idx ON public.purchase_orders(company_id);
CREATE INDEX IF NOT EXISTS purchase_orders_supplier_id_idx ON public.purchase_orders(supplier_id);
CREATE INDEX IF NOT EXISTS po_items_company_id_idx ON public.purchase_order_items(company_id);
CREATE INDEX IF NOT EXISTS po_items_po_id_idx ON public.purchase_order_items(po_id);
CREATE INDEX IF NOT EXISTS po_items_product_id_idx ON public.purchase_order_items(product_id);
CREATE INDEX IF NOT EXISTS customers_company_id_idx ON public.customers(company_id);
CREATE INDEX IF NOT EXISTS sales_company_id_idx ON public.sales(company_id);
CREATE INDEX IF NOT EXISTS sales_customer_id_idx ON public.sales(customer_id);
CREATE INDEX IF NOT EXISTS sale_items_company_id_idx ON public.sale_items(company_id);
CREATE INDEX IF NOT EXISTS sale_items_sale_id_idx ON public.sale_items(sale_id);
CREATE INDEX IF NOT EXISTS sale_items_product_id_idx ON public.sale_items(product_id);
CREATE INDEX IF NOT EXISTS conversations_user_id_idx ON public.conversations(user_id);
CREATE INDEX IF NOT EXISTS conversations_company_id_idx ON public.conversations(company_id);
CREATE INDEX IF NOT EXISTS messages_conversation_id_idx ON public.messages(conversation_id);
CREATE INDEX IF NOT EXISTS messages_company_id_idx ON public.messages(company_id);
CREATE INDEX IF NOT EXISTS integrations_company_id_idx ON public.integrations(company_id);
CREATE INDEX IF NOT EXISTS sync_logs_integration_id_idx ON public.sync_logs(integration_id);
CREATE INDEX IF NOT EXISTS inventory_ledger_company_id_idx ON public.inventory_ledger(company_id);
CREATE INDEX IF NOT EXISTS inventory_ledger_product_location_idx ON public.inventory_ledger(product_id, location_id);
CREATE INDEX IF NOT EXISTS export_jobs_company_id_idx ON public.export_jobs(company_id);
CREATE INDEX IF NOT EXISTS channel_fees_company_id_idx ON public.channel_fees(company_id);
CREATE INDEX IF NOT EXISTS audit_log_company_user_action_idx ON public.audit_log(company_id, user_id, action);
CREATE INDEX IF NOT EXISTS user_feedback_company_user_idx ON public.user_feedback(company_id, user_id);

-- Indexes for Materialized Views
CREATE UNIQUE INDEX IF NOT EXISTS company_dashboard_metrics_company_id_idx ON public.company_dashboard_metrics (company_id);
CREATE UNIQUE INDEX IF NOT EXISTS customer_analytics_metrics_company_id_idx ON public.customer_analytics_metrics (company_id);


-- 6. Functions & Triggers
--------------------------------------------------

-- Helper function to get the company_id from the session user's claims.
CREATE OR REPLACE FUNCTION auth.company_id()
RETURNS uuid
LANGUAGE sql STABLE
AS $$
  SELECT (auth.jwt() -> 'app_metadata' ->> 'company_id')::uuid
$$;

-- Function to handle new user sign-up.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  company_name_text text;
  new_company_id uuid;
BEGIN
  -- Extract company name from metadata; revert to exception if empty
  company_name_text := trim(new.raw_user_meta_data->>'company_name');
  IF company_name_text IS NULL OR company_name_text = '' THEN
    RAISE EXCEPTION 'Company name cannot be empty during signup.';
  END IF;

  -- Create a new company for the user
  INSERT INTO public.companies (company_name)
  VALUES (company_name_text)
  RETURNING id INTO new_company_id;

  -- Insert into our public users table
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (new.id, new_company_id, new.email, 'Owner');

  -- Update the user's app_metadata in auth.users
  UPDATE auth.users
  SET app_metadata = jsonb_set(
    COALESCE(app_metadata, '{}'::jsonb),
    '{company_id}',
    to_jsonb(new_company_id)
  ) || jsonb_set(
    COALESCE(app_metadata, '{}'::jsonb),
    '{role}',
    to_jsonb('Owner'::text)
  )
  WHERE id = new.id;
  
  RETURN new;
END;
$$;

-- Trigger to call the handle_new_user function on new user creation in auth.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE PROCEDURE public.handle_new_user();

-- Function and trigger to bump version and updated_at on inventory updates.
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
  WHEN (OLD.* IS DISTINCT FROM NEW.*)
  EXECUTE PROCEDURE public.increment_version();
  
-- Generic function to bump the updated_at timestamp on any table.
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

DROP TRIGGER IF EXISTS trigger_locations_updated_at ON public.locations;
CREATE TRIGGER trigger_locations_updated_at BEFORE UPDATE ON public.locations FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();

DROP TRIGGER IF EXISTS trigger_vendors_updated_at ON public.vendors;
CREATE TRIGGER trigger_vendors_updated_at BEFORE UPDATE ON public.vendors FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();

DROP TRIGGER IF EXISTS trigger_purchase_orders_updated_at ON public.purchase_orders;
CREATE TRIGGER trigger_purchase_orders_updated_at BEFORE UPDATE ON public.purchase_orders FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();

DROP TRIGGER IF EXISTS trigger_channel_fees_updated_at ON public.channel_fees;
CREATE TRIGGER trigger_channel_fees_updated_at BEFORE UPDATE ON public.channel_fees FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();

-- Trigger to ensure message.company_id matches conversation.company_id
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

DROP TRIGGER IF EXISTS trigger_message_company_id_consistency ON public.messages;
CREATE TRIGGER trigger_message_company_id_consistency
  BEFORE INSERT OR UPDATE ON public.messages
  FOR EACH ROW
  EXECUTE PROCEDURE public.enforce_message_company_id();


-- 7. Row Level Security (RLS)
--------------------------------------------------
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access for members" ON public.companies FOR ALL USING (id = auth.company_id());

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only see users in their own company" ON public.users FOR SELECT USING (company_id = auth.company_id() AND deleted_at IS NULL);
CREATE POLICY "Users can update their own profile" ON public.users FOR UPDATE USING (id = auth.uid());

ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access to settings" ON public.company_settings FOR ALL USING (company_id = auth.company_id());

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access to products" ON public.products FOR ALL USING (company_id = auth.company_id());

ALTER TABLE public.locations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access to locations" ON public.locations FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL);

ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access to inventory" ON public.inventory FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL);

ALTER TABLE public.vendors ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access to vendors" ON public.vendors FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL);

ALTER TABLE public.supplier_catalogs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access to supplier catalogs" ON public.supplier_catalogs FOR ALL USING (company_id = auth.company_id());

ALTER TABLE public.reorder_rules ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access to reorder rules" ON public.reorder_rules FOR ALL USING (company_id = auth.company_id());

ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access to purchase orders" ON public.purchase_orders FOR ALL USING (company_id = auth.company_id());

ALTER TABLE public.purchase_order_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access to PO items" ON public.purchase_order_items FOR ALL USING (company_id = auth.company_id());

ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access to customers" ON public.customers FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL);

ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access to sales" ON public.sales FOR ALL USING (company_id = auth.company_id());

ALTER TABLE public.sale_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access to sale items" ON public.sale_items FOR ALL USING (company_id = auth.company_id());

ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage their own conversations" ON public.conversations FOR ALL USING (user_id = auth.uid());

ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage messages in their conversations" ON public.messages FOR ALL USING (conversation_id IN (SELECT id FROM public.conversations WHERE user_id = auth.uid()));

ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access to integrations" ON public.integrations FOR ALL USING (company_id = auth.company_id());

ALTER TABLE public.sync_state ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access to sync state" ON public.sync_state FOR ALL USING (integration_id IN (SELECT id FROM public.integrations WHERE company_id = auth.company_id()));

ALTER TABLE public.sync_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access to sync logs" ON public.sync_logs FOR ALL USING (integration_id IN (SELECT id FROM public.integrations WHERE company_id = auth.company_id()));

ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access to inventory ledger" ON public.inventory_ledger FOR ALL USING (company_id = auth.company_id());

ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access to export jobs" ON public.export_jobs FOR ALL USING (company_id = auth.company_id());

ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access to channel fees" ON public.channel_fees FOR ALL USING (company_id = auth.company_id());

ALTER TABLE public.user_feedback ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage their own feedback" ON public.user_feedback FOR ALL USING (user_id = auth.uid());

ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access to audit log" ON public.audit_log FOR ALL USING (company_id = auth.company_id());

-- RLS for Materialized Views
ALTER TABLE public.company_dashboard_metrics ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access to dashboard metrics" ON public.company_dashboard_metrics FOR SELECT USING (company_id = auth.company_id());

ALTER TABLE public.customer_analytics_metrics ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company access to customer analytics" ON public.customer_analytics_metrics FOR SELECT USING (company_id = auth.company_id());


-- 8. Stored Procedures (RPC)
--------------------------------------------------

CREATE OR REPLACE FUNCTION public.check_inventory_references(p_company_id uuid, p_product_ids uuid[])
RETURNS TABLE(product_id uuid)
LANGUAGE sql
AS $$
  SELECT product_id FROM public.sale_items WHERE company_id = p_company_id AND product_id = ANY(p_product_ids)
  UNION
  SELECT product_id FROM public.purchase_order_items WHERE company_id = p_company_id AND product_id = ANY(p_product_ids);
$$;

CREATE OR REPLACE FUNCTION public.record_sale_transaction(
    p_company_id uuid,
    p_user_id uuid,
    p_sale_items jsonb,
    p_customer_name text,
    p_customer_email text,
    p_payment_method text,
    p_notes text,
    p_external_id text DEFAULT NULL
)
RETURNS public.sales
LANGUAGE plpgsql
AS $$
DECLARE
    new_sale_id uuid;
    new_customer_id uuid;
    total_amount_cents bigint;
    tax_amount bigint;
    company_tax_rate numeric;
    item_record record;
    inv_record record;
    sale_item_temp_table_name text;
BEGIN
    -- Use a temporary table for the sale items to avoid multiple JSON parses
    sale_item_temp_table_name := 'sale_items_temp_' || replace(gen_random_uuid()::text, '-', '');
    EXECUTE format(
      'CREATE TEMP TABLE %I (
        product_id uuid,
        product_name text,
        quantity int,
        unit_price int,
        location_id uuid,
        cost_at_time int
      ) ON COMMIT DROP;',
      sale_item_temp_table_name
    );

    EXECUTE format(
      'INSERT INTO %I (product_id, product_name, quantity, unit_price, location_id)
       SELECT (p_sale_items->>''product_id'')::uuid, p_sale_items->>''product_name'', (p_sale_items->>''quantity'')::int, (p_sale_items->>''unit_price'')::int, (p_sale_items->>''location_id'')::uuid
       FROM jsonb_to_recordset($1) AS p_sale_items(product_id text, product_name text, quantity text, unit_price text, location_id text)',
       sale_item_temp_table_name
    ) USING p_sale_items;

    -- Upsert customer
    IF p_customer_email IS NOT NULL THEN
        INSERT INTO public.customers (company_id, customer_name, email)
        VALUES (p_company_id, p_customer_name, p_customer_email)
        ON CONFLICT (company_id, email) DO UPDATE SET customer_name = EXCLUDED.customer_name
        RETURNING id INTO new_customer_id;
    END IF;
    
    -- Decrement inventory and update cost_at_time in temp table
    FOR item_record IN EXECUTE format('SELECT * FROM %I', sale_item_temp_table_name) LOOP
        SELECT * INTO inv_record FROM public.inventory 
        WHERE product_id = item_record.product_id AND company_id = p_company_id AND location_id = item_record.location_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Product with ID % not found at location %', item_record.product_id, item_record.location_id;
        END IF;
        IF inv_record.quantity < item_record.quantity THEN
            RAISE EXCEPTION 'Not enough stock for product ID %. Available: %, Required: %', item_record.product_id, inv_record.quantity, item_record.quantity;
        END IF;

        UPDATE public.inventory
        SET quantity = quantity - item_record.quantity, last_sold_date = CURRENT_DATE
        WHERE id = inv_record.id;
        
        EXECUTE format(
            'UPDATE %I SET cost_at_time = $1 WHERE product_id = $2 AND location_id = $3',
            sale_item_temp_table_name
        ) USING inv_record.cost, item_record.product_id, item_record.location_id;
    END LOOP;

    -- Calculate totals
    EXECUTE format('SELECT SUM(quantity * unit_price) FROM %I', sale_item_temp_table_name)
    INTO total_amount_cents;

    SELECT cs.tax_rate INTO company_tax_rate FROM public.company_settings cs WHERE cs.company_id = p_company_id;
    tax_amount := total_amount_cents * company_tax_rate;

    -- Create sale record
    INSERT INTO public.sales (company_id, customer_id, sale_number, total_amount, tax_amount, payment_method, notes, created_by)
    VALUES (p_company_id, new_customer_id, 'SALE-' || TO_CHAR(nextval('sales_sale_number_seq'), 'FM000000'), total_amount_cents, tax_amount, p_payment_method, p_notes, p_user_id)
    RETURNING id INTO new_sale_id;

    -- Insert sale items and ledger entries
    FOR item_record IN EXECUTE format('SELECT * FROM %I', sale_item_temp_table_name) LOOP
        INSERT INTO public.sale_items (sale_id, company_id, product_id, location_id, quantity, unit_price, cost_at_time)
        VALUES (new_sale_id, p_company_id, item_record.product_id, item_record.location_id, item_record.quantity, item_record.unit_price, item_record.cost_at_time);

        INSERT INTO public.inventory_ledger (company_id, product_id, location_id, created_by, change_type, quantity_change, new_quantity, related_id, notes)
        VALUES (p_company_id, item_record.product_id, item_record.location_id, p_user_id, 'sale', -item_record.quantity, (SELECT quantity FROM public.inventory WHERE product_id = item_record.product_id AND location_id = item_record.location_id), new_sale_id, 'Sale #' || (SELECT sale_number FROM public.sales WHERE id = new_sale_id));
    END LOOP;

    RETURN (SELECT * FROM public.sales WHERE id = new_sale_id);
END;
$$;


-- 9. Grants & Default Privileges
--------------------------------------------------
-- Grant usage on schemas
GRANT USAGE ON SCHEMA public TO authenticated, service_role;
GRANT USAGE ON SCHEMA auth TO authenticated, service_role;

-- Grant usage on custom types
GRANT USAGE ON TYPE public.user_role TO authenticated;
GRANT USAGE ON TYPE public.message_role TO authenticated;
GRANT USAGE ON TYPE public.purchase_order_status TO authenticated;

-- Grant execution on all functions in the public schema
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;

-- Grant permissions on tables
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO service_role;

-- Grant permissions on sequences
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO service_role;

-- Ensure future objects have correct permissions
ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO authenticated;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT USAGE, SELECT ON SEQUENCES TO authenticated;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT EXECUTE ON FUNCTIONS TO authenticated;

-- Grant permissions for Supabase managed schemas
GRANT USAGE ON SCHEMA storage TO authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA storage TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA storage TO authenticated;

-- Initial data seeding (optional)
-- You can add initial INSERT statements here if needed for testing or default setup.
-- Example:
-- INSERT INTO public.companies (company_name) VALUES ('Default Test Company');
-- ...

-- End of script
SELECT 'Schema setup complete.';
