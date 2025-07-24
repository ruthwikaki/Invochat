
-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Define custom types for roles and platforms
DO $$ BEGIN
    CREATE TYPE public.company_role AS ENUM ('Owner', 'Admin', 'Member');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE public.integration_platform AS ENUM ('shopify', 'woocommerce', 'amazon_fba');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE public.message_role AS ENUM ('user', 'assistant', 'tool');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
     CREATE TYPE public.feedback_type AS ENUM ('helpful', 'unhelpful');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;


-- Create companies table to hold company information
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.companies IS 'Stores company-level information.';

-- Create users table to link auth.users to companies
CREATE TABLE IF NOT EXISTS public.users (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role text NOT NULL DEFAULT 'Member',
    email text,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now()
);
COMMENT ON TABLE public.users IS 'Maps auth.users to companies and defines their roles.';


-- Create company_settings table
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    fast_moving_days integer NOT NULL DEFAULT 30,
    overstock_multiplier integer NOT NULL DEFAULT 3,
    high_value_threshold integer NOT NULL DEFAULT 1000, -- In cents
    predictive_stock_days integer NOT NULL DEFAULT 7,
    currency text DEFAULT 'USD',
    timezone text DEFAULT 'UTC',
    tax_rate numeric DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);
COMMENT ON TABLE public.company_settings IS 'Stores business logic settings for each company.';

-- Create integrations table
CREATE TABLE IF NOT EXISTS public.integrations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform integration_platform NOT NULL,
    shop_domain text,
    shop_name text,
    is_active boolean DEFAULT false,
    last_sync_at timestamptz,
    sync_status text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    UNIQUE (company_id, platform)
);
COMMENT ON TABLE public.integrations IS 'Stores integration settings for e-commerce platforms.';

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
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    deleted_at timestamptz
);
COMMENT ON TABLE public.products IS 'Stores product-level information.';

-- Create suppliers table
CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);
COMMENT ON TABLE public.suppliers IS 'Stores supplier and vendor information.';

-- Create product_variants table
CREATE TABLE IF NOT EXISTS public.product_variants (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
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
    price integer, -- In cents
    compare_at_price integer, -- In cents
    cost integer, -- In cents
    inventory_quantity integer NOT NULL DEFAULT 0,
    location text,
    supplier_id uuid null REFERENCES public.suppliers(id) ON DELETE SET NULL,
    reorder_point integer,
    reorder_quantity integer,
    external_variant_id text,
    version integer not null default 1,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    deleted_at timestamptz,
    UNIQUE (company_id, sku)
);
COMMENT ON TABLE public.product_variants IS 'Stores detailed information for each product variant.';


-- Create customers table
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text,
    email text,
    phone text,
    external_customer_id text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    deleted_at timestamptz,
    UNIQUE(company_id, external_customer_id)
);
COMMENT ON TABLE public.customers IS 'Stores customer information.';


-- Create orders table
CREATE TABLE IF NOT EXISTS public.orders (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
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
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, external_order_id)
);
COMMENT ON TABLE public.orders IS 'Stores order header information.';


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
    external_line_item_id text
);
COMMENT ON TABLE public.order_line_items IS 'Stores line item details for each order.';

-- Create purchase_orders table
CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.suppliers(id),
    status text NOT NULL DEFAULT 'Draft',
    po_number text NOT NULL,
    total_cost integer NOT NULL,
    expected_arrival_date date,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    idempotency_key uuid,
    UNIQUE(company_id, po_number)
);
COMMENT ON TABLE public.purchase_orders IS 'Stores purchase order information.';

-- Create purchase_order_line_items table
CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    purchase_order_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    quantity integer NOT NULL,
    cost integer NOT NULL
);
COMMENT ON TABLE public.purchase_order_line_items IS 'Stores line item details for each purchase order.';

-- Create inventory_ledger table
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.inventory_ledger IS 'Records all changes to inventory for auditing purposes.';

-- Create conversations table
CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    created_at timestamptz DEFAULT now(),
    last_accessed_at timestamptz DEFAULT now(),
    is_starred boolean DEFAULT false
);

-- Create messages table
CREATE TABLE IF NOT EXISTS public.messages (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role message_role NOT NULL,
    content text NOT NULL,
    visualization jsonb,
    component text,
    componentProps jsonb,
    confidence real,
    assumptions text[],
    isError boolean default false,
    created_at timestamptz DEFAULT now()
);

-- Create audit_log table
CREATE TABLE IF NOT EXISTS public.audit_log (
    id bigserial PRIMARY KEY,
    company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    action text NOT NULL,
    details jsonb,
    created_at timestamptz DEFAULT now()
);

-- Create channel_fees table
CREATE TABLE IF NOT EXISTS public.channel_fees (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    channel_name text NOT NULL,
    fixed_fee integer, -- In cents
    percentage_fee numeric,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    UNIQUE (company_id, channel_name)
);

-- Create export_jobs table
CREATE TABLE IF NOT EXISTS public.export_jobs (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    requested_by_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    status text NOT NULL DEFAULT 'pending',
    download_url text,
    expires_at timestamptz,
    error_message text,
    created_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz
);

-- Create webhook_events table
CREATE TABLE IF NOT EXISTS public.webhook_events (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id text NOT NULL,
    created_at timestamptz DEFAULT now(),
    UNIQUE(integration_id, webhook_id)
);
COMMENT ON TABLE public.webhook_events IS 'Stores processed webhook IDs to prevent replays.';

-- Create imports table
CREATE TABLE IF NOT EXISTS public.imports (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    created_by uuid NOT NULL REFERENCES auth.users(id),
    import_type text NOT NULL,
    file_name text NOT NULL,
    total_rows integer,
    processed_rows integer,
    failed_rows integer,
    status text NOT NULL DEFAULT 'processing',
    errors jsonb,
    summary jsonb,
    created_at timestamptz DEFAULT now(),
    completed_at timestamptz
);
COMMENT ON TABLE public.imports IS 'Tracks the status and results of CSV imports.';


--- FUNCTIONS and TRIGGERS ---

-- Function to create a company and assign the owner role
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  new_company_id uuid;
  user_company_name text;
BEGIN
  -- Create a new company for the user
  user_company_name := NEW.raw_app_meta_data->>'company_name';
  INSERT INTO public.companies (name)
  VALUES (user_company_name)
  RETURNING id INTO new_company_id;

  -- Link the user to the new company with the 'Owner' role
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (NEW.id, new_company_id, NEW.email, 'Owner');
  
  -- Update the user's app_metadata with the new company_id
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id)
  WHERE id = NEW.id;

  -- Create default settings for the new company
  INSERT INTO public.company_settings(company_id) VALUES (new_company_id);

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
COMMENT ON FUNCTION public.handle_new_user() IS 'Trigger function to create a company and link a new user as its owner.';

-- Trigger to call the function when a new user is created in auth.users
CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- Function to decrement inventory on sale
CREATE OR REPLACE FUNCTION public.handle_inventory_change_on_sale()
RETURNS TRIGGER AS $$
DECLARE
    variant_record public.product_variants;
BEGIN
    -- Get the current inventory quantity for the variant
    SELECT * INTO variant_record
    FROM public.product_variants
    WHERE id = NEW.variant_id;

    -- Check for sufficient inventory
    IF variant_record.inventory_quantity < NEW.quantity THEN
        RAISE EXCEPTION 'Insufficient inventory for SKU %: Available: %, Requested: %', 
            variant_record.sku, variant_record.inventory_quantity, NEW.quantity;
    END IF;

    -- Update the inventory quantity
    UPDATE public.product_variants
    SET inventory_quantity = inventory_quantity - NEW.quantity
    WHERE id = NEW.variant_id;

    -- Log the change in the inventory ledger
    INSERT INTO public.inventory_ledger (variant_id, company_id, change_type, quantity_change, new_quantity, related_id, notes)
    VALUES (NEW.variant_id, NEW.company_id, 'sale', -NEW.quantity, variant_record.inventory_quantity - NEW.quantity, NEW.order_id, 'Order #' || (SELECT order_number FROM public.orders WHERE id = NEW.order_id));
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger for inventory change on new order line item
CREATE OR REPLACE TRIGGER on_order_line_item_insert
  AFTER INSERT ON public.order_line_items
  FOR EACH ROW EXECUTE FUNCTION public.handle_inventory_change_on_sale();


-- Function to lock a user account
CREATE OR REPLACE FUNCTION public.lock_user_account(p_user_id uuid, p_lockout_duration text)
RETURNS void AS $$
BEGIN
    UPDATE auth.users
    SET banned_until = now() + p_lockout_duration::interval
    WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


--- ROW-LEVEL SECURITY (RLS) POLICIES ---

-- Enable RLS for all relevant tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.imports ENABLE ROW LEVEL SECURITY;

-- Helper function to get the company_id for the current user
CREATE OR REPLACE FUNCTION public.get_current_company_id()
RETURNS uuid AS $$
DECLARE
    company_id uuid;
BEGIN
    SELECT u.company_id INTO company_id
    FROM public.users u
    WHERE u.id = auth.uid();
    RETURN company_id;
END;
$$ LANGUAGE plpgsql STABLE;

-- Generic policy for tables with a direct company_id column
CREATE OR REPLACE POLICY "User can access their own company data"
ON public.companies
FOR SELECT
USING (id = public.get_current_company_id());

CREATE OR REPLACE POLICY "User can access their own company users"
ON public.users
FOR SELECT
USING (company_id = public.get_current_company_id());

CREATE OR REPLACE POLICY "User can access their own company settings"
ON public.company_settings
FOR ALL
USING (company_id = public.get_current_company_id());

CREATE OR REPLACE POLICY "User can access their own company integrations"
ON public.integrations
FOR ALL
USING (company_id = public.get_current_company_id());

CREATE OR REPLACE POLICY "User can access their own company products"
ON public.products
FOR ALL
USING (company_id = public.get_current_company_id());

CREATE OR REPLACE POLICY "User can access their own company suppliers"
ON public.suppliers
FOR ALL
USING (company_id = public.get_current_company_id());

CREATE OR REPLACE POLICY "User can access their own company variants"
ON public.product_variants
FOR ALL
USING (company_id = public.get_current_company_id());

CREATE OR REPLACE POLICY "User can access their own company customers"
ON public.customers
FOR ALL
USING (company_id = public.get_current_company_id());

CREATE OR REPLACE POLICY "User can access their own company orders"
ON public.orders
FOR ALL
USING (company_id = public.get_current_company_id());

CREATE OR REPLACE POLICY "User can access their own company order line items"
ON public.order_line_items
FOR ALL
USING (company_id = public.get_current_company_id());

CREATE OR REPLACE POLICY "User can access their own company purchase orders"
ON public.purchase_orders
FOR ALL
USING (company_id = public.get_current_company_id());

CREATE OR REPLACE POLICY "User can access their own company PO line items"
ON public.purchase_order_line_items
FOR ALL
USING (company_id = public.get_current_company_id());

CREATE OR REPLACE POLICY "User can access their own company inventory ledger"
ON public.inventory_ledger
FOR ALL
USING (company_id = public.get_current_company_id());

CREATE OR REPLACE POLICY "User can access their own conversations"
ON public.conversations
FOR ALL
USING (user_id = auth.uid());

CREATE OR REPLACE POLICY "User can access their own messages"
ON public.messages
FOR ALL
USING (company_id = public.get_current_company_id());

CREATE OR REPLACE POLICY "User can access their own audit log"
ON public.audit_log
FOR ALL
USING (company_id = public.get_current_company_id());

CREATE OR REPLACE POLICY "User can access their own channel fees"
ON public.channel_fees
FOR ALL
USING (company_id = public.get_current_company_id());

CREATE OR REPLACE POLICY "User can access their own export jobs"
ON public.export_jobs
FOR ALL
USING (company_id = public.get_current_company_id());

CREATE OR REPLACE POLICY "User can access their own webhook events"
ON public.webhook_events
FOR ALL
USING (
    integration_id IN (
        SELECT id FROM public.integrations WHERE company_id = public.get_current_company_id()
    )
);

CREATE OR REPLACE POLICY "User can access their own imports"
ON public.imports
FOR ALL
USING (company_id = public.get_current_company_id());

-- Grant usage on the public schema to the authenticated role
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public to authenticated;

-- Grant access to service_role for all tables
GRANT ALL ON ALL TABLES IN SCHEMA public to service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public to service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public to service_role;
