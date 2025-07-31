
-- ===============================================================================================
--                                          IMPORTANT
--  This file is the single source of truth for the database schema.
--  It should be idempotent, meaning it can be run multiple times without causing errors.
--  This is achieved by using `CREATE OR REPLACE` for functions and `CREATE TABLE IF NOT EXISTS` for tables.
--  DO NOT REMOVE OR ALTER 'SECURITY DEFINER' on functions. It is required for RLS to work correctly.
-- ===============================================================================================

-- -----------------------------------------------------------------------------------------------
--                                             Enums
--  Define custom types to enforce consistency for specific fields like roles and statuses.
-- -----------------------------------------------------------------------------------------------

DO $$ BEGIN
    CREATE TYPE public.company_role AS ENUM ('Owner', 'Admin', 'Member');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE public.integration_platform AS ENUM ('shopify', 'woocommerce', 'amazon_fba');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE public.message_role AS ENUM ('user', 'assistant', 'tool');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE public.feedback_type AS ENUM ('helpful', 'unhelpful');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- -----------------------------------------------------------------------------------------------
--                                       Core Data Tables
--  These tables store the primary business data for companies, users, and inventory.
-- -----------------------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.companies (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    name text NOT NULL,
    owner_id uuid NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.company_users (
    user_id uuid NOT NULL,
    company_id uuid NOT NULL,
    role company_role DEFAULT 'Member'::company_role NOT NULL,
    PRIMARY KEY (user_id, company_id)
);

CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days int DEFAULT 90 NOT NULL,
    fast_moving_days int DEFAULT 30 NOT NULL,
    overstock_multiplier real DEFAULT 3 NOT NULL,
    high_value_threshold int DEFAULT 100000 NOT NULL, -- Stored in cents
    currency text DEFAULT 'USD' NOT NULL,
    tax_rate real DEFAULT 0 NOT NULL,
    timezone text DEFAULT 'UTC' NOT NULL,
    predictive_stock_days int DEFAULT 7 NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days int,
    notes text,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.products (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    description text,
    handle text,
    product_type text,
    tags text[],
    status text,
    image_url text,
    external_product_id text,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz,
    UNIQUE (company_id, external_product_id)
);

CREATE TABLE IF NOT EXISTS public.product_variants (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
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
    price int, -- Stored in cents
    compare_at_price int, -- Stored in cents
    cost int, -- Stored in cents
    inventory_quantity int DEFAULT 0 NOT NULL,
    location text,
    reorder_point int,
    reorder_quantity int,
    external_variant_id text,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz,
    UNIQUE (company_id, sku),
    UNIQUE (company_id, external_variant_id)
);

CREATE TABLE IF NOT EXISTS public.customers (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    external_customer_id text,
    name text,
    email text,
    phone text,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz,
    deleted_at timestamptz,
    UNIQUE (company_id, external_customer_id),
    UNIQUE (company_id, email)
);

CREATE TABLE IF NOT EXISTS public.orders (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number text NOT NULL,
    external_order_id text,
    customer_id uuid REFERENCES public.customers(id),
    financial_status text,
    fulfillment_status text,
    currency text,
    subtotal int NOT NULL,
    total_tax int,
    total_shipping int,
    total_discounts int,
    total_amount int NOT NULL,
    source_platform text,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz,
    UNIQUE (company_id, external_order_id),
    UNIQUE (company_id, order_number)
);

CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id uuid REFERENCES public.product_variants(id) ON DELETE SET NULL,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_name text,
    variant_title text,
    sku text,
    quantity int NOT NULL,
    price int NOT NULL,
    total_discount int,
    tax_amount int,
    cost_at_time int,
    external_line_item_id text
);

CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.suppliers(id),
    status text DEFAULT 'Draft'::text NOT NULL,
    po_number text NOT NULL,
    total_cost int NOT NULL,
    expected_arrival_date date,
    idempotency_key uuid UNIQUE,
    notes text,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz,
    UNIQUE (company_id, po_number)
);

CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    purchase_order_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    quantity int NOT NULL,
    cost int NOT NULL
);

CREATE TABLE IF NOT EXISTS public.refunds (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    refund_number text NOT NULL,
    status text NOT NULL,
    reason text,
    note text,
    total_amount int NOT NULL,
    created_by_user_id uuid REFERENCES public.users(id),
    external_refund_id text,
    created_at timestamptz DEFAULT now() NOT NULL,
    UNIQUE (company_id, refund_number)
);

-- -----------------------------------------------------------------------------------------------
--                                          AI & System Tables
--  These tables support the AI features, integrations, and internal system operations.
-- -----------------------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL,
    last_accessed_at timestamptz DEFAULT now() NOT NULL,
    is_starred boolean DEFAULT false NOT NULL
);

CREATE TABLE IF NOT EXISTS public.messages (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role message_role NOT NULL,
    content text NOT NULL,
    component text,
    "componentProps" jsonb,
    visualization jsonb,
    confidence real,
    assumptions text[],
    "isError" boolean,
    created_at timestamptz DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.integrations (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform integration_platform NOT NULL,
    shop_domain text,
    shop_name text,
    is_active boolean DEFAULT true NOT NULL,
    last_sync_at timestamptz,
    sync_status text,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz,
    UNIQUE (company_id, platform)
);

CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type text NOT NULL,
    quantity_change int NOT NULL,
    new_quantity int NOT NULL,
    related_id uuid,
    notes text,
    created_at timestamptz DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.channel_fees (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    channel_name text NOT NULL,
    fixed_fee int, -- in cents
    percentage_fee real,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz,
    UNIQUE (company_id, channel_name)
);

CREATE TABLE IF NOT EXISTS public.export_jobs (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    requested_by_user_id uuid NOT NULL REFERENCES auth.users(id),
    status text DEFAULT 'pending'::text NOT NULL,
    download_url text,
    expires_at timestamptz,
    error_message text,
    created_at timestamptz DEFAULT now() NOT NULL,
    completed_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.audit_log (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id uuid REFERENCES auth.users(id),
    action text NOT NULL,
    details jsonb,
    created_at timestamptz DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.feedback (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users(id),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    subject_id text NOT NULL,
    subject_type text NOT NULL,
    feedback feedback_type NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.webhook_events (
  id uuid default gen_random_uuid() primary key,
  integration_id uuid not null references public.integrations(id) on delete cascade,
  webhook_id text not null,
  created_at timestamptz default now() not null,
  unique (integration_id, webhook_id)
);


-- ===============================================================================================
--                                        Helper Functions
--  These functions provide useful utilities that can be used in policies and other queries.
-- ===============================================================================================

-- This function retrieves the company_id from the JWT's app_metadata.
-- It's a secure way to get the user's company without an extra DB query.
CREATE OR REPLACE FUNCTION public.get_company_id_for_user(p_user_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT (auth.jwt()->>'app_metadata')::jsonb ->> 'company_id' FROM auth.users WHERE id = p_user_id;
$$;


-- Check if a user has a required role in their company.
CREATE OR REPLACE FUNCTION public.check_user_permission(p_user_id uuid, p_required_role company_role)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  user_role company_role;
BEGIN
  SELECT role INTO user_role
  FROM public.company_users
  WHERE user_id = p_user_id
    AND company_id = public.get_company_id_for_user(p_user_id);

  IF user_role IS NULL THEN
    RETURN FALSE;
  END IF;

  RETURN CASE
    WHEN p_required_role = 'Owner' THEN user_role = 'Owner'
    WHEN p_required_role = 'Admin' THEN user_role IN ('Owner', 'Admin')
    ELSE TRUE -- 'Member' role has no special permissions beyond base access
  END;
END;
$$;


-- ===============================================================================================
--                                       Database Triggers
--  Automated functions that fire in response to database events (e.g., new user sign-up).
-- ===============================================================================================

-- This trigger automatically creates a company for a new user and links them as the owner.
-- This is critical for the multi-tenant structure of the application.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_company_id uuid;
  company_name text := new.raw_user_meta_data->>'company_name';
BEGIN
  -- Create a new company for the user
  INSERT INTO public.companies (name, owner_id)
  VALUES (COALESCE(company_name, 'My Company'), new.id)
  RETURNING id INTO new_company_id;

  -- Link the user to the new company as 'Owner'
  INSERT INTO public.company_users (user_id, company_id, role)
  VALUES (new.id, new_company_id, 'Owner');

  -- Update the user's app_metadata with the new company_id
  UPDATE auth.users
  SET app_metadata = app_metadata || jsonb_build_object('company_id', new_company_id)
  WHERE id = new.id;

  RETURN new;
END;
$$;


-- Drop the trigger if it exists to ensure it can be created cleanly.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Create the trigger to fire the handle_new_user function after a new user is created in Supabase Auth.
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- ===============================================================================================
--                                      Row-Level Security (RLS)
--  These policies are the foundation of the multi-tenant security model. They ensure that users
--  can only access data belonging to their own company.
-- ===============================================================================================

-- Generic policy function to check company membership
CREATE OR REPLACE FUNCTION public.is_member_of_company(p_company_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.company_users
    WHERE company_id = p_company_id
      AND user_id = auth.uid()
  );
$$;

-- Enable RLS on all tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refunds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;


-- Drop existing policies before creating new ones to ensure a clean state
DROP POLICY IF EXISTS "Allow all access to own company" ON public.companies;
DROP POLICY IF EXISTS "Allow users to view members of their own company" ON public.company_users;
DROP POLICY IF EXISTS "Allow access to own settings" ON public.company_settings;
DROP POLICY IF EXISTS "Allow access to own suppliers" ON public.suppliers;
DROP POLICY IF EXISTS "Allow access to own products" ON public.products;
DROP POLICY IF EXISTS "Allow access to own variants" ON public.product_variants;
DROP POLICY IF EXISTS "Allow access to own customers" ON public.customers;
DROP POLICY IF EXISTS "Allow access to own orders" ON public.orders;
DROP POLICY IF EXISTS "Allow access to own order line items" ON public.order_line_items;
DROP POLICY IF EXISTS "Allow access to own purchase orders" ON public.purchase_orders;
DROP POLICY IF EXISTS "Allow access to own PO line items" ON public.purchase_order_line_items;
DROP POLICY IF EXISTS "Allow access to own refunds" ON public.refunds;
DROP POLICY IF EXISTS "Allow access to own conversations" ON public.conversations;
DROP POLICY IF EXISTS "Allow access to own messages" ON public.messages;
DROP POLICY IF EXISTS "Allow access to own integrations" ON public.integrations;
DROP POLICY IF EXISTS "Allow access to own inventory ledger" ON public.inventory_ledger;
DROP POLICY IF EXISTS "Allow access to own channel fees" ON public.channel_fees;
DROP POLICY IF EXISTS "Allow access to own export jobs" ON public.export_jobs;
DROP POLICY IF EXISTS "Allow access to own audit logs" ON public.audit_log;
DROP POLICY IF EXISTS "Allow access to own feedback" ON public.feedback;
DROP POLICY IF EXISTS "Allow access to own webhook events" ON public.webhook_events;

-- Policies for tables with a direct company_id column
CREATE POLICY "Allow all access to own company" ON public.companies FOR ALL USING (id = (select get_company_id_for_user(auth.uid())));
CREATE POLICY "Allow users to view members of their own company" ON public.company_users FOR SELECT USING (company_id = (select get_company_id_for_user(auth.uid())));
CREATE POLICY "Allow access to own settings" ON public.company_settings FOR ALL USING (company_id = (select get_company_id_for_user(auth.uid())));
CREATE POLICY "Allow access to own suppliers" ON public.suppliers FOR ALL USING (company_id = (select get_company_id_for_user(auth.uid())));
CREATE POLICY "Allow access to own products" ON public.products FOR ALL USING (company_id = (select get_company_id_for_user(auth.uid())));
CREATE POLICY "Allow access to own variants" ON public.product_variants FOR ALL USING (company_id = (select get_company_id_for_user(auth.uid())));
CREATE POLICY "Allow access to own customers" ON public.customers FOR ALL USING (company_id = (select get_company_id_for_user(auth.uid())));
CREATE POLICY "Allow access to own orders" ON public.orders FOR ALL USING (company_id = (select get_company_id_for_user(auth.uid())));
CREATE POLICY "Allow access to own order line items" ON public.order_line_items FOR ALL USING (company_id = (select get_company_id_for_user(auth.uid())));
CREATE POLICY "Allow access to own purchase orders" ON public.purchase_orders FOR ALL USING (company_id = (select get_company_id_for_user(auth.uid())));
CREATE POLICY "Allow access to own PO line items" ON public.purchase_order_line_items FOR ALL USING (company_id = (select get_company_id_for_user(auth.uid())));
CREATE POLICY "Allow access to own refunds" ON public.refunds FOR ALL USING (company_id = (select get_company_id_for_user(auth.uid())));
CREATE POLICY "Allow access to own integrations" ON public.integrations FOR ALL USING (company_id = (select get_company_id_for_user(auth.uid())));
CREATE POLICY "Allow access to own inventory ledger" ON public.inventory_ledger FOR ALL USING (company_id = (select get_company_id_for_user(auth.uid())));
CREATE POLICY "Allow access to own channel fees" ON public.channel_fees FOR ALL USING (company_id = (select get_company_id_for_user(auth.uid())));
CREATE POLICY "Allow access to own audit logs" ON public.audit_log FOR ALL USING (company_id = (select get_company_id_for_user(auth.uid())));
CREATE POLICY "Allow access to own feedback" ON public.feedback FOR ALL USING (company_id = (select get_company_id_for_user(auth.uid())));

-- User-specific policies
CREATE POLICY "Allow access to own conversations" ON public.conversations FOR ALL USING (user_id = auth.uid());
CREATE POLICY "Allow access to own messages" ON public.messages FOR ALL USING (company_id = (select get_company_id_for_user(auth.uid())));
CREATE POLICY "Allow access to own export jobs" ON public.export_jobs FOR ALL USING (requested_by_user_id = auth.uid());

-- Policy for webhook_events based on the linked integration
CREATE POLICY "Allow access to own webhook events" ON public.webhook_events FOR SELECT
USING (
    is_member_of_company(
        (SELECT company_id FROM public.integrations WHERE id = integration_id)
    )
);


-- ===============================================================================================
--                                      Database Views
--  Simplified, pre-joined, or aggregated versions of tables for easier and more performant querying.
--  They are read-only and help encapsulate complex logic.
-- ===============================================================================================

-- A unified view of product variants with their parent product details.
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.id,
    pv.product_id,
    pv.company_id,
    p.title as product_title,
    pv.title as variant_title,
    p.status as product_status,
    p.image_url,
    p.product_type,
    pv.sku,
    pv.price,
    pv.cost,
    pv.inventory_quantity,
    pv.location,
    pv.barcode,
    pv.compare_at_price,
    pv.option1_name,
    pv.option1_value,
    pv.option2_name,
    pv.option2_value,
    pv.option3_name,
    pv.option3_value,
    pv.supplier_id,
    pv.reorder_point,
    pv.reorder_quantity,
    pv.external_variant_id,
    pv.created_at,
    pv.updated_at
FROM
    public.product_variants pv
JOIN
    public.products p ON pv.product_id = p.id;


-- A view for all orders with customer email for easy searching.
CREATE OR REPLACE VIEW public.orders_view AS
SELECT
    o.*,
    c.email as customer_email
FROM
    public.orders o
LEFT JOIN
    public.customers c ON o.customer_id = c.id;

-- A view for all customers with their total orders and spend.
CREATE OR REPLACE VIEW public.customers_view AS
SELECT
    c.*,
    (SELECT COUNT(*) FROM public.orders o WHERE o.customer_id = c.id) as total_orders,
    (SELECT SUM(o.total_amount) FROM public.orders o WHERE o.customer_id = c.id) as total_spent
FROM
    public.customers c;


-- A view for all purchase orders with supplier name for easy display.
CREATE OR REPLACE VIEW public.purchase_orders_view AS
SELECT
  po.*,
  s.name as supplier_name,
  (
    SELECT json_agg(json_build_object(
      'id', poli.id,
      'product_name', p.title,
      'sku', pv.sku,
      'quantity', poli.quantity,
      'cost', poli.cost
    ))
    FROM public.purchase_order_line_items poli
    JOIN public.product_variants pv ON poli.variant_id = pv.id
    JOIN public.products p ON pv.product_id = p.id
    WHERE poli.purchase_order_id = po.id
  ) as line_items
FROM public.purchase_orders po
LEFT JOIN public.suppliers s ON po.supplier_id = s.id;


-- A view for audit logs that joins user email for readability.
CREATE OR REPLACE VIEW public.audit_log_view AS
SELECT
    al.id,
    al.created_at,
    al.company_id,
    al.action,
    al.details,
    u.email AS user_email
FROM
    public.audit_log al
LEFT JOIN
    auth.users u ON al.user_id = u.id;
    

-- A view for user feedback that joins message content for context.
CREATE OR REPLACE VIEW public.feedback_view AS
SELECT
    f.id,
    f.created_at,
    f.company_id,
    f.feedback,
    u.email AS user_email,
    m.content AS assistant_message_content,
    (
        SELECT prev_msg.content
        FROM public.messages prev_msg
        WHERE prev_msg.conversation_id = m.conversation_id
          AND prev_msg.created_at < m.created_at
        ORDER BY prev_msg.created_at DESC
        LIMIT 1
    ) AS user_message_content
FROM
    public.feedback f
JOIN
    auth.users u ON f.user_id = u.id
JOIN
    public.messages m ON f.subject_id = m.id AND f.subject_type = 'message';

-- ===============================================================================================
--                                  Materialized Views
--  These are pre-computed tables that store the result of a query. They are used for expensive
--  analytics queries that don't need to be real-time. This significantly speeds up the dashboard.
-- ===============================================================================================

CREATE MATERIALIZED VIEW IF NOT EXISTS public.daily_sales_stats AS
SELECT
    company_id,
    date(created_at) AS sale_date,
    SUM(total_amount) AS total_revenue,
    COUNT(id) AS total_sales,
    COUNT(DISTINCT customer_id) AS total_customers
FROM
    public.orders
GROUP BY
    company_id, date(created_at);

CREATE MATERIALIZED VIEW IF NOT EXISTS public.product_sales_stats AS
SELECT
    oli.company_id,
    oli.sku,
    oli.variant_id,
    p.id as product_id,
    p.title as product_name,
    p.image_url,
    SUM(oli.quantity) AS total_quantity_sold,
    SUM(oli.price * oli.quantity) AS total_revenue,
    SUM(oli.cost_at_time * oli.quantity) AS total_cogs
FROM
    public.order_line_items oli
JOIN
    public.product_variants pv ON oli.variant_id = pv.id
JOIN
    public.products p ON pv.product_id = p.id
GROUP BY
    oli.company_id, oli.sku, oli.variant_id, p.id;

-- Function to refresh all materialized views for a specific company
CREATE OR REPLACE FUNCTION public.refresh_all_matviews(p_company_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  -- We can't refresh concurrently on views that don't have a unique index
  -- For simplicity, we use a standard refresh. This will lock the view briefly.
  REFRESH MATERIALIZED VIEW public.daily_sales_stats;
  REFRESH MATERIALIZED VIEW public.product_sales_stats;
END;
$$;


-- ===============================================================================================
--                                  Functions for Indexes
--  These functions allow us to create indexes on expressions, which can dramatically speed up
--  queries that filter or sort on computed values (like JSONB properties).
-- ===============================================================================================

-- Safely get a text value from a JSONB object.
CREATE OR REPLACE FUNCTION public.jsonb_get_text(data jsonb, key text)
RETURNS text AS $$
BEGIN
  RETURN data->>key;
EXCEPTION
  WHEN others THEN
    RETURN NULL;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Safely get an integer value from a JSONB object.
CREATE OR REPLACE FUNCTION public.jsonb_get_int(data jsonb, key text)
RETURNS int AS $$
BEGIN
  RETURN (data->>key)::int;
EXCEPTION
  WHEN others THEN
    RETURN NULL;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Safely get a float value from a JSONB object.
CREATE OR REPLACE FUNCTION public.jsonb_get_float(data jsonb, key text)
RETURNS float AS $$
BEGIN
  RETURN (data->>key)::float;
EXCEPTION
  WHEN others THEN
    RETURN NULL;
END;
$$ LANGUAGE plpgsql IMMUTABLE;


-- ===============================================================================================
--                                            Indexes
--  Indexes are crucial for database performance. They speed up data retrieval operations.
-- ===============================================================================================

-- General purpose indexes on foreign keys and frequently queried columns
CREATE INDEX IF NOT EXISTS idx_company_users_company_id ON public.company_users(company_id);
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_company_id_sku ON public.product_variants(company_id, sku);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_orders_company_id_created_at ON public.orders(company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON public.order_line_items(variant_id);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_company_id ON public.purchase_orders(company_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id ON public.inventory_ledger(variant_id);

-- GIN indexes for tsvector full-text search (if implemented) and JSONB columns
CREATE INDEX IF NOT EXISTS idx_products_gin_tags ON public.products USING gin(tags);
CREATE INDEX IF NOT EXISTS idx_messages_visualization ON public.messages USING gin(visualization);
CREATE INDEX IF NOT EXISTS idx_messages_component_props ON public.messages USING gin("componentProps");

-- Indexes on materialized views for fast dashboard loading
CREATE UNIQUE INDEX IF NOT EXISTS idx_daily_sales_stats_unique ON public.daily_sales_stats(company_id, sale_date);
CREATE UNIQUE INDEX IF NOT EXISTS idx_product_sales_stats_unique ON public.product_sales_stats(company_id, variant_id);

-- Indexes for audit log and feedback tables
CREATE INDEX IF NOT EXISTS idx_audit_log_company_id_created_at ON public.audit_log(company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_feedback_subject ON public.feedback(subject_id, subject_type);
