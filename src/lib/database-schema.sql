
-- Enable UUID extension
create extension if not exists "uuid-ossp" with schema extensions;

-- Set timezone
SET TIMEZONE='UTC';

-- #############################################################################
-- ############################### TABLES ######################################
-- #############################################################################

-- Companies Table
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    name text NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT companies_pkey PRIMARY KEY (id)
);

-- Company Settings Table
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid NOT NULL,
    dead_stock_days integer NOT NULL DEFAULT 90,
    fast_moving_days integer NOT NULL DEFAULT 30,
    predictive_stock_days integer NOT NULL DEFAULT 7,
    currency text DEFAULT 'USD'::text,
    timezone text DEFAULT 'UTC'::text,
    tax_rate numeric DEFAULT 0,
    custom_rules jsonb,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone,
    subscription_status text DEFAULT 'trial'::text,
    subscription_plan text DEFAULT 'starter'::text,
    subscription_expires_at timestamp with time zone,
    stripe_customer_id text,
    stripe_subscription_id text,
    promo_sales_lift_multiplier real NOT NULL DEFAULT 2.5,
    overstock_multiplier integer NOT NULL DEFAULT 3,
    high_value_threshold integer NOT NULL DEFAULT 1000,
    CONSTRAINT company_settings_pkey PRIMARY KEY (company_id),
    CONSTRAINT company_settings_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);

-- Users Table (specific to app, separate from auth.users)
CREATE TABLE IF NOT EXISTS public.users (
    id uuid NOT NULL,
    company_id uuid NOT NULL,
    email text,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    role text DEFAULT 'member'::text,
    CONSTRAINT users_pkey PRIMARY KEY (id),
    CONSTRAINT users_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT users_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE
);

-- Suppliers Table
CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT suppliers_pkey PRIMARY KEY (id),
    CONSTRAINT suppliers_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);

-- Products Table
CREATE TABLE IF NOT EXISTS public.products (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    title text NOT NULL,
    description text,
    handle text,
    product_type text,
    tags text[],
    status text,
    image_url text,
    external_product_id text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone,
    fts_document tsvector GENERATED ALWAYS AS (to_tsvector('english'::regconfig, (COALESCE(title, ''::text) || ' '::text) || COALESCE(description, ''::text))) STORED,
    CONSTRAINT products_pkey PRIMARY KEY (id),
    CONSTRAINT products_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT products_company_id_external_product_id_key UNIQUE (company_id, external_product_id)
);

-- Product Variants Table
CREATE TABLE IF NOT EXISTS public.product_variants (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    product_id uuid NOT NULL,
    company_id uuid NOT NULL,
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
    inventory_quantity integer NOT NULL DEFAULT 0,
    external_variant_id text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    location text,
    CONSTRAINT product_variants_pkey PRIMARY KEY (id),
    CONSTRAINT product_variants_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT product_variants_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE,
    CONSTRAINT product_variants_company_id_sku_key UNIQUE (company_id, sku)
);


-- Customers Table
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    customer_name text NOT NULL,
    email text,
    total_orders integer DEFAULT 0,
    total_spent integer DEFAULT 0,
    first_order_date date,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT customers_pkey PRIMARY KEY (id),
    CONSTRAINT customers_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);

-- Orders Table
CREATE TABLE IF NOT EXISTS public.orders (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL,
    order_number text NOT NULL,
    external_order_id text,
    customer_id uuid,
    status text NOT NULL DEFAULT 'pending'::text,
    financial_status text DEFAULT 'pending'::text,
    fulfillment_status text DEFAULT 'unfulfilled'::text,
    currency text DEFAULT 'USD'::text,
    subtotal integer NOT NULL DEFAULT 0,
    total_tax integer DEFAULT 0,
    total_shipping integer DEFAULT 0,
    total_discounts integer DEFAULT 0,
    total_amount integer NOT NULL,
    source_platform text,
    source_name text,
    tags text[],
    notes text,
    cancelled_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT orders_pkey PRIMARY KEY (id),
    CONSTRAINT orders_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE SET NULL,
    CONSTRAINT orders_company_id_external_order_id_key UNIQUE (company_id, external_order_id)
);

-- Order Line Items Table
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    order_id uuid NOT NULL,
    variant_id uuid,
    company_id uuid NOT NULL,
    product_name text NOT NULL,
    variant_title text,
    sku text,
    quantity integer NOT NULL,
    price integer NOT NULL,
    total_discount integer DEFAULT 0,
    tax_amount integer DEFAULT 0,
    cost_at_time integer,
    external_line_item_id text,
    CONSTRAINT order_line_items_pkey PRIMARY KEY (id),
    CONSTRAINT order_line_items_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT order_line_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE,
    CONSTRAINT order_line_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE SET NULL
);


-- Purchase Orders Table
CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    supplier_id uuid,
    status text NOT NULL DEFAULT 'Draft'::text,
    po_number text NOT NULL,
    total_cost integer NOT NULL,
    expected_arrival_date date,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    idempotency_key uuid,
    CONSTRAINT purchase_orders_pkey PRIMARY KEY (id),
    CONSTRAINT purchase_orders_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT purchase_orders_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) ON DELETE SET NULL
);

-- Purchase Order Line Items Table
CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    purchase_order_id uuid NOT NULL,
    variant_id uuid NOT NULL,
    quantity integer NOT NULL,
    cost integer NOT NULL,
    CONSTRAINT purchase_order_line_items_pkey PRIMARY KEY (id),
    CONSTRAINT purchase_order_line_items_purchase_order_id_fkey FOREIGN KEY (purchase_order_id) REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    CONSTRAINT purchase_order_line_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE CASCADE
);

-- Inventory Ledger Table
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL,
    variant_id uuid NOT NULL,
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid,
    notes text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT inventory_ledger_pkey PRIMARY KEY (id),
    CONSTRAINT inventory_ledger_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT inventory_ledger_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE CASCADE
);

-- Integrations Table
CREATE TABLE IF NOT EXISTS public.integrations (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    platform text NOT NULL,
    shop_domain text,
    shop_name text,
    is_active boolean DEFAULT false,
    last_sync_at timestamp with time zone,
    sync_status text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone,
    CONSTRAINT integrations_pkey PRIMARY KEY (id),
    CONSTRAINT integrations_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT integrations_company_id_platform_key UNIQUE (company_id, platform)
);

-- Webhook Events Table
CREATE TABLE IF NOT EXISTS public.webhook_events (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    integration_id uuid NOT NULL,
    webhook_id text NOT NULL,
    processed_at timestamp with time zone DEFAULT now(),
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT webhook_events_pkey PRIMARY KEY (id),
    CONSTRAINT webhook_events_integration_id_fkey FOREIGN KEY (integration_id) REFERENCES public.integrations(id) ON DELETE CASCADE,
    CONSTRAINT webhook_events_integration_id_webhook_id_key UNIQUE (integration_id, webhook_id)
);


-- Conversations Table
CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL,
    company_id uuid NOT NULL,
    title text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    last_accessed_at timestamp with time zone DEFAULT now(),
    is_starred boolean DEFAULT false,
    CONSTRAINT conversations_pkey PRIMARY KEY (id),
    CONSTRAINT conversations_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT conversations_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);

-- Messages Table
CREATE TABLE IF NOT EXISTS public.messages (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    conversation_id uuid NOT NULL,
    company_id uuid NOT NULL,
    role text NOT NULL,
    content text,
    component text,
    component_props jsonb,
    visualization jsonb,
    confidence numeric,
    assumptions text[],
    created_at timestamp with time zone DEFAULT now(),
    is_error boolean DEFAULT false,
    CONSTRAINT messages_pkey PRIMARY KEY (id),
    CONSTRAINT messages_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT messages_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.conversations(id) ON DELETE CASCADE
);

-- #############################################################################
-- ########################### VIEWS & INDEXES #################################
-- #############################################################################

CREATE INDEX IF NOT EXISTS products_company_id_idx ON public.products(company_id);
CREATE INDEX IF NOT EXISTS products_fts_document_idx ON public.products USING gin (fts_document);
CREATE INDEX IF NOT EXISTS product_variants_company_id_idx ON public.product_variants(company_id);
CREATE INDEX IF NOT EXISTS product_variants_product_id_idx ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS orders_company_id_idx ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS orders_created_at_idx ON public.orders(created_at DESC);
CREATE INDEX IF NOT EXISTS order_line_items_order_id_idx ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS order_line_items_variant_id_idx ON public.order_line_items(variant_id);
CREATE INDEX IF NOT EXISTS inventory_ledger_variant_id_idx ON public.inventory_ledger(variant_id);
CREATE INDEX IF NOT EXISTS inventory_ledger_created_at_idx ON public.inventory_ledger(created_at DESC);


-- View for combining product and variant details
CREATE OR REPLACE VIEW public.product_variants_with_details AS
 SELECT
    pv.id,
    pv.product_id,
    pv.company_id,
    pv.sku,
    pv.title,
    pv.price,
    pv.cost,
    pv.inventory_quantity,
    pv.external_variant_id,
    pv.location,
    p.title AS product_title,
    p.status AS product_status,
    p.product_type,
    p.image_url
   FROM public.product_variants pv
     LEFT JOIN public.products p ON pv.product_id = p.id;


-- #############################################################################
-- ######################### FUNCTIONS & TRIGGERS ##############################
-- #############################################################################

-- Function to create a company and assign it to the new user
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  new_company_id uuid;
BEGIN
  -- Create a new company for the user
  INSERT INTO public.companies (name)
  VALUES (new.raw_app_meta_data->>'company_name')
  RETURNING id INTO new_company_id;

  -- Insert a corresponding entry in the public.users table
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (new.id, new_company_id, new.email, 'Owner');
  
  -- Update the user's app_metadata with the new company_id and role
  UPDATE auth.users
  SET raw_app_meta_data = new.raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'role', 'Owner')
  WHERE id = new.id;
  
  RETURN new;
END;
$$;

-- Trigger to call the function after a new user signs up
CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();


-- Function to get user role within a company
CREATE OR REPLACE FUNCTION public.get_user_role(p_user_id uuid)
RETURNS text
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN (
    SELECT role FROM public.users
    WHERE id = p_user_id
  );
END;
$$;


-- #############################################################################
-- ##################### ROW LEVEL SECURITY (RLS) ##############################
-- #############################################################################

-- Enable RLS for all relevant tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;


-- Function to get the current user's company_id from their session claims
CREATE OR REPLACE FUNCTION public.get_my_company_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid;
$$;

-- Function to check if the current user is an admin or owner
CREATE OR REPLACE FUNCTION public.is_admin_or_owner()
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'role', '') IN ('Admin', 'Owner');
$$;

-- Policies for tables with direct company_id
-- We create a single policy for SELECT and separate, stricter policies for write operations.

DO $$
DECLARE
    t_name TEXT;
BEGIN
    FOR t_name IN
        SELECT table_name FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name IN (
            'companies', 'company_settings', 'users', 'suppliers', 'products',
            'product_variants', 'customers', 'orders', 'order_line_items',
            'purchase_orders', 'purchase_order_line_items', 'inventory_ledger',
            'integrations', 'conversations', 'messages'
        )
    LOOP
        -- Drop existing policies to prevent conflicts
        EXECUTE format('DROP POLICY IF EXISTS "Allow full access for company members" ON public.%I;', t_name);
        EXECUTE format('DROP POLICY IF EXISTS "Allow read access for company members" ON public.%I;', t_name);
        EXECUTE format('DROP POLICY IF EXISTS "Allow write access for admins and owners" ON public.%I;', t_name);

        -- SELECT policy (all roles can read)
        EXECUTE format('CREATE POLICY "Allow read access for company members" ON public.%I FOR SELECT USING (company_id = public.get_my_company_id());', t_name);

        -- INSERT/UPDATE/DELETE policies (only Admin/Owner can write)
        EXECUTE format('CREATE POLICY "Allow write access for admins and owners" ON public.%I FOR ALL USING (company_id = public.get_my_company_id()) WITH CHECK (public.is_admin_or_owner());', t_name);
    END LOOP;
END;
$$;

-- Special policy for webhook_events table, which is linked via integration_id
DROP POLICY IF EXISTS "Allow read access for company members via integration" ON public.webhook_events;
CREATE POLICY "Allow read access for company members via integration"
ON public.webhook_events FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.integrations
    WHERE integrations.id = webhook_events.integration_id
    AND integrations.company_id = public.get_my_company_id()
  )
);
