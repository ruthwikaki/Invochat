-- ----
--
-- Tables
--
-- ----

-- Companies Table: Stores information about each company using the SaaS.
CREATE TABLE
  public.companies (
    id uuid DEFAULT gen_random_uuid () NOT NULL,
    created_at timestamp WITH time zone DEFAULT now() NOT NULL,
    name text NOT NULL,
    owner_id uuid NOT NULL,
    CONSTRAINT companies_pkey PRIMARY KEY (id),
    CONSTRAINT companies_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES auth.users (id) ON UPDATE CASCADE ON DELETE RESTRICT
  ) TABLESPACE pg_default;

-- Company Users Table: Manages user roles within a company.
CREATE TYPE public.company_role AS ENUM ('Owner', 'Admin', 'Member');
CREATE TABLE public.company_users (
    user_id UUID NOT NULL,
    company_id UUID NOT NULL,
    role company_role NOT NULL DEFAULT 'Member',
    PRIMARY KEY (user_id, company_id),
    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
    FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE
);

-- Company Settings Table: Stores business logic settings for each company.
CREATE TABLE public.company_settings (
    company_id UUID PRIMARY KEY REFERENCES companies(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    dead_stock_days INT NOT NULL DEFAULT 90,
    fast_moving_days INT NOT NULL DEFAULT 30,
    predictive_stock_days INT NOT NULL DEFAULT 7,
    currency TEXT NOT NULL DEFAULT 'USD',
    timezone TEXT NOT NULL DEFAULT 'UTC',
    tax_rate NUMERIC(5, 4) NOT NULL DEFAULT 0.0,
    overstock_multiplier INT NOT NULL DEFAULT 3,
    high_value_threshold INT NOT NULL DEFAULT 100000 -- in cents
);

-- Integrations Table: Stores information about connected e-commerce platforms.
CREATE TYPE public.integration_platform AS ENUM ('shopify', 'woocommerce', 'amazon_fba');
CREATE TABLE public.integrations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    platform integration_platform NOT NULL,
    shop_domain TEXT,
    shop_name TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    last_sync_at TIMESTAMPTZ,
    sync_status TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, platform)
);

-- Products Table: Central repository for all products.
CREATE TABLE public.products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    handle TEXT,
    product_type TEXT,
    tags TEXT[],
    status TEXT,
    image_url TEXT,
    external_product_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, external_product_id)
);

-- Suppliers Table: Stores vendor information.
CREATE TABLE public.suppliers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    default_lead_time_days INT,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

-- Product Variants Table: Stores individual SKUs for each product.
CREATE TABLE public.product_variants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    supplier_id UUID REFERENCES suppliers(id) ON DELETE SET NULL,
    sku TEXT NOT NULL,
    title TEXT,
    option1_name TEXT,
    option1_value TEXT,
    option2_name TEXT,
    option2_value TEXT,
    option3_name TEXT,
    option3_value TEXT,
    barcode TEXT,
    price INT, -- in cents
    compare_at_price INT, -- in cents
    cost INT, -- in cents
    inventory_quantity INT NOT NULL DEFAULT 0,
    location TEXT,
    external_variant_id TEXT,
    reorder_point INT,
    reorder_quantity INT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, sku)
);

-- Customers Table: Stores customer information.
CREATE TABLE public.customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    name TEXT,
    email TEXT,
    phone TEXT,
    external_customer_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ
);


-- Orders Table: Stores sales order information.
CREATE TABLE public.orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    order_number TEXT NOT NULL,
    external_order_id TEXT,
    customer_id UUID REFERENCES customers(id) ON DELETE SET NULL,
    financial_status TEXT,
    fulfillment_status TEXT,
    currency TEXT,
    subtotal INT NOT NULL,
    total_tax INT,
    total_shipping INT,
    total_discounts INT,
    total_amount INT NOT NULL,
    source_platform TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

-- Order Line Items Table: Connects orders to specific products.
CREATE TABLE public.order_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    variant_id UUID REFERENCES product_variants(id) ON DELETE SET NULL,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    product_name TEXT,
    variant_title TEXT,
    sku TEXT,
    quantity INT NOT NULL,
    price INT NOT NULL,
    total_discount INT,
    tax_amount INT,
    cost_at_time INT,
    external_line_item_id TEXT
);

-- Inventory Ledger Table: Tracks all changes to inventory levels.
CREATE TABLE public.inventory_ledger (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
    change_type TEXT NOT NULL, -- e.g., 'sale', 'purchase_order', 'manual_adjustment'
    quantity_change INT NOT NULL,
    new_quantity INT NOT NULL,
    related_id UUID, -- Can link to order_id, purchase_order_id, etc.
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Purchase Orders Table: Tracks incoming inventory orders.
CREATE TABLE public.purchase_orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    supplier_id UUID REFERENCES suppliers(id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'Draft',
    po_number TEXT NOT NULL,
    total_cost INT NOT NULL,
    expected_arrival_date DATE,
    idempotency_key UUID,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

-- Purchase Order Line Items Table
CREATE TABLE public.purchase_order_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    purchase_order_id UUID NOT NULL REFERENCES purchase_orders(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    quantity INT NOT NULL,
    cost INT NOT NULL -- in cents
);

-- Audit Log Table: Tracks significant user and system actions.
CREATE TABLE public.audit_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    details JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Conversations Table: Stores AI chat conversation metadata.
CREATE TYPE public.message_role AS ENUM ('user', 'assistant', 'tool');
CREATE TABLE public.conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_accessed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_starred BOOLEAN NOT NULL DEFAULT FALSE
);

-- Messages Table: Stores individual messages within a conversation.
CREATE TABLE public.messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    role message_role NOT NULL,
    content TEXT NOT NULL,
    component TEXT,
    componentProps JSONB,
    visualization JSONB,
    confidence FLOAT,
    assumptions TEXT[],
    isError BOOLEAN,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Feedback Table: Stores user feedback on AI responses.
CREATE TYPE public.feedback_type AS ENUM ('helpful', 'unhelpful');
CREATE TABLE public.feedback (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    subject_id UUID NOT NULL,
    subject_type TEXT NOT NULL, -- e.g., 'message', 'alert'
    feedback feedback_type NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- Channel Fees Table: Manages sales channel fees for profit calculations
CREATE TABLE public.channel_fees (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  channel_name TEXT NOT NULL,
  percentage_fee NUMERIC(5, 4),
  fixed_fee INT, -- in cents
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ,
  UNIQUE(company_id, channel_name)
);

-- Export Jobs Table: Manages asynchronous data export requests
CREATE TABLE public.export_jobs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    requested_by_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'pending', -- pending, processing, completed, failed
    download_url TEXT,
    expires_at TIMESTAMPTZ,
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ
);

-- Imports Table: Tracks data import jobs
CREATE TABLE public.imports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    created_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    import_type TEXT NOT NULL,
    file_name TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending', -- pending, processing, completed, completed_with_errors, failed
    total_rows INT,
    processed_rows INT,
    failed_rows INT,
    errors JSONB,
    summary JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ
);

-- Webhook Events Table: Stores webhook event IDs to prevent replay attacks
CREATE TABLE public.webhook_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    integration_id UUID NOT NULL REFERENCES integrations(id) ON DELETE CASCADE,
    webhook_id TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(integration_id, webhook_id)
);


-- ----
--
-- RLS (Row-Level Security)
--
-- ----

-- Enable RLS for all relevant tables
ALTER TABLE companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE company_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE channel_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE export_jobs ENABLE ROW LEVEL SECURITY;

-- Helper function to get company_id from user's app_metadata
CREATE OR REPLACE FUNCTION get_company_id_for_user(user_id UUID)
RETURNS UUID AS $$
BEGIN
    RETURN (
        SELECT company_id
        FROM public.company_users
        WHERE company_users.user_id = get_company_id_for_user.user_id
        LIMIT 1
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Policies for multi-tenancy
CREATE POLICY "Users can only see their own company"
ON public.companies FOR SELECT
USING (id = get_company_id_for_user(auth.uid()));

CREATE POLICY "Users can only access their own company's data"
ON public.company_users FOR ALL
USING (company_id = get_company_id_for_user(auth.uid()));

CREATE POLICY "Users can only see settings for their own company"
ON public.company_settings FOR ALL
USING (company_id = get_company_id_for_user(auth.uid()));

CREATE POLICY "Users can only see their own company's integrations"
ON public.integrations FOR ALL
USING (company_id = get_company_id_for_user(auth.uid()));

CREATE POLICY "Users can only see their own company's products"
ON public.products FOR ALL
USING (company_id = get_company_id_for_user(auth.uid()));

CREATE POLICY "Users can only see their own company's variants"
ON public.product_variants FOR ALL
USING (company_id = get_company_id_for_user(auth.uid()));

CREATE POLICY "Users can only see their own company's suppliers"
ON public.suppliers FOR ALL
USING (company_id = get_company_id_for_user(auth.uid()));

CREATE POLICY "Users can only see their own company's customers"
ON public.customers FOR ALL
USING (company_id = get_company_id_for_user(auth.uid()));

CREATE POLICY "Users can only see their own company's orders"
ON public.orders FOR ALL
USING (company_id = get_company_id_for_user(auth.uid()));

CREATE POLICY "Users can only see their own company's line items"
ON public.order_line_items FOR ALL
USING (company_id = get_company_id_for_user(auth.uid()));

CREATE POLICY "Users can only see their own company's inventory ledger"
ON public.inventory_ledger FOR ALL
USING (company_id = get_company_id_for_user(auth.uid()));

CREATE POLICY "Users can only see their own company's purchase orders"
ON public.purchase_orders FOR ALL
USING (company_id = get_company_id_for_user(auth.uid()));

CREATE POLICY "Users can only see their own company's po line items"
ON public.purchase_order_line_items FOR ALL
USING (company_id = get_company_id_for_user(auth.uid()));

CREATE POLICY "Users can only see their own company's audit log"
ON public.audit_log FOR SELECT
USING (company_id = get_company_id_for_user(auth.uid()));

CREATE POLICY "Users can only access their own conversations"
ON public.conversations FOR ALL
USING (user_id = auth.uid());

CREATE POLICY "Users can only access messages in their conversations"
ON public.messages FOR ALL
USING (conversation_id IN (SELECT id FROM conversations WHERE user_id = auth.uid()));

CREATE POLICY "Users can only manage their own company's channel fees"
ON public.channel_fees FOR ALL
USING (company_id = get_company_id_for_user(auth.uid()));

CREATE POLICY "Users can only access their own feedback"
ON public.feedback FOR ALL
USING (user_id = auth.uid());

CREATE POLICY "Users can only manage their own company's export jobs"
ON public.export_jobs FOR ALL
USING (company_id = get_company_id_for_user(auth.uid()));

-- ----
--
-- Triggers
--
-- ----

-- Trigger function to handle new user sign-ups
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    new_company_id UUID;
BEGIN
    -- Create a new company for the new user
    INSERT INTO public.companies (name, owner_id)
    VALUES (NEW.raw_user_meta_data->>'company_name', NEW.id)
    RETURNING id INTO new_company_id;

    -- Link the user to the new company as 'Owner'
    INSERT INTO public.company_users (user_id, company_id, role)
    VALUES (NEW.id, new_company_id, 'Owner');

    -- Create default settings for the new company
    INSERT INTO public.company_settings (company_id)
    VALUES (new_company_id);

    -- Update the user's app_metadata with the company_id
    UPDATE auth.users
    SET app_metadata = app_metadata || jsonb_build_object('company_id', new_company_id)
    WHERE id = NEW.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Attach the trigger to the users table in the auth schema
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- Trigger function to update the inventory ledger after an order is paid
CREATE OR REPLACE FUNCTION public.update_inventory_from_order()
RETURNS TRIGGER AS $$
BEGIN
    -- Only trigger for newly paid orders or updates to paid status
    IF (TG_OP = 'INSERT' AND NEW.financial_status = 'paid') OR 
       (TG_OP = 'UPDATE' AND OLD.financial_status != 'paid' AND NEW.financial_status = 'paid') THEN

        INSERT INTO public.inventory_ledger (company_id, variant_id, quantity_change, new_quantity, change_type, related_id)
        SELECT
            NEW.company_id,
            oli.variant_id,
            -oli.quantity,
            pv.inventory_quantity - oli.quantity,
            'sale',
            NEW.id
        FROM public.order_line_items oli
        JOIN public.product_variants pv ON oli.variant_id = pv.id
        WHERE oli.order_id = NEW.id;

        -- Atomically update the inventory quantity on the variants table
        UPDATE public.product_variants pv
        SET inventory_quantity = pv.inventory_quantity - oli.quantity
        FROM public.order_line_items oli
        WHERE pv.id = oli.variant_id AND oli.order_id = NEW.id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Attach the trigger to the orders table
DROP TRIGGER IF EXISTS on_order_paid ON public.orders;
CREATE TRIGGER on_order_paid
    AFTER INSERT OR UPDATE ON public.orders
    FOR EACH ROW
    EXECUTE FUNCTION public.update_inventory_from_order();


-- Trigger function to update inventory when a PO is marked as 'Received'
CREATE OR REPLACE FUNCTION public.update_inventory_from_po()
RETURNS TRIGGER AS $$
BEGIN
    -- Trigger only when status changes to 'Received'
    IF TG_OP = 'UPDATE' AND OLD.status != 'Received' AND NEW.status = 'Received' THEN
        INSERT INTO public.inventory_ledger (company_id, variant_id, quantity_change, new_quantity, change_type, related_id)
        SELECT
            NEW.company_id,
            poli.variant_id,
            poli.quantity,
            pv.inventory_quantity + poli.quantity,
            'purchase_order',
            NEW.id
        FROM public.purchase_order_line_items poli
        JOIN public.product_variants pv ON poli.variant_id = pv.id
        WHERE poli.purchase_order_id = NEW.id;

        -- Atomically update the inventory quantity on the variants table
        UPDATE public.product_variants pv
        SET inventory_quantity = pv.inventory_quantity + poli.quantity
        FROM public.purchase_order_line_items poli
        WHERE pv.id = poli.variant_id AND poli.purchase_order_id = NEW.id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Attach the trigger to the purchase_orders table
DROP TRIGGER IF EXISTS on_po_received ON public.purchase_orders;
CREATE TRIGGER on_po_received
    AFTER UPDATE ON public.purchase_orders
    FOR EACH ROW
    EXECUTE FUNCTION public.update_inventory_from_po();


-- ----
--
-- VIEWS
--
-- ----

CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT 
    pv.*,
    p.title as product_title,
    p.status as product_status,
    p.image_url,
    p.product_type
FROM 
    public.product_variants pv
JOIN 
    public.products p ON pv.product_id = p.id;

CREATE OR REPLACE VIEW public.customers_view AS
SELECT
    c.id,
    c.company_id,
    c.name as customer_name,
    c.email,
    COUNT(o.id) as total_orders,
    SUM(o.total_amount) as total_spent,
    MIN(o.created_at) as first_order_date,
    c.created_at
FROM
    public.customers c
LEFT JOIN
    public.orders o ON c.id = o.customer_id
WHERE c.deleted_at IS NULL
GROUP BY c.id, c.company_id, c.name, c.email, c.created_at;

CREATE OR REPLACE VIEW public.orders_view AS
SELECT
    o.*,
    c.email as customer_email
FROM
    public.orders o
LEFT JOIN
    public.customers c ON o.customer_id = c.id;

CREATE OR REPLACE VIEW public.audit_log_view AS
SELECT 
    al.*,
    u.email as user_email
FROM
    public.audit_log al
LEFT JOIN
    auth.users u ON al.user_id = u.id;


CREATE OR REPLACE VIEW public.feedback_view AS
SELECT
    f.id,
    f.created_at,
    f.feedback,
    u.email as user_email,
    user_msg.content as user_message_content,
    assistant_msg.content as assistant_message_content,
    f.company_id
FROM
    public.feedback f
LEFT JOIN
    auth.users u ON f.user_id = u.id
LEFT JOIN
    public.messages user_msg ON f.subject_id = user_msg.id AND f.subject_type = 'message'
LEFT JOIN
    public.messages assistant_msg ON user_msg.conversation_id = assistant_msg.conversation_id AND assistant_msg.role = 'assistant' AND assistant_msg.created_at > user_msg.created_at
ORDER BY
    f.created_at DESC, assistant_msg.created_at ASC
LIMIT 1;

CREATE OR REPLACE VIEW public.purchase_orders_view AS
SELECT
    po.*,
    s.name as supplier_name,
    json_agg(json_build_object(
        'id', poli.id,
        'quantity', poli.quantity,
        'cost', poli.cost,
        'sku', pv.sku,
        'product_name', p.title
    )) as line_items
FROM
    public.purchase_orders po
LEFT JOIN
    public.suppliers s ON po.supplier_id = s.id
LEFT JOIN
    public.purchase_order_line_items poli ON po.id = poli.purchase_order_id
LEFT JOIN
    public.product_variants pv ON poli.variant_id = pv.id
LEFT JOIN
    public.products p ON pv.product_id = p.id
GROUP BY
    po.id, s.name;


-- ----
--
-- Database Functions (RPC)
--
-- ----

-- Function to get dead stock report
CREATE OR REPLACE FUNCTION public.get_dead_stock_report(
  p_company_id uuid,
  p_days int DEFAULT 90
)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
WITH variant_last_sale AS (
  SELECT li.variant_id, MAX(o.created_at) AS last_sale_at
  FROM public.order_line_items li
  JOIN public.orders o ON o.id = li.order_id
  WHERE o.company_id = p_company_id
    AND o.cancelled_at IS NULL
  GROUP BY li.variant_id
),
params AS (
  SELECT COALESCE(cs.dead_stock_days, p_days) AS ds_days
  FROM public.company_settings cs
  WHERE cs.company_id = p_company_id
  LIMIT 1
),
dead AS (
  SELECT
    v.id                             AS variant_id,
    v.product_id,
    v.title                          AS variant_name,
    v.sku,
    v.inventory_quantity,
    v.cost::bigint                   AS cost,
    ls.last_sale_at
  FROM public.product_variants v
  LEFT JOIN variant_last_sale ls ON ls.variant_id = v.id
  CROSS JOIN params p
  WHERE v.company_id = p_company_id
    AND v.deleted_at IS NULL
    AND v.inventory_quantity > 0
    AND v.cost IS NOT NULL
    AND (ls.last_sale_at IS NULL OR ls.last_sale_at < (now() - make_interval(days => p.ds_days)))
)
SELECT jsonb_build_object(
  'deadStockItems', COALESCE(jsonb_agg(to_jsonb(dead)), '[]'::jsonb),
  'totalValue',     COALESCE(SUM((dead.inventory_quantity::bigint) * (dead.cost::bigint)), 0)
)
FROM dead;
$$;


-- Grant usage to authenticated users
GRANT EXECUTE ON FUNCTION public.get_company_id_for_user(user_id UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_dashboard_metrics(p_company_id UUID, p_days INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_dead_stock_report(p_company_id UUID, p_days INT) TO authenticated;

-- Final setup
ALTER publication supabase_realtime ADD TABLE company_settings;
ALTER publication supabase_realtime ADD TABLE integrations;
ALTER publication supabase_realtime ADD TABLE products;
ALTER publication supabase_realtime ADD TABLE product_variants;
ALTER publication supabase_realtime ADD TABLE suppliers;
ALTER publication supabase_realtime ADD TABLE customers;
ALTER publication supabase_realtime ADD TABLE orders;
ALTER publication supabase_realtime ADD TABLE order_line_items;
ALTER publication supabase_realtime ADD TABLE inventory_ledger;
ALTER publication supabase_realtime ADD TABLE purchase_orders;
ALTER publication supabase_realtime ADD TABLE purchase_order_line_items;
ALTER publication supabase_realtime ADD TABLE audit_log;
ALTER publication supabase_realtime ADD TABLE conversations;
ALTER publication supabase_realtime ADD TABLE messages;
ALTER publication supabase_realtime ADD TABLE feedback;
ALTER publication supabase_realtime ADD TABLE channel_fees;
ALTER publication supabase_realtime ADD TABLE export_jobs;
ALTER publication supabase_realtime ADD TABLE imports;
ALTER publication supabase_realtime ADD TABLE webhook_events;
