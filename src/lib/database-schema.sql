-- =====================================================
-- Reset and Setup
-- =====================================================

-- Drop existing public tables and functions in reverse dependency order to avoid errors
DROP VIEW IF EXISTS public.sales_summary, public.inventory_status, public.company_dashboard_metrics CASCADE;
DROP FUNCTION IF EXISTS public.update_updated_at_column, public.record_sale_transaction_v2, public.get_customer_analytics, public.get_sales_analytics, public.get_users_for_company, public.handle_new_user, public.record_order_from_platform CASCADE;
DROP TABLE IF EXISTS 
    public.refund_line_items,
    public.refunds,
    public.order_line_items, 
    public.orders, 
    public.product_variants, 
    public.products, -- Renaming inventory to products
    public.sale_items, -- Old table
    public.sales,      -- Old table
    public.inventory,  -- Old table to be replaced
    public.discounts, 
    public.customer_addresses, 
    public.inventory_ledger,
    public.suppliers,
    public.customers,
    public.sync_logs,
    public.sync_state,
    public.integrations,
    public.export_jobs,
    public.messages,
    public.conversations,
    public.audit_log,
    public.channel_fees,
    public.company_settings,
    public.users,
    public.companies
    CASCADE;

-- Create the companies table first as it's a top-level dependency
CREATE TABLE public.companies (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);

-- =====================================================
-- USER AND COMPANY SETUP
-- =====================================================
-- User Role Enum
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE public.user_role AS ENUM ('Owner', 'Admin', 'Member');
    END IF;
END$$;

-- Users table to store app-specific user data
CREATE TABLE public.users (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email text,
    role public.user_role NOT NULL DEFAULT 'Member',
    deleted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now()
);

-- Company Settings
CREATE TABLE public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    fast_moving_days integer NOT NULL DEFAULT 30,
    currency text DEFAULT 'USD',
    timezone text DEFAULT 'UTC',
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone
);

-- Function to handle new user sign-up and company creation
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_company_name text := NEW.raw_app_meta_data->>'company_name';
BEGIN
  -- Create a new company for the user
  INSERT INTO public.companies (name)
  VALUES (v_company_name)
  RETURNING id INTO v_company_id;

  -- Update the user's app_metadata with the new company_id
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', v_company_id, 'role', 'Owner')
  WHERE id = NEW.id;

  -- Create a corresponding entry in the public.users table
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (NEW.id, v_company_id, NEW.email, 'Owner');
  
  -- Create default settings for the new company
  INSERT INTO public.company_settings (company_id)
  VALUES (v_company_id);

  RETURN NEW;
END;
$$;

-- Trigger to execute the function on new user creation
CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();


-- =====================================================
-- MAIN E-COMMERCE ENTITIES
-- =====================================================
CREATE TABLE public.products (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    description text,
    handle text,
    product_type text,
    tags text[],
    status text, -- e.g., active, draft, archived
    image_url text,
    external_product_id text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone
);
CREATE INDEX idx_products_company_id ON public.products(company_id);


CREATE TABLE public.customers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name text,
    email text,
    total_orders integer DEFAULT 0,
    total_spent numeric(10,2) DEFAULT 0,
    first_order_date date,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now()
);
CREATE UNIQUE INDEX unique_customer_email_per_company ON public.customers(company_id, email) WHERE deleted_at IS NULL;
CREATE INDEX idx_customers_company_id ON public.customers(company_id);

-- 1. Product Variants Table
CREATE TABLE public.product_variants (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
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
    price numeric(10,2),
    compare_at_price numeric(10,2),
    cost numeric(10,2),
    weight numeric(10,3),
    weight_unit text,
    inventory_quantity integer DEFAULT 0,
    external_variant_id text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone
);
CREATE INDEX idx_product_variants_product_id ON public.product_variants(product_id);
CREATE INDEX idx_product_variants_company_id ON public.product_variants(company_id);
CREATE INDEX idx_product_variants_sku ON public.product_variants(sku);

-- 2. Orders Table
CREATE TABLE public.orders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number text NOT NULL,
    external_order_id text,
    customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
    financial_status text DEFAULT 'pending', -- pending/paid/refunded/partially_refunded
    fulfillment_status text DEFAULT 'unfulfilled', -- unfulfilled/partial/fulfilled
    currency text DEFAULT 'USD',
    subtotal numeric(10,2) NOT NULL DEFAULT 0,
    total_tax numeric(10,2) DEFAULT 0,
    total_shipping numeric(10,2) DEFAULT 0,
    total_discounts numeric(10,2) DEFAULT 0,
    total_amount numeric(10,2) NOT NULL,
    source_platform text, -- shopify/woocommerce
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone
);
CREATE INDEX idx_orders_company_id ON public.orders(company_id);
CREATE INDEX idx_orders_customer_id ON public.orders(customer_id);
CREATE INDEX idx_orders_order_number ON public.orders(order_number);
CREATE INDEX idx_orders_created_at ON public.orders(created_at);

-- 3. Order Line Items Table
CREATE TABLE public.order_line_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id uuid REFERENCES public.product_variants(id) ON DELETE SET NULL,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_name text,
    variant_title text,
    sku text,
    quantity integer NOT NULL,
    price numeric(10,2) NOT NULL,
    total_discount numeric(10,2) DEFAULT 0,
    tax_amount numeric(10,2) DEFAULT 0,
    cost_at_time numeric(10,2),
    external_line_item_id text
);
CREATE INDEX idx_order_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX idx_order_line_items_variant_id ON public.order_line_items(variant_id);

-- 4. Customer Addresses Table
CREATE TABLE public.customer_addresses (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id uuid NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
    address_type text NOT NULL DEFAULT 'shipping',
    first_name text,
    last_name text,
    company text,
    address1 text,
    address2 text,
    city text,
    province_code text,
    country_code text,
    zip text,
    phone text,
    is_default boolean DEFAULT false
);
CREATE INDEX idx_customer_addresses_customer_id ON public.customer_addresses(customer_id);

-- 5. Refunds Table
CREATE TABLE public.refunds (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    refund_number text NOT NULL,
    reason text,
    note text,
    total_amount numeric(10,2) NOT NULL,
    external_refund_id text,
    created_at timestamp with time zone DEFAULT now()
);
CREATE INDEX idx_refunds_company_id ON public.refunds(company_id);
CREATE INDEX idx_refunds_order_id ON public.refunds(order_id);

-- 6. Refund Line Items Table
CREATE TABLE public.refund_line_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    refund_id uuid NOT NULL REFERENCES public.refunds(id) ON DELETE CASCADE,
    order_line_item_id uuid NOT NULL REFERENCES public.order_line_items(id) ON DELETE CASCADE,
    quantity integer NOT NULL,
    amount numeric(10,2) NOT NULL,
    restock boolean DEFAULT true
);
CREATE INDEX idx_refund_line_items_refund_id ON public.refund_line_items(refund_id);

-- 7. Discounts Table
CREATE TABLE public.discounts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    code text NOT NULL,
    type text NOT NULL, -- percentage/fixed_amount/free_shipping
    value numeric(10,2) NOT NULL,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now()
);
CREATE INDEX idx_discounts_company_id ON public.discounts(company_id);
CREATE INDEX idx_discounts_code ON public.discounts(code);


-- =====================================================
-- INTERNAL APP TABLES
-- =====================================================
CREATE TABLE public.suppliers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE public.integrations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform text NOT NULL,
    shop_domain text,
    shop_name text,
    is_active boolean DEFAULT false,
    last_sync_at timestamp with time zone,
    sync_status text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone
);

CREATE TABLE public.conversations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    last_accessed_at timestamp with time zone DEFAULT now(),
    is_starred boolean DEFAULT false
);

CREATE TABLE public.messages (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role text NOT NULL,
    content text,
    visualization jsonb,
    confidence numeric,
    assumptions text[],
    is_error boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now()
);
-- =====================================================
-- TRIGGERS AND CONSTRAINTS
-- =====================================================
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_products_updated_at BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_product_variants_updated_at BEFORE UPDATE ON public.product_variants FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_orders_updated_at BEFORE UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

ALTER TABLE public.orders ADD CONSTRAINT unique_order_number_per_company UNIQUE (company_id, order_number);
ALTER TABLE public.refunds ADD CONSTRAINT unique_refund_number_per_company UNIQUE (company_id, refund_number);
ALTER TABLE public.discounts ADD CONSTRAINT unique_discount_code_per_company UNIQUE (company_id, code);
ALTER TABLE public.product_variants ADD CONSTRAINT unique_sku_per_company UNIQUE (company_id, sku);

-- =====================================================
-- PERMISSIONS
-- =====================================================
GRANT USAGE ON SCHEMA public TO authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated, service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated, service_role;
