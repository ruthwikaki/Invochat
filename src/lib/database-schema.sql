-- Enable Row-Level Security (RLS) for all tables by default
ALTER DEFAULT PRIVILEGES IN SCHEMA public ENABLE ROW LEVEL SECURITY;

-- Create a helper function to get the company_id from the current user's claims
CREATE OR REPLACE FUNCTION get_current_company_id()
RETURNS UUID AS $$
DECLARE
    company_id UUID;
BEGIN
    company_id := (current_setting('request.jwt.claims', true)::jsonb ->> 'company_id')::UUID;
    -- For service_role access where claims might not be set, allow a fallback
    -- This is a controlled exception for trusted server-side operations.
    IF company_id IS NULL AND current_setting('request.jwt.claims', true)::jsonb ->> 'role' = 'service_role' THEN
       RETURN NULL; -- Or a specific default if needed, but NULL is safer.
    END IF;
    RETURN company_id;
END;
$$ LANGUAGE plpgsql STABLE;


-- Create a helper function to get the current user's ID
CREATE OR REPLACE FUNCTION get_current_user_id()
RETURNS UUID AS $$
BEGIN
    RETURN (current_setting('request.jwt.claims', true)::jsonb ->> 'sub')::UUID;
END;
$$ LANGUAGE plpgsql STABLE;


-- COMPANIES table to store company information
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name character varying NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL
);
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;

-- USERS table (references auth.users)
-- Note: Supabase automatically mirrors the auth.users table, but this table allows for RLS policies.
CREATE TABLE IF NOT EXISTS public.users (
    id uuid NOT NULL PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE,
    email character varying,
    role character varying DEFAULT 'Member'::character varying NOT NULL
);
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;


-- COMPANY_SETTINGS table for business logic parameters
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid NOT NULL PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer DEFAULT 90 NOT NULL,
    fast_moving_days integer DEFAULT 30 NOT NULL,
    overstock_multiplier numeric DEFAULT 3.0 NOT NULL,
    high_value_threshold integer DEFAULT 100000 NOT NULL, -- in cents
    predictive_stock_days integer DEFAULT 7 NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz
);
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;

-- PRODUCTS table
CREATE TABLE IF NOT EXISTS public.products (
    id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT, -- Prevent deleting company with products
    title character varying NOT NULL,
    description text,
    handle character varying,
    product_type character varying,
    tags text[],
    status character varying,
    image_url character varying,
    external_product_id character varying,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz,
    CONSTRAINT products_company_id_external_product_id_key UNIQUE (company_id, external_product_id)
);
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_products_tags ON public.products USING GIN (tags);


-- PRODUCT_VARIANTS table
CREATE TABLE IF NOT EXISTS public.product_variants (
    id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku character varying,
    title character varying,
    option1_name text,
    option1_value text,
    option2_name text,
    option2_value text,
    option3_name text,
    option3_value text,
    barcode character varying,
    price integer, -- in cents
    compare_at_price integer,
    cost integer, -- in cents
    inventory_quantity integer DEFAULT 0 NOT NULL,
    external_variant_id character varying,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz,
    CONSTRAINT product_variants_company_id_sku_key UNIQUE (company_id, sku),
    CONSTRAINT product_variants_company_id_external_variant_id_key UNIQUE (company_id, external_variant_id)
);
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_product_variants_company_id ON public.product_variants(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants(product_id);

-- CUSTOMERS table
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name text,
    email character varying,
    total_orders integer DEFAULT 0 NOT NULL,
    total_spent integer DEFAULT 0 NOT NULL, -- in cents
    first_order_date date,
    created_at timestamptz DEFAULT now() NOT NULL,
    deleted_at timestamptz,
    CONSTRAINT customers_company_id_email_key UNIQUE (company_id, email)
);
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers(company_id);


-- ORDERS table
CREATE TABLE IF NOT EXISTS public.orders (
    id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number text NOT NULL,
    external_order_id text,
    customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
    financial_status text,
    fulfillment_status text,
    currency character varying,
    subtotal integer NOT NULL, -- in cents
    total_tax integer,
    total_shipping integer,
    total_discounts integer,
    total_amount integer NOT NULL,
    source_platform text,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz,
    CONSTRAINT orders_company_id_external_order_id_key UNIQUE (company_id, external_order_id)
);
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON public.orders(customer_id);

-- ORDER_LINE_ITEMS table
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id uuid REFERENCES public.product_variants(id) ON DELETE SET NULL,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_name text,
    variant_title text,
    sku text,
    quantity integer NOT NULL,
    price integer NOT NULL, -- in cents
    total_discount integer,
    tax_amount integer,
    cost_at_time integer, -- in cents
    external_line_item_id text,
    CONSTRAINT price_not_negative CHECK (price >= 0),
    CONSTRAINT cost_at_time_not_negative CHECK (cost_at_time >= 0)
);
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON public.order_line_items(variant_id);


-- SUPPLIERS table
CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz DEFAULT now() NOT NULL
);
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON public.suppliers(company_id);


-- CONVERSATIONS table for the chat feature
CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    is_starred boolean DEFAULT false,
    created_at timestamptz DEFAULT now() NOT NULL,
    last_accessed_at timestamptz DEFAULT now() NOT NULL
);
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

-- MESSAGES table for chat conversations
CREATE TABLE IF NOT EXISTS public.messages (
    id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role text NOT NULL,
    content text NOT NULL,
    visualization jsonb,
    component text,
    "componentProps" jsonb,
    confidence real,
    assumptions text[],
    "isError" boolean,
    created_at timestamptz DEFAULT now() NOT NULL
);
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- INTEGRATIONS table
CREATE TABLE IF NOT EXISTS public.integrations (
    id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform text NOT NULL,
    shop_domain text,
    shop_name text,
    is_active boolean DEFAULT true NOT NULL,
    last_sync_at timestamptz,
    sync_status text,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz,
    CONSTRAINT integrations_company_id_platform_key UNIQUE (company_id, platform)
);
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;

-- INVENTORY_LEDGER table
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid,
    notes text,
    created_at timestamptz DEFAULT now() NOT NULL
);
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id_created_at ON public.inventory_ledger(variant_id, created_at DESC);

-- Function and Trigger to create a company and associate the user
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    new_company_id UUID;
    company_name_text TEXT;
BEGIN
    -- Extract company name from metadata, fallback to a default if not present
    company_name_text := new.raw_user_meta_data ->> 'company_name';
    IF company_name_text IS NULL OR company_name_text = '' THEN
        company_name_text := 'Default Company';
    END IF;

    -- Create a new company for the new user
    INSERT INTO public.companies (name)
    VALUES (company_name_text)
    RETURNING id INTO new_company_id;

    -- Insert a row into public.users for the new user
    INSERT INTO public.users (id, company_id, email, role)
    VALUES (new.id, new_company_id, new.email, 'Owner');
    
    -- Insert default settings for the new company
    INSERT INTO public.company_settings (company_id)
    VALUES (new_company_id);

    -- Update the user's app_metadata with the new company_id
    UPDATE auth.users
    SET app_metadata = jsonb_set(
        COALESCE(app_metadata, '{}'::jsonb),
        '{company_id}',
        to_jsonb(new_company_id)
    )
    WHERE id = new.id;
    
    RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger the function every time a user is created
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- Function to create RLS policies on a table dynamically
CREATE OR REPLACE FUNCTION create_company_rls_policy(table_name TEXT)
RETURNS void AS $$
BEGIN
    EXECUTE format('
        DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.%I;
        CREATE POLICY "Allow full access based on company_id"
        ON public.%I
        FOR ALL
        USING (company_id = get_current_company_id())
        WITH CHECK (company_id = get_current_company_id());
    ', table_name, table_name);
END;
$$ LANGUAGE plpgsql;

-- Apply RLS policies to all relevant tables
SELECT create_company_rls_policy(table_name)
FROM information_schema.tables
WHERE table_schema = 'public' AND table_name IN (
    'company_settings', 'products', 'product_variants', 'customers',
    'orders', 'order_line_items', 'suppliers', 'conversations',
    'messages', 'integrations', 'inventory_ledger'
);

-- Special RLS for the 'companies' table itself
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.companies;
CREATE POLICY "Allow full access based on company_id"
ON public.companies
FOR ALL
USING (id = get_current_company_id())
WITH CHECK (id = get_current_company_id());

-- RLS policies for the 'users' table
DROP POLICY IF EXISTS "Allow read access to other users in same company" ON public.users;
CREATE POLICY "Allow read access to other users in same company"
ON public.users
FOR SELECT
USING (company_id = get_current_company_id());

DROP POLICY IF EXISTS "Allow update of own user record" ON public.users;
CREATE POLICY "Allow update of own user record"
ON public.users
FOR UPDATE
USING (id = auth.uid());
