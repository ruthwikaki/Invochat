
-- Enable UUID generation
create extension if not exists "uuid-ossp" with schema public;

-- Enable the pgcrypto extension for cryptographic functions
create extension if not exists "pgcrypto" with schema public;

-- Custom Types
do $$
begin
    if not exists (select 1 from pg_type where typname = 'company_role') then
        create type public.company_role as enum ('Owner', 'Admin', 'Member');
    end if;
    if not exists (select 1 from pg_type where typname = 'integration_platform') then
        create type public.integration_platform as enum ('shopify', 'woocommerce', 'amazon_fba');
    end if;
    if not exists (select 1 from pg_type where typname = 'message_role') then
        create type public.message_role as enum ('user', 'assistant', 'tool');
    end if;
    if not exists (select 1 from pg_type where typname = 'feedback_type') then
        create type public.feedback_type as enum ('helpful', 'unhelpful');
    end if;
end$$;


-- #############################################################################
-- Companies and Users
-- #############################################################################

-- Companies Table
CREATE TABLE
  public.companies (
    id uuid NOT NULL DEFAULT uuid_generate_v4 (),
    name text NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT companies_pkey PRIMARY KEY (id)
  );

-- Users Table
CREATE TABLE public.users (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email TEXT,
    role TEXT DEFAULT 'member',
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now()
);

-- Company Settings Table
CREATE TABLE
  public.company_settings (
    company_id uuid NOT NULL,
    dead_stock_days integer NOT NULL DEFAULT 90,
    fast_moving_days integer NOT NULL DEFAULT 30,
    predictive_stock_days integer NOT NULL DEFAULT 7,
    currency text NULL DEFAULT 'USD'::text,
    timezone text NULL DEFAULT 'UTC'::text,
    tax_rate numeric NULL DEFAULT 0,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NULL,
    overstock_multiplier integer NOT NULL DEFAULT 3,
    high_value_threshold integer NOT NULL DEFAULT 1000,
    CONSTRAINT company_settings_pkey PRIMARY KEY (company_id),
    CONSTRAINT company_settings_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies (id) ON DELETE CASCADE
  );


-- #############################################################################
-- Core Inventory and Sales Tables
-- #############################################################################

-- Products Table
CREATE TABLE
  public.products (
    id uuid NOT NULL DEFAULT uuid_generate_v4 (),
    company_id uuid NOT NULL,
    title text NOT NULL,
    description text NULL,
    handle text NULL,
    product_type text NULL,
    tags text[] NULL,
    status text NULL,
    image_url text NULL,
    external_product_id text NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NULL,
    deleted_at timestamptz,
    CONSTRAINT products_pkey PRIMARY KEY (id),
    CONSTRAINT products_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies (id) ON DELETE CASCADE
  );
CREATE UNIQUE INDEX products_company_id_external_product_id_idx ON public.products USING btree (company_id, external_product_id);

-- Suppliers Table
CREATE TABLE
  public.suppliers (
    id uuid NOT NULL DEFAULT uuid_generate_v4 (),
    company_id uuid NOT NULL,
    name text NOT NULL,
    email text NULL,
    phone text NULL,
    default_lead_time_days integer NULL,
    notes text NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamptz,
    CONSTRAINT suppliers_pkey PRIMARY KEY (id),
    CONSTRAINT suppliers_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies (id) ON DELETE CASCADE
  );

-- Product Variants Table
CREATE TABLE
  public.product_variants (
    id uuid NOT NULL DEFAULT gen_random_uuid (),
    product_id uuid NOT NULL,
    company_id uuid NOT NULL,
    sku text NOT NULL,
    title text NULL,
    option1_name text NULL,
    option1_value text NULL,
    option2_name text NULL,
    option2_value text NULL,
    option3_name text NULL,
    option3_value text NULL,
    barcode text NULL,
    price integer NULL,
    compare_at_price integer NULL,
    cost integer NULL,
    inventory_quantity integer NOT NULL DEFAULT 0,
    external_variant_id text NULL,
    created_at timestamp with time zone NULL DEFAULT now(),
    updated_at timestamp with time zone NULL DEFAULT now(),
    location text NULL,
    deleted_at timestamptz,
    version integer NOT NULL DEFAULT 1,
    reorder_point integer,
    reorder_quantity integer,
    supplier_id uuid null,
    CONSTRAINT product_variants_pkey PRIMARY KEY (id),
    CONSTRAINT product_variants_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies (id) ON DELETE CASCADE,
    CONSTRAINT product_variants_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products (id) ON DELETE CASCADE,
    CONSTRAINT product_variants_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers (id) ON DELETE SET NULL
  );
CREATE UNIQUE INDEX product_variants_company_id_sku_idx ON public.product_variants USING btree (company_id, sku);
CREATE UNIQUE INDEX product_variants_company_id_external_variant_id_idx ON public.product_variants USING btree (company_id, external_variant_id);

-- Customers Table
CREATE TABLE public.customers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    external_customer_id TEXT,
    name TEXT,
    email TEXT,
    phone TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ
);
CREATE UNIQUE INDEX customers_company_id_external_customer_id_idx ON public.customers (company_id, external_customer_id);

-- Orders Table
CREATE TABLE public.orders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    order_number TEXT NOT NULL,
    external_order_id TEXT,
    customer_id uuid REFERENCES customers(id) ON DELETE SET NULL,
    financial_status TEXT DEFAULT 'pending',
    fulfillment_status TEXT DEFAULT 'unfulfilled',
    currency TEXT DEFAULT 'USD',
    subtotal INT NOT NULL DEFAULT 0,
    total_tax INT DEFAULT 0,
    total_shipping INT DEFAULT 0,
    total_discounts INT DEFAULT 0,
    total_amount INT NOT NULL,
    source_platform TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Order Line Items Table
CREATE TABLE public.order_line_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    variant_id uuid REFERENCES product_variants(id) ON DELETE SET NULL,
    company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    product_name TEXT,
    variant_title TEXT,
    sku TEXT,
    quantity INT NOT NULL,
    price INT NOT NULL,
    total_discount INT DEFAULT 0,
    tax_amount INT DEFAULT 0,
    cost_at_time INT,
    external_line_item_id TEXT
);

-- Inventory Ledger Table
CREATE TABLE public.inventory_ledger (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
    change_type TEXT NOT NULL,
    quantity_change INT NOT NULL,
    new_quantity INT NOT NULL,
    related_id uuid, -- For Order ID or PO ID
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- #############################################################################
-- Integrations, AI, and System Tables
-- #############################################################################

-- Integrations Table
CREATE TABLE public.integrations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    platform integration_platform NOT NULL,
    shop_domain TEXT,
    shop_name TEXT,
    is_active BOOLEAN DEFAULT false,
    last_sync_at TIMESTAMPTZ,
    sync_status TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE (company_id, platform)
);

-- Webhook Events Table
CREATE TABLE public.webhook_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id uuid NOT NULL REFERENCES integrations(id) ON DELETE CASCADE,
    webhook_id TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE (integration_id, webhook_id)
);


-- Conversations Table (for AI Chat)
CREATE TABLE public.conversations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    last_accessed_at TIMESTAMPTZ DEFAULT now(),
    is_starred BOOLEAN DEFAULT false
);

-- Messages Table (for AI Chat)
CREATE TABLE public.messages (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id uuid NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    role message_role NOT NULL,
    content TEXT,
    component TEXT,
    component_props JSONB,
    visualization JSONB,
    confidence NUMERIC,
    assumptions TEXT[],
    is_error BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Audit Log Table
CREATE TABLE public.audit_log (
    id bigserial PRIMARY KEY,
    company_id uuid REFERENCES companies(id) ON DELETE CASCADE,
    user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    details JSONB,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- #############################################################################
-- Security and User Management Functions
-- #############################################################################

-- Function to create a new company and assign the owner role.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  company_id uuid;
begin
  -- Create a new company for the new user
  insert into public.companies (name)
  values (new.raw_app_meta_data->>'company_name')
  returning id into company_id;

  -- Update the user's app_metadata with the new company_id
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id)
  where id = new.id;
  
  -- Create a public user profile
  insert into public.users (id, company_id, email, role)
  values(new.id, company_id, new.email, 'Owner');

  return new;
end;
$$;

-- Trigger to call the function when a new user signs up
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


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

-- #############################################################################
-- Row Level Security (RLS)
-- #############################################################################

-- Enable RLS for all relevant tables
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;

-- Helper function to get the company_id from the user's claims
CREATE OR REPLACE FUNCTION auth.get_company_id()
RETURNS uuid
LANGUAGE sql STABLE
AS $$
  SELECT (current_setting('request.jwt.claims', true)::jsonb -> 'app_metadata' ->> 'company_id')::uuid
$$;

-- Policies to enforce data isolation by company_id
CREATE POLICY "Allow full access based on company_id" ON public.products
  FOR ALL USING (company_id = auth.get_company_id());

CREATE POLICY "Allow full access based on company_id" ON public.product_variants
  FOR ALL USING (company_id = auth.get_company_id());

CREATE POLICY "Allow full access based on company_id" ON public.suppliers
  FOR ALL USING (company_id = auth.get_company_id());
  
CREATE POLICY "Allow full access based on company_id" ON public.orders
  FOR ALL USING (company_id = auth.get_company_id());
  
CREATE POLICY "Allow full access based on company_id" ON public.order_line_items
  FOR ALL USING (company_id = auth.get_company_id());

CREATE POLICY "Allow full access based on company_id" ON public.customers
  FOR ALL USING (company_id = auth.get_company_id());
  
CREATE POLICY "Allow full access based on company_id" ON public.integrations
  FOR ALL USING (company_id = auth.get_company_id());
  
CREATE POLICY "Allow full access based on company_id" ON public.audit_log
  FOR ALL USING (company_id = auth.get_company_id());
  
CREATE POLICY "Allow access to own conversations" ON public.conversations
  FOR ALL USING (user_id = auth.uid());

CREATE POLICY "Allow access to own messages" ON public.messages
  FOR ALL USING (company_id = auth.get_company_id());
  
CREATE POLICY "Allow access to own company settings" ON public.company_settings
  FOR ALL USING (company_id = auth.get_company_id());
  

-- #############################################################################
-- Database Triggers for Automation
-- #############################################################################

-- Function to handle inventory changes on sales
CREATE OR REPLACE FUNCTION public.handle_inventory_change_on_sale()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    current_stock INT;
BEGIN
    -- Lock the variant row to prevent race conditions
    SELECT inventory_quantity INTO current_stock FROM public.product_variants
    WHERE id = NEW.variant_id FOR UPDATE;

    -- Check for sufficient stock
    IF current_stock < NEW.quantity THEN
        RAISE EXCEPTION 'Insufficient stock for SKU %: Tried to sell %, but only % available.', 
            (SELECT sku FROM public.product_variants WHERE id = NEW.variant_id),
            NEW.quantity, 
            current_stock;
    END IF;

    -- Update inventory quantity
    UPDATE public.product_variants
    SET inventory_quantity = inventory_quantity - NEW.quantity
    WHERE id = NEW.variant_id;

    -- Record the change in the ledger
    INSERT INTO public.inventory_ledger(company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes)
    VALUES (NEW.company_id, NEW.variant_id, 'sale', -NEW.quantity, current_stock - NEW.quantity, NEW.order_id, 'Order #' || (SELECT order_number FROM public.orders WHERE id = NEW.order_id));
    
    RETURN NEW;
END;
$$;

-- Trigger for sales
CREATE TRIGGER on_new_order_line_item
  AFTER INSERT ON public.order_line_items
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_inventory_change_on_sale();


-- Function to log changes to product_variants.inventory_quantity
CREATE OR REPLACE FUNCTION public.log_inventory_quantity_change()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.inventory_quantity <> NEW.inventory_quantity THEN
        INSERT INTO public.audit_log (company_id, user_id, action, details)
        VALUES (
            NEW.company_id,
            auth.uid(), -- Assumes the change is initiated by a logged-in user
            'inventory_quantity_updated',
            jsonb_build_object(
                'variant_id', NEW.id,
                'sku', NEW.sku,
                'product_id', NEW.product_id,
                'old_quantity', OLD.inventory_quantity,
                'new_quantity', NEW.inventory_quantity,
                'change_source', 'product_variants_trigger'
            )
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to log inventory changes
CREATE TRIGGER log_inventory_change_trigger
AFTER UPDATE ON public.product_variants
FOR EACH ROW
WHEN (OLD.inventory_quantity IS DISTINCT FROM NEW.inventory_quantity)
EXECUTE FUNCTION public.log_inventory_quantity_change();

-- Set up cascade deletes
ALTER TABLE public.users
  ADD CONSTRAINT users_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies (id) ON DELETE CASCADE;

ALTER TABLE public.company_users
  DROP CONSTRAINT company_users_company_id_fkey,
  ADD CONSTRAINT company_users_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;

ALTER TABLE public.company_users
  DROP CONSTRAINT company_users_user_id_fkey,
  ADD CONSTRAINT company_users_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
  
