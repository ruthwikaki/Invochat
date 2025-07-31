
-- ### Functions ###

-- This function is called by the trigger 'on_auth_user_created'
-- when a new user signs up. It creates a new company, assigns the new
-- user as its owner, and creates the default company settings.
-- This function is also responsible for creating the corresponding user record in the public.users table.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  new_company_id uuid;
BEGIN
  -- Create a new company for the new user
  INSERT INTO public.companies (owner_id, name)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'company_name', NEW.email || '''s Company'))
  RETURNING id INTO new_company_id;

  -- Create a public user record linked to the company
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (NEW.id, new_company_id, NEW.email, 'Owner');
  
  -- Create default settings for the new company
  INSERT INTO public.company_settings (company_id)
  VALUES (new_company_id);

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ### Triggers ###

-- This trigger fires after a new user is created in the auth.users table.
-- It executes the 'handle_new_user' function to set up the user's company
-- and other initial data.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- ### Tables ###

-- Note: The order of table creation is important due to foreign key constraints.

CREATE TABLE IF NOT EXISTS public.companies (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    name TEXT NOT NULL,
    owner_id uuid REFERENCES auth.users(id),
    created_at timestamptz DEFAULT now() NOT NULL
);
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.users (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email TEXT,
    role TEXT DEFAULT 'Member'::text NOT NULL,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now()
);
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

CREATE TYPE public.company_role AS ENUM ('Owner', 'Admin', 'Member');
CREATE TABLE IF NOT EXISTS public.company_users (
    company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
    role public.company_role DEFAULT 'Member'::public.company_role NOT NULL,
    PRIMARY KEY (company_id, user_id)
);
ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;

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
    fts_document tsvector,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz
);
CREATE UNIQUE INDEX IF NOT EXISTS products_company_id_external_product_id_idx ON public.products (company_id, external_product_id);
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    default_lead_time_days INT,
    notes TEXT,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz
);
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.product_variants (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL,
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
    reorder_point INT,
    reorder_quantity INT,
    location TEXT,
    external_variant_id TEXT,
    version INT NOT NULL DEFAULT 1,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz
);
CREATE UNIQUE INDEX IF NOT EXISTS product_variants_company_id_external_variant_id_idx ON public.product_variants (company_id, external_variant_id);
CREATE UNIQUE INDEX IF NOT EXISTS product_variants_company_id_sku_idx ON public.product_variants (company_id, sku);
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.customers (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name TEXT,
    email TEXT,
    phone TEXT,
    external_customer_id TEXT,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz
);
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.orders (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
    order_number TEXT NOT NULL,
    external_order_id TEXT,
    financial_status TEXT,
    fulfillment_status TEXT,
    currency TEXT,
    subtotal INT NOT NULL,
    total_tax INT,
    total_shipping INT,
    total_discounts INT,
    total_amount INT NOT NULL,
    source_platform TEXT,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz
);
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id uuid REFERENCES public.product_variants(id) ON DELETE SET NULL,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
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

CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type TEXT NOT NULL, -- e.g., 'sale', 'purchase_order', 'manual_adjustment', 'reconciliation'
    quantity_change INT NOT NULL,
    new_quantity INT NOT NULL,
    related_id uuid, -- e.g., order_id, purchase_order_id
    notes TEXT,
    created_at timestamptz DEFAULT now() NOT NULL
);
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;


CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days INT NOT NULL DEFAULT 90,
    fast_moving_days INT NOT NULL DEFAULT 30,
    overstock_multiplier INT NOT NULL DEFAULT 3,
    high_value_threshold INT NOT NULL DEFAULT 1000, -- in cents
    predictive_stock_days INT NOT NULL DEFAULT 7,
    currency TEXT DEFAULT 'USD',
    timezone TEXT DEFAULT 'UTC',
    tax_rate NUMERIC DEFAULT 0,
    alert_settings jsonb DEFAULT '{"low_stock_threshold": 10, "critical_stock_threshold": 5, "email_notifications": true, "morning_briefing_enabled": true, "morning_briefing_time": "09:00"}'::jsonb,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz
);
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;


CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'Draft',
    po_number TEXT NOT NULL,
    total_cost INT NOT NULL,
    expected_arrival_date timestamptz,
    idempotency_key uuid,
    notes TEXT,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz
);
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    purchase_order_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    quantity INT NOT NULL,
    cost INT NOT NULL
);
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;


CREATE TABLE IF NOT EXISTS public.channel_fees (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    channel_name TEXT NOT NULL,
    percentage_fee NUMERIC NOT NULL,
    fixed_fee NUMERIC NOT NULL,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, channel_name)
);
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;


CREATE TYPE public.integration_platform AS ENUM ('shopify', 'woocommerce', 'amazon_fba');
CREATE TABLE IF NOT EXISTS public.integrations (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform integration_platform NOT NULL,
    shop_domain TEXT,
    shop_name TEXT,
    is_active BOOLEAN DEFAULT false,
    last_sync_at timestamptz,
    sync_status TEXT,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, platform)
);
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;


CREATE TABLE IF NOT EXISTS public.imports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  created_by uuid NOT NULL REFERENCES auth.users(id),
  import_type TEXT NOT NULL,
  file_name TEXT NOT NULL,
  total_rows INT,
  processed_rows INT,
  failed_rows INT,
  status TEXT NOT NULL DEFAULT 'pending',
  errors jsonb,
  summary jsonb,
  created_at timestamptz DEFAULT now(),
  completed_at timestamptz
);
ALTER TABLE public.imports ENABLE ROW LEVEL SECURITY;


CREATE TABLE IF NOT EXISTS public.audit_log (
  id BIGSERIAL PRIMARY KEY,
  company_id uuid REFERENCES companies(id) ON DELETE CASCADE,
  user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  action TEXT NOT NULL,
  details jsonb,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

CREATE TYPE public.message_role AS ENUM ('user', 'assistant', 'tool');
CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    created_at timestamptz DEFAULT now(),
    last_accessed_at timestamptz DEFAULT now(),
    is_starred BOOLEAN DEFAULT false
);
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.messages (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id uuid NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    role message_role NOT NULL,
    content TEXT,
    component TEXT,
    "componentProps" jsonb,
    visualization jsonb,
    confidence NUMERIC(3, 2),
    assumptions TEXT[],
    is_error BOOLEAN DEFAULT false,
    created_at timestamptz DEFAULT now()
);
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;


CREATE TYPE public.feedback_type AS ENUM ('helpful', 'unhelpful');
CREATE TABLE IF NOT EXISTS public.feedback (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  subject_id TEXT NOT NULL,
  subject_type TEXT NOT NULL,
  feedback feedback_type NOT NULL,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE public.feedback ENABLE ROW LEVEL SECURITY;


CREATE TABLE IF NOT EXISTS public.webhook_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id uuid NOT NULL REFERENCES integrations(id) ON DELETE CASCADE,
    webhook_id TEXT NOT NULL,
    created_at timestamptz DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS webhook_events_integration_id_webhook_id_idx ON public.webhook_events (integration_id, webhook_id);
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;


-- ### Views ###

-- A comprehensive view combining products and their variants with key details.
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.id,
    pv.product_id,
    pv.company_id,
    p.title AS product_title,
    pv.title AS variant_title,
    pv.sku,
    pv.price,
    pv.cost,
    pv.inventory_quantity,
    pv.reorder_point,
    pv.reorder_quantity,
    p.product_type,
    p.status AS product_status,
    p.image_url,
    pv.location,
    pv.barcode,
    pv.compare_at_price,
    pv.external_variant_id,
    pv.supplier_id,
    pv.option1_name,
    pv.option1_value,
    pv.option2_name,
    pv.option2_value,
    pv.option3_name,
    pv.option3_value,
    pv.created_at,
    pv.updated_at
FROM
    public.product_variants pv
JOIN
    public.products p ON pv.product_id = p.id
WHERE
    p.deleted_at IS NULL AND pv.deleted_at IS NULL;


-- ### Row-Level Security (RLS) Policies ###

-- Companies
CREATE POLICY "Users can only see their own company" ON public.companies FOR SELECT USING (id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

-- Users
CREATE POLICY "Users can view their own user record" ON public.users FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can view other users in their own company" ON public.users FOR SELECT USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

-- Company Users
CREATE POLICY "Users can view members of their own company" ON public.company_users FOR SELECT USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));
CREATE POLICY "Owners and Admins can insert new users into their company" ON public.company_users FOR INSERT WITH CHECK (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()) AND (SELECT role FROM public.company_users WHERE user_id = auth.uid() AND company_id = company_users.company_id) IN ('Owner', 'Admin'));
CREATE POLICY "Owners can update roles in their own company" ON public.company_users FOR UPDATE USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()) AND (SELECT role FROM public.company_users WHERE user_id = auth.uid() AND company_id = company_users.company_id) = 'Owner');
CREATE POLICY "Owners can remove users from their company" ON public.company_users FOR DELETE USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()) AND (SELECT role FROM public.company_users WHERE user_id = auth.uid() AND company_id = company_users.company_id) = 'Owner');

-- Products
CREATE POLICY "Users can manage products in their own company" ON public.products FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

-- Product Variants
CREATE POLICY "Users can manage variants in their own company" ON public.product_variants FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

-- Suppliers
CREATE POLICY "Users can manage suppliers in their own company" ON public.suppliers FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

-- Customers
CREATE POLICY "Users can manage customers in their own company" ON public.customers FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

-- Orders and Line Items
CREATE POLICY "Users can manage orders in their own company" ON public.orders FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));
CREATE POLICY "Users can manage line items in their own company" ON public.order_line_items FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

-- Purchase Orders and Line Items
CREATE POLICY "Users can manage POs in their own company" ON public.purchase_orders FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));
CREATE POLICY "Users can manage PO line items in their own company" ON public.purchase_order_line_items FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

-- Inventory Ledger
CREATE POLICY "Users can manage inventory ledger in their own company" ON public.inventory_ledger FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

-- Company Settings
CREATE POLICY "Users can manage settings for their own company" ON public.company_settings FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

-- Integrations
CREATE POLICY "Users can manage integrations for their own company" ON public.integrations FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

-- Imports
CREATE POLICY "Users can manage imports for their own company" ON public.imports FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

-- Audit Log
CREATE POLICY "Users can view the audit log for their own company" ON public.audit_log FOR SELECT USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

-- Conversations and Messages
CREATE POLICY "Users can manage their own conversations" ON public.conversations FOR ALL USING (user_id = auth.uid());
CREATE POLICY "Users can manage messages in their own conversations" ON public.messages FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

-- Feedback
CREATE POLICY "Users can manage their own feedback" ON public.feedback FOR ALL USING (user_id = auth.uid());

-- Webhook Events (Restrictive - only backend can insert)
CREATE POLICY "Allow backend to insert webhook events" ON public.webhook_events FOR INSERT WITH CHECK (false);

-- Channel Fees
CREATE POLICY "Users can manage channel fees in their own company" ON public.channel_fees FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));
