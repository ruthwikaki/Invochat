
-- ### Extensions ###
-- Enable the "pgcrypto" extension for generating UUIDs
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- ### Helper Functions ###

-- Function to get the current user's company ID from their JWT claims
CREATE OR REPLACE FUNCTION get_current_company_id()
RETURNS uuid AS $$
DECLARE
  company_id uuid;
BEGIN
  -- We can't use current_setting because it's not available in all contexts (e.g., RLS).
  -- auth.jwt()->>'app_metadata' is the reliable way to get this info.
  SELECT (auth.jwt() -> 'app_metadata' ->> 'company_id')::uuid INTO company_id;
  RETURN company_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ### Table Definitions ###

-- Companies Table: Stores basic information about each company.
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
    name text NOT NULL,
    created_at timestamptz DEFAULT (now() at time zone 'utc') NOT NULL
);
COMMENT ON TABLE public.companies IS 'Stores basic information about each company.';

-- Company Settings Table: Stores business logic parameters for each company.
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer DEFAULT 90 NOT NULL,
    fast_moving_days integer DEFAULT 30 NOT NULL,
    overstock_multiplier numeric DEFAULT 3.0 NOT NULL,
    high_value_threshold integer DEFAULT 100000 NOT NULL, -- in cents
    predictive_stock_days integer DEFAULT 7 NOT NULL,
    created_at timestamptz DEFAULT (now() at time zone 'utc') NOT NULL,
    updated_at timestamptz
);
COMMENT ON TABLE public.company_settings IS 'Stores business logic parameters for each company.';

-- Products Table: Core product catalog information.
CREATE TABLE IF NOT EXISTS public.products (
    id uuid DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    description text,
    handle text,
    product_type text,
    tags text[],
    status text,
    image_url text,
    external_product_id text,
    created_at timestamptz DEFAULT (now() at time zone 'utc') NOT NULL,
    updated_at timestamptz,
    UNIQUE(company_id, external_product_id)
);
COMMENT ON TABLE public.products IS 'Core product catalog information.';

-- Product Variants Table: Specific variations of a product (e.g., size, color).
CREATE TABLE IF NOT EXISTS public.product_variants (
    id uuid DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku text,
    title text,
    option1_name text,
    option1_value text,
    option2_name text,
    option2_value text,
    option3_name text,
    option3_value text,
    barcode text,
    price integer, -- in cents
    compare_at_price integer, -- in cents
    cost integer, -- in cents
    inventory_quantity integer DEFAULT 0 NOT NULL,
    external_variant_id text,
    created_at timestamptz DEFAULT (now() at time zone 'utc') NOT NULL,
    updated_at timestamptz,
    UNIQUE(company_id, external_variant_id),
    UNIQUE(company_id, sku)
);
COMMENT ON TABLE public.product_variants IS 'Specific variations of a product.';

-- Customers Table: Stores information about customers.
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name text,
    email text,
    total_orders integer DEFAULT 0,
    total_spent integer DEFAULT 0,
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT (now() at time zone 'utc') NOT NULL,
    updated_at timestamptz,
    UNIQUE(company_id, email)
);
COMMENT ON TABLE public.customers IS 'Stores information about customers.';

-- Orders Table: Records sales orders.
CREATE TABLE IF NOT EXISTS public.orders (
    id uuid DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number text NOT NULL,
    external_order_id text,
    customer_id uuid REFERENCES public.customers(id),
    financial_status text,
    fulfillment_status text,
    currency text,
    subtotal integer NOT NULL,
    total_tax integer,
    total_shipping integer,
    total_discounts integer,
    total_amount integer NOT NULL,
    source_platform text,
    created_at timestamptz DEFAULT (now() at time zone 'utc') NOT NULL,
    updated_at timestamptz,
    UNIQUE(company_id, external_order_id)
);
COMMENT ON TABLE public.orders IS 'Records sales orders.';

-- Order Line Items Table: Individual items within an order.
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id uuid REFERENCES public.product_variants(id),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_name text,
    variant_title text,
    sku text,
    quantity integer NOT NULL CHECK (quantity > 0),
    price integer NOT NULL CHECK (price >= 0),
    total_discount integer NOT NULL DEFAULT 0 CHECK (total_discount >= 0),
    tax_amount integer,
    cost_at_time integer CHECK (cost_at_time >= 0),
    external_line_item_id text
);
COMMENT ON TABLE public.order_line_items IS 'Individual items within an order.';

-- Suppliers Table: Information about vendors.
CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz DEFAULT (now() at time zone 'utc') NOT NULL,
    updated_at timestamptz
);
COMMENT ON TABLE public.suppliers IS 'Information about vendors.';

-- Conversations Table: Stores chat conversations.
CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    created_at timestamptz DEFAULT (now() at time zone 'utc') NOT NULL,
    last_accessed_at timestamptz DEFAULT (now() at time zone 'utc') NOT NULL,
    is_starred boolean DEFAULT false NOT NULL
);
COMMENT ON TABLE public.conversations IS 'Stores chat conversations.';

-- Messages Table: Individual messages within a conversation.
CREATE TABLE IF NOT EXISTS public.messages (
    id uuid DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role text NOT NULL,
    content text NOT NULL,
    visualization jsonb,
    component text,
    component_props jsonb,
    confidence real,
    assumptions text[],
    is_error boolean DEFAULT false,
    created_at timestamptz DEFAULT (now() at time zone 'utc') NOT NULL
);
COMMENT ON TABLE public.messages IS 'Individual messages within a conversation.';

-- Integrations Table: Manages connections to external platforms.
CREATE TABLE IF NOT EXISTS public.integrations (
    id uuid DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform text NOT NULL,
    shop_domain text,
    shop_name text,
    is_active boolean DEFAULT true NOT NULL,
    last_sync_at timestamptz,
    sync_status text,
    created_at timestamptz DEFAULT (now() at time zone 'utc') NOT NULL,
    updated_at timestamptz,
    UNIQUE(company_id, platform)
);
COMMENT ON TABLE public.integrations IS 'Manages connections to external platforms.';

-- Inventory Ledger Table: Tracks all stock movements.
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid,
    notes text,
    created_at timestamptz DEFAULT (now() at time zone 'utc') NOT NULL
);
COMMENT ON TABLE public.inventory_ledger IS 'Tracks all stock movements.';

-- Audit Log Table: General audit trail for important actions.
CREATE TABLE IF NOT EXISTS public.audit_log (
    id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id uuid REFERENCES auth.users(id),
    action text NOT NULL,
    details jsonb,
    created_at timestamptz DEFAULT (now() at time zone 'utc') NOT NULL
);
COMMENT ON TABLE public.audit_log IS 'General audit trail for important actions.';

-- Webhook Events Table: Prevents replay attacks for webhooks.
CREATE TABLE IF NOT EXISTS public.webhook_events (
    id uuid DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id text NOT NULL,
    processed_at timestamptz DEFAULT (now() at time zone 'utc') NOT NULL,
    UNIQUE(integration_id, webhook_id)
);
COMMENT ON TABLE public.webhook_events IS 'Prevents replay attacks for webhooks.';

-- ### Views for Simplified Data Access ###

CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT 
    pv.*,
    p.title as product_title,
    p.status as product_status,
    p.image_url as image_url,
    NULL::uuid as location_id, -- Placeholder for future multi-location support
    'Default Location' as location_name
FROM 
    public.product_variants pv
JOIN 
    public.products p ON pv.product_id = p.id;

-- ### Indexes for Performance ###

CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_company_id_sku ON public.product_variants(company_id, sku);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON public.order_line_items(variant_id);
CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON public.suppliers(company_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id ON public.inventory_ledger(variant_id);
CREATE INDEX IF NOT EXISTS idx_products_tags ON public.products USING GIN (tags);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON public.orders(customer_id);

-- ### Triggers and Functions ###

-- Function to create a company and link it to the new user
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
  new_company_id uuid;
  user_company_name text;
BEGIN
  -- Get company name from user metadata, default if not present
  user_company_name := new.raw_user_meta_data ->> 'company_name';
  if user_company_name IS NULL OR user_company_name = '' THEN
    user_company_name := new.email || '''s Company';
  END IF;
  
  -- Create a new company for the user
  INSERT INTO public.companies (name)
  VALUES (user_company_name)
  RETURNING id INTO new_company_id;

  -- Update the user's app_metadata with the new company_id
  UPDATE auth.users
  SET app_metadata = app_metadata || jsonb_build_object('company_id', new_company_id)
  WHERE id = new.id;
  
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop the trigger if it exists, then create it
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- Trigger to automatically update 'updated_at' columns
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger AS $$
BEGIN
    new.updated_at = (now() at time zone 'utc');
    RETURN new;
END;
$$ LANGUAGE plpgsql;

-- Function to apply the 'set_updated_at' trigger to a table
CREATE OR REPLACE FUNCTION public.apply_updated_at_trigger(table_name text)
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

-- Apply the trigger to all tables with an 'updated_at' column
SELECT public.apply_updated_at_trigger(table_name::text)
FROM information_schema.columns
WHERE table_schema = 'public' AND column_name = 'updated_at';


-- Function to record a sale and automatically update inventory
CREATE OR REPLACE FUNCTION public.record_order_from_platform(p_company_id uuid, p_order_payload jsonb, p_platform text)
RETURNS void AS $$
DECLARE
    v_customer_id uuid;
    v_order_id uuid;
    line_item jsonb;
    v_variant_id uuid;
    v_quantity integer;
BEGIN
    -- Upsert customer
    INSERT INTO public.customers (company_id, email, customer_name, total_orders, total_spent)
    VALUES (
        p_company_id,
        p_order_payload -> 'customer' ->> 'email',
        COALESCE(p_order_payload -> 'customer' ->> 'first_name' || ' ' || p_order_payload -> 'customer' ->> 'last_name', p_order_payload -> 'customer' ->> 'email'),
        1,
        (p_order_payload ->> 'total_price')::numeric * 100
    )
    ON CONFLICT (company_id, email)
    DO UPDATE SET
        total_orders = customers.total_orders + 1,
        total_spent = customers.total_spent + (p_order_payload ->> 'total_price')::numeric * 100
    RETURNING id INTO v_customer_id;

    -- Insert order
    INSERT INTO public.orders (company_id, external_order_id, customer_id, order_number, total_amount, source_platform, financial_status, fulfillment_status, currency, subtotal, total_tax, total_shipping, total_discounts)
    VALUES (
        p_company_id,
        p_order_payload ->> 'id',
        v_customer_id,
        p_order_payload ->> 'name',
        (p_order_payload ->> 'total_price')::numeric * 100,
        p_platform,
        p_order_payload ->> 'financial_status',
        p_order_payload ->> 'fulfillment_status',
        p_order_payload ->> 'currency',
        (p_order_payload ->> 'subtotal_price')::numeric * 100,
        (p_order_payload ->> 'total_tax')::numeric * 100,
        (p_order_payload ->> 'total_shipping_price')::numeric * 100,
        (p_order_payload ->> 'total_discounts')::numeric * 100
    )
    RETURNING id INTO v_order_id;
    
    -- Loop through line items
    FOR line_item IN SELECT * FROM jsonb_array_elements(p_order_payload -> 'line_items')
    LOOP
        -- Find variant_id
        SELECT id INTO v_variant_id FROM public.product_variants WHERE company_id = p_company_id AND sku = (line_item ->> 'sku');
        v_quantity := (line_item ->> 'quantity')::integer;

        -- Insert line item
        INSERT INTO public.order_line_items (order_id, variant_id, company_id, sku, quantity, price)
        VALUES (
            v_order_id,
            v_variant_id,
            p_company_id,
            line_item ->> 'sku',
            v_quantity,
            (line_item ->> 'price')::numeric * 100
        );

        -- Update inventory using row-level locking for safety
        IF v_variant_id IS NOT NULL THEN
            UPDATE public.product_variants
            SET inventory_quantity = inventory_quantity - v_quantity
            WHERE id = v_variant_id AND company_id = p_company_id;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.cleanup_old_data()
RETURNS void AS $$
DECLARE
  retention_period_audit interval := '90 days';
  retention_period_messages interval := '180 days';
BEGIN
  -- Delete old audit logs
  DELETE FROM public.audit_log WHERE created_at < (now() - retention_period_audit);
  -- Delete old messages
  DELETE FROM public.messages WHERE created_at < (now() - retention_period_messages);
END;
$$ LANGUAGE plpgsql;


-- ### Row-Level Security (RLS) Policies ###
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;

-- Function to dynamically create RLS policies for a table
CREATE OR REPLACE FUNCTION public.create_company_rls_policy(table_name text)
RETURNS void AS $$
BEGIN
    EXECUTE format('
        CREATE POLICY "Allow full access based on company_id"
        ON public.%I
        FOR ALL
        USING (company_id = get_current_company_id())
        WITH CHECK (company_id = get_current_company_id());
    ', table_name);
END;
$$ LANGUAGE plpgsql;

-- Apply the generic RLS policy to all tables with a 'company_id' column
DO $$
DECLARE
    t_name text;
BEGIN
    FOR t_name IN 
        SELECT table_name 
        FROM information_schema.columns 
        WHERE table_schema = 'public' AND column_name = 'company_id' AND table_name != 'companies'
    LOOP
        -- Drop existing policy if it exists, to make this script re-runnable
        EXECUTE format('DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.%I;', t_name);
        -- Create the new policy
        PERFORM public.create_company_rls_policy(t_name);
    END LOOP;
END;
$$;

-- Custom RLS policy for the 'companies' table itself
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.companies;
CREATE POLICY "Allow full access based on company_id"
ON public.companies
FOR ALL
USING (id = get_current_company_id())
WITH CHECK (id = get_current_company_id());

-- Grant usage on the schema to the authenticated role
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public to authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
