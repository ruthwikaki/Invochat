
-- ### Enums ###

-- Enum for user roles within a company
CREATE TYPE public.company_role AS ENUM ('Owner', 'Admin', 'Member');
-- Enum for integration platforms
CREATE TYPE public.integration_platform AS ENUM ('shopify', 'woocommerce', 'amazon_fba');
-- Enum for message roles in chat
CREATE TYPE public.message_role AS ENUM ('user', 'assistant', 'tool');
-- Enum for feedback types
CREATE TYPE public.feedback_type AS ENUM ('helpful', 'unhelpful');


-- ### Tables ###

-- Table to store companies
CREATE TABLE public.companies (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    name text NOT NULL,
    owner_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.companies ADD CONSTRAINT companies_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES auth.users(id) ON DELETE CASCADE;


-- Table for company user relationships
CREATE TABLE public.company_users (
    user_id uuid NOT NULL,
    company_id uuid NOT NULL,
    role public.company_role NOT NULL DEFAULT 'Member',
    PRIMARY KEY (user_id, company_id)
);
ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_users ADD CONSTRAINT company_users_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE public.company_users ADD CONSTRAINT company_users_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;

-- Public user profiles (mirrors auth.users but with company context)
CREATE TABLE public.users (
  id uuid NOT NULL PRIMARY KEY,
  company_id uuid NOT NULL,
  email text,
  name text,
  avatar_url text
);
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ADD CONSTRAINT fk_users_auth_id FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE public.users ADD CONSTRAINT fk_users_company_id FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


-- Table for company-specific settings
CREATE TABLE public.company_settings (
    company_id uuid PRIMARY KEY NOT NULL,
    dead_stock_days int NOT NULL DEFAULT 90,
    fast_moving_days int NOT NULL DEFAULT 30,
    overstock_multiplier numeric NOT NULL DEFAULT 3,
    high_value_threshold int NOT NULL DEFAULT 100000, -- in cents
    predictive_stock_days int NOT NULL DEFAULT 7,
    currency text NOT NULL DEFAULT 'USD',
    tax_rate numeric NOT NULL DEFAULT 0.0,
    timezone text NOT NULL DEFAULT 'UTC',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ADD CONSTRAINT company_settings_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


-- ### Functions & Triggers for New User/Company Creation ###

-- New function to be called from the server action during signup.
-- This approach avoids race conditions with Supabase's internal triggers.
CREATE OR REPLACE FUNCTION public.create_company_and_owner(
  p_user_id uuid,
  p_company_name text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_user_email text;
BEGIN
  -- 1. Get the new user's email
  SELECT email INTO v_user_email FROM auth.users WHERE id = p_user_id;

  -- 2. Create the company and get its ID
  INSERT INTO public.companies (name, owner_id)
  VALUES (p_company_name, p_user_id)
  RETURNING id INTO v_company_id;

  -- 3. Update the user's app_metadata with the new company ID
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', v_company_id)
  WHERE id = p_user_id;

  -- 4. Create the corresponding public user profile
  INSERT INTO public.users (id, company_id, email)
  VALUES (p_user_id, v_company_id, v_user_email);

  -- 5. Link the user to the company with the 'Owner' role
  INSERT INTO public.company_users (user_id, company_id, role)
  VALUES (p_user_id, v_company_id, 'Owner');
  
END;
$$;


-- ### Other tables ###

-- Integrations Table
CREATE TABLE public.integrations (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL,
    platform public.integration_platform NOT NULL,
    shop_domain text,
    shop_name text,
    is_active boolean NOT NULL DEFAULT true,
    last_sync_at timestamptz,
    sync_status text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ADD CONSTRAINT integrations_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
CREATE UNIQUE INDEX integrations_company_id_platform_idx ON public.integrations (company_id, platform);

-- Webhook Events (for preventing replay attacks)
CREATE TABLE public.webhook_events (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    integration_id uuid NOT NULL,
    webhook_id text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_events ADD CONSTRAINT webhook_events_integration_id_fkey FOREIGN KEY (integration_id) REFERENCES public.integrations(id) ON DELETE CASCADE;
CREATE UNIQUE INDEX webhook_events_integration_id_webhook_id_idx ON public.webhook_events (integration_id, webhook_id);

-- Products Table
CREATE TABLE public.products (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL,
    title text NOT NULL,
    description text,
    handle text,
    product_type text,
    tags text[],
    status text,
    image_url text,
    external_product_id text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ADD CONSTRAINT products_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
CREATE UNIQUE INDEX products_company_id_external_product_id_idx ON public.products (company_id, external_product_id);


-- Product Variants Table
CREATE TABLE public.product_variants (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    product_id uuid NOT NULL,
    company_id uuid NOT NULL,
    sku text NOT NULL,
    title text,
    option1_name text,
    option1_value text,
    option2_name text,
    option2_value text,
    option3_name text,
    option3_value text,
    barcode text,
    price int, -- in cents
    compare_at_price int, -- in cents
    cost int, -- in cents
    inventory_quantity int NOT NULL DEFAULT 0,
    location text,
    reorder_point int,
    reorder_quantity int,
    supplier_id uuid,
    external_variant_id text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ADD CONSTRAINT fk_product_variants_product_id FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;
ALTER TABLE public.product_variants ADD CONSTRAINT product_variants_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
CREATE UNIQUE INDEX product_variants_company_id_sku_idx ON public.product_variants (company_id, sku);
CREATE UNIQUE INDEX product_variants_company_id_external_variant_id_idx ON public.product_variants (company_id, external_variant_id);


-- Suppliers Table
CREATE TABLE public.suppliers (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days int,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ADD CONSTRAINT suppliers_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.product_variants ADD CONSTRAINT product_variants_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) ON DELETE SET NULL;

-- Customers Table
CREATE TABLE public.customers (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL,
    name text,
    email text,
    phone text,
    external_customer_id text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    deleted_at timestamptz
);
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ADD CONSTRAINT customers_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
CREATE UNIQUE INDEX customers_company_id_external_customer_id_idx ON public.customers (company_id, external_customer_id);

-- Orders Table
CREATE TABLE public.orders (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL,
    order_number text NOT NULL,
    customer_id uuid,
    external_order_id text,
    financial_status text,
    fulfillment_status text,
    currency text,
    subtotal int NOT NULL,
    total_tax int,
    total_shipping int,
    total_discounts int,
    total_amount int NOT NULL,
    source_platform text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ADD CONSTRAINT orders_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.orders ADD CONSTRAINT orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE SET NULL;
CREATE UNIQUE INDEX orders_company_id_external_order_id_idx ON public.orders (company_id, external_order_id);

-- Order Line Items Table
CREATE TABLE public.order_line_items (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    order_id uuid NOT NULL,
    variant_id uuid,
    company_id uuid NOT NULL,
    product_name text,
    variant_title text,
    sku text,
    quantity int NOT NULL,
    price int NOT NULL,
    total_discount int,
    tax_amount int,
    cost_at_time int,
    external_line_item_id text
);
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ADD CONSTRAINT order_line_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;
ALTER TABLE public.order_line_items ADD CONSTRAINT order_line_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE SET NULL;
ALTER TABLE public.order_line_items ADD CONSTRAINT order_line_items_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;

-- Purchase Orders Table
CREATE TABLE public.purchase_orders (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL,
    supplier_id uuid,
    status text NOT NULL DEFAULT 'Draft',
    po_number text NOT NULL,
    total_cost int NOT NULL,
    expected_arrival_date date,
    idempotency_key uuid,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ADD CONSTRAINT purchase_orders_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.purchase_orders ADD CONSTRAINT purchase_orders_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) ON DELETE SET NULL;
CREATE UNIQUE INDEX purchase_orders_company_id_po_number_idx ON public.purchase_orders (company_id, po_number);

-- Purchase Order Line Items Table
CREATE TABLE public.purchase_order_line_items (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    purchase_order_id uuid NOT NULL,
    variant_id uuid NOT NULL,
    company_id uuid NOT NULL,
    quantity int NOT NULL,
    cost int NOT NULL -- cost per unit in cents
);
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_line_items ADD CONSTRAINT purchase_order_line_items_purchase_order_id_fkey FOREIGN KEY (purchase_order_id) REFERENCES public.purchase_orders(id) ON DELETE CASCADE;
ALTER TABLE public.purchase_order_line_items ADD CONSTRAINT purchase_order_line_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE CASCADE;
ALTER TABLE public.purchase_order_line_items ADD CONSTRAINT purchase_order_line_items_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;

-- Refunds Table
CREATE TABLE public.refunds (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL,
    order_id uuid NOT NULL,
    refund_number text NOT NULL,
    status text NOT NULL,
    reason text,
    note text,
    total_amount int NOT NULL,
    created_by_user_id uuid,
    external_refund_id text,
    created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.refunds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refunds ADD CONSTRAINT refunds_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.refunds ADD CONSTRAINT refunds_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;
ALTER TABLE public.refunds ADD CONSTRAINT refunds_created_by_user_id_fkey FOREIGN KEY (created_by_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
CREATE UNIQUE INDEX refunds_company_id_external_refund_id_idx ON public.refunds (company_id, external_refund_id);

-- Inventory Ledger Table
CREATE TABLE public.inventory_ledger (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL,
    variant_id uuid NOT NULL,
    change_type text NOT NULL, -- e.g., 'sale', 'purchase_order_received', 'manual_adjustment'
    quantity_change int NOT NULL,
    new_quantity int NOT NULL,
    related_id uuid, -- e.g., order_id, purchase_order_id
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ADD CONSTRAINT inventory_ledger_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.inventory_ledger ADD CONSTRAINT inventory_ledger_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE CASCADE;


-- Channel Fees Table (for net margin calculations)
CREATE TABLE public.channel_fees (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL,
    channel_name text NOT NULL,
    fixed_fee int, -- in cents
    percentage_fee numeric,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.channel_fees ADD CONSTRAINT channel_fees_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
CREATE UNIQUE INDEX channel_fees_company_id_channel_name_idx ON public.channel_fees(company_id, channel_name);

-- Chat/AI Related Tables
CREATE TABLE public.conversations (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid NOT NULL,
    company_id uuid NOT NULL,
    title text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    last_accessed_at timestamptz NOT NULL DEFAULT now(),
    is_starred boolean NOT NULL DEFAULT false
);
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ADD CONSTRAINT conversations_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE public.conversations ADD CONSTRAINT conversations_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;

CREATE TABLE public.messages (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    conversation_id uuid NOT NULL,
    company_id uuid NOT NULL,
    role public.message_role NOT NULL,
    content text NOT NULL,
    visualization jsonb,
    component text,
    componentProps jsonb,
    confidence real,
    assumptions text[],
    isError boolean,
    created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ADD CONSTRAINT messages_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.conversations(id) ON DELETE CASCADE;
ALTER TABLE public.messages ADD CONSTRAINT messages_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;

-- Feedback Table
CREATE TABLE public.feedback (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid NOT NULL,
    company_id uuid NOT NULL,
    subject_id uuid NOT NULL,
    subject_type text NOT NULL, -- e.g., 'message', 'alert'
    feedback public.feedback_type NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.feedback ADD CONSTRAINT feedback_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE public.feedback ADD CONSTRAINT feedback_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;

-- Audit Log Table
CREATE TABLE public.audit_log (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL,
    user_id uuid, -- can be null for system actions
    action text NOT NULL,
    details jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ADD CONSTRAINT audit_log_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.audit_log ADD CONSTRAINT audit_log_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL;


-- Export Jobs Table
CREATE TABLE public.export_jobs (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL,
    requested_by_user_id uuid NOT NULL,
    status text NOT NULL DEFAULT 'queued',
    download_url text,
    expires_at timestamptz,
    error_message text,
    created_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz
);
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.export_jobs ADD CONSTRAINT export_jobs_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.export_jobs ADD CONSTRAINT export_jobs_requested_by_user_id_fkey FOREIGN KEY (requested_by_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- ### RLS Policies ###

-- Helper function to get company_id from user's app_metadata
CREATE OR REPLACE FUNCTION public.get_company_id_for_user(p_user_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT (raw_app_meta_data->>'company_id')::uuid
  FROM auth.users
  WHERE id = p_user_id;
$$;

-- Generic RLS policy for tables with a 'company_id' column
CREATE OR REPLACE FUNCTION create_company_rls_policy(table_name text) RETURNS void AS $$
BEGIN
  EXECUTE format('
    CREATE POLICY "Users can only see their own company''s data"
    ON public.%I FOR SELECT
    USING (company_id = public.get_company_id_for_user(auth.uid()));', table_name);
  
  EXECUTE format('
    CREATE POLICY "Users can only insert into their own company"
    ON public.%I FOR INSERT
    WITH CHECK (company_id = public.get_company_id_for_user(auth.uid()));', table_name);
    
  EXECUTE format('
    CREATE POLICY "Users can only update their own company''s data"
    ON public.%I FOR UPDATE
    USING (company_id = public.get_company_id_for_user(auth.uid()));', table_name);

  EXECUTE format('
    CREATE POLICY "Users can only delete their own company''s data"
    ON public.%I FOR DELETE
    USING (company_id = public.get_company_id_for_user(auth.uid()));', table_name);
END;
$$ LANGUAGE plpgsql;

-- Apply RLS policies to all company-scoped tables
SELECT create_company_rls_policy(table_name)
FROM information_schema.tables
WHERE table_schema = 'public'
AND table_name IN (
    'products', 'product_variants', 'suppliers', 'customers', 'orders',
    'order_line_items', 'purchase_orders', 'purchase_order_line_items', 'refunds',
    'inventory_ledger', 'integrations', 'company_settings', 'company_users',
    'conversations', 'messages', 'feedback', 'audit_log', 'channel_fees',
    'export_jobs', 'webhook_events'
);

-- RLS for companies table
CREATE POLICY "Users can see their own company" ON public.companies FOR SELECT USING (id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "Owners can update their own company" ON public.companies FOR UPDATE USING (id = public.get_company_id_for_user(auth.uid()) AND auth.uid() = owner_id);

-- RLS for users table
CREATE POLICY "Users can see other users in their company" ON public.users FOR SELECT USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "Users can update their own profile" ON public.users FOR UPDATE USING (id = auth.uid());


-- ### Initial data functions ###
-- These are temporary and should be removed or secured in a real production environment.

-- Function to create multiple test users and assign them to companies
CREATE OR REPLACE FUNCTION create_test_users()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  stylehub_id uuid;
  techmart_id uuid;
  homefinds_id uuid;
  fitnessgear_id uuid;
  booknook_id uuid;
BEGIN
  -- Create companies first and get their IDs
  INSERT INTO public.companies (name, owner_id) VALUES ('StyleHub', (SELECT id FROM auth.users WHERE email = 'owner_stylehub@test.com')) RETURNING id INTO stylehub_id;
  INSERT INTO public.companies (name, owner_id) VALUES ('TechMart', (SELECT id FROM auth.users WHERE email = 'owner_techmart@test.com')) RETURNING id INTO techmart_id;
  INSERT INTO public.companies (name, owner_id) VALUES ('HomeFinds', (SELECT id FROM auth.users WHERE email = 'owner_homefinds@test.com')) RETURNING id INTO homefinds_id;
  INSERT INTO public.companies (name, owner_id) VALUES ('FitnessGear', (SELECT id FROM auth.users WHERE email = 'owner_fitnessgear@test.com')) RETURNING id INTO fitnessgear_id;
  INSERT INTO public.companies (name, owner_id) VALUES ('BookNook', (SELECT id FROM auth.users WHERE email = 'owner_booknook@test.com')) RETURNING id INTO booknook_id;

  -- Create users if they don't exist
  -- This part would be run manually in Supabase SQL editor using the provided user list
  -- Example for one user:
  -- IF NOT EXISTS (SELECT 1 FROM auth.users WHERE email = 'admin_stylehub@test.com') THEN
  --   INSERT INTO auth.users (email, password, ...) VALUES ('admin_stylehub@test.com', '...', ...);
  -- END IF;
  
  -- Link users to companies
  INSERT INTO public.company_users (user_id, company_id, role)
  VALUES
    ((SELECT id FROM auth.users WHERE email = 'owner_stylehub@test.com'), stylehub_id, 'Owner'),
    ((SELECT id FROM auth.users WHERE email = 'admin_stylehub@test.com'), stylehub_id, 'Admin'),
    ((SELECT id FROM auth.users WHERE email = 'member_stylehub@test.com'), stylehub_id, 'Member'),
    ((SELECT id FROM auth.users WHERE email = 'owner_techmart@test.com'), techmart_id, 'Owner'),
    ((SELECT id FROM auth.users WHERE email = 'admin_techmart@test.com'), techmart_id, 'Admin'),
    ((SELECT id FROM auth.users WHERE email = 'member_techmart@test.com'), techmart_id, 'Member'),
    ((SELECT id FROM auth.users WHERE email = 'owner_homefinds@test.com'), homefinds_id, 'Owner'),
    ((SELECT id FROM auth.users WHERE email = 'admin_homefinds@test.com'), homefinds_id, 'Admin'),
    ((SELECT id FROM auth.users WHERE email = 'member_homefinds@test.com'), homefinds_id, 'Member'),
    ((SELECT id FROM auth.users WHERE email = 'owner_fitnessgear@test.com'), fitnessgear_id, 'Owner'),
    ((SELECT id FROM auth.users WHERE email = 'admin_fitnessgear@test.com'), fitnessgear_id, 'Admin'),
    ((SELECT id FROM auth.users WHERE email = 'member_fitnessgear@test.com'), fitnessgear_id, 'Member'),
    ((SELECT id FROM auth.users WHERE email = 'owner_booknook@test.com'), booknook_id, 'Owner'),
    ((SELECT id FROM auth.users WHERE email = 'admin_booknook@test.com'), booknook_id, 'Admin'),
    ((SELECT id FROM auth.users WHERE email = 'member_booknook@test.com'), booknook_id, 'Member');
END;
$$;
