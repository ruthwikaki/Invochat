
-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Define custom types
CREATE TYPE public.company_role AS ENUM ('Owner', 'Admin', 'Member');
CREATE TYPE public.integration_platform AS ENUM ('shopify', 'woocommerce', 'amazon_fba');
CREATE TYPE public.message_role AS ENUM ('user', 'assistant', 'tool');
CREATE TYPE public.feedback_type AS ENUM ('helpful', 'unhelpful');


--
-- Table structure for companies
--
CREATE TABLE public.companies (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    name text NOT NULL,
    owner_id uuid NOT NULL REFERENCES auth.users(id),
    created_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;

--
-- Table structure for company_users (junction table)
--
CREATE TABLE public.company_users (
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role public.company_role DEFAULT 'Member'::public.company_role NOT NULL,
    PRIMARY KEY (user_id, company_id)
);
ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;


--
-- Table structure for company_settings
--
CREATE TABLE public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    currency text DEFAULT 'USD' NOT NULL,
    timezone text DEFAULT 'UTC' NOT NULL,
    dead_stock_days integer DEFAULT 90 NOT NULL,
    fast_moving_days integer DEFAULT 30 NOT NULL,
    overstock_multiplier numeric DEFAULT 3.0 NOT NULL,
    high_value_threshold integer DEFAULT 100000 NOT NULL, -- in cents
    predictive_stock_days integer DEFAULT 7 NOT NULL,
    tax_rate numeric DEFAULT 0.0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;

--
-- Table structure for products
--
CREATE TABLE public.products (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
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
    updated_at timestamp with time zone
);
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX products_company_id_external_product_id_idx ON public.products (company_id, external_product_id) WHERE external_product_id IS NOT NULL;


--
-- Table structure for suppliers
--
CREATE TABLE public.suppliers (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;


--
-- Table structure for product_variants
--
CREATE TABLE public.product_variants (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
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
    location text,
    external_variant_id text,
    reorder_point integer,
    reorder_quantity integer,
    supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX product_variants_company_id_sku_idx ON public.product_variants (company_id, sku);
CREATE UNIQUE INDEX product_variants_company_id_external_variant_id_idx ON public.product_variants (company_id, external_variant_id) WHERE external_variant_id IS NOT NULL;


--
-- Table structure for customers
--
CREATE TABLE public.customers (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text,
    email text,
    phone text,
    external_customer_id text,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX customers_company_id_external_customer_id_idx ON public.customers (company_id, external_customer_id) WHERE external_customer_id IS NOT NULL;


--
-- Table structure for orders
--
CREATE TABLE public.orders (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
    order_number text NOT NULL,
    external_order_id text,
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
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX orders_company_id_external_order_id_idx ON public.orders (company_id, external_order_id) WHERE external_order_id IS NOT NULL;


--
-- Table structure for order_line_items
--
CREATE TABLE public.order_line_items (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id uuid REFERENCES public.product_variants(id) ON DELETE SET NULL,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_name text,
    variant_title text,
    sku text,
    quantity integer NOT NULL,
    price integer NOT NULL,
    total_discount integer,
    tax_amount integer,
    cost_at_time integer,
    external_line_item_id text
);
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;


--
-- Table structure for refunds
--
CREATE TABLE public.refunds (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    refund_number text NOT NULL,
    status text NOT NULL,
    reason text,
    note text,
    total_amount integer NOT NULL,
    created_by_user_id uuid REFERENCES auth.users(id),
    external_refund_id text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.refunds ENABLE ROW LEVEL SECURITY;


--
-- Table structure for purchase_orders
--
CREATE TABLE public.purchase_orders (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
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
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;


--
-- Table structure for purchase_order_line_items
--
CREATE TABLE public.purchase_order_line_items (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    purchase_order_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    quantity integer NOT NULL,
    cost integer NOT NULL
);
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;


--
-- Table structure for inventory_ledger
--
CREATE TABLE public.inventory_ledger (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;

--
-- Table structure for integrations
--
CREATE TABLE public.integrations (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform public.integration_platform NOT NULL,
    shop_domain text,
    shop_name text,
    is_active boolean DEFAULT true NOT NULL,
    last_sync_at timestamp with time zone,
    sync_status text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX integrations_company_id_platform_idx ON public.integrations (company_id, platform);


--
-- Table structure for conversations (AI chat)
--
CREATE TABLE public.conversations (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    is_starred boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    last_accessed_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;


--
-- Table structure for messages (AI chat)
--
CREATE TABLE public.messages (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role public.message_role NOT NULL,
    content text NOT NULL,
    visualization jsonb,
    component text,
    "componentProps" jsonb,
    confidence real,
    assumptions text[],
    "isError" boolean,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;


--
-- Table structure for feedback
--
CREATE TABLE public.feedback (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    subject_id text NOT NULL,
    subject_type text NOT NULL,
    feedback public.feedback_type NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.feedback ENABLE ROW LEVEL SECURITY;


--
-- Table structure for channel_fees
--
CREATE TABLE public.channel_fees (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    channel_name text NOT NULL,
    percentage_fee numeric,
    fixed_fee integer, -- in cents
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX channel_fees_company_id_channel_name_idx ON public.channel_fees (company_id, channel_name);


--
-- Table structure for export_jobs
--
CREATE TABLE public.export_jobs (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    requested_by_user_id uuid NOT NULL REFERENCES auth.users(id),
    status text DEFAULT 'queued'::text NOT NULL,
    download_url text,
    expires_at timestamp with time zone,
    error_message text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_at timestamp with time zone
);
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;


--
-- Table structure for imports
--
CREATE TABLE public.imports (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    created_by uuid NOT NULL REFERENCES auth.users(id),
    import_type text NOT NULL,
    status text DEFAULT 'processing'::text NOT NULL,
    file_name text NOT NULL,
    total_rows integer,
    processed_rows integer,
    failed_rows integer,
    errors jsonb,
    summary jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_at timestamp with time zone
);
ALTER TABLE public.imports ENABLE ROW LEVEL SECURITY;


--
-- Table structure for audit_log
--
CREATE TABLE public.audit_log (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id uuid REFERENCES auth.users(id),
    action text NOT NULL,
    details jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

--
-- Table structure for webhook_events
--
CREATE TABLE public.webhook_events (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX webhook_events_integration_id_webhook_id_idx ON public.webhook_events(integration_id, webhook_id);

-- =================================================================
-- RLS (Row Level Security) POLICIES
-- =================================================================

--
-- Helper function to get company_id from JWT
--
CREATE OR REPLACE FUNCTION auth.company_id()
RETURNS UUID AS $$
DECLARE
    company_id_val UUID;
BEGIN
    company_id_val := NULLIF(current_setting('request.jwt.claims', true)::JSONB -> 'app_metadata' ->> 'company_id', '')::UUID;
    
    IF company_id_val IS NULL THEN
        company_id_val := NULLIF(current_setting('request.jwt.claims', true)::JSONB -> 'user_metadata' ->> 'company_id', '')::UUID;
    END IF;
    
    IF company_id_val IS NULL THEN
        SELECT (raw_app_meta_data ->> 'company_id')::UUID
        INTO company_id_val
        FROM auth.users
        WHERE id = auth.uid();
    END IF;
    
    RETURN company_id_val;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;


--
-- Helper function to check user role
--
CREATE OR REPLACE FUNCTION auth.user_role(p_user_id uuid)
RETURNS text AS $$
DECLARE
    v_role text;
BEGIN
    SELECT role INTO v_role
    FROM public.company_users
    WHERE user_id = p_user_id AND company_id = auth.company_id();
    RETURN v_role;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;


--
-- Policies for 'companies' table
--
CREATE POLICY "Users can only see their own company" ON public.companies
    FOR SELECT USING (id = auth.company_id());

--
-- Policies for 'company_users' table
--
CREATE POLICY "Users can see other members of their own company" ON public.company_users
    FOR SELECT USING (company_id = auth.company_id());

--
-- Policies for all other tables
--
CREATE POLICY "Users can only access their own company data" ON public.products FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Users can only access their own company data" ON public.product_variants FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Users can only access their own company data" ON public.suppliers FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Users can only access their own company data" ON public.orders FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Users can only access their own company data" ON public.order_line_items FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Users can only access their own company data" ON public.customers FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Users can only access their own company data" ON public.purchase_orders FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Users can only access their own company data" ON public.purchase_order_line_items FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Users can only access their own company data" ON public.inventory_ledger FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Users can only access their own company data" ON public.integrations FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Users can only access their own company data" ON public.company_settings FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Users can only access their own company data" ON public.conversations FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Users can only access their own company data" ON public.messages FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Users can only access their own company data" ON public.feedback FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Users can only access their own company data" ON public.channel_fees FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Users can only access their own company data" ON public.export_jobs FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Users can only access their own company data" ON public.imports FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Users can only access their own company data" ON public.audit_log FOR ALL USING (company_id = auth.company_id());

-- =================================================================
-- DATABASE TRIGGERS
-- =================================================================

--
-- Trigger function to handle new user signup
--
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    v_company_name text;
    v_company_id uuid;
BEGIN
    -- Extract company name from user metadata
    v_company_name := new.raw_user_meta_data->>'company_name';

    -- Create a new company for the user
    INSERT INTO public.companies (name, owner_id)
    VALUES (v_company_name, new.id)
    RETURNING id INTO v_company_id;

    -- Link the user to the new company as an Owner
    INSERT INTO public.company_users (user_id, company_id, role)
    VALUES (new.id, v_company_id, 'Owner');
    
    -- Update the user's app_metadata with the company_id
    UPDATE auth.users
    SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', v_company_id)
    WHERE id = new.id;

    RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

--
-- Attach trigger to auth.users table
--
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

--
-- Trigger function to update the 'updated_at' timestamp on tables
--
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply timestamp trigger to relevant tables
CREATE TRIGGER handle_updated_at BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE PROCEDURE public.update_updated_at_column();
CREATE TRIGGER handle_updated_at BEFORE UPDATE ON public.product_variants FOR EACH ROW EXECUTE PROCEDURE public.update_updated_at_column();
CREATE TRIGGER handle_updated_at BEFORE UPDATE ON public.suppliers FOR EACH ROW EXECUTE PROCEDURE public.update_updated_at_column();
CREATE TRIGGER handle_updated_at BEFORE UPDATE ON public.orders FOR EACH ROW EXECUTE PROCEDURE public.update_updated_at_column();
CREATE TRIGGER handle_updated_at BEFORE UPDATE ON public.customers FOR EACH ROW EXECUTE PROCEDURE public.update_updated_at_column();
CREATE TRIGGER handle_updated_at BEFORE UPDATE ON public.purchase_orders FOR EACH ROW EXECUTE PROCEDURE public.update_updated_at_column();
CREATE TRIGGER handle_updated_at BEFORE UPDATE ON public.integrations FOR EACH ROW EXECUTE PROCEDURE public.update_updated_at_column();
CREATE TRIGGER handle_updated_at BEFORE UPDATE ON public.company_settings FOR EACH ROW EXECUTE PROCEDURE public.update_updated_at_column();

--
-- Trigger function to maintain inventory ledger on stock changes
--
CREATE OR REPLACE FUNCTION public.log_inventory_change()
RETURNS TRIGGER AS $$
DECLARE
    v_change_type text;
    v_related_id uuid;
    v_notes text;
BEGIN
    IF (TG_OP = 'UPDATE' AND NEW.inventory_quantity <> OLD.inventory_quantity) OR (TG_OP = 'INSERT') THEN
        -- Determine change type based on context if possible (e.g., from an active session variable)
        -- For simplicity here, we'll default to 'manual_adjustment'
        v_change_type := COALESCE(current_setting('app.inventory_change_type', true), 'manual_adjustment');
        v_related_id := NULLIF(current_setting('app.inventory_related_id', true), '')::uuid;
        v_notes := NULLIF(current_setting('app.inventory_change_notes', true), '');

        INSERT INTO public.inventory_ledger (company_id, variant_id, quantity_change, new_quantity, change_type, related_id, notes)
        VALUES (NEW.company_id, NEW.id, NEW.inventory_quantity - COALESCE(OLD.inventory_quantity, 0), NEW.inventory_quantity, v_change_type, v_related_id, v_notes);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Attach inventory ledger trigger
CREATE TRIGGER on_inventory_quantity_change
    AFTER INSERT OR UPDATE OF inventory_quantity ON public.product_variants
    FOR EACH ROW EXECUTE PROCEDURE public.log_inventory_change();


--
-- Trigger to auto-generate PO number
--
CREATE OR REPLACE FUNCTION public.generate_po_number()
RETURNS TRIGGER AS $$
DECLARE
    v_prefix TEXT := 'PO';
    v_count BIGINT;
BEGIN
    SELECT count(*) + 1 INTO v_count FROM public.purchase_orders WHERE company_id = NEW.company_id;
    NEW.po_number := v_prefix || '-' || to_char(now(), 'YYMMDD') || '-' || v_count;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_po_number
    BEFORE INSERT ON public.purchase_orders
    FOR EACH ROW
    WHEN (NEW.po_number IS NULL)
    EXECUTE PROCEDURE public.generate_po_number();


-- =================================================================
-- VIEWS FOR SIMPLIFIED DATA ACCESS
-- =================================================================

--
-- View for products with their variants' details
--
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.id,
    pv.company_id,
    p.title AS product_title,
    p.status AS product_status,
    p.image_url,
    p.product_type,
    pv.title,
    pv.sku,
    pv.inventory_quantity,
    pv.price,
    pv.cost,
    pv.location,
    pv.barcode,
    pv.compare_at_price,
    pv.option1_name,
    pv.option1_value,
    pv.option2_name,
    pv.option2_value,
    pv.option3_name,
    pv.option3_value,
    pv.product_id,
    pv.external_variant_id,
    pv.created_at,
    pv.updated_at,
    pv.reorder_point,
    pv.reorder_quantity,
    pv.supplier_id
FROM public.product_variants pv
JOIN public.products p ON pv.product_id = p.id;


--
-- View for orders with customer email
--
CREATE OR REPLACE VIEW public.orders_view AS
SELECT
    o.*,
    c.email AS customer_email
FROM public.orders o
LEFT JOIN public.customers c ON o.customer_id = c.id;


--
-- View for customers with aggregated sales data
--
CREATE MATERIALIZED VIEW public.customers_view AS
SELECT
    c.id,
    c.company_id,
    c.name AS customer_name,
    c.email,
    c.created_at,
    MIN(o.created_at) AS first_order_date,
    COUNT(o.id) AS total_orders,
    SUM(o.total_amount) AS total_spent
FROM public.customers c
LEFT JOIN public.orders o ON c.id = o.customer_id
WHERE c.deleted_at IS NULL
GROUP BY c.id, c.company_id, c.name, c.email, c.created_at;

CREATE UNIQUE INDEX on public.customers_view (id);


--
-- View for Purchase Orders with Supplier Name
--
CREATE OR REPLACE VIEW public.purchase_orders_view AS
SELECT
    po.*,
    s.name as supplier_name
FROM public.purchase_orders po
LEFT JOIN public.suppliers s ON po.supplier_id = s.id;


--
-- View for AI Feedback with message context
--
CREATE OR REPLACE VIEW public.feedback_view AS
SELECT
    f.id,
    f.created_at,
    f.feedback,
    u.email as user_email,
    m.content as assistant_message_content,
    (SELECT content FROM public.messages um WHERE um.conversation_id = m.conversation_id AND um.role = 'user' AND um.created_at < m.created_at ORDER BY um.created_at DESC LIMIT 1) as user_message_content,
    f.company_id
FROM public.feedback f
JOIN public.messages m ON f.subject_id = m.id AND f.subject_type = 'message'
JOIN auth.users u ON f.user_id = u.id;


--
-- View for Audit Log with user email
--
CREATE OR REPLACE VIEW public.audit_log_view AS
SELECT
    al.id,
    al.created_at,
    al.action,
    al.details,
    u.email as user_email,
    al.company_id
FROM public.audit_log al
LEFT JOIN auth.users u ON al.user_id = u.id;

-- =================================================================
-- INITIAL DATA (Optional)
-- =================================================================

-- You can add some initial default data here if needed, for example:
-- INSERT INTO public.company_settings (company_id, currency, timezone)
-- VALUES ('some-default-company-id', 'USD', 'UTC')
-- ON CONFLICT (company_id) DO NOTHING;

-- Initial refresh of materialized views
REFRESH MATERIALIZED VIEW public.customers_view;
