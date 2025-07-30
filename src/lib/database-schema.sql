-- This is the single source of truth for your database schema.
-- It is idempotent and can be safely run multiple times.
-- This file should be the ONLY way you modify your database schema.
-- (Excluding temporary, still-in-development changes).

-- 1. Enable UUID extension
create extension if not exists "uuid-ossp" with schema extensions;

-- 2. Enable pgcrypto extension
create extension if not exists "pgcrypto" with schema extensions;

-- 3. Create company_role enum
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'company_role') THEN
        CREATE TYPE public.company_role AS ENUM ('Owner', 'Admin', 'Member');
    END IF;
END$$;

-- 4. Create integration_platform enum
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'integration_platform') THEN
        CREATE TYPE public.integration_platform AS ENUM ('shopify', 'woocommerce', 'amazon_fba');
    END IF;
END IF;
END$$;

-- 5. Create feedback_type enum
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'feedback_type') THEN
        CREATE TYPE public.feedback_type AS ENUM ('helpful', 'unhelpful');
    END IF;
END IF;
END$$;


-- 6. Create companies table
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    name text NOT NULL,
    owner_id uuid REFERENCES auth.users(id),
    created_at timestamptz NOT NULL DEFAULT now()
);

-- 7. Create company_users join table
CREATE TABLE IF NOT EXISTS public.company_users (
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role public.company_role NOT NULL DEFAULT 'Member',
    PRIMARY KEY (company_id, user_id)
);

-- 8. Create company_settings table
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    fast_moving_days integer NOT NULL DEFAULT 30,
    overstock_multiplier integer NOT NULL DEFAULT 3,
    high_value_threshold integer NOT NULL DEFAULT 100000, -- Stored in cents
    predictive_stock_days integer NOT NULL DEFAULT 7,
    currency text DEFAULT 'USD',
    timezone text DEFAULT 'UTC',
    tax_rate numeric DEFAULT 0,
    alert_settings jsonb DEFAULT '{"email_notifications": true, "low_stock_threshold": 10, "critical_stock_threshold": 5, "morning_briefing_enabled": true, "morning_briefing_time": "09:00"}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);

-- 9. Create suppliers table
CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);

-- 10. Create products table
CREATE TABLE IF NOT EXISTS public.products (
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
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, external_product_id)
);


-- 11. Create product_variants table
CREATE TABLE IF NOT EXISTS public.product_variants (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
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
    reorder_point integer,
    reorder_quantity integer,
    external_variant_id text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, sku)
);


-- 12. Create customers table
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text,
    email text,
    phone text,
    external_customer_id text,
    deleted_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, external_customer_id)
);

-- 13. Create orders table
CREATE TABLE IF NOT EXISTS public.orders (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
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


-- 14. Create order_line_items table
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
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

-- 15. Create purchase_orders table
CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.suppliers(id),
    status text NOT NULL DEFAULT 'Draft',
    po_number text NOT NULL,
    total_cost integer NOT NULL,
    expected_arrival_date date,
    idempotency_key uuid UNIQUE,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, po_number)
);

-- 16. Create purchase_order_line_items table
CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    purchase_order_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    quantity integer NOT NULL,
    cost integer NOT NULL
);

-- 17. Create integrations table
CREATE TABLE IF NOT EXISTS public.integrations (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform public.integration_platform NOT NULL,
    shop_domain text,
    shop_name text,
    is_active boolean DEFAULT false,
    last_sync_at timestamptz,
    sync_status text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, platform)
);

-- 18. Create conversations table
CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    created_at timestamptz DEFAULT now(),
    last_accessed_at timestamptz DEFAULT now(),
    is_starred boolean DEFAULT false
);

-- 19. Create messages table
CREATE TABLE IF NOT EXISTS public.messages (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role text NOT NULL,
    content text,
    component text,
    "componentProps" jsonb,
    visualization jsonb,
    confidence numeric,
    assumptions text[],
    "isError" boolean DEFAULT false,
    created_at timestamptz DEFAULT now()
);

-- 20. Create channel_fees table
CREATE TABLE IF NOT EXISTS public.channel_fees (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    channel_name text NOT NULL,
    percentage_fee numeric NOT NULL,
    fixed_fee numeric NOT NULL,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, channel_name)
);

-- 21. Create inventory_ledger table
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type text NOT NULL, -- e.g., 'sale', 'purchase_order', 'manual_adjustment', 'reconciliation'
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid, -- e.g., order_id, purchase_order_id
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- 22. Create audit_log table
CREATE TABLE IF NOT EXISTS public.audit_log (
  id bigserial PRIMARY KEY,
  company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE,
  user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  action text NOT NULL,
  details jsonb,
  created_at timestamptz DEFAULT now()
);

-- 23. Create feedback table
CREATE TABLE IF NOT EXISTS public.feedback (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    subject_id text NOT NULL,
    subject_type text NOT NULL, -- e.g., 'message', 'alert'
    feedback public.feedback_type NOT NULL,
    created_at timestamptz DEFAULT now()
);

-- 24. Create export_jobs table
CREATE TABLE IF NOT EXISTS public.export_jobs (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    requested_by_user_id uuid NOT NULL REFERENCES auth.users(id),
    status text NOT NULL DEFAULT 'pending',
    download_url text,
    expires_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- 25. Create webhook_events table
CREATE TABLE IF NOT EXISTS public.webhook_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id text NOT NULL,
    created_at timestamptz DEFAULT now(),
    UNIQUE(integration_id, webhook_id)
);


-- RLS Policies
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only see their own company" ON public.companies FOR SELECT USING (id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));

ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only see their own company_users rows" ON public.company_users FOR ALL USING (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));

-- Add more RLS policies for all other tables...
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only access their own company settings" ON public.company_settings FOR ALL USING (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));

ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only access their own company suppliers" ON public.suppliers FOR ALL USING (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only access their own company products" ON public.products FOR ALL USING (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));

ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only access their own company variants" ON public.product_variants FOR ALL USING (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));

ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only access their own company customers" ON public.customers FOR ALL USING (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));

ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only access their own company orders" ON public.orders FOR ALL USING (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));

ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only access their own company order line items" ON public.order_line_items FOR ALL USING (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));

ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only access their own company purchase orders" ON public.purchase_orders FOR ALL USING (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));

ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only access their own company PO line items" ON public.purchase_order_line_items FOR ALL USING (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));

ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only access their own company integrations" ON public.integrations FOR ALL USING (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));

ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only access their own conversations" ON public.conversations FOR ALL USING (user_id = auth.uid());

ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only access messages in their conversations" ON public.messages FOR ALL USING (conversation_id IN (SELECT id FROM public.conversations WHERE user_id = auth.uid()));

ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only access their own company inventory ledger" ON public.inventory_ledger FOR ALL USING (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));

ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only see audit logs for their own company" ON public.audit_log FOR SELECT USING (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));

ALTER TABLE public.feedback ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only access their own feedback" ON public.feedback FOR ALL USING (user_id = auth.uid());


-- Remove the old, problematic trigger if it exists
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Remove the old, problematic function if it exists
DROP FUNCTION IF EXISTS public.handle_new_user();

-- Create a new RPC function to handle company and user creation in a single transaction.
-- This is called from a server-side action to avoid race conditions.
CREATE OR REPLACE FUNCTION public.create_company_and_user(
    p_company_name text,
    p_user_email text,
    p_user_password text,
    p_email_redirect_to text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER -- <<< This is the critical change
AS $$
DECLARE
  new_company_id uuid;
  new_user_id uuid;
BEGIN
  -- 1. Create the company first.
  INSERT INTO public.companies (name)
  VALUES (p_company_name)
  RETURNING id INTO new_company_id;

  -- 2. Create the user in auth.users, passing the new company_id in the metadata.
  -- Supabase's internal hooks will use this metadata to populate the public.users table correctly.
  new_user_id := auth.signup(
    p_user_email,
    p_user_password,
    jsonb_build_object(
        'company_id', new_company_id,
        'company_name', p_company_name
    ),
    jsonb_build_object(
        'email_redirect_to', p_email_redirect_to
    )
  );

  -- 3. Link the user to the company with the 'Owner' role.
  INSERT INTO public.company_users (user_id, company_id, role)
  VALUES (new_user_id, new_company_id, 'Owner');
  
  -- 4. Update the company with the owner_id now that the user exists.
  UPDATE public.companies SET owner_id = new_user_id WHERE id = new_company_id;

  RETURN new_user_id;
END;
$$;
