
-- ===============================================================================================
-- InvoChat Database Schema
--
-- This script is designed to be idempotent, meaning it can be run multiple times
-- without causing errors or creating duplicate objects.
--
-- For this script to work, you must enable the `pgcrypto` extension in your Supabase project.
-- Go to Database -> Extensions and enable `pgcrypto`.
-- ===============================================================================================


-- ===============================================================================================
-- Section 1: Table Definitions
-- All tables are created here first to ensure dependencies are met.
-- ===============================================================================================

CREATE TABLE IF NOT EXISTS public.companies (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    name TEXT NOT NULL,
    created_at timestamptz DEFAULT (now() at time zone 'utc')
);
COMMENT ON TABLE public.companies IS 'Stores company/organization information.';

CREATE TABLE IF NOT EXISTS public.profiles (
    user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid REFERENCES public.companies(id) ON DELETE SET NULL,
    first_name TEXT,
    last_name TEXT,
    role TEXT DEFAULT 'Member'::text NOT NULL,
    created_at timestamptz DEFAULT (now() at time zone 'utc'),
    updated_at timestamptz
);
COMMENT ON TABLE public.profiles IS 'Stores user-specific profile data, linking auth users to companies.';

CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days INT NOT NULL DEFAULT 90,
    fast_moving_days INT NOT NULL DEFAULT 30,
    overstock_multiplier NUMERIC NOT NULL DEFAULT 3,
    high_value_threshold NUMERIC NOT NULL DEFAULT 1000,
    predictive_stock_days INT NOT NULL DEFAULT 7,
    created_at timestamptz DEFAULT (now() at time zone 'utc'),
    updated_at timestamptz
);
COMMENT ON TABLE public.company_settings IS 'Business logic settings for a company.';

CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    default_lead_time_days INT,
    notes TEXT,
    created_at timestamptz DEFAULT (now() at time zone 'utc'),
    updated_at timestamptz
);
COMMENT ON TABLE public.suppliers IS 'Stores supplier/vendor information.';

CREATE TABLE IF NOT EXISTS public.locations (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    is_default BOOLEAN DEFAULT false,
    created_at timestamptz DEFAULT (now() at time zone 'utc'),
    updated_at timestamptz
);
COMMENT ON TABLE public.locations IS 'Stores inventory locations like warehouses or stores.';


CREATE TABLE IF NOT EXISTS public.products (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    handle TEXT,
    product_type TEXT,
    tags TEXT[],
    status TEXT,
    image_url TEXT,
    external_product_id TEXT,
    created_at timestamptz DEFAULT (now() at time zone 'utc'),
    updated_at timestamptz,
    UNIQUE(company_id, external_product_id)
);
COMMENT ON TABLE public.products IS 'Core product information.';

CREATE TABLE IF NOT EXISTS public.product_variants (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku TEXT,
    title TEXT,
    option1_name TEXT,
    option1_value TEXT,
    option2_name TEXT,
    option2_value TEXT,
    option3_name TEXT,
    option3_value TEXT,
    barcode TEXT,
    price INT,
    compare_at_price INT,
    cost INT,
    inventory_quantity INT NOT NULL DEFAULT 0,
    location_id uuid REFERENCES public.locations(id) ON DELETE SET NULL,
    external_variant_id TEXT,
    created_at timestamptz DEFAULT (now() at time zone 'utc'),
    updated_at timestamptz,
    UNIQUE(company_id, sku),
    UNIQUE(company_id, external_variant_id)
);
COMMENT ON TABLE public.product_variants IS 'Specific variations of a product.';

CREATE TABLE IF NOT EXISTS public.customers (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name TEXT,
    email TEXT,
    total_orders INT DEFAULT 0,
    total_spent INT DEFAULT 0,
    first_order_date DATE,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT (now() at time zone 'utc'),
    updated_at timestamptz,
    UNIQUE(company_id, email)
);
COMMENT ON TABLE public.customers IS 'Stores customer information.';

CREATE TABLE IF NOT EXISTS public.orders (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number TEXT NOT NULL,
    external_order_id TEXT,
    customer_id uuid REFERENCES public.customers(id),
    financial_status TEXT,
    fulfillment_status TEXT,
    currency TEXT,
    subtotal INT,
    total_tax INT,
    total_shipping INT,
    total_discounts INT,
    total_amount INT,
    source_platform TEXT,
    created_at timestamptz DEFAULT (now() at time zone 'utc'),
    updated_at timestamptz,
    UNIQUE(company_id, external_order_id)
);
COMMENT ON TABLE public.orders IS 'Stores sales order information.';

CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id uuid REFERENCES public.product_variants(id),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
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
COMMENT ON TABLE public.order_line_items IS 'Individual line items for each order.';

CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    is_starred BOOLEAN DEFAULT false,
    created_at timestamptz DEFAULT (now() at time zone 'utc'),
    last_accessed_at timestamptz DEFAULT (now() at time zone 'utc')
);
COMMENT ON TABLE public.conversations IS 'Stores AI chat conversation history.';

CREATE TABLE IF NOT EXISTS public.messages (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
    content TEXT NOT NULL,
    visualization JSONB,
    confidence REAL,
    assumptions TEXT[],
    component TEXT,
    "componentProps" JSONB,
    "isError" BOOLEAN,
    created_at timestamptz DEFAULT (now() at time zone 'utc')
);
COMMENT ON TABLE public.messages IS 'Stores individual messages within a conversation.';

CREATE TABLE IF NOT EXISTS public.integrations (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform TEXT NOT NULL,
    shop_domain TEXT,
    shop_name TEXT,
    is_active BOOLEAN DEFAULT true,
    last_sync_at timestamptz,
    sync_status TEXT,
    created_at timestamptz DEFAULT (now() at time zone 'utc'),
    updated_at timestamptz,
    UNIQUE(company_id, platform)
);
COMMENT ON TABLE public.integrations IS 'Stores integration settings for platforms like Shopify.';

CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    location_id uuid NOT NULL REFERENCES public.locations(id) ON DELETE CASCADE,
    change_type TEXT NOT NULL,
    quantity_change INT NOT NULL,
    new_quantity INT NOT NULL,
    related_id uuid,
    notes TEXT,
    created_at timestamptz DEFAULT (now() at time zone 'utc')
);
COMMENT ON TABLE public.inventory_ledger IS 'Transactional log of all inventory movements.';

CREATE TABLE IF NOT EXISTS public.audit_log (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    details JSONB,
    created_at timestamptz DEFAULT (now() at time zone 'utc')
);
COMMENT ON TABLE public.audit_log IS 'Logs significant actions performed by users.';

CREATE TABLE IF NOT EXISTS public.webhook_events (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id TEXT NOT NULL,
    received_at timestamptz DEFAULT (now() at time zone 'utc'),
    UNIQUE(webhook_id)
);
COMMENT ON TABLE public.webhook_events IS 'Stores webhook IDs to prevent replay attacks.';


-- ===============================================================================================
-- Section 2: Helper Functions & Triggers
-- Functions are defined here, after the tables they may depend on have been created.
-- ===============================================================================================

CREATE OR REPLACE FUNCTION public.get_current_company_id()
RETURNS uuid
LANGUAGE sql STABLE
AS $$
  select company_id from public.profiles where user_id = auth.uid();
$$;
COMMENT ON FUNCTION public.get_current_company_id() IS 'A helper function to get the company ID for the currently authenticated user.';

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  new_company_id uuid;
  user_company_name TEXT;
BEGIN
  -- Create a new company for the user
  user_company_name := COALESCE(new.raw_user_meta_data->>'company_name', 'My Company');
  INSERT INTO public.companies (name) VALUES (user_company_name) RETURNING id INTO new_company_id;

  -- Create a profile for the new user, linking them to the new company as 'Owner'
  INSERT INTO public.profiles (user_id, company_id, role)
  VALUES (new.id, new_company_id, 'Owner');
  
  RETURN new;
END;
$$;
COMMENT ON FUNCTION public.handle_new_user() IS 'Trigger function to create a company and profile for a new user upon signup.';

-- Drop the trigger if it exists, then create it.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = (now() at time zone 'utc');
  RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.set_updated_at() IS 'Automatically sets the updated_at timestamp on a row before an update.';

CREATE OR REPLACE FUNCTION public.apply_updated_at_trigger(table_name TEXT)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    EXECUTE format('
        DROP TRIGGER IF EXISTS handle_updated_at ON public.%I;
        CREATE TRIGGER handle_updated_at
        BEFORE UPDATE ON public.%I
        FOR EACH ROW
        EXECUTE FUNCTION public.set_updated_at();
    ', table_name, table_name);
END;
$$;
COMMENT ON FUNCTION public.apply_updated_at_trigger(TEXT) IS 'A helper function to apply the set_updated_at trigger to a given table.';

-- Apply the updated_at trigger to all tables that have an updated_at column
SELECT public.apply_updated_at_trigger(table_name)
FROM information_schema.columns
WHERE table_schema = 'public'
  AND column_name = 'updated_at'
  AND table_name NOT IN ('product_variants_with_details'); -- Exclude views


-- ===============================================================================================
-- Section 3: Row-Level Security (RLS)
-- Enable RLS and create policies for all tables.
-- ===============================================================================================

-- Enable RLS for all tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.locations ENABLE ROW LEVEL SECURITY;

-- Drop existing policies before creating new ones
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.companies;
DROP POLICY IF EXISTS "Allow users to read their own profile" ON public.profiles;
DROP POLICY IF EXISTS "Allow users to read profiles in their own company" ON public.profiles;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.company_settings;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.suppliers;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.products;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.product_variants;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.customers;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.orders;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.order_line_items;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.conversations;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.messages;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.integrations;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.inventory_ledger;
DROP POLICY IF EXISTS "Allow read access to company audit log" ON public.audit_log;
DROP POLICY IF EXISTS "Allow read access to webhook_events" ON public.webhook_events;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.locations;

-- Create Policies
CREATE POLICY "Allow full access based on company_id" ON public.companies FOR ALL USING (id = get_current_company_id()) WITH CHECK (id = get_current_company_id());
CREATE POLICY "Allow users to read their own profile" ON public.profiles FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "Allow users to read profiles in their own company" ON public.profiles FOR SELECT USING (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.company_settings FOR ALL USING (company_id = get_current_company_id()) WITH CHECK (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.suppliers FOR ALL USING (company_id = get_current_company_id()) WITH CHECK (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.products FOR ALL USING (company_id = get_current_company_id()) WITH CHECK (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.product_variants FOR ALL USING (company_id = get_current_company_id()) WITH CHECK (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.customers FOR ALL USING (company_id = get_current_company_id()) WITH CHECK (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.orders FOR ALL USING (company_id = get_current_company_id()) WITH CHECK (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.order_line_items FOR ALL USING (company_id = get_current_company_id()) WITH CHECK (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.conversations FOR ALL USING (company_id = get_current_company_id()) WITH CHECK (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.messages FOR ALL USING (company_id = get_current_company_id()) WITH CHECK (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.integrations FOR ALL USING (company_id = get_current_company_id()) WITH CHECK (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.inventory_ledger FOR ALL USING (company_id = get_current_company_id()) WITH CHECK (company_id = get_current_company_id());
CREATE POLICY "Allow read access to company audit log" ON public.audit_log FOR SELECT USING (company_id = get_current_company_id());
CREATE POLICY "Allow read access to webhook_events" ON public.webhook_events FOR SELECT USING (EXISTS (SELECT 1 FROM integrations WHERE id = webhook_events.integration_id AND company_id = get_current_company_id()));
CREATE POLICY "Allow full access based on company_id" ON public.locations FOR ALL USING (company_id = get_current_company_id()) WITH CHECK (company_id = get_current_company_id());


-- ===============================================================================================
-- Section 4: Views
-- Create views to simplify data querying.
-- ===============================================================================================

CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.*,
    p.title AS product_title,
    p.status AS product_status,
    p.image_url,
    l.name AS location_name
FROM
    public.product_variants pv
JOIN
    public.products p ON pv.product_id = p.id
LEFT JOIN
    public.locations l ON pv.location_id = l.id;

COMMENT ON VIEW public.product_variants_with_details IS 'A flattened view combining product variants with key details from their parent product and location.';


-- ===============================================================================================
-- Section 5: Indexes
-- Create indexes to improve query performance on frequently queried columns.
-- ===============================================================================================

CREATE INDEX IF NOT EXISTS idx_profiles_company_id ON public.profiles(company_id);
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_company_id ON public.product_variants(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_sku ON public.product_variants(sku);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON public.orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON public.order_line_items(variant_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id ON public.inventory_ledger(variant_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_change_type ON public.inventory_ledger(change_type);

-- ===============================================================================================
-- Section 6: Stored Procedures / RPCs
-- These are the more complex business logic functions callable from the application.
-- ===============================================================================================

CREATE OR REPLACE FUNCTION public.record_order_from_platform(p_company_id UUID, p_order_payload JSONB, p_platform TEXT)
RETURNS VOID AS $$
DECLARE
    v_customer_id UUID;
    v_order_id UUID;
    v_variant_id UUID;
    v_line_item JSONB;
    v_customer_name TEXT;
BEGIN
    -- This function is now idempotent. It will not create duplicate orders.
    IF EXISTS (SELECT 1 FROM public.orders WHERE company_id = p_company_id AND external_order_id = p_order_payload->>'id') THEN
        RETURN;
    END IF;
    
    -- Determine customer name based on platform
    IF p_platform = 'shopify' THEN
        v_customer_name := (p_order_payload->'customer'->>'first_name') || ' ' || (p_order_payload->'customer'->>'last_name');
    ELSIF p_platform = 'woocommerce' THEN
        v_customer_name := (p_order_payload->'billing'->>'first_name') || ' ' || (p_order_payload->'billing'->>'last_name');
    END IF;

    -- Upsert customer
    INSERT INTO public.customers (company_id, email, customer_name)
    VALUES (
        p_company_id,
        p_order_payload->'customer'->>'email',
        v_customer_name
    )
    ON CONFLICT (company_id, email) DO UPDATE SET customer_name = EXCLUDED.customer_name
    RETURNING id INTO v_customer_id;

    -- Insert order
    INSERT INTO public.orders (company_id, customer_id, order_number, total_amount, source_platform, external_order_id, created_at)
    VALUES (
        p_company_id,
        v_customer_id,
        p_order_payload->>'number',
        (p_order_payload->>'total_price')::NUMERIC * 100,
        p_platform,
        p_order_payload->>'id',
        (p_order_payload->>'created_at')::timestamptz
    )
    RETURNING id INTO v_order_id;

    -- Loop through line items and update inventory
    FOR v_line_item IN SELECT * FROM jsonb_array_elements(p_order_payload->'line_items')
    LOOP
        -- Find the corresponding product variant
        SELECT id INTO v_variant_id FROM public.product_variants
        WHERE company_id = p_company_id AND sku = v_line_item->>'sku'
        LIMIT 1;

        -- If variant exists, process it. Otherwise, we skip (or you could add logic to create it)
        IF v_variant_id IS NOT NULL THEN
            -- Lock the variant row to prevent race conditions
            PERFORM * FROM public.product_variants WHERE id = v_variant_id FOR UPDATE;

            -- Insert line item
            INSERT INTO public.order_line_items (order_id, variant_id, company_id, quantity, price)
            VALUES (v_order_id, v_variant_id, p_company_id, (v_line_item->>'quantity')::INT, (v_line_item->>'price')::NUMERIC * 100);

            -- Update inventory quantity and log the change
            UPDATE public.product_variants
            SET inventory_quantity = inventory_quantity - (v_line_item->>'quantity')::INT
            WHERE id = v_variant_id;
            
            INSERT INTO public.inventory_ledger (company_id, variant_id, location_id, change_type, quantity_change, new_quantity, related_id, notes)
            SELECT p_company_id, v_variant_id, pv.location_id, 'sale', -(v_line_item->>'quantity')::INT, pv.inventory_quantity, v_order_id, 'Order #' || p_order_payload->>'number'
            FROM public.product_variants pv WHERE pv.id = v_variant_id;
        END IF;
    END LOOP;

    -- Update customer stats
    UPDATE public.customers
    SET
        total_orders = total_orders + 1,
        total_spent = total_spent + ((p_order_payload->>'total_price')::NUMERIC * 100),
        first_order_date = LEAST(first_order_date, (p_order_payload->>'created_at')::DATE)
    WHERE id = v_customer_id;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION public.record_order_from_platform(UUID, JSONB, TEXT) IS 'A transactional function to safely record an order from a synced platform, updating customers and inventory.';

CREATE OR REPLACE FUNCTION public.cleanup_old_data(retention_period_days INT)
RETURNS VOID AS $$
BEGIN
    -- Delete audit logs older than the retention period
    DELETE FROM public.audit_log
    WHERE created_at < (now() at time zone 'utc') - (retention_period_days || ' days')::INTERVAL;

    -- Delete chat messages older than the retention period
    DELETE FROM public.messages
    WHERE created_at < (now() at time zone 'utc') - (retention_period_days || ' days')::INTERVAL;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION public.cleanup_old_data(INT) IS 'A maintenance function to delete old audit logs and messages to manage database size.';


-- ===============================================================================================
-- Final Script
-- ===============================================================================================
-- Grant usage on the public schema to the anon and authenticated roles.
-- This allows them to access the tables and functions we've defined.
GRANT USAGE ON SCHEMA public TO anon, authenticated;

-- Grant select permission on all tables in the public schema to the authenticated role.
-- RLS policies will handle the actual data visibility.
GRANT SELECT ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- Let authenticated users use the tables. RLS policies will protect the data.
GRANT all privileges on all tables in schema public to authenticated;
-- ===============================================================================================

