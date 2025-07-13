
-- InvoChat SaaS Schema
-- Version: 1.0.0
-- Description: This script sets up the multi-tenant database schema for InvoChat.
-- It is designed to be idempotent and can be re-run safely.

--
-- Extension: pgcrypto
--
CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";
--
-- Extension: uuid-ossp
--
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";


--
-- Cleanup: Drop old objects in reverse dependency order
--
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.get_current_company_id();
DROP FUNCTION IF EXISTS public.create_rls_policy(text);

-- Drop old tables that are being replaced by the new schema
DROP TABLE IF EXISTS public.inventory;
DROP TABLE IF EXISTS public.sales;
DROP TABLE IF EXISTS public.sale_items;

--
-- Type: user_role
--
DROP TYPE IF EXISTS public.user_role CASCADE;
CREATE TYPE public.user_role AS ENUM (
    'Owner',
    'Admin',
    'Member'
);


--
-- Table: companies
--
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    name text NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT companies_pkey PRIMARY KEY (id)
);
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;


--
-- Table: users (in public schema, mirrors auth.users for app-specific logic)
--
CREATE TABLE IF NOT EXISTS public.users (
    id uuid NOT NULL,
    company_id uuid NOT NULL,
    email text,
    role public.user_role NOT NULL DEFAULT 'Member'::public.user_role,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT users_pkey PRIMARY KEY (id),
    CONSTRAINT users_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT users_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;


--
-- Function: handle_new_user
--
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  company_id uuid;
  user_role public.user_role;
BEGIN
  -- Create a new company for the new user
  INSERT INTO public.companies (name)
  VALUES (new.raw_app_meta_data->>'company_name')
  RETURNING id INTO company_id;

  -- Set the user's role to 'Owner'
  user_role := 'Owner';

  -- Insert a new record into the public.users table
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (new.id, company_id, new.email, user_role);

  -- Update the user's app_metadata with the new company_id and role
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id, 'role', user_role)
  WHERE id = new.id;

  RETURN new;
END;
$function$;

--
-- Trigger: on_auth_user_created
--
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();


--
-- Table: company_settings
--
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid NOT NULL,
    dead_stock_days integer NOT NULL DEFAULT 90,
    fast_moving_days integer NOT NULL DEFAULT 30,
    predictive_stock_days integer NOT NULL DEFAULT 7,
    overstock_multiplier numeric NOT NULL DEFAULT 3,
    high_value_threshold numeric NOT NULL DEFAULT 1000,
    currency text DEFAULT 'USD'::text,
    timezone text DEFAULT 'UTC'::text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone,
    subscription_status text DEFAULT 'trial'::text,
    subscription_plan text DEFAULT 'starter'::text,
    subscription_expires_at timestamp with time zone,
    stripe_customer_id text,
    stripe_subscription_id text,
    promo_sales_lift_multiplier real NOT NULL DEFAULT 2.5,
    CONSTRAINT company_settings_pkey PRIMARY KEY (company_id),
    CONSTRAINT company_settings_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;


--
-- Table: products
--
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
    CONSTRAINT products_pkey PRIMARY KEY (id),
    CONSTRAINT products_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT products_company_id_external_product_id_key UNIQUE (company_id, external_product_id)
);
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);


--
-- Table: product_variants
--
CREATE TABLE IF NOT EXISTS public.product_variants (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    product_id uuid NOT NULL,
    company_id uuid NOT NULL,
    sku text,
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
    inventory_quantity integer DEFAULT 0,
    external_variant_id text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone,
    supplier_id uuid,
    reorder_point integer,
    reorder_quantity integer,
    lead_time_days integer,
    CONSTRAINT product_variants_pkey PRIMARY KEY (id),
    CONSTRAINT product_variants_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT product_variants_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE,
    CONSTRAINT product_variants_company_id_sku_key UNIQUE (company_id, sku)
);
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_product_variants_company_id ON public.product_variants(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_sku ON public.product_variants(sku);


--
-- Table: suppliers
--
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
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ADD CONSTRAINT product_variants_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) ON DELETE SET NULL;


--
-- Table: customers
--
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    customer_name text,
    email text,
    total_orders integer DEFAULT 0,
    total_spent integer DEFAULT 0,
    first_order_date date,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT customers_pkey PRIMARY KEY (id),
    CONSTRAINT customers_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT customers_company_id_email_key UNIQUE (company_id, email)
);
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;


--
-- Table: orders
--
CREATE TABLE IF NOT EXISTS public.orders (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL,
    order_number text NOT NULL,
    external_order_id text,
    customer_id uuid,
    financial_status text,
    fulfillment_status text,
    currency text,
    subtotal integer NOT NULL,
    total_tax integer,
    total_shipping integer,
    total_discounts integer,
    total_amount integer NOT NULL,
    source_platform text,
    cancelled_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone,
    CONSTRAINT orders_pkey PRIMARY KEY (id),
    CONSTRAINT orders_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE SET NULL,
    CONSTRAINT orders_company_id_external_order_id_key UNIQUE (company_id, external_order_id)
);
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;


--
-- Table: order_line_items
--
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    order_id uuid NOT NULL,
    variant_id uuid,
    company_id uuid NOT NULL,
    product_name text,
    variant_title text,
    sku text,
    quantity integer NOT NULL,
    price integer NOT NULL,
    total_discount integer,
    tax_amount integer,
    cost_at_time integer,
    external_line_item_id text,
    CONSTRAINT order_line_items_pkey PRIMARY KEY (id),
    CONSTRAINT order_line_items_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT order_line_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE,
    CONSTRAINT order_line_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE SET NULL
);
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;


--
-- Table: inventory_ledger
--
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
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;


--
-- Table: integrations
--
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
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;


--
-- Table: audit_log, conversations, messages, etc.
-- (These tables are less critical for the core data model and are included for completeness)
--
CREATE TABLE IF NOT EXISTS public.audit_log (
    id bigserial,
    company_id uuid,
    user_id uuid,
    action text NOT NULL,
    details jsonb,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT audit_log_pkey PRIMARY KEY (id),
    CONSTRAINT audit_log_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT audit_log_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL
);
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

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
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

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
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;


--
-- RLS Helper Functions
--
CREATE OR REPLACE FUNCTION public.get_current_company_id()
RETURNS uuid
LANGUAGE sql STABLE
AS $$
  SELECT
    CASE
      WHEN (auth.jwt()->>'app_metadata')::jsonb ? 'company_id' THEN
        ((auth.jwt()->>'app_metadata')::jsonb->>'company_id')::uuid
      ELSE
        NULL::uuid
    END;
$$;


--
-- RLS Policy Creation
--
CREATE OR REPLACE PROCEDURE create_rls_policy(table_name TEXT)
LANGUAGE plpgsql
AS $$
BEGIN
  EXECUTE format('
    DROP POLICY IF EXISTS "Users can only see their own company''s data." ON public.%I;
    CREATE POLICY "Users can only see their own company''s data."
    ON public.%I FOR ALL
    USING (company_id = public.get_current_company_id());
  ', table_name, table_name);
END;
$$;

-- Apply RLS policies to all company-scoped tables
CALL create_rls_policy('companies');
CALL create_rls_policy('users');
CALL create_rls_policy('company_settings');
CALL create_rls_policy('products');
CALL create_rls_policy('product_variants');
CALL create_rls_policy('suppliers');
CALL create_rls_policy('customers');
CALL create_rls_policy('orders');
CALL create_rls_policy('order_line_items');
CALL create_rls_policy('inventory_ledger');
CALL create_rls_policy('integrations');
CALL create_rls_policy('audit_log');
CALL create_rls_policy('conversations');
CALL create_rls_policy('messages');


--
-- Triggers for `updated_at` columns
--
CREATE OR REPLACE FUNCTION public.set_current_timestamp_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
  _new_record RECORD;
BEGIN
  _new_record := NEW;
  _new_record."updated_at" = NOW();
  RETURN _new_record;
END;
$function$;

-- Drop and recreate triggers to ensure idempotency
DROP TRIGGER IF EXISTS handle_updated_at ON public.products;
CREATE TRIGGER handle_updated_at
BEFORE UPDATE ON public.products
FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updated_at();

DROP TRIGGER IF EXISTS handle_updated_at ON public.product_variants;
CREATE TRIGGER handle_updated_at
BEFORE UPDATE ON public.product_variants
FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updated_at();

DROP TRIGGER IF EXISTS handle_updated_at ON public.orders;
CREATE TRIGGER handle_updated_at
BEFORE UPDATE ON public.orders
FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updated_at();

DROP TRIGGER IF EXISTS handle_updated_at ON public.integrations;
CREATE TRIGGER handle_updated_at
BEFORE UPDATE ON public.integrations
FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updated_at();

DROP TRIGGER IF EXISTS handle_updated_at ON public.company_settings;
CREATE TRIGGER handle_updated_at
BEFORE UPDATE ON public.company_settings
FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updated_at();

--
-- Other necessary tables that were missing from the previous schema
--
CREATE TABLE IF NOT EXISTS public.customer_addresses (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    customer_id uuid NOT NULL,
    company_id uuid NOT NULL,
    address_type text NOT NULL DEFAULT 'shipping',
    first_name text,
    last_name text,
    company text,
    address1 text,
    address2 text,
    city text,
    province_code text,
    country_code text,
    zip text,
    phone text,
    is_default boolean DEFAULT false,
    CONSTRAINT customer_addresses_pkey PRIMARY KEY (id),
    CONSTRAINT customer_addresses_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE CASCADE,
    CONSTRAINT customer_addresses_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);
ALTER TABLE public.customer_addresses ENABLE ROW LEVEL SECURITY;
CALL create_rls_policy('customer_addresses');

CREATE TABLE IF NOT EXISTS public.refunds (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL,
    order_id uuid NOT NULL,
    refund_number text NOT NULL,
    status text NOT NULL DEFAULT 'pending',
    reason text,
    note text,
    total_amount integer NOT NULL,
    created_by_user_id uuid,
    external_refund_id text,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT refunds_pkey PRIMARY KEY (id),
    CONSTRAINT refunds_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT refunds_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE,
    CONSTRAINT refunds_created_by_user_id_fkey FOREIGN KEY (created_by_user_id) REFERENCES auth.users(id) ON DELETE SET NULL
);
ALTER TABLE public.refunds ENABLE ROW LEVEL SECURITY;
CALL create_rls_policy('refunds');

CREATE TABLE IF NOT EXISTS public.refund_line_items (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    refund_id uuid NOT NULL,
    order_line_item_id uuid NOT NULL,
    quantity integer NOT NULL,
    amount integer NOT NULL,
    restock boolean DEFAULT true,
    company_id uuid NOT NULL,
    CONSTRAINT refund_line_items_pkey PRIMARY KEY (id),
    CONSTRAINT refund_line_items_refund_id_fkey FOREIGN KEY (refund_id) REFERENCES public.refunds(id) ON DELETE CASCADE,
    CONSTRAINT refund_line_items_order_line_item_id_fkey FOREIGN KEY (order_line_item_id) REFERENCES public.order_line_items(id) ON DELETE CASCADE,
    CONSTRAINT refund_line_items_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);
ALTER TABLE public.refund_line_items ENABLE ROW LEVEL SECURITY;
CALL create_rls_policy('refund_line_items');


CREATE TABLE IF NOT EXISTS public.discounts (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL,
    code text NOT NULL,
    type text NOT NULL,
    value integer NOT NULL,
    minimum_purchase integer,
    usage_limit integer,
    usage_count integer DEFAULT 0,
    applies_to text DEFAULT 'all',
    starts_at timestamp with time zone,
    ends_at timestamp with time zone,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT discounts_pkey PRIMARY KEY (id),
    CONSTRAINT discounts_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);
ALTER TABLE public.discounts ENABLE ROW LEVEL SECURITY;
CALL create_rls_policy('discounts');

CREATE TABLE IF NOT EXISTS public.webhook_events (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    integration_id uuid NOT NULL,
    platform text NOT NULL,
    external_event_id text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT webhook_events_pkey PRIMARY KEY (id),
    CONSTRAINT webhook_events_integration_id_external_event_id_key UNIQUE (integration_id, external_event_id),
    CONSTRAINT webhook_events_integration_id_fkey FOREIGN KEY (integration_id) REFERENCES public.integrations(id) ON DELETE CASCADE
);
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;

-- Final check on column types that caused issues before
ALTER TABLE public.orders ALTER COLUMN subtotal TYPE integer;
ALTER TABLE public.orders ALTER COLUMN total_tax TYPE integer;
ALTER TABLE public.orders ALTER COLUMN total_shipping TYPE integer;
ALTER TABLE public.orders ALTER COLUMN total_discounts TYPE integer;
ALTER TABLE public.orders ALTER COLUMN total_amount TYPE integer;

ALTER TABLE public.order_line_items ALTER COLUMN price TYPE integer;
ALTER TABLE public.order_line_items ALTER COLUMN total_discount TYPE integer;
ALTER TABLE public.order_line_items ALTER COLUMN tax_amount TYPE integer;
ALTER TABLE public.order_line_items ALTER COLUMN cost_at_time TYPE integer;

ALTER TABLE public.product_variants ALTER COLUMN price TYPE integer;
ALTER TABLE public.product_variants ALTER COLUMN compare_at_price TYPE integer;
ALTER TABLE public.product_variants ALTER COLUMN cost TYPE integer;


--
-- Function to record orders from platforms, ensuring data consistency.
--
CREATE OR REPLACE FUNCTION public.record_order_from_platform(
    p_company_id uuid,
    p_order_payload jsonb,
    p_platform text
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
    v_customer_id uuid;
    v_order_id uuid;
    v_line_item jsonb;
    v_variant_id uuid;
    v_variant_cost integer;
BEGIN
    -- Find or create the customer
    SELECT id INTO v_customer_id FROM public.customers
    WHERE company_id = p_company_id AND email = (p_order_payload->'customer'->>'email');

    IF v_customer_id IS NULL THEN
        INSERT INTO public.customers (company_id, customer_name, email)
        VALUES (p_company_id, p_order_payload->'customer'->>'first_name' || ' ' || p_order_payload->'customer'->>'last_name', p_order_payload->'customer'->>'email')
        RETURNING id INTO v_customer_id;
    END IF;

    -- Upsert the order
    INSERT INTO public.orders (
        company_id, external_order_id, order_number, customer_id,
        financial_status, fulfillment_status, currency, subtotal,
        total_tax, total_shipping, total_discounts, total_amount,
        source_platform, created_at, updated_at
    )
    VALUES (
        p_company_id,
        p_order_payload->>'id',
        p_order_payload->>'name',
        v_customer_id,
        p_order_payload->>'financial_status',
        p_order_payload->>'fulfillment_status',
        p_order_payload->>'currency',
        (p_order_payload->>'subtotal_price')::numeric * 100,
        (p_order_payload->>'total_tax')::numeric * 100,
        (p_order_payload->>'total_shipping_price_set'->'shop_money'->>'amount')::numeric * 100,
        (p_order_payload->>'total_discounts')::numeric * 100,
        (p_order_payload->>'total_price')::numeric * 100,
        p_platform,
        (p_order_payload->>'created_at')::timestamptz,
        (p_order_payload->>'updated_at')::timestamptz
    )
    ON CONFLICT (company_id, external_order_id)
    DO UPDATE SET
        financial_status = EXCLUDED.financial_status,
        fulfillment_status = EXCLUDED.fulfillment_status,
        updated_at = EXCLUDED.updated_at
    RETURNING id INTO v_order_id;

    -- Insert line items
    FOR v_line_item IN SELECT * FROM jsonb_array_elements(p_order_payload->'line_items')
    LOOP
        -- Find the corresponding variant in our DB
        SELECT id, cost INTO v_variant_id, v_variant_cost FROM public.product_variants
        WHERE company_id = p_company_id AND external_variant_id = (v_line_item->>'variant_id');

        INSERT INTO public.order_line_items (
            order_id, company_id, variant_id, external_line_item_id,
            product_name, variant_title, sku, quantity, price, cost_at_time
        )
        VALUES (
            v_order_id,
            p_company_id,
            v_variant_id,
            v_line_item->>'id',
            v_line_item->>'title',
            v_line_item->>'variant_title',
            v_line_item->>'sku',
            (v_line_item->>'quantity')::integer,
            (v_line_item->>'price')::numeric * 100,
            v_variant_cost -- Use the cost from our variants table
        )
        ON CONFLICT (id) DO NOTHING;
    END LOOP;

    RETURN v_order_id;
END;
$$;
