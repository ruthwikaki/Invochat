-- InvoChat Database Schema
-- Version: 1.5.0
-- Description: This script defines the complete database structure for the InvoChat application.
-- It is designed to be idempotent and can be safely run multiple times.

-- 1. Extensions
-- Enable pgcrypto for UUID generation
CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "public";
CREATE EXTENSION IF NOT EXISTS "vector" WITH SCHEMA "public";

-- 2. Custom Types
-- Drop existing types if they exist to prevent conflicts
DROP TYPE IF EXISTS public.user_role;
CREATE TYPE public.user_role AS ENUM ('Owner', 'Admin', 'Member');

-- 3. Tables
-- Note: The order of table creation is important to satisfy foreign key constraints.

-- Companies Table: Represents a tenant in the multi-tenant architecture.
CREATE TABLE IF NOT EXISTS public.companies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);
COMMENT ON TABLE public.companies IS 'Stores company-level information for multi-tenancy.';

-- Profiles Table: Stores user-specific data, linked to auth.users.
CREATE TABLE IF NOT EXISTS public.profiles (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE,
    first_name TEXT,
    last_name TEXT,
    role user_role NOT NULL DEFAULT 'Member',
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    updated_at TIMESTAMPTZ
);
COMMENT ON TABLE public.profiles IS 'Stores user profiles and their association with a company.';

-- Company Settings Table: Configurable business logic parameters per company.
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id UUID PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days INT NOT NULL DEFAULT 90,
    fast_moving_days INT NOT NULL DEFAULT 30,
    predictive_stock_days INT NOT NULL DEFAULT 7,
    overstock_multiplier INT NOT NULL DEFAULT 3,
    high_value_threshold INT NOT NULL DEFAULT 100000, -- in cents
    promo_sales_lift_multiplier REAL NOT NULL DEFAULT 2.5,
    currency TEXT DEFAULT 'USD',
    timezone TEXT DEFAULT 'UTC',
    tax_rate NUMERIC(5, 4) DEFAULT 0.0000,
    custom_rules JSONB,
    subscription_plan TEXT DEFAULT 'starter',
    subscription_status TEXT DEFAULT 'trial',
    subscription_expires_at TIMESTAMPTZ,
    stripe_customer_id TEXT,
    stripe_subscription_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    updated_at TIMESTAMPTZ
);
COMMENT ON TABLE public.company_settings IS 'Stores settings and business logic parameters for each company.';

-- Suppliers Table
CREATE TABLE IF NOT EXISTS public.suppliers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    default_lead_time_days INT,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    updated_at TIMESTAMPTZ
);
COMMENT ON TABLE public.suppliers IS 'Stores supplier and vendor information.';

-- Products Table
CREATE TABLE IF NOT EXISTS public.products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    handle TEXT,
    product_type TEXT,
    tags TEXT[],
    status TEXT,
    image_url TEXT,
    external_product_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, external_product_id)
);
COMMENT ON TABLE public.products IS 'Core product information.';

-- Product Variants Table
CREATE TABLE IF NOT EXISTS public.product_variants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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
    location TEXT, -- Simple text field for bin/shelf location
    external_variant_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, sku),
    UNIQUE(company_id, external_variant_id)
);
COMMENT ON TABLE public.product_variants IS 'Stores individual product variants (SKUs).';

-- Customers Table
CREATE TABLE IF NOT EXISTS public.customers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name TEXT,
    email TEXT,
    total_orders INT DEFAULT 0,
    total_spent INT DEFAULT 0,
    first_order_date DATE,
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    updated_at TIMESTAMPTZ
);
COMMENT ON TABLE public.customers IS 'Stores customer data.';

-- Orders Table
CREATE TABLE IF NOT EXISTS public.orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number TEXT NOT NULL,
    external_order_id TEXT,
    customer_id UUID REFERENCES public.customers(id),
    financial_status TEXT,
    fulfillment_status TEXT,
    currency TEXT,
    subtotal INT NOT NULL,
    total_tax INT,
    total_shipping INT,
    total_discounts INT,
    total_amount INT NOT NULL,
    source_platform TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    updated_at TIMESTAMPTZ
);
COMMENT ON TABLE public.orders IS 'Stores sales order information.';

-- Order Line Items Table
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id UUID REFERENCES public.product_variants(id) ON DELETE SET NULL,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
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
COMMENT ON TABLE public.order_line_items IS 'Stores individual line items for each order.';

-- Inventory Ledger Table
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type TEXT NOT NULL,
    quantity_change INT NOT NULL,
    new_quantity INT NOT NULL,
    related_id UUID,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);
COMMENT ON TABLE public.inventory_ledger IS 'Transactional log of all inventory movements.';

-- Integrations Table
CREATE TABLE IF NOT EXISTS public.integrations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform TEXT NOT NULL,
    shop_domain TEXT,
    shop_name TEXT,
    is_active BOOLEAN DEFAULT false,
    last_sync_at TIMESTAMPTZ,
    sync_status TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, platform)
);
COMMENT ON TABLE public.integrations IS 'Stores integration settings for each company.';

-- Webhook Events Table
CREATE TABLE IF NOT EXISTS public.webhook_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id UUID NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id TEXT NOT NULL,
    processed_at TIMESTAMPTZ DEFAULT (now() AT TIME ZONE 'utc'),
    created_at TIMESTAMPTZ DEFAULT (now() AT TIME ZONE 'utc'),
    UNIQUE(integration_id, webhook_id)
);
COMMENT ON TABLE public.webhook_events IS 'Stores processed webhook IDs to prevent replay attacks.';

-- Audit Log Table
CREATE TABLE IF NOT EXISTS public.audit_log (
    id BIGSERIAL PRIMARY KEY,
    company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id UUID,
    action TEXT NOT NULL,
    details JSONB,
    created_at TIMESTAMPTZ DEFAULT (now() AT TIME ZONE 'utc')
);
COMMENT ON TABLE public.audit_log IS 'Records important actions for auditing and security.';

-- Conversations Table
CREATE TABLE IF NOT EXISTS public.conversations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT (now() AT TIME ZONE 'utc'),
    last_accessed_at TIMESTAMPTZ DEFAULT (now() AT TIME ZONE 'utc'),
    is_starred BOOLEAN DEFAULT FALSE
);
COMMENT ON TABLE public.conversations IS 'Stores chat conversation threads.';

-- Messages Table
CREATE TABLE IF NOT EXISTS public.messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role TEXT NOT NULL,
    content TEXT,
    component TEXT,
    component_props JSONB,
    visualization JSONB,
    confidence NUMERIC(3, 2),
    assumptions TEXT[],
    is_error BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT (now() AT TIME ZONE 'utc')
);
COMMENT ON TABLE public.messages IS 'Stores individual chat messages within a conversation.';


-- 4. Helper Functions & Triggers

-- Function to get the company_id from the current user's profile
CREATE OR REPLACE FUNCTION public.get_current_company_id()
RETURNS UUID AS $$
BEGIN
  RETURN (SELECT company_id FROM public.profiles WHERE user_id = auth.uid());
EXCEPTION
  WHEN OTHERS THEN
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
COMMENT ON FUNCTION public.get_current_company_id() IS 'Retrieves the company_id for the currently authenticated user.';

-- Trigger function to automatically update 'updated_at' columns
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = (now() AT TIME ZONE 'utc');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION public.set_updated_at() IS 'Sets the updated_at column to the current UTC timestamp on row update.';

-- Function to apply the updated_at trigger to multiple tables
CREATE OR REPLACE FUNCTION public.apply_updated_at_trigger(table_names TEXT[])
RETURNS void AS $$
DECLARE
    table_name TEXT;
BEGIN
    FOREACH table_name IN ARRAY table_names
    LOOP
        EXECUTE 'DROP TRIGGER IF EXISTS handle_updated_at ON public.' || quote_ident(table_name);
        EXECUTE 'CREATE TRIGGER handle_updated_at BEFORE UPDATE ON public.' || quote_ident(table_name) || ' FOR EACH ROW EXECUTE FUNCTION public.set_updated_at()';
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Apply the trigger to all tables that have an 'updated_at' column
SELECT public.apply_updated_at_trigger(ARRAY[
    'profiles', 'company_settings', 'suppliers', 'products', 'product_variants',
    'customers', 'orders', 'integrations'
]);

-- Trigger to create a company and profile for a new user
CREATE OR REPLACE FUNCTION public.on_auth_user_created()
RETURNS TRIGGER AS $$
DECLARE
  new_company_id UUID;
  user_company_name TEXT;
BEGIN
  -- Create a new company for the user
  user_company_name := COALESCE(NEW.raw_app_meta_data->>'company_name', 'My Company');
  INSERT INTO public.companies (name) VALUES (user_company_name) RETURNING id INTO new_company_id;

  -- Create a profile for the new user, linking them to the new company as 'Owner'
  INSERT INTO public.profiles (user_id, company_id, role, first_name, last_name)
  VALUES (NEW.id, new_company_id, 'Owner', NEW.raw_user_meta_data->>'first_name', NEW.raw_user_meta_data->>'last_name');

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Apply the user creation trigger
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.on_auth_user_created();


-- 5. Views

-- A comprehensive view for inventory items with all relevant details
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.id,
    pv.product_id,
    pv.company_id,
    pv.sku,
    pv.title,
    pv.option1_name,
    pv.option1_value,
    pv.option2_name,
    pv.option2_value,
    pv.option3_name,
    pv.option3_value,
    pv.barcode,
    pv.price,
    pv.compare_at_price,
    pv.cost,
    pv.inventory_quantity,
    pv.location,
    pv.external_variant_id,
    pv.created_at,
    pv.updated_at,
    p.title AS product_title,
    p.status AS product_status,
    p.image_url,
    p.product_type
FROM
    public.product_variants pv
LEFT JOIN
    public.products p ON pv.product_id = p.id;

COMMENT ON VIEW public.product_variants_with_details IS 'Denormalized view combining product variants with key details from the parent product table for efficient querying.';


-- 6. Indexes
-- Create indexes for performance on frequently queried columns.
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_company_id ON public.product_variants(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON public.orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON public.order_line_items(variant_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id ON public.inventory_ledger(variant_id);
CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON public.suppliers(company_id);
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers(company_id);
CREATE INDEX IF NOT EXISTS idx_integrations_company_id ON public.integrations(company_id);
CREATE INDEX IF NOT EXISTS idx_conversations_user_id ON public.conversations(user_id);
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id ON public.messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_company_id ON public.audit_log(company_id);
CREATE INDEX IF NOT EXISTS idx_profiles_user_id ON public.profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_profiles_company_id ON public.profiles(company_id);


-- 7. Row-Level Security (RLS)
-- Enable RLS for all relevant tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- RLS Policies
-- Users can only see their own profile
DROP POLICY IF EXISTS "Allow individual access to own profile" ON public.profiles;
CREATE POLICY "Allow individual access to own profile" ON public.profiles
    FOR SELECT USING (auth.uid() = user_id);

-- Users can see other users in their own company
DROP POLICY IF EXISTS "Allow read access to other users in same company" ON public.profiles;
CREATE POLICY "Allow read access to other users in same company" ON public.profiles
    FOR SELECT USING (company_id = get_current_company_id());

-- Users can only see their own company's data
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.companies;
CREATE POLICY "Allow full access based on company_id" ON public.companies
    FOR ALL USING (id = get_current_company_id());

-- Generic policy creation function for tenant isolation
CREATE OR REPLACE FUNCTION public.create_tenant_rls_policy(table_name TEXT)
RETURNS void AS $$
BEGIN
    EXECUTE format(
        'DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.%I;' ||
        'CREATE POLICY "Allow full access based on company_id" ON public.%I ' ||
        'FOR ALL USING (company_id = get_current_company_id());',
        table_name, table_name
    );
END;
$$ LANGUAGE plpgsql;

-- Apply the generic RLS policy to all company-scoped tables
SELECT public.create_tenant_rls_policy(t) FROM unnest(ARRAY[
    'company_settings', 'products', 'product_variants', 'inventory_ledger',
    'customers', 'orders', 'order_line_items', 'suppliers',
    'integrations', 'conversations', 'messages'
]) AS t;

-- Special RLS policies
DROP POLICY IF EXISTS "Allow read access to company audit log" ON public.audit_log;
CREATE POLICY "Allow read access to company audit log" ON public.audit_log
    FOR SELECT USING (company_id = get_current_company_id());

DROP POLICY IF EXISTS "Allow read access to webhook_events" ON public.webhook_events;
CREATE POLICY "Allow read access to webhook_events" ON public.webhook_events
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.integrations i
            WHERE i.id = webhook_events.integration_id AND i.company_id = get_current_company_id()
        )
    );

DROP POLICY IF EXISTS "Users can manage their own conversations" ON public.conversations;
CREATE POLICY "Users can manage their own conversations" ON public.conversations
    FOR ALL USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can manage messages in their own conversations" ON public.messages;
CREATE POLICY "Users can manage messages in their own conversations" ON public.messages
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM public.conversations c
            WHERE c.id = messages.conversation_id AND c.user_id = auth.uid()
        )
    );

-- Grant usage on the public schema to authenticated users
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;


-- 8. Transactional Functions
-- More robust function for recording sales, ensuring atomicity
CREATE OR REPLACE FUNCTION public.record_order_from_platform(p_company_id UUID, p_order_payload JSONB, p_platform TEXT)
RETURNS void AS $$
DECLARE
    v_customer_id UUID;
    v_order_id UUID;
    v_line_item JSONB;
    v_variant_id UUID;
    v_quantity INT;
    v_email TEXT;
BEGIN
    -- Step 1: Find or create the customer
    v_email := p_order_payload->'customer'->>'email';
    IF v_email IS NOT NULL THEN
        SELECT id INTO v_customer_id FROM public.customers
        WHERE company_id = p_company_id AND email = v_email;

        IF v_customer_id IS NULL THEN
            INSERT INTO public.customers (company_id, customer_name, email, first_order_date)
            VALUES (
                p_company_id,
                COALESCE(p_order_payload->'customer'->>'first_name' || ' ' || p_order_payload->'customer'->>'last_name', 'Walk-in Customer'),
                v_email,
                (p_order_payload->>'created_at')::date
            ) RETURNING id INTO v_customer_id;
        END IF;
    END IF;

    -- Step 2: Insert the order
    INSERT INTO public.orders (
        company_id, external_order_id, order_number, customer_id, financial_status,
        fulfillment_status, currency, subtotal, total_tax, total_shipping, total_discounts,
        total_amount, source_platform, created_at
    ) VALUES (
        p_company_id,
        p_order_payload->>'id',
        p_order_payload->>'order_number',
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
        (p_order_payload->>'created_at')::timestamptz
    ) RETURNING id INTO v_order_id;

    -- Step 3: Loop through line items, adjust inventory, and record line items
    FOR v_line_item IN SELECT * FROM jsonb_array_elements(p_order_payload->'line_items')
    LOOP
        -- Find the corresponding product variant
        SELECT id INTO v_variant_id FROM public.product_variants
        WHERE company_id = p_company_id AND external_variant_id = v_line_item->>'variant_id';

        IF v_variant_id IS NOT NULL THEN
            v_quantity := (v_line_item->>'quantity')::int;

            -- Atomically update inventory and log the change
            UPDATE public.product_variants
            SET inventory_quantity = inventory_quantity - v_quantity
            WHERE id = v_variant_id;

            INSERT INTO public.inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes)
            SELECT p_company_id, v_variant_id, 'sale', -v_quantity, inventory_quantity, v_order_id, 'Order #' || (p_order_payload->>'order_number')
            FROM public.product_variants WHERE id = v_variant_id;

            -- Insert the order line item
            INSERT INTO public.order_line_items (
                order_id, company_id, variant_id, product_name, sku, quantity, price, external_line_item_id
            ) VALUES (
                v_order_id, p_company_id, v_variant_id, v_line_item->>'title', v_line_item->>'sku', v_quantity,
                (v_line_item->>'price')::numeric * 100, v_line_item->>'id'
            );
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION public.record_order_from_platform IS 'Atomically records a sales order and updates inventory levels from a platform payload.';

-- 9. Cleanup old data cron job
CREATE OR REPLACE FUNCTION public.cleanup_old_data()
RETURNS void AS $$
BEGIN
    -- Delete audit logs older than 90 days
    DELETE FROM public.audit_log WHERE created_at < now() - interval '90 days';
    
    -- Delete messages from conversations not accessed in 90 days
    DELETE FROM public.messages WHERE conversation_id IN (
        SELECT id FROM public.conversations WHERE last_accessed_at < now() - interval '90 days'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
COMMENT ON FUNCTION public.cleanup_old_data IS 'Cron job function to clean up old audit logs and messages.';


-- Final script completion message
-- This line doesn't do anything but signals the end of the script.
SELECT 'InvoChat schema setup complete.';
