
-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ### Functions for Auth and RLS ###

-- Custom function to get the company_id from the current user's profile
CREATE OR REPLACE FUNCTION get_current_company_id()
RETURNS UUID AS $$
DECLARE
  company_id_val UUID;
BEGIN
  -- We now get the company_id from the user's profile, not the auth.users metadata.
  select company_id into company_id_val from public.profiles where user_id = auth.uid();
  RETURN company_id_val;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Custom function to extract the company name from signup metadata
CREATE OR REPLACE FUNCTION get_company_name_from_metadata()
RETURNS TEXT AS $$
BEGIN
    RETURN current_setting('request.jwt.claims', true)::jsonb->'raw_user_meta_data'->>'company_name';
END;
$$ LANGUAGE plpgsql;


-- ### Tables ###

-- Create companies table to hold company information
CREATE TABLE IF NOT EXISTS public.companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() at time zone 'utc')
);

-- Create profiles table to store user-specific data, linking to auth.users
CREATE TABLE IF NOT EXISTS public.profiles (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE NOT NULL,
    first_name TEXT,
    last_name TEXT,
    role TEXT CHECK (role IN ('Owner', 'Admin', 'Member')) DEFAULT 'Member',
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() at time zone 'utc'),
    updated_at TIMESTAMPTZ
);
COMMENT ON TABLE public.profiles IS 'Stores user-specific application data, linked to the authentication user.';

-- Create company_settings table
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
    tax_rate NUMERIC DEFAULT 0,
    custom_rules JSONB,
    subscription_plan TEXT DEFAULT 'starter',
    subscription_status TEXT DEFAULT 'trial',
    subscription_expires_at TIMESTAMPTZ,
    stripe_customer_id TEXT,
    stripe_subscription_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() at time zone 'utc'),
    updated_at TIMESTAMPTZ
);

-- Create products table
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

-- Create product_variants table
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
    compare_at_price INT,
    cost INT,
    inventory_quantity INT DEFAULT 0 NOT NULL,
    location TEXT NULL, -- a simple text field for bin location, etc.
    external_variant_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() at time zone 'utc'),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, sku),
    UNIQUE(company_id, external_variant_id)
);

-- Create suppliers table
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

-- Create inventory_ledger table to track stock movements
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type TEXT NOT NULL, -- e.g., 'sale', 'purchase_order', 'reconciliation'
    quantity_change INT NOT NULL,
    new_quantity INT NOT NULL,
    related_id UUID, -- e.g., order_id, purchase_order_id
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() at time zone 'utc')
);

-- Create customers table
CREATE TABLE IF NOT EXISTS public.customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name TEXT NOT NULL,
    email TEXT,
    total_orders INT DEFAULT 0,
    total_spent INT DEFAULT 0, -- in cents
    first_order_date DATE,
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() at time zone 'utc')
);

-- Create orders table
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
    total_amount INT NOT NULL,
    source_platform TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() at time zone 'utc'),
    updated_at TIMESTAMPTZ
);

-- Create order_line_items table
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id UUID REFERENCES public.product_variants(id),
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

-- Create integrations table
CREATE TABLE IF NOT EXISTS public.integrations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform TEXT NOT NULL,
    shop_domain TEXT,
    shop_name TEXT,
    is_active BOOLEAN DEFAULT false,
    last_sync_at TIMESTAMPTZ,
    sync_status TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() at time zone 'utc'),
    updated_at TIMESTAMPTZ
);

-- Create conversations table for chat history
CREATE TABLE IF NOT EXISTS public.conversations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT (now() at time zone 'utc'),
  last_accessed_at TIMESTAMPTZ DEFAULT (now() at time zone 'utc'),
  is_starred BOOLEAN DEFAULT false
);

-- Create messages table for individual chat messages
CREATE TABLE IF NOT EXISTS public.messages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  role TEXT NOT NULL,
  content TEXT,
  component TEXT,
  component_props JSONB,
  visualization JSONB,
  confidence NUMERIC,
  assumptions TEXT[],
  is_error BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT (now() at time zone 'utc')
);

-- Create audit_log table
CREATE TABLE IF NOT EXISTS public.audit_log (
  id BIGSERIAL PRIMARY KEY,
  company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE,
  user_id UUID, -- Can be null for system actions
  action TEXT NOT NULL,
  details JSONB,
  created_at TIMESTAMPTZ DEFAULT (now() at time zone 'utc')
);

-- Create webhook_events table for replay protection
CREATE TABLE IF NOT EXISTS public.webhook_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  integration_id UUID NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
  webhook_id TEXT NOT NULL,
  processed_at TIMESTAMPTZ DEFAULT (now() at time zone 'utc'),
  created_at TIMESTAMPTZ DEFAULT (now() at time zone 'utc'),
  UNIQUE(integration_id, webhook_id)
);


-- ### Triggers and Functions ###

-- Function to automatically set updated_at timestamp
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = (now() at time zone 'utc');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger application function
CREATE OR REPLACE FUNCTION public.apply_updated_at_trigger(table_name TEXT)
RETURNS void AS $$
BEGIN
    EXECUTE format('DROP TRIGGER IF EXISTS handle_updated_at ON public.%I;', table_name);
    EXECUTE format('
        CREATE TRIGGER handle_updated_at
        BEFORE UPDATE ON public.%I
        FOR EACH ROW
        EXECUTE FUNCTION public.set_updated_at();
    ', table_name);
END;
$$ LANGUAGE plpgsql;

-- Apply the trigger to all relevant tables
SELECT public.apply_updated_at_trigger(table_name)
FROM (VALUES
    ('profiles'),
    ('company_settings'),
    ('products'),
    ('product_variants'),
    ('suppliers'),
    ('orders'),
    ('integrations')
) AS t(table_name);

-- Trigger function to handle new user sign-ups
CREATE OR REPLACE FUNCTION public.on_auth_user_created()
RETURNS TRIGGER AS $$
DECLARE
  company_name_val TEXT;
  new_company_id UUID;
BEGIN
  -- Extract company name from metadata
  company_name_val := get_company_name_from_metadata();

  -- Create a new company
  INSERT INTO public.companies (name) VALUES (company_name_val)
  RETURNING id INTO new_company_id;

  -- Create a profile for the new user, linking them to the new company
  INSERT INTO public.profiles (user_id, company_id, role)
  VALUES (NEW.id, new_company_id, 'Owner');

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Apply the user creation trigger
DROP TRIGGER IF EXISTS on_auth_user_created_trigger ON auth.users;
CREATE TRIGGER on_auth_user_created_trigger
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.on_auth_user_created();


-- ### Database Views ###

-- Create a view for a unified inventory list
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.id,
    pv.product_id,
    pv.company_id,
    p.title AS product_title,
    pv.title AS variant_title,
    pv.sku,
    p.status AS product_status,
    p.product_type,
    p.image_url,
    pv.inventory_quantity,
    pv.price,
    pv.cost,
    pv.location,
    pv.created_at,
    pv.updated_at
FROM
    public.product_variants pv
LEFT JOIN
    public.products p ON pv.product_id = p.id;


-- ### Row-Level Security (RLS) ###

-- Enable RLS on all tables
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
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;

-- RLS Policies
DROP POLICY IF EXISTS "Allow full access based on user_id" ON public.profiles;
CREATE POLICY "Allow full access based on user_id" ON public.profiles
  FOR ALL USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can only see their own company" ON public.companies;
CREATE POLICY "Users can only see their own company" ON public.companies
  FOR SELECT USING (id = get_current_company_id());

DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.company_settings;
CREATE POLICY "Allow full access based on company_id" ON public.company_settings
  FOR ALL USING (company_id = get_current_company_id());

DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.products;
CREATE POLICY "Allow full access based on company_id" ON public.products
  FOR ALL USING (company_id = get_current_company_id());

DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.product_variants;
CREATE POLICY "Allow full access based on company_id" ON public.product_variants
  FOR ALL USING (company_id = get_current_company_id());

DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.inventory_ledger;
CREATE POLICY "Allow full access based on company_id" ON public.inventory_ledger
  FOR ALL USING (company_id = get_current_company_id());

DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.customers;
CREATE POLICY "Allow full access based on company_id" ON public.customers
  FOR ALL USING (company_id = get_current_company_id());

DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.orders;
CREATE POLICY "Allow full access based on company_id" ON public.orders
  FOR ALL USING (company_id = get_current_company_id());

DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.order_line_items;
CREATE POLICY "Allow full access based on company_id" ON public.order_line_items
  FOR ALL USING (company_id = get_current_company_id());

DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.suppliers;
CREATE POLICY "Allow full access based on company_id" ON public.suppliers
  FOR ALL USING (company_id = get_current_company_id());

DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.integrations;
CREATE POLICY "Allow full access based on company_id" ON public.integrations
  FOR ALL USING (company_id = get_current_company_id());

DROP POLICY IF EXISTS "Allow access based on company_id" ON public.conversations;
CREATE POLICY "Allow access based on company_id" ON public.conversations
  FOR ALL USING (company_id = get_current_company_id());

DROP POLICY IF EXISTS "Allow access based on company_id" ON public.messages;
CREATE POLICY "Allow access based on company_id" ON public.messages
  FOR ALL USING (company_id = get_current_company_id());
  
DROP POLICY IF EXISTS "Allow read access to company audit log" ON public.audit_log;
CREATE POLICY "Allow read access to company audit log" ON public.audit_log
  FOR SELECT USING (company_id = get_current_company_id());
  
DROP POLICY IF EXISTS "Allow read access to webhook_events" ON public.webhook_events;
CREATE POLICY "Allow read access to webhook_events" ON public.webhook_events
  FOR SELECT USING (
    EXISTS (
        SELECT 1 FROM public.integrations
        WHERE integrations.id = webhook_events.integration_id
        AND integrations.company_id = get_current_company_id()
    )
  );

-- ### Indexes ###

CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_variants_company_id ON public.product_variants(company_id);
CREATE INDEX IF NOT EXISTS idx_variants_sku ON public.product_variants(sku);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_ledger_variant_id ON public.inventory_ledger(variant_id);
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers(company_id);
CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON public.suppliers(company_id);
CREATE INDEX IF NOT EXISTS idx_integrations_company_id ON public.integrations(company_id);
CREATE INDEX IF NOT EXISTS idx_conversations_user_id ON public.conversations(user_id);
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id ON public.messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_profiles_company_id ON public.profiles(company_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_company_user ON public.audit_log(company_id, user_id, created_at DESC);

-- ### Advanced Database Functions for Analytics (RPC) ###

CREATE OR REPLACE FUNCTION public.record_sale_transaction(
    p_company_id UUID,
    p_user_id UUID,
    p_customer_name TEXT,
    p_customer_email TEXT,
    p_payment_method TEXT,
    p_notes TEXT,
    p_sale_items JSONB,
    p_external_id TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_customer_id UUID;
    v_order_id UUID;
    v_item JSONB;
    v_variant_id UUID;
    v_quantity INT;
BEGIN
    -- This function now correctly uses `SELECT ... FOR UPDATE` to prevent race conditions
    -- when updating inventory quantities. This is a critical fix for data integrity.

    -- Upsert customer
    IF p_customer_email IS NOT NULL THEN
        SELECT id INTO v_customer_id FROM public.customers WHERE email = p_customer_email AND company_id = p_company_id;
        IF v_customer_id IS NULL THEN
            INSERT INTO public.customers (company_id, customer_name, email)
            VALUES (p_company_id, p_customer_name, p_customer_email)
            RETURNING id INTO v_customer_id;
        END IF;
    END IF;

    -- Create order
    INSERT INTO public.orders (company_id, customer_id, order_number, total_amount, source_platform, external_order_id)
    VALUES (p_company_id, v_customer_id, 'SALE-' || substr(uuid_generate_v4()::text, 1, 8), 0, 'manual', p_external_id)
    RETURNING id INTO v_order_id;
    
    -- Process line items
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_sale_items)
    LOOP
        SELECT id INTO v_variant_id FROM public.product_variants WHERE sku = v_item->>'sku' AND company_id = p_company_id;
        v_quantity := (v_item->>'quantity')::INT;

        IF v_variant_id IS NOT NULL THEN
            -- Lock the variant row to prevent race conditions
            PERFORM * FROM public.product_variants WHERE id = v_variant_id FOR UPDATE;

            INSERT INTO public.order_line_items (order_id, variant_id, company_id, product_name, sku, quantity, price, cost_at_time)
            VALUES (v_order_id, v_variant_id, p_company_id, v_item->>'product_name', v_item->>'sku', v_quantity, (v_item->>'unit_price')::INT, (v_item->>'cost_at_time')::INT);

            -- Update inventory and log it
            UPDATE public.product_variants SET inventory_quantity = inventory_quantity - v_quantity WHERE id = v_variant_id;
            
            INSERT INTO public.inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes)
            SELECT p_company_id, v_variant_id, 'sale', -v_quantity, inventory_quantity, v_order_id, 'Order ' || (SELECT order_number FROM public.orders WHERE id = v_order_id)
            FROM public.product_variants WHERE id = v_variant_id;
        END IF;
    END LOOP;

    -- Update order total
    UPDATE public.orders o
    SET total_amount = (SELECT COALESCE(SUM(oli.price * oli.quantity), 0) FROM public.order_line_items oli WHERE oli.order_id = v_order_id)
    WHERE o.id = v_order_id;

    RETURN v_order_id;
END;
$$ LANGUAGE plpgsql;


-- Function to periodically clean up old data to keep the database size manageable.
CREATE OR REPLACE FUNCTION public.cleanup_old_data()
RETURNS void AS $$
DECLARE
    retention_period_audit INTERVAL := '90 days';
    retention_period_messages INTERVAL := '180 days';
BEGIN
    -- Delete old audit logs
    DELETE FROM public.audit_log
    WHERE created_at < (now() - retention_period_audit);

    -- Delete old chat messages
    DELETE FROM public.messages
    WHERE created_at < (now() - retention_period_messages);

END;
$$ LANGUAGE plpgsql;


-- Final check to ensure RLS is enforced for the security definer functions
ALTER FUNCTION public.get_current_company_id() SECURITY DEFINER;

-- Grant usage on functions to the authenticated role
GRANT EXECUTE ON FUNCTION public.get_current_company_id() TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_sale_transaction(UUID, UUID, TEXT, TEXT, TEXT, TEXT, JSONB, TEXT) TO authenticated;
