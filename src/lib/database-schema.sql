
-- ===============================================================================================
-- HELPER FUNCTIONS
-- ===============================================================================================

-- Gets the company_id for a user from their JWT, falling back to a direct lookup.
-- This function is crucial for RLS policies.
CREATE OR REPLACE FUNCTION get_company_id_for_user(p_user_id uuid)
RETURNS uuid AS $$
DECLARE
    company_id_from_jwt uuid;
    company_id_from_db uuid;
BEGIN
    -- First, try to get the company_id from the JWT's app_metadata.
    -- This is the fastest and most common method.
    SELECT (auth.jwt() -> 'app_metadata' ->> 'company_id')::uuid INTO company_id_from_jwt;

    IF company_id_from_jwt IS NOT NULL THEN
        RETURN company_id_from_jwt;
    END IF;

    -- If the JWT doesn't have it (e.g., during signup race conditions),
    -- fall back to a direct query on the company_users table.
    -- This part is NOT called by RLS policies on company_users itself, avoiding recursion.
    SELECT company_id INTO company_id_from_db
    FROM public.company_users
    WHERE user_id = p_user_id;

    RETURN company_id_from_db;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ===============================================================================================
-- TABLE CREATION
-- ===============================================================================================

-- Companies Table: Stores basic information about each company tenant.
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    name text NOT NULL,
    owner_id uuid REFERENCES auth.users(id),
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Company Users Table: A junction table to link users to companies with roles.
CREATE TABLE IF NOT EXISTS public.company_users (
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role company_role NOT NULL DEFAULT 'Member',
    PRIMARY KEY (company_id, user_id)
);

-- Suppliers Table: Stores supplier information for each company.
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

-- Products Table: Central repository for product master data.
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
    UNIQUE(company_id, external_product_id)
);

-- Product Variants Table: Stores individual SKUs for each product.
CREATE TABLE IF NOT EXISTS public.product_variants (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL,
    sku text NOT NULL,
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
    inventory_quantity integer NOT NULL DEFAULT 0,
    location text,
    external_variant_id text,
    reorder_point integer,
    reorder_quantity integer,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, sku)
);


-- Customers Table: Stores customer information.
CREATE TABLE IF NOT EXISTS public.customers (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  name text,
  email text,
  phone text,
  external_customer_id text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz,
  deleted_at timestamptz,
  UNIQUE(company_id, email)
);

-- Orders Table: Records sales transactions.
CREATE TABLE IF NOT EXISTS public.orders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
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
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, external_order_id)
);

-- Order Line Items Table: Details of products within each order.
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id uuid REFERENCES public.product_variants(id) ON DELETE SET NULL,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_name text,
    variant_title text,
    sku text,
    quantity integer NOT NULL,
    price integer NOT NULL, -- in cents
    total_discount integer,
    tax_amount integer,
    cost_at_time integer,
    external_line_item_id text
);


-- Purchase Orders Table: Manages orders placed with suppliers.
CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.suppliers(id),
    status text NOT NULL DEFAULT 'Draft',
    po_number text NOT NULL,
    total_cost integer NOT NULL,
    expected_arrival_date date,
    idempotency_key uuid,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, po_number)
);

-- Purchase Order Line Items Table: Details of products within each PO.
CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    purchase_order_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    quantity integer NOT NULL,
    cost integer NOT NULL -- in cents
);

-- Inventory Ledger Table: Immutable record of all stock movements.
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type text NOT NULL, -- e.g., 'sale', 'purchase_order', 'manual_adjustment'
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid, -- e.g., order_id or purchase_order_id
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);


-- Integrations Table: Manages connections to third-party platforms.
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
  UNIQUE(company_id, platform)
);


-- Webhook Events Table: Stores webhook events to prevent duplicates.
CREATE TABLE IF NOT EXISTS public.webhook_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id text NOT NULL,
    created_at timestamptz DEFAULT now(),
    UNIQUE(integration_id, webhook_id)
);

-- Company Settings Table: Configurable business logic parameters.
CREATE TABLE IF NOT EXISTS public.company_settings (
  company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
  dead_stock_days integer NOT NULL DEFAULT 90,
  fast_moving_days integer NOT NULL DEFAULT 30,
  overstock_multiplier real NOT NULL DEFAULT 3,
  high_value_threshold integer NOT NULL DEFAULT 100000, -- in cents
  predictive_stock_days integer NOT NULL DEFAULT 7,
  currency text DEFAULT 'USD',
  timezone text DEFAULT 'UTC',
  tax_rate numeric DEFAULT 0,
  alert_settings jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz
);

-- Audit Log Table: Tracks significant user and system actions.
CREATE TABLE IF NOT EXISTS public.audit_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  user_id uuid REFERENCES auth.users(id),
  action text NOT NULL,
  details jsonb,
  created_at timestamptz DEFAULT now()
);

-- Feedback Table: Stores user feedback on AI responses.
CREATE TABLE IF NOT EXISTS public.feedback (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  subject_id text NOT NULL,
  subject_type text NOT NULL,
  feedback feedback_type NOT NULL,
  created_at timestamptz DEFAULT now()
);

-- Conversations Table: Stores AI chat conversations.
CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    created_at timestamptz DEFAULT now(),
    last_accessed_at timestamptz DEFAULT now(),
    is_starred boolean DEFAULT false
);

-- Messages Table: Stores individual chat messages.
CREATE TABLE IF NOT EXISTS public.messages (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role message_role NOT NULL,
    content text NOT NULL,
    component text,
    "componentProps" jsonb,
    visualization jsonb,
    confidence numeric,
    assumptions text[],
    isError boolean,
    created_at timestamptz DEFAULT now()
);


-- Channel Fees Table: Stores sales channel fees for profit calculation.
CREATE TABLE IF NOT EXISTS public.channel_fees (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    channel_name text NOT NULL,
    percentage_fee numeric NOT NULL,
    fixed_fee numeric NOT NULL, -- in cents
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, channel_name)
);

-- Export Jobs Table: Manages asynchronous data export requests.
CREATE TABLE IF NOT EXISTS public.export_jobs (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    requested_by_user_id uuid NOT NULL REFERENCES auth.users(id),
    status text NOT NULL DEFAULT 'pending', -- pending, processing, completed, failed
    download_url text,
    expires_at timestamptz,
    error_message text,
    created_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz
);

-- Imports Table: Tracks CSV file import jobs.
CREATE TABLE IF NOT EXISTS public.imports (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
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
    created_at timestamptz DEFAULT now(),
    completed_at timestamptz
);

-- Alert History Table: Tracks user interactions with alerts.
CREATE TABLE IF NOT EXISTS public.alert_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    alert_id TEXT NOT NULL,
    status TEXT DEFAULT 'unread', -- 'unread', 'read', 'dismissed'
    created_at TIMESTAMPTZ DEFAULT NOW(),
    read_at TIMESTAMPTZ,
    dismissed_at TIMESTAMPTZ,
    metadata JSONB DEFAULT '{}'::jsonb,
    UNIQUE (company_id, alert_id)
);
-- ===============================================================================================
-- ROW-LEVEL SECURITY (RLS) POLICIES
-- ===============================================================================================

-- Enable RLS for all tables in the public schema
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.imports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.alert_history ENABLE ROW LEVEL SECURITY;


-- Policies for 'companies' table
CREATE POLICY "Allow owner to read their own company" ON public.companies FOR SELECT USING (id = get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow owner to update their own company" ON public.companies FOR UPDATE USING (id = get_company_id_for_user(auth.uid()));

-- Policies for 'company_users' table
CREATE POLICY "Allow users to see members of their own company" ON public.company_users FOR SELECT USING (company_id = get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow admin/owner to manage their company users" ON public.company_users FOR ALL USING (company_id = get_company_id_for_user(auth.uid()) AND check_user_permission(auth.uid(), 'Admin'));

-- Policies for tables with a direct company_id link
CREATE POLICY "Allow company members to access their own data" ON public.suppliers FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow company members to access their own data" ON public.products FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow company members to access their own data" ON public.product_variants FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow company members to access their own data" ON public.customers FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow company members to access their own data" ON public.orders FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow company members to access their own data" ON public.order_line_items FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow company members to access their own data" ON public.purchase_orders FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow company members to access their own data" ON public.purchase_order_line_items FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow company members to access their own data" ON public.inventory_ledger FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow company members to access their own data" ON public.integrations FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow company members to access their own settings" ON public.company_settings FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow company members to access their own audit logs" ON public.audit_log FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow company members to access their own feedback" ON public.feedback FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow users to access their own conversations" ON public.conversations FOR ALL USING (user_id = auth.uid());
CREATE POLICY "Allow users to access messages in their conversations" ON public.messages FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow company members to access their own data" ON public.channel_fees FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow users to access their own export jobs" ON public.export_jobs FOR ALL USING (requested_by_user_id = auth.uid());
CREATE POLICY "Allow company members to access their own imports" ON public.imports FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow company members to access their own alert history" ON public.alert_history FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));


-- ===============================================================================================
-- DATABASE TRIGGERS
-- ===============================================================================================

-- Trigger to create a company and link the owner when a new user signs up.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
  new_company_id uuid;
BEGIN
  -- Create a new company for the user
  INSERT INTO public.companies (name, owner_id)
  VALUES (new.raw_app_meta_data->>'company_name', new.id)
  RETURNING id INTO new_company_id;

  -- Link the user to the new company as an Owner
  INSERT INTO public.company_users (company_id, user_id, role)
  VALUES (new_company_id, new.id, 'Owner');
  
  -- Update the user's app_metadata with the new company_id
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id)
  WHERE id = new.id;
  
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop the trigger if it already exists to avoid errors on re-run
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Create the trigger
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- Trigger to automatically set the updated_at timestamp on various tables
CREATE OR REPLACE FUNCTION set_updated_at_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply the updated_at trigger to relevant tables
DROP TRIGGER IF EXISTS set_updated_at ON public.suppliers;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.suppliers FOR EACH ROW EXECUTE FUNCTION set_updated_at_timestamp();

DROP TRIGGER IF EXISTS set_updated_at ON public.products;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION set_updated_at_timestamp();

DROP TRIGGER IF EXISTS set_updated_at ON public.product_variants;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.product_variants FOR EACH ROW EXECUTE FUNCTION set_updated_at_timestamp();

DROP TRIGGER IF EXISTS set_updated_at ON public.customers;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.customers FOR EACH ROW EXECUTE FUNCTION set_updated_at_timestamp();

DROP TRIGGER IF EXISTS set_updated_at ON public.orders;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION set_updated_at_timestamp();

DROP TRIGGER IF EXISTS set_updated_at ON public.purchase_orders;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.purchase_orders FOR EACH ROW EXECUTE FUNCTION set_updated_at_timestamp();

DROP TRIGGER IF EXISTS set_updated_at ON public.company_settings;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.company_settings FOR EACH ROW EXECUTE FUNCTION set_updated_at_timestamp();
