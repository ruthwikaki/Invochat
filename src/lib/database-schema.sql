
-- ---------------------------------------------------------------------
-- InvoChat - Simplified Database Schema
-- Focus: Inventory Intelligence, not Operations Management
-- ---------------------------------------------------------------------

-- 
-- Extensions
-- 
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

--
-- RLS (Row-Level Security)
--
ALTER ROLE supabase_admin SET pgrst.db_plan_enabled TO 'true';
ALTER ROLE authenticator SET pgrst.db_plan_enabled TO 'true';


--
-- Types
--
CREATE TYPE public.user_role AS ENUM (
    'Owner',
    'Admin',
    'Member'
);


--
-- Tables
--

-- Companies: Represents a single business/tenant.
CREATE TABLE public.companies (
    id uuid DEFAULT uuid_generate_v4() NOT NULL PRIMARY KEY,
    name text NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL
);
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;

-- Users: Stores user data, linked to a company and auth.users.
CREATE TABLE public.users (
    id uuid NOT NULL PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email text,
    role user_role DEFAULT 'Member'::public.user_role NOT NULL,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now()
);
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- Company Settings: Configurable business rules for a company.
CREATE TABLE public.company_settings (
    company_id uuid NOT NULL PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer DEFAULT 90 NOT NULL,
    fast_moving_days integer DEFAULT 30 NOT NULL,
    currency text DEFAULT 'USD'::text,
    timezone text DEFAULT 'UTC'::text,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz,
    -- Subscription & Billing Fields
    subscription_status text DEFAULT 'trial'::text,
    subscription_plan text DEFAULT 'starter'::text,
    subscription_expires_at timestamptz,
    stripe_customer_id text,
    stripe_subscription_id text
);
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow company members to read settings" ON public.company_settings FOR SELECT USING (auth.uid() IN (SELECT id FROM users WHERE company_id = company_settings.company_id));
CREATE POLICY "Allow company owner/admin to update settings" ON public.company_settings FOR UPDATE USING (public.is_company_owner_or_admin(company_id));


-- Suppliers: Simplified vendor information.
CREATE TABLE public.suppliers (
    id uuid DEFAULT uuid_generate_v4() NOT NULL PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz DEFAULT now(),
    UNIQUE (company_id, name)
);
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow company members to manage suppliers" ON public.suppliers FOR ALL USING (public.is_company_member(company_id));

-- Inventory: Core table for product and stock information.
CREATE TABLE public.inventory (
    id uuid DEFAULT uuid_generate_v4() NOT NULL PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL,
    sku text NOT NULL,
    quantity integer DEFAULT 0 NOT NULL,
    cost bigint DEFAULT 0 NOT NULL, -- Stored in cents
    reorder_point integer,
    reorder_quantity integer,
    last_sold_date date,
    supplier_id uuid REFERENCES public.suppliers(id),
    deleted_at timestamptz,
    deleted_by uuid REFERENCES auth.users(id),
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    UNIQUE (company_id, sku)
);
ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow company members to manage inventory" ON public.inventory FOR ALL USING (public.is_company_member(company_id));

-- Products: Core, unchanging product information.
CREATE TABLE public.products (
    id uuid DEFAULT uuid_generate_v4() NOT NULL PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku text NOT NULL,
    name text NOT NULL,
    category text,
    price bigint, -- Stored in cents
    barcode text,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz,
    UNIQUE (company_id, sku)
);
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow company members to manage products" ON public.products FOR ALL USING (public.is_company_member(company_id));
ALTER TABLE public.inventory ADD CONSTRAINT fk_inventory_product FOREIGN KEY (product_id) REFERENCES public.products(id);


-- Sales: Transaction records.
CREATE TABLE public.sales (
    id uuid DEFAULT uuid_generate_v4() NOT NULL PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sale_number text NOT NULL UNIQUE,
    customer_id uuid,
    total_amount bigint NOT NULL, -- Stored in cents
    payment_method text,
    notes text,
    created_at timestamptz DEFAULT now(),
    created_by uuid REFERENCES auth.users(id)
);
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow company members to manage sales" ON public.sales FOR ALL USING (public.is_company_member(company_id));

-- Sale Items: Line items for each sale.
CREATE TABLE public.sale_items (
    id uuid DEFAULT uuid_generate_v4() NOT NULL PRIMARY KEY,
    sale_id uuid NOT NULL REFERENCES public.sales(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id),
    quantity integer NOT NULL,
    unit_price bigint NOT NULL, -- Stored in cents
    cost_at_time bigint -- Stored in cents
);
ALTER TABLE public.sale_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow company members to manage sale items" ON public.sale_items FOR ALL USING (public.is_company_member(company_id));


-- Customers: Basic customer information.
CREATE TABLE public.customers (
    id uuid DEFAULT uuid_generate_v4() NOT NULL PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name text NOT NULL,
    email text,
    created_at timestamptz DEFAULT now()
);
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow company members to manage customers" ON public.customers FOR ALL USING (public.is_company_member(company_id));
ALTER TABLE public.sales ADD CONSTRAINT fk_sales_customer FOREIGN KEY (customer_id) REFERENCES public.customers(id);

-- Inventory Ledger: Simple, append-only log of stock changes.
CREATE TABLE public.inventory_ledger (
    id uuid DEFAULT uuid_generate_v4() NOT NULL PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id),
    product_id uuid NOT NULL REFERENCES public.products(id),
    change_type text NOT NULL, -- 'sale', 'restock', 'adjustment'
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid, -- e.g., sale_id or manual adjustment id
    created_by uuid REFERENCES auth.users(id),
    created_at timestamptz DEFAULT now() NOT NULL
);
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow company members to manage ledger" ON public.inventory_ledger FOR ALL USING (public.is_company_member(company_id));


-- Integrations: For connecting to platforms like Shopify.
CREATE TABLE public.integrations (
  id uuid DEFAULT uuid_generate_v4() NOT NULL PRIMARY KEY,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  platform text NOT NULL,
  shop_domain text,
  shop_name text,
  is_active boolean DEFAULT false,
  last_sync_at timestamptz,
  sync_status text,
  created_at timestamptz DEFAULT now() NOT NULL,
  updated_at timestamptz,
  UNIQUE(company_id, platform)
);
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow company members to manage integrations" ON public.integrations FOR ALL USING (public.is_company_member(company_id));


-- Conversations & Messages (for the chat UI)
CREATE TABLE public.conversations (
  id uuid DEFAULT uuid_generate_v4() NOT NULL PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  title text NOT NULL,
  created_at timestamptz DEFAULT now(),
  last_accessed_at timestamptz DEFAULT now(),
  is_starred boolean DEFAULT false
);
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow user to manage their own conversations" ON public.conversations FOR ALL USING (auth.uid() = user_id);

CREATE TABLE public.messages (
  id uuid DEFAULT uuid_generate_v4() NOT NULL PRIMARY KEY,
  conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES public.companies(id),
  role text NOT NULL,
  content text,
  visualization jsonb,
  created_at timestamptz DEFAULT now(),
  is_error boolean DEFAULT false
);
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow user to manage messages in their conversations" ON public.messages FOR ALL USING (auth.uid() = (SELECT user_id FROM conversations WHERE id = conversation_id));


--
-- Indexes
--
CREATE INDEX idx_inventory_company_product ON public.inventory(company_id, product_id);
CREATE INDEX idx_products_company_sku ON public.products(company_id, sku);
CREATE INDEX idx_inventory_ledger_product ON public.inventory_ledger(product_id, created_at DESC);
CREATE INDEX idx_sales_created_at ON public.sales(company_id, created_at DESC);


--
-- Stored Procedures & Functions
--

-- Helper function to check user role
CREATE OR REPLACE FUNCTION public.is_company_owner_or_admin(p_company_id uuid)
RETURNS boolean AS $$
DECLARE
    user_role_val public.user_role;
BEGIN
    SELECT role INTO user_role_val FROM public.users WHERE id = auth.uid() AND company_id = p_company_id;
    RETURN user_role_val IN ('Owner', 'Admin');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.is_company_member(p_company_id uuid)
RETURNS boolean AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.users WHERE id = auth.uid() AND company_id = p_company_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Function to handle new user signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
  v_company_id uuid;
  v_role public.user_role;
BEGIN
  -- Create a new company for the user
  INSERT INTO public.companies (name)
  VALUES (new.raw_user_meta_data->>'company_name')
  RETURNING id INTO v_company_id;

  -- Set the user's role to 'Owner'
  v_role := 'Owner';

  -- Insert into our public users table
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (new.id, v_company_id, new.email, v_role);

  -- Update the user's app_metadata in auth.users
  PERFORM auth.admin_update_user_by_id(
    new.id,
    jsonb_build_object(
      'app_metadata', jsonb_build_object(
        'company_id', v_company_id,
        'role', v_role
      )
    )
  );

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger for new user signup
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- Function to record a sale and update inventory atomically
CREATE OR REPLACE FUNCTION public.record_sale_transaction(
    p_company_id uuid,
    p_user_id uuid,
    p_sale_items jsonb,
    p_customer_name text DEFAULT NULL,
    p_customer_email text DEFAULT NULL,
    p_payment_method text DEFAULT 'other',
    p_notes text DEFAULT NULL
) RETURNS public.sales
LANGUAGE plpgsql
AS $$
DECLARE
  new_sale public.sales;
  v_customer_id uuid;
  item_record record;
  v_total_amount bigint := 0;
  v_inventory_record public.inventory;
BEGIN
  -- Find or create customer
  IF p_customer_email IS NOT NULL THEN
    SELECT id INTO v_customer_id FROM public.customers WHERE email = p_customer_email AND company_id = p_company_id;
    IF v_customer_id IS NULL THEN
      INSERT INTO public.customers (company_id, customer_name, email)
      VALUES (p_company_id, COALESCE(p_customer_name, p_customer_email), p_customer_email)
      RETURNING id INTO v_customer_id;
    END IF;
  END IF;

  -- Calculate total amount
  FOR item_record IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(unit_price bigint, quantity int)
  LOOP
    v_total_amount := v_total_amount + (item_record.quantity * item_record.unit_price);
  END LOOP;

  -- Create the sale record
  INSERT INTO public.sales
    (company_id, sale_number, customer_id, total_amount, payment_method, notes, created_by)
  VALUES
    (p_company_id, 'SALE-' || substr(uuid_generate_v4()::text, 1, 8), v_customer_id, v_total_amount, p_payment_method, p_notes, p_user_id)
  RETURNING * INTO new_sale;

  -- Process sale items and update inventory
  FOR item_record IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(product_id uuid, quantity int, unit_price bigint)
  LOOP
    -- Lock inventory row for this item to prevent race conditions
    SELECT * INTO v_inventory_record FROM public.inventory 
    WHERE product_id = item_record.product_id AND company_id = p_company_id FOR UPDATE;

    IF v_inventory_record IS NULL THEN
        RAISE EXCEPTION 'Inventory item not found for product_id %', item_record.product_id;
    END IF;

    IF v_inventory_record.quantity < item_record.quantity THEN
      RAISE EXCEPTION 'Not enough stock for product_id %. Available: %, Requested: %', 
        item_record.product_id, v_inventory_record.quantity, item_record.quantity;
    END IF;

    -- Create sale item record
    INSERT INTO public.sale_items (sale_id, company_id, product_id, quantity, unit_price, cost_at_time)
    VALUES (new_sale.id, p_company_id, item_record.product_id, item_record.quantity, item_record.unit_price, v_inventory_record.cost);

    -- Update inventory quantity and last sold date
    UPDATE public.inventory
    SET 
      quantity = quantity - item_record.quantity,
      last_sold_date = CURRENT_DATE
    WHERE id = v_inventory_record.id;

    -- Create ledger entry
    INSERT INTO public.inventory_ledger (company_id, product_id, change_type, quantity_change, new_quantity, related_id, created_by)
    VALUES (p_company_id, item_record.product_id, 'sale', -item_record.quantity, v_inventory_record.quantity - item_record.quantity, new_sale.id, p_user_id);
  
  END LOOP;

  RETURN new_sale;
END;
$$;
