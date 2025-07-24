
-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Enable the pgcrypto extension for encryption functions
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Custom Types
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'company_role') THEN
        CREATE TYPE public.company_role AS ENUM ('Owner', 'Admin', 'Member');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'integration_platform') THEN
        CREATE TYPE public.integration_platform AS ENUM ('shopify', 'woocommerce', 'amazon_fba');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'message_role') THEN
        CREATE TYPE public.message_role AS ENUM ('user', 'assistant', 'tool');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'feedback_type') THEN
        CREATE TYPE public.feedback_type AS ENUM ('helpful', 'unhelpful');
    END IF;
END$$;


-- Companies Table
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid DEFAULT uuid_generate_v4() NOT NULL PRIMARY KEY,
    name text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);
COMMENT ON TABLE public.companies IS 'Stores company information.';

-- Users Table (replaces company_users)
CREATE TABLE IF NOT EXISTS public.users (
    id uuid NOT NULL PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email text,
    role text DEFAULT 'member'::text,
    created_at timestamp with time zone DEFAULT now(),
    deleted_at timestamp with time zone
);
COMMENT ON TABLE public.users IS 'Maps auth.users to companies and defines their role.';


-- Company Settings Table
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid NOT NULL PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer DEFAULT 90 NOT NULL,
    fast_moving_days integer DEFAULT 30 NOT NULL,
    overstock_multiplier integer DEFAULT 3 NOT NULL,
    high_value_threshold integer DEFAULT 1000 NOT NULL, -- Stored in cents
    predictive_stock_days integer DEFAULT 7 NOT NULL,
    currency text DEFAULT 'USD'::text,
    timezone text DEFAULT 'UTC'::text,
    tax_rate numeric DEFAULT 0,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);

-- Suppliers Table
CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid DEFAULT uuid_generate_v4() NOT NULL PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

-- Products Table
CREATE TABLE IF NOT EXISTS public.products (
    id uuid DEFAULT uuid_generate_v4() NOT NULL PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    description text,
    handle text,
    product_type text,
    tags text[],
    status text,
    image_url text,
    external_product_id text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    deleted_at timestamp with time zone
);
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);

-- Product Variants Table
CREATE TABLE IF NOT EXISTS public.product_variants (
    id uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid null REFERENCES public.suppliers(id) ON DELETE SET NULL,
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
    inventory_quantity integer DEFAULT 0 NOT NULL,
    location text,
    external_variant_id text,
    version integer default 1 not null,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone,
    deleted_at timestamp with time zone
);
CREATE UNIQUE INDEX IF NOT EXISTS product_variants_company_id_sku_key ON public.product_variants(company_id, sku);

-- Customers Table
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid DEFAULT uuid_generate_v4() NOT NULL PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name text,
    email text,
    total_orders integer DEFAULT 0,
    total_spent integer DEFAULT 0,
    first_order_date date,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now()
);

-- Orders Table
CREATE TABLE IF NOT EXISTS public.orders (
    id uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number text NOT NULL,
    external_order_id text,
    customer_id uuid REFERENCES public.customers(id),
    financial_status text DEFAULT 'pending'::text,
    fulfillment_status text DEFAULT 'unfulfilled'::text,
    currency text DEFAULT 'USD'::text,
    subtotal integer DEFAULT 0 NOT NULL,
    total_tax integer DEFAULT 0,
    total_shipping integer DEFAULT 0,
    total_discounts integer DEFAULT 0,
    total_amount integer NOT NULL,
    source_platform text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);

-- Order Line Items Table
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id uuid REFERENCES public.product_variants(id),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_name text,
    variant_title text,
    sku text,
    quantity integer NOT NULL,
    price integer NOT NULL,
    total_discount integer DEFAULT 0,
    tax_amount integer DEFAULT 0,
    cost_at_time integer,
    external_line_item_id text
);

-- Purchase Orders Table
CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid DEFAULT uuid_generate_v4() NOT NULL PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.suppliers(id),
    status text DEFAULT 'Draft'::text NOT NULL,
    po_number text NOT NULL,
    total_cost integer NOT NULL,
    expected_arrival_date date,
    idempotency_key uuid,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);

-- Purchase Order Line Items Table
CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id uuid DEFAULT uuid_generate_v4() NOT NULL PRIMARY KEY,
    purchase_order_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    quantity integer NOT NULL,
    cost integer NOT NULL
);

-- Integrations Table
CREATE TABLE IF NOT EXISTS public.integrations (
    id uuid DEFAULT uuid_generate_v4() NOT NULL PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform text NOT NULL,
    shop_domain text,
    shop_name text,
    is_active boolean DEFAULT false,
    last_sync_at timestamp with time zone,
    sync_status text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);

-- Channel Fees Table
CREATE TABLE IF NOT EXISTS public.channel_fees (
    id uuid DEFAULT uuid_generate_v4() NOT NULL PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    channel_name text NOT NULL,
    percentage_fee numeric NOT NULL,
    fixed_fee numeric NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone
);

-- Conversations Table
CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid DEFAULT uuid_generate_v4() NOT NULL PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users(id),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    last_accessed_at timestamp with time zone DEFAULT now(),
    is_starred boolean DEFAULT false
);

-- Messages Table
CREATE TABLE IF NOT EXISTS public.messages (
    id uuid DEFAULT uuid_generate_v4() NOT NULL PRIMARY KEY,
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role text NOT NULL,
    content text,
    component text,
    component_props jsonb,
    visualization jsonb,
    confidence numeric,
    assumptions text[],
    is_error boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now()
);

-- Inventory Ledger Table
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id),
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

-- Audit Log Table
CREATE TABLE IF NOT EXISTS public.audit_log (
    id bigserial PRIMARY KEY,
    company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id uuid REFERENCES auth.users(id),
    action text NOT NULL,
    details jsonb,
    created_at timestamp with time zone DEFAULT now()
);

-- Webhook Events Table
CREATE TABLE IF NOT EXISTS public.webhook_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id text NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS webhook_events_integration_id_webhook_id_key ON public.webhook_events(integration_id, webhook_id);

-- Import Jobs Table
CREATE TABLE IF NOT EXISTS public.imports (
    id uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    created_by uuid NOT NULL REFERENCES auth.users(id),
    import_type text NOT NULL,
    file_name text NOT NULL,
    total_rows integer,
    processed_rows integer,
    failed_rows integer,
    status text NOT NULL DEFAULT 'pending',
    errors jsonb,
    summary jsonb,
    created_at timestamp with time zone DEFAULT now(),
    completed_at timestamp with time zone
);

-- Export Jobs Table
CREATE TABLE IF NOT EXISTS public.export_jobs (
    id uuid DEFAULT uuid_generate_v4() NOT NULL PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    requested_by_user_id uuid NOT NULL REFERENCES auth.users(id),
    status text NOT NULL DEFAULT 'pending',
    download_url text,
    expires_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);

-- Feedback Table
CREATE TABLE IF NOT EXISTS public.feedback (
    id uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users(id),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    subject_id text NOT NULL,
    subject_type text NOT NULL,
    feedback public.feedback_type NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);

-- Helper function to get company_id from user's claims
CREATE OR REPLACE FUNCTION public.get_company_id_for_user(p_user_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN (
    SELECT company_id
    FROM public.users
    WHERE id = p_user_id
  );
END;
$$;

-- Function to lock a user account
CREATE OR REPLACE FUNCTION public.lock_user_account(p_user_id uuid, p_lockout_duration text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE auth.users
    SET banned_until = now() + p_lockout_duration::interval
    WHERE id = p_user_id;
END;
$$;

-- Trigger to create a company and link user on new user signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  new_company_id uuid;
BEGIN
  -- Create a new company for the new user
  INSERT INTO public.companies (name)
  VALUES (new.raw_app_meta_data->>'company_name')
  RETURNING id INTO new_company_id;

  -- Link the new user to the new company
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (new.id, new_company_id, new.email, 'Owner');
  
  RETURN new;
END;
$$;

-- Drop trigger if it exists
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
-- Create the trigger
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Trigger function to prevent negative inventory
CREATE OR REPLACE FUNCTION public.handle_inventory_change_on_sale()
RETURNS TRIGGER AS $$
BEGIN
    -- Check if there is enough stock
    IF (SELECT inventory_quantity FROM public.product_variants WHERE id = NEW.variant_id) < NEW.quantity THEN
        RAISE EXCEPTION 'Insufficient stock for SKU %. Cannot fulfill order.', (SELECT sku FROM public.product_variants WHERE id = NEW.variant_id);
    END IF;

    -- Update inventory
    UPDATE public.product_variants
    SET inventory_quantity = inventory_quantity - NEW.quantity
    WHERE id = NEW.variant_id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop trigger if it exists
DROP TRIGGER IF EXISTS after_order_line_item_insert ON public.order_line_items;
-- Create the trigger
CREATE TRIGGER after_order_line_item_insert
AFTER INSERT ON public.order_line_items
FOR EACH ROW
EXECUTE FUNCTION public.handle_inventory_change_on_sale();


-- Trigger function to log inventory changes to audit table
CREATE OR REPLACE FUNCTION public.log_inventory_changes()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND OLD.inventory_quantity <> NEW.inventory_quantity THEN
        INSERT INTO public.audit_log (company_id, user_id, action, details)
        VALUES (
            NEW.company_id,
            auth.uid(), -- Assumes change is initiated by a logged-in user
            'inventory_quantity_updated',
            jsonb_build_object(
                'variant_id', NEW.id,
                'sku', NEW.sku,
                'old_quantity', OLD.inventory_quantity,
                'new_quantity', NEW.inventory_quantity
            )
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop trigger if it exists
DROP TRIGGER IF EXISTS inventory_update_audit_trigger ON public.product_variants;
-- Create the trigger
CREATE TRIGGER inventory_update_audit_trigger
AFTER UPDATE ON public.product_variants
FOR EACH ROW
WHEN (OLD.inventory_quantity IS DISTINCT FROM NEW.inventory_quantity)
EXECUTE FUNCTION public.log_inventory_changes();


-- Enable RLS for all relevant tables
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.imports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;


-- RLS Policies
DROP POLICY IF EXISTS "User can access their own company data" ON public.products;
CREATE POLICY "User can access their own company data" ON public.products FOR SELECT USING (company_id = (SELECT public.get_company_id_for_user(auth.uid())));
DROP POLICY IF EXISTS "User can access their own company data" ON public.product_variants;
CREATE POLICY "User can access their own company data" ON public.product_variants FOR SELECT USING (company_id = (SELECT public.get_company_id_for_user(auth.uid())));
DROP POLICY IF EXISTS "User can access their own company data" ON public.orders;
CREATE POLICY "User can access their own company data" ON public.orders FOR SELECT USING (company_id = (SELECT public.get_company_id_for_user(auth.uid())));
DROP POLICY IF EXISTS "User can access their own company data" ON public.order_line_items;
CREATE POLICY "User can access their own company data" ON public.order_line_items FOR SELECT USING (company_id = (SELECT public.get_company_id_for_user(auth.uid())));
DROP POLICY IF EXISTS "User can access their own company data" ON public.customers;
CREATE POLICY "User can access their own company data" ON public.customers FOR SELECT USING (company_id = (SELECT public.get_company_id_for_user(auth.uid())));
DROP POLICY IF EXISTS "User can access their own company data" ON public.suppliers;
CREATE POLICY "User can access their own company data" ON public.suppliers FOR SELECT USING (company_id = (SELECT public.get_company_id_for_user(auth.uid())));
DROP POLICY IF EXISTS "User can access their own company data" ON public.purchase_orders;
CREATE POLICY "User can access their own company data" ON public.purchase_orders FOR SELECT USING (company_id = (SELECT public.get_company_id_for_user(auth.uid())));
DROP POLICY IF EXISTS "User can access their own company data" ON public.purchase_order_line_items;
CREATE POLICY "User can access their own company data" ON public.purchase_order_line_items FOR SELECT USING (company_id = (SELECT public.get_company_id_for_user(auth.uid())));
DROP POLICY IF EXISTS "User can access their own company data" ON public.integrations;
CREATE POLICY "User can access their own company data" ON public.integrations FOR SELECT USING (company_id = (SELECT public.get_company_id_for_user(auth.uid())));
DROP POLICY IF EXISTS "User can access their own company data" ON public.company_settings;
CREATE POLICY "User can access their own company data" ON public.company_settings FOR SELECT USING (company_id = (SELECT public.get_company_id_for_user(auth.uid())));
DROP POLICY IF EXISTS "User can access their own company data" ON public.channel_fees;
CREATE POLICY "User can access their own company data" ON public.channel_fees FOR SELECT USING (company_id = (SELECT public.get_company_id_for_user(auth.uid())));
DROP POLICY IF EXISTS "User can access their own company data" ON public.conversations;
CREATE POLICY "User can access their own company data" ON public.conversations FOR SELECT USING (company_id = (SELECT public.get_company_id_for_user(auth.uid())));
DROP POLICY IF EXISTS "User can access their own company data" ON public.messages;
CREATE POLICY "User can access their own company data" ON public.messages FOR SELECT USING (company_id = (SELECT public.get_company_id_for_user(auth.uid())));
DROP POLICY IF EXISTS "User can access their own company data" ON public.audit_log;
CREATE POLICY "User can access their own company data" ON public.audit_log FOR SELECT USING (company_id = (SELECT public.get_company_id_for_user(auth.uid())));
DROP POLICY IF EXISTS "User can access their own company data" ON public.feedback;
CREATE POLICY "User can access their own company data" ON public.feedback FOR SELECT USING (company_id = (SELECT public.get_company_id_for_user(auth.uid())));
DROP POLICY IF EXISTS "User can access their own company data" ON public.imports;
CREATE POLICY "User can access their own company data" ON public.imports FOR SELECT USING (company_id = (SELECT public.get_company_id_for_user(auth.uid())));
DROP POLICY IF EXISTS "User can access their own company data" ON public.export_jobs;
CREATE POLICY "User can access their own company data" ON public.export_jobs FOR SELECT USING (company_id = (SELECT public.get_company_id_for_user(auth.uid())));
DROP POLICY IF EXISTS "User can access their own company data" ON public.webhook_events;
CREATE POLICY "User can access their own company data" ON public.webhook_events FOR SELECT USING (integration_id IN (SELECT id FROM public.integrations WHERE company_id = (SELECT public.get_company_id_for_user(auth.uid()))));


-- Grant usage on schemas
GRANT USAGE ON SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT USAGE ON SCHEMA public TO supabase_admin;


-- Grant all privileges on tables
GRANT ALL ON TABLE public.companies TO postgres, anon, authenticated, service_role;
GRANT ALL ON TABLE public.users TO postgres, anon, authenticated, service_role;
GRANT ALL ON TABLE public.company_settings TO postgres, anon, authenticated, service_role;
GRANT ALL ON TABLE public.suppliers TO postgres, anon, authenticated, service_role;
GRANT ALL ON TABLE public.products TO postgres, anon, authenticated, service_role;
GRANT ALL ON TABLE public.product_variants TO postgres, anon, authenticated, service_role;
GRANT ALL ON TABLE public.customers TO postgres, anon, authenticated, service_role;
GRANT ALL ON TABLE public.orders TO postgres, anon, authenticated, service_role;
GRANT ALL ON TABLE public.order_line_items TO postgres, anon, authenticated, service_role;
GRANT ALL ON TABLE public.purchase_orders TO postgres, anon, authenticated, service_role;
GRANT ALL ON TABLE public.purchase_order_line_items TO postgres, anon, authenticated, service_role;
GRANT ALL ON TABLE public.integrations TO postgres, anon, authenticated, service_role;
GRANT ALL ON TABLE public.channel_fees TO postgres, anon, authenticated, service_role;
GRANT ALL ON TABLE public.conversations TO postgres, anon, authenticated, service_role;
GRANT ALL ON TABLE public.messages TO postgres, anon, authenticated, service_role;
GRANT ALL ON TABLE public.inventory_ledger TO postgres, anon, authenticated, service_role;
GRANT ALL ON TABLE public.audit_log TO postgres, anon, authenticated, service_role;
GRANT ALL ON TABLE public.webhook_events TO postgres, anon, authenticated, service_role;
GRANT ALL ON TABLE public.imports TO postgres, anon, authenticated, service_role;
GRANT ALL ON TABLE public.export_jobs TO postgres, anon, authenticated, service_role;
GRANT ALL ON TABLE public.feedback TO postgres, anon, authenticated, service_role;

-- Grant execute on functions
GRANT EXECUTE ON FUNCTION public.handle_new_user() TO postgres, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_company_id_for_user(p_user_id uuid) TO postgres, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.lock_user_account(p_user_id uuid, p_lockout_duration text) TO postgres, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.handle_inventory_change_on_sale() TO postgres, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.log_inventory_changes() TO postgres, anon, authenticated, service_role;


-- Grant permissions to Supabase admin
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO supabase_admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO supabase_admin;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO supabase_admin;
