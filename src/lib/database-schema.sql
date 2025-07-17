-- InvoChat Base Schema
-- Version: 1.2
-- Last Updated: 2024-07-17
--
-- This script is intended for the initial setup of a new InvoChat database.
-- For existing databases, please use the migration scripts.
--
-- Features in this version:
-- - Complete table definitions for all core features.
-- - Robust Row-Level Security (RLS) policies for all tables.
-- - Performance indexes on foreign keys and frequently queried columns.
-- - Functions for handling new users and common database operations.
-- - Views for simplified data querying.

-- 1. extensions
create extension if not exists "uuid-ossp" with schema public;
create extension if not exists pgroonga with schema extensions;
-- 2. schemas
create schema if not exists private;
-- 3. roles
create role "user" with nologin;
-- 4. auth helpers
create or replace function public.get_current_user_id()
returns uuid
language sql stable
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;
create or replace function public.get_company_id()
returns uuid
language sql stable
as $$
  select nullif(current_setting('request.jwt.claim.company_id', true), '')::uuid;
$$;
-- 5. tables
CREATE TABLE public.companies (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    name text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT companies_pkey PRIMARY KEY (id)
);
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.users (
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
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
CREATE INDEX users_company_id_idx ON public.users USING btree (company_id);


CREATE TABLE public.company_settings (
    company_id uuid NOT NULL,
    dead_stock_days integer DEFAULT 90 NOT NULL,
    fast_moving_days integer DEFAULT 30 NOT NULL,
    predictive_stock_days integer DEFAULT 7 NOT NULL,
    currency text DEFAULT 'USD'::text,
    timezone text DEFAULT 'UTC'::text,
    tax_rate numeric DEFAULT 0,
    custom_rules jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    subscription_status text DEFAULT 'trial'::text,
    subscription_plan text DEFAULT 'starter'::text,
    subscription_expires_at timestamp with time zone,
    stripe_customer_id text,
    stripe_subscription_id text,
    promo_sales_lift_multiplier real DEFAULT 2.5 NOT NULL,
    overstock_multiplier integer DEFAULT 3 NOT NULL,
    high_value_threshold integer DEFAULT 1000 NOT NULL,
    CONSTRAINT company_settings_pkey PRIMARY KEY (company_id),
    CONSTRAINT company_settings_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.products (
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
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    fts_document tsvector,
    CONSTRAINT products_pkey PRIMARY KEY (id),
    CONSTRAINT products_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
CREATE INDEX products_company_id_idx ON public.products USING btree (company_id);
CREATE INDEX products_external_product_id_idx ON public.products USING btree (external_product_id);
CREATE INDEX products_fts_document_idx ON public.products USING gin (fts_document);


CREATE TABLE public.product_variants (
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
    inventory_quantity integer DEFAULT 0 NOT NULL,
    external_variant_id text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    location text,
    CONSTRAINT product_variants_pkey PRIMARY KEY (id),
    CONSTRAINT product_variants_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT product_variants_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE,
    CONSTRAINT product_variants_sku_company_id_unique UNIQUE (sku, company_id)
);
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
CREATE INDEX product_variants_company_id_idx ON public.product_variants USING btree (company_id);
CREATE INDEX product_variants_product_id_idx ON public.product_variants USING btree (product_id);
CREATE INDEX product_variants_sku_idx ON public.product_variants USING btree (sku);


CREATE TABLE public.inventory_ledger (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL,
    variant_id uuid NOT NULL,
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    related_id uuid,
    notes text,
    CONSTRAINT inventory_ledger_pkey PRIMARY KEY (id),
    CONSTRAINT inventory_ledger_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT inventory_ledger_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE CASCADE
);
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
CREATE INDEX inventory_ledger_company_id_variant_id_idx ON public.inventory_ledger USING btree (company_id, variant_id);


CREATE TABLE public.orders (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL,
    order_number text NOT NULL,
    external_order_id text,
    customer_id uuid,
    financial_status text DEFAULT 'pending'::text,
    fulfillment_status text DEFAULT 'unfulfilled'::text,
    currency text DEFAULT 'USD'::text,
    subtotal integer DEFAULT 0 NOT NULL,
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
    CONSTRAINT orders_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
CREATE INDEX orders_company_id_idx ON public.orders USING btree (company_id);
CREATE INDEX orders_created_at_idx ON public.orders USING btree (created_at);
CREATE UNIQUE INDEX orders_company_id_external_order_id_idx ON public.orders USING btree (company_id, external_order_id) WHERE (external_order_id IS NOT NULL);


CREATE TABLE public.order_line_items (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    order_id uuid NOT NULL,
    product_id uuid NOT NULL,
    variant_id uuid NOT NULL,
    company_id uuid NOT NULL,
    product_name text NOT NULL,
    variant_title text,
    sku text NOT NULL,
    quantity integer NOT NULL,
    price integer NOT NULL,
    total_discount integer DEFAULT 0,
    tax_amount integer DEFAULT 0,
    fulfillment_status text DEFAULT 'unfulfilled'::text,
    requires_shipping boolean DEFAULT true,
    external_line_item_id text,
    cost_at_time integer,
    CONSTRAINT order_line_items_pkey PRIMARY KEY (id),
    CONSTRAINT order_line_items_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT order_line_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE,
    CONSTRAINT order_line_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE SET NULL
);
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
CREATE INDEX order_line_items_order_id_idx ON public.order_line_items USING btree (order_id);
CREATE INDEX order_line_items_variant_id_idx ON public.order_line_items USING btree (variant_id);


CREATE TABLE public.customers (
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
    CONSTRAINT customers_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT customers_email_company_id_unique UNIQUE (email, company_id)
);
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
CREATE INDEX customers_company_id_idx ON public.customers USING btree (company_id);

CREATE TABLE public.suppliers (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT suppliers_pkey PRIMARY KEY (id),
    CONSTRAINT suppliers_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
CREATE INDEX suppliers_company_id_idx ON public.suppliers USING btree (company_id);


CREATE TABLE public.purchase_orders (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    supplier_id uuid,
    status text DEFAULT 'Draft'::text NOT NULL,
    po_number text NOT NULL,
    total_cost integer NOT NULL,
    expected_arrival_date date,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    idempotency_key uuid,
    CONSTRAINT purchase_orders_pkey PRIMARY KEY (id),
    CONSTRAINT purchase_orders_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT purchase_orders_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) ON DELETE SET NULL
);
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
CREATE INDEX purchase_orders_company_id_idx ON public.purchase_orders USING btree (company_id);
CREATE INDEX purchase_orders_supplier_id_idx ON public.purchase_orders USING btree (supplier_id);
CREATE UNIQUE INDEX purchase_orders_po_number_company_id_idx ON public.purchase_orders(po_number, company_id);

CREATE TABLE public.purchase_order_line_items (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    purchase_order_id uuid NOT NULL,
    variant_id uuid NOT NULL,
    company_id uuid NOT NULL,
    quantity integer NOT NULL,
    cost integer NOT NULL,
    CONSTRAINT purchase_order_line_items_pkey PRIMARY KEY (id),
    CONSTRAINT purchase_order_line_items_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT purchase_order_line_items_purchase_order_id_fkey FOREIGN KEY (purchase_order_id) REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    CONSTRAINT purchase_order_line_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE CASCADE
);
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
CREATE INDEX po_line_items_po_id_idx ON public.purchase_order_line_items(purchase_order_id);

CREATE TABLE public.integrations (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    platform text NOT NULL,
    shop_domain text,
    shop_name text,
    is_active boolean DEFAULT false,
    last_sync_at timestamp with time zone,
    sync_status text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    CONSTRAINT integrations_pkey PRIMARY KEY (id),
    CONSTRAINT integrations_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT integrations_company_platform_unique UNIQUE (company_id, platform)
);
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.conversations (
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
CREATE INDEX conversations_user_id_idx ON public.conversations(user_id);

CREATE TABLE public.messages (
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
CREATE INDEX messages_conversation_id_idx ON public.messages(conversation_id);


CREATE TABLE public.audit_log (
    id bigserial NOT NULL,
    user_id uuid,
    action text NOT NULL,
    details jsonb,
    created_at timestamp with time zone DEFAULT now(),
    company_id uuid,
    CONSTRAINT audit_log_pkey PRIMARY KEY (id),
    CONSTRAINT audit_log_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT audit_log_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL
);
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
CREATE INDEX audit_log_company_id_action_idx ON public.audit_log(company_id, action, created_at DESC);


CREATE TABLE public.channel_fees (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    channel_name text NOT NULL,
    percentage_fee numeric NOT NULL,
    fixed_fee numeric NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone,
    CONSTRAINT channel_fees_pkey PRIMARY KEY (id),
    CONSTRAINT channel_fees_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT channel_fees_company_id_channel_name_key UNIQUE (company_id, channel_name)
);
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.webhook_events (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    integration_id uuid NOT NULL,
    webhook_id text NOT NULL,
    processed_at timestamp with time zone DEFAULT now(),
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT webhook_events_pkey PRIMARY KEY (id),
    CONSTRAINT webhook_events_integration_id_fkey FOREIGN KEY (integration_id) REFERENCES public.integrations(id) ON DELETE CASCADE,
    CONSTRAINT webhook_events_integration_id_webhook_id_key UNIQUE (integration_id, webhook_id)
);
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;

-- 6. views
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.*,
    p.title as product_title,
    p.status as product_status,
    p.image_url as image_url
FROM public.product_variants pv
JOIN public.products p ON pv.product_id = p.id;

CREATE OR REPLACE VIEW public.orders_view AS
SELECT 
    o.id,
    o.company_id,
    o.order_number,
    o.external_order_id,
    o.financial_status,
    o.fulfillment_status,
    o.total_amount,
    o.created_at,
    o.updated_at,
    c.email AS customer_email
FROM public.orders o
LEFT JOIN public.customers c ON o.customer_id = c.id;


CREATE OR REPLACE VIEW public.customers_view AS
SELECT 
    c.id,
    c.company_id,
    c.customer_name,
    c.email,
    c.first_order_date,
    c.created_at,
    COUNT(o.id) AS total_orders,
    COALESCE(SUM(o.total_amount), 0) AS total_spent
FROM public.customers c
LEFT JOIN public.orders o ON c.id = o.customer_id
GROUP BY c.id;


-- 7. functions & triggers

-- When a new user signs up, this function creates a company and a user profile.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  company_id_var uuid;
  user_company_name text;
BEGIN
  -- Extract company name from auth metadata
  user_company_name := new.raw_app_meta_data->>'company_name';
  
  -- Create a new company
  INSERT INTO public.companies (name)
  VALUES (user_company_name)
  RETURNING id INTO company_id_var;
  
  -- Create a new user profile, linking to the new company
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (new.id, company_id_var, new.email, 'Owner');

  -- Update the user's app_metadata in auth.users with the new company_id and role
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id_var, 'role', 'Owner')
  WHERE id = new.id;
  
  RETURN new;
END;
$$;

-- Trigger to execute the function when a new auth.user is created
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();


-- A function to safely apply RLS policies to all tables in the public schema
CREATE OR REPLACE FUNCTION private.enable_rls_for_all_tables(schema_name text)
RETURNS void AS $$
DECLARE
    table_record record;
BEGIN
    FOR table_record IN
        SELECT tablename FROM pg_tables WHERE schemaname = schema_name
    LOOP
        EXECUTE 'ALTER TABLE ' || quote_ident(schema_name) || '.' || quote_ident(table_record.tablename) || ' ENABLE ROW LEVEL SECURITY;';
        
        -- Default policy for tables with a company_id column
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = schema_name AND table_name = table_record.tablename AND column_name = 'company_id') THEN
            EXECUTE 'CREATE POLICY "Allow all access to own company data" ON ' || quote_ident(schema_name) || '.' || quote_ident(table_record.tablename) || 
                    ' FOR ALL USING (company_id = public.get_company_id());';
        
        -- Special policy for the 'companies' table itself
        ELSIF table_record.tablename = 'companies' THEN
            EXECUTE 'CREATE POLICY "Allow all access to own company data" ON public.companies FOR ALL USING (id = public.get_company_id());';

        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Apply the RLS policies to all tables.
SELECT private.enable_rls_for_all_tables('public');

-- Grant usage on the public schema to the "user" role
GRANT USAGE ON SCHEMA public TO "user";
-- Grant select, insert, update, delete permissions on all tables to the "user" role
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO "user";
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO "user";

-- The authenticated user role needs to be able to use the 'user' role
GRANT "user" TO authenticated;

-- Set up RLS for Supabase storage
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow authenticated access to storage" ON storage.objects FOR ALL
  USING ( auth.role() = 'authenticated' );

-- Final setup for RPC functions security
GRANT EXECUTE ON FUNCTION public.get_company_id() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_current_user_id() TO authenticated;

-- Grant permissions for RPC functions used by the app
GRANT EXECUTE ON FUNCTION public.get_dashboard_metrics(uuid,integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_sales_analytics(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_inventory_analytics(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_customer_analytics(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_dead_stock_report(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_reorder_suggestions(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.detect_anomalies(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_alerts(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_inventory_aging_report(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_product_lifecycle_analysis(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_inventory_risk_report(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_customer_segment_analysis(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_cash_flow_insights(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_supplier_performance_report(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_inventory_turnover(uuid, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reconcile_inventory_from_integration(uuid, uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_purchase_orders_from_suggestions(uuid, uuid, jsonb, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_order_from_platform(uuid, jsonb, text) to authenticated;
GRANT EXECUTE ON FUNCTION public.get_historical_sales_for_sku(uuid, text) to authenticated;
GRANT EXECUTE ON FUNCTION public.get_users_for_company(uuid) to authenticated;

-- Grant access to service_role for critical backend operations
GRANT "user" TO service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO service_role;

-- Log that the schema setup is complete
select 'InvoChat base schema setup complete.';
