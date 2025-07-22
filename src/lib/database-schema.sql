
-- Enable the UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
-- Enable pg_tle for more advanced function management if available
CREATE EXTENSION IF NOT EXISTS "pg_tle";

-- Custom Types
CREATE TYPE public.company_role AS ENUM ('Owner', 'Admin', 'Member');
CREATE TYPE public.integration_platform AS ENUM ('shopify', 'woocommerce', 'amazon_fba');
CREATE TYPE public.message_role AS ENUM ('user', 'assistant', 'tool');
CREATE TYPE public.feedback_type AS ENUM ('helpful', 'unhelpful');


-- COMPANIES TABLE
-- Stores the core company information.
CREATE TABLE public.companies (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    owner_id uuid NOT NULL REFERENCES auth.users(id),
    name text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only see their own company" ON public.companies FOR SELECT USING (id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));


-- COMPANY_USERS TABLE (JUNCTION TABLE)
-- Links users to companies and assigns them a role.
CREATE TABLE public.company_users (
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role company_role DEFAULT 'Member'::company_role NOT NULL,
    PRIMARY KEY (user_id, company_id)
);
ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can see their own association" ON public.company_users FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "Owners can manage users in their company" ON public.company_users FOR ALL USING (
    (SELECT role FROM public.company_users WHERE user_id = auth.uid() AND company_id = company_users.company_id) = 'Owner'
);


-- COMPANY_SETTINGS TABLE
-- Stores configurable business logic parameters for each company.
CREATE TABLE public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer DEFAULT 90 NOT NULL,
    fast_moving_days integer DEFAULT 30 NOT NULL,
    overstock_multiplier real DEFAULT 3 NOT NULL,
    high_value_threshold integer DEFAULT 100000 NOT NULL, -- Stored in cents
    predictive_stock_days integer DEFAULT 7 NOT NULL,
    currency text DEFAULT 'USD' NOT NULL,
    tax_rate numeric(5,4) DEFAULT 0.00 NOT NULL,
    timezone text DEFAULT 'UTC' NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage settings for their own company" ON public.company_settings FOR ALL USING (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));


-- PRODUCTS TABLE
CREATE TABLE public.products (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
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
    UNIQUE(company_id, external_product_id)
);
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage products for their own company" ON public.products FOR ALL USING (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));


-- SUPPLIERS TABLE
CREATE TABLE public.suppliers (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage suppliers for their own company" ON public.suppliers FOR ALL USING (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));


-- PRODUCT_VARIANTS TABLE
CREATE TABLE public.product_variants (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
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
    price integer, -- in cents
    compare_at_price integer, -- in cents
    cost integer, -- in cents
    inventory_quantity integer DEFAULT 0 NOT NULL,
    location text,
    supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL,
    reorder_point integer,
    reorder_quantity integer,
    external_variant_id text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    UNIQUE (company_id, sku),
    UNIQUE (company_id, external_variant_id)
);
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage variants for their own company" ON public.product_variants FOR ALL USING (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));


-- INVENTORY_LEDGER TABLE
-- Tracks all changes to inventory quantities for full auditability.
CREATE TABLE public.inventory_ledger (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type text NOT NULL, -- e.g., 'sale', 'purchase_order', 'manual_adjustment', 'reconciliation'
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid, -- e.g., order_id, purchase_order_id
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can see ledger entries for their own company" ON public.inventory_ledger FOR SELECT USING (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));
-- Note: Inserts into this table are handled by database functions and triggers, not direct user actions.


-- CUSTOMERS TABLE
CREATE TABLE public.customers (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text,
    email text,
    phone text,
    external_customer_id text,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    UNIQUE(company_id, external_customer_id)
);
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage customers for their own company" ON public.customers FOR ALL USING (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));


-- ORDERS TABLE
CREATE TABLE public.orders (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number text NOT NULL,
    customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
    external_order_id text,
    financial_status text,
    fulfillment_status text,
    currency text,
    subtotal integer NOT NULL,
    total_tax integer,
    total_shipping integer,
    total_discounts integer,
    total_amount integer NOT NULL,
    source_platform text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    UNIQUE(company_id, external_order_id)
);
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage orders for their own company" ON public.orders FOR ALL USING (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));


-- ORDER_LINE_ITEMS TABLE
CREATE TABLE public.order_line_items (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id uuid REFERENCES public.product_variants(id) ON DELETE SET NULL,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_name text,
    variant_title text,
    sku text,
    quantity integer NOT NULL,
    price integer NOT NULL, -- in cents
    total_discount integer, -- in cents
    tax_amount integer, -- in cents
    cost_at_time integer, -- in cents
    external_line_item_id text
);
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage line items for their own company" ON public.order_line_items FOR ALL USING (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));


-- INTEGRATIONS TABLE
CREATE TABLE public.integrations (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform integration_platform NOT NULL,
    shop_domain text,
    shop_name text,
    is_active boolean DEFAULT true NOT NULL,
    last_sync_at timestamp with time zone,
    sync_status text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    UNIQUE(company_id, platform)
);
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage integrations for their own company" ON public.integrations FOR ALL USING (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));


-- AI CONVERSATIONS & MESSAGES
CREATE TABLE public.conversations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    last_accessed_at timestamp with time zone DEFAULT now() NOT NULL,
    is_starred boolean DEFAULT false NOT NULL
);
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage their own conversations" ON public.conversations FOR ALL USING (user_id = auth.uid());

CREATE TABLE public.messages (
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
    isError boolean,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage messages in their own conversations" ON public.messages FOR ALL USING (conversation_id IN (SELECT id FROM public.conversations WHERE user_id = auth.uid()));


-- Helper function to get company_id from user's metadata
CREATE OR REPLACE FUNCTION get_company_id_from_metadata()
RETURNS uuid AS $$
  SELECT (auth.jwt()->>'user_metadata')::jsonb->>'company_id'
$$ LANGUAGE sql STABLE;

-- Add company_id to all tables on insert
CREATE OR REPLACE FUNCTION add_company_id()
RETURNS TRIGGER AS $$
BEGIN
  NEW.company_id = get_company_id_from_metadata();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Get company_id for a given user_id
CREATE OR REPLACE FUNCTION get_company_id_for_user(p_user_id UUID)
RETURNS UUID AS $$
DECLARE
    v_company_id UUID;
BEGIN
    SELECT company_id INTO v_company_id
    FROM public.company_users
    WHERE user_id = p_user_id;
    RETURN v_company_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- TRIGGER: Create a company and link user on new user signup
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  new_company_id uuid;
  company_name_from_meta text;
BEGIN
  -- Get company name from user metadata, default if not provided
  company_name_from_meta := NEW.raw_user_meta_data->>'company_name';
  IF company_name_from_meta IS NULL OR company_name_from_meta = '' THEN
      company_name_from_meta := 'My Company';
  END IF;

  -- Create a new company for the new user
  INSERT INTO public.companies (owner_id, name)
  VALUES (NEW.id, company_name_from_meta)
  RETURNING id INTO new_company_id;

  -- Link the user to the new company as 'Owner'
  INSERT INTO public.company_users (user_id, company_id, role)
  VALUES (NEW.id, new_company_id, 'Owner');

  -- Update the user's metadata with the new company_id
  UPDATE auth.users
  SET raw_user_meta_data = raw_user_meta_data || jsonb_build_object('company_id', new_company_id)
  WHERE id = NEW.id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop existing trigger if it exists
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
-- Create the trigger
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- Add indexes for performance
CREATE INDEX idx_products_company_id ON public.products(company_id);
CREATE INDEX idx_variants_product_id ON public.product_variants(product_id);
CREATE INDEX idx_variants_company_id_sku ON public.product_variants(company_id, sku);
CREATE INDEX idx_orders_company_id ON public.orders(company_id);
CREATE INDEX idx_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX idx_line_items_variant_id ON public.order_line_items(variant_id);

-- Get dashboard metrics
CREATE OR REPLACE FUNCTION get_dashboard_metrics(p_company_id UUID)
RETURNS JSONB AS $$
DECLARE
    total_products INT;
    total_orders INT;
    total_revenue NUMERIC;
    low_stock_count INT;
BEGIN
    SELECT COUNT(*) INTO total_products
    FROM product_variants WHERE company_id = p_company_id;
    
    SELECT COUNT(*) INTO total_orders
    FROM orders WHERE company_id = p_company_id;
    
    SELECT COALESCE(SUM(total_amount), 0) INTO total_revenue
    FROM orders WHERE company_id = p_company_id AND financial_status != 'cancelled';
    
    SELECT COUNT(*) INTO low_stock_count
    FROM product_variants WHERE company_id = p_company_id AND inventory_quantity < 10;
    
    RETURN jsonb_build_object(
        'total_products', total_products,
        'total_orders', total_orders,
        'total_revenue', total_revenue,
        'low_stock_count', low_stock_count
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get inventory metrics
CREATE OR REPLACE FUNCTION get_inventory_metrics(p_company_id UUID)
RETURNS TABLE(
    metric_name TEXT,
    metric_value NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT 'total_value'::TEXT, SUM(inventory_quantity * cost)
    FROM product_variants WHERE company_id = p_company_id
    UNION ALL
    SELECT 'total_items'::TEXT, SUM(inventory_quantity)::NUMERIC
    FROM product_variants WHERE company_id = p_company_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
