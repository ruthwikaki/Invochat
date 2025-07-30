
-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
-- Enable the pgcrypto extension for cryptographic functions
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Enumerated types for roles and platforms
CREATE TYPE public.company_role AS ENUM ('Owner', 'Admin', 'Member');
CREATE TYPE public.integration_platform AS ENUM ('shopify', 'woocommerce', 'amazon_fba');
CREATE TYPE public.message_role AS ENUM ('user', 'assistant', 'tool');
CREATE TYPE public.feedback_type AS ENUM ('helpful', 'unhelpful');


-- Companies Table: Stores information about each company/tenant
CREATE TABLE public.companies (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    name text NOT NULL,
    owner_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;


-- Company Users Table: Links users to companies with specific roles
CREATE TABLE public.company_users (
    user_id uuid NOT NULL,
    company_id uuid NOT NULL,
    role public.company_role NOT NULL DEFAULT 'Member',
    PRIMARY KEY (user_id, company_id)
);
ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;


-- Company Settings Table
CREATE TABLE public.company_settings (
    company_id uuid PRIMARY KEY NOT NULL,
    currency text NOT NULL DEFAULT 'USD',
    timezone text NOT NULL DEFAULT 'UTC',
    dead_stock_days integer NOT NULL DEFAULT 90,
    fast_moving_days integer NOT NULL DEFAULT 30,
    overstock_multiplier real NOT NULL DEFAULT 3,
    high_value_threshold integer NOT NULL DEFAULT 100000,
    predictive_stock_days integer NOT NULL DEFAULT 7,
    tax_rate real NOT NULL DEFAULT 0.0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;


-- Products Table
CREATE TABLE public.products (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    title text NOT NULL,
    description text,
    handle text,
    product_type text,
    tags text[],
    status text,
    image_url text,
    external_product_id text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    CONSTRAINT unique_product_handle UNIQUE(company_id, handle)
);
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;


-- Product Variants Table
CREATE TABLE public.product_variants (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
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
    reorder_point integer,
    reorder_quantity integer,
    supplier_id uuid,
    location text,
    external_variant_id text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    CONSTRAINT unique_variant_sku UNIQUE(company_id, sku)
);
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;


-- Suppliers Table
CREATE TABLE public.suppliers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;


-- Customers Table
CREATE TABLE public.customers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    external_customer_id text,
    name text,
    email text,
    phone text,
    deleted_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;


-- Orders Table
CREATE TABLE public.orders (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    customer_id uuid,
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
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;


-- Order Line Items Table
CREATE TABLE public.order_line_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
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
    external_line_item_id text
);
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;


-- Purchase Orders Table
CREATE TABLE public.purchase_orders (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    supplier_id uuid,
    po_number text NOT NULL,
    status text NOT NULL DEFAULT 'Draft',
    total_cost integer NOT NULL,
    expected_arrival_date date,
    idempotency_key uuid,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;


-- Purchase Order Line Items Table
CREATE TABLE public.purchase_order_line_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    purchase_order_id uuid NOT NULL,
    company_id uuid NOT NULL,
    variant_id uuid NOT NULL,
    quantity integer NOT NULL,
    cost integer NOT NULL
);
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;


-- Refunds Table
CREATE TABLE public.refunds (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    order_id uuid NOT NULL,
    refund_number text NOT NULL,
    status text NOT NULL,
    reason text,
    note text,
    total_amount integer NOT NULL,
    created_by_user_id uuid,
    external_refund_id text,
    created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.refunds ENABLE ROW LEVEL SECURITY;


-- Inventory Ledger Table
CREATE TABLE public.inventory_ledger (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    variant_id uuid NOT NULL,
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;


-- Integrations Table
CREATE TABLE public.integrations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    platform public.integration_platform NOT NULL,
    shop_domain text,
    shop_name text,
    is_active boolean NOT NULL DEFAULT true,
    last_sync_at timestamptz,
    sync_status text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;


-- Conversations Table
CREATE TABLE public.conversations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL,
    company_id uuid NOT NULL,
    title text NOT NULL,
    is_starred boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    last_accessed_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;


-- Messages Table
CREATE TABLE public.messages (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id uuid NOT NULL,
    company_id uuid NOT NULL,
    role public.message_role NOT NULL,
    content text NOT NULL,
    visualization jsonb,
    component text,
    "componentProps" jsonb,
    confidence real,
    assumptions text[],
    "isError" boolean,
    created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;


-- Feedback Table
CREATE TABLE public.feedback (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL,
    company_id uuid NOT NULL,
    subject_id uuid NOT NULL,
    subject_type text NOT NULL,
    feedback public.feedback_type NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.feedback ENABLE ROW LEVEL SECURITY;


-- Audit Log Table
CREATE TABLE public.audit_log (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    user_id uuid,
    action text NOT NULL,
    details jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;


-- Export Jobs Table
CREATE TABLE public.export_jobs (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    requested_by_user_id uuid NOT NULL,
    status text NOT NULL DEFAULT 'pending',
    download_url text,
    expires_at timestamptz,
    error_message text,
    created_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz
);
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;


-- Channel Fees Table
CREATE TABLE public.channel_fees (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    channel_name text NOT NULL,
    fixed_fee integer,
    percentage_fee real,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;


-- Webhook Events Table
CREATE TABLE public.webhook_events (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    integration_id uuid NOT NULL,
    webhook_id text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;


-- Foreign Key Constraints
ALTER TABLE public.companies ADD CONSTRAINT companies_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES auth.users(id);
ALTER TABLE public.company_users ADD CONSTRAINT company_users_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE public.company_users ADD CONSTRAINT company_users_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.company_settings ADD CONSTRAINT company_settings_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.products ADD CONSTRAINT products_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id);
ALTER TABLE public.product_variants ADD CONSTRAINT fk_product_variants_product_id FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;
ALTER TABLE public.product_variants ADD CONSTRAINT product_variants_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id);
ALTER TABLE public.product_variants ADD CONSTRAINT product_variants_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) ON DELETE SET NULL;
ALTER TABLE public.suppliers ADD CONSTRAINT suppliers_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id);
ALTER TABLE public.customers ADD CONSTRAINT customers_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id);
ALTER TABLE public.orders ADD CONSTRAINT orders_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id);
ALTER TABLE public.orders ADD CONSTRAINT orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE SET NULL;
ALTER TABLE public.order_line_items ADD CONSTRAINT order_line_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;
ALTER TABLE public.order_line_items ADD CONSTRAINT order_line_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE SET NULL;
ALTER TABLE public.order_line_items ADD CONSTRAINT order_line_items_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id);
ALTER TABLE public.purchase_orders ADD CONSTRAINT purchase_orders_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id);
ALTER TABLE public.purchase_orders ADD CONSTRAINT purchase_orders_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) ON DELETE SET NULL;
ALTER TABLE public.purchase_order_line_items ADD CONSTRAINT purchase_order_line_items_purchase_order_id_fkey FOREIGN KEY (purchase_order_id) REFERENCES public.purchase_orders(id) ON DELETE CASCADE;
ALTER TABLE public.purchase_order_line_items ADD CONSTRAINT purchase_order_line_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE CASCADE;
ALTER TABLE public.purchase_order_line_items ADD CONSTRAINT purchase_order_line_items_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id);
ALTER TABLE public.refunds ADD CONSTRAINT refunds_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id);
ALTER TABLE public.refunds ADD CONSTRAINT refunds_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;
ALTER TABLE public.refunds ADD CONSTRAINT refunds_created_by_user_id_fkey FOREIGN KEY (created_by_user_id) REFERENCES auth.users(id);
ALTER TABLE public.inventory_ledger ADD CONSTRAINT inventory_ledger_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id);
ALTER TABLE public.inventory_ledger ADD CONSTRAINT inventory_ledger_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE CASCADE;
ALTER TABLE public.integrations ADD CONSTRAINT integrations_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id);
ALTER TABLE public.conversations ADD CONSTRAINT conversations_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id);
ALTER TABLE public.conversations ADD CONSTRAINT conversations_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id);
ALTER TABLE public.messages ADD CONSTRAINT messages_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.conversations(id) ON DELETE CASCADE;
ALTER TABLE public.messages ADD CONSTRAINT messages_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id);
ALTER TABLE public.feedback ADD CONSTRAINT feedback_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id);
ALTER TABLE public.feedback ADD CONSTRAINT feedback_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id);
ALTER TABLE public.audit_log ADD CONSTRAINT audit_log_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id);
ALTER TABLE public.audit_log ADD CONSTRAINT audit_log_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id);
ALTER TABLE public.export_jobs ADD CONSTRAINT export_jobs_requested_by_user_id_fkey FOREIGN KEY (requested_by_user_id) REFERENCES auth.users(id);
ALTER TABLE public.export_jobs ADD CONSTRAINT export_jobs_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id);
ALTER TABLE public.channel_fees ADD CONSTRAINT channel_fees_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id);
ALTER TABLE public.webhook_events ADD CONSTRAINT webhook_events_integration_id_fkey FOREIGN KEY (integration_id) REFERENCES public.integrations(id) ON DELETE CASCADE;


-- Unique constraints
ALTER TABLE public.channel_fees ADD CONSTRAINT unique_channel_name_per_company UNIQUE (company_id, channel_name);
ALTER TABLE public.webhook_events ADD CONSTRAINT unique_webhook_event UNIQUE (integration_id, webhook_id);


-- Indexes for performance
CREATE INDEX idx_products_company_id ON public.products (company_id);
CREATE INDEX idx_product_variants_product_id ON public.product_variants (product_id);
CREATE INDEX idx_product_variants_company_id ON public.product_variants (company_id);
CREATE INDEX idx_orders_company_id ON public.orders (company_id);
CREATE INDEX idx_order_line_items_order_id ON public.order_line_items (order_id);
CREATE INDEX idx_inventory_ledger_variant_id ON public.inventory_ledger (variant_id);
CREATE INDEX idx_integrations_company_id ON public.integrations (company_id);
CREATE INDEX idx_conversations_user_id ON public.conversations (user_id);

-- Performance indexes recommended by audit
CREATE INDEX CONCURRENTLY IF NOT EXISTS orders_analytics_idx ON public.orders(company_id, created_at, financial_status);
CREATE INDEX CONCURRENTLY IF NOT EXISTS inventory_ledger_history_idx ON public.inventory_ledger(variant_id, created_at);
CREATE INDEX CONCURRENTLY IF NOT EXISTS messages_conversation_history_idx ON public.messages(conversation_id, created_at);


-- Helper function to get company_id from user_id
CREATE OR REPLACE FUNCTION public.get_company_id_for_user(p_user_id uuid)
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT company_id FROM public.company_users WHERE user_id = p_user_id LIMIT 1;
$$;


-- Row-level security policies
CREATE POLICY "Allow owner full access" ON public.companies FOR ALL TO authenticated USING (auth.uid() = owner_id);
CREATE POLICY "Allow company members read access" ON public.companies FOR SELECT TO authenticated USING (id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow members access to their own company users" ON public.company_users FOR ALL TO authenticated USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow members access to their own company settings" ON public.company_settings FOR ALL TO authenticated USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow members access to their own company products" ON public.products FOR ALL TO authenticated USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow members access to their own company variants" ON public.product_variants FOR ALL TO authenticated USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow members access to their own company suppliers" ON public.suppliers FOR ALL TO authenticated USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow members access to their own company customers" ON public.customers FOR ALL TO authenticated USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow members access to their own company orders" ON public.orders FOR ALL TO authenticated USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow members access to their own company order line items" ON public.order_line_items FOR ALL TO authenticated USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow members access to their own company purchase orders" ON public.purchase_orders FOR ALL TO authenticated USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow members access to their own company PO line items" ON public.purchase_order_line_items FOR ALL TO authenticated USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow members access to their own company refunds" ON public.refunds FOR ALL TO authenticated USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow members access to their own company inventory ledger" ON public.inventory_ledger FOR ALL TO authenticated USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow members access to their own company integrations" ON public.integrations FOR ALL TO authenticated USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow users to manage their own conversations" ON public.conversations FOR ALL TO authenticated USING (user_id = auth.uid());
CREATE POLICY "Allow users to manage their own messages" ON public.messages FOR ALL TO authenticated USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow users to manage their own feedback" ON public.feedback FOR ALL TO authenticated USING (user_id = auth.uid());
CREATE POLICY "Allow members read access to their own company audit log" ON public.audit_log FOR SELECT TO authenticated USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow admins to see export jobs for their company" ON public.export_jobs FOR SELECT TO authenticated USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow admins to create export jobs for their company" ON public.export_jobs FOR INSERT TO authenticated WITH CHECK (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow access to own channel fees" ON public.channel_fees FOR ALL TO authenticated USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow access to own webhook events" ON public.webhook_events FOR ALL TO authenticated USING (integration_id IN (SELECT id FROM public.integrations WHERE company_id = public.get_company_id_for_user(auth.uid())));


-- Trigger function to handle new user setup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  company_id uuid;
  company_name text;
BEGIN
  -- Extract company_name from the user's metadata
  company_name := new.raw_user_meta_data->>'company_name';

  -- Create a new company for the user
  INSERT INTO public.companies (name, owner_id)
  VALUES (COALESCE(company_name, 'My Company'), new.id)
  RETURNING id INTO company_id;

  -- Link the user to the new company as an Owner
  INSERT INTO public.company_users (user_id, company_id, role)
  VALUES (new.id, company_id, 'Owner');

  -- Set the company_id in the user's app_metadata
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id)
  WHERE id = new.id;

  -- Create default settings for the new company
  INSERT INTO public.company_settings (company_id)
  VALUES (company_id);

  RETURN new;
END;
$$;

-- Trigger to execute the function on new user creation
CREATE TRIGGER on_new_user
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();


-- Trigger function to handle inventory updates on order line item insertion
CREATE OR REPLACE FUNCTION public.update_inventory_on_sale()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE public.product_variants
  SET inventory_quantity = inventory_quantity - NEW.quantity
  WHERE id = NEW.variant_id;
  
  INSERT INTO public.inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes)
  SELECT NEW.company_id, NEW.variant_id, 'sale', -NEW.quantity, pv.inventory_quantity, NEW.order_id, 'Order #' || o.order_number
  FROM public.product_variants pv
  JOIN public.orders o ON o.id = NEW.order_id
  WHERE pv.id = NEW.variant_id;

  RETURN NEW;
END;
$$;

-- Trigger to execute inventory update on new order line item
CREATE TRIGGER on_new_order_line_item
  AFTER INSERT ON public.order_line_items
  FOR EACH ROW
  EXECUTE FUNCTION public.update_inventory_on_sale();


-- Views for simplified data access
CREATE OR REPLACE VIEW public.customers_view AS
SELECT 
    c.id,
    c.company_id,
    c.name as customer_name,
    c.email,
    c.created_at,
    COUNT(o.id) as total_orders,
    SUM(o.total_amount) as total_spent,
    MIN(o.created_at) as first_order_date
FROM public.customers c
LEFT JOIN public.orders o ON c.id = o.customer_id
WHERE c.deleted_at IS NULL
GROUP BY c.id;


CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT 
    pv.*,
    p.title as product_title,
    p.status as product_status,
    p.image_url,
    p.product_type
FROM public.product_variants pv
JOIN public.products p ON pv.product_id = p.id;


CREATE OR REPLACE VIEW public.orders_view AS
SELECT
    o.id,
    o.company_id,
    o.order_number,
    o.external_order_id,
    o.created_at,
    o.updated_at,
    c.email AS customer_email,
    o.customer_id,
    o.financial_status,
    o.fulfillment_status,
    o.currency,
    o.subtotal,
    o.total_tax,
    o.total_shipping,
    o.total_discounts,
    o.total_amount,
    o.source_platform
FROM public.orders o
LEFT JOIN public.customers c ON o.customer_id = c.id;


CREATE OR REPLACE VIEW public.audit_log_view AS
SELECT 
    al.id,
    al.created_at,
    u.email AS user_email,
    al.action,
    al.details,
    al.company_id
FROM public.audit_log al
LEFT JOIN auth.users u ON al.user_id = u.id;


CREATE OR REPLACE VIEW public.feedback_view AS
SELECT 
    f.id,
    f.created_at,
    f.feedback,
    u.email as user_email,
    um.content as user_message_content,
    am.content as assistant_message_content,
    f.company_id
FROM public.feedback f
JOIN auth.users u ON f.user_id = u.id
LEFT JOIN public.messages um ON f.subject_id = um.id AND um.role = 'user'
LEFT JOIN public.messages am ON f.subject_id = am.id AND am.role = 'assistant'
WHERE f.subject_type = 'message';


-- Materialized view for daily sales performance
CREATE MATERIALIZED VIEW public.daily_sales_performance AS
SELECT
    o.company_id,
    DATE(o.created_at) as sale_date,
    SUM(oli.quantity) as total_units_sold,
    SUM(oli.price * oli.quantity) as total_revenue,
    COUNT(DISTINCT o.id) as total_orders
FROM public.orders o
JOIN public.order_line_items oli ON o.id = oli.order_id
GROUP BY o.company_id, DATE(o.created_at);

-- Materialized view for product sales performance
CREATE MATERIALIZED VIEW public.product_sales_performance AS
SELECT
    pv.company_id,
    pv.product_id,
    p.title as product_name,
    pv.id as variant_id,
    pv.sku,
    SUM(oli.quantity) as total_quantity_sold,
    SUM(oli.price * oli.quantity) as total_revenue,
    SUM(oli.quantity * COALESCE(oli.cost_at_time, pv.cost, 0)) as total_cogs,
    SUM((oli.price * oli.quantity) - (oli.quantity * COALESCE(oli.cost_at_time, pv.cost, 0))) as total_profit
FROM public.order_line_items oli
JOIN public.product_variants pv ON oli.variant_id = pv.id
JOIN public.products p ON pv.product_id = p.id
GROUP BY pv.company_id, pv.product_id, p.title, pv.id, pv.sku;
