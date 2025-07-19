-- Protect the "public" schema from write access by default
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO postgres, anon, authenticated, service_role;

-- Allow read access to all tables in the public schema
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO anon, authenticated, service_role;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;

-- Allow all actions on all tables for the service_role (used for server-side operations)
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO service_role;

-- Create custom types
CREATE TYPE public.user_role AS ENUM ('Owner', 'Admin', 'Member');
CREATE TYPE public.po_status AS ENUM ('Draft', 'Ordered', 'Partially Received', 'Received', 'Cancelled');

-- Create tables
CREATE TABLE public.companies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.users_companies (
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role public.user_role NOT NULL DEFAULT 'Member',
    PRIMARY KEY (user_id, company_id)
);
ALTER TABLE public.users_companies ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.company_settings (
    company_id UUID PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days INT NOT NULL DEFAULT 90,
    fast_moving_days INT NOT NULL DEFAULT 30,
    overstock_multiplier NUMERIC(5,2) NOT NULL DEFAULT 3.0,
    high_value_threshold INT NOT NULL DEFAULT 100000,
    predictive_stock_days INT NOT NULL DEFAULT 7,
    currency TEXT NOT NULL DEFAULT 'USD',
    tax_rate NUMERIC(5,4) NOT NULL DEFAULT 0,
    timezone TEXT NOT NULL DEFAULT 'UTC',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.products (
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
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, external_product_id)
);
CREATE INDEX ON public.products(company_id);
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.product_variants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku TEXT NOT NULL,
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
    location TEXT,
    external_variant_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, sku),
    UNIQUE(company_id, external_variant_id)
);
CREATE INDEX ON public.product_variants(company_id);
CREATE INDEX ON public.product_variants(product_id);
CREATE INDEX ON public.product_variants(sku);
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.inventory_ledger (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type TEXT NOT NULL,
    quantity_change INT NOT NULL,
    new_quantity INT NOT NULL,
    related_id UUID,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX ON public.inventory_ledger(company_id, variant_id);
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.suppliers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    default_lead_time_days INT,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX ON public.suppliers(company_id);
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.product_supplier (
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    supplier_id UUID NOT NULL REFERENCES public.suppliers(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    is_primary BOOLEAN DEFAULT true,
    PRIMARY KEY (product_id, supplier_id)
);
ALTER TABLE public.product_supplier ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.purchase_orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id UUID REFERENCES public.suppliers(id),
    status public.po_status NOT NULL DEFAULT 'Draft',
    po_number TEXT NOT NULL,
    total_cost INT NOT NULL DEFAULT 0,
    expected_arrival_date DATE,
    idempotency_key UUID UNIQUE,
    created_by_user_id UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX ON public.purchase_orders(company_id, status);
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.purchase_order_line_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    purchase_order_id UUID NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    quantity INT NOT NULL,
    cost INT
);
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.customers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    external_customer_id TEXT,
    customer_name TEXT,
    email TEXT,
    phone TEXT,
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX ON public.customers(company_id, email);
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.orders (
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
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);
CREATE INDEX ON public.orders(company_id);
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.order_line_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id),
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
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.refunds (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    refund_number TEXT NOT NULL,
    status TEXT NOT NULL,
    reason TEXT,
    note TEXT,
    total_amount INT NOT NULL,
    created_by_user_id UUID REFERENCES auth.users(id),
    external_refund_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.refunds ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  last_accessed_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  is_starred BOOLEAN DEFAULT FALSE NOT NULL
);
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  role TEXT NOT NULL,
  content TEXT,
  visualization JSONB,
  component TEXT,
  "componentProps" JSONB,
  confidence REAL,
  assumptions TEXT[],
  "isError" BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.integrations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  platform TEXT NOT NULL,
  shop_domain TEXT,
  shop_name TEXT,
  is_active BOOLEAN DEFAULT TRUE NOT NULL,
  sync_status TEXT,
  last_sync_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
  updated_at TIMESTAMPTZ
);
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.webhook_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  integration_id UUID NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
  webhook_id TEXT NOT NULL,
  received_at TIMESTAMPTZ DEFAULT now() NOT NULL,
  UNIQUE(integration_id, webhook_id)
);
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;


-- Create a view for unified inventory with product details
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT 
    pv.*,
    p.title as product_title,
    p.status as product_status,
    p.image_url as image_url,
    p.product_type as product_type
FROM 
    public.product_variants pv
JOIN 
    public.products p ON pv.product_id = p.id;

-- RLS Policies
-- Companies
CREATE POLICY "Users can only view their own company" ON public.companies FOR SELECT USING (id = (SELECT company_id FROM public.users_companies WHERE user_id = auth.uid()));
CREATE POLICY "Owners can update their own company" ON public.companies FOR UPDATE USING (id = (SELECT company_id FROM public.users_companies WHERE user_id = auth.uid() AND role = 'Owner'));

-- Users_Companies
CREATE POLICY "Users can view their own company association" ON public.users_companies FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "Owners can manage users in their company" ON public.users_companies FOR ALL USING (company_id = (SELECT company_id FROM public.users_companies WHERE user_id = auth.uid() AND role = 'Owner'));

-- All other tables are protected by company_id matching
CREATE POLICY "Users can manage data within their own company" ON public.products FOR ALL USING (company_id = (SELECT company_id FROM public.users_companies WHERE user_id = auth.uid()));
CREATE POLICY "Users can manage data within their own company" ON public.product_variants FOR ALL USING (company_id = (SELECT company_id FROM public.users_companies WHERE user_id = auth.uid()));
CREATE POLICY "Users can manage data within their own company" ON public.inventory_ledger FOR ALL USING (company_id = (SELECT company_id FROM public.users_companies WHERE user_id = auth.uid()));
CREATE POLICY "Users can manage data within their own company" ON public.suppliers FOR ALL USING (company_id = (SELECT company_id FROM public.users_companies WHERE user_id = auth.uid()));
CREATE POLICY "Users can manage data within their own company" ON public.product_supplier FOR ALL USING (company_id = (SELECT company_id FROM public.users_companies WHERE user_id = auth.uid()));
CREATE POLICY "Users can manage data within their own company" ON public.purchase_orders FOR ALL USING (company_id = (SELECT company_id FROM public.users_companies WHERE user_id = auth.uid()));
CREATE POLICY "Users can manage data within their own company" ON public.purchase_order_line_items FOR ALL USING (company_id = (SELECT company_id FROM public.users_companies WHERE user_id = auth.uid()));
CREATE POLICY "Users can manage data within their own company" ON public.customers FOR ALL USING (company_id = (SELECT company_id FROM public.users_companies WHERE user_id = auth.uid()));
CREATE POLICY "Users can manage data within their own company" ON public.orders FOR ALL USING (company_id = (SELECT company_id FROM public.users_companies WHERE user_id = auth.uid()));
CREATE POLICY "Users can manage data within their own company" ON public.order_line_items FOR ALL USING (company_id = (SELECT company_id FROM public.users_companies WHERE user_id = auth.uid()));
CREATE POLICY "Users can manage data within their own company" ON public.refunds FOR ALL USING (company_id = (SELECT company_id FROM public.users_companies WHERE user_id = auth.uid()));
CREATE POLICY "Users can manage their own conversations" ON public.conversations FOR ALL USING (user_id = auth.uid());
CREATE POLICY "Users can manage messages in their own conversations" ON public.messages FOR ALL USING (company_id = (SELECT company_id FROM public.users_companies WHERE user_id = auth.uid()));
CREATE POLICY "Users can manage their own integrations" ON public.integrations FOR ALL USING (company_id = (SELECT company_id FROM public.users_companies WHERE user_id = auth.uid()));
CREATE POLICY "Users can manage their own webhook events" ON public.webhook_events FOR ALL USING (EXISTS (SELECT 1 FROM public.integrations i WHERE i.id = integration_id AND i.company_id = (SELECT company_id FROM public.users_companies WHERE user_id = auth.uid())));

-- Function to handle new user signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  new_company_id UUID;
  company_name TEXT;
BEGIN
  -- Extract company name from user's metadata, default if not present
  company_name := new.raw_user_meta_data->>'company_name';
  IF company_name IS NULL OR company_name = '' THEN
    company_name := new.email || '''s Company';
  END IF;

  -- Create a new company for the user
  INSERT INTO public.companies (name)
  VALUES (company_name)
  RETURNING id INTO new_company_id;

  -- Link the user to the new company as 'Owner'
  INSERT INTO public.users_companies (user_id, company_id, role)
  VALUES (new.id, new_company_id, 'Owner');

  -- Update the user's app_metadata with the company_id for easy access
  UPDATE auth.users
  SET app_metadata = app_metadata || jsonb_build_object('company_id', new_company_id)
  WHERE id = new.id;
  
  RETURN new;
END;
$$;

-- Trigger to call the function on new user signup
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

CREATE OR REPLACE VIEW public.customers_view AS
SELECT 
    c.id,
    c.company_id,
    c.customer_name,
    c.email,
    COUNT(o.id) as total_orders,
    COALESCE(SUM(o.total_amount), 0) as total_spent,
    MIN(o.created_at) as first_order_date,
    c.created_at
FROM 
    public.customers c
LEFT JOIN
    public.orders o ON c.id = o.customer_id
WHERE c.deleted_at IS NULL
GROUP BY c.id;

CREATE OR REPLACE VIEW public.orders_view AS
SELECT
    o.id,
    o.company_id,
    o.order_number,
    o.external_order_id,
    o.customer_id,
    c.email as customer_email,
    o.financial_status,
    o.fulfillment_status,
    o.currency,
    o.subtotal,
    o.total_tax,
    o.total_shipping,
    o.total_discounts,
    o.total_amount,
    o.source_platform,
    o.created_at,
    o.updated_at
FROM public.orders o
LEFT JOIN public.customers c ON o.customer_id = c.id;
