-- -------------------------------------------------------------------------------- --
--                                                                                  --
--                                     ARVO SCHEMA                                  --
--                                     Version 4.0                                  --
--                                                                                  --
-- -------------------------------------------------------------------------------- --

-- -------------------------------------------------------------------------------- --
--                                  Setup & Extensions                                --
-- -------------------------------------------------------------------------------- --

-- Install the 'uuid-ossp' extension to use uuid_generate_v4()
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;

-- Install the 'pgcrypto' extension for encryption functions
CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA extensions;

-- -------------------------------------------------------------------------------- --
--                                     Enums & Types                                  --
-- -------------------------------------------------------------------------------- --

-- Define a custom type for Purchase Order status
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'po_status') THEN
    CREATE TYPE public.po_status AS ENUM (
      'draft',
      'pending_approval',
      'sent',
      'partial',
      'received',
      'cancelled'
    );
  END IF;
END
$$;

-- Define a custom type for Message roles
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'message_role') THEN
    CREATE TYPE public.message_role AS ENUM (
      'user',
      'assistant'
    );
  END IF;
END
$$;

-- -------------------------------------------------------------------------------- --
--                                     Core Tables                                    --
-- -------------------------------------------------------------------------------- --

-- Table: companies
-- Stores basic information about each company (tenant) in the system.
CREATE TABLE IF NOT EXISTS public.companies (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  name text NOT NULL,
  created_at timestamptz DEFAULT now()
);

-- Table: products
-- Master list of all products, independent of stock levels.
CREATE TABLE IF NOT EXISTS public.products (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE,
  sku text NOT NULL,
  name text NOT NULL,
  category text,
  barcode text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz,
  deleted_at timestamptz,
  UNIQUE(company_id, sku)
);

-- Table: locations
-- Warehouses or other places where inventory is stored.
CREATE TABLE IF NOT EXISTS public.locations (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE,
  name text NOT NULL,
  address text,
  is_default boolean DEFAULT false,
  deleted_at timestamptz,
  UNIQUE(company_id, name)
);

-- Table: inventory
-- Tracks stock levels for each product at a specific location.
CREATE TABLE IF NOT EXISTS public.inventory (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE,
  product_id uuid REFERENCES public.products(id) ON DELETE RESTRICT,
  location_id uuid REFERENCES public.locations(id) ON DELETE SET NULL,
  quantity integer NOT NULL DEFAULT 0,
  cost integer NOT NULL DEFAULT 0, -- in cents
  price integer, -- in cents
  landed_cost integer, -- in cents
  on_order_quantity integer NOT NULL DEFAULT 0,
  last_sold_date date,
  version integer NOT NULL DEFAULT 1,
  deleted_at timestamptz,
  deleted_by uuid REFERENCES auth.users(id),
  source_platform text,
  external_product_id text,
  external_variant_id text,
  external_quantity integer,
  last_sync_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz,
  UNIQUE(company_id, product_id, location_id)
);

-- Table: reorder_rules
-- Stores reordering parameters for products.
CREATE TABLE IF NOT EXISTS public.reorder_rules (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE,
  product_id uuid REFERENCES public.products(id) ON DELETE CASCADE,
  location_id uuid REFERENCES public.locations(id) ON DELETE CASCADE,
  rule_type text DEFAULT 'manual',
  min_stock integer,
  max_stock integer,
  reorder_quantity integer,
  UNIQUE(company_id, product_id, location_id)
);

-- Sequence for sales numbers
CREATE SEQUENCE IF NOT EXISTS public.sales_sale_number_seq;

-- Table: sales
-- Header information for each sale transaction.
CREATE TABLE IF NOT EXISTS public.sales (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE,
  sale_number text UNIQUE NOT NULL DEFAULT 'SALE-' || TO_CHAR(nextval('sales_sale_number_seq'), 'FM000000'),
  customer_id uuid, -- FK added later
  customer_name text,
  customer_email text,
  total_amount integer NOT NULL, -- in cents
  tax_amount integer, -- in cents
  payment_method text NOT NULL DEFAULT 'other',
  notes text,
  created_at timestamptz DEFAULT now(),
  created_by uuid REFERENCES auth.users(id),
  external_id text
);

-- Table: sale_items
-- Line items for each sale.
CREATE TABLE IF NOT EXISTS public.sale_items (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  sale_id uuid REFERENCES public.sales(id) ON DELETE CASCADE,
  company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE,
  product_id uuid REFERENCES public.products(id) ON DELETE RESTRICT,
  location_id uuid REFERENCES public.locations(id) ON DELETE RESTRICT,
  quantity integer NOT NULL,
  unit_price integer NOT NULL, -- in cents
  cost_at_time integer -- in cents
);

-- Table: customers
-- Stores information about customers.
CREATE TABLE IF NOT EXISTS public.customers (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE,
  platform text,
  external_id text,
  customer_name text NOT NULL,
  email text,
  status text,
  deleted_at timestamptz,
  created_at timestamptz DEFAULT now(),
  UNIQUE(company_id, email)
);

-- Add the foreign key from sales to customers now that customers table exists.
ALTER TABLE public.sales
  ADD CONSTRAINT fk_sales_customer_id FOREIGN KEY (customer_id)
  REFERENCES public.customers(id) ON DELETE SET NULL;

-- Table: vendors (Suppliers)
CREATE TABLE IF NOT EXISTS public.vendors (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE,
  vendor_name text NOT NULL,
  contact_info text,
  address text,
  terms text,
  account_number text,
  deleted_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz,
  UNIQUE(company_id, vendor_name)
);

-- Sequence for PO numbers
CREATE SEQUENCE IF NOT EXISTS public.purchase_orders_po_number_seq;

-- Table: purchase_orders
-- Header information for purchase orders.
CREATE TABLE IF NOT EXISTS public.purchase_orders (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE,
  supplier_id uuid REFERENCES public.vendors(id) ON DELETE SET NULL,
  po_number text UNIQUE NOT NULL DEFAULT 'PO-' || TO_CHAR(nextval('purchase_orders_po_number_seq'), 'FM000000'),
  status public.po_status DEFAULT 'draft',
  order_date date NOT NULL DEFAULT CURRENT_DATE,
  expected_date date,
  total_amount integer NOT NULL DEFAULT 0, -- in cents
  tax_amount integer,
  shipping_cost integer,
  notes text,
  requires_approval boolean NOT NULL DEFAULT false,
  approved_by uuid REFERENCES auth.users(id),
  approved_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz
);

-- Table: purchase_order_items
-- Line items for each purchase order.
CREATE TABLE IF NOT EXISTS public.purchase_order_items (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  po_id uuid REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
  company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE,
  product_id uuid REFERENCES public.products(id) ON DELETE RESTRICT,
  quantity_ordered integer NOT NULL,
  quantity_received integer NOT NULL DEFAULT 0,
  unit_cost integer NOT NULL, -- in cents
  tax_rate numeric(5,4),
  UNIQUE (po_id, product_id)
);

-- Table: supplier_catalogs
-- Maps products to suppliers with their specific terms.
CREATE TABLE IF NOT EXISTS public.supplier_catalogs (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  supplier_id uuid REFERENCES public.vendors(id) ON DELETE CASCADE,
  product_id uuid REFERENCES public.products(id) ON DELETE CASCADE,
  supplier_sku text,
  unit_cost integer NOT NULL, -- in cents
  moq integer DEFAULT 1,
  lead_time_days integer,
  is_active boolean DEFAULT true,
  UNIQUE(supplier_id, product_id)
);

-- Table: conversations
-- Stores chat conversation history.
CREATE TABLE IF NOT EXISTS public.conversations (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE,
  title text NOT NULL,
  created_at timestamptz DEFAULT now(),
  last_accessed_at timestamptz DEFAULT now(),
  is_starred boolean DEFAULT false
);

-- Table: messages
-- Stores individual chat messages.
CREATE TABLE IF NOT EXISTS public.messages (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  conversation_id uuid REFERENCES public.conversations(id) ON DELETE CASCADE,
  company_id uuid NOT NULL,
  role public.message_role NOT NULL,
  content text NOT NULL,
  component text,
  "componentProps" jsonb,
  visualization jsonb,
  confidence numeric(3,2),
  assumptions text[],
  isError boolean,
  created_at timestamptz DEFAULT now()
);

-- Table: company_settings
-- Stores settings specific to each company.
CREATE TABLE IF NOT EXISTS public.company_settings (
  company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
  dead_stock_days integer DEFAULT 90,
  overstock_multiplier numeric(5,2) DEFAULT 3.0,
  high_value_threshold integer DEFAULT 100000,
  fast_moving_days integer DEFAULT 30,
  predictive_stock_days integer DEFAULT 7,
  currency text DEFAULT 'USD',
  timezone text DEFAULT 'UTC',
  tax_rate numeric(5,4),
  custom_rules jsonb,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz
);

-- Table: inventory_ledger
-- Audit trail for all inventory movements.
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE,
  product_id uuid REFERENCES public.products(id) ON DELETE RESTRICT,
  location_id uuid REFERENCES public.locations(id) ON DELETE RESTRICT,
  created_at timestamptz DEFAULT now(),
  created_by uuid REFERENCES auth.users(id),
  change_type text NOT NULL,
  quantity_change integer NOT NULL,
  new_quantity integer NOT NULL,
  related_id uuid,
  notes text
);

-- Table: channel_fees
-- Stores transaction fees for different sales channels.
CREATE TABLE IF NOT EXISTS public.channel_fees (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE,
  channel_name text NOT NULL,
  percentage_fee numeric(8,6) NOT NULL,
  fixed_fee integer NOT NULL, -- in cents
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz,
  UNIQUE(company_id, channel_name)
);

-- Table: integrations
-- Stores connection details for third-party platforms.
CREATE TABLE IF NOT EXISTS public.integrations (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE,
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

-- Table: sync_logs
-- Logs the history of data syncs.
CREATE TABLE IF NOT EXISTS public.sync_logs (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  integration_id uuid REFERENCES public.integrations(id) ON DELETE CASCADE,
  sync_type text NOT NULL,
  status text NOT NULL,
  records_synced integer,
  error_message text,
  started_at timestamptz DEFAULT now(),
  completed_at timestamptz
);

-- Table: sync_state
-- Tracks the state of ongoing syncs for resumability.
CREATE TABLE IF NOT EXISTS public.sync_state (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  integration_id uuid REFERENCES public.integrations(id) ON DELETE CASCADE,
  sync_type text NOT NULL,
  last_processed_cursor text,
  last_update timestamptz DEFAULT now(),
  UNIQUE(integration_id, sync_type)
);

-- Table: export_jobs
-- Manages data export requests.
CREATE TABLE IF NOT EXISTS public.export_jobs (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE,
  requested_by_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'pending',
  download_url text,
  expires_at timestamptz,
  created_at timestamptz DEFAULT now()
);

-- Table: audit_log
-- Central log for all significant user and system actions.
CREATE TABLE IF NOT EXISTS public.audit_log (
  id bigint PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  user_id uuid,
  company_id uuid,
  action text NOT NULL,
  details jsonb,
  created_at timestamptz DEFAULT now()
);

-- Table: user_feedback
-- Stores user feedback on AI features.
CREATE TABLE IF NOT EXISTS public.user_feedback (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE,
  subject_id text NOT NULL,
  subject_type text NOT NULL,
  feedback text NOT NULL,
  created_at timestamptz DEFAULT now()
);

-- -------------------------------------------------------------------------------- --
--                                       Views                                      --
-- -------------------------------------------------------------------------------- --

-- Materialized View: company_dashboard_metrics
-- Pre-calculates expensive dashboard metrics for fast loading.
CREATE MATERIALIZED VIEW IF NOT EXISTS public.company_dashboard_metrics AS
SELECT
    c.id AS company_id,
    COALESCE(SUM(i.quantity * i.cost), 0) AS inventory_value,
    COUNT(DISTINCT p.id) AS total_skus,
    COUNT(DISTINCT
        CASE
            WHEN i.quantity <= COALESCE(rr.min_stock, 0) AND i.quantity > 0 THEN p.id
            ELSE NULL
        END
    ) AS low_stock_count
FROM
    public.companies c
LEFT JOIN
    public.products p ON c.id = p.company_id AND p.deleted_at IS NULL
LEFT JOIN
    public.inventory i ON p.id = i.product_id AND i.deleted_at IS NULL
LEFT JOIN
    public.reorder_rules rr ON i.product_id = rr.product_id AND i.location_id = rr.location_id
GROUP BY
    c.id;

-- Materialized View: customer_analytics_metrics
-- Pre-calculates customer analytics for fast loading.
CREATE MATERIALIZED VIEW IF NOT EXISTS public.customer_analytics_metrics AS
SELECT
    s.company_id,
    COUNT(DISTINCT s.customer_id) AS total_customers,
    COUNT(DISTINCT CASE WHEN s.created_at >= NOW() - INTERVAL '30 days' THEN s.customer_id ELSE NULL END) AS new_customers_last_30_days,
    CASE
        WHEN COUNT(DISTINCT s.customer_id) > 0 THEN SUM(s.total_amount) / COUNT(DISTINCT s.customer_id)
        ELSE 0
    END AS average_lifetime_value,
    (SELECT COUNT(DISTINCT customer_id) FROM public.sales WHERE company_id = s.company_id AND customer_id IS NOT NULL AND (SELECT COUNT(*) FROM public.sales s2 WHERE s2.customer_id = s.customer_id) > 1)
    / NULLIF(COUNT(DISTINCT s.customer_id), 0)::numeric AS repeat_customer_rate
FROM
    public.sales s
WHERE s.customer_id IS NOT NULL
GROUP BY
    s.company_id;

-- -------------------------------------------------------------------------------- --
--                                      Indexes                                     --
-- -------------------------------------------------------------------------------- --

-- Foreign Key Indexes
CREATE INDEX IF NOT EXISTS products_company_id_idx ON public.products(company_id);
CREATE INDEX IF NOT EXISTS inventory_company_id_idx ON public.inventory(company_id);
CREATE INDEX IF NOT EXISTS inventory_product_location_idx ON public.inventory(product_id, location_id);
CREATE INDEX IF NOT EXISTS reorder_rules_product_id_idx ON public.reorder_rules(product_id);
CREATE INDEX IF NOT EXISTS sales_company_id_idx ON public.sales(company_id);
CREATE INDEX IF NOT EXISTS sale_items_sale_id_idx ON public.sale_items(sale_id);
CREATE INDEX IF NOT EXISTS customers_company_id_idx ON public.customers(company_id);
CREATE INDEX IF NOT EXISTS vendors_company_id_idx ON public.vendors(company_id);
CREATE INDEX IF NOT EXISTS purchase_orders_company_id_idx ON public.purchase_orders(company_id);
CREATE INDEX IF NOT EXISTS po_items_po_id_idx ON public.purchase_order_items(po_id);
CREATE INDEX IF NOT EXISTS supplier_catalogs_product_id_idx ON public.supplier_catalogs(product_id);
CREATE INDEX IF NOT EXISTS conversations_user_id_idx ON public.conversations(user_id);
CREATE INDEX IF NOT EXISTS messages_conversation_id_idx ON public.messages(conversation_id);
CREATE INDEX IF NOT EXISTS inventory_ledger_company_id_idx ON public.inventory_ledger(company_id);
CREATE INDEX IF NOT EXISTS inventory_ledger_product_location_idx ON public.inventory_ledger(product_id, location_id);
CREATE INDEX IF NOT EXISTS channel_fees_company_id_idx ON public.channel_fees(company_id);
CREATE INDEX IF NOT EXISTS export_jobs_company_id_idx ON public.export_jobs(company_id);

-- Performance Indexes
CREATE INDEX IF NOT EXISTS inventory_last_sold_date_idx ON public.inventory(last_sold_date);

-- -------------------------------------------------------------------------------- --
--                                Triggers & Functions                                --
-- -------------------------------------------------------------------------------- --

-- Function: handle_new_user
-- Creates a company for a new user and updates their metadata.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  new_company_id uuid;
  user_company_name text;
BEGIN
  -- Extract company name from user metadata, defaulting if necessary
  user_company_name := NEW.raw_user_meta_data->>'company_name';
  IF user_company_name IS NULL OR trim(user_company_name) = '' THEN
    RAISE EXCEPTION 'Company name cannot be empty during signup.';
  END IF;

  -- Create a new company for the user
  INSERT INTO public.companies (name)
  VALUES (user_company_name)
  RETURNING id INTO new_company_id;

  -- Update the user's app_metadata with the new company_id and role
  -- This is the only safe way to modify user metadata from a trigger
  PERFORM auth.admin_update_user_by_id(
    NEW.id,
    jsonb_build_object(
        'app_metadata', jsonb_build_object(
            'company_id', new_company_id,
            'role', 'Owner'
        )
    )
  );

  RETURN NEW;
END;
$$;

-- Trigger: on_auth_user_created
-- Fires the handle_new_user function when a new user signs up.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE PROCEDURE public.handle_new_user();

-- Function: bump_updated_at
-- A generic trigger function to update the `updated_at` timestamp.
CREATE OR REPLACE FUNCTION public.bump_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- Function: increment_version
-- A trigger function to increment the version number and update timestamp.
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

-- Trigger: handle_inventory_update
-- Fires the increment_version function when inventory is updated.
DROP TRIGGER IF EXISTS handle_inventory_update ON public.inventory;
CREATE TRIGGER handle_inventory_update
  BEFORE UPDATE ON public.inventory
  FOR EACH ROW
  EXECUTE PROCEDURE public.increment_version();

-- Apply the generic updated_at trigger to other tables
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

DROP TRIGGER IF EXISTS trigger_locations_updated_at ON public.locations;
CREATE TRIGGER trigger_locations_updated_at
  BEFORE UPDATE ON public.locations
  FOR EACH ROW
  EXECUTE PROCEDURE public.bump_updated_at();

DROP TRIGGER IF EXISTS trigger_purchase_orders_updated_at ON public.purchase_orders;
CREATE TRIGGER trigger_purchase_orders_updated_at
  BEFORE UPDATE ON public.purchase_orders
  FOR EACH ROW
  EXECUTE PROCEDURE public.bump_updated_at();

-- Function: enforce_message_company_id
-- Ensures messages have the same company_id as their conversation.
CREATE OR REPLACE FUNCTION public.enforce_message_company_id()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    conversation_company_id uuid;
BEGIN
    SELECT company_id INTO conversation_company_id
    FROM public.conversations
    WHERE id = NEW.conversation_id;

    IF conversation_company_id IS NULL THEN
        RAISE EXCEPTION 'Conversation not found for message.';
    END IF;

    IF NEW.company_id != conversation_company_id THEN
        RAISE EXCEPTION 'Message company_id does not match conversation company_id.';
    END IF;

    RETURN NEW;
END;
$$;

-- Trigger: before_message_insert_or_update
-- Fires the enforcement function for messages.
DROP TRIGGER IF EXISTS before_message_insert_or_update ON public.messages;
CREATE TRIGGER before_message_insert_or_update
  BEFORE INSERT OR UPDATE ON public.messages
  FOR EACH ROW
  EXECUTE PROCEDURE public.enforce_message_company_id();


-- -------------------------------------------------------------------------------- --
--                                     RPC Functions                                --
-- -------------------------------------------------------------------------------- --

-- Function: auth.company_id
-- Helper to get the authenticated user's company_id.
CREATE OR REPLACE FUNCTION auth.company_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT (auth.jwt()->>'app_metadata')::jsonb->>'company_id'::text
$$;

-- Function: record_sale_transaction
-- The primary function for recording a sale and updating inventory atomically.
CREATE OR REPLACE FUNCTION public.record_sale_transaction(
  p_company_id   uuid,
  p_user_id      uuid,
  p_sale_items   jsonb,
  p_customer_name text     DEFAULT NULL,
  p_customer_email text    DEFAULT NULL,
  p_payment_method text    DEFAULT 'other',
  p_notes         text     DEFAULT NULL,
  p_external_id   text     DEFAULT NULL
)
RETURNS public.sales
LANGUAGE plpgsql
AS $$
DECLARE
  new_sale       public.sales;
  new_customer   uuid;
  total_amount_cents   bigint;
  tax_rate       numeric;
  tax_amount_cents     bigint;
  item_rec       record;
  tmp_table_name text := 'sale_items_tmp_'||replace(gen_random_uuid()::text,'-','');
BEGIN
  -- 1) Create the temp table
  EXECUTE format($fmt$
    CREATE TEMP TABLE %I (
      product_id   uuid,
      location_id  uuid,
      product_name text,
      quantity     integer,
      unit_price   integer,
      cost_at_time integer
    ) ON COMMIT DROP
  $fmt$, tmp_table_name);

  -- 2) Populate it from the JSON payload using jsonb_array_elements
  EXECUTE format($sql$
    INSERT INTO %I (product_id, product_name, quantity, unit_price, location_id, cost_at_time)
    SELECT
      (item->>'product_id')::uuid         AS product_id,
      p.name                               AS product_name,
      (item->>'quantity')::integer         AS quantity,
      (item->>'unit_price')::integer       AS unit_price,
      (item->>'location_id')::uuid         AS location_id,
      inv.cost                             AS cost_at_time
    FROM jsonb_array_elements($1) AS x(item)
    JOIN public.products p
      ON p.id = (x.item->>'product_id')::uuid
    JOIN public.inventory inv
      ON inv.product_id  = (x.item->>'product_id')::uuid
     AND inv.location_id = (x.item->>'location_id')::uuid
     AND inv.company_id  = $2
  $sql$, tmp_table_name)
  USING p_sale_items, p_company_id;

  -- 3) Stock checks
  FOR item_rec IN EXECUTE format('SELECT * FROM %I', tmp_table_name)
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM public.inventory
      WHERE company_id  = p_company_id
        AND product_id  = item_rec.product_id
        AND location_id = item_rec.location_id
        AND quantity    >= item_rec.quantity
    ) THEN
      RAISE EXCEPTION 'Insufficient stock for product % at location %',
        item_rec.product_id, item_rec.location_id;
    END IF;
  END LOOP;

  -- 4) Totals & tax
  EXECUTE format('SELECT SUM(quantity * unit_price) FROM %I', tmp_table_name)
  INTO total_amount_cents;

  SELECT cs.tax_rate INTO tax_rate
    FROM public.company_settings cs
   WHERE cs.company_id = p_company_id;
  tax_amount_cents := total_amount_cents * COALESCE(tax_rate,0);

  -- 5) Upsert customer
  IF p_customer_email IS NOT NULL THEN
    INSERT INTO public.customers(company_id, customer_name, email)
    VALUES (p_company_id, p_customer_name, p_customer_email)
    ON CONFLICT (company_id,email)
    DO UPDATE SET customer_name = EXCLUDED.customer_name
    RETURNING id INTO new_customer;
  END IF;

  -- 6) Insert sale header
  INSERT INTO public.sales (
    company_id, customer_id, customer_name, customer_email, total_amount, tax_amount,
    payment_method, notes, created_by, external_id
  )
  VALUES (
    p_company_id, new_customer, p_customer_name, p_customer_email, total_amount_cents, tax_amount_cents,
    p_payment_method, p_notes, p_user_id, p_external_id
  )
  RETURNING * INTO new_sale;

  -- 7) Items + ledger + inventory update
  FOR item_rec IN EXECUTE format('SELECT * FROM %I', tmp_table_name)
  LOOP
    INSERT INTO public.sale_items (
      sale_id, company_id, product_id, location_id, quantity, unit_price, cost_at_time
    )
    VALUES (
      new_sale.id, p_company_id, item_rec.product_id, item_rec.location_id, item_rec.quantity,
      item_rec.unit_price, item_rec.cost_at_time
    );

    UPDATE public.inventory
    SET
      quantity = quantity - item_rec.quantity,
      last_sold_date = CURRENT_DATE
    WHERE
      company_id  = p_company_id
      AND product_id  = item_rec.product_id
      AND location_id = item_rec.location_id;

    INSERT INTO public.inventory_ledger(
      company_id, product_id, location_id, change_type, quantity_change, new_quantity, related_id, notes, created_by
    )
    SELECT
      p_company_id, item_rec.product_id, item_rec.location_id, 'sale', -item_rec.quantity,
      i.quantity, new_sale.id, 'Sale #'||new_sale.sale_number, p_user_id
    FROM public.inventory i
    WHERE i.product_id = item_rec.product_id AND i.location_id = item_rec.location_id AND i.company_id = p_company_id;
  END LOOP;

  RETURN new_sale;
END;
$$;


-- -------------------------------------------------------------------------------- --
--                            Row Level Security (RLS)                                --
-- -------------------------------------------------------------------------------- --

-- Enable RLS on all tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reorder_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sale_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vendors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_catalogs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sync_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sync_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_feedback ENABLE ROW LEVEL SECURITY;

-- Enable RLS on Materialized Views
ALTER MATERIALIZED VIEW public.company_dashboard_metrics ENABLE ROW LEVEL SECURITY;
ALTER MATERIALIZED VIEW public.customer_analytics_metrics ENABLE ROW LEVEL SECURITY;

-- Policies
CREATE POLICY "Company data is isolated" ON public.companies FOR ALL USING (id = auth.company_id());
CREATE POLICY "Company access to products" ON public.products FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL);
CREATE POLICY "Company access to locations" ON public.locations FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL);
CREATE POLICY "Company access to inventory" ON public.inventory FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL);
CREATE POLICY "Company access to reorder rules" ON public.reorder_rules FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access to sales" ON public.sales FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access to sale items" ON public.sale_items FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access to customers" ON public.customers FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL);
CREATE POLICY "Company access to vendors" ON public.vendors FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL);
CREATE POLICY "Company access to POs" ON public.purchase_orders FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access to PO Items" ON public.purchase_order_items FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access to supplier catalogs" ON public.supplier_catalogs FOR ALL USING (EXISTS (SELECT 1 FROM public.vendors v WHERE v.id = supplier_id AND v.company_id = auth.company_id()));
CREATE POLICY "Users can manage their own conversations" ON public.conversations FOR ALL USING (user_id = auth.uid());
CREATE POLICY "Users can manage messages in their conversations" ON public.messages FOR ALL USING (conversation_id IN (SELECT id FROM public.conversations WHERE user_id = auth.uid()));
CREATE POLICY "Company access to settings" ON public.company_settings FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access to inventory ledger" ON public.inventory_ledger FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access to channel fees" ON public.channel_fees FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access to integrations" ON public.integrations FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access to sync logs" ON public.sync_logs FOR ALL USING (EXISTS (SELECT 1 FROM public.integrations i WHERE i.id = integration_id AND i.company_id = auth.company_id()));
CREATE POLICY "Company access to sync state" ON public.sync_state FOR ALL USING (EXISTS (SELECT 1 FROM public.integrations i WHERE i.id = integration_id AND i.company_id = auth.company_id()));
CREATE POLICY "Company access to export jobs" ON public.export_jobs FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access to audit log" ON public.audit_log FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access to user feedback" ON public.user_feedback FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access to dashboard metrics" ON public.company_dashboard_metrics FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access to customer analytics" ON public.customer_analytics_metrics FOR ALL USING (company_id = auth.company_id());


-- -------------------------------------------------------------------------------- --
--                           Storage & Asset Management                               --
-- -------------------------------------------------------------------------------- --

-- Create a bucket for public assets if it doesn't exist
INSERT INTO storage.buckets (id, name, public)
VALUES ('public_assets', 'public_assets', true)
ON CONFLICT (id) DO NOTHING;

-- Enable RLS on storage objects
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

-- Allow public read access to the 'public_assets' bucket
CREATE POLICY "Public read access for public_assets"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'public_assets');

-- -------------------------------------------------------------------------------- --
--                                  Finalization                                    --
-- -------------------------------------------------------------------------------- --

-- Define a function to refresh all materialized views
CREATE OR REPLACE FUNCTION public.refresh_materialized_views(
  p_company_id uuid,
  p_view_names text[] DEFAULT ARRAY['company_dashboard_metrics', 'customer_analytics_metrics']
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  IF 'company_dashboard_metrics' = ANY(p_view_names) THEN
    REFRESH MATERIALIZED VIEW public.company_dashboard_metrics;
  END IF;
  IF 'customer_analytics_metrics' = ANY(p_view_names) THEN
    REFRESH MATERIALIZED VIEW public.customer_analytics_metrics;
  END IF;
END;
$$;

-- Initial refresh of materialized views
SELECT public.refresh_materialized_views(null);

-- That's a wrap!
