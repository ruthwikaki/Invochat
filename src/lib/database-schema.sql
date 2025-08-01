-- ============================================================================
-- ARVO DATABASE SCHEMA
-- ============================================================================
-- This script is idempotent and can be run safely on new or existing databases.

-- ============================================================================
-- EXTENSIONS
-- ============================================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "vector";

-- ============================================================================
-- TYPES
-- ============================================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'company_role') THEN
        CREATE TYPE public.company_role AS ENUM ('Owner', 'Admin', 'Member');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'integration_platform') THEN
        CREATE TYPE public.integration_platform AS ENUM ('shopify', 'woocommerce', 'amazon_fba');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'message_role') THEN
        CREATE TYPE public.message_role AS ENUM ('user', 'assistant', 'tool');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'feedback_type') THEN
        CREATE TYPE public.feedback_type AS ENUM ('helpful', 'unhelpful');
    END IF;
END$$;


-- ============================================================================
-- TABLES
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    name text NOT NULL,
    owner_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.company_users (
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role public.company_role NOT NULL DEFAULT 'Member',
    PRIMARY KEY (company_id, user_id)
);

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
    updated_at timestamptz
);
CREATE UNIQUE INDEX IF NOT EXISTS products_company_id_external_product_id_idx ON public.products(company_id, external_product_id);


CREATE TABLE IF NOT EXISTS public.product_variants (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
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
    reorder_point integer,
    reorder_quantity integer,
    supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL,
    location text,
    external_variant_id text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz
);
CREATE UNIQUE INDEX IF NOT EXISTS product_variants_company_id_sku_idx ON public.product_variants(company_id, sku);


CREATE TABLE IF NOT EXISTS public.orders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number text NOT NULL,
    external_order_id text,
    customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
    financial_status text DEFAULT 'pending',
    fulfillment_status text DEFAULT 'unfulfilled',
    currency text DEFAULT 'USD',
    subtotal integer NOT NULL DEFAULT 0,
    total_tax integer DEFAULT 0,
    total_shipping integer DEFAULT 0,
    total_discounts integer DEFAULT 0,
    total_amount integer NOT NULL,
    source_platform text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id uuid REFERENCES public.product_variants(id) ON DELETE SET NULL,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_name text,
    variant_title text,
    sku text,
    quantity integer NOT NULL,
    price integer NOT NULL,
    total_discount integer DEFAULT 0,
    tax_amount integer DEFAULT 0,
    cost_at_time integer,
    external_line_item_id text
);

CREATE TABLE IF NOT EXISTS public.customers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text,
    email text,
    phone text,
    external_customer_id text,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz
);


CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);


CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL,
    status text NOT NULL DEFAULT 'Draft',
    po_number text NOT NULL,
    total_cost integer NOT NULL,
    expected_arrival_date date,
    idempotency_key uuid,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    purchase_order_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    quantity integer NOT NULL,
    cost integer NOT NULL
);

CREATE TABLE IF NOT EXISTS public.integrations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform public.integration_platform NOT NULL,
    shop_domain text,
    shop_name text,
    is_active boolean DEFAULT false,
    last_sync_at timestamptz,
    sync_status text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);
CREATE UNIQUE INDEX IF NOT EXISTS integrations_company_id_platform_idx ON public.integrations(company_id, platform);

CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    created_at timestamptz DEFAULT now(),
    last_accessed_at timestamptz DEFAULT now(),
    is_starred boolean DEFAULT false
);


CREATE TABLE IF NOT EXISTS public.messages (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role public.message_role NOT NULL,
    content text,
    component text,
    componentProps jsonb,
    visualization jsonb,
    confidence numeric,
    assumptions text[],
    isError boolean DEFAULT false,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.audit_log (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    action text NOT NULL,
    details jsonb,
    created_at timestamptz DEFAULT now()
);


CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    fast_moving_days integer NOT NULL DEFAULT 30,
    overstock_multiplier integer NOT NULL DEFAULT 3,
    high_value_threshold integer NOT NULL DEFAULT 100000,
    predictive_stock_days integer NOT NULL DEFAULT 7,
    currency text DEFAULT 'USD',
    timezone text DEFAULT 'UTC',
    tax_rate numeric DEFAULT 0,
    alert_settings jsonb DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);


CREATE TABLE IF NOT EXISTS public.channel_fees (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    channel_name text NOT NULL,
    fixed_fee integer,
    percentage_fee numeric,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, channel_name)
);

CREATE TABLE IF NOT EXISTS public.feedback (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    subject_id text NOT NULL,
    subject_type text NOT NULL,
    feedback public.feedback_type NOT NULL,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.export_jobs (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    requested_by_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    status text NOT NULL DEFAULT 'pending',
    download_url text,
    expires_at timestamptz,
    error_message text,
    created_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.imports (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    import_type text NOT NULL,
    file_name text NOT NULL,
    total_rows integer,
    processed_rows integer,
    failed_rows integer,
    status text NOT NULL DEFAULT 'pending',
    errors jsonb,
    summary jsonb,
    created_at timestamptz DEFAULT now(),
    completed_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.webhook_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id text NOT NULL,
    created_at timestamptz DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS webhook_events_integration_id_webhook_id_idx ON public.webhook_events(integration_id, webhook_id);

-- ============================================================================
-- FUNCTIONS & TRIGGERS
-- ============================================================================
DROP FUNCTION IF EXISTS public.handle_new_user();
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    company_id_to_set uuid;
    user_company_name text;
BEGIN
    -- Sanitize and get company name, providing a fallback
    user_company_name := BTRIM(REGEXP_REPLACE(new.raw_user_meta_data->>'company_name', '[^\w\s-]', '', 'g'));
    IF user_company_name IS NULL OR user_company_name = '' THEN
        user_company_name := new.email || '''s Company';
    END IF;

    -- Create a new company for the new user
    INSERT INTO public.companies (name, owner_id)
    VALUES (user_company_name, new.id)
    RETURNING id INTO company_id_to_set;

    -- If company creation was successful, link the user to the new company
    IF company_id_to_set IS NOT NULL THEN
        INSERT INTO public.company_users (company_id, user_id, role)
        VALUES (company_id_to_set, new.id, 'Owner');
    ELSE
        -- This block should ideally never be reached if the INSERT succeeded
        RAISE EXCEPTION 'Failed to create a company for the new user';
    END IF;

    -- Update the user's app_metadata with the new company_id
    UPDATE auth.users
    SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id_to_set)
    WHERE id = new.id;
    
    RETURN new;
END;
$$;

-- Drop trigger if it exists
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Create the trigger to fire after a new user is created in auth.users
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();


DROP FUNCTION IF EXISTS public.get_company_id_for_user(uuid);
CREATE OR REPLACE FUNCTION public.get_company_id_for_user()
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
BEGIN
  -- This function now securely gets the company_id directly from the JWT.
  -- This is more performant and avoids the recursive loop.
  RETURN (SELECT NULLIF(current_setting('request.jwt.claims', true)::jsonb->'app_metadata'->>'company_id', '')::uuid);
END;
$$;

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

-- Helper function to drop a policy if it exists
CREATE OR REPLACE FUNCTION drop_policy_if_exists(table_name_param text, policy_name_param text)
RETURNS void AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE tablename = table_name_param AND policyname = policy_name_param
    ) THEN
        EXECUTE 'DROP POLICY ' || quote_ident(policy_name_param) || ' ON ' || quote_ident(table_name_param);
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Generic policy for most tables
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.imports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;


-- Drop old policies if they exist, then create new ones
SELECT drop_policy_if_exists('products', 'User can access their own company data');
CREATE POLICY "User can access their own company data" ON public.products FOR ALL
USING (company_id = public.get_company_id_for_user())
WITH CHECK (company_id = public.get_company_id_for_user());

SELECT drop_policy_if_exists('product_variants', 'User can access their own company data');
CREATE POLICY "User can access their own company data" ON public.product_variants FOR ALL
USING (company_id = public.get_company_id_for_user())
WITH CHECK (company_id = public.get_company_id_for_user());

SELECT drop_policy_if_exists('orders', 'User can access their own company data');
CREATE POLICY "User can access their own company data" ON public.orders FOR ALL
USING (company_id = public.get_company_id_for_user())
WITH CHECK (company_id = public.get_company_id_for_user());

SELECT drop_policy_if_exists('order_line_items', 'User can access their own company data');
CREATE POLICY "User can access their own company data" ON public.order_line_items FOR ALL
USING (company_id = public.get_company_id_for_user())
WITH CHECK (company_id = public.get_company_id_for_user());

SELECT drop_policy_if_exists('customers', 'User can access their own company data');
CREATE POLICY "User can access their own company data" ON public.customers FOR ALL
USING (company_id = public.get_company_id_for_user())
WITH CHECK (company_id = public.get_company_id_for_user());

SELECT drop_policy_if_exists('suppliers', 'User can access their own company data');
CREATE POLICY "User can access their own company data" ON public.suppliers FOR ALL
USING (company_id = public.get_company_id_for_user())
WITH CHECK (company_id = public.get_company_id_for_user());

SELECT drop_policy_if_exists('purchase_orders', 'User can access their own company data');
CREATE POLICY "User can access their own company data" ON public.purchase_orders FOR ALL
USING (company_id = public.get_company_id_for_user())
WITH CHECK (company_id = public.get_company_id_for_user());

SELECT drop_policy_if_exists('purchase_order_line_items', 'User can access their own company data');
CREATE POLICY "User can access their own company data" ON public.purchase_order_line_items FOR ALL
USING (company_id = public.get_company_id_for_user())
WITH CHECK (company_id = public.get_company_id_for_user());

SELECT drop_policy_if_exists('integrations', 'User can access their own company data');
CREATE POLICY "User can access their own company data" ON public.integrations FOR ALL
USING (company_id = public.get_company_id_for_user())
WITH CHECK (company_id = public.get_company_id_for_user());

SELECT drop_policy_if_exists('inventory_ledger', 'User can access their own company data');
CREATE POLICY "User can access their own company data" ON public.inventory_ledger FOR ALL
USING (company_id = public.get_company_id_for_user())
WITH CHECK (company_id = public.get_company_id_for_user());

SELECT drop_policy_if_exists('conversations', 'User can access their own conversations');
CREATE POLICY "User can access their own conversations" ON public.conversations FOR ALL
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

SELECT drop_policy_if_exists('messages', 'User can access messages in their own company');
CREATE POLICY "User can access messages in their own company" ON public.messages FOR ALL
USING (company_id = public.get_company_id_for_user())
WITH CHECK (company_id = public.get_company_id_for_user());

SELECT drop_policy_if_exists('audit_log', 'User can access their own company audit log');
CREATE POLICY "User can access their own company audit log" ON public.audit_log FOR ALL
USING (company_id = public.get_company_id_for_user())
WITH CHECK (company_id = public.get_company_id_for_user());

SELECT drop_policy_if_exists('company_settings', 'User can access their own company settings');
CREATE POLICY "User can access their own company settings" ON public.company_settings FOR ALL
USING (company_id = public.get_company_id_for_user())
WITH CHECK (company_id = public.get_company_id_for_user());

SELECT drop_policy_if_exists('channel_fees', 'User can access their own company channel fees');
CREATE POLICY "User can access their own company channel fees" ON public.channel_fees FOR ALL
USING (company_id = public.get_company_id_for_user())
WITH CHECK (company_id = public.get_company_id_for_user());

SELECT drop_policy_if_exists('feedback', 'User can access their own company feedback');
CREATE POLICY "User can access their own company feedback" ON public.feedback FOR ALL
USING (company_id = public.get_company_id_for_user())
WITH CHECK (company_id = public.get_company_id_for_user());

SELECT drop_policy_if_exists('export_jobs', 'User can access their own company export jobs');
CREATE POLICY "User can access their own company export jobs" ON public.export_jobs FOR ALL
USING (company_id = public.get_company_id_for_user())
WITH CHECK (company_id = public.get_company_id_for_user());

SELECT drop_policy_if_exists('imports', 'User can access their own company imports');
CREATE POLICY "User can access their own company imports" ON public.imports FOR ALL
USING (company_id = public.get_company_id_for_user())
WITH CHECK (company_id = public.get_company_id_for_user());

SELECT drop_policy_if_exists('webhook_events', 'User can access their own company webhook events');
CREATE POLICY "User can access their own company webhook events" ON public.webhook_events FOR ALL
USING (integration_id IN (SELECT id FROM public.integrations WHERE company_id = public.get_company_id_for_user()))
WITH CHECK (integration_id IN (SELECT id FROM public.integrations WHERE company_id = public.get_company_id_for_user()));

SELECT drop_policy_if_exists('companies', 'User can access their own company');
CREATE POLICY "User can access their own company" ON public.companies FOR ALL
USING (id = public.get_company_id_for_user())
WITH CHECK (id = public.get_company_id_for_user());

SELECT drop_policy_if_exists('company_users', 'User can access their own company''s user list');
CREATE POLICY "User can access their own company's user list" ON public.company_users FOR ALL
USING (company_id = public.get_company_id_for_user())
WITH CHECK (company_id = public.get_company_id_for_user());

DROP FUNCTION IF EXISTS public.drop_policy_if_exists(text, text);
