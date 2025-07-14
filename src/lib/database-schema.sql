
-- Enable the UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Enable the pg_trgm extension for fuzzy string matching
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- #################################################################
-- ###                  TABLES AND ENUMS                           ###
-- #################################################################

-- Table for Companies
CREATE TABLE IF NOT EXISTS public.companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT (now() AT TIME ZONE 'utc')
);
COMMENT ON TABLE public.companies IS 'Stores company/organization information.';

-- Table for Company-specific settings
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id UUID PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days INT DEFAULT 90,
    fast_moving_days INT DEFAULT 30,
    overstock_multiplier NUMERIC DEFAULT 3,
    high_value_threshold NUMERIC DEFAULT 1000,
    predictive_stock_days INT DEFAULT 7,
    created_at TIMESTAMPTZ DEFAULT (now() AT TIME ZONE 'utc'),
    updated_at TIMESTAMPTZ
);
COMMENT ON TABLE public.company_settings IS 'Stores business logic settings for each company.';

-- Table for Products
CREATE TABLE IF NOT EXISTS public.products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    handle TEXT,
    product_type TEXT,
    tags TEXT[],
    status TEXT,
    image_url TEXT,
    external_product_id TEXT,
    created_at TIMESTAMPTZ DEFAULT (now() AT TIME ZONE 'utc'),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, external_product_id)
);
COMMENT ON TABLE public.products IS 'Stores master product information.';
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_products_external_id ON public.products(external_product_id);
CREATE INDEX IF NOT EXISTS idx_products_tags ON public.products USING GIN(tags);

-- Table for Product Variants
CREATE TABLE IF NOT EXISTS public.product_variants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku TEXT,
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
    external_variant_id TEXT,
    created_at TIMESTAMPTZ DEFAULT (now() AT TIME ZONE 'utc'),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, sku),
    UNIQUE(company_id, external_variant_id)
);
COMMENT ON TABLE public.product_variants IS 'Stores individual product variants (SKUs).';
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_company_id ON public.product_variants(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_sku ON public.product_variants(sku);
CREATE INDEX IF NOT EXISTS idx_product_variants_external_id ON public.product_variants(external_variant_id);

-- Table for Inventory Ledger
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type TEXT NOT NULL,
    quantity_change INT NOT NULL,
    new_quantity INT NOT NULL,
    related_id UUID,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT (now() AT TIME ZONE 'utc')
);
COMMENT ON TABLE public.inventory_ledger IS 'Tracks every change to inventory quantity for auditing.';
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id ON public.inventory_ledger(variant_id);

-- Table for Customers
CREATE TABLE IF NOT EXISTS public.customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name TEXT,
    email TEXT,
    total_orders INT DEFAULT 0,
    total_spent INT DEFAULT 0, -- in cents
    first_order_date TIMESTAMPTZ,
    external_customer_id TEXT,
    created_at TIMESTAMPTZ DEFAULT (now() AT TIME ZONE 'utc'),
    deleted_at TIMESTAMPTZ,
    UNIQUE(company_id, email),
    UNIQUE(company_id, external_customer_id)
);
COMMENT ON TABLE public.customers IS 'Stores customer information.';

-- Table for Orders
CREATE TABLE IF NOT EXISTS public.orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number TEXT NOT NULL,
    external_order_id TEXT,
    customer_id UUID REFERENCES public.customers(id),
    financial_status TEXT,
    fulfillment_status TEXT,
    currency TEXT,
    subtotal INT,
    total_tax INT,
    total_shipping INT,
    total_discounts INT,
    total_amount INT,
    source_platform TEXT,
    created_at TIMESTAMPTZ DEFAULT (now() AT TIME ZONE 'utc'),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, external_order_id)
);
COMMENT ON TABLE public.orders IS 'Stores sales order information.';
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON public.orders(customer_id);

-- Table for Order Line Items
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id UUID REFERENCES public.product_variants(id),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_name TEXT,
    variant_title TEXT,
    sku TEXT,
    quantity INT,
    price INT,
    total_discount INT,
    tax_amount INT,
    cost_at_time INT,
    external_line_item_id TEXT
);
COMMENT ON TABLE public.order_line_items IS 'Stores line items for each order.';
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON public.order_line_items(variant_id);

-- Table for Suppliers
CREATE TABLE IF NOT EXISTS public.suppliers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    default_lead_time_days INT,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT (now() AT TIME ZONE 'utc'),
    updated_at TIMESTAMPTZ
);
COMMENT ON TABLE public.suppliers IS 'Stores supplier/vendor information.';

-- Table for Conversations (AI Chat)
CREATE TABLE IF NOT EXISTS public.conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT (now() AT TIME ZONE 'utc'),
    last_accessed_at TIMESTAMPTZ DEFAULT (now() AT TIME ZONE 'utc'),
    is_starred BOOLEAN DEFAULT FALSE
);
COMMENT ON TABLE public.conversations IS 'Stores AI chat conversation threads.';

-- Table for Messages (AI Chat)
CREATE TABLE IF NOT EXISTS public.messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
    content TEXT,
    visualization JSONB,
    confidence NUMERIC,
    assumptions TEXT[],
    component TEXT,
    componentProps JSONB,
    isError BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT (now() AT TIME ZONE 'utc')
);
COMMENT ON TABLE public.messages IS 'Stores individual messages within a chat conversation.';

-- Table for Integrations
CREATE TABLE IF NOT EXISTS public.integrations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform TEXT NOT NULL,
    shop_domain TEXT,
    shop_name TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    last_sync_at TIMESTAMPTZ,
    sync_status TEXT,
    created_at TIMESTAMPTZ DEFAULT (now() AT TIME ZONE 'utc'),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, platform)
);
COMMENT ON TABLE public.integrations IS 'Stores integration settings for each company.';

-- Table for Audit Log
CREATE TABLE IF NOT EXISTS public.audit_log (
    id BIGSERIAL PRIMARY KEY,
    company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id),
    action TEXT NOT NULL,
    details JSONB,
    created_at TIMESTAMPTZ DEFAULT (now() AT TIME ZONE 'utc')
);
COMMENT ON TABLE public.audit_log IS 'Records significant actions performed by users.';

-- Table for Webhook Events
CREATE TABLE IF NOT EXISTS public.webhook_events (
    id BIGSERIAL PRIMARY KEY,
    integration_id UUID NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id TEXT NOT NULL,
    received_at TIMESTAMPTZ DEFAULT (now() AT TIME ZONE 'utc'),
    UNIQUE(integration_id, webhook_id)
);
COMMENT ON TABLE public.webhook_events IS 'Stores webhook IDs to prevent replay attacks.';


-- #################################################################
-- ###                  VIEWS                                      ###
-- #################################################################

-- A unified view for inventory items with key details
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.id,
    pv.product_id,
    pv.company_id,
    p.title as product_title,
    p.status as product_status,
    p.image_url,
    pv.title,
    pv.sku,
    pv.price,
    pv.cost,
    pv.inventory_quantity,
    pv.created_at,
    p.product_type,
    pv.location_id,
    l.name as location_name
FROM public.product_variants pv
JOIN public.products p ON pv.product_id = p.id
LEFT JOIN public.locations l ON pv.location_id = l.id;


-- #################################################################
-- ###                  FUNCTIONS & TRIGGERS                       ###
-- #################################################################

-- Function to automatically set updated_at timestamp
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = (now() AT TIME ZONE 'utc');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Helper function to apply the updated_at trigger
CREATE OR REPLACE FUNCTION public.apply_updated_at_trigger(table_name TEXT)
RETURNS void AS $$
BEGIN
    EXECUTE format('
        DROP TRIGGER IF EXISTS handle_updated_at ON public.%I;
        CREATE TRIGGER handle_updated_at
        BEFORE UPDATE ON public.%I
        FOR EACH ROW
        EXECUTE FUNCTION public.set_updated_at();
    ', table_name, table_name);
END;
$$ LANGUAGE plpgsql;

-- Apply the trigger to all tables that have an updated_at column
SELECT public.apply_updated_at_trigger(table_name)
FROM information_schema.tables
WHERE table_schema = 'public' AND table_name IN (
    'company_settings', 'products', 'product_variants', 'orders', 'suppliers', 'integrations'
);


-- Function to handle new user registration
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    v_company_id UUID;
BEGIN
    -- Create a new company for the new user
    INSERT INTO public.companies (name)
    VALUES (new.raw_user_meta_data->>'company_name')
    RETURNING id INTO v_company_id;

    -- Update the user's metadata with the new company_id and default role
    UPDATE auth.users
    SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', v_company_id, 'role', 'Owner')
    WHERE id = new.id;

    RETURN new;
END;
$$ LANGUAGE plpgsql;

-- Trigger to execute the function on new user creation in auth.users
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_user();


-- #################################################################
-- ###                  ROW-LEVEL SECURITY (RLS)                   ###
-- #################################################################

-- Enable RLS on all relevant tables
DO $$
DECLARE
    t_name TEXT;
BEGIN
    FOR t_name IN
        SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'
    LOOP
        EXECUTE 'ALTER TABLE public.' || quote_ident(t_name) || ' ENABLE ROW LEVEL SECURITY;';
    END LOOP;
END;
$$;


-- Function to get the company_id for the current user
CREATE OR REPLACE FUNCTION public.get_current_company_id()
RETURNS UUID AS $$
BEGIN
    RETURN (SELECT nullif(current_setting('request.jwt.claims', true)::jsonb->>'app_metadata', '')::jsonb->>'company_id')::UUID;
EXCEPTION
    WHEN others THEN
        RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Helper function to create RLS policies
CREATE OR REPLACE FUNCTION public.create_company_rls_policy(table_name TEXT)
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

-- Apply the generic RLS policy to all tables with a company_id column
SELECT public.create_company_rls_policy(table_name)
FROM information_schema.columns
WHERE table_schema = 'public' AND column_name = 'company_id';


-- RLS for the 'companies' table (special case, uses `id` column)
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.companies;
CREATE POLICY "Allow full access based on company_id"
ON public.companies
FOR ALL
USING (id = get_current_company_id())
WITH CHECK (id = get_current_company_id());


-- Function to get company_id for a given user
CREATE OR REPLACE FUNCTION public.get_company_id_for_user(user_id UUID)
RETURNS UUID AS $$
DECLARE
    company_id UUID;
BEGIN
    SELECT raw_app_meta_data->>'company_id' INTO company_id
    FROM auth.users
    WHERE id = user_id;
    RETURN company_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- RLS policy for the `users` table
DROP POLICY IF EXISTS "Allow read access to other users in same company" ON auth.users;
CREATE POLICY "Allow read access to other users in same company"
ON auth.users FOR SELECT
USING (get_company_id_for_user(id) = get_current_company_id());

-- RLS for audit_log and webhook_events
DROP POLICY IF EXISTS "Allow read access to company audit log" ON public.audit_log;
CREATE POLICY "Allow read access to company audit log"
ON public.audit_log FOR SELECT
USING (company_id = get_current_company_id());

DROP POLICY IF EXISTS "Allow read access to webhook_events" ON public.webhook_events;
CREATE POLICY "Allow read access to webhook_events"
ON public.webhook_events FOR SELECT
USING (company_id = get_current_company_id());

-- RLS for conversations and messages (user-specific access)
DROP POLICY IF EXISTS "Allow full access to own conversations" ON public.conversations;
CREATE POLICY "Allow full access to own conversations"
ON public.conversations FOR ALL
USING (user_id = auth.uid() AND company_id = get_current_company_id())
WITH CHECK (user_id = auth.uid() AND company_id = get_current_company_id());

DROP POLICY IF EXISTS "Allow full access to messages in own conversations" ON public.messages;
CREATE POLICY "Allow full access to messages in own conversations"
ON public.messages FOR ALL
USING (
    company_id = get_current_company_id() AND
    conversation_id IN (SELECT id FROM public.conversations WHERE user_id = auth.uid())
);


-- #################################################################
-- ###                  STORED PROCEDURES                        ###
-- #################################################################

CREATE OR REPLACE FUNCTION public.record_order_from_platform(
    p_company_id UUID,
    p_order_payload JSONB,
    p_platform TEXT
)
RETURNS void AS $$
DECLARE
    v_customer_id UUID;
    v_order_id UUID;
    v_variant_id UUID;
    v_item JSONB;
BEGIN
    -- Find or create the customer record
    SELECT id INTO v_customer_id FROM public.customers
    WHERE company_id = p_company_id AND email = p_order_payload->'billing'->>'email';

    IF v_customer_id IS NULL THEN
        INSERT INTO public.customers (company_id, customer_name, email, external_customer_id)
        VALUES (
            p_company_id,
            p_order_payload->'billing'->>'first_name' || ' ' || p_order_payload->'billing'->>'last_name',
            p_order_payload->'billing'->>'email',
            (p_order_payload->>'customer_id')::TEXT
        )
        RETURNING id INTO v_customer_id;
    END IF;

    -- Create the order record
    INSERT INTO public.orders (
        company_id, order_number, external_order_id, customer_id, financial_status,
        fulfillment_status, currency, subtotal, total_tax, total_shipping,
        total_discounts, total_amount, source_platform, created_at
    )
    VALUES (
        p_company_id,
        p_order_payload->>'number',
        (p_order_payload->>'id')::TEXT,
        v_customer_id,
        p_order_payload->>'financial_status',
        p_order_payload->>'fulfillment_status',
        p_order_payload->>'currency',
        (p_order_payload->>'subtotal_price')::NUMERIC * 100,
        (p_order_payload->>'total_tax')::NUMERIC * 100,
        (p_order_payload->>'total_shipping_price_set'->'shop_money'->>'amount')::NUMERIC * 100,
        (p_order_payload->>'total_discounts')::NUMERIC * 100,
        (p_order_payload->>'total_price')::NUMERIC * 100,
        p_platform,
        (p_order_payload->>'created_at')::TIMESTAMPTZ
    )
    RETURNING id INTO v_order_id;

    -- Create order line items and adjust inventory
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_order_payload->'line_items')
    LOOP
        -- Find the corresponding product variant
        SELECT id INTO v_variant_id FROM public.product_variants
        WHERE company_id = p_company_id AND sku = v_item->>'sku';
        
        -- Lock the variant row to prevent race conditions
        IF v_variant_id IS NOT NULL THEN
            PERFORM * FROM public.product_variants WHERE id = v_variant_id FOR UPDATE;
        END IF;

        -- Insert line item
        INSERT INTO public.order_line_items (
            order_id, variant_id, company_id, product_name, variant_title, sku,
            quantity, price, total_discount, tax_amount, external_line_item_id
        )
        VALUES (
            v_order_id, v_variant_id, p_company_id, v_item->>'name', v_item->>'variant_title',
            v_item->>'sku', (v_item->>'quantity')::INT, (v_item->>'price')::NUMERIC * 100,
            (v_item->>'total_discount')::NUMERIC * 100,
            (v_item->'tax_lines'->0->>'price')::NUMERIC * 100,
            (v_item->>'id')::TEXT
        );

        -- Adjust inventory if variant exists
        IF v_variant_id IS NOT NULL THEN
            UPDATE public.product_variants
            SET inventory_quantity = inventory_quantity - (v_item->>'quantity')::INT
            WHERE id = v_variant_id;

            INSERT INTO public.inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes)
            SELECT p_company_id, v_variant_id, 'sale', -(v_item->>'quantity')::INT, pv.inventory_quantity, v_order_id, 'Order #' || (p_order_payload->>'number')
            FROM public.product_variants pv WHERE pv.id = v_variant_id;
        END IF;
    END LOOP;

    -- Update customer stats
    UPDATE public.customers
    SET
        total_orders = total_orders + 1,
        total_spent = total_spent + ((p_order_payload->>'total_price')::NUMERIC * 100)::INT,
        first_order_date = LEAST(first_order_date, (p_order_payload->>'created_at')::TIMESTAMPTZ)
    WHERE id = v_customer_id;
END;
$$ LANGUAGE plpgsql;

-- Procedure to clean up old data
CREATE OR REPLACE FUNCTION cleanup_old_data()
RETURNS void AS $$
DECLARE
    retention_period_logs INTERVAL := '90 days';
    retention_period_messages INTERVAL := '1 year';
BEGIN
    -- Delete old audit logs
    DELETE FROM public.audit_log
    WHERE created_at < (now() AT TIME ZONE 'utc') - retention_period_logs;

    -- Delete old chat messages (for non-starred conversations)
    DELETE FROM public.messages m
    USING public.conversations c
    WHERE m.conversation_id = c.id
      AND c.is_starred = FALSE
      AND m.created_at < (now() AT TIME ZONE 'utc') - retention_period_messages;

END;
$$ LANGUAGE plpgsql;
