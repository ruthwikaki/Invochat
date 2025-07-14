
-- Enable the UUID extension if it doesn't exist
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Enable the pg_stat_statements extension for monitoring query performance
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";

-- Enable the pgcrypto extension for hashing
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ### Helper Functions ###

-- Function to get the current user's company_id from their JWT claims
CREATE OR REPLACE FUNCTION get_current_company_id()
RETURNS UUID AS $$
DECLARE
    company_id_claim UUID;
BEGIN
    SELECT current_setting('request.jwt.claims', true)::jsonb ->> 'company_id' INTO company_id_claim;
    RETURN company_id_claim;
EXCEPTION
    WHEN others THEN
        RETURN NULL; -- Return null if the claim doesn't exist or is invalid
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to automatically set the `updated_at` timestamp
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = (now() at time zone 'utc');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Procedure to apply the `updated_at` trigger to a list of tables
CREATE OR REPLACE PROCEDURE apply_updated_at_trigger(p_table_names TEXT[])
LANGUAGE plpgsql AS $$
DECLARE
    table_name TEXT;
BEGIN
    FOREACH table_name IN ARRAY p_table_names
    LOOP
        EXECUTE format('
            DROP TRIGGER IF EXISTS handle_updated_at ON public.%I;
            CREATE TRIGGER handle_updated_at
            BEFORE UPDATE ON public.%I
            FOR EACH ROW
            EXECUTE FUNCTION public.set_updated_at();
        ', table_name, table_name);
    END LOOP;
END;
$$;


-- ### Table Definitions ###

CREATE TABLE IF NOT EXISTS public.companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() at time zone 'utc')
);

CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id UUID PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days INT NOT NULL DEFAULT 90 CHECK (dead_stock_days >= 0),
    fast_moving_days INT NOT NULL DEFAULT 30 CHECK (fast_moving_days > 0),
    overstock_multiplier NUMERIC NOT NULL DEFAULT 3 CHECK (overstock_multiplier > 0),
    high_value_threshold INT NOT NULL DEFAULT 100000 CHECK (high_value_threshold >= 0), -- in cents
    predictive_stock_days INT NOT NULL DEFAULT 7 CHECK (predictive_stock_days > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() at time zone 'utc'),
    updated_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID REFERENCES public.companies(id) ON DELETE SET NULL,
    role TEXT NOT NULL CHECK (role IN ('Owner', 'Admin', 'Member')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() at time zone 'utc'),
    updated_at TIMESTAMPTZ
);

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
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() at time zone 'utc'),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, external_product_id)
);

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
    price INT CHECK (price IS NULL OR price >= 0), -- in cents
    compare_at_price INT CHECK (compare_at_price IS NULL OR compare_at_price >= 0),
    cost INT CHECK (cost IS NULL OR cost >= 0), -- in cents
    inventory_quantity INT NOT NULL DEFAULT 0,
    external_variant_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() at time zone 'utc'),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, sku),
    UNIQUE(company_id, external_variant_id)
);

CREATE TABLE IF NOT EXISTS public.customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name TEXT,
    email TEXT,
    total_orders INT NOT NULL DEFAULT 0,
    total_spent INT NOT NULL DEFAULT 0,
    first_order_date DATE,
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() at time zone 'utc'),
    UNIQUE(company_id, email)
);

CREATE TABLE IF NOT EXISTS public.orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number TEXT NOT NULL,
    external_order_id TEXT,
    customer_id UUID REFERENCES public.customers(id) ON DELETE SET NULL,
    financial_status TEXT,
    fulfillment_status TEXT,
    currency TEXT,
    subtotal INT NOT NULL CHECK (subtotal >= 0),
    total_tax INT CHECK (total_tax IS NULL OR total_tax >= 0),
    total_shipping INT CHECK (total_shipping IS NULL OR total_shipping >= 0),
    total_discounts INT CHECK (total_discounts IS NULL OR total_discounts >= 0),
    total_amount INT NOT NULL CHECK (total_amount >= 0),
    source_platform TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() at time zone 'utc'),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, external_order_id)
);

CREATE TABLE IF NOT EXISTS public.order_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id UUID REFERENCES public.product_variants(id) ON DELETE SET NULL,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_name TEXT,
    variant_title TEXT,
    sku TEXT,
    quantity INT NOT NULL CHECK (quantity > 0),
    price INT NOT NULL CHECK (price >= 0),
    total_discount INT CHECK (total_discount IS NULL OR total_discount >= 0),
    tax_amount INT CHECK (tax_amount IS NULL OR tax_amount >= 0),
    cost_at_time INT CHECK (cost_at_time IS NULL OR cost_at_time >= 0),
    external_line_item_id TEXT
);

CREATE TABLE IF NOT EXISTS public.suppliers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    default_lead_time_days INT,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() at time zone 'utc'),
    updated_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS public.conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() at time zone 'utc'),
    last_accessed_at TIMESTAMPTZ NOT NULL DEFAULT (now() at time zone 'utc'),
    is_starred BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE IF NOT EXISTS public.messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
    content TEXT NOT NULL,
    visualization JSONB,
    confidence NUMERIC,
    assumptions TEXT[],
    is_error BOOLEAN DEFAULT FALSE,
    component TEXT,
    component_props JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() at time zone 'utc')
);

CREATE TABLE IF NOT EXISTS public.integrations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform TEXT NOT NULL,
    shop_domain TEXT,
    shop_name TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    last_sync_at TIMESTAMPTZ,
    sync_status TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() at time zone 'utc'),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, platform)
);

CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type TEXT NOT NULL,
    quantity_change INT NOT NULL,
    new_quantity INT NOT NULL,
    related_id UUID, -- Can link to an order, purchase order, etc.
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() at time zone 'utc')
);

CREATE TABLE IF NOT EXISTS public.audit_log (
    id BIGSERIAL PRIMARY KEY,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    details JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() at time zone 'utc')
);

CREATE TABLE IF NOT EXISTS public.webhook_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    integration_id UUID NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() at time zone 'utc'),
    UNIQUE(webhook_id)
);


-- ### Triggers and Auth Functions ###

-- Trigger to create a user profile when a new user signs up
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    new_company_id UUID;
BEGIN
    -- Create a new company for the user
    INSERT INTO public.companies (name)
    VALUES (new.raw_user_meta_data->>'company_name')
    RETURNING id INTO new_company_id;

    -- Update the user's metadata with the new company_id
    UPDATE auth.users
    SET raw_app_meta_data = jsonb_set(
        COALESCE(raw_app_meta_data, '{}'::jsonb),
        '{company_id}',
        to_jsonb(new_company_id)
    )
    WHERE id = NEW.id;

    -- Insert into the public.users table
    INSERT INTO public.users (id, company_id, role)
    VALUES (new.id, new_company_id, 'Owner');
    RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_user();

-- Apply `updated_at` triggers to all relevant tables
DO $$
BEGIN
    CALL apply_updated_at_trigger(ARRAY[
        'company_settings', 'users', 'products', 'product_variants',
        'orders', 'suppliers', 'integrations'
    ]);
END
$$;


-- ### Indexes ###

-- Product related indexes
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_products_tags ON public.products USING GIN (tags);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_company_id ON public.product_variants(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_sku ON public.product_variants(sku);

-- Order related indexes
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON public.orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON public.order_line_items(variant_id);

-- Other indexes
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers(company_id);
CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON public.suppliers(company_id);
CREATE INDEX IF NOT EXISTS idx_conversations_user_id ON public.conversations(user_id);
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id ON public.messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_integrations_company_id ON public.integrations(company_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id ON public.inventory_ledger(variant_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_company_id ON public.audit_log(company_id);


-- ### Row-Level Security (RLS) ###

-- Procedure to create RLS policies for a list of tables
CREATE OR REPLACE PROCEDURE create_company_rls_policy(p_table_names TEXT[])
LANGUAGE plpgsql AS $$
DECLARE
    table_name TEXT;
BEGIN
    FOREACH table_name IN ARRAY p_table_names
    LOOP
        EXECUTE format('
            ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;
            DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.%I;
            CREATE POLICY "Allow full access based on company_id"
            ON public.%I
            FOR ALL
            USING (company_id = get_current_company_id())
            WITH CHECK (company_id = get_current_company_id());
        ', table_name, table_name, table_name);
    END LOOP;
END;
$$;

-- Apply RLS policies to all company-scoped tables
DO $$
BEGIN
    CALL create_company_rls_policy(ARRAY[
        'company_settings', 'products', 'product_variants', 'customers',
        'orders', 'order_line_items', 'suppliers', 'conversations',
        'messages', 'integrations', 'inventory_ledger'
    ]);
END
$$;

-- Special RLS policy for the `companies` table itself
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.companies;
CREATE POLICY "Allow full access based on company_id"
ON public.companies
FOR ALL
USING (id = get_current_company_id())
WITH CHECK (id = get_current_company_id());

-- Special RLS policies for the `users` table
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow user to manage themselves" ON public.users;
CREATE POLICY "Allow user to manage themselves"
ON public.users
FOR ALL
USING (id = auth.uid());

DROP POLICY IF EXISTS "Allow read access to other users in same company" ON public.users;
CREATE POLICY "Allow read access to other users in same company"
ON public.users
FOR SELECT
USING (company_id = get_current_company_id());

-- RLS for audit_log and webhook_events
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow read access to company audit log" ON public.audit_log;
CREATE POLICY "Allow read access to company audit log"
ON public.audit_log
FOR SELECT
USING (company_id = get_current_company_id());

ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow read access to webhook_events" ON public.webhook_events;
CREATE POLICY "Allow read access to webhook_events"
ON public.webhook_events
FOR SELECT
USING (company_id = (SELECT company_id FROM public.integrations i WHERE i.id = integration_id));


-- ### Views ###

CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.id,
    pv.product_id,
    pv.company_id,
    pv.sku,
    pv.title,
    p.title AS product_title,
    p.status AS product_status,
    p.image_url,
    p.product_type,
    pv.price,
    pv.cost,
    pv.inventory_quantity,
    pv.barcode,
    pv.updated_at
FROM
    public.product_variants pv
JOIN
    public.products p ON pv.product_id = p.id;


-- ### Database Functions (RPC) ###

-- Function to record a sale and update inventory atomically
CREATE OR REPLACE FUNCTION record_order_from_platform(p_company_id UUID, p_order_payload JSONB, p_platform TEXT)
RETURNS VOID AS $$
DECLARE
    v_customer_id UUID;
    v_order_id UUID;
    v_line_item JSONB;
    v_variant_id UUID;
    v_quantity INT;
    v_current_stock INT;
BEGIN
    -- Find or create customer
    SELECT id INTO v_customer_id FROM customers
    WHERE company_id = p_company_id AND email = p_order_payload->'customer'->>'email';

    IF v_customer_id IS NULL THEN
        INSERT INTO customers (company_id, customer_name, email)
        VALUES (
            p_company_id,
            p_order_payload->'customer'->>'first_name' || ' ' || p_order_payload->'customer'->>'last_name',
            p_order_payload->'customer'->>'email'
        )
        RETURNING id INTO v_customer_id;
    END IF;

    -- Insert the order
    INSERT INTO orders (
        company_id, customer_id, order_number, total_amount, subtotal,
        total_tax, total_discounts, total_shipping, currency, financial_status,
        fulfillment_status, source_platform, external_order_id, created_at
    )
    VALUES (
        p_company_id, v_customer_id, p_order_payload->>'id',
        (p_order_payload->>'total_price')::numeric * 100, (p_order_payload->>'subtotal_price')::numeric * 100,
        (p_order_payload->>'total_tax')::numeric * 100, (p_order_payload->>'total_discounts')::numeric * 100,
        (p_order_payload->'shipping_lines'->0->>'price')::numeric * 100, p_order_payload->>'currency',
        p_order_payload->>'financial_status', p_order_payload->>'fulfillment_status',
        p_platform, p_order_payload->>'id', (p_order_payload->>'created_at')::timestamptz
    )
    RETURNING id INTO v_order_id;

    -- Loop through line items and update inventory
    FOR v_line_item IN SELECT * FROM jsonb_array_elements(p_order_payload->'line_items')
    LOOP
        -- Find the corresponding product variant
        SELECT id INTO v_variant_id FROM product_variants
        WHERE company_id = p_company_id AND external_variant_id = v_line_item->>'variant_id';

        -- If variant exists, update inventory and log the transaction
        IF v_variant_id IS NOT NULL THEN
            v_quantity := (v_line_item->>'quantity')::int;

            -- Atomically update inventory and get the new stock level
            UPDATE product_variants
            SET inventory_quantity = inventory_quantity - v_quantity
            WHERE id = v_variant_id
            RETURNING inventory_quantity INTO v_current_stock;

            -- Log the inventory change
            INSERT INTO inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes)
            VALUES (p_company_id, v_variant_id, 'sale', -v_quantity, v_current_stock, v_order_id, 'Order #' || (p_order_payload->>'id'));

             -- Insert the line item
            INSERT INTO order_line_items (order_id, variant_id, company_id, quantity, price, sku, product_name)
            VALUES (v_order_id, v_variant_id, p_company_id, v_quantity, (v_line_item->>'price')::numeric * 100, v_line_item->>'sku', v_line_item->>'name');
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Function to handle data cleanup
CREATE OR REPLACE FUNCTION cleanup_old_data()
RETURNS void AS $$
BEGIN
    -- Delete audit logs older than 90 days
    DELETE FROM public.audit_log WHERE created_at < now() - interval '90 days';
    -- Delete webhook events older than 30 days
    DELETE FROM public.webhook_events WHERE created_at < now() - interval '30 days';
    -- Delete non-starred conversations that haven't been accessed in 180 days
    DELETE FROM public.conversations
    WHERE is_starred = FALSE AND last_accessed_at < now() - interval '180 days';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Set up cron job to run the cleanup task daily
-- This requires the pg_cron extension to be enabled on the Supabase instance.
-- The user needs to run this part manually in the Supabase SQL editor.
/*
SELECT cron.schedule(
    'daily-cleanup', -- name of the job
    '0 1 * * *',     -- every day at 1 AM UTC
    $$SELECT public.cleanup_old_data()$$
);
*/
```