
-- Enable UUID generation
create extension if not exists "uuid-ossp" with schema public;

-- Custom Types
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'company_role') THEN
        CREATE TYPE public.company_role AS ENUM ('Owner', 'Admin', 'Member');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'integration_platform') THEN
        create type public.integration_platform as enum ('shopify', 'woocommerce', 'amazon_fba');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'feedback_type') THEN
        create type public.feedback_type as enum ('helpful', 'unhelpful');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'message_role') THEN
        create type public.message_role as enum ('user', 'assistant', 'tool');
    END IF;
END
$$;

-- #############################################################################
-- ### Tables
-- #############################################################################

-- Companies Table
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    name text NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT companies_pkey PRIMARY KEY (id)
);

-- Users Table (replaces company_users)
CREATE TABLE IF NOT EXISTS public.users (
    id uuid NOT NULL,
    company_id uuid NOT NULL,
    email text,
    role text DEFAULT 'member'::text,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT users_pkey PRIMARY KEY (id, company_id),
    CONSTRAINT users_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE,
    CONSTRAINT users_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);

-- Products Table
CREATE TABLE IF NOT EXISTS public.products (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    title text NOT NULL,
    description text,
    handle text,
    product_type text,
    tags text[],
    status text,
    image_url text,
    external_product_id text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone,
    deleted_at timestamp with time zone,
    fts_document tsvector,
    CONSTRAINT products_pkey PRIMARY KEY (id),
    CONSTRAINT products_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT products_external_id_unique UNIQUE (company_id, external_product_id)
);

-- Suppliers Table
CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT suppliers_pkey PRIMARY KEY (id),
    CONSTRAINT suppliers_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);

-- Product Variants Table
CREATE TABLE IF NOT EXISTS public.product_variants (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
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
    price integer,
    compare_at_price integer,
    cost integer,
    inventory_quantity integer NOT NULL DEFAULT 0,
    location text,
    external_variant_id text,
    supplier_id uuid,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    deleted_at timestamp with time zone,
    version integer NOT NULL DEFAULT 1,
    CONSTRAINT product_variants_pkey PRIMARY KEY (id),
    CONSTRAINT product_variants_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT product_variants_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE,
    CONSTRAINT product_variants_sku_unique UNIQUE (company_id, sku),
    CONSTRAINT product_variants_external_id_unique UNIQUE (company_id, external_variant_id),
    CONSTRAINT product_variants_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) ON DELETE SET NULL
);

-- Customers Table
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    customer_name text NOT NULL,
    email text,
    total_orders integer DEFAULT 0,
    total_spent integer DEFAULT 0,
    first_order_date date,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT customers_pkey PRIMARY KEY (id),
    CONSTRAINT customers_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);

-- Orders Table
CREATE TABLE IF NOT EXISTS public.orders (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL,
    order_number text NOT NULL,
    external_order_id text,
    customer_id uuid,
    financial_status text DEFAULT 'pending'::text,
    fulfillment_status text DEFAULT 'unfulfilled'::text,
    currency text DEFAULT 'USD'::text,
    subtotal integer NOT NULL DEFAULT 0,
    total_tax integer DEFAULT 0,
    total_shipping integer DEFAULT 0,
    total_discounts integer DEFAULT 0,
    total_amount integer NOT NULL,
    source_platform text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT orders_pkey PRIMARY KEY (id),
    CONSTRAINT orders_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE SET NULL
);

-- Order Line Items Table
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    order_id uuid NOT NULL,
    variant_id uuid NOT NULL,
    company_id uuid NOT NULL,
    product_name text,
    variant_title text,
    sku text,
    quantity integer NOT NULL,
    price integer NOT NULL,
    total_discount integer DEFAULT 0,
    tax_amount integer DEFAULT 0,
    cost_at_time integer,
    external_line_item_id text,
    CONSTRAINT order_line_items_pkey PRIMARY KEY (id),
    CONSTRAINT order_line_items_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT order_line_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE,
    CONSTRAINT order_line_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE RESTRICT
);

-- Inventory Ledger Table
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    variant_id uuid NOT NULL,
    company_id uuid NOT NULL,
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid,
    notes text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT inventory_ledger_pkey PRIMARY KEY (id),
    CONSTRAINT inventory_ledger_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT inventory_ledger_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE CASCADE
);

-- Company Settings Table
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid NOT NULL,
    dead_stock_days integer NOT NULL DEFAULT 90,
    fast_moving_days integer NOT NULL DEFAULT 30,
    overstock_multiplier integer NOT NULL DEFAULT 3,
    high_value_threshold integer NOT NULL DEFAULT 1000,
    predictive_stock_days integer NOT NULL DEFAULT 7,
    currency text DEFAULT 'USD'::text,
    timezone text DEFAULT 'UTC'::text,
    tax_rate numeric DEFAULT 0,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone,
    CONSTRAINT company_settings_pkey PRIMARY KEY (company_id),
    CONSTRAINT company_settings_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);

-- Integrations Table
CREATE TABLE IF NOT EXISTS public.integrations (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    platform text NOT NULL,
    shop_domain text,
    shop_name text,
    is_active boolean DEFAULT false,
    last_sync_at timestamp with time zone,
    sync_status text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone,
    CONSTRAINT integrations_pkey PRIMARY KEY (id),
    CONSTRAINT integrations_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);

-- Audit Log Table
CREATE TABLE IF NOT EXISTS public.audit_log (
    id bigserial,
    company_id uuid,
    user_id uuid,
    action text NOT NULL,
    details jsonb,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT audit_log_pkey PRIMARY KEY (id),
    CONSTRAINT audit_log_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT audit_log_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL
);

-- Conversations Table
CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL,
    company_id uuid NOT NULL,
    title text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    last_accessed_at timestamp with time zone DEFAULT now(),
    is_starred boolean DEFAULT false,
    CONSTRAINT conversations_pkey PRIMARY KEY (id),
    CONSTRAINT conversations_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
    CONSTRAINT conversations_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);

-- Messages Table
CREATE TABLE IF NOT EXISTS public.messages (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    conversation_id uuid NOT NULL,
    company_id uuid NOT NULL,
    role text NOT NULL,
    content text,
    component text,
    "componentProps" jsonb,
    visualization jsonb,
    confidence numeric,
    assumptions text[],
    "isError" boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT messages_pkey PRIMARY KEY (id),
    CONSTRAINT messages_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.conversations(id) ON DELETE CASCADE
);

-- Purchase Orders Table
CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    supplier_id uuid,
    status text NOT NULL DEFAULT 'Draft'::text,
    po_number text NOT NULL,
    total_cost integer NOT NULL,
    expected_arrival_date date,
    idempotency_key uuid,
    notes text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone,
    CONSTRAINT purchase_orders_pkey PRIMARY KEY (id),
    CONSTRAINT purchase_orders_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT purchase_orders_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) ON DELETE SET NULL
);

-- Purchase Order Line Items Table
CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    purchase_order_id uuid NOT NULL,
    variant_id uuid NOT NULL,
    company_id uuid NOT NULL,
    quantity integer NOT NULL,
    cost integer NOT NULL,
    CONSTRAINT purchase_order_line_items_pkey PRIMARY KEY (id),
    CONSTRAINT purchase_order_line_items_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT purchase_order_line_items_purchase_order_id_fkey FOREIGN KEY (purchase_order_id) REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    CONSTRAINT purchase_order_line_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE RESTRICT
);

-- Channel Fees Table
CREATE TABLE IF NOT EXISTS public.channel_fees (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    channel_name text NOT NULL,
    percentage_fee numeric NOT NULL,
    fixed_fee numeric NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone,
    CONSTRAINT channel_fees_pkey PRIMARY KEY (id),
    CONSTRAINT channel_fees_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);

-- Export Jobs Table
CREATE TABLE IF NOT EXISTS public.export_jobs (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    requested_by_user_id uuid NOT NULL,
    status text NOT NULL DEFAULT 'pending'::text,
    download_url text,
    expires_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT export_jobs_pkey PRIMARY KEY (id),
    CONSTRAINT export_jobs_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT export_jobs_requested_by_user_id_fkey FOREIGN KEY (requested_by_user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);

-- Webhook Events Table
CREATE TABLE IF NOT EXISTS public.webhook_events (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    integration_id uuid NOT NULL,
    webhook_id text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT webhook_events_pkey PRIMARY KEY (id),
    CONSTRAINT webhook_events_integration_id_fkey FOREIGN KEY (integration_id) REFERENCES public.integrations(id) ON DELETE CASCADE,
    CONSTRAINT webhook_events_integration_id_webhook_id_key UNIQUE (integration_id, webhook_id)
);


-- #############################################################################
-- ### Functions
-- #############################################################################

-- Function to get the current user's company ID
DROP FUNCTION IF EXISTS public.get_company_id_for_user(uuid);
CREATE FUNCTION public.get_company_id_for_user(p_user_id uuid)
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


-- Function to handle new user setup
DROP FUNCTION IF EXISTS public.handle_new_user();
CREATE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  new_company_id uuid;
  company_name_from_meta text;
BEGIN
  -- Extract company name from metadata, default if not present
  company_name_from_meta := NEW.raw_app_meta_data->>'company_name';
  IF company_name_from_meta IS NULL OR company_name_from_meta = '' THEN
    company_name_from_meta := NEW.email || '''s Company';
  END IF;

  -- Create a new company for the new user
  INSERT INTO public.companies (name)
  VALUES (company_name_from_meta)
  RETURNING id INTO new_company_id;

  -- Create a public user profile linked to the new company
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (NEW.id, new_company_id, NEW.email, 'Owner');
  
  -- Update the user's app_metadata with the new company_id
  -- This is crucial for middleware and RLS policies
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id)
  WHERE id = NEW.id;
  
  RETURN NEW;
END;
$$;

-- Function to handle inventory changes from sales
DROP FUNCTION IF EXISTS public.handle_inventory_change_on_sale();
CREATE FUNCTION public.handle_inventory_change_on_sale()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  current_stock integer;
BEGIN
  -- Get current stock level
  SELECT inventory_quantity INTO current_stock
  FROM public.product_variants
  WHERE id = NEW.variant_id;
  
  -- Check for sufficient stock
  IF current_stock < NEW.quantity THEN
    RAISE EXCEPTION 'Insufficient stock for SKU %. Available: %, Requested: %', (SELECT sku from public.product_variants where id = NEW.variant_id), current_stock, NEW.quantity;
  END IF;

  -- Update inventory quantity
  UPDATE public.product_variants
  SET inventory_quantity = inventory_quantity - NEW.quantity
  WHERE id = NEW.variant_id;

  -- Log the inventory change
  INSERT INTO public.inventory_ledger (variant_id, company_id, change_type, quantity_change, new_quantity, related_id, notes)
  VALUES (NEW.variant_id, NEW.company_id, 'sale', -NEW.quantity, current_stock - NEW.quantity, NEW.order_id, 'Order #' || (SELECT order_number from public.orders where id = NEW.order_id));

  RETURN NEW;
END;
$$;

-- Function to audit changes to inventory quantity
DROP FUNCTION IF EXISTS public.audit_inventory_changes();
CREATE OR REPLACE FUNCTION public.audit_inventory_changes()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND OLD.inventory_quantity <> NEW.inventory_quantity THEN
        INSERT INTO public.audit_log (company_id, user_id, action, details)
        VALUES (
            NEW.company_id,
            auth.uid(),
            'inventory_updated',
            jsonb_build_object(
                'variant_id', NEW.id,
                'sku', NEW.sku,
                'old_quantity', OLD.inventory_quantity,
                'new_quantity', NEW.inventory_quantity
            )
        );
    ELSIF TG_OP = 'INSERT' THEN
        INSERT INTO public.audit_log (company_id, user_id, action, details)
        VALUES (
            NEW.company_id,
            auth.uid(),
            'inventory_created',
            jsonb_build_object(
                'variant_id', NEW.id,
                'sku', NEW.sku,
                'initial_quantity', NEW.inventory_quantity
            )
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to lock a user account
DROP FUNCTION IF EXISTS public.lock_user_account(uuid, interval);
CREATE FUNCTION public.lock_user_account(p_user_id uuid, p_lockout_duration interval)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE auth.users
  SET banned_until = now() + p_lockout_duration
  WHERE id = p_user_id;
END;
$$;

-- #############################################################################
-- ### Triggers
-- #############################################################################

-- Trigger to set up a new user and company
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- Trigger to update inventory on new sales
DROP TRIGGER IF EXISTS on_order_line_item_insert ON public.order_line_items;
CREATE TRIGGER on_order_line_item_insert
  AFTER INSERT ON public.order_line_items
  FOR EACH ROW EXECUTE PROCEDURE public.handle_inventory_change_on_sale();

-- Trigger for inventory audit log
DROP TRIGGER IF EXISTS audit_inventory_trigger ON public.product_variants;
CREATE TRIGGER audit_inventory_trigger
AFTER INSERT OR UPDATE OF inventory_quantity ON public.product_variants
FOR EACH ROW EXECUTE FUNCTION public.audit_inventory_changes();


-- #############################################################################
-- ### Row-Level Security (RLS)
-- #############################################################################

-- Enable RLS for all tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;

-- Policies
-- Users can only see their own company's data.
DROP POLICY IF EXISTS "User can access their own company data" ON public.companies;
CREATE POLICY "User can access their own company data" ON public.companies FOR SELECT USING (id = public.get_company_id_for_user(auth.uid()));

DROP POLICY IF EXISTS "User can access their own user record" ON public.users;
CREATE POLICY "User can access their own user record" ON public.users FOR SELECT USING (id = auth.uid());

DROP POLICY IF EXISTS "User can access their own company data" ON public.products;
CREATE POLICY "User can access their own company data" ON public.products FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));

DROP POLICY IF EXISTS "User can access their own company data" ON public.product_variants;
CREATE POLICY "User can access their own company data" ON public.product_variants FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));

DROP POLICY IF EXISTS "User can access their own company data" ON public.suppliers;
CREATE POLICY "User can access their own company data" ON public.suppliers FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));

DROP POLICY IF EXISTS "User can access their own company data" ON public.customers;
CREATE POLICY "User can access their own company data" ON public.customers FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));

DROP POLICY IF EXISTS "User can access their own company data" ON public.orders;
CREATE POLICY "User can access their own company data" ON public.orders FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));

DROP POLICY IF EXISTS "User can access their own company data" ON public.order_line_items;
CREATE POLICY "User can access their own company data" ON public.order_line_items FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));

DROP POLICY IF EXISTS "User can access their own company data" ON public.inventory_ledger;
CREATE POLICY "User can access their own company data" ON public.inventory_ledger FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));

DROP POLICY IF EXISTS "User can access their own company settings" ON public.company_settings;
CREATE POLICY "User can access their own company settings" ON public.company_settings FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));

DROP POLICY IF EXISTS "User can access their own company integrations" ON public.integrations;
CREATE POLICY "User can access their own company integrations" ON public.integrations FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));

DROP POLICY IF EXISTS "User can access their own company audit log" ON public.audit_log;
CREATE POLICY "User can access their own company audit log" ON public.audit_log FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));

DROP POLICY IF EXISTS "User can access their own conversations" ON public.conversations;
CREATE POLICY "User can access their own conversations" ON public.conversations FOR ALL USING (user_id = auth.uid());

DROP POLICY IF EXISTS "User can access messages in their conversations" ON public.messages;
CREATE POLICY "User can access messages in their conversations" ON public.messages FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));

DROP POLICY IF EXISTS "User can access their own company purchase orders" ON public.purchase_orders;
CREATE POLICY "User can access their own company purchase orders" ON public.purchase_orders FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));

DROP POLICY IF EXISTS "User can access their own company PO line items" ON public.purchase_order_line_items;
CREATE POLICY "User can access their own company PO line items" ON public.purchase_order_line_items FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));
