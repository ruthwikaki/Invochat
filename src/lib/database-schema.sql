
-- ### InvoChat Database Schema ###
-- This script is designed for a fresh Supabase project installation.

-- 1. Extensions
-- Enable pgcrypto for gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "public";

-- 2. Custom Types
-- Drop the type if it exists, then create it
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        DROP TYPE public.user_role;
    END IF;
    CREATE TYPE public.user_role AS ENUM ('Owner', 'Admin', 'Member');
END$$;

-- 3. Tables
-- Companies are the top-level tenants
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT NOW()
);
COMMENT ON TABLE public.companies IS 'Top-level tenant for data isolation.';

-- Users table stores app users, linked to a company
CREATE TABLE IF NOT EXISTS public.users (
    id uuid NOT NULL PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid REFERENCES public.companies(id) ON DELETE SET NULL,
    email text UNIQUE,
    role public.user_role NOT NULL DEFAULT 'Member',
    deleted_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT NOW(),
    updated_at timestamptz
);
COMMENT ON TABLE public.users IS 'Stores application users and their company affiliation.';

-- Company-specific settings and business rules
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    overstock_multiplier numeric NOT NULL DEFAULT 3,
    high_value_threshold integer NOT NULL DEFAULT 100000, -- in cents
    fast_moving_days integer NOT NULL DEFAULT 30,
    predictive_stock_days integer NOT NULL DEFAULT 7,
    currency text NOT NULL DEFAULT 'USD',
    timezone text NOT NULL DEFAULT 'UTC',
    tax_rate numeric NOT NULL DEFAULT 0.0,
    custom_rules jsonb,
    created_at timestamptz NOT NULL DEFAULT NOW(),
    updated_at timestamptz
);
COMMENT ON TABLE public.company_settings IS 'Stores business logic settings for each company.';

-- Product master list
CREATE TABLE IF NOT EXISTS public.products (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku text NOT NULL,
    name text NOT NULL,
    category text,
    barcode text,
    created_at timestamptz NOT NULL DEFAULT NOW(),
    updated_at timestamptz,
    UNIQUE(company_id, sku)
);
COMMENT ON TABLE public.products IS 'Master list of all products.';

-- Locations for inventory
CREATE TABLE IF NOT EXISTS public.locations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    address text,
    is_default boolean NOT NULL DEFAULT false,
    deleted_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT NOW(),
    updated_at timestamptz,
    UNIQUE(company_id, name)
);
COMMENT ON TABLE public.locations IS 'Warehouses or other stock-keeping locations.';

-- Inventory stock levels
CREATE TABLE IF NOT EXISTS public.inventory (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    location_id uuid REFERENCES public.locations(id) ON DELETE SET NULL,
    quantity integer NOT NULL DEFAULT 0,
    cost integer NOT NULL DEFAULT 0, -- in cents
    price integer, -- in cents
    landed_cost integer, -- in cents
    on_order_quantity integer NOT NULL DEFAULT 0,
    last_sold_date date,
    version integer NOT NULL DEFAULT 1,
    deleted_at timestamptz,
    deleted_by uuid REFERENCES public.users(id),
    source_platform text,
    external_product_id text,
    external_variant_id text,
    external_quantity integer,
    created_at timestamptz NOT NULL DEFAULT NOW(),
    updated_at timestamptz,
    UNIQUE (company_id, product_id, location_id),
    UNIQUE (company_id, source_platform, external_variant_id)
);
COMMENT ON TABLE public.inventory IS 'Tracks stock levels for products at various locations.';

-- Supplier/Vendor information
CREATE TABLE IF NOT EXISTS public.vendors (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    vendor_name text NOT NULL,
    contact_info text,
    address text,
    terms text,
    account_number text,
    deleted_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT NOW(),
    updated_at timestamptz,
    UNIQUE(company_id, vendor_name)
);
COMMENT ON TABLE public.vendors IS 'Stores supplier/vendor information.';

-- Supplier-specific product catalog
CREATE TABLE IF NOT EXISTS public.supplier_catalogs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    supplier_id uuid NOT NULL REFERENCES public.vendors(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    supplier_sku text,
    unit_cost integer NOT NULL, -- in cents
    moq integer,
    lead_time_days integer,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT NOW(),
    updated_at timestamptz,
    UNIQUE(supplier_id, product_id)
);
COMMENT ON TABLE public.supplier_catalogs IS 'Stores supplier-specific pricing and SKUs for products.';

-- Reorder rules for products
CREATE TABLE IF NOT EXISTS public.reorder_rules (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    location_id uuid REFERENCES public.locations(id) ON DELETE CASCADE,
    rule_type text NOT NULL DEFAULT 'manual',
    min_stock integer,
    max_stock integer,
    reorder_quantity integer,
    created_at timestamptz NOT NULL DEFAULT NOW(),
    updated_at timestamptz,
    UNIQUE(company_id, product_id, location_id),
    CHECK(min_stock IS NULL OR max_stock IS NULL OR min_stock <= max_stock),
    CHECK(reorder_quantity IS NULL OR reorder_quantity > 0)
);
COMMENT ON TABLE public.reorder_rules IS 'Defines reordering thresholds for products.';

-- Purchase Orders
CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.vendors(id) ON DELETE SET NULL,
    po_number text NOT NULL,
    status text NOT NULL DEFAULT 'draft',
    order_date date NOT NULL,
    expected_date date,
    total_amount integer, -- in cents
    tax_amount integer, -- in cents
    shipping_cost integer, -- in cents
    notes text,
    requires_approval boolean NOT NULL DEFAULT false,
    approved_by uuid REFERENCES public.users(id),
    approved_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT NOW(),
    updated_at timestamptz,
    UNIQUE(company_id, po_number)
);
COMMENT ON TABLE public.purchase_orders IS 'Tracks purchase orders sent to suppliers.';
CREATE SEQUENCE IF NOT EXISTS purchase_orders_po_number_seq;
ALTER TABLE public.purchase_orders ALTER COLUMN po_number SET DEFAULT 'PO-' || TO_CHAR(nextval('purchase_orders_po_number_seq'), 'FM000000');


-- Items within a Purchase Order
CREATE TABLE IF NOT EXISTS public.purchase_order_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    po_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    quantity_ordered integer NOT NULL,
    quantity_received integer NOT NULL DEFAULT 0,
    unit_cost integer NOT NULL, -- in cents
    tax_rate numeric,
    created_at timestamptz NOT NULL DEFAULT NOW(),
    updated_at timestamptz,
    UNIQUE(po_id, product_id)
);
COMMENT ON TABLE public.purchase_order_items IS 'Line items for each purchase order.';

-- Customer data
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform text,
    external_id text,
    customer_name text NOT NULL,
    email text,
    status text,
    deleted_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT NOW(),
    updated_at timestamptz,
    UNIQUE(company_id, email)
);
COMMENT ON TABLE public.customers IS 'Stores customer information.';

-- Sales records
CREATE TABLE IF NOT EXISTS public.sales (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_id uuid REFERENCES public.customers(id),
    sale_number text NOT NULL,
    total_amount integer NOT NULL, -- in cents
    tax_amount integer, -- in cents
    payment_method text,
    notes text,
    created_at timestamptz NOT NULL DEFAULT NOW(),
    created_by uuid REFERENCES public.users(id),
    external_id text,
    UNIQUE(company_id, sale_number)
);
COMMENT ON TABLE public.sales IS 'Tracks sales transactions.';
CREATE SEQUENCE IF NOT EXISTS sales_sale_number_seq;

-- Items within a Sale
CREATE TABLE IF NOT EXISTS public.sale_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    sale_id uuid NOT NULL REFERENCES public.sales(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    location_id uuid REFERENCES public.locations(id) ON DELETE SET NULL,
    quantity integer NOT NULL,
    unit_price integer NOT NULL, -- in cents
    cost_at_time integer -- in cents
);
COMMENT ON TABLE public.sale_items IS 'Line items for each sale.';

-- Integration settings
CREATE TABLE IF NOT EXISTS public.integrations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform text NOT NULL,
    shop_domain text,
    shop_name text,
    is_active boolean NOT NULL DEFAULT false,
    last_sync_at timestamptz,
    sync_status text,
    created_at timestamptz NOT NULL DEFAULT NOW(),
    updated_at timestamptz,
    UNIQUE(company_id, platform)
);
COMMENT ON TABLE public.integrations IS 'Stores third-party integration settings.';

-- Sync state for integrations
CREATE TABLE IF NOT EXISTS public.sync_state (
    integration_id uuid PRIMARY KEY REFERENCES public.integrations(id) ON DELETE CASCADE,
    sync_type text NOT NULL,
    last_processed_cursor text,
    last_update timestamptz NOT NULL DEFAULT NOW()
);
COMMENT ON TABLE public.sync_state IS 'Tracks the state of ongoing data synchronizations.';

-- Logs for sync jobs
CREATE TABLE IF NOT EXISTS public.sync_logs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    sync_type text NOT NULL,
    status text NOT NULL,
    records_synced integer,
    error_message text,
    started_at timestamptz NOT NULL DEFAULT NOW(),
    completed_at timestamptz
);
COMMENT ON TABLE public.sync_logs IS 'Logs the history of sync jobs.';

-- Chat conversation history
CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES public.users(id),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    title text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT NOW(),
    last_accessed_at timestamptz NOT NULL DEFAULT NOW(),
    is_starred boolean NOT NULL DEFAULT false
);
COMMENT ON TABLE public.conversations IS 'Stores chat conversation threads.';

-- Individual chat messages
CREATE TABLE IF NOT EXISTS public.messages (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id),
    role text NOT NULL,
    content text,
    component text,
    component_props jsonb,
    visualization jsonb,
    confidence real,
    assumptions text[],
    created_at timestamptz NOT NULL DEFAULT NOW()
);
COMMENT ON TABLE public.messages IS 'Stores individual messages within a conversation.';

-- Channel fee configuration for net margin calculations
CREATE TABLE IF NOT EXISTS public.channel_fees (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    channel_name text NOT NULL,
    percentage_fee numeric NOT NULL DEFAULT 0,
    fixed_fee integer NOT NULL DEFAULT 0, -- in cents
    created_at timestamptz NOT NULL DEFAULT NOW(),
    updated_at timestamptz,
    UNIQUE(company_id, channel_name)
);
COMMENT ON TABLE public.channel_fees IS 'Stores sales channel fees for net margin calculations.';

-- Audit log for important actions
CREATE TABLE IF NOT EXISTS public.audit_log (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid REFERENCES public.users(id),
    company_id uuid REFERENCES public.companies(id),
    action text NOT NULL,
    details jsonb,
    created_at timestamptz NOT NULL DEFAULT NOW()
);
COMMENT ON TABLE public.audit_log IS 'Tracks significant user and system actions.';

-- Inventory movement ledger
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    location_id uuid NOT NULL REFERENCES public.locations(id) ON DELETE RESTRICT,
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid,
    notes text,
    created_at timestamptz NOT NULL DEFAULT NOW(),
    created_by uuid REFERENCES public.users(id)
);
COMMENT ON TABLE public.inventory_ledger IS 'Immutable log of all inventory movements.';

-- Background job tracking for data exports
CREATE TABLE IF NOT EXISTS public.export_jobs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    requested_by_user_id uuid NOT NULL REFERENCES public.users(id),
    status text NOT NULL,
    download_url text,
    expires_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT NOW()
);
COMMENT ON TABLE public.export_jobs IS 'Tracks background data export jobs.';

-- User feedback on AI responses
CREATE TABLE IF NOT EXISTS public.user_feedback (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES public.users(id),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    subject_id text NOT NULL,
    subject_type text NOT NULL,
    feedback text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT NOW()
);
COMMENT ON TABLE public.user_feedback IS 'Collects user feedback on AI features.';

-- 4. Materialized Views for Performance
CREATE MATERIALIZED VIEW IF NOT EXISTS public.company_dashboard_metrics AS
SELECT
    i.company_id,
    SUM(i.quantity * i.cost) AS inventory_value,
    COUNT(DISTINCT p.id) AS total_skus,
    SUM(CASE WHEN i.quantity < COALESCE(rr.min_stock, 0) THEN 1 ELSE 0 END) AS low_stock_count
FROM
    public.inventory i
JOIN
    public.products p ON i.product_id = p.id
LEFT JOIN
    public.reorder_rules rr ON i.product_id = rr.product_id AND i.location_id = rr.location_id
WHERE
    i.deleted_at IS NULL
GROUP BY
    i.company_id;

CREATE MATERIALIZED VIEW IF NOT EXISTS public.customer_analytics_metrics AS
SELECT
    s.company_id,
    COUNT(DISTINCT c.id) AS total_customers,
    SUM(CASE WHEN c.created_at >= NOW() - INTERVAL '30 days' THEN 1 ELSE 0 END) AS new_customers_last_30_days,
    AVG(s.total_amount) AS average_lifetime_value,
    COUNT(CASE WHEN s.order_count > 1 THEN 1 ELSE 0 END)::numeric / NULLIF(COUNT(DISTINCT c.id), 0) AS repeat_customer_rate
FROM
    (
        SELECT
            company_id,
            customer_id,
            SUM(total_amount) AS total_amount,
            COUNT(*) AS order_count
        FROM public.sales
        GROUP BY company_id, customer_id
    ) s
JOIN
    public.customers c ON s.customer_id = c.id
WHERE
    c.deleted_at IS NULL
GROUP BY
    s.company_id;


-- 5. Indexes for Performance
CREATE INDEX IF NOT EXISTS users_company_id_idx ON public.users(company_id);
CREATE INDEX IF NOT EXISTS products_company_id_idx ON public.products(company_id);
CREATE INDEX IF NOT EXISTS inventory_product_id_idx ON public.inventory(product_id);
CREATE INDEX IF NOT EXISTS inventory_company_id_idx ON public.inventory(company_id);
CREATE INDEX IF NOT EXISTS inventory_location_id_idx ON public.inventory(location_id);
CREATE INDEX IF NOT EXISTS vendors_company_id_idx ON public.vendors(company_id);
CREATE INDEX IF NOT EXISTS po_company_id_idx ON public.purchase_orders(company_id);
CREATE INDEX IF NOT EXISTS po_supplier_id_idx ON public.purchase_orders(supplier_id);
CREATE INDEX IF NOT EXISTS po_items_product_id_idx ON public.purchase_order_items(product_id);
CREATE INDEX IF NOT EXISTS sales_company_id_idx ON public.sales(company_id);
CREATE INDEX IF NOT EXISTS sale_items_product_id_idx ON public.sale_items(product_id);
CREATE INDEX IF NOT EXISTS sale_items_company_id_idx ON public.sale_items(company_id);
CREATE INDEX IF NOT EXISTS integrations_company_id_idx ON public.integrations(company_id);
CREATE INDEX IF NOT EXISTS sync_logs_integration_id_idx ON public.sync_logs(integration_id);
CREATE INDEX IF NOT EXISTS conversations_user_id_idx ON public.conversations(user_id);
CREATE INDEX IF NOT EXISTS messages_conversation_id_idx ON public.messages(conversation_id);
CREATE INDEX IF NOT EXISTS messages_company_id_idx ON public.messages(company_id);
CREATE INDEX IF NOT EXISTS ledger_company_product_location_idx ON public.inventory_ledger (company_id, product_id, location_id);
CREATE INDEX IF NOT EXISTS ledger_company_id_idx ON public.inventory_ledger (company_id);
CREATE INDEX IF NOT EXISTS rr_product_id_idx ON public.reorder_rules(product_id);
CREATE INDEX IF NOT EXISTS sc_product_id_idx ON public.supplier_catalogs(product_id);
CREATE INDEX IF NOT EXISTS export_jobs_company_id_idx ON public.export_jobs(company_id);
CREATE INDEX IF NOT EXISTS channel_fees_company_id_idx ON public.channel_fees(company_id);


-- 6. Helper Functions & Triggers

-- Function to get the current user's company ID from the JWT
CREATE OR REPLACE FUNCTION auth.company_id()
RETURNS uuid
LANGUAGE sql STABLE
AS $$
  SELECT NULLIF(current_setting('request.jwt.claims', true)::jsonb ->> 'app_metadata', '')::jsonb ->> 'company_id' AS company_id
$$;
COMMENT ON FUNCTION auth.company_id() IS 'Returns the company_id of the currently authenticated user.';

-- Function to handle new user setup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  company_id_var uuid;
  company_name_text text;
BEGIN
  -- Extract company name from metadata, provide a fallback
  company_name_text := trim(new.raw_user_meta_data->>'company_name');
  IF company_name_text IS NULL OR company_name_text = '' THEN
    RAISE EXCEPTION 'Company name cannot be empty.';
  END IF;

  -- Create a new company for the user
  INSERT INTO public.companies (company_name)
  VALUES (company_name_text)
  RETURNING id INTO company_id_var;

  -- Insert the user into the public.users table
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (new.id, company_id_var, new.email, 'Owner');

  -- Update the user's app_metadata in auth.users
  UPDATE auth.users
  SET app_metadata = jsonb_set(
    COALESCE(app_metadata, '{}'::jsonb),
    '{company_id}',
    to_jsonb(company_id_var)
  ) || jsonb_set(
    COALESCE(app_metadata, '{}'::jsonb),
    '{role}',
    to_jsonb('Owner'::text)
  )
  WHERE id = new.id;

  RETURN new;
END;
$$;
COMMENT ON FUNCTION public.handle_new_user() IS 'Trigger function to create a company and user profile on new user signup.';

-- Generic function to update the 'updated_at' timestamp
CREATE OR REPLACE FUNCTION public.increment_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
   NEW.updated_at = NOW();
   RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.increment_updated_at() IS 'Updates the updated_at timestamp on a row update.';


-- Function to increment version on inventory updates
CREATE OR REPLACE FUNCTION public.increment_version()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  new.version = old.version + 1;
  new.updated_at = NOW();
  RETURN new;
END;
$$;
COMMENT ON FUNCTION public.increment_version() IS 'Increments the version number on inventory updates for optimistic locking.';

-- Trigger to enforce message company_id matches conversation company_id
CREATE OR REPLACE FUNCTION public.enforce_message_company_id()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    conversation_company_id uuid;
BEGIN
    SELECT company_id INTO conversation_company_id FROM public.conversations WHERE id = NEW.conversation_id;
    IF NEW.company_id != conversation_company_id THEN
        RAISE EXCEPTION 'Message company_id does not match conversation company_id';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_message_company_id() IS 'Ensures a message''s company_id matches its parent conversation.';

-- 7. Apply Triggers

-- Trigger for new user signup
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- Trigger for inventory versioning
DROP TRIGGER IF EXISTS handle_inventory_update ON public.inventory;
CREATE TRIGGER handle_inventory_update
  BEFORE UPDATE ON public.inventory
  FOR EACH ROW
  WHEN (OLD.* IS DISTINCT FROM NEW.*)
  EXECUTE PROCEDURE public.increment_version();

-- Trigger for message company_id consistency
DROP TRIGGER IF EXISTS on_message_insert_or_update ON public.messages;
CREATE TRIGGER on_message_insert_or_update
  BEFORE INSERT OR UPDATE ON public.messages
  FOR EACH ROW
  EXECUTE PROCEDURE public.enforce_message_company_id();

-- Apply generic updated_at triggers
DROP TRIGGER IF EXISTS handle_products_update ON public.products;
CREATE TRIGGER handle_products_update BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE PROCEDURE public.increment_updated_at();

DROP TRIGGER IF EXISTS handle_locations_update ON public.locations;
CREATE TRIGGER handle_locations_update BEFORE UPDATE ON public.locations FOR EACH ROW EXECUTE PROCEDURE public.increment_updated_at();

DROP TRIGGER IF EXISTS handle_vendors_update ON public.vendors;
CREATE TRIGGER handle_vendors_update BEFORE UPDATE ON public.vendors FOR EACH ROW EXECUTE PROCEDURE public.increment_updated_at();

DROP TRIGGER IF EXISTS handle_supplier_catalogs_update ON public.supplier_catalogs;
CREATE TRIGGER handle_supplier_catalogs_update BEFORE UPDATE ON public.supplier_catalogs FOR EACH ROW EXECUTE PROCEDURE public.increment_updated_at();

DROP TRIGGER IF EXISTS handle_reorder_rules_update ON public.reorder_rules;
CREATE TRIGGER handle_reorder_rules_update BEFORE UPDATE ON public.reorder_rules FOR EACH ROW EXECUTE PROCEDURE public.increment_updated_at();

DROP TRIGGER IF EXISTS handle_purchase_orders_update ON public.purchase_orders;
CREATE TRIGGER handle_purchase_orders_update BEFORE UPDATE ON public.purchase_orders FOR EACH ROW EXECUTE PROCEDURE public.increment_updated_at();

DROP TRIGGER IF EXISTS handle_purchase_order_items_update ON public.purchase_order_items;
CREATE TRIGGER handle_purchase_order_items_update BEFORE UPDATE ON public.purchase_order_items FOR EACH ROW EXECUTE PROCEDURE public.increment_updated_at();

DROP TRIGGER IF EXISTS handle_customers_update ON public.customers;
CREATE TRIGGER handle_customers_update BEFORE UPDATE ON public.customers FOR EACH ROW EXECUTE PROCEDURE public.increment_updated_at();

DROP TRIGGER IF EXISTS handle_integrations_update ON public.integrations;
CREATE TRIGGER handle_integrations_update BEFORE UPDATE ON public.integrations FOR EACH ROW EXECUTE PROCEDURE public.increment_updated_at();


-- 8. Advanced Functions (RPCs)

-- Function to record a sale and update inventory atomically
CREATE OR REPLACE FUNCTION public.record_sale_transaction(
    p_company_id uuid,
    p_user_id uuid,
    p_sale_items jsonb,
    p_customer_name text DEFAULT NULL,
    p_customer_email text DEFAULT NULL,
    p_payment_method text DEFAULT 'card',
    p_notes text DEFAULT NULL,
    p_external_id text DEFAULT NULL
)
RETURNS public.sales
LANGUAGE plpgsql
AS $$
DECLARE
    new_sale_id uuid;
    new_customer_id uuid;
    total_amount_cents bigint;
    item_record record;
    sale_item_temp_table_name text;
BEGIN
    -- Create a temporary table to hold sale items
    sale_item_temp_table_name := 'sale_items_temp_' || replace(gen_random_uuid()::text, '-', '');
    EXECUTE format(
        'CREATE TEMP TABLE %I (
            product_id uuid,
            quantity int,
            unit_price int,
            location_id uuid
        ) ON COMMIT DROP;',
        sale_item_temp_table_name
    );

    -- Populate the temporary table from JSONB input
    EXECUTE format(
        'INSERT INTO %I (product_id, quantity, unit_price, location_id)
         SELECT (item->>''product_id'')::uuid, (item->>''quantity'')::int, (item->>''unit_price'')::int, (item->>''location_id'')::uuid
         FROM jsonb_array_elements(%L);',
        sale_item_temp_table_name, p_sale_items
    );

    -- Calculate total amount from the temporary table
    EXECUTE format('SELECT SUM(quantity * unit_price) FROM %I', sale_item_temp_table_name)
    INTO total_amount_cents;

    -- Upsert customer and get their ID
    IF p_customer_email IS NOT NULL THEN
        INSERT INTO public.customers (company_id, customer_name, email)
        VALUES (p_company_id, COALESCE(p_customer_name, p_customer_email), p_customer_email)
        ON CONFLICT (company_id, email) DO UPDATE SET customer_name = EXCLUDED.customer_name
        RETURNING id INTO new_customer_id;
    END IF;

    -- Create the sale record
    INSERT INTO public.sales (company_id, customer_id, sale_number, total_amount, payment_method, notes, created_by, external_id)
    VALUES (p_company_id, new_customer_id, 'SALE-' || TO_CHAR(nextval('sales_sale_number_seq'), 'FM000000'), total_amount_cents, p_payment_method, p_notes, p_user_id, p_external_id)
    RETURNING id INTO new_sale_id;

    -- Loop through temp table to update inventory and create sale_items
    FOR item_record IN EXECUTE format('SELECT * FROM %I', sale_item_temp_table_name)
    LOOP
        -- Decrement inventory
        UPDATE public.inventory
        SET quantity = quantity - item_record.quantity
        WHERE product_id = item_record.product_id
          AND company_id = p_company_id
          AND location_id = item_record.location_id;
          
        -- Insert into sale_items
        INSERT INTO public.sale_items (sale_id, company_id, product_id, location_id, quantity, unit_price, cost_at_time)
        VALUES (
            new_sale_id,
            p_company_id,
            item_record.product_id,
            item_record.location_id,
            item_record.quantity,
            item_record.unit_price,
            (SELECT cost FROM public.inventory WHERE product_id = item_record.product_id AND company_id = p_company_id AND location_id = item_record.location_id)
        );

        -- Insert into inventory ledger
        INSERT INTO public.inventory_ledger(company_id, product_id, location_id, change_type, quantity_change, new_quantity, related_id, notes, created_by)
        SELECT
            p_company_id,
            item_record.product_id,
            item_record.location_id,
            'sale',
            -item_record.quantity,
            i.quantity,
            new_sale_id,
            'Sale #' || (SELECT sale_number FROM public.sales WHERE id = new_sale_id),
            p_user_id
        FROM public.inventory i
        WHERE i.product_id = item_record.product_id
          AND i.company_id = p_company_id
          AND i.location_id = item_record.location_id;

    END LOOP;

    RETURN (SELECT * FROM public.sales WHERE id = new_sale_id);
END;
$$;
COMMENT ON FUNCTION public.record_sale_transaction IS 'Records a sale, updates inventory, and creates ledger entries in a single transaction.';

-- Other functions remain the same as previous correct version...
CREATE OR REPLACE FUNCTION public.check_inventory_references(p_company_id uuid, p_product_ids uuid[])
RETURNS TABLE(product_id uuid)
LANGUAGE sql
AS $$
  SELECT product_id FROM public.sale_items WHERE company_id = p_company_id AND product_id = ANY(p_product_ids)
  UNION
  SELECT product_id FROM public.purchase_order_items poi JOIN public.purchase_orders po ON poi.po_id = po.id WHERE po.company_id = p_company_id AND poi.product_id = ANY(p_product_ids);
$$;

CREATE OR REPLACE FUNCTION public.refresh_materialized_views(p_company_id uuid, p_view_names text[])
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    view_name text;
BEGIN
    FOREACH view_name IN ARRAY p_view_names
    LOOP
        EXECUTE 'REFRESH MATERIALIZED VIEW CONCURRENTLY public.' || quote_ident(view_name);
    END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_alerts(p_company_id uuid, p_dead_stock_days integer, p_fast_moving_days integer, p_predictive_stock_days integer)
RETURNS TABLE(type text, product_id uuid, product_name text, current_stock integer, reorder_point integer, last_sold_date date, value integer, days_of_stock_remaining numeric)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Low Stock Alerts
    RETURN QUERY
    SELECT
        'low_stock'::text as type,
        p.id as product_id,
        p.name as product_name,
        i.quantity as current_stock,
        rr.min_stock as reorder_point,
        i.last_sold_date,
        (i.quantity * i.cost)::integer as value,
        NULL::numeric as days_of_stock_remaining
    FROM public.inventory i
    JOIN public.products p ON i.product_id = p.id
    JOIN public.reorder_rules rr ON i.product_id = rr.product_id AND i.location_id = rr.location_id
    WHERE i.company_id = p_company_id AND i.quantity < rr.min_stock AND i.deleted_at IS NULL;

    -- Dead Stock Alerts
    RETURN QUERY
    SELECT
        'dead_stock'::text as type,
        p.id as product_id,
        p.name as product_name,
        i.quantity as current_stock,
        rr.min_stock as reorder_point,
        i.last_sold_date,
        (i.quantity * i.cost)::integer as value,
        NULL::numeric as days_of_stock_remaining
    FROM public.inventory i
    JOIN public.products p ON i.product_id = p.id
    LEFT JOIN public.reorder_rules rr ON i.product_id = rr.product_id AND i.location_id = rr.location_id
    WHERE i.company_id = p_company_id
      AND i.last_sold_date < (NOW() - (p_dead_stock_days || ' days')::interval)
      AND i.deleted_at IS NULL;

    -- Predictive Stockout Alerts
    RETURN QUERY
    WITH sales_velocity AS (
        SELECT
            si.product_id,
            SUM(si.quantity)::numeric / NULLIF(p_fast_moving_days, 0) AS daily_sales
        FROM public.sale_items si
        JOIN public.sales s ON si.sale_id = s.id
        WHERE si.company_id = p_company_id AND s.created_at >= NOW() - (p_fast_moving_days || ' days')::interval
        GROUP BY si.product_id
    )
    SELECT
        'predictive'::text as type,
        p.id as product_id,
        p.name as product_name,
        i.quantity as current_stock,
        rr.min_stock as reorder_point,
        i.last_sold_date,
        (i.quantity * i.cost)::integer as value,
        i.quantity / NULLIF(sv.daily_sales, 0) as days_of_stock_remaining
    FROM public.inventory i
    JOIN public.products p ON i.product_id = p.id
    JOIN sales_velocity sv ON i.product_id = sv.product_id
    LEFT JOIN public.reorder_rules rr ON i.product_id = rr.product_id AND i.location_id = rr.location_id
    WHERE i.company_id = p_company_id
      AND sv.daily_sales > 0
      AND (i.quantity / sv.daily_sales) <= p_predictive_stock_days
      AND i.deleted_at IS NULL;

END;
$$;


CREATE OR REPLACE FUNCTION public.batch_upsert_with_transaction(
    p_table_name text,
    p_records jsonb,
    p_conflict_columns text[]
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    temp_table_name text;
    insert_cols text;
    conflict_cols_formatted text;
    update_cols text;
    query text;
BEGIN
    temp_table_name := 'temp_upsert_' || replace(gen_random_uuid()::text, '-', '');

    -- Create a temporary table with the structure of the target table
    EXECUTE format('CREATE TEMP TABLE %I (LIKE public.%I INCLUDING DEFAULTS) ON COMMIT DROP;', temp_table_name, to_regclass(p_table_name)::text);

    -- Insert the JSON data into the temporary table
    EXECUTE format('INSERT INTO %I SELECT * FROM jsonb_populate_recordset(null::%I, %L);', temp_table_name, to_regclass(p_table_name)::text, p_records);

    -- Construct the column lists for the upsert command
    SELECT
        string_agg(quote_ident(column_name), ', '),
        string_agg(quote_ident(column_name) || ' = EXCLUDED.' || quote_ident(column_name), ', ')
    INTO insert_cols, update_cols
    FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = p_table_name;

    conflict_cols_formatted := array_to_string(p_conflict_columns, ', ');

    -- Construct and execute the final UPSERT command
    query := format(
        'INSERT INTO public.%I (%s) ' ||
        'SELECT %s FROM %I ' ||
        'ON CONFLICT (%s) DO UPDATE SET %s;',
        p_table_name, insert_cols, insert_cols, temp_table_name, conflict_cols_formatted, update_cols
    );

    EXECUTE query;
END;
$$;


-- 9. Row-Level Security (RLS)
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vendors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_catalogs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reorder_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sale_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sync_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sync_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_dashboard_metrics ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_analytics_metrics ENABLE ROW LEVEL SECURITY;

-- Policies
CREATE POLICY "Company access" ON public.companies FOR ALL USING (id = auth.company_id());
CREATE POLICY "Company access for users" ON public.users FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access for settings" ON public.company_settings FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access for products" ON public.products FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL);
CREATE POLICY "Company access for inventory" ON public.inventory FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL);
CREATE POLICY "Company access for locations" ON public.locations FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL);
CREATE POLICY "Company access for vendors" ON public.vendors FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL);
CREATE POLICY "Company access for catalogs" ON public.supplier_catalogs FOR ALL USING ((SELECT company_id FROM public.vendors WHERE id = supplier_id) = auth.company_id());
CREATE POLICY "Company access for reorder rules" ON public.reorder_rules FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access for purchase orders" ON public.purchase_orders FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access for po items" ON public.purchase_order_items FOR ALL USING ((( SELECT company_id FROM public.purchase_orders WHERE id = po_id ) = auth.company_id()));
CREATE POLICY "Company access for customers" ON public.customers FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL);
CREATE POLICY "Company access for sales" ON public.sales FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access for sale items" ON public.sale_items FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access for integrations" ON public.integrations FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access for sync state" ON public.sync_state FOR ALL USING ((( SELECT company_id FROM public.integrations WHERE id = integration_id ) = auth.company_id()));
CREATE POLICY "Company access for sync logs" ON public.sync_logs FOR ALL USING ((( SELECT company_id FROM public.integrations WHERE id = integration_id ) = auth.company_id()));
CREATE POLICY "Users can manage their own conversations" ON public.conversations FOR ALL USING (user_id = auth.uid());
CREATE POLICY "Users can manage messages in their conversations" ON public.messages FOR ALL USING ((conversation_id IN (SELECT id FROM public.conversations WHERE user_id = auth.uid())));
CREATE POLICY "Company access to audit log" ON public.audit_log FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access to inventory ledger" ON public.inventory_ledger FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access to export jobs" ON public.export_jobs FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access to channel fees" ON public.channel_fees FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access to user feedback" ON public.user_feedback FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access to dashboard metrics" ON public.company_dashboard_metrics FOR SELECT USING (company_id = auth.company_id());
CREATE POLICY "Company access to customer metrics" ON public.customer_analytics_metrics FOR SELECT USING (company_id = auth.company_id());


-- 10. Grants
GRANT USAGE ON SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO postgres, service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO postgres, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO postgres, service_role;

GRANT USAGE ON TYPE public.user_role TO authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- Ensure future functions/types are also granted
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE ON TYPES TO authenticated;
