-- This is the schema for the AIVentory application.
-- It includes tables for products, inventory, sales, customers, suppliers,
-- purchase orders, and AI-related conversations and feedback.

--
-- Enums
--

-- Company Role Enum
CREATE TYPE public.company_role AS ENUM (
    'Owner',
    'Admin',
    'Member'
);

-- Integration Platform Enum
CREATE TYPE public.integration_platform AS ENUM (
    'shopify',
    'woocommerce',
    'amazon_fba'
);

-- Message Role Enum
CREATE TYPE public.message_role AS ENUM (
    'user',
    'assistant',
    'system',
    'tool'
);

-- Feedback Type Enum
CREATE TYPE public.feedback_type AS ENUM (
    'helpful',
    'unhelpful'
);


--
-- Tables
--

-- Companies Table
CREATE TABLE public.companies (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    owner_id uuid NOT NULL
);
ALTER TABLE public.companies ADD CONSTRAINT companies_pkey PRIMARY KEY (id);
ALTER TABLE public.companies ADD CONSTRAINT companies_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- Company Users Table (Join Table)
CREATE TABLE public.company_users (
    user_id uuid NOT NULL,
    company_id uuid NOT NULL,
    role public.company_role DEFAULT 'Member'::public.company_role NOT NULL
);
ALTER TABLE public.company_users ADD CONSTRAINT company_users_pkey PRIMARY KEY (user_id, company_id);
ALTER TABLE public.company_users ADD CONSTRAINT company_users_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.company_users ADD CONSTRAINT company_users_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- Products Table
CREATE TABLE public.products (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
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
    deleted_at timestamp with time zone,
    version integer DEFAULT 1 NOT NULL
);
ALTER TABLE public.products ADD CONSTRAINT products_pkey PRIMARY KEY (id);
ALTER TABLE public.products ADD CONSTRAINT products_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
CREATE UNIQUE INDEX products_company_id_external_product_id_idx ON public.products USING btree (company_id, external_product_id);


-- Suppliers Table
CREATE TABLE public.suppliers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    name text NOT NULL,
    email text,
    phone text,
    notes text,
    default_lead_time_days integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);
ALTER TABLE public.suppliers ADD CONSTRAINT suppliers_pkey PRIMARY KEY (id);
ALTER TABLE public.suppliers ADD CONSTRAINT suppliers_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


-- Product Variants Table
CREATE TABLE public.product_variants (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
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
    reserved_quantity integer DEFAULT 0 NOT NULL,
    in_transit_quantity integer DEFAULT 0 NOT NULL,
    location text,
    reorder_point integer,
    reorder_quantity integer,
    supplier_id uuid,
    lead_time_days integer,
    external_variant_id text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    deleted_at timestamp with time zone,
    version integer DEFAULT 1 NOT NULL
);
ALTER TABLE public.product_variants ADD CONSTRAINT product_variants_pkey PRIMARY KEY (id);
ALTER TABLE public.product_variants ADD CONSTRAINT product_variants_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.product_variants ADD CONSTRAINT product_variants_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;
ALTER TABLE public.product_variants ADD CONSTRAINT product_variants_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) ON DELETE SET NULL;
CREATE UNIQUE INDEX product_variants_company_id_sku_idx ON public.product_variants USING btree (company_id, sku);
CREATE UNIQUE INDEX product_variants_company_id_external_variant_id_idx ON public.product_variants USING btree (company_id, external_variant_id);


-- Customers Table
CREATE TABLE public.customers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    name text,
    email text,
    phone text,
    external_customer_id text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    deleted_at timestamp with time zone
);
ALTER TABLE public.customers ADD CONSTRAINT customers_pkey PRIMARY KEY (id);
ALTER TABLE public.customers ADD CONSTRAINT customers_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
CREATE UNIQUE INDEX customers_company_id_external_customer_id_idx ON public.customers USING btree (company_id, external_customer_id);

-- Orders Table
CREATE TABLE public.orders (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
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
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);
ALTER TABLE public.orders ADD CONSTRAINT orders_pkey PRIMARY KEY (id);
ALTER TABLE public.orders ADD CONSTRAINT orders_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.orders ADD CONSTRAINT orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE SET NULL;
CREATE UNIQUE INDEX orders_company_id_external_order_id_idx ON public.orders USING btree (company_id, external_order_id);

-- Order Line Items Table
CREATE TABLE public.order_line_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
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
    fulfillment_status text,
    external_line_item_id text
);
ALTER TABLE public.order_line_items ADD CONSTRAINT order_line_items_pkey PRIMARY KEY (id);
ALTER TABLE public.order_line_items ADD CONSTRAINT order_line_items_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.order_line_items ADD CONSTRAINT order_line_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;
ALTER TABLE public.order_line_items ADD CONSTRAINT order_line_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE SET NULL;

-- Purchase Orders Table
CREATE TABLE public.purchase_orders (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    supplier_id uuid,
    status text DEFAULT 'Draft'::text NOT NULL,
    po_number text NOT NULL,
    total_cost integer NOT NULL,
    notes text,
    expected_arrival_date date,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    idempotency_key uuid
);
ALTER TABLE public.purchase_orders ADD CONSTRAINT purchase_orders_pkey PRIMARY KEY (id);
ALTER TABLE public.purchase_orders ADD CONSTRAINT purchase_orders_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.purchase_orders ADD CONSTRAINT purchase_orders_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) ON DELETE SET NULL;


-- Purchase Order Line Items Table
CREATE TABLE public.purchase_order_line_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    purchase_order_id uuid NOT NULL,
    variant_id uuid NOT NULL,
    company_id uuid NOT NULL,
    quantity integer NOT NULL,
    cost integer NOT NULL
);
ALTER TABLE public.purchase_order_line_items ADD CONSTRAINT purchase_order_line_items_pkey PRIMARY KEY (id);
ALTER TABLE public.purchase_order_line_items ADD CONSTRAINT purchase_order_line_items_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.purchase_order_line_items ADD CONSTRAINT purchase_order_line_items_purchase_order_id_fkey FOREIGN KEY (purchase_order_id) REFERENCES public.purchase_orders(id) ON DELETE CASCADE;
ALTER TABLE public.purchase_order_line_items ADD CONSTRAINT purchase_order_line_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE CASCADE;

-- Refunds Table
CREATE TABLE public.refunds (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    order_id uuid NOT NULL,
    refund_number text NOT NULL,
    status text NOT NULL,
    reason text,
    note text,
    total_amount integer NOT NULL,
    created_by_user_id uuid,
    external_refund_id text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.refunds ADD CONSTRAINT refunds_pkey PRIMARY KEY (id);
ALTER TABLE public.refunds ADD CONSTRAINT refunds_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.refunds ADD CONSTRAINT refunds_created_by_user_id_fkey FOREIGN KEY (created_by_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.refunds ADD CONSTRAINT refunds_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;


-- Inventory Ledger Table
CREATE TABLE public.inventory_ledger (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    variant_id uuid NOT NULL,
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.inventory_ledger ADD CONSTRAINT inventory_ledger_pkey PRIMARY KEY (id);
ALTER TABLE public.inventory_ledger ADD CONSTRAINT inventory_ledger_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.inventory_ledger ADD CONSTRAINT inventory_ledger_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE CASCADE;

-- Integrations Table
CREATE TABLE public.integrations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    platform public.integration_platform NOT NULL,
    shop_domain text,
    shop_name text,
    is_active boolean DEFAULT true NOT NULL,
    last_sync_at timestamp with time zone,
    sync_status text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);
ALTER TABLE public.integrations ADD CONSTRAINT integrations_pkey PRIMARY KEY (id);
ALTER TABLE public.integrations ADD CONSTRAINT integrations_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
CREATE UNIQUE INDEX integrations_company_id_platform_idx ON public.integrations USING btree (company_id, platform);

-- Company Settings Table
CREATE TABLE public.company_settings (
    company_id uuid NOT NULL,
    dead_stock_days integer DEFAULT 90 NOT NULL,
    fast_moving_days integer DEFAULT 30 NOT NULL,
    predictive_stock_days integer DEFAULT 7 NOT NULL,
    currency text DEFAULT 'USD'::text NOT NULL,
    timezone text DEFAULT 'UTC'::text NOT NULL,
    tax_rate numeric DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    overstock_multiplier integer DEFAULT 3 NOT NULL,
    high_value_threshold integer DEFAULT 100000 NOT NULL,
    alert_settings jsonb,
    email_notifications boolean DEFAULT true NOT NULL,
    morning_briefing_enabled boolean DEFAULT true NOT NULL,
    morning_briefing_time text DEFAULT '08:00'::text NOT NULL,
    low_stock_threshold integer DEFAULT 10 NOT NULL,
    critical_stock_threshold integer DEFAULT 3 NOT NULL
);
ALTER TABLE public.company_settings ADD CONSTRAINT company_settings_pkey PRIMARY KEY (company_id);
ALTER TABLE public.company_settings ADD CONSTRAINT company_settings_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


-- Conversations Table
CREATE TABLE public.conversations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    company_id uuid NOT NULL,
    title text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    last_accessed_at timestamp with time zone DEFAULT now() NOT NULL,
    is_starred boolean DEFAULT false NOT NULL
);
ALTER TABLE public.conversations ADD CONSTRAINT conversations_pkey PRIMARY KEY (id);
ALTER TABLE public.conversations ADD CONSTRAINT conversations_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.conversations ADD CONSTRAINT conversations_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- Messages Table
CREATE TABLE public.messages (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    conversation_id uuid NOT NULL,
    company_id uuid NOT NULL,
    role public.message_role NOT NULL,
    content text NOT NULL,
    component text,
    component_props jsonb,
    visualization jsonb,
    confidence real,
    assumptions text[],
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    is_error boolean
);
ALTER TABLE public.messages ADD CONSTRAINT messages_pkey PRIMARY KEY (id);
ALTER TABLE public.messages ADD CONSTRAINT messages_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.messages ADD CONSTRAINT messages_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.conversations(id) ON DELETE CASCADE;

-- Feedback Table
CREATE TABLE public.feedback (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    company_id uuid NOT NULL,
    subject_id text NOT NULL,
    subject_type text NOT NULL,
    feedback public.feedback_type NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.feedback ADD CONSTRAINT feedback_pkey PRIMARY KEY (id);
ALTER TABLE public.feedback ADD CONSTRAINT feedback_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.feedback ADD CONSTRAINT feedback_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- Audit Log Table
CREATE TABLE public.audit_log (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    user_id uuid,
    action text NOT NULL,
    details jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.audit_log ADD CONSTRAINT audit_log_pkey PRIMARY KEY (id);
ALTER TABLE public.audit_log ADD CONSTRAINT audit_log_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.audit_log ADD CONSTRAINT audit_log_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL;

-- Export Jobs Table
CREATE TABLE public.export_jobs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    requested_by_user_id uuid NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    download_url text,
    error_message text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_at timestamp with time zone,
    expires_at timestamp with time zone
);
ALTER TABLE public.export_jobs ADD CONSTRAINT export_jobs_pkey PRIMARY KEY (id);
ALTER TABLE public.export_jobs ADD CONSTRAINT export_jobs_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.export_jobs ADD CONSTRAINT export_jobs_requested_by_user_id_fkey FOREIGN KEY (requested_by_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;

-- Channel Fees Table
CREATE TABLE public.channel_fees (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    channel_name text NOT NULL,
    percentage_fee real,
    fixed_fee integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);
ALTER TABLE public.channel_fees ADD CONSTRAINT channel_fees_pkey PRIMARY KEY (id);
ALTER TABLE public.channel_fees ADD CONSTRAINT channel_fees_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
CREATE UNIQUE INDEX channel_fees_company_id_channel_name_idx ON public.channel_fees USING btree (company_id, channel_name);

-- Alert History Table
CREATE TABLE public.alert_history (
    company_id uuid NOT NULL,
    alert_id text NOT NULL,
    status text NOT NULL,
    read_at timestamp with time zone,
    dismissed_at timestamp with time zone
);
ALTER TABLE public.alert_history ADD CONSTRAINT alert_history_pkey PRIMARY KEY (company_id, alert_id);
ALTER TABLE public.alert_history ADD CONSTRAINT alert_history_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;

-- Webhook Events Table
CREATE TABLE public.webhook_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    integration_id uuid NOT NULL,
    webhook_id text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.webhook_events ADD CONSTRAINT webhook_events_pkey PRIMARY KEY (id);
ALTER TABLE public.webhook_events ADD CONSTRAINT webhook_events_integration_id_fkey FOREIGN KEY (integration_id) REFERENCES public.integrations(id) ON DELETE CASCADE;
CREATE UNIQUE INDEX webhook_events_integration_id_webhook_id_idx ON public.webhook_events USING btree (integration_id, webhook_id);

-- Imports Table
CREATE TABLE public.imports (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    created_by uuid NOT NULL,
    import_type text NOT NULL,
    file_name text NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    processed_rows integer,
    failed_rows integer,
    total_rows integer,
    errors jsonb,
    summary jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_at timestamp with time zone,
    error_count integer
);
ALTER TABLE public.imports ADD CONSTRAINT imports_pkey PRIMARY KEY (id);
ALTER TABLE public.imports ADD CONSTRAINT imports_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.imports ADD CONSTRAINT imports_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE CASCADE;

--
-- Functions
--

-- Handle New User Function
-- This function is called by a trigger when a new user signs up.
-- It creates a new company for the user and links them as the owner.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    new_company_id uuid;
BEGIN
    -- Create a new company for the new user, using the company name from the user's metadata.
    INSERT INTO public.companies (name, owner_id)
    VALUES (new.raw_user_meta_data->>'company_name', new.id)
    RETURNING id INTO new_company_id;

    -- Link the user to the new company as 'Owner'.
    INSERT INTO public.company_users (user_id, company_id, role)
    VALUES (new.id, new_company_id, 'Owner');

    -- Update the user's app_metadata with the company_id.
    -- This makes it available in the JWT for easy access.
    UPDATE auth.users
    SET app_metadata = app_metadata || jsonb_build_object('company_id', new_company_id)
    WHERE id = new.id;

    RETURN new;
END;
$$;
COMMENT ON FUNCTION public.handle_new_user() IS 'Trigger function to create a company for a new user and assign ownership.';

-- Get Company ID for User Function
CREATE OR REPLACE FUNCTION public.get_company_id_for_user(p_user_id uuid)
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
AS $$
    SELECT company_id FROM public.company_users WHERE user_id = p_user_id LIMIT 1;
$$;
COMMENT ON FUNCTION public.get_company_id_for_user(uuid) IS 'Retrieves the company ID for a given user ID.';

-- Get Dead Stock Report Function
CREATE OR REPLACE FUNCTION public.get_dead_stock_report(p_company_id uuid)
RETURNS TABLE (
    sku text,
    product_name text,
    quantity integer,
    total_value numeric,
    last_sale_date timestamp with time zone
)
LANGUAGE sql
STABLE
AS $$
    WITH company_settings AS (
        SELECT dead_stock_days
        FROM public.company_settings 
        WHERE company_id = p_company_id
    ),
    dead_stock_cutoff AS (
        SELECT CURRENT_DATE - INTERVAL '1 day' * COALESCE((SELECT dead_stock_days FROM company_settings), 90) AS cutoff_date
    ),
    last_sales AS (
        SELECT 
            oli.sku,
            MAX(o.created_at) AS last_sale_date
        FROM public.order_line_items oli
        JOIN public.orders o ON oli.order_id = o.id
        WHERE o.company_id = p_company_id
            AND o.financial_status = 'paid'
        GROUP BY oli.sku
    ),
    dead_stock_variants AS (
        SELECT 
            pv.sku,
            pv.title AS variant_title,
            p.title AS product_title,
            pv.inventory_quantity,
            COALESCE(pv.cost, 0) AS cost,
            ls.last_sale_date
        FROM public.product_variants pv
        JOIN public.products p ON pv.product_id = p.id
        LEFT JOIN last_sales ls ON pv.sku = ls.sku
        CROSS JOIN dead_stock_cutoff dsc
        WHERE pv.company_id = p_company_id
            AND pv.inventory_quantity > 0
            AND (ls.last_sale_date IS NULL OR ls.last_sale_date < dsc.cutoff_date)
    )
    SELECT 
        dsv.sku,
        COALESCE(dsv.variant_title, dsv.product_title) AS product_name,
        dsv.inventory_quantity AS quantity,
        (dsv.inventory_quantity * dsv.cost) AS total_value,
        dsv.last_sale_date
    FROM dead_stock_variants dsv
    ORDER BY total_value DESC;
$$;
COMMENT ON FUNCTION public.get_dead_stock_report(uuid) IS 'Returns dead stock items for a company based on dead_stock_days setting and sales history';


--
-- Triggers
--

-- Trigger for handle_new_user
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


--
-- Row Level Security (RLS)
--

-- Enable RLS for all tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refunds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.alert_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.imports ENABLE ROW LEVEL SECURITY;


--
-- Policies
--

-- Companies Policies
CREATE POLICY "Users can see their own company" ON public.companies FOR SELECT USING (id = (SELECT public.get_company_id_for_user(auth.uid())));

-- Company Users Policies
CREATE POLICY "Users can see other members of their company" ON public.company_users FOR SELECT USING (company_id = (SELECT public.get_company_id_for_user(auth.uid())));

-- Generic policies for most tables
DO $$
DECLARE
    tbl_name text;
BEGIN
    FOR tbl_name IN
        SELECT table_name FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name NOT IN ('companies', 'company_users')
    LOOP
        EXECUTE format('CREATE POLICY "Users can manage their own company''s %1$s" ON public.%1$s FOR ALL USING (company_id = (SELECT public.get_company_id_for_user(auth.uid()))) WITH CHECK (company_id = (SELECT public.get_company_id_for_user(auth.uid())));', tbl_name);
    END LOOP;
END $$;

-- Special Policy for Company Settings (only one per company)
CREATE POLICY "Users can manage their own company settings" ON public.company_settings FOR ALL USING (company_id = (SELECT public.get_company_id_for_user(auth.uid()))) WITH CHECK (company_id = (SELECT public.get_company_id_for_user(auth.uid())));


-- Grant execute permissions for functions
GRANT EXECUTE ON FUNCTION public.handle_new_user() TO postgres;
GRANT EXECUTE ON FUNCTION public.get_company_id_for_user(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_dead_stock_report(uuid) TO authenticated;

-- Grant usage on schema to required roles
GRANT USAGE ON SCHEMA public TO postgres, anon, authenticated, service_role;

-- Grant all permissions to supabase_admin for all tables in the public schema
DO $$
DECLARE
    tbl_name text;
BEGIN
    FOR tbl_name IN
        SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'
    LOOP
        EXECUTE format('ALTER TABLE public.%1$s OWNER TO supabase_admin;', tbl_name);
        EXECUTE format('GRANT ALL ON TABLE public.%1$s TO supabase_admin;', tbl_name);
    END LOOP;
END $$;

-- Grant permissions for roles on all tables
GRANT ALL ON ALL TABLES IN SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO postgres, anon, authenticated, service_role;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres, anon, authenticated, service_role;
