--
-- Enums
--
CREATE TYPE public.company_role AS ENUM (
    'Owner',
    'Admin',
    'Member'
);

CREATE TYPE public.integration_platform AS ENUM (
    'shopify',
    'woocommerce',
    'amazon_fba'
);

CREATE TYPE public.message_role AS ENUM (
    'user',
    'assistant',
    'tool'
);

CREATE TYPE public.feedback_type AS ENUM (
    'helpful',
    'unhelpful'
);


--
-- Tables
--
CREATE TABLE public.companies (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    name text NOT NULL,
    owner_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.users (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email text,
    role public.company_role NOT NULL,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE public.company_users (
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role public.company_role DEFAULT 'Member'::public.company_role NOT NULL,
    PRIMARY KEY (company_id, user_id)
);

ALTER TABLE public.companies
ADD CONSTRAINT fk_companies_owner_id
FOREIGN KEY (owner_id) REFERENCES public.users(id) ON DELETE SET NULL;


CREATE TABLE public.products (
    id uuid DEFAULT uuid_generate_v4() NOT NULL PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    description text,
    handle text,
    product_type text,
    tags text[],
    status text,
    image_url text,
    external_product_id text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    deleted_at timestamp with time zone,
    fts_document tsvector GENERATED ALWAYS AS (to_tsvector('english'::regconfig, title || ' ' || COALESCE(description, ''::text))) STORED
);
CREATE INDEX products_fts_document_idx ON public.products USING gin (fts_document);
CREATE UNIQUE INDEX products_company_id_external_product_id_idx ON public.products(company_id, external_product_id);


CREATE TABLE public.product_variants (
    id uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
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
    inventory_quantity integer DEFAULT 0 NOT NULL,
    reserved_quantity integer DEFAULT 0 NOT NULL,
    in_transit_quantity integer DEFAULT 0 NOT NULL,
    external_variant_id text,
    location text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    deleted_at timestamp with time zone
);
CREATE UNIQUE INDEX product_variants_company_id_sku_idx ON public.product_variants(company_id, sku);


CREATE TABLE public.suppliers (
    id uuid DEFAULT uuid_generate_v4() NOT NULL PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);
ALTER TABLE public.product_variants
ADD COLUMN supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL;


CREATE TABLE public.customers (
    id uuid DEFAULT uuid_generate_v4() NOT NULL PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text,
    email text,
    phone text,
    external_customer_id text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone,
    deleted_at timestamp with time zone
);
CREATE UNIQUE INDEX customers_company_id_email_idx ON public.customers(company_id, email) WHERE deleted_at IS NULL;


CREATE TABLE public.orders (
    id uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number text NOT NULL,
    external_order_id text,
    customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
    financial_status text DEFAULT 'pending'::text,
    fulfillment_status text DEFAULT 'unfulfilled'::text,
    currency text DEFAULT 'USD'::text,
    subtotal integer DEFAULT 0 NOT NULL,
    total_tax integer DEFAULT 0,
    total_shipping integer DEFAULT 0,
    total_discounts integer DEFAULT 0,
    total_amount integer NOT NULL,
    source_platform text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


CREATE TABLE public.order_line_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
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

CREATE TABLE public.purchase_orders (
    id uuid DEFAULT uuid_generate_v4() NOT NULL PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL,
    status text DEFAULT 'Draft'::text NOT NULL,
    po_number text NOT NULL,
    total_cost integer NOT NULL,
    expected_arrival_date date,
    idempotency_key uuid,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);

CREATE TABLE public.purchase_order_line_items (
    id uuid DEFAULT uuid_generate_v4() NOT NULL PRIMARY KEY,
    purchase_order_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE RESTRICT,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    quantity integer NOT NULL,
    cost integer NOT NULL
);

CREATE TABLE public.inventory_ledger (
    id uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.integrations (
    id uuid DEFAULT uuid_generate_v4() NOT NULL PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform public.integration_platform NOT NULL,
    shop_domain text,
    shop_name text,
    is_active boolean DEFAULT false,
    last_sync_at timestamp with time zone,
    sync_status text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);
CREATE UNIQUE INDEX integrations_company_id_platform_idx ON public.integrations(company_id, platform);

CREATE TABLE public.conversations (
    id uuid DEFAULT uuid_generate_v4() NOT NULL PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    last_accessed_at timestamp with time zone DEFAULT now(),
    is_starred boolean DEFAULT false
);

CREATE TABLE public.messages (
    id uuid DEFAULT uuid_generate_v4() NOT NULL PRIMARY KEY,
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role public.message_role NOT NULL,
    content text,
    component text,
    component_props jsonb,
    visualization jsonb,
    confidence real,
    assumptions text[],
    isError boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer DEFAULT 90 NOT NULL,
    fast_moving_days integer DEFAULT 30 NOT NULL,
    overstock_multiplier real DEFAULT 3 NOT NULL,
    high_value_threshold integer DEFAULT 100000 NOT NULL,
    predictive_stock_days integer DEFAULT 7 NOT NULL,
    currency text DEFAULT 'USD'::text,
    timezone text DEFAULT 'UTC'::text,
    tax_rate numeric DEFAULT 0,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);

CREATE TABLE public.audit_log (
    id bigserial PRIMARY KEY,
    company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    action text NOT NULL,
    details jsonb,
    created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE public.feedback (
    id uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    subject_id text NOT NULL,
    subject_type text NOT NULL,
    feedback public.feedback_type NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE public.webhook_events (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id text NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);
CREATE UNIQUE INDEX webhook_events_integration_id_webhook_id_idx ON public.webhook_events(integration_id, webhook_id);

CREATE TABLE public.channel_fees (
    id uuid DEFAULT uuid_generate_v4() NOT NULL PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    channel_name text NOT NULL,
    percentage_fee numeric,
    fixed_fee integer,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone
);
CREATE UNIQUE INDEX channel_fees_company_id_channel_name_idx ON public.channel_fees(company_id, channel_name);

CREATE TABLE public.export_jobs (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    requested_by_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    status text DEFAULT 'pending' NOT NULL,
    download_url text,
    expires_at timestamp with time zone,
    error_message text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_at timestamp with time zone
);

--
-- Functions
--
CREATE OR REPLACE FUNCTION public.create_company_and_user(
  p_company_name text,
  p_user_email text,
  p_user_password text
)
RETURNS uuid AS $$
DECLARE
  new_user_id uuid;
  new_company_id uuid;
BEGIN
  -- Create the company first, but without an owner_id initially
  INSERT INTO public.companies (name)
  VALUES (p_company_name)
  RETURNING id INTO new_company_id;

  -- Now, create the user in auth.users, embedding the new company_id in the metadata.
  -- Supabase's built-in trigger will use this metadata to populate public.users.
  new_user_id := auth.uid() FROM auth.users WHERE email = p_user_email;
  IF new_user_id IS NULL THEN
    INSERT INTO auth.users (email, password, raw_app_meta_data)
    VALUES (p_user_email, crypt(p_user_password, gen_salt('bf')), jsonb_build_object('company_id', new_company_id, 'role', 'Owner'))
    RETURNING id INTO new_user_id;
  END IF;

  -- Finally, update the company with the new user's ID as the owner.
  UPDATE public.companies
  SET owner_id = new_user_id
  WHERE id = new_company_id;

  RETURN new_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


--
-- RLS Policies
--
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow users to see their own company" ON public.companies FOR SELECT USING (id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow users to see their own data" ON public.users FOR SELECT USING (id = auth.uid());
CREATE POLICY "Allow users to see members of their own company" ON public.users FOR SELECT USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow users to see their own company's membership" ON public.company_users FOR SELECT USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

-- Apply RLS to all other tables based on company_id
DO $$
DECLARE
    table_name TEXT;
BEGIN
    FOR table_name IN 
        SELECT tablename 
        FROM pg_tables 
        WHERE schemaname = 'public' 
          AND tablename NOT IN ('companies', 'users', 'company_users')
    LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', table_name);
        EXECUTE format('CREATE POLICY "Company isolation policy" ON public.%I FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));', table_name);
    END LOOP;
END;
$$;
