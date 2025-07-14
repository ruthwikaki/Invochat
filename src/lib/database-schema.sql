
-- Enable the UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
-- Enable the pgcrypto extension for encryption functions
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Grant usage on the public schema to the postgres user
GRANT USAGE ON SCHEMA public TO postgres;

-- Set up PostGIS for spatial data (if needed in the future)
-- create extension if not exists postgis with schema public;

-- =================================================================
--  Initial Schema Creation
-- =================================================================

-- Create companies table to hold basic company information
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    name text NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL
);
COMMENT ON TABLE public.companies IS 'Stores basic information about each company tenant.';

-- Create company_settings table for tenant-specific business logic
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer DEFAULT 90 NOT NULL,
    fast_moving_days integer DEFAULT 30 NOT NULL,
    overstock_multiplier real DEFAULT 3 NOT NULL,
    high_value_threshold integer DEFAULT 100000 NOT NULL,
    predictive_stock_days integer DEFAULT 7 NOT NULL,
    currency text DEFAULT 'USD' NOT NULL,
    timezone text DEFAULT 'UTC' NOT NULL,
    tax_rate numeric(5,4) DEFAULT 0.0000 NOT NULL,
    custom_rules jsonb,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz,
    subscription_plan text,
    subscription_status text,
    subscription_expires_at timestamptz,
    stripe_customer_id text,
    stripe_subscription_id text,
    promo_sales_lift_multiplier real DEFAULT 2.5 NOT NULL
);
COMMENT ON TABLE public.company_settings IS 'Stores business logic settings for each company.';

-- Create suppliers table for vendor information
CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz DEFAULT now() NOT NULL
);
COMMENT ON TABLE public.suppliers IS 'Stores information about vendors and suppliers.';

-- Create products table
CREATE TABLE IF NOT EXISTS public.products (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    description text,
    handle text,
    product_type text,
    tags text[],
    status text,
    image_url text,
    external_product_id text,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz,
    UNIQUE (company_id, external_product_id)
);
COMMENT ON TABLE public.products IS 'Stores core product information.';

-- Create product_variants table
CREATE TABLE IF NOT EXISTS public.product_variants (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
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
    price integer,
    compare_at_price integer,
    cost integer,
    inventory_quantity integer NOT NULL DEFAULT 0,
    external_variant_id text,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz,
    UNIQUE (company_id, external_variant_id)
);
COMMENT ON TABLE public.product_variants IS 'Stores product variants, including SKU and pricing.';

-- Create orders table
CREATE TABLE IF NOT EXISTS public.orders (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
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
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz
);
COMMENT ON TABLE public.orders IS 'Stores sales order information.';

-- Create order_line_items table
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
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
    external_line_item_id text,
    CONSTRAINT positive_price CHECK (price >= 0),
    CONSTRAINT positive_cost CHECK (cost_at_time IS NULL OR cost_at_time >= 0)
);
COMMENT ON TABLE public.order_line_items IS 'Stores individual line items for each order.';

-- Create customers table
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name text,
    email text,
    total_orders integer DEFAULT 0,
    total_spent integer DEFAULT 0,
    first_order_date date,
    created_at timestamptz DEFAULT now() NOT NULL,
    deleted_at timestamptz,
    UNIQUE(company_id, email)
);
COMMENT ON TABLE public.customers IS 'Stores customer information.';

-- Create purchase_orders table
CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL,
    status text NOT NULL,
    po_number text NOT NULL,
    total_cost integer NOT NULL,
    expected_arrival_date date,
    created_at timestamptz DEFAULT now() NOT NULL,
    created_by uuid REFERENCES auth.users(id),
    updated_at timestamptz,
    UNIQUE(company_id, po_number)
);
COMMENT ON TABLE public.purchase_orders IS 'Stores purchase order information.';

-- Create purchase_order_line_items table
CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    purchase_order_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    quantity integer NOT NULL,
    cost integer NOT NULL
);
COMMENT ON TABLE public.purchase_order_line_items IS 'Stores line items for each purchase order.';

-- Create inventory_ledger table for tracking stock movements
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid,
    notes text,
    created_at timestamptz DEFAULT now() NOT NULL
);
COMMENT ON TABLE public.inventory_ledger IS 'Records every change in inventory for auditing.';

-- Create integrations table for connecting external platforms
CREATE TABLE IF NOT EXISTS public.integrations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform text NOT NULL,
    shop_domain text,
    shop_name text,
    is_active boolean DEFAULT true,
    last_sync_at timestamptz,
    sync_status text,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz,
    UNIQUE (company_id, platform)
);
COMMENT ON TABLE public.integrations IS 'Stores connection details for external platforms.';

-- Create webhook_events table for replay protection
CREATE TABLE IF NOT EXISTS public.webhook_events (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id text NOT NULL,
    received_at timestamptz DEFAULT now() NOT NULL,
    UNIQUE(integration_id, webhook_id)
);
COMMENT ON TABLE public.webhook_events IS 'Prevents webhook replay attacks by logging processed IDs.';

-- Create user_feedback table
CREATE TABLE IF NOT EXISTS public.user_feedback (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL REFERENCES auth.users(id),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    subject_id text NOT NULL,
    subject_type text NOT NULL,
    feedback text NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL
);
COMMENT ON TABLE public.user_feedback IS 'Stores user feedback on AI suggestions and features.';

-- =================================================================
--  Functions and Triggers
-- =================================================================

-- Function to get the company_id from a user's JWT claims
CREATE OR REPLACE FUNCTION get_current_company_id()
RETURNS uuid AS $$
BEGIN
    RETURN (current_setting('request.jwt.claims', true)::jsonb ->> 'company_id')::uuid;
EXCEPTION
    WHEN others THEN
        RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to handle new user sign-ups
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    new_company_id uuid;
    company_name text := new.raw_user_meta_data->>'company_name';
BEGIN
    -- Create a new company for the user
    INSERT INTO public.companies (name)
    VALUES (COALESCE(company_name, 'My Company'))
    RETURNING id INTO new_company_id;
    
    -- Insert default settings for the new company
    INSERT INTO public.company_settings (company_id)
    VALUES (new_company_id);

    -- Update the user's metadata with the new company_id and role
    UPDATE auth.users
    SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'role', 'Owner')
    WHERE id = NEW.id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to execute the handle_new_user function on new user creation
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION handle_new_user();

-- =================================================================
--  Row Level Security (RLS) Policies
-- =================================================================

-- Enable RLS on all tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_feedback ENABLE ROW LEVEL SECURITY;

-- Create policies for each table
CREATE POLICY "Allow full access based on company_id" ON public.companies FOR ALL USING (id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.company_settings FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.suppliers FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.products FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.product_variants FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.orders FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.order_line_items FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.customers FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.purchase_orders FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.purchase_order_line_items FOR ALL USING (purchase_order_id IN (SELECT id FROM public.purchase_orders WHERE company_id = get_current_company_id()));
CREATE POLICY "Allow full access based on company_id" ON public.inventory_ledger FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.integrations FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Allow access to own feedback" ON public.user_feedback FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Allow access based on integration" ON public.webhook_events FOR ALL USING (integration_id IN (SELECT id FROM public.integrations WHERE company_id = get_current_company_id()));


-- Grant all privileges to the service_role
GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO service_role;
